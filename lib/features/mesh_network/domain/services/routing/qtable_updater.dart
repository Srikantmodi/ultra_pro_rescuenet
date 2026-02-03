import '../../entities/node_info.dart';

/// Updates Q-table based on routing outcomes.
class QTableUpdater {
  final double learningRate;
  final double discountFactor;
  final Map<String, double> _qTable = {};

  QTableUpdater({
    this.learningRate = 0.1,
    this.discountFactor = 0.9,
  });

  /// Get Q-value for a state-action pair.
  double getQValue(String state, String action) {
    return _qTable['$state|$action'] ?? 0.0;
  }

  /// Update Q-value after observing reward.
  void update({
    required String state,
    required String action,
    required double reward,
    String? nextState,
    List<String>? nextActions,
  }) {
    final key = '$state|$action';
    final currentQ = _qTable[key] ?? 0.0;

    double maxNextQ = 0.0;
    if (nextState != null && nextActions != null && nextActions.isNotEmpty) {
      maxNextQ = nextActions
          .map((a) => getQValue(nextState, a))
          .reduce((a, b) => a > b ? a : b);
    }

    // Q-Learning update
    final newQ = currentQ + learningRate * (reward + discountFactor * maxNextQ - currentQ);
    _qTable[key] = newQ;
  }

  /// Record successful delivery (+10 reward).
  void recordSuccess(String nodeId) {
    update(
      state: 'forward',
      action: nodeId,
      reward: 10.0,
    );
  }

  /// Record failed delivery (-5 reward).
  void recordFailure(String nodeId) {
    update(
      state: 'forward',
      action: nodeId,
      reward: -5.0,
    );
  }

  /// Get best action for a list of candidates.
  String? getBestAction(List<NodeInfo> candidates) {
    if (candidates.isEmpty) return null;

    String? bestAction;
    double bestQ = double.negativeInfinity;

    for (final node in candidates) {
      final q = getQValue('forward', node.id);
      if (q > bestQ) {
        bestQ = q;
        bestAction = node.id;
      }
    }

    return bestAction;
  }

  /// Clear all Q-values.
  void clear() => _qTable.clear();

  /// Export Q-table for persistence.
  Map<String, double> export() => Map.from(_qTable);

  /// Import Q-table from persistence.
  void import(Map<String, double> table) {
    _qTable.clear();
    _qTable.addAll(table);
  }
}
