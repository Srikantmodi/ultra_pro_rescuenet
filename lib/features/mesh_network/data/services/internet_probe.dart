import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rxdart/rxdart.dart';

/// Probes internet connectivity to determine if this node is a "Goal" node.
///
/// A "Goal" node has internet access and can deliver SOS packets to
/// emergency services or cloud backends.
///
/// **CRITICAL:** This probe determines whether an SOS packet terminates here
/// (Goal node) or continues through the mesh (Relay node). A false positive
/// means the packet dies at a node that can't deliver it — killing the mesh.
///
/// **How it works (FIX: Internet Probe False-Positive Elimination):**
/// 1. Uses ONLY HTTP-based checks (HTTP 204 / HTTP 200) to verify real internet
/// 2. DNS lookups and raw socket connections are REMOVED — they produce false
///    positives for IP literals and cached results
/// 3. Listens to `connectivity_plus` platform events for instant detection
///    of network interface changes (WiFi/mobile toggled)
/// 4. Every platform event triggers an immediate HTTP re-probe
/// 5. `markOffline()` allows external callers (e.g., failed cloud delivery)
///    to force an immediate reclassification
class InternetProbe {
  /// HTTP endpoints to probe for real connectivity.
  /// Each entry is [url, expectedStatusCode].
  /// These are lightweight connectivity-check endpoints operated by major providers.
  /// ONLY HTTP responses prove real internet access.
  static const List<List<dynamic>> _httpCheckEndpoints = [
    ['http://connectivitycheck.gstatic.com/generate_204', 204],   // Google
    ['http://www.msftconnecttest.com/connecttest.txt', 200],       // Microsoft
    ['http://connectivity-check.ubuntu.com/', 200],                // Ubuntu/Canonical
  ];

  /// How long to wait between probes when internet is detected.
  /// Shorter than before (was 60s) to detect drops faster.
  static const Duration _normalProbeInterval = Duration(seconds: 30);

  /// How long to wait between probes when no internet.
  /// 30s is sufficient — no need to hammer the network when offline.
  /// Previous 10s value caused excessive metadata churn that disrupted
  /// DNS-SD service registration on the native layer.
  static const Duration _offlineProbeInterval = Duration(seconds: 30);

  /// Timeout for each HTTP probe attempt.
  static const Duration _probeTimeout = Duration(seconds: 4);

  /// Cache duration for connectivity result.
  /// Shorter than before (was 30s) to reduce stale-state window.
  static const Duration _cacheDuration = Duration(seconds: 10);

  // State
  bool _hasInternet = false;
  DateTime? _lastProbeTime;
  Timer? _probeTimer;

  /// When non-null, a probe is in flight.  Concurrent callers await
  /// this completer instead of returning a stale cached value.
  Completer<bool>? _activeProbe;

  // Platform connectivity listener (connectivity_plus v5.x returns single ConnectivityResult)
  StreamSubscription<ConnectivityResult>? _platformConnectivitySub;

  // Stream controller
  final _connectivityController = BehaviorSubject<bool>.seeded(false);

  /// Stream of connectivity status changes.
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Current connectivity status.
  bool get hasInternet => _hasInternet;

  /// Whether the cached result is still valid.
  bool get _isCacheValid {
    if (_lastProbeTime == null) return false;
    return DateTime.now().difference(_lastProbeTime!) < _cacheDuration;
  }

