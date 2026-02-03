import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import '../../../domain/entities/node_info.dart';
import 'wifi_p2p/channels/discovery_channel.dart';
import 'wifi_p2p/channels/connection_channel.dart';
import 'wifi_p2p/channels/socket_channel.dart';

/// Flutter data source for Wi-Fi Direct communication via platform channels.
///
/// This class bridges the Flutter domain layer with the native Android
/// implementation via multiple Channels.
class WifiP2pSource {
  static const _generalChannel = MethodChannel('com.rescuenet/wifi_p2p');
  
  final _discoveryChannel = DiscoveryChannel();
  final _connectionChannel = ConnectionChannel();
  final _socketChannel = SocketChannel();
  
  final _wifiStateController = BehaviorSubject<bool>.seeded(false);
  final _discoveredNodesController = BehaviorSubject<List<NodeInfo>>.seeded([]);
  final _errorController = StreamController<String>.broadcast();
  
  // Cache of discovered nodes
  final Map<String, NodeInfo> _nodeCache = {};
  
  StreamSubscription? _discoverySubscription;
  StreamSubscription? _packetSubscription;
  Timer? _staleCleanupTimer;

  /// Stream of discovered nodes.
  Stream<List<NodeInfo>> get discoveredNodes => _discoveredNodesController.stream;

  /// Current list of discovered nodes.
  List<NodeInfo> get currentNodes => _nodeCache.values.toList();

  /// Stream of received packets.
  Stream<ReceivedPacket> get receivedPackets => _socketChannel.packetStream.map(
    (event) => ReceivedPacket(
      senderIp: event.senderIp,
      packetJson: event.packetJson,
      receivedAt: DateTime.now(),
    ),
  );

  /// Stream of Wi-Fi P2P enabled state.
  Stream<bool> get wifiP2pState => _wifiStateController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Initializes the Wi-Fi P2P system.
  Future<bool> initialize() async {
    try {
      final result = await _generalChannel.invokeMethod<Map>('initialize');
      final success = result?['success'] as bool? ?? false;
      
      if (success) {
        _startListeningToDiscovery();
        _startStaleCleanupTimer();
      }
      return success;
    } on PlatformException catch (e) {
      _emitError('Initialization failed: ${e.message}');
      throw WifiP2pException('Initialization failed: ${e.message}', e.code);
    }
  }

  void _startListeningToDiscovery() {
    _discoverySubscription = _discoveryChannel.neighborsStream.listen((nodes) {
      for (final node in nodes) {
        _nodeCache[node.id] = node;
      }
      _discoveredNodesController.add(_nodeCache.values.toList());
    });
  }

