# RescueNet Pro — Root-Level Bug Analysis & Implementation Plan

## SECTION 1: CONFIRMED BUGS (Root-Cause Evidence)

### BUG-01 ✦ CRITICAL — Discovery Never Produces TXT Records
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/WifiP2pHandler.kt` (line ~271)  
**Root Cause:** `startDiscoveryPersistent()` calls `discoverPeers()` *before* `discoverServices()`. Android's Wi-Fi P2P framework can only run **one** active scan at a time. `discoverPeers()` holds the scan slot; when `discoverServices()` is immediately called next, the framework returns error code `2` (`BUSY`) and silently aborts service scan. Result: the `DnsSdTxtRecordListener` **never fires**. `nodeId` in every service event is `null`. In `_handleServicesFound()` the guard `if (nodeId == null || deviceAddress.isEmpty) continue` drops every discovered node. The neighbor list stays empty forever.

**Secondary compounding factor:** `peerDiscoveryTimer` fires every 20 seconds and calls `discoverPeers()` again, which cancels any `discoverServices()` scan that miraculously managed to start. Discovery never stabilises.

---

### BUG-02 ✦ CRITICAL — SOS Is Silently Dropped (Sender Never Enters MeshActive)
**File:** `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart` (line ~327), `lib/features/mesh_network/presentation/pages/sos_form_page.dart` (line ~50)  
**Root Cause:** `_onSendSos()` has an explicit guard:
```dart
if (currentState is! MeshActive) {
  print('🚨 MeshBloc: State is NOT MeshActive, ignoring SOS');
  return;
}
```
When Device A (Survivor) opens the SOS form from `HomePage`, the app calls `MeshInitialize` in `initState`. This transitions state to `MeshReady`, **never `MeshActive`**. `MeshStart` is only dispatched from `RelayModePage._onRelayToggled()`. A Survivor who never opens Relay Mode stays in `MeshReady` forever. Every `MeshSendSos` event is silently discarded. No packet is created. No forwarding happens.

---

### BUG-03 ✦ CRITICAL — Goal-Node Identity Never Propagates to Peers
**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`, `lib/features/mesh_network/data/datasources/remote/wifi_p2p_source.dart`  
**Root Cause:** `_buildNodeMetadata()` correctly sets `'net': hasInternet ? '1' : '0'` and `'rol': hasInternet ? 'g' : 'r'`. The problem is what happens when connectivity **changes after** the node started. `_ConnectivityChanged` fires in the BLoC and updates `state.hasInternet` in Flutter, but **never calls `updateMetadata()` on the repository**. `updateMetadata()` calls `wifiP2pSource.startBroadcasting()`, which logs `"startBroadcasting() is now a no-op"` and returns. The native TXT record is **never re-registered** with the new metadata. Other relay nodes keep routing with the old `net=0` value. The Goal Node never gets selected.

---

### BUG-04 ✦ HIGH — `SERVICE_TYPE` Missing `.local.` Suffix
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/WifiP2pHandler.kt` (line ~36)  
**Root Cause:** Constant is `"_rescuenet._tcp"`. Android's `WifiP2pDnsSdServiceInfo` SDK expects the type to end in `".local."` per the DNS-SD RFC. On stock Android this is auto-appended, but on Samsung One UI and Pixel with custom DNS-SD stacks it is not, causing registration to succeed but discovery to return 0 results. Must be `"_rescuenet._tcp.local."` consistently across `newInstance()` registration and filtering.

---

### BUG-05 ✦ HIGH — ConnectionManager Group-Owner Self-Connection
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/ConnectionManager.kt` (line ~95)  
**Root Cause:**
```kotlin
val targetIp = if (info.isGroupOwner) {
    Log.w(TAG, "⚠️ We became group owner unexpectedly")
    "192.168.49.1"   // ← THIS IS OUR OWN IP
}
```
When `groupOwnerIntent = 0` is set on the sender and the P2P negotiation grants GO role to the sender anyway (negotiated based on device capabilities), `info.isGroupOwner == true`. The code then tries to connect TCP to `192.168.49.1:8888`, which is the **sender's own socket server**. The sender's socket server accepts the loopback connection, echoes an ACK, and logs "Packet received" — from itself. The receiver (Device B) gets nothing. The `result.success = true` is a false positive.

