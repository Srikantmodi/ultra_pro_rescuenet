/// Scoring weights for the AI router.
///
/// These weights determine how nodes are ranked for packet forwarding.
/// Higher total score = better candidate for routing.
class ScoringWeights {
  ScoringWeights._();

  // ============== PRIMARY WEIGHTS ==============

  /// Weight for internet connectivity (50 points max)
  /// Highest priority - nodes with internet can deliver packets
  static const double internetWeight = 50.0;

  /// Weight for SOS priority (30 points max)
  /// SOS packets get priority routing
  static const double sosPriorityWeight = 30.0;

  /// Weight for battery level (25 points max)
  /// Higher battery = more reliable relay
  static const double batteryWeight = 25.0;

  /// Weight for signal strength (10 points max)
  /// Better signal = more reliable connection
  static const double signalWeight = 10.0;

  // ============== PENALTIES ==============

  /// Penalty for stale nodes (outdated info)
  static const double stalePenalty = -30.0;

  /// Penalty for low battery (<20%)
  static const double lowBatteryPenalty = -20.0;

  /// Penalty for critical battery (<10%)
  static const double criticalBatteryPenalty = -40.0;

  /// Penalty for weak signal (>-70 dBm)
  static const double weakSignalPenalty = -10.0;

  /// Penalty for nodes in packet trace (loop prevention)
  static const double tracePenalty = -100.0;

  /// Penalty for unavailable relay nodes
  static const double unavailablePenalty = -100.0;

  // ============== BONUSES ==============

  /// Bonus for goal nodes (have reached internet)
  static const double goalNodeBonus = 20.0;

  /// Bonus for nodes with high success rate
  static const double highSuccessRateBonus = 15.0;

  /// Bonus for nearby nodes (strong signal)
  static const double proximityBonus = 5.0;

  // ============== THRESHOLDS ==============

  /// Minimum score to be considered for routing
  static const double minimumRoutableScore = 10.0;

  /// Score threshold for "excellent" candidate
  static const double excellentScoreThreshold = 80.0;

  /// Score threshold for "good" candidate
  static const double goodScoreThreshold = 50.0;

  // ============== CALCULATION ==============

  /// Calculate total score for a node
  static double calculateScore({
    required bool hasInternet,
    required bool isSosPacket,
    required int batteryLevel,
    required int signalStrength,
    required bool isStale,
    required bool inTrace,
    required bool isAvailable,
  }) {
    if (!isAvailable) return unavailablePenalty;
    if (inTrace) return tracePenalty;

    double score = 0;

    // Internet bonus
    if (hasInternet) score += internetWeight;

    // SOS priority
    if (isSosPacket) score += sosPriorityWeight;

    // Battery contribution (0-100 normalized to weight)
    score += (batteryLevel / 100.0) * batteryWeight;

    // Signal contribution (-100 to 0 dBm normalized)
    final signalNormalized = ((signalStrength + 100) / 100.0).clamp(0.0, 1.0);
    score += signalNormalized * signalWeight;

    // Penalties
    if (isStale) score += stalePenalty;
    if (batteryLevel < 10) {
      score += criticalBatteryPenalty;
    } else if (batteryLevel < 20) {
      score += lowBatteryPenalty;
    }
    if (signalStrength < -70) score += weakSignalPenalty;

    return score;
  }
}
