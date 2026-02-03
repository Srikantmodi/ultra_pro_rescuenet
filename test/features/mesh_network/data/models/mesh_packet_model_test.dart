// File: test/features/mesh_network/data/models/mesh_packet_model_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/data/models/mesh_packet_model.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/entities/mesh_packet.dart';

void main() {
  group('UNIT TEST: MeshPacket Protocol', () {
    test('Should verify Packet Model JSON Serialization', () {
      final packet = MeshPacketModel(
        id: 'unique_id',
        originatorId: 'A',
        trace: ['A', 'B'],
        ttl: 15,
        payload: jsonEncode({'msg': 'SOS'}),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        priority: MeshPacket.priorityCritical,
        packetType: MeshPacket.typeSos,
      );

      final json = packet.toJson();
      final reconstructed = MeshPacketModel.fromJson(json);

      expect(reconstructed.id, packet.id);
      expect(reconstructed.trace, contains('A'));
      
      // Verify payload integrity
      final payloadMap = jsonDecode(reconstructed.payload);
      expect(payloadMap['msg'], 'SOS');
    });

    test('Should decrement TTL and append Trace correctly', () {
      var packet = MeshPacket(
          id: '1', 
          trace: const ['A'], 
          ttl: 20, 
          originatorId: 'A',
          packetType: MeshPacket.typeData,
          priority: MeshPacket.priorityMedium,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: ''
      );
      
      // Act: Forward to Node B (Method returns NEW packet)
      packet = packet.addHop('B');

      expect(packet.trace, ['A', 'B']);
      expect(packet.ttl, 19);
    });

    test('Should mark packet as DEAD if TTL reaches 0', () {
      var packet = MeshPacket(
          id: '1', 
          trace: const [], 
          ttl: 1,
          originatorId: 'A',
          packetType: MeshPacket.typeData,
          priority: MeshPacket.priorityMedium,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: ''
      );
      packet = packet.addHop('A'); // TTL becomes 0
      
      expect(packet.ttl, 0);
      expect(packet.isExpired, isTrue); // Verify domain logic
    });
  });
}