  /// Starts periodic connectivity probing.
  void startProbing() {
    // Run immediately
    checkConnectivity();

    // Schedule periodic probes
    _scheduleNextProbe();

    // Listen to platform connectivity changes for instant detection
    // When user toggles WiFi/mobile data, Android fires this immediately
    _platformConnectivitySub?.cancel();
    _platformConnectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        print('🌐 InternetProbe: Platform connectivity changed: $results');
        // Force immediate re-probe — don't trust the platform event alone
        checkConnectivity(forceRefresh: true);
      },
    );
  }

  /// Stops periodic connectivity probing.
  void stopProbing() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _platformConnectivitySub?.cancel();
    _platformConnectivitySub = null;
  }

  /// Checks connectivity and returns the result.
  ///
  /// Uses cached result if still valid, unless forceRefresh is true.
  /// If a probe is already in flight, concurrent callers **await** the same
  /// result instead of returning a stale cached value.
  Future<bool> checkConnectivity({bool forceRefresh = false}) async {
    // Return cached result if valid and not forcing refresh
    if (!forceRefresh && _isCacheValid) {
      return _hasInternet;
    }

    // If a probe is already in flight, await its result — never return stale data.
    if (_activeProbe != null) {
      return _activeProbe!.future;
    }

    _activeProbe = Completer<bool>();
    try {
      final result = await _probeConnectivity();
      _updateConnectivity(result);
      _activeProbe!.complete(result);
      return result;
    } catch (e) {
      // On error, treat as offline and still complete the completer
      // so awaiting callers aren't stuck forever.
      _updateConnectivity(false);
      if (!_activeProbe!.isCompleted) {
        _activeProbe!.complete(false);
      }
      return false;
    } finally {
      _activeProbe = null;
    }
  }

  /// Performs the actual connectivity probe using ONLY HTTP checks.
  ///
  /// CRITICAL FIX: DNS lookups and raw socket connections are REMOVED.
  /// - `InternetAddress.lookup('8.8.8.8')` returns true for IP literals
  ///   without any network access — this was the root cause of the
  ///   permanent false-positive bug.
  /// - Only HTTP responses from known connectivity-check endpoints
  ///   can authoritatively confirm real internet access.
  Future<bool> _probeConnectivity() async {
    // Try all HTTP endpoints in parallel
    final results = await Future.wait(
      _httpCheckEndpoints.map((entry) => _tryHttpCheck(
        entry[0] as String,
        entry[1] as int,
      )),
    );

    // If ANY endpoint responds correctly, we have real internet
    final hasReal = results.any((result) => result);
    print('🌐 InternetProbe: HTTP probe result=$hasReal '
        '(${results.map((r) => r ? '✅' : '❌').join(', ')})');
    return hasReal;
  }

  /// Performs an HTTP GET/HEAD to a connectivity-check endpoint.
  ///
  /// Returns true ONLY if the server responds with the expected status code.
  /// This is the SOLE authority for internet connectivity.
  Future<bool> _tryHttpCheck(String url, int expectedStatus) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = _probeTimeout;
      final request = await client.getUrl(
        Uri.parse(url),
      ).timeout(_probeTimeout);
      final response = await request.close().timeout(_probeTimeout);
      // Drain the response body to free resources
      await response.drain<void>();
      return response.statusCode == expectedStatus;
    } catch (e) {
      return false;
    } finally {
      client?.close();
    }
  }

  /// Updates connectivity state and notifies listeners.
  ///
  /// ALWAYS updates `_lastProbeTime` (cache freshness).
  /// Only fires stream event on actual VALUE changes.
  void _updateConnectivity(bool hasInternet) {
    _lastProbeTime = DateTime.now();

    if (_hasInternet != hasInternet) {
      _hasInternet = hasInternet;
      _connectivityController.add(hasInternet);
      print('🌐 InternetProbe: Connectivity CHANGED → hasInternet=$hasInternet');
    }

    // ALWAYS reschedule the next probe regardless of state change.
    // _scheduleNextProbe() creates a single-shot Timer — if it was only
    // called on state changes, probing would stop permanently the moment
    // two consecutive probes return the same result (e.g. relay node stays
    // offline).  That node would then NEVER discover it gained internet.
    _scheduleNextProbe();
  }

  /// Force-mark as offline (e.g., when cloud delivery fails despite probe
  /// saying online). This triggers an immediate re-probe on the next cycle.
  ///
  /// Use this when an actual network operation fails, proving the probe
  /// result was stale or wrong.
  void markOffline() {
    if (_hasInternet) {
      print('🌐 InternetProbe: Forced OFFLINE by external caller');
      _hasInternet = false;
      _connectivityController.add(false);
      _lastProbeTime = null; // Invalidate cache so next check re-probes
      _scheduleNextProbe(); // Switch to faster offline polling interval
    }
  }

  /// Schedules the next connectivity probe.
  void _scheduleNextProbe() {
    _probeTimer?.cancel();

    final interval = _hasInternet
        ? _normalProbeInterval
        : _offlineProbeInterval;

    _probeTimer = Timer(interval, () {
      checkConnectivity(forceRefresh: true);
    });
  }

  /// Gets a summary of the current connectivity status.
  ConnectivityStatus getStatus() {
    return ConnectivityStatus(
      hasInternet: _hasInternet,
      lastCheck: _lastProbeTime,
      isProbing: _probeTimer != null,
    );
  }

  /// Disposes of resources.
  void dispose() {
    stopProbing();
    _connectivityController.close();
  }
}

/// Current connectivity status.
class ConnectivityStatus {
  final bool hasInternet;
  final DateTime? lastCheck;
  final bool isProbing;

  const ConnectivityStatus({
    required this.hasInternet,
    this.lastCheck,
    required this.isProbing,
  });

  /// How long ago the last check was performed.
  Duration? get timeSinceLastCheck {
    if (lastCheck == null) return null;
    return DateTime.now().difference(lastCheck!);
  }

  /// Human-readable status string.
  String get statusText {
    if (!isProbing) return 'Not monitoring';
    if (hasInternet) return 'Connected';
    return 'No internet';
  }

  @override
  String toString() {
    return 'ConnectivityStatus($statusText, '
        'lastCheck: ${timeSinceLastCheck?.inSeconds ?? "never"}s ago)';
  }
}

/// Extension to integrate with mesh network.
extension InternetProbeExtension on InternetProbe {
  /// Determines the node role based on connectivity.
  ///
  /// Returns 'goal' if has internet, 'relay' otherwise.
  String getNodeRole() {
    return hasInternet ? 'goal' : 'relay';
  }

  /// Gets the internet score for AI routing.
  ///
  /// Returns 50 if has internet (the full weight), 0 otherwise.
  int getInternetScore() {
    return hasInternet ? 50 : 0;
  }
}
