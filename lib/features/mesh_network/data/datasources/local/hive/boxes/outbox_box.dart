import 'dart:async';
import 'package:hive/hive.dart';
import '../../../../models/mesh_packet_model.dart';
import '../../../../../domain/entities/mesh_packet.dart';

/// The Outbox manages packets waiting to be sent through the mesh network.
///
/// This is Hive-backed persistent storage that survives app restarts.
/// When the relay orchestrator finds a viable route, it will pick packets
/// from this outbox and attempt to send them.
///
/// **Key Features:**
/// - Persistent storage (survives app kill/restart)
/// - Priority queue (critical SOS packets sent first)
/// - Retry tracking (packets get multiple send attempts)
/// - Expiration (old packets are cleaned up)
class OutboxBox {
  static const String boxName = 'outbox';
  static const int maxRetries = 5;
  static const Duration packetTtl = Duration(hours: 1);

  Box<OutboxEntry>? _box;

  /// Whether the outbox has been initialized.
  bool get isInitialized => _box?.isOpen ?? false;

  /// Opens the outbox Hive box.
  ///
  /// Must be called before using any other methods.
  Future<void> init() async {
    if (_box?.isOpen ?? false) return;

    // Register adapter if not already registered
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(OutboxEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MeshPacketModelAdapter());
    }

    _box = await Hive.openBox<OutboxEntry>(boxName);
    
    // Clean up expired entries on startup
    await _cleanupExpired();
  }

  /// Closes the outbox box.
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  /// Adds a packet to the outbox for sending.
  ///
  /// [packet] - The domain entity to queue.
  /// Returns the entry key for tracking.
  Future<String> addPacket(MeshPacket packet) async {
    _ensureInitialized();

    final entry = OutboxEntry(
      packet: MeshPacketModel.fromEntity(packet),
      addedAt: DateTime.now().millisecondsSinceEpoch,
      retryCount: 0,
      lastAttemptAt: null,
      status: OutboxStatus.pending,
    );

    await _box!.put(packet.id, entry);
    return packet.id;
  }

  /// Gets all pending packets, sorted by priority (critical first).
  List<MeshPacket> getPendingPackets() {
    _ensureInitialized();

    final entries = _box!.values
        .where((e) => e.status == OutboxStatus.pending)
        .toList();

    // Sort by priority (higher = more urgent, so descending)
    entries.sort((a, b) => b.packet.priority.compareTo(a.packet.priority));

    return entries.map((e) => e.packet.toEntity()).toList();
  }

  /// Gets the next packet to send (highest priority pending).
  MeshPacket? getNextPacket() {
    final pending = getPendingPackets();
    return pending.isNotEmpty ? pending.first : null;
  }

  /// Marks a packet as successfully sent.
  Future<void> markSent(String packetId) async {
    _ensureInitialized();

    final entry = _box!.get(packetId);
    if (entry != null) {
      final updated = entry.copyWith(status: OutboxStatus.sent);
      await _box!.put(packetId, updated);
    }
  }

  /// Marks a packet as failed (increments retry count).
  ///
  /// Returns true if the packet can be retried, false if max retries exceeded.
  Future<bool> markFailed(String packetId) async {
    _ensureInitialized();

    final entry = _box!.get(packetId);
    if (entry == null) return false;

    final newRetryCount = entry.retryCount + 1;
    
    if (newRetryCount >= maxRetries) {
      // Max retries exceeded, mark as failed permanently
      final updated = entry.copyWith(
        status: OutboxStatus.failed,
        retryCount: newRetryCount,
        lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _box!.put(packetId, updated);
      return false;
    }

    // Can retry
    final updated = entry.copyWith(
      status: OutboxStatus.pending,
      retryCount: newRetryCount,
      lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _box!.put(packetId, updated);
    return true;
  }

  /// Marks a packet as currently being sent.
  Future<void> markInProgress(String packetId) async {
    _ensureInitialized();

    final entry = _box!.get(packetId);
    if (entry != null) {
      final updated = entry.copyWith(
        status: OutboxStatus.inProgress,
        lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _box!.put(packetId, updated);
    }
  }

  /// Removes a packet from the outbox.
  Future<void> removePacket(String packetId) async {
    _ensureInitialized();
    await _box!.delete(packetId);
  }

  /// Checks if a packet is in the outbox.
  bool contains(String packetId) {
    _ensureInitialized();
    return _box!.containsKey(packetId);
  }

  /// Gets the status of a packet.
  OutboxStatus? getStatus(String packetId) {
    _ensureInitialized();
    return _box!.get(packetId)?.status;
  }

  /// Gets the count of pending packets.
  int get pendingCount {
    _ensureInitialized();
    return _box!.values.where((e) => e.status == OutboxStatus.pending).length;
  }

  /// Gets the count of all packets in outbox.
  int get totalCount {
    _ensureInitialized();
    return _box!.length;
  }

  /// Clears all packets from the outbox.
  Future<void> clear() async {
    _ensureInitialized();
    await _box!.clear();
  }

  /// Cleans up expired packets.
  Future<int> _cleanupExpired() async {
    _ensureInitialized();

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredKeys = <String>[];

    for (final entry in _box!.toMap().entries) {
      final age = now - entry.value.addedAt;
      if (age > packetTtl.inMilliseconds) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      await _box!.delete(key);
    }

    return expiredKeys.length;
  }

  /// Returns outbox statistics.
  OutboxStats getStats() {
    _ensureInitialized();

    int pending = 0;
    int inProgress = 0;
    int sent = 0;
    int failed = 0;

    for (final entry in _box!.values) {
      switch (entry.status) {
        case OutboxStatus.pending:
          pending++;
          break;
        case OutboxStatus.inProgress:
          inProgress++;
          break;
        case OutboxStatus.sent:
          sent++;
          break;
        case OutboxStatus.failed:
          failed++;
          break;
      }
    }

    return OutboxStats(
      pending: pending,
      inProgress: inProgress,
      sent: sent,
      failed: failed,
      total: _box!.length,
    );
  }

  void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError('OutboxBox not initialized. Call init() first.');
    }
  }
}

