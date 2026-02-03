import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/data/datasources/remote/wifi_p2p_source.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/data/repositories/mesh_repository_impl.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/data/services/internet_probe.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/data/services/relay_orchestrator.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/entities/node_info.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/domain/entities/sos_payload.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/presentation/bloc/mesh/mesh_bloc.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/presentation/bloc/mesh/mesh_event.dart';
import 'package:ultra_pro_rescuenet/features/mesh_network/presentation/bloc/mesh/mesh_state.dart';

// ============================================================================
// MANUAL MOCK CLASSES
// ============================================================================

/// Mock implementation of MeshRepositoryImpl for testing.
class MockMeshRepositoryImpl implements MeshRepositoryImpl {
  bool sendSosCalled = false;
  bool sendSosSuccess = true;
  Exception? sendSosException;
  
  bool initializeCalled = false;
  bool startDiscoveryCalled = false;
  bool stopDiscoveryCalled = false;
  
  final _neighborsController = StreamController<List<NodeInfo>>.broadcast();
  final _packetsController = StreamController<ReceivedPacket>.broadcast();

  @override
  Stream<List<NodeInfo>> get neighborsStream => _neighborsController.stream;

  @override
  Stream<ReceivedPacket> get packetsStream => _packetsController.stream;

  @override
  Future<Either<Failure, void>> initialize({required String nodeId}) async {
    initializeCalled = true;
    return const Right(null);
  }

  @override
  Future<void> startDiscovery() async {
    startDiscoveryCalled = true;
  }

  @override
  Future<void> stopDiscovery() async {
    stopDiscoveryCalled = true;
  }

  @override
  Future<Either<Failure, String>> sendSos(SosPayload sos) async {
    sendSosCalled = true;
    if (sendSosException != null) {
      throw sendSosException!;
    }
    if (sendSosSuccess) {
      return Right('mock-packet-id-${DateTime.now().millisecondsSinceEpoch}');
    } else {
      return Left(UnexpectedFailure('Mock send failure'));
    }
  }

  @override
  Future<void> broadcastMetadata(Map<String, String> metadata) async {}

  // Other required interface methods (stubs)
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void mockDispose() {
    _neighborsController.close();
    _packetsController.close();
  }
}

/// Mock implementation of RelayOrchestrator for testing.
class MockRelayOrchestrator implements RelayOrchestrator {
  bool startCalled = false;
  bool stopCalled = false;

  @override
  void start() {
    startCalled = true;
  }

