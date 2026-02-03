import 'dart:async';
import 'dart:io';

/// Internet probe for checking connectivity to multiple endpoints.
class InternetProbeRemote {
  static const List<String> _defaultEndpoints = [
    'google.com',
    'cloudflare.com',
    '8.8.8.8',
    '1.1.1.1',
  ];

  final List<String> endpoints;
  final Duration timeout;

  bool _lastResult = false;
  DateTime? _lastCheck;

  InternetProbeRemote({
    List<String>? endpoints,
    this.timeout = const Duration(seconds: 5),
  }) : endpoints = endpoints ?? _defaultEndpoints;

  /// Last known result.
  bool get hasInternet => _lastResult;

  /// Time since last check.
  Duration? get timeSinceLastCheck =>
      _lastCheck != null ? DateTime.now().difference(_lastCheck!) : null;

  /// Probe internet connectivity.
  Future<bool> probe() async {
    for (final endpoint in endpoints) {
      try {
        final result = await InternetAddress.lookup(endpoint).timeout(timeout);
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          _lastResult = true;
          _lastCheck = DateTime.now();
          return true;
        }
      } catch (e) {
        // Try next endpoint
        continue;
      }
    }

    _lastResult = false;
    _lastCheck = DateTime.now();
    return false;
  }

  /// Probe with TCP socket for more reliable check.
  Future<bool> probeWithSocket({String host = '8.8.8.8', int port = 53}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      _lastResult = true;
      _lastCheck = DateTime.now();
      return true;
    } catch (e) {
      _lastResult = false;
      _lastCheck = DateTime.now();
      return false;
    }
  }

  /// Get cached result if recent, otherwise probe.
  Future<bool> getCachedOrProbe({Duration maxAge = const Duration(seconds: 30)}) async {
    if (_lastCheck != null && timeSinceLastCheck! < maxAge) {
      return _lastResult;
    }
    return probe();
  }
}
