import 'package:hive/hive.dart';
import '../../../../../domain/entities/node_info.dart';

/// Hive TypeAdapter for NodeInfo.
class NodeInfoAdapter extends TypeAdapter<NodeInfo> {
  @override
  final int typeId = 1;

  @override
  NodeInfo read(BinaryReader reader) {
    return NodeInfo(
      id: reader.readString(),
      deviceAddress: '02:00:00:00:00:00', // Default as we don't persist this efficiently yet or changes often
      displayName: reader.readString(),
      batteryLevel: reader.readInt(),
      hasInternet: reader.readBool(),
      latitude: reader.readDouble(),
      longitude: reader.readDouble(),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      signalStrength: reader.readInt(),
      triageLevel: reader.readString(),
      role: reader.readString(),
      isAvailableForRelay: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, NodeInfo obj) {
    writer.writeString(obj.id);
    // Skip deviceAddress to save space/privacy, or read/write if needed. 
    // For now we skip it in Hive as it's transient P2P info.
    writer.writeString(obj.displayName);
    writer.writeInt(obj.batteryLevel);
    writer.writeBool(obj.hasInternet);
    writer.writeDouble(obj.latitude);
    writer.writeDouble(obj.longitude);
    writer.writeInt(obj.lastSeen.millisecondsSinceEpoch);
    writer.writeInt(obj.signalStrength);
    writer.writeString(obj.triageLevel);
    writer.writeString(obj.role);
    writer.writeBool(obj.isAvailableForRelay);
  }
}
