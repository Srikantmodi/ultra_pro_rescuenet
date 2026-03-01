import 'package:get_it/get_it.dart';
import '../../features/mesh_network/data/datasources/local/cache/lru_cache.dart';
import '../../features/mesh_network/data/datasources/local/hive/boxes/outbox_box.dart';
import '../../features/mesh_network/data/datasources/remote/wifi_p2p_source.dart';
import '../../features/mesh_network/data/repositories/mesh_repository_impl.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../features/mesh_network/data/services/cloud_delivery_service.dart';
import '../../features/mesh_network/data/services/cloud_client.dart';
import '../../features/mesh_network/data/services/internet_probe.dart';
import '../../features/mesh_network/data/services/relay_orchestrator.dart';
import '../../features/mesh_network/presentation/bloc/mesh_bloc.dart';
import '../platform/location_manager.dart';

/// Mesh network module for dependency injection.
///
/// Registers all mesh network related dependencies.
class ModuleMesh {
  ModuleMesh._();

  /// Register all mesh network dependencies.
  static void register(GetIt sl) {
    // Data Sources
    sl.registerLazySingleton<WifiP2pSource>(() => WifiP2pSource());
    sl.registerLazySingleton<OutboxBox>(() => OutboxBox());
    sl.registerLazySingleton<SeenPacketCache>(() => SeenPacketCache());
    sl.registerLazySingleton<LocationManager>(() => LocationManager());
    sl.registerLazySingleton<InternetProbe>(() => InternetProbe());
    sl.registerLazySingleton<Battery>(() => Battery());
    sl.registerLazySingleton<CloudDeliveryService>(() => CloudDeliveryService());
    sl.registerLazySingleton<CloudClient>(
      () => CloudClient(outbox: sl<OutboxBox>()),
    );

    // Repository
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

    // Relay Orchestrator
    sl.registerLazySingleton<RelayOrchestrator>(
      () => RelayOrchestrator(
        wifiP2pSource: sl<WifiP2pSource>(),
        outbox: sl<OutboxBox>(),
        nodeId: '',
      ),
    );

    // BLoC
    sl.registerFactory<MeshBloc>(
      () => MeshBloc(
        repository: sl<MeshRepositoryImpl>(),
        relayOrchestrator: sl<RelayOrchestrator>(),
        internetProbe: sl<InternetProbe>(),
      ),
    );
  }
}
