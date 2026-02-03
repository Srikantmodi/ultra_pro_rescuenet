Write-Host "🚀 Initializing RescueNet Pro Structure..." -ForegroundColor Cyan

# Define the root path
$root = Get-Location

# Function to create directories
function MkDir($path) {
    $fullPath = Join-Path $root $path
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
        Write-Host "Created: $path" -ForegroundColor Gray
    }
}

# Function to create empty files
function Touch($path) {
    $fullPath = Join-Path $root $path
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType File -Force -Path $fullPath | Out-Null
    }
}

# --- 1. CORE LAYER ---
MkDir "lib\core\config"
MkDir "lib\core\constants"
MkDir "lib\core\di"
MkDir "lib\core\error"
MkDir "lib\core\network"
MkDir "lib\core\platform"
MkDir "lib\core\utils\extensions"

Touch "lib\core\config\app_config.dart"
Touch "lib\core\config\feature_flags.dart"
Touch "lib\core\constants\app_constants.dart"
Touch "lib\core\constants\network_constants.dart"
Touch "lib\core\constants\scoring_weights.dart"
Touch "lib\core\di\injection_container.dart"
Touch "lib\core\di\module_mesh.dart"
Touch "lib\core\error\failures.dart"
Touch "lib\core\error\exceptions.dart"
Touch "lib\core\error\error_handler.dart"
Touch "lib\core\network\network_info.dart"
Touch "lib\core\network\network_security.dart"
Touch "lib\core\platform\permission_manager.dart"
Touch "lib\core\platform\device_info_provider.dart"
Touch "lib\core\utils\packet_serializer.dart"
Touch "lib\core\utils\trace_validator.dart"
Touch "lib\core\utils\logger.dart"

# --- 2. DATA LAYER ---
MkDir "lib\features\mesh_network\data\datasources\local\hive\adapters"
MkDir "lib\features\mesh_network\data\datasources\local\hive\boxes"
MkDir "lib\features\mesh_network\data\datasources\local\cache"
MkDir "lib\features\mesh_network\data\datasources\remote\wifi_p2p\channels"
MkDir "lib\features\mesh_network\data\datasources\remote\wifi_p2p\managers"
MkDir "lib\features\mesh_network\data\datasources\remote\connectivity"
MkDir "lib\features\mesh_network\data\models"
MkDir "lib\features\mesh_network\data\repositories"

Touch "lib\features\mesh_network\data\datasources\local\hive\adapters\mesh_packet_adapter.dart"
Touch "lib\features\mesh_network\data\datasources\local\hive\adapters\node_info_adapter.dart"
Touch "lib\features\mesh_network\data\datasources\local\hive\boxes\outbox_box.dart"
Touch "lib\features\mesh_network\data\datasources\local\hive\boxes\inbox_box.dart"
Touch "lib\features\mesh_network\data\datasources\local\hive\boxes\seen_cache_box.dart"
Touch "lib\features\mesh_network\data\datasources\local\hive\boxes\qlearning_box.dart"
Touch "lib\features\mesh_network\data\datasources\local\hive\local_database.dart"
Touch "lib\features\mesh_network\data\datasources\local\cache\lru_cache.dart"
Touch "lib\features\mesh_network\data\datasources\local\cache\packet_deduplicator.dart"

Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\channels\discovery_channel.dart"
Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\channels\connection_channel.dart"
Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\channels\socket_channel.dart"
Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\managers\service_manager.dart"
Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\managers\group_manager.dart"
Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\managers\socket_manager.dart"
Touch "lib\features\mesh_network\data\datasources\remote\wifi_p2p\wifi_p2p_source.dart"
Touch "lib\features\mesh_network\data\datasources\remote\connectivity\internet_probe.dart"
Touch "lib\features\mesh_network\data\datasources\remote\connectivity\connectivity_monitor.dart"
Touch "lib\features\mesh_network\data\datasources\remote\connectivity\network_state_notifier.dart"

