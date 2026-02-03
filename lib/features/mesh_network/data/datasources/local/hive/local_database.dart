import 'package:hive_flutter/hive_flutter.dart';
import '../../../models/mesh_packet_model.dart';

/// Local Hive database manager.
class LocalDatabase {
  static const String _outboxBoxName = 'outbox';
  static const String _inboxBoxName = 'inbox';
  static const String _seenCacheBoxName = 'seen_cache';
  static const String _settingsBoxName = 'settings';

  bool _isInitialized = false;

  /// Whether the database is initialized.
  bool get isInitialized => _isInitialized;

  /// Initialize Hive and register adapters.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    // Register type adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MeshPacketModelAdapter());
    }

    // Open boxes
    await Hive.openBox<MeshPacketModel>(_outboxBoxName);
    await Hive.openBox<MeshPacketModel>(_inboxBoxName);
    await Hive.openBox<String>(_seenCacheBoxName);
    await Hive.openBox(_settingsBoxName);

    _isInitialized = true;
  }

  /// Get outbox box.
  Box<MeshPacketModel> get outbox {
    _ensureInitialized();
    return Hive.box<MeshPacketModel>(_outboxBoxName);
  }

  /// Get inbox box.
  Box<MeshPacketModel> get inbox {
    _ensureInitialized();
    return Hive.box<MeshPacketModel>(_inboxBoxName);
  }

  /// Get seen cache box.
  Box<String> get seenCache {
    _ensureInitialized();
    return Hive.box<String>(_seenCacheBoxName);
  }

  /// Get settings box.
  Box get settings {
    _ensureInitialized();
    return Hive.box(_settingsBoxName);
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('LocalDatabase not initialized. Call initialize() first.');
    }
  }

  /// Clear all data.
  Future<void> clearAll() async {
    await outbox.clear();
    await inbox.clear();
    await seenCache.clear();
  }

  /// Close all boxes.
  Future<void> close() async {
    await Hive.close();
    _isInitialized = false;
  }
}
