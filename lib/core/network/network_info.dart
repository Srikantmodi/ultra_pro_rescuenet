import 'dart:async';
import 'dart:io';

/// Network information provider.
///
/// Checks network connectivity and provides network state.
class NetworkInfo {
  final StreamController<NetworkState> _stateController =
      StreamController<NetworkState>.broadcast();

  NetworkState _currentState = NetworkState.unknown;
  Timer? _checkTimer;

  /// Stream of network state changes.
  Stream<NetworkState> get stateStream => _stateController.stream;

  /// Current network state.
  NetworkState get currentState => _currentState;

  /// Whether currently connected to any network.
  bool get isConnected =>
      _currentState == NetworkState.wifi ||
      _currentState == NetworkState.mobile;

  /// Whether connected via Wi-Fi.
  bool get isWifi => _currentState == NetworkState.wifi;

  /// Whether connected via mobile data.
  bool get isMobile => _currentState == NetworkState.mobile;

  /// Start monitoring network state.
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    stopMonitoring();
    _checkNetworkState();
    _checkTimer = Timer.periodic(interval, (_) => _checkNetworkState());
  }

  /// Stop monitoring network state.
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Check network state once.
  Future<NetworkState> checkNetworkState() async {
    await _checkNetworkState();
    return _currentState;
  }

  Future<void> _checkNetworkState() async {
    try {
      // Try to resolve a known host
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        // Connected - determine type based on interface
        // For now, assume wifi since we can't easily determine on all platforms
        _updateState(NetworkState.wifi);
      } else {
        _updateState(NetworkState.disconnected);
      }
    } catch (e) {
      _updateState(NetworkState.disconnected);
    }
  }

  void _updateState(NetworkState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Dispose resources.
  void dispose() {
    stopMonitoring();
    _stateController.close();
  }
}

/// Network connection state.
enum NetworkState {
  /// Unknown state
  unknown,

  /// Disconnected from all networks
  disconnected,

  /// Connected via Wi-Fi
  wifi,

  /// Connected via mobile data
  mobile,

  /// Connected via ethernet
  ethernet,
}

extension NetworkStateExtension on NetworkState {
  /// Human-readable name.
  String get displayName {
    switch (this) {
      case NetworkState.unknown:
        return 'Unknown';
      case NetworkState.disconnected:
        return 'Disconnected';
      case NetworkState.wifi:
        return 'Wi-Fi';
      case NetworkState.mobile:
        return 'Mobile Data';
      case NetworkState.ethernet:
        return 'Ethernet';
    }
  }

  /// Whether this state indicates connectivity.
  bool get isConnected =>
      this == NetworkState.wifi ||
      this == NetworkState.mobile ||
      this == NetworkState.ethernet;
}
