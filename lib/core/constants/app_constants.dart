/// Application-wide constants.
class AppConstants {
  AppConstants._();

  // ============== TIMING ==============

  /// Stale node timeout in minutes
  static const int staleNodeTimeoutMinutes = 2;

  /// Discovery refresh interval in seconds
  static const int discoveryRefreshSeconds = 10;

  /// Location update interval in seconds
  static const int locationUpdateSeconds = 30;

  /// High accuracy location interval in seconds
  static const int highAccuracyLocationSeconds = 5;

  /// Relay loop interval in seconds
  static const int relayLoopIntervalSeconds = 10;

  /// Outbox expiration in minutes
  static const int outboxExpirationMinutes = 60;

  // ============== LIMITS ==============

  /// Maximum packet TTL (hops)
  static const int maxPacketTtl = 10;

  /// Maximum retries for failed packets
  static const int maxPacketRetries = 5;

  /// Maximum seen packet cache size
  static const int maxSeenCacheSize = 1000;

  /// Maximum outbox size
  static const int maxOutboxSize = 100;

  /// Maximum recent SOS alerts to display
  static const int maxRecentSosAlerts = 10;

  // ============== THRESHOLDS ==============

  /// Minimum movement in meters to trigger location update
  static const double minimumMovementMeters = 5.0;

  /// Low battery threshold percentage
  static const int lowBatteryThreshold = 20;

  /// Critical battery threshold percentage
  static const int criticalBatteryThreshold = 10;

  /// Weak signal threshold in dBm
  static const int weakSignalThreshold = -70;

  // ============== UI ==============

  /// Animation duration in milliseconds
  static const int animationDurationMs = 300;

  /// Snackbar duration in seconds
  static const int snackbarDurationSeconds = 3;

  /// Map zoom level default
  static const double defaultMapZoom = 15.0;
}
