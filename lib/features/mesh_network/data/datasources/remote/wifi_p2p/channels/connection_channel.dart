import 'dart:async';
import 'package:flutter/services.dart';

/// Channel for managing Wi-Fi P2P connections.
class ConnectionChannel {
  static const _channel = MethodChannel('com.rescuenet/wifi_p2p/connection');

  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();

  ConnectionState _currentState = ConnectionState.disconnected;

  /// Stream of connection state changes.
  Stream<ConnectionState> get stateStream => _stateController.stream;

  /// Current connection state.
  ConnectionState get currentState => _currentState;

  /// Connect to a device by MAC address.
  Future<Map<String, dynamic>?> connect(String deviceAddress) async {
    _updateState(ConnectionState.connecting);
    
    try {
      final result = await _channel.invokeMethod<Map>('connect', {
        'deviceAddress': deviceAddress,
      });
      
      if (result != null && result['success'] == true) {
        _updateState(ConnectionState.connected);
        return result.cast<String, dynamic>();
      } else {
        _updateState(ConnectionState.disconnected);
        return null;
      }
    } on PlatformException catch (e) {
      _updateState(ConnectionState.error);
      throw Exception('Connection failed: ${e.message}');
    }
  }

  /// Disconnect from current connection.
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      _updateState(ConnectionState.disconnected);
    } on PlatformException {
      // Already disconnected
      _updateState(ConnectionState.disconnected);
    }
  }

  /// Remove the current group.
  Future<void> removeGroup() async {
    try {
      await _channel.invokeMethod('removeGroup');
      _updateState(ConnectionState.disconnected);
    } on PlatformException {
      // Ignore - may not be in a group
    }
  }

  /// Get connection info.
  Future<Map<String, dynamic>?> getConnectionInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getConnectionInfo');
      return result?.cast<String, dynamic>();
    } on PlatformException {
      return null;
    }
  }

  /// Get group info including connected clients.
  Future<GroupInfo?> getGroupInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getGroupInfo');
      if (result == null || result['hasGroup'] != true) {
        return null;
      }
      
      final clientsList = result['clients'] as List? ?? [];
      final clients = clientsList.map((c) {
        final clientMap = c as Map;
        return PeerInfo(
          deviceName: clientMap['deviceName'] as String? ?? 'Unknown',
          deviceAddress: clientMap['deviceAddress'] as String? ?? '',
        );
      }).toList();
      
      return GroupInfo(
        networkName: result['networkName'] as String? ?? '',
        isGroupOwner: result['isGroupOwner'] as bool? ?? false,
        ownerAddress: result['ownerAddress'] as String? ?? '',
        ownerName: result['ownerName'] as String? ?? '',
        clients: clients,
      );
    } on PlatformException {
      return null;
    }
  }

  void _updateState(ConnectionState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Dispose resources.
  void dispose() {
    _stateController.close();
  }
}

/// Connection states.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

extension ConnectionStateExtension on ConnectionState {
  bool get isConnected => this == ConnectionState.connected;
  bool get isConnecting => this == ConnectionState.connecting;
}

/// Group information including connected peers.
class GroupInfo {
  final String networkName;
  final bool isGroupOwner;
  final String ownerAddress;
  final String ownerName;
  final List<PeerInfo> clients;

  GroupInfo({
    required this.networkName,
    required this.isGroupOwner,
    required this.ownerAddress,
    required this.ownerName,
    required this.clients,
  });
}

/// Peer information.
class PeerInfo {
  final String deviceName;
  final String deviceAddress;

  PeerInfo({
    required this.deviceName,
    required this.deviceAddress,
  });
}
