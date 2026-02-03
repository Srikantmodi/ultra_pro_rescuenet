import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';

/// Probes internet connectivity to determine if this node is a "Goal" node.
///
/// A "Goal" node has internet access and can deliver SOS packets to
/// emergency services or cloud backends.
///
/// **How it works:**
/// 1. Periodically pings multiple reliable endpoints
/// 2. Uses DNS lookup and HTTP HEAD requests
/// 3. Caches result to avoid excessive network usage
/// 4. Broadcasts connectivity changes via stream
///
/// This is critical for the AI Router's scoring - nodes with internet
/// get +50 points as they are the ultimate destination for SOS packets.
class InternetProbe {
  /// Endpoints to probe for connectivity.
  /// Uses multiple to avoid false negatives from single point failures.
  static const List<String> _probeEndpoints = [
    'google.com',
    'cloudflare.com',
    '8.8.8.8', // Google DNS
    '1.1.1.1', // Cloudflare DNS
  ];

  /// How long to wait between probes when internet is detected.
  static const Duration _normalProbeInterval = Duration(seconds: 60);

  /// How long to wait between probes when no internet (probe more often).
  static const Duration _offlineProbeInterval = Duration(seconds: 15);

  /// Timeout for each probe attempt.
  static const Duration _probeTimeout = Duration(seconds: 5);

  /// Cache duration for connectivity result.
  static const Duration _cacheDuration = Duration(seconds: 30);

  // State
  bool _hasInternet = false;
  DateTime? _lastProbeTime;
  Timer? _probeTimer;

  // Stream controller
  final _connectivityController = BehaviorSubject<bool>.seeded(false);

  /// Stream of connectivity status changes.
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Current connectivity status.
  bool get hasInternet => _hasInternet;

  /// Whether the cached result is still valid.
  bool get _isCacheValid {
    if (_lastProbeTime == null) return false;
    return DateTime.now().difference(_lastProbeTime!) < _cacheDuration;
  }

  /// Starts periodic connectivity probing.
  void startProbing() {
    // Run immediately
    checkConnectivity();

    // Schedule periodic probes
    _scheduleNextProbe();
  }

  /// Stops periodic connectivity probing.
  void stopProbing() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  /// Checks connectivity and returns the result.
  ///
  /// Uses cached result if still valid.
  Future<bool> checkConnectivity({bool forceRefresh = false}) async {
    // Return cached result if valid and not forcing refresh
    if (!forceRefresh && _isCacheValid) {
      return _hasInternet;
    }

    final result = await _probeConnectivity();
    _updateConnectivity(result);
    return result;
  }

  /// Performs the actual connectivity probe.
  Future<bool> _probeConnectivity() async {
    // Try multiple endpoints in parallel
    final results = await Future.wait(
      _probeEndpoints.map((endpoint) => _probeEndpoint(endpoint)),
    );

    // If any endpoint is reachable, we have internet
    return results.any((result) => result);
  }

  /// Probes a single endpoint.
  Future<bool> _probeEndpoint(String endpoint) async {
    try {
      // Try DNS lookup first (faster)
      final dnsResult = await _tryDnsLookup(endpoint);
      if (dnsResult) return true;

      // If DNS fails, try socket connection
      return await _trySocketConnection(endpoint);
    } catch (e) {
      return false;
    }
  }

  /// Attempts DNS lookup.
  Future<bool> _tryDnsLookup(String host) async {
    try {
      final result = await InternetAddress.lookup(host)
          .timeout(_probeTimeout);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Attempts socket connection.
  Future<bool> _trySocketConnection(String host) async {
    Socket? socket;
    try {
      // Try connecting to port 53 (DNS) or 443 (HTTPS)
      final port = host.contains('.') && !host.startsWith(RegExp(r'\d')) ? 443 : 53;
      socket = await Socket.connect(
        host,
        port,
        timeout: _probeTimeout,
      );
      return true;
    } catch (e) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Updates connectivity state and notifies listeners.
  void _updateConnectivity(bool hasInternet) {
    _lastProbeTime = DateTime.now();

    if (_hasInternet != hasInternet) {
      _hasInternet = hasInternet;
      _connectivityController.add(hasInternet);

      // Reschedule probe with appropriate interval
      _scheduleNextProbe();
    }
  }

  /// Schedules the next connectivity probe.
  void _scheduleNextProbe() {
    _probeTimer?.cancel();

    final interval = _hasInternet
        ? _normalProbeInterval
        : _offlineProbeInterval;

    _probeTimer = Timer(interval, () {
      checkConnectivity(forceRefresh: true);
      _scheduleNextProbe();
    });
  }

  /// Gets a summary of the current connectivity status.
  ConnectivityStatus getStatus() {
    return ConnectivityStatus(
      hasInternet: _hasInternet,
      lastCheck: _lastProbeTime,
      isProbing: _probeTimer != null,
    );
  }

  /// Disposes of resources.
  void dispose() {
    stopProbing();
    _connectivityController.close();
  }
}

/// Current connectivity status.
class ConnectivityStatus {
  final bool hasInternet;
  final DateTime? lastCheck;
  final bool isProbing;

  const ConnectivityStatus({
    required this.hasInternet,
    this.lastCheck,
    required this.isProbing,
  });

  /// How long ago the last check was performed.
  Duration? get timeSinceLastCheck {
    if (lastCheck == null) return null;
    return DateTime.now().difference(lastCheck!);
  }

  /// Human-readable status string.
  String get statusText {
    if (!isProbing) return 'Not monitoring';
    if (hasInternet) return 'Connected';
    return 'No internet';
  }

  @override
  String toString() {
    return 'ConnectivityStatus($statusText, '
        'lastCheck: ${timeSinceLastCheck?.inSeconds ?? "never"}s ago)';
  }
}

/// Extension to integrate with mesh network.
extension InternetProbeExtension on InternetProbe {
  /// Determines the node role based on connectivity.
  ///
  /// Returns 'goal' if has internet, 'relay' otherwise.
  String getNodeRole() {
    return hasInternet ? 'goal' : 'relay';
  }

  /// Gets the internet score for AI routing.
  ///
  /// Returns 50 if has internet (the full weight), 0 otherwise.
  int getInternetScore() {
    return hasInternet ? 50 : 0;
  }
}
