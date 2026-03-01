import 'package:battery_plus/battery_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/mesh_network/data/datasources/local/cache/lru_cache.dart';
import '../../features/mesh_network/data/datasources/local/hive/boxes/outbox_box.dart';
import '../../features/mesh_network/data/datasources/remote/wifi_p2p_source.dart';
import '../../features/mesh_network/data/repositories/mesh_repository_impl.dart';
import '../../features/mesh_network/data/services/internet_probe.dart';
import '../../features/mesh_network/data/services/cloud_delivery_service.dart';
import '../../features/mesh_network/data/services/cloud_client.dart';
import '../../features/mesh_network/data/services/relay_orchestrator.dart';
import '../../features/mesh_network/presentation/bloc/mesh_bloc.dart';
import '../platform/location_manager.dart';

/// Global dependency injection container.
final GetIt sl = GetIt.instance;

/// Initializes all dependencies.
Future<void> initDependencies() async {
  // Initialize Hive
  await Hive.initFlutter();

  // Register all modules
  await _registerCoreDependencies();
  await _registerDataSources();
  await _registerRepositories();
  await _registerBlocs();
}

/// Register core platform dependencies.
Future<void> _registerCoreDependencies() async {
  sl.registerLazySingleton<LocationManager>(() => LocationManager());


  sl.registerLazySingleton<InternetProbe>(() => InternetProbe());
  sl.registerLazySingleton<Battery>(() => Battery());
  sl.registerLazySingleton<CloudDeliveryService>(() => CloudDeliveryService());
  sl.registerLazySingleton<CloudClient>(
    () => CloudClient(outbox: sl<OutboxBox>()),
  );
}

/// Register data sources.
Future<void> _registerDataSources() async {
  sl.registerLazySingleton<WifiP2pSource>(() => WifiP2pSource());
  sl.registerLazySingleton<OutboxBox>(() => OutboxBox());
  sl.registerLazySingleton<SeenPacketCache>(() => SeenPacketCache());
}

/// Register repositories.
Future<void> _registerRepositories() async {
  sl.registerLazySingleton<MeshRepositoryImpl>(
    () => MeshRepositoryImpl(
      wifiP2pSource: sl<WifiP2pSource>(),
      outbox: sl<OutboxBox>(),
      seenCache: sl<SeenPacketCache>(),

      locationManager: sl<LocationManager>(),
      internetProbe: sl<InternetProbe>(),
      battery: sl<Battery>(),
      cloudDeliveryService: sl<CloudDeliveryService>(),
      cloudClient: sl<CloudClient>(),
    ),
  );
}

/// Register BLoCs.
Future<void> _registerBlocs() async {
  // Register RelayOrchestrator first
  sl.registerLazySingleton<RelayOrchestrator>(
    () => RelayOrchestrator(
      wifiP2pSource: sl<WifiP2pSource>(),
      outbox: sl<OutboxBox>(),
      nodeId: '', // Will be set during initialization
    ),
  );

  // MeshBloc as factory (can be recreated)
  sl.registerFactory<MeshBloc>(
    () => MeshBloc(
      repository: sl<MeshRepositoryImpl>(),
      relayOrchestrator: sl<RelayOrchestrator>(),
      internetProbe: sl<InternetProbe>(),
    ),
  );
}

/// Reset all dependencies (for testing).
Future<void> resetDependencies() async {
  await sl.reset();
}
