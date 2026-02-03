import 'dart:async';
import 'package:hive/hive.dart';

/// Seen packet cache storage using Hive for persistence.
class SeenCacheBox {
  static const String _boxName = 'seen_cache';
  static const int _maxSize = 1000;
  Box<int>? _box;

  /// Initialize the seen cache box.
  Future<void> initialize() async {
    _box = await Hive.openBox<int>(_boxName);
  }

  /// Check if packet has been seen.
  bool hasSeen(String packetId) {
    _ensureOpen();
    return _box!.containsKey(packetId);
  }

  /// Mark packet as seen.
  Future<void> markSeen(String packetId) async {
    _ensureOpen();

    // Evict old entries if at capacity
    if (_box!.length >= _maxSize) {
      await _evictOldest();
    }

    await _box!.put(packetId, DateTime.now().millisecondsSinceEpoch);
  }

  /// Check and mark in one operation.
  Future<bool> checkAndMark(String packetId) async {
    if (hasSeen(packetId)) {
      return true; // Was already seen
    }
    await markSeen(packetId);
    return false; // Was not seen before
  }

  /// Get when a packet was seen.
  DateTime? getSeenTime(String packetId) {
    _ensureOpen();
    final timestamp = _box!.get(packetId);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Clear all seen packets.
  Future<void> clear() async {
    _ensureOpen();
    await _box!.clear();
  }

  /// Get count of seen packets.
  int get count {
    _ensureOpen();
    return _box!.length;
  }

  Future<void> _evictOldest() async {
    // Find entries older than 1 hour
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    final expiredKeys = <String>[];

    for (final key in _box!.keys) {
      final timestamp = _box!.get(key);
      if (timestamp != null) {
        final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (time.isBefore(oneHourAgo)) {
          expiredKeys.add(key as String);
        }
      }
    }

    // Delete expired
    for (final key in expiredKeys) {
      await _box!.delete(key);
    }

    // If still too many, delete oldest
    if (_box!.length >= _maxSize) {
      final entries = _box!.keys.toList();
      final toDelete = entries.take((_maxSize * 0.1).round()).toList();
      for (final key in toDelete) {
        await _box!.delete(key);
      }
    }
  }

  void _ensureOpen() {
    if (_box == null) {
      throw StateError('SeenCacheBox not initialized');
    }
  }
}
