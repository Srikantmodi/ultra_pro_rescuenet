import 'dart:async';
import 'connectivity_monitor.dart';

/// Notifies listeners of network state changes.
class NetworkStateNotifier {
  final ConnectivityMonitor _monitor;
  final List<void Function(bool isConnected)> _listeners = [];

  StreamSubscription? _subscription;

  NetworkStateNotifier(this._monitor);

  /// Add a listener for connectivity changes.
  void addListener(void Function(bool isConnected) listener) {
    _listeners.add(listener);
    // Notify immediately with current state
    listener(_monitor.currentStatus.isConnected);
  }

  /// Remove a listener.
  void removeListener(void Function(bool isConnected) listener) {
    _listeners.remove(listener);
  }

  /// Start listening to connectivity changes.
  void startListening() {
    _subscription?.cancel();
    _subscription = _monitor.stream.listen((status) {
      _notifyAll(status.isConnected);
    });
    _monitor.startMonitoring();
  }

  /// Stop listening.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _monitor.stopMonitoring();
  }

  void _notifyAll(bool isConnected) {
    for (final listener in _listeners) {
      listener(isConnected);
    }
  }

  /// Current connectivity state.
  bool get isConnected => _monitor.currentStatus.isConnected;

  /// Dispose resources.
  void dispose() {
    stopListening();
    _listeners.clear();
    _monitor.dispose();
  }
}
