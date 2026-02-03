/// Feature flags for RescueNet Pro.
///
/// Used to enable/disable features during development and A/B testing.
class FeatureFlags {
  FeatureFlags._();

  /// Enable AI-based routing
  static const bool enableAiRouting = true;

  /// Enable Q-Learning based optimization
  static const bool enableQLearning = false;

  /// Enable offline maps
  static const bool enableOfflineMaps = true;

  /// Enable SOS broadcasting
  static const bool enableSosBroadcast = true;

  /// Enable packet encryption
  static const bool enableEncryption = false;

  /// Enable telemetry (when internet available)
  static const bool enableTelemetry = false;

  /// Enable high-accuracy GPS for SOS
  static const bool enableHighAccuracyGps = true;

  /// Enable foreground service for background operation
  static const bool enableForegroundService = true;

  /// Enable battery optimization bypass prompt
  static const bool enableBatteryOptimizationPrompt = true;

  /// Enable debug overlay
  static const bool enableDebugOverlay = true;

  /// Enable packet trace logging
  static const bool enablePacketTraceLogging = true;

  /// Maximum allow TTL for packets
  static const int maxPacketTtl = 10;

  /// Enable aggressive neighbor discovery
  static const bool enableAggressiveDiscovery = false;
}
