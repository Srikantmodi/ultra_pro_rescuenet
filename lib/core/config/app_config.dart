/// Application configuration for RescueNet Pro.
///
/// Centralized configuration values for the mesh network app.
class AppConfig {
  AppConfig._();

  /// Application name
  static const String appName = 'RescueNet Pro';

  /// Application version
  static const String version = '1.0.0';

  /// Build number
  static const int buildNumber = 1;

  /// Enable debug mode
  static const bool debugMode = true;

  /// Enable verbose logging
  static const bool verboseLogging = true;

  /// Default node ID prefix
  static const String nodeIdPrefix = 'RN_';

  /// API endpoints (for when internet is available)
  static const String sosReportEndpoint = 'https://api.rescuenet.io/v1/sos';
  static const String telemetryEndpoint = 'https://api.rescuenet.io/v1/telemetry';

  /// Local storage paths
  static const String hiveDatabasePath = 'rescue_net_db';

  /// Hive box names
  static const String outboxBoxName = 'outbox';
  static const String inboxBoxName = 'inbox';
  static const String seenCacheBoxName = 'seen_cache';
  static const String settingsBoxName = 'settings';

  /// Environment
  static Environment get environment => 
      debugMode ? Environment.development : Environment.production;
}

/// Application environment
enum Environment {
  development,
  staging,
  production,
}

extension EnvironmentExtension on Environment {
  bool get isDevelopment => this == Environment.development;
  bool get isProduction => this == Environment.production;
}