---

### BUG-06 ✦ HIGH — Relay Incoming Packets Not Persisted to Outbox
**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`  
**Root Cause:** In `_processIncomingPacket()`, after parsing the relay packet, `_handleForwardOrDeliver()` is called which tries `_forwardPacket()` immediately. If no neighbor is currently available, the function returns `false`. The packet is **not added to the outbox**. The `RelayOrchestrator` never sees it. There is zero retry for transit packets. One Wi-Fi scan gap = permanent packet loss in the relay chain.

---

### BUG-07 ✦ HIGH — Stale Node Eviction Races with Discovery Refresh
**File:** `lib/features/mesh_network/data/datasources/remote/wifi_p2p_source.dart` (line ~398), `lib/features/mesh_network/domain/entities/node_info.dart` (line ~131)  
**Root Cause:** The cache cleanup in `cleanStaleNodes()` removes any node not seen in **60 seconds**. `NodeInfo.isStale` (used by the AI scoring layer to penalise nodes) uses **2 minutes**. Discovery refresh fires every 15 seconds, so in theory nodes should be refreshed every cycle. But with BUG-01 active, TXT records don't arrive — nodes added once get evicted in 60 seconds. Even without BUG-01, the 60-second eviction is more aggressive than needed and will drop valid nodes during discovery gaps.

---

### BUG-08 ✦ HIGH — `updateMetadata()` is a No-Op in the Data Layer  
**File:** `lib/features/mesh_network/data/datasources/remote/wifi_p2p_source.dart` (line ~219)  
**Root Cause:** `startBroadcasting()` calls `updateMetadata()` on the native side — but the native `updateMetadata()` method calls `clearLocalServices()` and re-registers. This path *is* implemented. The real bug is that `_onConnectivityChanged` in the BLoC updates `state.hasInternet` but **never dispatches `MeshUpdateMetadata`**, so `updateMetadata()` on the repository is never triggered.

The chain exists:
```dart
Future<void> updateMetadata() async {
  if (_nodeId == null) return;
  final metadata = await _buildNodeMetadata();
  await _wifiP2pSource.startBroadcasting(nodeId: _nodeId!, metadata: metadata);
}
```
And `startBroadcasting`:
```dart
Future<void> startBroadcasting({required String nodeId, required Map<String, String> metadata}) async {
  final fullMetadata = Map<String, String>.from(metadata);
  fullMetadata['id'] = nodeId;
  await updateMetadata(fullMetadata);
}
```
This calls the native `updateMetadata` properly. **The actual bug** is that `_onConnectivityChanged` in the BLoC updates `state.hasInternet` but **never dispatches `MeshUpdateMetadata`**, so `updateMetadata()` on the repository is never triggered.

---

### BUG-09 ✦ MEDIUM — Discovery Refresh Resets Listeners Mid-Discovery
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/WifiP2pHandler.kt` (line ~358)  
**Root Cause:** `discoveryRefreshTimer` fires every 15 seconds and calls `setupDnsSdListeners()` then `discoverServices()`. `setDnsSdResponseListeners()` overwrites the active listener with a new lambda. If a TXT record is in-flight at the moment of the reset, the callback arrives on the old sink reference (now orphaned) and is never processed.

---

