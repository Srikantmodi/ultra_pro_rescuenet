import 'package:equatable/equatable.dart';

/// Represents metadata about a discovered node in the mesh network.
///
/// This entity contains all the information broadcast via DNS-SD TXT records
/// and is used by the AI Router to make forwarding decisions.
///
/// Key fields for routing decisions:
/// - [hasInternet]: +50 points (Goal Node priority)
/// - [batteryLevel]: +25 points scaled by percentage
/// - [signalStrength]: +10 points scaled by dBm
///
/// The [isStale] getter determines if this node info is outdated (>2 minutes)
/// and should be excluded from routing decisions.
class NodeInfo extends Equatable {
  /// Unique identifier for this node (device-specific UUID)
  final String id;

  /// Wi-Fi Direct MAC address for connection.
  final String deviceAddress;

  /// Human-readable display name (device name or user-set name)
  final String displayName;

  /// Current battery level (0-100)
  final int batteryLevel;

  /// Whether this device has verified internet connectivity.
  /// Goal Nodes have this set to true, giving them +50 priority points.
  final bool hasInternet;

  /// GPS latitude coordinate
  final double latitude;

  /// GPS longitude coordinate
  final double longitude;

  /// Last time this node's metadata was updated.
  /// Used for stale detection.
  final DateTime lastSeen;

  /// Wi-Fi Direct signal strength in dBm.
  /// Typical range: -30 (excellent) to -90 (weak)
  final int signalStrength;

  /// Current triage level if this node is sending an SOS.
  /// - 'none': Not in emergency
  /// - 'green': Minor/walking wounded
  /// - 'yellow': Delayed - serious but stable
  /// - 'red': Immediate - life threatening
  final String triageLevel;

  /// Current role of this node in the mesh.
  /// - 'sender': Sending an SOS
  /// - 'relay': Acting as relay
  /// - 'goal': Has internet, final destination
  /// - 'idle': Not actively participating
  final String role;

  /// Whether the node is currently accepting relay connections.
  final bool isAvailableForRelay;

  /// Stale timeout in minutes. Nodes not seen within this time are excluded.
  static const int staleTimeoutMinutes = 2;

  /// Signal strength thresholds for quality classification
  static const int signalExcellent = -40;
  static const int signalGood = -55;
  static const int signalFair = -70;
  static const int signalWeak = -85;

  /// Role constants
  static const String roleSender = 'sender';
  static const String roleRelay = 'relay';
  static const String roleGoal = 'goal';
  static const String roleIdle = 'idle';

  /// Triage level constants
  static const String triageNone = 'none';
  static const String triageGreen = 'green';
  static const String triageYellow = 'yellow';
  static const String triageRed = 'red';

  /// Triage level integer values for compatibility
  static const int triageLevelNone = 0;
  static const int triageLevelGreen = 1;
  static const int triageLevelYellow = 2;
  static const int triageLevelRed = 3;

  const NodeInfo({
    required this.id,
    required this.deviceAddress,
    required this.displayName,
    required this.batteryLevel,
    required this.hasInternet,
    required this.latitude,
    required this.longitude,
    required this.lastSeen,
    required this.signalStrength,
    this.triageLevel = triageNone,
    this.role = roleIdle,
    this.isAvailableForRelay = true,
  });

  /// Creates a NodeInfo instance with basic defaults.
  factory NodeInfo.create({
    required String id,
    required String displayName,
    required int batteryLevel,
    required bool hasInternet,
    required double latitude,
    required double longitude,
    String deviceAddress = '',
    int signalStrength = -50,
    String triageLevel = triageNone,
    String role = roleIdle,
    bool isAvailableForRelay = true,
  }) {
    return NodeInfo(
      id: id,
      deviceAddress: deviceAddress,
      displayName: displayName,
      batteryLevel: batteryLevel.clamp(0, 100),
      hasInternet: hasInternet,
      latitude: latitude,
      longitude: longitude,
      lastSeen: DateTime.now(),
      signalStrength: signalStrength.clamp(-100, 0),
      triageLevel: triageLevel,
      role: role,
      isAvailableForRelay: isAvailableForRelay,
    );
  }

