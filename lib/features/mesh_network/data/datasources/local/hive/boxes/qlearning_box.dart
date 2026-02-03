import 'dart:async';
import 'package:hive/hive.dart';

/// Q-Learning table storage for routing optimization.
///
/// Stores Q-values for state-action pairs in the routing decision process.
class QLearningBox {
  static const String _boxName = 'qlearning';
  Box<double>? _box;

  /// Learning rate (alpha)
  final double learningRate;

  /// Discount factor (gamma)
  final double discountFactor;

  QLearningBox({
    this.learningRate = 0.1,
    this.discountFactor = 0.9,
  });

  /// Initialize the Q-learning box.
  Future<void> initialize() async {
    _box = await Hive.openBox<double>(_boxName);
  }

  /// Get Q-value for a state-action pair.
  double getQValue(String state, String action) {
    _ensureOpen();
    final key = _makeKey(state, action);
    return _box!.get(key, defaultValue: 0.0) ?? 0.0;
  }

  /// Update Q-value using reward.
  Future<void> updateQValue({
    required String state,
    required String action,
    required double reward,
    String? nextState,
    String? nextAction,
  }) async {
    _ensureOpen();

    final currentQ = getQValue(state, action);
    double nextMaxQ = 0.0;

    if (nextState != null && nextAction != null) {
      nextMaxQ = getQValue(nextState, nextAction);
    }

    // Q-Learning update formula:
    // Q(s,a) = Q(s,a) + α * (r + γ * max(Q(s',a')) - Q(s,a))
    final newQ = currentQ + learningRate * (reward + discountFactor * nextMaxQ - currentQ);

    await _box!.put(_makeKey(state, action), newQ);
  }

  /// Get best action for a state.
  String? getBestAction(String state, List<String> possibleActions) {
    if (possibleActions.isEmpty) return null;

    String? bestAction;
    double bestQ = double.negativeInfinity;

    for (final action in possibleActions) {
      final q = getQValue(state, action);
      if (q > bestQ) {
        bestQ = q;
        bestAction = action;
      }
    }

    return bestAction;
  }

  /// Clear all Q-values.
  Future<void> clear() async {
    _ensureOpen();
    await _box!.clear();
  }

  String _makeKey(String state, String action) => '$state|$action';

  void _ensureOpen() {
    if (_box == null) {
      throw StateError('QLearningBox not initialized');
    }
  }
}
