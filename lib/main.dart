import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:get_it/get_it.dart';
import 'features/mesh_network/data/datasources/local/cache/lru_cache.dart';
import 'features/mesh_network/data/datasources/local/hive/boxes/outbox_box.dart';
import 'features/mesh_network/data/datasources/remote/wifi_p2p_source.dart';
import 'features/mesh_network/data/repositories/mesh_repository_impl.dart';
import 'package:battery_plus/battery_plus.dart';
import 'features/mesh_network/data/services/cloud_delivery_service.dart';
import 'features/mesh_network/data/services/internet_probe.dart';
import 'features/mesh_network/data/services/relay_orchestrator.dart';
import 'features/mesh_network/presentation/bloc/mesh_bloc.dart';
import 'features/mesh_network/presentation/pages/home_page.dart';
import 'core/platform/location_manager.dart';
import 'core/theme/app_theme.dart';

final getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0D0D1A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Initialize Hive
    await Hive.initFlutter();

    // Initialize dependency injection
    await _initDependencies();

    runApp(const RescueNetApp());
  } catch (e, stackTrace) {
    // If initialization fails, show error screen
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: $e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Try to restart
                    SystemNavigator.pop();
                  },
                  child: const Text('Close App'),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    
    // Print error for debugging
    debugPrint('Initialization error: $e');
    debugPrint('Stack trace: $stackTrace');
  }
}

/// Initializes all dependencies for the app.
Future<void> _initDependencies() async {
  // Data sources
  getIt.registerLazySingleton<WifiP2pSource>(() => WifiP2pSource());
  getIt.registerLazySingleton<OutboxBox>(() => OutboxBox());
  getIt.registerLazySingleton<SeenPacketCache>(() => SeenPacketCache());
  getIt.registerLazySingleton<LocationManager>(() => LocationManager());
  getIt.registerLazySingleton<InternetProbe>(() => InternetProbe());
  getIt.registerLazySingleton<Battery>(() => Battery());
  getIt.registerLazySingleton<CloudDeliveryService>(() => CloudDeliveryService());

  // Repository (depends on above)
  getIt.registerLazySingleton<MeshRepositoryImpl>(
    () => MeshRepositoryImpl(
      wifiP2pSource: getIt<WifiP2pSource>(),
      outbox: getIt<OutboxBox>(),
      seenCache: getIt<SeenPacketCache>(),
      locationManager: getIt<LocationManager>(),
      internetProbe: getIt<InternetProbe>(),
      battery: getIt<Battery>(),
      cloudDeliveryService: getIt<CloudDeliveryService>(),
    ),
  );

  // Relay Orchestrator
  getIt.registerLazySingleton<RelayOrchestrator>(
    () => RelayOrchestrator(
      wifiP2pSource: getIt<WifiP2pSource>(),
      outbox: getIt<OutboxBox>(),
      nodeId: '', // Will be set during initialization
    ),
  );

  // MeshBloc - factory since it may be recreated
  getIt.registerFactory<MeshBloc>(
    () => MeshBloc(
      repository: getIt<MeshRepositoryImpl>(),
      relayOrchestrator: getIt<RelayOrchestrator>(),
      internetProbe: getIt<InternetProbe>(),
    ),
  );
}

/// Root widget for RescueNet Pro application.
class RescueNetApp extends StatelessWidget {
  const RescueNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MeshBloc>(
      create: (context) => getIt<MeshBloc>(),
      child: MaterialApp(
        title: 'RescueNet Pro',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const HomePage(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return AppTheme.darkTheme;
  }
}