  /// Creates an empty NodeInfo for default cases.
  factory NodeInfo.empty() {
    return NodeInfo(
      id: '',
      deviceAddress: '',
      displayName: '',
      batteryLevel: 0,
      hasInternet: false,
      latitude: 0.0,
      longitude: 0.0,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
      signalStrength: -100,
      triageLevel: triageNone,
      role: roleIdle,
      isAvailableForRelay: false,
    );
  }

  /// Checks if this node info is stale (not updated recently).
  ///
  /// Returns true if [lastSeen] is more than [staleTimeoutMinutes] ago.
  /// Stale nodes should be excluded from routing decisions as they may
  /// have moved out of range or turned off.
  bool get isStale {
    final now = DateTime.now();
    final staleCutoff = now.subtract(
      const Duration(minutes: staleTimeoutMinutes),
    );
    return lastSeen.isBefore(staleCutoff);
  }

  /// Checks if this node info is fresh (recently updated).
  bool get isFresh => !isStale;

  /// Returns the age of this node info in seconds.
  int get ageSeconds {
    return DateTime.now().difference(lastSeen).inSeconds;
  }

  /// Returns a human-readable age string (e.g., "30s ago", "2m ago")
  String get ageString {
    final seconds = ageSeconds;
    if (seconds < 60) {
      return '${seconds}s ago';
    } else if (seconds < 3600) {
      return '${(seconds / 60).floor()}m ago';
    } else {
      return '${(seconds / 3600).floor()}h ago';
    }
  }

  /// Checks if this is a Goal Node (has internet connectivity).
  bool get isGoalNode => hasInternet;

  /// Checks if this node has active SOS.
  bool get hasActiveSos => triageLevel != triageNone;

  /// Checks if this is a critical (red) SOS.
  bool get isCriticalSos => triageLevel == triageRed;

  /// Returns signal quality as a category string.
  String get signalQuality {
    if (signalStrength >= signalExcellent) return 'excellent';
    if (signalStrength >= signalGood) return 'good';
    if (signalStrength >= signalFair) return 'fair';
    if (signalStrength >= signalWeak) return 'weak';
    return 'poor';
  }

  /// Returns battery level as a category string.
  String get batteryStatus {
    if (batteryLevel >= 80) return 'full';
    if (batteryLevel >= 50) return 'good';
    if (batteryLevel >= 20) return 'low';
    return 'critical';
  }

  /// Returns normalized signal strength (0.0 - 1.0) for scoring.
  /// Maps -90 dBm → 0.0 and -30 dBm → 1.0
  double get normalizedSignal {
    // Clamp to expected range and normalize
    final clamped = signalStrength.clamp(-90, -30);
    return (clamped + 90) / 60.0; // 0.0 to 1.0
  }

  /// Returns normalized battery level (0.0 - 1.0) for scoring.
  double get normalizedBattery => batteryLevel / 100.0;

  /// Calculates approximate distance to another node in meters.
  /// Uses Haversine formula for accuracy.
  double distanceTo(NodeInfo other) {
    return _haversineDistance(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
  }

  /// Haversine formula for calculating distance between two GPS coordinates.
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0; // Earth's radius in meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = _sin2(dLat / 2) +
        _cos(lat1) * _cos(lat2) * _sin2(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));

    return earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * 3.141592653589793 / 180.0;
  static double _sin2(double x) {
    final s = _sin(x);
    return s * s;
  }

