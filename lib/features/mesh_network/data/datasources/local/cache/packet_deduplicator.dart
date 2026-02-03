import 'lru_cache.dart';

/// Packet deduplicator using LRU cache.
///
/// Wraps SeenPacketCache with additional functionality.
class PacketDeduplicator {
  final SeenPacketCache _cache;

  PacketDeduplicator({int maxSize = 1000})
      : _cache = SeenPacketCache(capacity: maxSize);

  /// Check if packet has been seen and mark it.
  bool isDuplicate(String packetId) {
    return !_cache.checkAndMark(packetId);
  }

  /// Check if packet has been seen without marking.
  bool hasSeen(String packetId) {
    return _cache.hasSeen(packetId);
  }

  /// Mark packet as seen.
  void markSeen(String packetId) {
    _cache.markAsSeen(packetId);
  }

  /// Get the number of unique packets seen.
  int get seenCount => _cache.size;

  /// Clear all seen packets.
  void clear() => _cache.clear();
}
