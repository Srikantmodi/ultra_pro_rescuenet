import 'package:flutter/services.dart';

/// Manages DNS-SD service registration.
class ServiceManager {
  static const _channel = MethodChannel('com.rescuenet/wifi_p2p/service');

  bool _isRegistered = false;
  Map<String, String> _currentMetadata = {};

  /// Whether the service is registered.
  bool get isRegistered => _isRegistered;

  /// Current service metadata.
  Map<String, String> get currentMetadata => Map.unmodifiable(_currentMetadata);

  /// Register the local service.
  Future<bool> registerService(Map<String, String> metadata) async {
    try {
      final result = await _channel.invokeMethod<bool>('register', metadata);
      if (result == true) {
        _isRegistered = true;
        _currentMetadata = Map.from(metadata);
      }
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Update service metadata.
  Future<bool> updateMetadata(Map<String, String> metadata) async {
    if (!_isRegistered) {
      return registerService(metadata);
    }

    try {
      final result = await _channel.invokeMethod<bool>('update', metadata);
      if (result == true) {
        _currentMetadata = Map.from(metadata);
      }
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Unregister the service.
  Future<void> unregisterService() async {
    try {
      await _channel.invokeMethod('unregister');
      _isRegistered = false;
      _currentMetadata = {};
    } on PlatformException {
      // Already unregistered
    }
  }

  /// Clear and re-register service (DNS-SD refresh hack).
  Future<bool> refreshService() async {
    if (!_isRegistered) return false;

    final savedMetadata = Map<String, String>.from(_currentMetadata);
    await unregisterService();
    await Future.delayed(const Duration(milliseconds: 500));
    return registerService(savedMetadata);
  }
}