/// Entry in the outbox representing a queued packet.
@HiveType(typeId: 1)
class OutboxEntry extends HiveObject {
  @HiveField(0)
  final MeshPacketModel packet;

  @HiveField(1)
  final int addedAt;

  @HiveField(2)
  final int retryCount;

  @HiveField(3)
  final int? lastAttemptAt;

  @HiveField(4)
  final OutboxStatus status;

  OutboxEntry({
    required this.packet,
    required this.addedAt,
    required this.retryCount,
    this.lastAttemptAt,
    required this.status,
  });

  OutboxEntry copyWith({
    MeshPacketModel? packet,
    int? addedAt,
    int? retryCount,
    int? lastAttemptAt,
    OutboxStatus? status,
  }) {
    return OutboxEntry(
      packet: packet ?? this.packet,
      addedAt: addedAt ?? this.addedAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      status: status ?? this.status,
    );
  }
}

/// Status of an outbox entry.
@HiveType(typeId: 2)
enum OutboxStatus {
  @HiveField(0)
  pending,

  @HiveField(1)
  inProgress,

  @HiveField(2)
  sent,

  @HiveField(3)
  failed,
}

/// Manual Hive adapter for OutboxEntry.
class OutboxEntryAdapter extends TypeAdapter<OutboxEntry> {
  @override
  final int typeId = 1;

  @override
  OutboxEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OutboxEntry(
      packet: fields[0] as MeshPacketModel,
      addedAt: fields[1] as int,
      retryCount: fields[2] as int,
      lastAttemptAt: fields[3] as int?,
      status: OutboxStatus.values[fields[4] as int],
    );
  }

  @override
  void write(BinaryWriter writer, OutboxEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.packet)
      ..writeByte(1)
      ..write(obj.addedAt)
      ..writeByte(2)
      ..write(obj.retryCount)
      ..writeByte(3)
      ..write(obj.lastAttemptAt)
      ..writeByte(4)
      ..write(obj.status.index);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboxEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

/// Statistics about the outbox.
class OutboxStats {
  final int pending;
  final int inProgress;
  final int sent;
  final int failed;
  final int total;

  const OutboxStats({
    required this.pending,
    required this.inProgress,
    required this.sent,
    required this.failed,
    required this.total,
  });

  @override
  String toString() {
    return 'OutboxStats(pending: $pending, inProgress: $inProgress, '
        'sent: $sent, failed: $failed, total: $total)';
  }
}