  void _startStaleCleanupTimer() {
    _staleCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      cleanStaleNodes();
    });
  }

  /// Checks permissions.
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

  /// Requests permissions.
  Future<bool> requestPermissions() async {
    try {
      final result = await _generalChannel.invokeMethod<Map>('requestPermissions');
      return result?['allGranted'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw WifiP2pException('Permission request failed: ${e.message}', e.code);
    }
  }
  
  /// Starts the Android Foreground Service.
  /// 
  /// Must be called only AFTER permissions are granted to avoid Android 14+ crash.
  Future<bool> startMeshService() async {
    try {
      final result = await _generalChannel.invokeMethod<bool>('startMeshService');
      return result ?? false;
    } on PlatformException catch (e) {
      // Log but don't rethrow, as service might already be running or not critical for basic UI
      return false;
    }
  }

  /// Starts broadcasting metadata via local service.
  Future<void> startBroadcasting({
    required String nodeId,
    required Map<String, String> metadata,
  }) async {
    try {
      // Ensure node ID is in metadata
      final fullMetadata = Map<String, String>.from(metadata);
      fullMetadata['id'] = nodeId;
      await _discoveryChannel.registerService(fullMetadata);
    } on PlatformException catch (e) {
      _emitError('Broadcasting failed: ${e.message}');
      throw WifiP2pException('Broadcasting failed: ${e.message}', e.code);
    }
  }

  /// Stops broadcasting metadata.
  Future<void> stopBroadcasting() async {
    try {
      await _discoveryChannel.unregisterService();
    } on PlatformException catch (e) {
      throw WifiP2pException('Stop broadcasting failed: ${e.message}', e.code);
    }
  }

  /// Starts discovery.
  Future<void> startDiscovery() async {
    try {
      _nodeCache.clear();
      _discoveredNodesController.add([]);
      await _discoveryChannel.startDiscovery();
    } on PlatformException catch (e) {
      _emitError('Discovery failed: ${e.message}');
      throw WifiP2pException('Discovery failed: ${e.message}', e.code);
    }
  }

  /// Refreshes discovery without clearing cache.
  Future<void> refreshDiscovery() async {
    try {
      await _discoveryChannel.refreshDiscovery();
    } catch (e) {
      // Ignore refresh errors
    }
  }

  /// Stops discovery.
  Future<void> stopDiscovery() async {
    try {
      await _discoveryChannel.stopDiscovery();
    } on PlatformException catch (e) {
      throw WifiP2pException('Stop discovery failed: ${e.message}', e.code);
    }
  }

  /// Starts server.
  Future<void> startServer() async {
    try {
      await _socketChannel.startListening();
    } on PlatformException catch (e) {
      throw WifiP2pException('Server start failed: ${e.message}', e.code);
    }
  }

  /// Stops server.
  Future<void> stopServer() async {
    try {
      await _socketChannel.stopListening();
    } on PlatformException catch (e) {
      throw WifiP2pException('Server stop failed: ${e.message}', e.code);
    }
  }

  /// Sends packet implementation.
  Future<TransmissionResult> sendPacket({
    required String targetIp,
    required String packetJson,
  }) async {
     try {
       final success = await _socketChannel.sendPacketJson(targetIp, packetJson);
       if (success) {
         return TransmissionResult.success(targetIp: targetIp);
       } else {
         return TransmissionResult.failure(targetIp: targetIp, error: 'Send failed', message: 'Unknown error');
       }
     } catch (e) {
       return TransmissionResult.failure(targetIp: targetIp, error: 'Error', message: e.toString());
     }
  }

  /// Connects to a device.
  Future<ConnectionInfo> connect(String deviceAddress) async {
      try {
        // Remove any existing group first
        await removeGroup();
        
        final result = await _connectionChannel.connect(deviceAddress);
        
        if (result != null && result['success'] == true) {
          return ConnectionInfo(
            success: true,
            groupOwnerAddress: result['groupOwnerAddress'] as String?,
            isGroupOwner: result['isGroupOwner'] as bool? ?? false,
          );
        }
        
        // Fallback to getting connection info
        final info = await _connectionChannel.getConnectionInfo();
        return ConnectionInfo(
          success: info != null && info['groupFormed'] == true,
          groupOwnerAddress: info?['groupOwnerAddress'] as String?,
          isGroupOwner: info?['isGroupOwner'] as bool? ?? false,
        );
      } catch (e) {
        return ConnectionInfo(success: false, error: e.toString());
      }
  }

  /// Gets group info including connected clients.
  Future<GroupInfo?> getGroupInfo() async {
    return _connectionChannel.getGroupInfo();
  }

  Future<void> removeGroup() => _connectionChannel.removeGroup();
  Future<void> disconnect() => _connectionChannel.disconnect();
  
  Future<void> cleanup() async {
    _staleCleanupTimer?.cancel();
    _discoverySubscription?.cancel();
    _discoveryChannel.dispose();
    _socketChannel.dispose();
    _connectionChannel.dispose();
    _discoveredNodesController.close();
    _wifiStateController.close();
    _errorController.close();
  }
  
  /// Remove stale nodes.
  void cleanStaleNodes() {
    final now = DateTime.now();
    _nodeCache.removeWhere((id, node) {
      return now.difference(node.lastSeen).inSeconds > 60;
    });
    _discoveredNodesController.add(_nodeCache.values.toList());
  }

  void _emitError(String message) {
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }

  /// Resolves a client's IP address from their MAC address using ARP table.
  /// 
  /// This is required when we are the Group Owner and need to send data
  /// to a specific client.
  Future<String?> resolveClientIp(String peerMacAddress) async {
    try {
      final file = File('/proc/net/arp');
      if (!await file.exists()) return null;

      final lines = await file.readAsLines();
      final normalizedMac = peerMacAddress.toLowerCase().replaceAll(':', '');

      for (final line in lines) {
        // Line format: IP address       HW type     Flags       HW address            Mask     Device
        // Example: 192.168.49.205   0x1         0x2         aa:bb:cc:dd:ee:ff     *        p2p-wlan0-0
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final ip = parts[0];
          final mac = parts[3].toLowerCase().replaceAll(':', '');

          if (mac == normalizedMac) {
            return ip;
          }
        }
      }
    } catch (e) {
      // Ignore reading errors
    }
    return null;
  }
}

/// Exception for Wi-Fi P2P errors.
class WifiP2pException implements Exception {
  final String message;
  final String? code;

  WifiP2pException(this.message, [this.code]);

  @override
  String toString() => 'WifiP2pException: $message${code != null ? ' ($code)' : ''}';
}

/// Permission status information.
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

/// Result of a packet transmission.
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

/// Wi-Fi Direct connection information.
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

/// A received packet from the mesh network.
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

/// Device information.
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