### BUG-10 ✦ MEDIUM — Signal Strength Hardcoded; AI Routing Is Blind
**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`  
**Root Cause:**
```dart
'sig': '-50',  // Still approximated
```
Every broadcast node advertises `-50 dBm`. The scoring formula `weightSignal * neighbor.normalizedSignal` yields the same value for all nodes. Effectively, 10 of the 85 scoring points are wasted. The AI Router cannot differentiate between a node 2 metres away and one 40 metres away.

---

### BUG-11 ✦ MEDIUM — Node ID Regenerated on Every App Restart
**File:** `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart` (bloc-level)  
**Root Cause:**
```dart
final nodeId = const Uuid().v4();
```
The top-level `bloc/mesh_bloc.dart` (which is what UI imports) generates a new UUID on **every `MeshInitialize` event**. Every app restart creates a different node ID. This means relay nodes cannot recognize a previously seen device after restart, preventing re-use of known routing paths. The inner `bloc/mesh/mesh_bloc.dart` correctly uses `DeviceInfoProvider.getDeviceId()`, but that file is not imported by the UI.

---

### BUG-12 ✦ MEDIUM — MeshService Foreground Service Has No BroadcastReceiver
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/MeshService.kt`, `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/MainActivity.kt` (line ~65)  
**Root Cause:** All Wi-Fi P2P broadcasts (`WIFI_P2P_PEERS_CHANGED_ACTION`, `WIFI_P2P_CONNECTION_CHANGED_ACTION`) are received only in `MainActivity`. When the app is backgrounded (user presses Home), `MainActivity.onPause()` doesn't unregister the receiver, but Android can kill the process or restrict broadcast delivery. `MeshService` is the correct place to register for P2P broadcasts for background relay operation. Currently `MeshService` only holds a wake lock and shows a notification — it has no P2P functionality.

---

