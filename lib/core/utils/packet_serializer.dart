import 'dart:convert';
import '../../features/mesh_network/domain/entities/mesh_packet.dart';
import '../../features/mesh_network/data/models/mesh_packet_model.dart';

/// Utility for serializing/deserializing mesh packets.
class PacketSerializer {
  PacketSerializer._();

  /// Serialize MeshPacket to JSON string.
  static String toJson(MeshPacket packet) {
    return MeshPacketModel.entityToJsonString(packet);
  }

  /// Deserialize JSON string to MeshPacket.
  static MeshPacket fromJson(String json) {
    return MeshPacketModel.entityFromJsonString(json);
  }

  /// Serialize MeshPacket to Map.
  static Map<String, dynamic> toMap(MeshPacket packet) {
    return MeshPacketModel.fromEntity(packet).toJson();
  }

  /// Deserialize Map to MeshPacket.
  static MeshPacket fromMap(Map<String, dynamic> map) {
    return MeshPacketModel.fromJson(map).toEntity();
  }

  /// Serialize packet for network transmission.
  ///
  /// Returns base64-encoded JSON for compact transmission.
  static String serialize(MeshPacket packet) {
    final json = toJson(packet);
    return base64.encode(utf8.encode(json));
  }

  /// Deserialize packet from network transmission.
  static MeshPacket deserialize(String encoded) {
    final json = utf8.decode(base64.decode(encoded));
    return fromJson(json);
  }

  /// Validate packet JSON structure.
  static bool isValid(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return _validateStructure(map);
    } catch (e) {
      return false;
    }
  }

  static bool _validateStructure(Map<String, dynamic> map) {
    // Check required fields
    if (!map.containsKey('id')) return false;
    if (!map.containsKey('originatorId')) return false;
    if (!map.containsKey('payload')) return false;
    if (!map.containsKey('trace')) return false;
    if (!map.containsKey('ttl')) return false;

    // Validate types
    if (map['id'] is! String) return false;
    if (map['originatorId'] is! String) return false;
    if (map['payload'] is! String) return false;
    if (map['trace'] is! List) return false;
    if (map['ttl'] is! int) return false;

    // Validate TTL range
    final ttl = map['ttl'] as int;
    if (ttl < 0 || ttl > 100) return false;

    return true;
  }

  /// Get packet size in bytes.
  static int getPacketSize(MeshPacket packet) {
    final json = toJson(packet);
    return utf8.encode(json).length;
  }

  /// Check if packet exceeds size limit.
  static bool exceedsSizeLimit(MeshPacket packet, {int maxBytes = 65536}) {
    return getPacketSize(packet) > maxBytes;
  }
}
