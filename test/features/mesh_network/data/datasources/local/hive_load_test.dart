import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/data/models/mesh_packet_model.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/entities/mesh_packet.dart';

void main() {
  group('LOAD TEST: Hive Persistence', () {
    late Box<String> outbox;

    setUpAll(() async {
      // Use a temporary directory for Hive in tests
      Hive.init('./test_hive_db'); 
      outbox = await Hive.openBox<String>('test_outbox');
    });

    tearDownAll(() async {
      try {
        if (outbox.isOpen) {
          await outbox.close();
        }
        await outbox.deleteFromDisk();
      } catch (e) {
        // Ignore cleanup errors in tests
      }
    });

    test('Should handle High-Throughput Write/Read (1,000 packets)', () async {
      final stopwatch = Stopwatch()..start();

      // WRITE
      for (int i = 0; i < 1000; i++) {
        final packet = MeshPacketModel(
            id: '$i', 
            trace: const [], 
            ttl: 20, 
            payload: '{}',
            originatorId: 'Test',
            packetType: MeshPacket.typeData,
            priority: MeshPacket.priorityMedium,
            timestamp: DateTime.now().millisecondsSinceEpoch
        );
        await outbox.put(packet.id, packet.toJsonString());
      }
      stopwatch.stop();
      final writeTime = stopwatch.elapsedMilliseconds;
      print('Write 1000 packets: ${writeTime}ms');

      // READ
      stopwatch.reset();
      stopwatch.start();
      final allPackets = outbox.values.toList();
      stopwatch.stop();
      final readTime = stopwatch.elapsedMilliseconds;
      print('Read 1000 packets: ${readTime}ms');

      expect(allPackets.length, 1000);
      
      // Performance Checks
      expect(writeTime, lessThan(1000), reason: "Writing 1k packets took too long!");
      expect(readTime, lessThan(500), reason: "Reading 1k packets took too long!");
    });
  });
}
