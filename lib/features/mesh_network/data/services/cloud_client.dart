import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../datasources/local/hive/boxes/outbox_box.dart';
import '../../domain/entities/sos_payload.dart';
import '../../../../core/utils/logger.dart';

// ---------------------------------------------------------------------------
// CloudClient — Gateway-Node Cloud Upload Service
// ---------------------------------------------------------------------------
//
// PURPOSE:
//   When this device regains internet (becomes a "Gateway Node"), CloudClient
//   scans the local Hive OutboxBox for SOS packets that have NOT yet been
//   pushed to the AWS backend, transforms each into the required JSON schema,
//   and POSTs them one-by-one to the API Gateway endpoint.
//
// EXPECTED MeshPacket / MeshPacketModel FIELDS USED:
//   • id            — String, UUID, used as `packet_id` in the cloud payload
//   • originatorId  — String, device ID of the original sender
//   • payload       — String, JSON-encoded SosPayload containing:
//         senderName, latitude, longitude, emergencyType, triageLevel, ...
//   • trace         — List<String>, ordered MAC/node-IDs visited (packet_trace)
//   • packetType    — String, must be 'sos' for cloud upload eligibility
//   • priority      — int, 3 = critical (SOS)
//   • timestamp     — int, unix milliseconds
//
// CLOUD JSON SCHEMA (exact POST body):
//   {
//     "packet_id":      "String (Unique ID)",
//     "victim_name":    "String",
//     "gps_lat":        double,
//     "gps_long":       double,
//     "severity":       "String (e.g., 'CRITICAL', 'HIGH')",
//     "emergency_type": "String (e.g., 'Medical', 'Fire')",
//     "packet_trace":   ["List of Strings (MAC addresses)"]
//   }
//
// UPLOAD TRACKING:
//   A lightweight Hive box ('cloud_upload_ledger') stores the Set of packet
//   IDs that have been successfully uploaded. This is separate from the
//   OutboxBox's mesh-delivery status so the two concerns don't couple.
//
// ERROR STRATEGY:
//   • 200 OK        → mark uploaded, move to next packet
//   • 4xx           → log & skip (malformed data — won't fix itself on retry)
//   • 5xx / timeout → log & leave in queue for the next cycle
//   • Network loss during batch → abort remaining, retry next cycle
// ---------------------------------------------------------------------------

class CloudClient {
  // ── Configuration ────────────────────────────────────────────────────────

  /// AWS API Gateway endpoint.
  /// Replace with the real URL once the serverless backend is deployed.
  static const String _defaultApiUrl =
      'https://m53u0qspv6.execute-api.ap-south-1.amazonaws.com/prod';

  /// HTTP timeout per request. Generous to survive spotty first-reconnects.
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// Minimum pause between consecutive uploads to avoid hammering the backend.
  static const Duration _interUploadDelay = Duration(milliseconds: 500);

  /// Name of the Hive box that records successfully-uploaded packet IDs.
  static const String _ledgerBoxName = 'cloud_upload_ledger';

  // ── Dependencies ─────────────────────────────────────────────────────────

  /// HTTP client — injectable for testing.
  final http.Client _httpClient;

  /// The local outbox containing queued SOS packets.
  final OutboxBox _outbox;

  /// connectivity_plus instance — injectable for testing.
  final Connectivity _connectivity;

  /// The API Gateway URL to POST to.
  final String _apiUrl;

  /// Logger scoped to this service.
  static const _log = Logger('CloudClient');

  // ── Internal State ───────────────────────────────────────────────────────

  /// Hive box that stores uploaded packet IDs (Set<String>).
  Box<String>? _ledgerBox;

  /// Guard flag to prevent concurrent upload cycles.
  bool _isSyncing = false;

  /// Stream subscription listening for connectivity changes.
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  // ── Constructor ──────────────────────────────────────────────────────────