Touch "lib\features\mesh_network\data\models\mesh_packet_model.dart"
Touch "lib\features\mesh_network\data\models\node_metadata_model.dart"
Touch "lib\features\mesh_network\data\models\routing_table_model.dart"
Touch "lib\features\mesh_network\data\models\ack_packet_model.dart"
Touch "lib\features\mesh_network\data\repositories\mesh_repository_impl.dart"
Touch "lib\features\mesh_network\data\repositories\node_repository_impl.dart"
Touch "lib\features\mesh_network\data\repositories\routing_repository_impl.dart"

# --- 3. DOMAIN LAYER ---
MkDir "lib\features\mesh_network\domain\entities"
MkDir "lib\features\mesh_network\domain\repositories"
MkDir "lib\features\mesh_network\domain\services\routing"
MkDir "lib\features\mesh_network\domain\services\relay"
MkDir "lib\features\mesh_network\domain\services\validation"
MkDir "lib\features\mesh_network\domain\usecases\transmission"
MkDir "lib\features\mesh_network\domain\usecases\discovery"
MkDir "lib\features\mesh_network\domain\usecases\processing"

Touch "lib\features\mesh_network\domain\entities\mesh_packet.dart"
Touch "lib\features\mesh_network\domain\entities\node_info.dart"
Touch "lib\features\mesh_network\domain\entities\routing_entry.dart"
Touch "lib\features\mesh_network\domain\entities\packet_trace.dart"
Touch "lib\features\mesh_network\domain\entities\transmission_result.dart"

Touch "lib\features\mesh_network\domain\repositories\mesh_repository.dart"
Touch "lib\features\mesh_network\domain\repositories\node_repository.dart"
Touch "lib\features\mesh_network\domain\repositories\routing_repository.dart"

Touch "lib\features\mesh_network\domain\services\routing\ai_router.dart"
Touch "lib\features\mesh_network\domain\services\routing\neighbor_scorer.dart"
Touch "lib\features\mesh_network\domain\services\routing\route_optimizer.dart"
Touch "lib\features\mesh_network\domain\services\routing\qtable_updater.dart"
Touch "lib\features\mesh_network\domain\services\relay\relay_orchestrator.dart"
Touch "lib\features\mesh_network\domain\services\relay\packet_processor.dart"
Touch "lib\features\mesh_network\domain\services\relay\outbox_scheduler.dart"
Touch "lib\features\mesh_network\domain\services\relay\forwarding_strategy.dart"
Touch "lib\features\mesh_network\domain\services\validation\packet_validator.dart"
Touch "lib\features\mesh_network\domain\services\validation\loop_detector.dart"
Touch "lib\features\mesh_network\domain\services\validation\integrity_checker.dart"

Touch "lib\features\mesh_network\domain\usecases\transmission\broadcast_sos_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\transmission\relay_packet_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\transmission\acknowledge_packet_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\discovery\start_discovery_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\discovery\stop_discovery_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\discovery\update_metadata_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\processing\process_incoming_packet_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\processing\handle_duplicate_packet_usecase.dart"
Touch "lib\features\mesh_network\domain\usecases\processing\deliver_final_packet_usecase.dart"

# --- 4. PRESENTATION LAYER ---
MkDir "lib\features\mesh_network\presentation\bloc\mesh"
MkDir "lib\features\mesh_network\presentation\bloc\discovery"
MkDir "lib\features\mesh_network\presentation\bloc\transmission"
MkDir "lib\features\mesh_network\presentation\bloc\connectivity"
MkDir "lib\features\mesh_network\presentation\widgets\radar"
MkDir "lib\features\mesh_network\presentation\widgets\controls"
MkDir "lib\features\mesh_network\presentation\widgets\status"
MkDir "lib\features\mesh_network\presentation\widgets\lists"
MkDir "lib\features\mesh_network\presentation\pages"

