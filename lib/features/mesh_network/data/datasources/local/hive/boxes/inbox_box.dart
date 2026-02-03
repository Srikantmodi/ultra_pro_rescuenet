import 'dart:async';
import 'package:hive/hive.dart';
import '../../../../models/mesh_packet_model.dart';
import '../../../../../domain/entities/mesh_packet.dart';

/// Inbox Hive box for storing received packets.
class InboxBox {
  static const String _boxName = 'inbox';
  Box<MeshPacketModel>? _box;

  /// Initialize the inbox box.
  Future<void> initialize() async {
    _box = await Hive.openBox<MeshPacketModel>(_boxName);
  }

  /// Get all packets.
  List<MeshPacket> getAll() {
    _ensureOpen();
    return _box!.values.map((m) => m.toEntity()).toList();
  }

  /// Get recent packets (limited).
  List<MeshPacket> getRecent({int limit = 50}) {
    _ensureOpen();
    final all = _box!.values.toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).map((m) => m.toEntity()).toList();
  }

  /// Add a received packet.
  Future<void> add(MeshPacket packet) async {
    _ensureOpen();
    await _box!.put(packet.id, MeshPacketModel.fromEntity(packet));
  }

  /// Check if packet exists.
  bool contains(String packetId) {
    _ensureOpen();
    return _box!.containsKey(packetId);
  }

  /// Delete a packet.
  Future<void> delete(String packetId) async {
    _ensureOpen();
    await _box!.delete(packetId);
  }

  /// Clear all packets.
  Future<void> clear() async {
    _ensureOpen();
    await _box!.clear();
  }

  /// Get SOS packets only.
  List<MeshPacket> getSosCalls() {
    _ensureOpen();
    return _box!.values
        .where((m) => m.packetType == MeshPacket.typeSos)
        .map((m) => m.toEntity())
        .toList();
  }

  void _ensureOpen() {
    if (_box == null) {
      throw StateError('InboxBox not initialized');
    }
  }
}
