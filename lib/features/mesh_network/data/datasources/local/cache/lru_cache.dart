import 'dart:collection';

/// LRU (Least Recently Used) Cache for duplicate packet detection.
///
/// This cache stores packet IDs that have been seen recently to prevent
/// processing the same packet multiple times. This is the third layer
/// of loop prevention after trace checking and sender exclusion.
///
/// **How it works:**
/// - Fixed capacity (default 1000 entries)
/// - When capacity is reached, oldest entries are evicted
/// - O(1) lookup time using HashSet
/// - O(1) insert time using LinkedHashSet for ordering
///
/// **Usage in mesh network:**
/// 1. When a packet arrives, check `contains(packetId)`
/// 2. If true, drop the packet (duplicate)
/// 3. If false, add the ID and process the packet
class LruCache<T> {
  final int _capacity;
  final LinkedHashSet<T> _cache = LinkedHashSet<T>();

  /// Creates an LRU cache with the given capacity.
  ///
  /// [capacity] - Maximum number of items to store.
  /// Default is 1000, which is sufficient for typical mesh scenarios.
  LruCache({int capacity = 1000}) : _capacity = capacity {
    if (_capacity <= 0) {
      throw ArgumentError('Capacity must be positive, got $_capacity');
    }
  }

  /// Current number of items in the cache.
  int get size => _cache.length;

  /// Maximum capacity of the cache.
  int get capacity => _capacity;

  /// Whether the cache is empty.
  bool get isEmpty => _cache.isEmpty;

  /// Whether the cache is at capacity.
  bool get isFull => _cache.length >= _capacity;

  /// Checks if the given item is in the cache.
  ///
  /// Returns true if the item exists, false otherwise.
  /// This is an O(1) operation.
  bool contains(T item) {
    return _cache.contains(item);
  }

  /// Adds an item to the cache.
  ///
  /// If the item already exists, it's moved to the "most recently used" end.
  /// If the cache is full, the least recently used item is evicted.
  ///
  /// Returns true if the item was newly added, false if it already existed.
  bool add(T item) {
    // If already in cache, remove and re-add to update position
    if (_cache.contains(item)) {
      _cache.remove(item);
      _cache.add(item);
      return false; // Already existed
    }

    // Evict oldest if at capacity
    if (_cache.length >= _capacity) {
      _cache.remove(_cache.first);
    }

    _cache.add(item);
    return true; // Newly added
  }

  /// Adds an item only if it's not already in the cache.
  ///
  /// Returns true if the item was added (meaning it was new),
  /// false if it already existed (meaning this is a duplicate).
  ///
  /// This is the primary method for duplicate detection:
  /// ```dart
  /// if (!cache.addIfAbsent(packetId)) {
  ///   // Duplicate packet, drop it
  ///   return;
  /// }
  /// // Process new packet
  /// ```
  bool addIfAbsent(T item) {
    if (_cache.contains(item)) {
      return false; // Already exists, don't add
    }

    // Evict oldest if at capacity
    if (_cache.length >= _capacity) {
      _cache.remove(_cache.first);
    }

    _cache.add(item);
    return true; // Newly added
  }

  /// Removes an item from the cache.
  ///
  /// Returns true if the item was removed, false if it didn't exist.
  bool remove(T item) {
    return _cache.remove(item);
  }

  /// Clears all items from the cache.
  void clear() {
    _cache.clear();
  }

  /// Returns all items in the cache as a list (oldest first).
  List<T> toList() {
    return _cache.toList();
  }

  /// Returns cache statistics for debugging.
  CacheStats get stats {
    return CacheStats(
      size: _cache.length,
      capacity: _capacity,
      fillRatio: _cache.length / _capacity,
    );
  }

  @override
  String toString() {
    return 'LruCache(size: ${_cache.length}/$_capacity)';
  }
}

/// Specialized LRU cache for packet ID deduplication.
///
/// This is a convenience wrapper around [LruCache] specifically for
/// packet ID strings, with additional helper methods.
class SeenPacketCache {
  final LruCache<String> _cache;

  /// Creates a seen packet cache with the given capacity.
  ///
  /// [capacity] - Maximum number of packet IDs to remember.
  /// Default is 1000.
  SeenPacketCache({int capacity = 1000}) : _cache = LruCache<String>(capacity: capacity);

  /// Checks if a packet has been seen before.
  bool hasSeen(String packetId) {
    return _cache.contains(packetId);
  }

  /// Marks a packet as seen.
  ///
  /// Returns true if this is a new packet (first time seen),
  /// false if this is a duplicate (already seen).
  bool markAsSeen(String packetId) {
    return _cache.addIfAbsent(packetId);
  }

  /// Checks and marks in one operation.
  ///
  /// Returns true if the packet should be processed (new packet),
  /// false if it should be dropped (duplicate).
  ///
  /// This is the recommended method for packet reception:
  /// ```dart
  /// if (!seenCache.checkAndMark(packet.id)) {
  ///   log('Dropping duplicate packet: ${packet.id}');
  ///   return;
  /// }
  /// // Process the packet
  /// ```
  bool checkAndMark(String packetId) {
    return markAsSeen(packetId);
  }

  /// Removes a packet ID from the seen cache.
  ///
  /// Useful when a packet needs to be re-sent (e.g., after failure).
  void forget(String packetId) {
    _cache.remove(packetId);
  }

  /// Clears all seen packet IDs.
  void clear() {
    _cache.clear();
  }

  /// Number of packet IDs currently remembered.
  int get size => _cache.size;

  /// Maximum capacity.
  int get capacity => _cache.capacity;

  /// Cache statistics.
  CacheStats get stats => _cache.stats;

  @override
  String toString() => 'SeenPacketCache($_cache)';
}

/// Statistics about cache state.
class CacheStats {
  final int size;
  final int capacity;
  final double fillRatio;

  const CacheStats({
    required this.size,
    required this.capacity,
    required this.fillRatio,
  });

  @override
  String toString() {
    return 'CacheStats(size: $size/$capacity, fill: ${(fillRatio * 100).toStringAsFixed(1)}%)';
  }
}
