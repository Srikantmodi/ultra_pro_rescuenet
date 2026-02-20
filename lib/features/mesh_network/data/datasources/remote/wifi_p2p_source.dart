import 'dart:async';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import '../../../domain/entities/node_info.dart';

/// Unified Wi-Fi P2P data source bridging the Flutter domain layer with the
/// native Android implementation.
///
/// Uses two platform channels:
///   - `com.rescuenet/wifi_p2p` (GeneralHandler): permissions, init, service lifecycle
///   - `com.rescuenet/wifi_p2p/discovery` (WifiP2pHandler): mesh node operations
///
/// And one event channel:
///   - `com.rescuenet/wifi_p2p/discovery_events`: servicesFound, packetReceived
class WifiP2pSource {
  // ── Platform Channels ──────────────────────────────────────────────
  /// General channel → GeneralHandler (permissions, init, foreground service)
  static const _generalChannel = MethodChannel('com.rescuenet/wifi_p2p');

  /// Discovery channel → WifiP2pHandler (mesh node ops, connectAndSend)
  static const _discoveryChannel = MethodChannel('com.rescuenet/wifi_p2p/discovery');

  /// Event channel → WifiP2pHandler emits servicesFound / packetReceived
  static const _eventChannel = EventChannel('com.rescuenet/wifi_p2p/discovery_events');

  // ── State ──────────────────────────────────────────────────────────
  final _wifiStateController = BehaviorSubject<bool>.seeded(false);
  final _discoveredNodesController = BehaviorSubject<List<NodeInfo>>.seeded([]);
  final _receivedPacketsController = StreamController<ReceivedPacket>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  final Map<String, NodeInfo> _nodeCache = {};

  StreamSubscription? _eventSubscription;
  Timer? _staleCleanupTimer;
  bool _isInitialized = false;

  // ═══════════════════════════════════════════════════════════════════
  // PUBLIC STREAMS
  // ═══════════════════════════════════════════════════════════════════

  Stream<List<NodeInfo>> get discoveredNodes => _discoveredNodesController.stream;
  List<NodeInfo> get currentNodes => _nodeCache.values.toList();
  Stream<ReceivedPacket> get receivedPackets => _receivedPacketsController.stream;
  Stream<bool> get wifiP2pState => _wifiStateController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // ═══════════════════════════════════════════════════════════════════
  // INITIALIZATION  (GeneralHandler → com.rescuenet/wifi_p2p)
  // ═══════════════════════════════════════════════════════════════════

  /// Initializes the Wi-Fi P2P system and starts listening for native events.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final result = await _generalChannel.invokeMethod<Map>('initialize');
      final success = result?['success'] as bool? ?? false;

