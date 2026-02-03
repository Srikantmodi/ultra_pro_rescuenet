import 'dart:async';
import 'package:flutter/services.dart';
import '../../../../../domain/entities/mesh_packet.dart';
import '../../../../models/mesh_packet_model.dart';

/// Channel for socket-based packet transmission.
class SocketChannel {
  static const _methodChannel = MethodChannel('com.rescuenet/wifi_p2p/socket');
  static const _eventChannel = EventChannel('com.rescuenet/wifi_p2p/packets');

  final StreamController<SocketPacketEvent> _packetController =
      StreamController<SocketPacketEvent>.broadcast();

  StreamSubscription? _subscription;
  bool _isListening = false;

  /// Stream of received packets.
  Stream<SocketPacketEvent> get packetStream => _packetController.stream;

  /// Whether listening for packets.
  bool get isListening => _isListening;

  /// Start listening for incoming packets.
  Future<void> startListening() async {
    if (_isListening) return;

    await _methodChannel.invokeMethod('startServer');
    _subscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_handlePacketEvent, onError: _handleError);
    _isListening = true;
  }

  /// Stop listening for packets.
  Future<void> stopListening() async {
    if (!_isListening) return;

    await _methodChannel.invokeMethod('stopServer');
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }

  /// Send a packet to a target address.
  Future<bool> sendPacket(String targetAddress, MeshPacket packet) async {
    try {
      final jsonString = MeshPacketModel.entityToJsonString(packet);
      return await sendPacketJson(targetAddress, jsonString);
    } on PlatformException {
      return false;
    }
  }

  /// Send raw packet JSON.
  Future<bool> sendPacketJson(String targetAddress, String jsonString) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('sendPacket', {
        'targetAddress': targetAddress,
        'packetJson': jsonString,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  void _handlePacketEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      if (type == 'packetReceived') {
        final json = event['packet'] as String?;
        final senderIp = event['senderIp'] as String? ?? '0.0.0.0';
        if (json != null) {
          _packetController.add(SocketPacketEvent(
            senderIp: senderIp,
            packetJson: json,
          ));
        }
      }
    }
  }

  void _handleError(Object error) {
    // Log but don't crash
  }

  /// Dispose resources.
  void dispose() {
    _subscription?.cancel();
    _packetController.close();
  }
}

class SocketPacketEvent {
  final String senderIp;
  final String packetJson;

  SocketPacketEvent({
    required this.senderIp,
    required this.packetJson,
  });
}
