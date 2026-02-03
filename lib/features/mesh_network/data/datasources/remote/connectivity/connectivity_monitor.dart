import 'dart:async';
import 'dart:io';

/// Monitors network connectivity changes.
class ConnectivityMonitor {
  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();

  ConnectivityStatus _currentStatus = ConnectivityStatus.unknown;
  Timer? _pollTimer;

  /// Stream of connectivity status changes.
  Stream<ConnectivityStatus> get stream => _controller.stream;

  /// Current connectivity status.
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Start monitoring connectivity.
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    stopMonitoring();
    _checkConnectivity();
    _pollTimer = Timer.periodic(interval, (_) => _checkConnectivity());
  }

  /// Stop monitoring.
  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Check connectivity immediately.
  Future<ConnectivityStatus> checkNow() async {
    return _checkConnectivity();
  }

  Future<ConnectivityStatus> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.connected);
      } else {
        _updateStatus(ConnectivityStatus.disconnected);
      }
    } on SocketException {
      _updateStatus(ConnectivityStatus.disconnected);
    } on TimeoutException {
      _updateStatus(ConnectivityStatus.disconnected);
    } catch (e) {
      _updateStatus(ConnectivityStatus.unknown);
    }

    return _currentStatus;
  }

  void _updateStatus(ConnectivityStatus newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      _controller.add(newStatus);
    }
  }

  /// Dispose resources.
  void dispose() {
    stopMonitoring();
    _controller.close();
  }
}

/// Connectivity status.
enum ConnectivityStatus {
  unknown,
  connected,
  disconnected,
}

extension ConnectivityStatusExtension on ConnectivityStatus {
  bool get isConnected => this == ConnectivityStatus.connected;
  bool get isDisconnected => this == ConnectivityStatus.disconnected;
  
  String get displayName {
    switch (this) {
      case ConnectivityStatus.connected:
        return 'Connected';
      case ConnectivityStatus.disconnected:
        return 'Disconnected';
      default:
        return 'Unknown';
    }
  }
}
