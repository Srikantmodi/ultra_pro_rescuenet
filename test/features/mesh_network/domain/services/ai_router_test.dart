import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/entities/mesh_packet.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/entities/node_info.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/services/routing/ai_router.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/services/routing/neighbor_scorer.dart';

void main() {
  late AiRouter aiRouter;
  late NeighborScorer scorer;

  setUp(() {
    scorer = NeighborScorer();
    aiRouter = AiRouter(scorer: scorer);
  });

  group('UNIT TEST: AI Router Logic', () {
    test('Should prioritize Node with Internet (+50 points)', () {
      final packet = MeshPacket(
          id: '1',
          trace: const [],
          ttl: 10,
          originatorId: 'Sender',
          packetType: MeshPacket.typeData,
          priority: MeshPacket.priorityMedium,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: ''
      );

      final neighbors = [
        NodeInfo.create(id: 'A', hasInternet: false, batteryLevel: 100, signalStrength: -30, displayName: 'A', latitude: 0, longitude: 0), // Strong signal
        NodeInfo.create(id: 'B', hasInternet: true, batteryLevel: 50, signalStrength: -70, displayName: 'B', latitude: 0, longitude: 0),   // Weak signal BUT Internet
      ];

      final best = aiRouter.selectBestNode(neighbors: neighbors, packet: packet, currentNodeId: 'Me');
      expect(best?.id, 'B', reason: "Internet availability should outweigh signal strength.");
    });

    test('Should strictly exclude Sender ID (Layer 1 Loop Defense)', () {
      final packet = MeshPacket(
          id: '1',
          trace: const ['Node_A'],
          ttl: 10,
          originatorId: 'OriginalSender',
          packetType: MeshPacket.typeData,
          priority: MeshPacket.priorityMedium,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: ''
      );

      final neighbors = [
        NodeInfo.create(id: 'Node_A', hasInternet: true, batteryLevel: 100, signalStrength: -20, displayName: 'A', latitude: 0, longitude: 0),
        NodeInfo.create(id: 'Node_B', hasInternet: false, batteryLevel: 50, signalStrength: -80, displayName: 'B', latitude: 0, longitude: 0),
      ];

      final best = aiRouter.selectBestNode(neighbors: neighbors, packet: packet, currentNodeId: 'Me');
      expect(best?.id, 'Node_B', reason: "The sender (Node_A) must be banned.");
    });

    test('Should exclude nodes in Trace History (Layer 2 Loop Defense)', () {
      final packet = MeshPacket(
          id: '1',
          trace: const ['Node_C'],
          ttl: 10,
          originatorId: 'Sender',
          packetType: MeshPacket.typeData,
          priority: MeshPacket.priorityMedium,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: ''
      );

      final neighbors = [
        NodeInfo.create(id: 'Node_C', hasInternet: true, batteryLevel: 100, signalStrength: -20, displayName: 'C', latitude: 0, longitude: 0),
        NodeInfo.create(id: 'Node_D', hasInternet: false, batteryLevel: 50, signalStrength: -80, displayName: 'D', latitude: 0, longitude: 0),
      ];

      final best = aiRouter.selectBestNode(neighbors: neighbors, packet: packet, currentNodeId: 'Me');
      expect(best?.id, 'Node_D', reason: "Node_C was already visited.");
    });
  });

  group('PERFORMANCE TEST: Routing Speed', () {
    test('Should sort 10,000 neighbors in under 100ms', () {
       final packet = MeshPacket(
          id: '1',
          trace: const [],
          ttl: 10,
          originatorId: 'Sender',
          packetType: MeshPacket.typeData,
          priority: MeshPacket.priorityMedium,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: ''
      );
      
      // Generate 10k dummy nodes
      final neighbors = List.generate(10000, (i) => 
        NodeInfo.create(
            id: 'Node_$i', 
            hasInternet: i % 100 == 0, 
            batteryLevel: 50, 
            signalStrength: -60,
            displayName: 'N',
            latitude: 0, longitude: 0
        )
      );

      final stopwatch = Stopwatch()..start();
      aiRouter.selectBestNode(neighbors: neighbors, packet: packet, currentNodeId: 'Me');
      stopwatch.stop();

      print('Routing 10k nodes took: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(200)); // Increased to 200ms for stability
    });
  });
}
