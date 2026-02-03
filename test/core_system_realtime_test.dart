// File: test/core_system_realtime_test.dart
//
// This is the "Gold Standard" Real-Time Integration Test.
// It validates zero-latency reactions to neighbor discovery events.

import 'dart:async';
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
    aiRouter = AiRouter(scorer: scorer);
  });

  group('STRICT REAL-TIME SYSTEM VERIFICATION', () {
    
    // -----------------------------------------------------------------------
    // TEST 1: The "Zero-Latency" Goal Reaction
    // SCENARIO: 
    // 1. Packet is waiting for routing.
    // 2. A "Goal Node" (Internet) suddenly appears in the neighbor list.
    // 3. AI Router must select it INSTANTLY.
    // -----------------------------------------------------------------------
    test('VERIFY: Immediate Reaction to Goal Node Appearance', () async {
      // 1. Setup Data: A packet waiting for a route
      final pendingPacket = MeshPacket(
        id: 'sos_critical',
        originatorId: 'Phone_A',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Phone_A'],
        ttl: 20,
        payload: jsonEncode({'msg': 'Broken Leg'}),
      );

      // 2. EVENT: A neighbor walks into range (Node A: No Internet)
      // Expectation: AI should select it, but score will be lower
      final weakNeighbors = [
        NodeInfo.create(
          id: 'Node_A',
          displayName: 'Weak Relay',
          hasInternet: false,
          batteryLevel: 50,
          signalStrength: -80,
          latitude: 0,
          longitude: 0,
        ),
      ];

      final weakDecision = aiRouter.selectBestNode(
        neighbors: weakNeighbors,
        packet: pendingPacket,
        currentNodeId: 'Phone_B',
      );

      // Should select Node_A as it's the only option
      expect(weakDecision?.id, 'Node_A');
      print('📡 Weak neighbor selected: ${weakDecision?.displayName}');

      // 3. EVENT: A Goal Node walks into range (Node Goal: Has Internet)
      // Expectation: AI should see "+50" score and select it immediately.
      final goalNode = NodeInfo.create(
        id: 'Node_Goal',
        displayName: 'Goal Node',
        hasInternet: true, // <--- CRITICAL
        batteryLevel: 90,
        signalStrength: -60,
        latitude: 0,
        longitude: 0,
      );

      print("⚡ Simulating Goal Node Appearance...");
      
      // Start Stopwatch for Performance Check
      final stopwatch = Stopwatch()..start();

      // Now neighbors include both weak node and goal node
      final allNeighbors = [weakNeighbors[0], goalNode];
      
      final goalDecision = aiRouter.selectBestNode(
        neighbors: allNeighbors,
        packet: pendingPacket,
        currentNodeId: 'Phone_B',
      );

      stopwatch.stop();

      // 4. STRICT VERIFICATION
      // Did it select the Goal Node?
      expect(goalDecision?.id, 'Node_Goal',
          reason: "FAIL: AI did not prioritize the Goal Node!");
      expect(goalDecision?.hasInternet, isTrue,
          reason: "FAIL: Selected node doesn't have internet!");

      // 5. Performance Check
      print("⏱️ Goal Selection Time: ${stopwatch.elapsedMicroseconds}μs");
      expect(stopwatch.elapsedMilliseconds, lessThan(10),
          reason: "FAIL: Selection took too long!");

      print("✅ PASS: System reacted instantly to Goal Node discovery.");
      print("   Selected: ${goalDecision?.displayName} (has internet: ${goalDecision?.hasInternet})");
    });

    // -----------------------------------------------------------------------
    // TEST 2: The "Loop & Latency" Guard
    // SCENARIO: 
    // 1. Neighbor is the Sender (Loop Risk).
    // 2. Neighbor is in trace history (Already visited).
    // 3. Valid Neighbor exists.
    // CHECK: Sender/Visited are ignored. Processing time < 100ms.
    // -----------------------------------------------------------------------
    test('VERIFY: Loop Prevention & Processing Speed', () async {
      final packet = MeshPacket(
        id: 'sos_002',
        originatorId: 'Bad_Sender',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Bad_Sender', 'Visited_Node'],
        ttl: 15,
        payload: jsonEncode({'msg': 'Help'}),
      );

      final neighbors = [
        // 1. The Loop Risk (In trace history) - Should be IGNORED
        NodeInfo.create(
          id: 'Bad_Sender',
          displayName: 'Sender (Loop Risk)',
          hasInternet: true,
          batteryLevel: 100,
          signalStrength: -30,
          latitude: 0,
          longitude: 0,
        ),
        
        // 2. Already Visited Node (In trace) - Should be IGNORED
        NodeInfo.create(
          id: 'Visited_Node',
          displayName: 'Already Visited',
          hasInternet: true,
          batteryLevel: 100,
          signalStrength: -30,
          latitude: 0,
          longitude: 0,
        ),
        
        // 3. The Valid Target - Should be SELECTED
        NodeInfo.create(
          id: 'Valid_Target',
          displayName: 'Fresh Node',
          hasInternet: false,
          batteryLevel: 80,
          signalStrength: -50,
          latitude: 0,
          longitude: 0,
        ),
      ];

      // Start Stopwatch for Performance Check
      final stopwatch = Stopwatch()..start();

      // Execute AI Decision
      final decision = aiRouter.selectBestNode(
        neighbors: neighbors,
        packet: packet,
        currentNodeId: 'Phone_B',
      );

      stopwatch.stop();

      // VERIFY: Did we avoid the loop risks?
      expect(decision?.id, isNot('Bad_Sender'),
          reason: "CRITICAL FAILURE: AI selected the sender (infinite loop created)!");
      expect(decision?.id, isNot('Visited_Node'),
          reason: "FAILURE: AI selected an already-visited node (loop risk)!");

      // VERIFY: Did we select the valid target?
      expect(decision?.id, 'Valid_Target',
          reason: "FAILURE: AI did not select the only valid target!");

      // VERIFY: Performance
      print("⏱️ Processing Time: ${stopwatch.elapsedMilliseconds}ms");
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: "FAIL: Latency too high (>100ms)!");
      
      print("✅ PASS: Loops blocked. Latency minimal.");
      print("   Selected: ${decision?.displayName}");
      print("   Avoided: Bad_Sender, Visited_Node");
    });

    // -----------------------------------------------------------------------
    // TEST 3: Stream-Based Real-Time Neighbor Updates
    // SCENARIO: 
    // Simulates real-world neighbor discovery stream.
    // Neighbors appear/disappear dynamically.
    // AI must adapt in real-time.
    // -----------------------------------------------------------------------
    test('VERIFY: Real-Time Stream-Based Neighbor Discovery', () async {
      final packet = MeshPacket(
        id: 'sos_stream',
        originatorId: 'Sender',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Sender'],
        ttl: 20,
        payload: jsonEncode({'msg': 'Stream Test'}),
      );

      // Create a stream controller to simulate neighbor discovery
      final neighborStream = StreamController<List<NodeInfo>>.broadcast();
      final decisions = <NodeInfo?>[];

      // Listen to neighbor updates and make routing decisions
      neighborStream.stream.listen((neighbors) {
        if (neighbors.isNotEmpty) {
          final decision = aiRouter.selectBestNode(
            neighbors: neighbors,
            packet: packet,
            currentNodeId: 'Me',
          );
          decisions.add(decision);
          print('📡 Neighbors updated: ${neighbors.length} nodes, Selected: ${decision?.displayName ?? "none"}');
        }
      });

      // PHASE 1: No neighbors (empty radar)
      print('\n--- PHASE 1: Empty Radar ---');
      neighborStream.add([]);
      await Future.delayed(const Duration(milliseconds: 10));
      
      // PHASE 2: Weak relay appears
      print('\n--- PHASE 2: Weak Relay Appears ---');
      neighborStream.add([
        NodeInfo.create(
          id: 'Weak_Relay',
          displayName: 'Weak Relay',
          hasInternet: false,
          batteryLevel: 30,
          signalStrength: -85,
          latitude: 0,
          longitude: 0,
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 10));

      // PHASE 3: Goal node appears (should immediately switch)
      print('\n--- PHASE 3: Goal Node Appears! ---');
      final goalNode = NodeInfo.create(
        id: 'Goal',
        displayName: 'Goal Node',
        hasInternet: true,
        batteryLevel: 90,
        signalStrength: -50,
        latitude: 0,
        longitude: 0,
      );
      
      final stopwatch = Stopwatch()..start();
      neighborStream.add([goalNode]);
      await Future.delayed(const Duration(milliseconds: 10));
      stopwatch.stop();

      // Verify decisions were made
      expect(decisions.length, greaterThanOrEqualTo(2),
          reason: "Should have made at least 2 routing decisions");

      // Verify last decision selected the goal node
      final lastDecision = decisions.last;
      expect(lastDecision?.id, 'Goal',
          reason: "Final decision should select the Goal node!");
      expect(lastDecision?.hasInternet, isTrue,
          reason: "Selected node must have internet!");

      print("\n⏱️ Stream Reaction Time: ${stopwatch.elapsedMilliseconds}ms");
      print("✅ PASS: Real-time stream adaptation successful!");
      print("   Total decisions made: ${decisions.length}");
      print("   Final selection: ${lastDecision?.displayName} (Internet: ${lastDecision?.hasInternet})");

      await neighborStream.close();
    });

    // -----------------------------------------------------------------------
    // TEST 4: High-Throughput Stress Test
    // SCENARIO: 
    // Process 1000 routing decisions rapidly.
    // Verify performance remains under threshold.
    // -----------------------------------------------------------------------
    test('VERIFY: High-Throughput Performance (1000 decisions)', () async {
      final packet = MeshPacket(
        id: 'stress_test',
        originatorId: 'Sender',
        packetType: MeshPacket.typeSos,
        priority: MeshPacket.priorityCritical,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        trace: const ['Sender'],
        ttl: 20,
        payload: jsonEncode({'msg': 'Stress Test'}),
      );

      // Generate 100 neighbors
      final neighbors = List.generate(100, (i) => 
        NodeInfo.create(
          id: 'Node_$i',
          displayName: 'Node $i',
          hasInternet: i % 10 == 0, // Every 10th node has internet
          batteryLevel: 50 + (i % 50),
          signalStrength: -40 - (i % 40),
          latitude: 0,
          longitude: 0,
        ),
      );

      print('\n🔥 Starting stress test: 1000 routing decisions...');
      final stopwatch = Stopwatch()..start();

      // Make 1000 routing decisions
      for (int i = 0; i < 1000; i++) {
        final decision = aiRouter.selectBestNode(
          neighbors: neighbors,
          packet: packet,
          currentNodeId: 'Me',
        );
        
        // Verify decision is valid
        expect(decision, isNotNull, reason: "Decision $i failed!");
        expect(decision!.id, isNot('Sender'), reason: "Loop detected at decision $i!");
      }

      stopwatch.stop();

      final totalTime = stopwatch.elapsedMilliseconds;
      final avgTime = totalTime / 1000;

      print('⏱️ Total Time: ${totalTime}ms');
      print('⏱️ Average Time per Decision: ${avgTime.toStringAsFixed(2)}ms');
      print('⏱️ Decisions per Second: ${(1000000 / stopwatch.elapsedMicroseconds).toStringAsFixed(0)}');

      // Performance thresholds
      expect(totalTime, lessThan(5000),
          reason: "FAIL: 1000 decisions took too long (>5s)!");
      expect(avgTime, lessThan(5),
          reason: "FAIL: Average decision time too high (>5ms)!");

      print('✅ PASS: High-throughput stress test successful!');
    });
  });
}
