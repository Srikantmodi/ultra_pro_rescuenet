import 'dart:async';
import 'package:flutter/services.dart';
import '../../../../../domain/entities/node_info.dart';

/// Channel for service discovery operations.
class DiscoveryChannel {
  static const _methodChannel = MethodChannel('com.rescuenet/wifi_p2p/discovery');
  static const _eventChannel = EventChannel('com.rescuenet/wifi_p2p/discovery_events');

  final StreamController<List<NodeInfo>> _neighborsController =
      StreamController<List<NodeInfo>>.broadcast();

  StreamSubscription? _subscription;
  bool _isDiscovering = false;
  Timer? _refreshTimer;

  /// Stream of discovered neighbors.
  Stream<List<NodeInfo>> get neighborsStream => _neighborsController.stream;

  /// Whether discovery is active.
  bool get isDiscovering => _isDiscovering;

  /// Start discovering services.
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      // Already discovering, just refresh
      await refreshDiscovery();
      return;
    }

    try {
      await _methodChannel.invokeMethod('startDiscovery');
      _subscription = _eventChannel
          .receiveBroadcastStream()
          .listen(_handleDiscoveryEvent, onError: _handleError);
      _isDiscovering = true;
      
      // Start periodic refresh timer
      _startRefreshTimer();
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// Stop discovering services.
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;

    _stopRefreshTimer();
    
    try {
      await _methodChannel.invokeMethod('stopDiscovery');
    } catch (e) {
      // Ignore stop errors
    }
    
    _subscription?.cancel();
    _subscription = null;
    _isDiscovering = false;
  }

  /// Refresh discovery without full restart.
  Future<void> refreshDiscovery() async {
    if (!_isDiscovering) return;
    
    try {
      await _methodChannel.invokeMethod('refreshDiscovery');
    } catch (e) {
      // If refresh fails, try full restart
      _isDiscovering = false;
      await startDiscovery();
    }
  }

  /// Register local service.
  Future<void> registerService(Map<String, String> metadata) async {
    try {
      await _methodChannel.invokeMethod('registerService', metadata);
    } on PlatformException catch (e) {
      // Re-throw with more context
      throw PlatformException(
        code: e.code,
        message: 'Service registration failed: ${e.message}',
        details: e.details,
      );
    }
  }

  /// Unregister local service.
  Future<void> unregisterService() async {
    _stopRefreshTimer();
    await _methodChannel.invokeMethod('unregisterService');
  }

  void _startRefreshTimer() {
    _stopRefreshTimer();
    // Refresh discovery every 30 seconds on the Dart side
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshDiscovery();
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _handleDiscoveryEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      if (type == 'servicesFound') {
        final services = event['services'] as List?;
        if (services != null) {
          final neighbors = _parseServices(services);
          if (neighbors.isNotEmpty) {
            _neighborsController.add(neighbors);
          }
        }
      }
    }
  }

  List<NodeInfo> _parseServices(List services) {
    return services.map((s) {
      if (s is Map) {
        final txtRecord = s.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        final displayName = txtRecord['deviceName'] ?? txtRecord['name'] ?? txtRecord['id'] ?? 'Unknown';
        final deviceAddress = txtRecord['deviceAddress'] ?? '';
        final signalStrength = int.tryParse(txtRecord['sig'] ?? '-70') ?? -70;
        return NodeInfo.fromTxtRecord(txtRecord, displayName, deviceAddress, signalStrength);
      }
      return null;
    }).whereType<NodeInfo>().toList();
  }

  void _handleError(Object error) {
    // Log error but don't crash
    // ignore: avoid_print
    print('DiscoveryChannel error: $error');
  }

  /// Dispose resources.
  void dispose() {
    _stopRefreshTimer();
    _subscription?.cancel();
    _neighborsController.close();
  }
}