### BUG-13 ✦ MEDIUM — WakeLock Acquired With No Timeout
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/MeshService.kt` (line ~22)  
**Root Cause:** `wakeLock?.acquire()` with no timeout parameter holds the CPU wake lock indefinitely. If the app crashes without calling `onDestroy()`, the wake lock is orphaned and keeps draining battery until reboot. Android recommends `acquire(timeoutMs)`.

---

### BUG-14 ✦ LOW — `clearServiceRequests()` Not Called Before Re-adding in Refresh Loop
**File:** `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/WifiP2pHandler.kt` (line ~273)  
**Root Cause:** Every time `startDiscoveryPersistent()` runs (including on refresh), `addServiceRequest()` is called without first calling `clearServiceRequests()`. The framework accumulates duplicate service requests, which can confuse the discovery engine on Samsung devices.

---

### BUG-15 ✦ LOW — `OutboxEntry.maxRetries` and Orchestrator Limits Are Inconsistent
**File:** `lib/features/mesh_network/data/datasources/local/hive/boxes/outbox_box.dart` (line ~18), `lib/features/mesh_network/data/services/relay_orchestrator.dart` (line ~32)  
**Root Cause:** `OutboxBox.maxRetries = 5` but `RelayOrchestrator.maxConsecutiveFailures = 3`. After 3 consecutive failures the orchestrator pauses — but individually each packet is allowed 5 tries. These limits conflict and can cause packets to be retried longer than intended.

---

## SECTION 2: IMPLEMENTATION PLAN (Phased)

---

### PHASE A — Native Android Layer Fixes (Kotlin)
*All changes in `android/app/src/main/kotlin/com/example/ultra_pro_rescuenet/`*  
*Purpose: Fix the root cause of discovery failure and connection self-loop*

| # | Fix | File | Description |
|---|-----|------|-------------|
| A-1 | **Fix SERVICE_TYPE** | `WifiP2pHandler.kt` | Change constant to `"_rescuenet._tcp.local."`. Update the `instanceName.contains("RescueNet")` and `fullDomainName.contains("rescuenet")` filters to also match the `.local.` variant |
| A-2 | **Fix discovery sequence** | `WifiP2pHandler.kt` | In `startDiscoveryPersistent()`: remove the `discoverPeers()` call entirely. The new sequence must be: `clearServiceRequests()` → `addServiceRequest()` → `discoverServices()`. `discoverServices()` internally triggers peer discovery. This alone fixes BUG-01 |
| A-3 | **Remove peerDiscoveryTimer** | `WifiP2pHandler.kt` | Delete `peerDiscoveryTimer` and its `Timer` declaration and the `PEER_DISCOVERY_INTERVAL_MS` constant. Remove its `cancel()` calls in `stopMeshNode()` and `cleanup()`. Only keep `discoveryRefreshTimer` |
| A-4 | **Fix refresh timer: don't reset listeners** | `WifiP2pHandler.kt` | In `discoveryRefreshTimer`'s `run()` block: remove the `setupDnsSdListeners()` call. Only call `clearServiceRequests()` → `addServiceRequest()` → `discoverServices()`. Move `setupDnsSdListeners()` to be called ONCE in `setup()` only |
| A-5 | **Fix ConnectionManager group-owner race** | `ConnectionManager.kt` | When `info.isGroupOwner == true`, do NOT use `"192.168.49.1"`. Instead call `manager.requestGroupInfo(channel)` to get the group's client list and use the first connected client's `deviceAddress`. If no clients yet, retry `requestConnectionInfo()`. Add a new code path: if after all retries we are still GO with no clients, call `manager.removeGroup()` and return `onFailure("Became unexpected group owner")` so the relay orchestrator can retry |
| A-6 | **Add `clearServiceRequests()` before re-adding** | `WifiP2pHandler.kt` | In `startDiscoveryPersistent()` and in the refresh timer block, always call `manager.clearServiceRequests()` before `manager.addServiceRequest()`. Use a callback chain to ensure ordering |
| A-7 | **Move BroadcastReceiver to MeshService** | `MeshService.kt`, `MainActivity.kt` | Add a `WifiP2pBroadcastReceiver` inner class to `MeshService`. Register it in `MeshService.onCreate()` for `WIFI_P2P_STATE_CHANGED_ACTION`, `WIFI_P2P_PEERS_CHANGED_ACTION`, `WIFI_P2P_CONNECTION_CHANGED_ACTION`. Feed `WIFI_P2P_CONNECTION_CHANGED_ACTION` events through an `Intent` broadcast or `LocalBroadcastManager` to `WifiP2pHandler`. This enables background relay operation |
| A-8 | **Fix wake lock timeout** | `MeshService.kt` | Change `wakeLock?.acquire()` to `wakeLock?.acquire(TimeUnit.HOURS.toMillis(4))` (4-hour max). Add `wakeLock?.let { if (it.isHeld) it.release() }` in `onTaskRemoved()` as well as `onDestroy()` |
| A-9 | **Connection-changed intent drives ConnectionManager** | `MainActivity.kt`, `ConnectionManager.kt` | Instead of polling `requestConnectionInfo()` every second, make `ConnectionManager` expose a `onP2pConnectionChanged(info: WifiP2pInfo)` callback. Wire `MainActivity`'s `WIFI_P2P_CONNECTION_CHANGED_ACTION` receiver to call this. If `info.groupFormed == true`, fulfill the pending connection immediately. Keep the polling as a 10-second fallback only |
| A-10 | **Filter service request by type** | `WifiP2pHandler.kt` | Change `WifiP2pDnsSdServiceRequest.newInstance()` to `WifiP2pDnsSdServiceRequest.newInstance(SERVICE_TYPE)`. This reduces noise from non-RescueNet P2P services on crowded channels |

---

### PHASE B — Flutter Data & Service Layer Fixes (Dart)
*Purpose: Fix the SOS-sender path, stale node mismatch, and relay persistence*

| # | Fix | File | Description |
|---|-----|------|-------------|
| B-1 | **Auto-start mesh node when SOS form opens** | `sos_form_page.dart`, `mesh_bloc.dart` | In `SosFormPage.initState()`, dispatch `MeshStart` if the current BLoC state is `MeshReady` (not yet `MeshActive`). Wait for the state to become `MeshActive` before enabling the "Send SOS" button. This ensures Device A has an active mesh node, starts discovery, and can find Device B before attempting to send |
| B-2 | **Set SOS sender node role to `sender` in metadata** | `mesh_repository_impl.dart` | Add a `_currentRole` field to the repository. When the module is started from the SOS path, set `rol: 's'` (sender). Discovery by others is still possible since the mesh is started — other relay nodes can see the sender node but its metadata correctly marks it as a survivor |
| B-3 | **Fix metadata update chain for connectivity changes** | `mesh_bloc.dart` | In `_onConnectivityChanged()`, after updating state, dispatch `MeshUpdateMetadata`. In `_onUpdateMetadata()`, call `await _repository.updateMetadata()`. This triggers the native `updateMetadata()` → re-registers TXT record with `net=1` → other nodes learn this is now a goal node. Also call `updateMetadata` when `MeshStart` completes |
| B-4 | **Persist incoming relay packets to outbox** | `mesh_repository_impl.dart` | In `_processIncomingPacket()`, after emitting the SOS to the UI stream but before calling `_handleForwardOrDeliver()`, add the **updated packet** (with current hop added) to the outbox. Then attempt `_forwardPacket()` immediately. If forwarding succeeds, call `_outbox.markSent(packet.id)`. If it fails, leave in outbox for `RelayOrchestrator` to retry within 10 seconds. Add a `_seenCache.markAsSeen()` call before adding to prevent the orchestrator from re-processing a packet it just sent successfully |
| B-5 | **Align stale node timeouts** | `wifi_p2p_source.dart`, `node_info.dart` | Choose one stale timeout: **2 minutes** for both. Change `cleanStaleNodes()` from `> 60` seconds to `> 120` seconds. Change `NodeInfo.staleTimeoutMinutes` to remain `2`. Keep stale cleanup running every 60 seconds (fine for a 2-minute window) |
| B-6 | **Replace random UUID with persistent device ID** | `mesh_bloc.dart` (bloc-level) | In the top-level `bloc/mesh_bloc.dart`'s `_onInitialize()`, replace `const Uuid().v4()` with `await DeviceInfoProvider.getDeviceId()`. This already exists in `core/platform/device_info_provider.dart` and is used in `bloc/mesh/mesh_bloc.dart`. Also remove the duplicate inner `mesh_bloc.dart` or consolidate to one |
| B-7 | **Add real Wi-Fi RSSI to metadata** | `mesh_repository_impl.dart`, `WifiP2pHandler.kt` | Add an Android method `getRssi()` or use `WIFI_P2P_PEERS_CHANGED_ACTION`'s `WifiP2pDevice.status` to approximate signal quality. Alternatively, use `WifiManager.calculateSignalLevel()` on the associated AP. Expose it via a new method channel call `getSignalStrength()`. Use the result in `_buildNodeMetadata()` to populate `sig` with a real value |
| B-8 | **Fix `OutboxBox.maxRetries` + orchestrator alignment** | `outbox_box.dart`, `relay_orchestrator.dart` | Set `OutboxBox.maxRetries = 3` to match `RelayOrchestrator.maxConsecutiveFailures`. Add a packet-level retry counter display in relay log so testers can see retry state. After max retries, emit a `RelayActivity.expired` so upstream knows the packet is being dropped |

---

### PHASE C — Flutter Presentation Layer Fixes (Dart)
*Purpose: Fix the UI state checks and survivor flow*

| # | Fix | File | Description |
|---|-----|------|-------------|
| C-1 | **Fix SOS form's neighbor scanning** | `sos_form_page.dart` | Change `if (state is MeshActive)` to check the sealed class hierarchy correctly. `SosFormPage._scanDevices()` must use a `BlocListener` that reacts to `MeshActive` state changes and refreshes `_nearbyDevices = state.neighbors`. Add a `CircularProgressIndicator` while `state is MeshLoading` |
| C-2 | **SOS send button conditional enabling** | `sos_form_page.dart` | Disable the "SEND EMERGENCY SOS" button until: (a) state is `MeshActive`, and (b) form is valid. Show a status badge: "Connecting to mesh..." → "Mesh active (N nodes found)" → "Ready to send" |
| C-3 | **Add automatic mesh start on home screen** | `home_page.dart` | Dispatch `MeshStart` immediately after `MeshInitialize` completes (state becomes `MeshReady`). This means ALL device roles begin discovery as soon as the app opens, matching real-world behaviour where a relay node or responder should always be listening |
| C-4 | **Relay Mode page start/stop wiring** | `relay_mode_page.dart` | Verify that tapping "Start Relay" dispatches `MeshStart` and tapping "Stop Relay" dispatches `MeshStop`. Confirm button label toggles are bound to `state is MeshActive` not a local `_isRelaying` boolean, which can desync from actual BLoC state |
| C-5 | **Responder Mode: auto-enter MeshActive** | `responder_mode_page.dart` | When the Responder Mode page opens, if state is `MeshReady`, dispatch `MeshStart`. The responder must be in mesh to receive SOS packets routed to it |
| C-6 | **Debug console: live Logcat relay** | `debug_console_page.dart` | Wire `RelayOrchestrator.activity` stream to the debug console so every relay attempt, selection, send success/fail appears in real time inside the app. This makes field testing without ADB possible |

---

### PHASE D — Architecture & Reliability Hardening
*Purpose: Make the mesh robust in real-world conditions*

| # | Fix | Files | Description |
|---|-----|-------|-------------|
| D-1 | **Consolidated discovery timer (single timer)** | `WifiP2pHandler.kt` | Replace all three timers (`discoveryRefreshTimer`, `peerDiscoveryTimer`, `serviceUpdateTimer`) with ONE `Timer` at `30-second` intervals. Each tick: `clearServiceRequests()` → `addServiceRequest()` → `discoverServices()`. This eliminates all interference between timers |
| D-2 | **P2P group cleanup before new connections** | `WifiP2pHandler.kt`, `ConnectionManager.kt` | Before calling `manager.connect()`, always call `manager.removeGroup()` and wait for `onSuccess()`/`onFailure()` callback. This clears any residual P2P group from previous connections that blocks new group formation. This is the most common real-device group formation failure |
| D-3 | **Receiver side: SocketServer bind to P2P interface** | `SocketServerManager.kt` | When starting the socket server, detect whether the device is the P2P Group Owner (has IP `192.168.49.1`). If so, bind `ServerSocket` to that specific IP instead of `0.0.0.0`. On non-GO devices, keep `0.0.0.0`. This prevents routing ambiguity on multi-interface devices |
| D-4 | **Connection timeout externalised** | `ConnectionManager.kt` | Replace the hardcoded `maxAttempts = 15` (15 seconds) with a configurable timeout constant. Expose it to Flutter via method channel so test duration can be adjusted without rebuilding. Default: 10 seconds |
| D-5 | **Re-discover after successful packet send** | `WifiP2pHandler.kt` | After a `connectAndSend()` completes (group removed in `disconnect()`), immediately restart `discoverServices()`. The P2P disconnect clears the channel state; without immediate re-discovery, new peers take 15-30 seconds to reappear |
| D-6 | **MeshService: full Wi-Fi P2P integration** | `MeshService.kt` | Move `WifiP2pManager` init, `WifiP2pHandler`, and `BroadcastReceiver` into `MeshService`. `MainActivity` should delegate ALL P2P work to `MeshService` via AIDL or `LocalBroadcastManager`. This ensures relay continues when app is backgrounded or screen off |
| D-7 | **Internet probe uses multiple methods** | `internet_probe.dart` | Current DNS lookup approach (`InternetAddress.lookup`) can block or return cached results. Supplement with an HTTP HEAD request to `http://connectivitycheck.gstatic.com/generate_204`. If HTTP returns 204, internet is confirmed. Fall back to DNS only if HTTP fails. This prevents false-positive goal-node identification |
| D-8 | **Packet integrity check** | `wifi_p2p_source.dart`, `SocketServerManager.kt` | Add a CRC32 checksum to the 4-byte header, making the wire format 8 bytes: `[4-byte size][4-byte CRC32]`. Receiver validates checksum before ACK. This catches truncated packets and avoids JSON parse exceptions in `_processIncomingPacket` |

