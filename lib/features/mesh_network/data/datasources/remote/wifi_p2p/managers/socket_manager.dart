import 'package:flutter/services.dart';

/// Manages TCP socket operations for packet transmission.
class SocketManager {
  static const _channel = MethodChannel('com.rescuenet/wifi_p2p/socket');
  static const int _defaultPort = 8988;

  bool _isServerRunning = false;

  /// Whether the socket server is running.
  bool get isServerRunning => _isServerRunning;

  /// Start the socket server.
  Future<bool> startServer({int port = _defaultPort}) async {
    if (_isServerRunning) return true;

    try {
      final result = await _channel.invokeMethod<bool>('startServer', {
        'port': port,
      });
      _isServerRunning = result ?? false;
      return _isServerRunning;
    } on PlatformException {
      return false;
    }
  }

  /// Stop the socket server.
  Future<void> stopServer() async {
    if (!_isServerRunning) return;

    try {
      await _channel.invokeMethod('stopServer');
      _isServerRunning = false;
    } on PlatformException {
      // Already stopped
    }
  }

  /// Send data to a target.
  Future<SendResult> send({
    required String targetAddress,
    required String data,
    int port = _defaultPort,
    int timeoutMs = 5000,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('send', {
        'address': targetAddress,
        'port': port,
        'data': data,
        'timeout': timeoutMs,
      });

      return SendResult(
        success: result?['success'] as bool? ?? false,
        ackReceived: result?['ackReceived'] as bool? ?? false,
        durationMs: result?['durationMs'] as int? ?? 0,
        error: result?['error'] as String?,
      );
    } on PlatformException catch (e) {
      return SendResult(
        success: false,
        ackReceived: false,
        durationMs: 0,
        error: e.message,
      );
    }
  }
}

/// Result of a send operation.
class SendResult {
  final bool success;
  final bool ackReceived;
  final int durationMs;
  final String? error;

  const SendResult({
    required this.success,
    required this.ackReceived,
    required this.durationMs,
    this.error,
  });

  bool get isSuccess => success && ackReceived;
}