  @override
  void stop() {
    stopCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mock implementation of InternetProbe for testing.
class MockInternetProbe implements InternetProbe {
  bool startProbingCalled = false;
  bool stopProbingCalled = false;
  bool hasInternetResult = true;
  
  final _connectivityController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectivityStream => _connectivityController.stream;

  @override
  void startProbing() {
    startProbingCalled = true;
  }

  @override
  void stopProbing() {
    stopProbingCalled = true;
  }

  @override
  Future<bool> checkConnectivity({bool forceRefresh = false}) async {
    return hasInternetResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void mockDispose() {
    _connectivityController.close();
  }
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

void main() {
  group('INTEGRATION TEST: SOS Flow', () {
    late MeshBloc meshBloc;
    late MockMeshRepositoryImpl mockRepository;
    late MockRelayOrchestrator mockRelayOrchestrator;
    late MockInternetProbe mockInternetProbe;

    setUp(() {
      mockRepository = MockMeshRepositoryImpl();
      mockRelayOrchestrator = MockRelayOrchestrator();
      mockInternetProbe = MockInternetProbe();

      meshBloc = MeshBloc(
        repository: mockRepository,
        relayOrchestrator: mockRelayOrchestrator,
        internetProbe: mockInternetProbe,
      );
    });

    tearDown(() {
      meshBloc.close();
      mockRepository.mockDispose();
      mockInternetProbe.mockDispose();
    });

    test('Initial state is MeshState with inactive status', () {
      expect(meshBloc.state.status, equals(MeshStatus.inactive));
    });

    blocTest<MeshBloc, MeshState>(
      'Emits state with incremented packetsSent when SOS is successfully sent',
      build: () {
        mockRepository.sendSosSuccess = true;
        return meshBloc;
      },
      act: (bloc) {
        final sosPayload = SosPayload.create(
          sosId: 'test-sos-001',
          senderId: 'node-123',
          senderName: 'Test User',
          latitude: 37.7749,
          longitude: -122.4194,
          emergencyType: EmergencyType.medical,
          additionalNotes: 'Integration test SOS',
        );
        bloc.add(SendSos(sosPayload));
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<MeshState>().having(
          (state) => state.statistics.packetsSent,
          'packetsSent',
          1,
        ),
      ],
      verify: (_) {
        expect(mockRepository.sendSosCalled, isTrue);
      },
    );

    blocTest<MeshBloc, MeshState>(
      'Emits error state when SOS sending fails',
      build: () {
        mockRepository.sendSosException = Exception('Network timeout');
        return meshBloc;
      },
      act: (bloc) {
        final sosPayload = SosPayload.create(
          sosId: 'test-sos-002',
          senderId: 'node-123',
          senderName: 'Test User',
          latitude: 37.7749,
          longitude: -122.4194,
          emergencyType: EmergencyType.medical,
          additionalNotes: 'Integration test SOS failure',
        );
        bloc.add(SendSos(sosPayload));
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<MeshState>().having(
          (state) => state.error,
          'error',
          contains('Failed to send SOS'),
        ),
      ],
    );

    blocTest<MeshBloc, MeshState>(
      'Emits [initializing, inactive] when mesh is initialized successfully',
      build: () {
        mockInternetProbe.hasInternetResult = true;
        return meshBloc;
      },
      act: (bloc) => bloc.add(InitializeMesh()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<MeshState>().having(
          (state) => state.status,
          'status',
          MeshStatus.initializing,
        ),
        isA<MeshState>()
            .having((state) => state.status, 'status', MeshStatus.inactive)
            .having((state) => state.currentNode, 'currentNode', isNotNull),
      ],
      verify: (_) {
        expect(mockRepository.initializeCalled, isTrue);
      },
    );

    blocTest<MeshBloc, MeshState>(
      'Emits active state when mesh is started successfully',
      build: () => meshBloc,
      act: (bloc) => bloc.add(StartMesh()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<MeshState>()
            .having((state) => state.status, 'status', MeshStatus.active)
            .having((state) => state.isRelaying, 'isRelaying', true),
      ],
      verify: (_) {
        expect(mockRepository.startDiscoveryCalled, isTrue);
        expect(mockRelayOrchestrator.startCalled, isTrue);
        expect(mockInternetProbe.startProbingCalled, isTrue);
      },
    );

    blocTest<MeshBloc, MeshState>(
      'Emits inactive state when mesh is stopped',
      build: () => meshBloc,
      act: (bloc) => bloc.add(StopMesh()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<MeshState>()
            .having((state) => state.status, 'status', MeshStatus.inactive)
            .having((state) => state.isRelaying, 'isRelaying', false),
      ],
      verify: (_) {
        expect(mockRepository.stopDiscoveryCalled, isTrue);
        expect(mockRelayOrchestrator.stopCalled, isTrue);
        expect(mockInternetProbe.stopProbingCalled, isTrue);
      },
    );

    group('Full SOS Pipeline Integration', () {
      blocTest<MeshBloc, MeshState>(
        'Complete flow: Initialize -> Start -> Send SOS -> Verify stats',
        build: () {
          mockInternetProbe.hasInternetResult = true;
          mockRepository.sendSosSuccess = true;
          return meshBloc;
        },
        act: (bloc) async {
          // 1. Initialize the mesh
          bloc.add(InitializeMesh());
          await Future.delayed(const Duration(milliseconds: 150));

          // 2. Start the mesh network
          bloc.add(StartMesh());
          await Future.delayed(const Duration(milliseconds: 150));

          // 3. Send SOS
          final sosPayload = SosPayload.create(
            sosId: 'full-flow-sos',
            senderId: 'node-full',
            senderName: 'Full Flow Test',
            latitude: 37.7749,
            longitude: -122.4194,
            emergencyType: EmergencyType.fire,
            additionalNotes: 'Full pipeline test',
          );
          bloc.add(SendSos(sosPayload));
        },
        wait: const Duration(milliseconds: 500),
        expect: () => [
          // State 1: Initializing
          isA<MeshState>().having(
            (s) => s.status,
            'status',
            MeshStatus.initializing,
          ),
          // State 2: Initialized (inactive with node)
          isA<MeshState>()
              .having((s) => s.status, 'status', MeshStatus.inactive)
              .having((s) => s.currentNode, 'currentNode', isNotNull),
          // State 3: Active (mesh started)
          isA<MeshState>()
              .having((s) => s.status, 'status', MeshStatus.active)
              .having((s) => s.isRelaying, 'isRelaying', true),
          // State 4: SOS sent (stats updated)
          isA<MeshState>().having(
            (s) => s.statistics.packetsSent,
            'packetsSent',
            1,
          ),
        ],
        verify: (_) {
          // Verify the complete pipeline was executed
          expect(mockRepository.initializeCalled, isTrue);
          expect(mockRepository.startDiscoveryCalled, isTrue);
          expect(mockRelayOrchestrator.startCalled, isTrue);
          expect(mockRepository.sendSosCalled, isTrue);
        },
      );
    });
  });
}