---

### PHASE E — Testing & Validation Infrastructure
*Purpose: Make the test workflow (from the spec) executable*

| # | Fix | Description |
|---|-----|-------------|
| E-1 | **ADB Logcat filter script** | Create a `scripts/logcat_filter.bat` that runs `adb -s $DEVICE logcat -v time WifiP2pHandler:D ConnectionManager:D SocketServer:D flutter:I *:S`. One script per device with correct ADB serial argument |
| E-2 | **Diagnostic page shows live discovery events** | Wire `WifiP2pSource.discoveredNodes` and `wifiP2pState` streams into `DiagnosticPage`. Show: node cache size, last TXT record received, last discovery refresh time, outbox count, relay cycle count |
| E-3 | **TTL test mode** | Add a developer setting in `AppConfig` that sets `MeshPacket.defaultTtl` to 3 for TEST-5 without rebuilding the app. Expose in `SettingsPage` behind a developer toggle |
| E-4 | **Packet history page** | `PacketHistoryPage` should show all packets from outbox (pending, sent, failed) with retry count, timestamp, hop trace, and TTL. Wire the `OutboxBox` values stream directly to the page |
| E-5 | **Integration test harness** | Implement `integration_test/wifi_p2p_connection_test.dart`: launch app → init mesh → verify `WifiP2pSource.initialize()` returns `true` → verify socket server logged start on port 8888. Implement `integration_test/mesh_network_flow_test.dart`: mock native channel → inject fake `servicesFound` event → verify neighbor appears in state → dispatch `MeshSendSos` → verify outbox has one entry |

