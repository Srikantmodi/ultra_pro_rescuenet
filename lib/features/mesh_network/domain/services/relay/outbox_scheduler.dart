import 'dart:async';
import '../../entities/mesh_packet.dart';

/// Schedules outbox packet processing.
class OutboxScheduler {
  final Duration _normalInterval;
  final Duration _priorityInterval;

  Timer? _timer;
  bool _isRunning = false;
  Function(List<MeshPacket>)? _onProcess;

  OutboxScheduler({
    Duration normalInterval = const Duration(seconds: 10),
    Duration priorityInterval = const Duration(seconds: 2),
  })  : _normalInterval = normalInterval,
        _priorityInterval = priorityInterval;

  /// Whether the scheduler is running.
  bool get isRunning => _isRunning;

  /// Start the scheduler.
  void start({required Function(List<MeshPacket>) onProcess}) {
    if (_isRunning) return;

    _onProcess = onProcess;
    _isRunning = true;
    _scheduleNext(_normalInterval);
  }

  /// Stop the scheduler.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Trigger immediate processing for priority packets.
  void triggerImmediate() {
    _timer?.cancel();
    _scheduleNext(Duration.zero);
  }

  /// Notify that priority packet was added.
  void notifyPriorityPacket() {
    _timer?.cancel();
    _scheduleNext(_priorityInterval);
  }

  void _scheduleNext(Duration delay) {
    _timer = Timer(delay, () {
      if (!_isRunning) return;

      // The actual packets will be fetched by the callback
      _onProcess?.call([]);
      _scheduleNext(_normalInterval);
    });
  }

  /// Dispose resources.
  void dispose() {
    stop();
  }
}