  /// Creates a [CloudClient].
  ///
  /// All dependencies can be injected for testing:
  /// - [outbox]       : the Hive outbox box managing queued packets
  /// - [httpClient]   : defaults to a new [http.Client]
  /// - [connectivity] : defaults to a new [Connectivity] instance
  /// - [apiUrl]       : defaults to [_defaultApiUrl]
  CloudClient({
    required OutboxBox outbox,
    http.Client? httpClient,
    Connectivity? connectivity,
    String? apiUrl,
  })  : _outbox = outbox,
        _httpClient = httpClient ?? http.Client(),
        _connectivity = connectivity ?? Connectivity(),
        _apiUrl = apiUrl ?? _defaultApiUrl;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Initializes the cloud upload ledger and starts listening for
  /// connectivity changes.
  ///
  /// Call this once during app startup (after Hive is initialized).
  Future<void> init() async {
    // Open (or reuse) the ledger box that tracks uploaded packet IDs.
    if (_ledgerBox == null || !(_ledgerBox!.isOpen)) {
      _ledgerBox = await Hive.openBox<String>(_ledgerBoxName);
    }

    _log.i('Initialized — ${_ledgerBox!.length} packets already uploaded');

    // Listen to platform connectivity changes.
    // Every time the device gains a network interface, we attempt a sync.
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      (result) {
        _log.d('Connectivity changed: $result');
        if (_isConnectedResult(result)) {
          // Device just gained a network interface — trigger upload cycle.
          syncPendingPackets();
        }
      },
    );