  // Using approximations to avoid dart:math import in pure domain layer
  static double _sin(double x) {
    // Normalize to [-π, π]
    while (x > 3.141592653589793) x -= 2 * 3.141592653589793;
    while (x < -3.141592653589793) x += 2 * 3.141592653589793;
    // Taylor series approximation (good for small angles after normalization)
    final x2 = x * x;
    return x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42)));
  }

  static double _cos(double x) => _sin(x + 3.141592653589793 / 2);
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  static double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }

  static double _atan(double x) {
    // Taylor series for arctangent
    if (x.abs() > 1) {
      return (x > 0 ? 3.141592653589793 / 2 : -3.141592653589793 / 2) -
          _atan(1 / x);
    }
    final x2 = x * x;
    return x * (1 - x2 / 3 + x2 * x2 / 5 - x2 * x2 * x2 / 7);
  }

  /// Creates a copy of this node info with updated fields.
  NodeInfo copyWith({
    String? id,
    String? deviceAddress,
    String? displayName,
    int? batteryLevel,
    bool? hasInternet,
    double? latitude,
    double? longitude,
    DateTime? lastSeen,
    int? signalStrength,
    String? triageLevel,
    String? role,
    bool? isAvailableForRelay,
  }) {
    return NodeInfo(
      id: id ?? this.id,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      displayName: displayName ?? this.displayName,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      hasInternet: hasInternet ?? this.hasInternet,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      lastSeen: lastSeen ?? this.lastSeen,
      signalStrength: signalStrength ?? this.signalStrength,
      triageLevel: triageLevel ?? this.triageLevel,
      role: role ?? this.role,
      isAvailableForRelay: isAvailableForRelay ?? this.isAvailableForRelay,
    );
  }

  /// Updates the lastSeen timestamp to now.
  NodeInfo refresh() {
    return copyWith(lastSeen: DateTime.now());
  }

  @override
  List<Object?> get props => [
        id,
        deviceAddress,
        displayName,
        batteryLevel,
        hasInternet,
        latitude,
        longitude,
        lastSeen,
        signalStrength,
        triageLevel,
        role,
        isAvailableForRelay,
      ];

  @override
  String toString() {
    return 'NodeInfo('
        'id: $id, '
        'addr: $deviceAddress, '
        'name: $displayName, '
        'bat: $batteryLevel%, '
        'inet: $hasInternet, '
        'sig: ${signalStrength}dBm, '
        'role: $role, '
        'stale: $isStale'
        ')';
  }

  /// Converts to a compact map for DNS-SD TXT record broadcasting.
  /// Keys are abbreviated to minimize packet size.
  Map<String, String> toTxtRecord() {
    return {
      'id': id,
      'bat': batteryLevel.toString(),
      'net': hasInternet ? '1' : '0',
      'lat': latitude.toStringAsFixed(6),
      'lng': longitude.toStringAsFixed(6),
      'sig': signalStrength.toString(),
      'tri': triageLevel.substring(0, 1), // n/g/y/r
      'rol': role.substring(0, 1), // s/r/g/i
      'rel': isAvailableForRelay ? '1' : '0',
    };
  }

  /// Creates a NodeInfo from a DNS-SD TXT record map.
  factory NodeInfo.fromTxtRecord(
    Map<String, String> record,
    String displayName,
    String deviceAddress,
    int signalStrength,
  ) {
    final triageMap = {'n': triageNone, 'g': triageGreen, 'y': triageYellow, 'r': triageRed};
    final roleMap = {'s': roleSender, 'r': roleRelay, 'g': roleGoal, 'i': roleIdle};

    return NodeInfo(
      id: record['id'] ?? '',
      deviceAddress: deviceAddress,
      displayName: displayName,
      batteryLevel: int.tryParse(record['bat'] ?? '0') ?? 0,
      hasInternet: record['net'] == '1',
      latitude: double.tryParse(record['lat'] ?? '0') ?? 0,
      longitude: double.tryParse(record['lng'] ?? '0') ?? 0,
      lastSeen: DateTime.now(),
      signalStrength: signalStrength,
      triageLevel: triageMap[record['tri']] ?? triageNone,
      role: roleMap[record['rol']] ?? roleIdle,
      isAvailableForRelay: record['rel'] != '0',
    );
  }
}