Touch "lib\features\mesh_network\presentation\bloc\mesh\mesh_bloc.dart"
Touch "lib\features\mesh_network\presentation\bloc\mesh\mesh_event.dart"
Touch "lib\features\mesh_network\presentation\bloc\mesh\mesh_state.dart"
Touch "lib\features\mesh_network\presentation\bloc\discovery\discovery_bloc.dart"
Touch "lib\features\mesh_network\presentation\bloc\discovery\discovery_event.dart"
Touch "lib\features\mesh_network\presentation\bloc\discovery\discovery_state.dart"
Touch "lib\features\mesh_network\presentation\bloc\transmission\transmission_bloc.dart"
Touch "lib\features\mesh_network\presentation\bloc\transmission\transmission_event.dart"
Touch "lib\features\mesh_network\presentation\bloc\transmission\transmission_state.dart"
Touch "lib\features\mesh_network\presentation\bloc\connectivity\connectivity_bloc.dart"
Touch "lib\features\mesh_network\presentation\bloc\connectivity\connectivity_event.dart"
Touch "lib\features\mesh_network\presentation\bloc\connectivity\connectivity_state.dart"

Touch "lib\features\mesh_network\presentation\widgets\radar\radar_view.dart"
Touch "lib\features\mesh_network\presentation\widgets\radar\radar_painter.dart"
Touch "lib\features\mesh_network\presentation\widgets\radar\peer_marker.dart"
Touch "lib\features\mesh_network\presentation\widgets\controls\sos_button.dart"
Touch "lib\features\mesh_network\presentation\widgets\controls\discovery_toggle.dart"
Touch "lib\features\mesh_network\presentation\widgets\controls\relay_mode_switch.dart"
Touch "lib\features\mesh_network\presentation\widgets\status\signal_strength_bar.dart"
Touch "lib\features\mesh_network\presentation\widgets\status\battery_indicator.dart"
Touch "lib\features\mesh_network\presentation\widgets\status\internet_badge.dart"
Touch "lib\features\mesh_network\presentation\widgets\status\packet_counter.dart"
Touch "lib\features\mesh_network\presentation\widgets\lists\peer_list_tile.dart"
Touch "lib\features\mesh_network\presentation\widgets\lists\packet_log_item.dart"
Touch "lib\features\mesh_network\presentation\widgets\lists\route_trace_widget.dart"

Touch "lib\features\mesh_network\presentation\pages\dashboard_page.dart"
Touch "lib\features\mesh_network\presentation\pages\debug_console_page.dart"
Touch "lib\features\mesh_network\presentation\pages\settings_page.dart"
Touch "lib\features\mesh_network\presentation\pages\packet_history_page.dart"

# --- 5. NATIVE & TESTS ---
MkDir "android\app\src\main\kotlin\com\rescuenet\wifi"
MkDir "android\app\src\main\kotlin\com\rescuenet\utils"
MkDir "test\core"
MkDir "test\fixtures"
MkDir "test\features\mesh_network\data"
MkDir "test\features\mesh_network\domain\services"
MkDir "test\features\mesh_network\domain\usecases"
MkDir "integration_test"

Touch "android\app\src\main\kotlin\com\rescuenet\wifi\WifiP2pPlugin.kt"
Touch "android\app\src\main\kotlin\com\rescuenet\wifi\ServiceDiscoveryManager.kt"
Touch "android\app\src\main\kotlin\com\rescuenet\wifi\GroupNegotiationManager.kt"
Touch "android\app\src\main\kotlin\com\rescuenet\wifi\SocketTransportManager.kt"
Touch "android\app\src\main\kotlin\com\rescuenet\utils\PermissionHandler.kt"
Touch "android\app\src\main\kotlin\com\rescuenet\utils\NetworkUtils.kt"

Touch "test\core\utils_test.dart"
Touch "test\features\mesh_network\data\repositories_test.dart"
Touch "test\features\mesh_network\data\models_test.dart"
Touch "test\features\mesh_network\domain\services\ai_router_test.dart"
Touch "test\features\mesh_network\domain\services\relay_orchestrator_test.dart"
Touch "test\features\mesh_network\domain\usecases\broadcast_sos_usecase_test.dart"
Touch "test\fixtures\mesh_packet_fixture.dart"
Touch "test\fixtures\node_info_fixture.dart"
Touch "integration_test\mesh_network_flow_test.dart"
Touch "integration_test\wifi_p2p_connection_test.dart"

Write-Host "✅ Complete folder structure created successfully!" -ForegroundColor Green