    // Also attempt an immediate sync in case we already have internet.
    syncPendingPackets();
  }

  /// Releases resources. Call on app teardown.
  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _ledgerBox?.close();
    _ledgerBox = null;
    _httpClient.close();
    _log.i('Disposed');
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Triggers a full upload cycle: checks internet, fetches pending SOS
  /// packets from the outbox, and pushes each to the cloud backend.
  ///
  /// Safe to call multiple times — concurrent invocations are no-ops.
  /// Returns the number of packets successfully uploaded in this cycle.
  Future<int> syncPendingPackets() async {
    // ── Guard: prevent overlapping cycles ──
    if (_isSyncing) {
      _log.d('Sync already in progress — skipping');
      return 0;
    }
    _isSyncing = true;

    int uploadedCount = 0;

    try {
      // ─── STEP 1: Verify real internet connectivity ───────────────────
      final hasInternet = await _verifyInternetAccess();
      if (!hasInternet) {
        _log.d('No internet — aborting sync cycle');
        return 0;
      }

      _log.i('Internet confirmed — starting cloud upload cycle');

      // ─── STEP 2: Fetch pending SOS packets from Hive outbox ─────────
      final pendingPackets = _fetchPendingSosPackets();

      if (pendingPackets.isEmpty) {
        _log.d('No pending SOS packets to upload');
        return 0;
      }

      _log.i('Found ${pendingPackets.length} pending SOS packet(s)');

      // ─── STEP 3: Upload each packet sequentially ────────────────────
      for (final entry in pendingPackets) {
        // Re-check connectivity before each upload in case we lost it
        // mid-batch (e.g., user walked out of Wi-Fi range).
        final stillConnected = await _verifyInternetAccess();
        if (!stillConnected) {
          _log.w('Lost internet mid-batch — stopping. '
              'Uploaded $uploadedCount so far.');
          break;
        }

        final success = await _uploadSinglePacket(entry);
        if (success) {
          uploadedCount++;
        }

        // Small delay to avoid hammering the backend.
        await Future.delayed(_interUploadDelay);
      }

      _log.i('Upload cycle complete — '
          '$uploadedCount/${pendingPackets.length} packets uploaded');
    } catch (e, st) {
      _log.e('Unexpected error during sync cycle', e, st);
    } finally {
      _isSyncing = false;
    }

    return uploadedCount;
  }

  /// Returns `true` if a given packet has already been uploaded to the cloud.
  bool isUploaded(String packetId) {
    return _ledgerBox?.containsKey(packetId) ?? false;
  }

  /// Returns the total number of packets that have been uploaded.
  int get uploadedCount => _ledgerBox?.length ?? 0;

  // ── Private Helpers ──────────────────────────────────────────────────────

  /// Checks whether the device currently has real internet access.
  ///
  /// Uses a two-layer approach:
  ///   1. `connectivity_plus` to quickly check if ANY network interface is up
  ///   2. A lightweight HTTP HEAD to Google's 204 endpoint to confirm the
  ///      interface actually routes to the internet (avoids captive portals).
  Future<bool> _verifyInternetAccess() async {
    try {
      // Layer 1: Platform-level check (fast, but can lie about captive portals)
      final connectivityResult = await _connectivity.checkConnectivity();
      if (!_isConnectedResult(connectivityResult)) {
        return false;
      }

      // Layer 2: HTTP probe — authoritative proof of internet access.
      final response = await _httpClient
          .head(
            Uri.parse('http://connectivitycheck.gstatic.com/generate_204'),
          )
          .timeout(const Duration(seconds: 4));

      return response.statusCode == 204;
    } catch (_) {
      // Any exception (timeout, DNS failure, socket error) → no internet.
      return false;
    }
  }

  /// Returns `true` if the [ConnectivityResult] indicates a usable interface.
  bool _isConnectedResult(ConnectivityResult result) {
    return result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet;
  }

  /// Fetches all SOS-type packets from the outbox that have NOT yet been
  /// uploaded to the cloud.
  ///
  /// A packet is eligible for cloud upload if:
  ///   • It is an SOS packet (`packetType == 'sos'`)
  ///   • It has NOT been recorded in the cloud ledger (i.e., not yet uploaded)
  ///
  /// Note: We read ALL outbox entries (not just "pending") because a packet
  /// might already be marked "sent" via mesh relay but still needs cloud push.
  List<OutboxEntry> _fetchPendingSosPackets() {
    if (!_outbox.isInitialized) {
      _log.w('OutboxBox not initialized — cannot fetch packets');
      return [];
    }

    final allEntries = _outbox.getAllEntries();

    return allEntries.where((entry) {
      final packet = entry.packet;

      // Only upload SOS packets to the cloud.
      final isSos = packet.packetType == 'sos';

      // Skip packets we've already uploaded.
      final alreadyUploaded = isUploaded(packet.id);

      return isSos && !alreadyUploaded;
    }).toList();
  }

  /// Uploads a single SOS packet to the AWS backend.
  ///
  /// Returns `true` if the upload succeeded (HTTP 200) and the packet was
  /// recorded in the cloud ledger. Returns `false` on any failure.
  Future<bool> _uploadSinglePacket(OutboxEntry entry) async {
    final packet = entry.packet;

    try {
      // ─── Build the cloud JSON payload ───────────────────────────────
      final jsonBody = _buildCloudPayload(packet.id, packet.payload,
          packet.trace);

      if (jsonBody == null) {
        // Payload parsing failed — log and skip (won't fix itself on retry).
        _log.w('Skipping packet ${packet.id} — failed to parse SOS payload');
        return false;
      }

      _log.d('Uploading packet ${packet.id}...');

      // ─── HTTP POST to AWS API Gateway ───────────────────────────────
      final response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(jsonBody),
          )
          .timeout(_requestTimeout);

      // ─── Handle response ────────────────────────────────────────────
      if (response.statusCode == 200 || response.statusCode == 201) {
        // SUCCESS — record in ledger so we never re-upload this packet.
        await _markAsUploaded(packet.id);
        _log.i('☁️ UPLOADED packet ${packet.id} — '
            '${response.statusCode} OK');
        return true;
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        // CLIENT ERROR (4xx) — our payload is malformed; retrying won't help.
        _log.e('☁️ REJECTED packet ${packet.id} — '
            'HTTP ${response.statusCode}: ${response.body}');
        // Optionally mark as uploaded to stop retrying a permanently bad packet.
        // Uncomment the line below if you prefer to skip permanently:
        // await _markAsUploaded(packet.id);
        return false;
      } else {
        // SERVER ERROR (5xx) or unexpected status — leave in queue for retry.
        _log.e('☁️ SERVER ERROR for packet ${packet.id} — '
            'HTTP ${response.statusCode}: ${response.body}');
        return false;
      }
    } on TimeoutException {
      // Request timed out — leave in queue for the next retry cycle.
      _log.w('☁️ TIMEOUT uploading packet ${packet.id} — '
          'will retry next cycle');
      return false;
    } on http.ClientException catch (e) {
      // Network-level error (DNS, socket reset, etc.).
      _log.e('☁️ NETWORK ERROR uploading packet ${packet.id}', e);
      return false;
    } catch (e, st) {
      // Catch-all for truly unexpected errors.
      _log.e('☁️ UNEXPECTED ERROR uploading packet ${packet.id}', e, st);
      return false;
    }
  }

  /// Transforms the raw MeshPacket data into the exact JSON schema
  /// expected by the AWS API Gateway.
  ///
  /// Returns `null` if the SOS payload cannot be parsed (defensive).
  ///
  /// Input:
  ///   • [packetId]  — unique packet ID
  ///   • [rawPayload] — JSON string encoding of [SosPayload]
  ///   • [trace]      — list of node/MAC IDs the packet has traversed
  ///
  /// Output JSON:
  /// ```json
  /// {
  ///   "packet_id":      "<packetId>",
  ///   "victim_name":    "<senderName from SosPayload>",
  ///   "gps_lat":        <latitude>,
  ///   "gps_long":       <longitude>,
  ///   "severity":       "CRITICAL" | "HIGH" | "MEDIUM" | "LOW",
  ///   "emergency_type": "Medical" | "Fire" | ...,
  ///   "packet_trace":   ["nodeA", "nodeB", ...]
  /// }
  /// ```
  Map<String, dynamic>? _buildCloudPayload(
    String packetId,
    String rawPayload,
    List<String> trace,
  ) {
    try {
      // Parse the SOS payload embedded in the MeshPacket's `payload` field.
      final sos = SosPayload.fromJsonString(rawPayload);

      return {
        'packet_id': packetId,
        'victim_name': sos.senderName,
        'gps_lat': sos.latitude,
        'gps_long': sos.longitude,
        'severity': _mapTriageToSeverity(sos.triageLevel),
        'emergency_type': _mapEmergencyType(sos.emergencyType),
        'packet_trace': List<String>.from(trace),
      };
    } catch (e) {
      _log.e('Failed to parse SOS payload for packet $packetId', e);
      return null;
    }
  }

  /// Maps the app's [TriageLevel] enum to the severity string expected by
  /// the AWS backend.
  ///
  /// Mapping:
  ///   critical / red  → "CRITICAL"
  ///   high / yellow   → "HIGH"
  ///   medium          → "MEDIUM"
  ///   low / green     → "LOW"
  ///   none            → "UNKNOWN"
  String _mapTriageToSeverity(TriageLevel triage) {
    switch (triage) {
      case TriageLevel.critical:
      case TriageLevel.red:
        return 'CRITICAL';
      case TriageLevel.high:
      case TriageLevel.yellow:
        return 'HIGH';
      case TriageLevel.medium:
        return 'MEDIUM';
      case TriageLevel.low:
      case TriageLevel.green:
        return 'LOW';
      case TriageLevel.none:
        return 'UNKNOWN';
    }
  }

  /// Maps the app's [EmergencyType] enum to the human-readable string
  /// expected by the AWS backend.
  String _mapEmergencyType(EmergencyType type) {
    switch (type) {
      case EmergencyType.medical:
        return 'Medical';
      case EmergencyType.fire:
        return 'Fire';
      case EmergencyType.flood:
        return 'Flood';
      case EmergencyType.earthquake:
        return 'Earthquake';
      case EmergencyType.trapped:
        return 'Trapped';
      case EmergencyType.injury:
        return 'Injury';
      case EmergencyType.rescue:
        return 'Rescue';
      case EmergencyType.naturalDisaster:
        return 'Natural Disaster';
      case EmergencyType.security:
        return 'Security';
      case EmergencyType.general:
        return 'General';
      case EmergencyType.other:
        return 'Other';
    }
  }

  /// Records a packet ID in the cloud upload ledger (Hive box).
  ///
  /// Once written here, the packet will be skipped in all future sync cycles.
  Future<void> _markAsUploaded(String packetId) async {
    await _ledgerBox?.put(packetId, DateTime.now().toIso8601String());
  }
}