      if (success) {
        _startEventListener();
        _startStaleCleanupTimer();
        _isInitialized = true;
        print('✅ WifiP2pSource initialized');
      }
      return success;
    } on PlatformException catch (e) {
      _emitError('Initialization failed: ${e.message}');
      throw WifiP2pException('Initialization failed: ${e.message}', e.code);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // PERMISSIONS  (GeneralHandler)
  // ═══════════════════════════════════════════════════════════════════

  Future<PermissionStatus> checkPermissions() async {
    try {
      final result = await _generalChannel.invokeMethod<Map>('checkPermissions');
      return PermissionStatus(
        allGranted: result?['allGranted'] as bool? ?? false,
        hasWifiDirect: result?['hasWifiDirect'] as bool? ?? false,
        missing: List<String>.from(result?['missing'] ?? []),
        androidVersion: result?['androidVersion'] as int? ?? 0,
      );
    } on PlatformException catch (e) {
      throw WifiP2pException('Permission check failed: ${e.message}', e.code);
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final result = await _generalChannel.invokeMethod<Map>('requestPermissions');
      return result?['allGranted'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw WifiP2pException('Permission request failed: ${e.message}', e.code);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // FOREGROUND SERVICE  (GeneralHandler)
  // ═══════════════════════════════════════════════════════════════════

  Future<bool> startMeshService() async {
    try {
      final result = await _generalChannel.invokeMethod<bool>('startMeshService');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopMeshService() async {
    try {
      final result = await _generalChannel.invokeMethod<bool>('stopMeshService');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // MESH NODE OPERATIONS  (WifiP2pHandler → com.rescuenet/wifi_p2p/discovery)
  // ═══════════════════════════════════════════════════════════════════

  /// Starts the mesh node in dual-mode (advertising + discovery + server).
  ///
  /// This replaces the old separate startBroadcasting / startDiscovery / startServer
  /// calls. The native WifiP2pHandler registers the DNS-SD service, starts
  /// peer+service discovery, and starts periodic refresh timers — all in one call.
  Future<bool> startMeshNode({
    required String nodeId,
    required Map<String, String> metadata,
  }) async {
    try {
      print('═══════════════════════════════════');
      print('STARTING MESH NODE (DUAL MODE)');
      print('   Node ID: $nodeId');
      print('   Metadata: $metadata');
      print('═══════════════════════════════════');

      _nodeCache.clear();
      _discoveredNodesController.add([]);

      // Native expects the metadata map directly as `call.arguments`
      final fullMetadata = Map<String, String>.from(metadata);
      fullMetadata['id'] = nodeId;

      final result = await _discoveryChannel.invokeMethod<bool>('startMeshNode', fullMetadata);

      if (result == true) {
        print('✅ Mesh node started successfully');
        return true;
      } else {
        print('❌ Mesh node start failed');
        _emitError('Mesh node start failed');
        return false;
      }
    } on PlatformException catch (e) {
      print('❌ Start mesh node exception: ${e.message}');
      _emitError('Start mesh node failed: ${e.message}');
      return false;
    }
  }

  /// Updates node metadata without restarting the mesh node.
  /// Maps to native `updateMetadata`.
  Future<bool> updateMetadata(Map<String, String> metadata) async {
    try {
      final result = await _discoveryChannel.invokeMethod<bool>('updateMetadata', metadata);
      return result == true;
    } on PlatformException catch (e) {
      print('❌ Update metadata error: ${e.message}');
      return false;
    }
  }

  /// Stops the mesh node (stops advertising, discovery, and server timers).
  Future<bool> stopMeshNode() async {
    try {
      final result = await _discoveryChannel.invokeMethod<bool>('stopMeshNode');
      if (result == true) {
        _nodeCache.clear();
        _discoveredNodesController.add([]);
        print('✅ Mesh node stopped');
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      print('❌ Stop mesh node error: ${e.message}');
      return false;
    }
  }

  /// Gets diagnostic information from the native layer.
  Future<Map<String, dynamic>> getDiagnostics() async {
    try {
      final result = await _discoveryChannel.invokeMethod<Map>('getDiagnostics');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      print('❌ Get diagnostics error: ${e.message}');
      return {};
    }
  }

  /// FIX B-7: Gets real Wi-Fi RSSI from native layer.
  /// Returns signal strength in dBm (e.g. -45), or -70 as fallback.
  Future<int> getSignalStrength() async {
    try {
      final result = await _discoveryChannel.invokeMethod<int>('getSignalStrength');
      return result ?? -70;
    } on PlatformException catch (e) {
      print('⚠️ getSignalStrength error: ${e.message}');
      return -70;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // BACKWARD-COMPAT WRAPPERS
  //
  // These are kept so that callers (MeshRepositoryImpl, DiscoveryBloc) that
  // still reference the old API names don't break. They are now no-ops or
  // thin wrappers over the unified API.
  // ═══════════════════════════════════════════════════════════════════

  /// Start broadcasting — now maps to updateMetadata (the mesh node must
  /// already be started via startMeshNode).
  Future<void> startBroadcasting({
    required String nodeId,
    required Map<String, String> metadata,
  }) async {
    final fullMetadata = Map<String, String>.from(metadata);
    fullMetadata['id'] = nodeId;
    await updateMetadata(fullMetadata);
  }

  /// No-op. Discovery is auto-managed by the native mesh node.
  Future<void> startDiscovery() async {
    // Discovery is automatically managed by startMeshNode.
    // Kept for backward compatibility with DiscoveryBloc.
    print('ℹ️  startDiscovery() is now a no-op — managed by startMeshNode');
  }

  /// No-op. Discovery is auto-managed by the native mesh node.
  Future<void> stopDiscovery() async {
    print('ℹ️  stopDiscovery() is now a no-op — managed by stopMeshNode');
  }

  /// No-op. Server is auto-started by WifiP2pHandler.setup().
  Future<void> startServer() async {
    print('ℹ️  startServer() is now a no-op — auto-started by native');
  }

  /// No-op. Server lifecycle is managed by native cleanup.
  Future<void> stopServer() async {
    print('ℹ️  stopServer() is now a no-op — managed by native cleanup');
  }

  /// No-op. Broadcasting is managed by stopMeshNode now.
  Future<void> stopBroadcasting() async {
    print('ℹ️  stopBroadcasting() is now a no-op — managed by stopMeshNode');
  }

  /// No-op. Refresh is handled by native periodic timers.
  Future<void> refreshDiscovery() async {
    print('ℹ️  refreshDiscovery() is now a no-op — native handles periodic refresh');
  }

  // ═══════════════════════════════════════════════════════════════════
  // PACKET TRANSMISSION  (WifiP2pHandler → connectAndSend)
  // ═══════════════════════════════════════════════════════════════════

  /// Connects to a target device, sends a packet, waits for ACK, disconnects.
  ///
  /// This is the **only** way to transmit data. The native layer handles
  /// the full connect → send → ACK → disconnect lifecycle ("hit-and-run").
  Future<TransmissionResult> connectAndSendPacket({
    required String deviceAddress,
    required String packetJson,
  }) async {
    try {
      print('═══════════════════════════════════');
      print('CONNECT AND SEND PACKET');
      print('   Target: $deviceAddress');
      print('   Packet size: ${packetJson.length} bytes');
      print('═══════════════════════════════════');

      final result = await _discoveryChannel.invokeMethod<bool>('connectAndSend', {
        'deviceAddress': deviceAddress,
        'packet': packetJson,
      });

      if (result == true) {
        print('✅ Packet sent successfully');
        return TransmissionResult.success(targetIp: deviceAddress);
      } else {
        print('❌ Send failed');
        return TransmissionResult.failure(
          targetIp: deviceAddress,
          error: 'SEND_FAILED',
          message: 'Native returned false',
        );
      }
    } on PlatformException catch (e) {
      print('❌ Connect and send exception: ${e.message}');
      return TransmissionResult.failure(
        targetIp: deviceAddress,
        error: e.code,
        message: e.message ?? 'Unknown error',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // EVENT LISTENER  (EventChannel → discovery_events)
  // ═══════════════════════════════════════════════════════════════════

  void _startEventListener() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;

        final eventMap = Map<String, dynamic>.from(event);
        final type = eventMap['type'] as String?;

        switch (type) {
          case 'servicesFound':
            _handleServicesFound(eventMap);
            break;
          case 'packetReceived':
            _handlePacketReceived(eventMap);
            break;
          default:
            print('⚠️ Unknown event type: $type');
        }
      },
      onError: (error) {
        print('❌ Event stream error: $error');
        _emitError('Event stream error: $error');
      },
    );
  }

  void _handleServicesFound(Map<String, dynamic> event) {
    try {
      final services = event['services'] as List?;
      if (services == null || services.isEmpty) return;

      for (final service in services) {
        if (service is! Map) continue;

        final svcMap = Map<String, dynamic>.from(service);
        final nodeId = svcMap['id'] as String? ?? svcMap['nodeId'] as String?;
        final deviceAddress = svcMap['deviceAddress'] as String? ?? '';

        if (nodeId == null || deviceAddress.isEmpty) continue;

        // Build NodeInfo using the TXT record fields when available,
        // falling back to defaults for the serviceCallback (no TXT data).
        final hasTxtData = svcMap.containsKey('bat');

        final node = NodeInfo(
          id: nodeId,
          deviceAddress: deviceAddress,
          displayName: svcMap['deviceName'] as String? ?? 'Unknown',
          batteryLevel: int.tryParse(svcMap['bat']?.toString() ?? '0') ?? 0,
          hasInternet: svcMap['net'] == '1',
          latitude: double.tryParse(svcMap['lat']?.toString() ?? '0') ?? 0.0,
          longitude: double.tryParse(svcMap['lng']?.toString() ?? '0') ?? 0.0,
          lastSeen: DateTime.now(),
          signalStrength: int.tryParse(svcMap['sig']?.toString() ?? '-70') ?? -70,
          triageLevel: _mapTriageLevel(svcMap['tri']?.toString()),
          role: _mapRole(svcMap['rol']?.toString()),
          isAvailableForRelay: svcMap['rel'] != '0',
        );

        _nodeCache[node.id] = node;
        print('✅ Node discovered: ${node.id} (${node.deviceAddress}) [${hasTxtData ? "TXT" : "service"}]');
      }

      _discoveredNodesController.add(_nodeCache.values.toList());
    } catch (e) {
      print('❌ Error handling servicesFound: $e');
    }
  }

  void _handlePacketReceived(Map<String, dynamic> event) {
    try {
      final data = event['data'] as String?;
      if (data == null) return;

      print('📦 PACKET RECEIVED (${data.length} bytes)');

      _receivedPacketsController.add(ReceivedPacket(
        senderIp: 'p2p',
        packetJson: data,
        receivedAt: DateTime.now(),
      ));
    } catch (e) {
      print('❌ Error handling packetReceived: $e');
    }
  }

  static String _mapTriageLevel(String? code) {
    if (code == null) return NodeInfo.triageNone;
    const map = {'n': NodeInfo.triageNone, 'g': NodeInfo.triageGreen, 'y': NodeInfo.triageYellow, 'r': NodeInfo.triageRed};
    return map[code] ?? NodeInfo.triageNone;
  }

  static String _mapRole(String? code) {
    if (code == null) return NodeInfo.roleIdle;
    const map = {'s': NodeInfo.roleSender, 'r': NodeInfo.roleRelay, 'g': NodeInfo.roleGoal, 'i': NodeInfo.roleIdle};
    return map[code] ?? NodeInfo.roleIdle;
  }

  // ═══════════════════════════════════════════════════════════════════
  // STALE NODE CLEANUP
  // ═══════════════════════════════════════════════════════════════════

  void _startStaleCleanupTimer() {
    _staleCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      cleanStaleNodes();
    });
  }

  void cleanStaleNodes() {
    final before = _nodeCache.length;
    final now = DateTime.now();
    // FIX B-5: Aligned to 120s to match NodeInfo.staleTimeoutMinutes = 2
    // Previous 60s was too aggressive — nodes were evicted between discovery refresh cycles
    _nodeCache.removeWhere((id, node) => now.difference(node.lastSeen).inSeconds > 120);
    if (_nodeCache.length != before) {
      print('🧹 Cleaned ${before - _nodeCache.length} stale nodes');
      _discoveredNodesController.add(_nodeCache.values.toList());
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════

  Future<void> cleanup() async {
    _staleCleanupTimer?.cancel();
    _eventSubscription?.cancel();
    await _discoveredNodesController.close();
    await _receivedPacketsController.close();
    await _wifiStateController.close();
    await _errorController.close();
    _isInitialized = false;
    print('✅ WifiP2pSource cleanup complete');
  }

  void _emitError(String message) {
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════

class WifiP2pException implements Exception {
  final String message;
  final String? code;

  WifiP2pException(this.message, [this.code]);

  @override
  String toString() => 'WifiP2pException: $message${code != null ? ' ($code)' : ''}';
}

class PermissionStatus {
  final bool allGranted;
  final bool hasWifiDirect;
  final List<String> missing;
  final int androidVersion;

  PermissionStatus({
    required this.allGranted,
    required this.hasWifiDirect,
    required this.missing,
    required this.androidVersion,
  });
}

class TransmissionResult {
  final bool success;
  final String targetIp;
  final String? error;
  final String? message;

  TransmissionResult._({
    required this.success,
    required this.targetIp,
    this.error,
    this.message,
  });

  factory TransmissionResult.success({required String targetIp}) {
    return TransmissionResult._(success: true, targetIp: targetIp);
  }

  factory TransmissionResult.failure({
    required String targetIp,
    required String error,
    required String message,
  }) {
    return TransmissionResult._(
      success: false,
      targetIp: targetIp,
      error: error,
      message: message,
    );
  }
}

class ConnectionInfo {
  final bool success;
  final String? groupOwnerAddress;
  final bool isGroupOwner;
  final String? error;

  ConnectionInfo({
    required this.success,
    this.groupOwnerAddress,
    this.isGroupOwner = false,
    this.error,
  });
}

class ReceivedPacket {
  final String senderIp;
  final String packetJson;
  final DateTime receivedAt;

  ReceivedPacket({
    required this.senderIp,
    required this.packetJson,
    required this.receivedAt,
  });
}

class DeviceInfo {
  final String deviceName;
  final int androidVersion;
  final bool isP2pSupported;

  DeviceInfo({
    required this.deviceName,
    required this.androidVersion,
    required this.isP2pSupported,
  });
}
