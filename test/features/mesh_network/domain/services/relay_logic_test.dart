// File: test/features/mesh_network/domain/services/relay_logic_test.dart

import 'dart:convert';
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
    aiRouter = AiRouter(scorer: scorer); // The "Brain"
  });

  group('Relay Node (Phone B) Intelligent Routing Verification', () {
    
    // -----------------------------------------------------------------------
    // SCENARIO 1: Standard Relay Operation
    // Phone B receives SOS from Phone A.
    // Neighbors: A (Sender), C (Goal/Internet), D (Weak Relay).
    // EXPECTATION: Ignore A. Select C automatically.
    // -----------------------------------------------------------------------
    test('VERIFY: Sender Exclusion & Goal Node Prioritization', () {
      // 1. Simulate Incoming Packet from Sender A
      final packet = MeshPacket(
        id: 'sos_001',
        originatorId: 'Phone_A',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Phone_A'], // History: Created by A
        ttl: 20,
        payload: jsonEncode({'msg': 'Help'}),
      );

      // 2. Simulate Real-Time Neighbor Discovery (The "Radar")
      final neighbors = [
        // Phone A: Strong signal, BUT it sent the packet. (MUST EXCLUDE)
        NodeInfo.create(
          id: 'Phone_A', 
          displayName: 'Sender A',
          batteryLevel: 90, 
          hasInternet: false, 
          signalStrength: -40, // Very close/strong
          latitude: 0, longitude: 0
        ),
        
        // Phone D: A random relay node. No internet.
        NodeInfo.create(
          id: 'Phone_D', 
          displayName: 'Relay D',
          batteryLevel: 50, 
          hasInternet: false, 
          signalStrength: -70,
          latitude: 0, longitude: 0
        ),
        
        // Phone C: The Goal Node. Has Internet. (MUST SELECT)
        NodeInfo.create(
          id: 'Phone_C', 
          displayName: 'Goal C',
          batteryLevel: 60, 
          hasInternet: true, // <--- THE GOLDEN TICKET
          signalStrength: -65,
          latitude: 0, longitude: 0
        ),
      ];

      // 3. Execute AI Decision
      print("\n--- TEST 1: Relay Decision ---");
      // Note: We act as 'Phone_B' here
      final bestNode = aiRouter.selectBestNode(
        neighbors: neighbors, 
        packet: packet, 
        currentNodeId: 'Phone_B'
      );

      // 4. Assertions (The "Proof")
      
      // Check Loop Prevention
      expect(bestNode?.id, isNot('Phone_A'), 
        reason: "CRITICAL FAILURE: AI selected the Sender (Phone_A). Infinite loop created.");

      // Check Optimization
      expect(bestNode?.id, equals('Phone_C'), 
        reason: "FAILURE: AI failed to prioritize the Internet-connected Goal Node.");

      print("✅ PASS: Ignored Sender (A). Auto-selected Goal Node (C).");
    });

    // -----------------------------------------------------------------------
    // SCENARIO 2: Trace History Loop Prevention
    // Phone B receives packet.
    // Neighbors: E (Strong Signal).
    // BUT: Packet trace shows it visited E 2 hops ago (A -> E -> B).
    // EXPECTATION: Ignore E to prevent "Circle of Death".
    // -----------------------------------------------------------------------
    test('VERIFY: Trace History Loop Exclusion', () {
      // 1. Packet with history
      final packet = MeshPacket(
        id: 'sos_002',
        originatorId: 'Phone_A',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Phone_A', 'Phone_E'], // Visited A, then E. (Now at B)
        ttl: 18,
        payload: '',
      );

      // 2. Neighbors
      final neighbors = [
        // Phone E: Strong signal, but is in the TRACE history.
        NodeInfo.create(
          id: 'Phone_E', 
          displayName: 'Visited E',
          batteryLevel: 100, 
          hasInternet: false, 
          signalStrength: -30, // Strong signal
          latitude: 0, longitude: 0
        ),
        
        // Phone F: Weaker signal, but fresh.
        NodeInfo.create(
          id: 'Phone_F', 
          displayName: 'Fresh F',
          batteryLevel: 50, 
          hasInternet: false, 
          signalStrength: -80, // Weak signal
          latitude: 0, longitude: 0
        ),
      ];

      // 3. Execute
      print("\n--- TEST 2: History Check ---");
      final bestNode = aiRouter.selectBestNode(
        neighbors: neighbors, 
        packet: packet,
        currentNodeId: 'Phone_B'
      );

      // 4. Assertions
      expect(bestNode?.id, isNot('Phone_E'), 
        reason: "FAILURE: AI selected a node found in the Trace history.");
      
      expect(bestNode?.id, equals('Phone_F'), 
        reason: "FAILURE: Should have selected Phone_F as the only valid option.");

      print("✅ PASS: Ignored Visited Node (E). Selected Fresh Node (F).");
    });

    // -----------------------------------------------------------------------
    // SCENARIO 3: Goal Node Self-Recognition
    // I am Phone C. I have Internet. I receive a packet.
    // EXPECTATION: Do NOT forward. Terminate and Store.
    // -----------------------------------------------------------------------
    test('VERIFY: Goal Node Termination', () {
      // 1. My Status (Live check from ConnectivityService)
      // Represented by passing 'currentNodeHasInternet: true' to the router check
      bool amIConnectedToInternet = true; 

      // 2. Incoming Packet
      final packet = MeshPacket(
        id: 'sos_003',
        originatorId: 'Phone_A',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Phone_A', 'Phone_B'],
        ttl: 15,
        payload: '',
      );

      print("\n--- TEST 3: Goal Node Logic ---");
      
      // The Logic to Test: AiRouter.shouldDeliverHere
      bool shouldDeliver = aiRouter.shouldDeliverHere(
        packet: packet, 
        currentNodeHasInternet: amIConnectedToInternet
      );
      
      bool shouldForward = !shouldDeliver;

      // 3. Assertions
      expect(shouldDeliver, isTrue, 
        reason: "FAILURE: Goal Node failed to recognize itself as the destination.");
      
      expect(shouldForward, isFalse, 
        reason: "FAILURE: Goal Node tried to relay packet instead of stopping.");

      print("✅ PASS: Goal Node recognized itself. Hopping Stopped.");
    });
  });
}