---

## SECTION 3: Bug Impact/Priority Matrix

| BUG | Area | Discovery | SOS Transfer | Relay | Priority |
|-----|------|-----------|--------------|-------|----------|
| BUG-01 | Native | ❌ Kills it | ❌ No neighbors | ❌ No route | **P0** |
| BUG-02 | Flutter | ✓ | ❌ Silent drop | ✓ | **P0** |
| BUG-03 | Flutter | ✓ | ✓ | ❌ Goal never selected | **P0** |
| BUG-05 | Native | ✓ | ❌ Self-connect | ✓ | **P1** |
| BUG-04 | Native | ⚠️ OEM-specific | ✓ | ⚠️ | **P1** |
| BUG-06 | Flutter | ✓ | ✓ | ❌ Transit packet lost | **P1** |
| BUG-07 | Flutter | ⚠️ | ✓ | ⚠️ | **P2** |
| BUG-08 | Flutter | ✓ | ✓ | ⚠️ | **P2** |
| BUG-09 | Native | ⚠️ | ✓ | ✓ | **P2** |
| BUG-11 | Flutter | ⚠️ | ✓ | ⚠️ | **P2** |
| BUG-12 | Native | ✓ | ✓ | ❌ Background | **P2** |
| BUG-10 | Flutter | ✓ | ✓ | ⚠️ suboptimal | **P3** |
| BUG-13 | Native | ✓ | ✓ | ⚠️ battery | **P3** |

---

## SECTION 4: Minimum Viable Fix Set for TEST-1 → WORKFLOW-A

To make the test workflow runnable end-to-end, the **minimum changes** in sequence order:

1. **A-2** (fix discovery sequence — single change, one file, maximum impact)
2. **A-3** (remove peerDiscoveryTimer — prevents re-breaking fixed discovery)
3. **A-4** (fix refresh: no listener reset mid-discovery)
4. **A-6** (clearServiceRequests before each cycle)
5. **B-1** (auto-start mesh on SOS form open — survivor enters MeshActive)
6. **A-5** (fix group-owner self-connect in ConnectionManager)
7. **D-2** (removeGroup before new connection — prevents "BUSY" on re-connections)
8. **B-3** (connectivity → updateMetadata → goal-node identity propagates)
9. **B-4** (persist incoming relay packets to outbox — no lost transit packets)
10. **D-5** (restart discovery after each send — keeps mesh alive between transmissions)

These 10 changes cover BUG-01, BUG-02, BUG-03, BUG-05, and BUG-06 — the five bugs that make TEST-1 through WORKFLOW-A completely non-functional. All remaining bugs from Phase B–E improve reliability, performance, and edge-case handling for TEST-4 through TEST-14.
