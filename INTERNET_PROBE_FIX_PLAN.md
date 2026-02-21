# Internet Probe & False Goal-Node Fix Plan

## Executive Summary

**Critical Bug:** Device D1 (OPPO, `6XOZ9X599HB6RKCA`) had NO internet (mobile data OFF, WiFi router disconnected), yet when D2 (Redmi) sent an SOS, the packet was routed to D1's "I Can Help" (Responder/Goal) section. The SOS terminated there, thinking it reached a goal node. This is a **mesh-killing false positive** — the packet dies at a node that can't actually deliver it to the cloud.

---

## Root Cause Analysis (5 Layers Deep)

### Layer 1: `InternetAddress.lookup()` for IP Literals Is a No-Op

The `InternetProbe._probeEndpoints` list contains:
```dart
static const List<String> _probeEndpoints = [
  'google.com',
  'cloudflare.com',
  '8.8.8.8',     // ← IP literal
  '1.1.1.1',     // ← IP literal
];
```

For each endpoint, `_probeEndpoint()` calls `_tryDnsLookup(endpoint)`:
```dart
final result = await InternetAddress.lookup(host).timeout(_probeTimeout);
return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
```

**The bug:** `InternetAddress.lookup('8.8.8.8')` in Dart does NOT perform a DNS query for IP literals. It immediately parses the IP address and returns a valid `InternetAddress` with non-empty `rawAddress`. **This always returns `true` regardless of network state.**

Since `_probeConnectivity()` uses `results.any((result) => result)` across all 4 endpoints, and at least 2 endpoints (`8.8.8.8`, `1.1.1.1`) always return `true` via the DNS path, **the probe permanently reports `hasInternet = true`**.

### Layer 2: Fallback Chain Short-Circuits on False Positive

`_probeEndpoint()` tries three methods in order:
```
1. _tryHttpHead()         → HTTP 204 check (RELIABLE ✓)
2. _tryDnsLookup(endpoint) → DNS lookup     (FALSE POSITIVE for IPs ✗)
3. _trySocketConnection()  → TCP socket     (never reached)
```

When `_tryHttpHead()` fails (no real internet), `_tryDnsLookup('8.8.8.8')` immediately returns `true`. The probe concludes "internet is available" without ever performing a real network operation.

### Layer 3: `_updateConnectivity` Only Fires on CHANGE

```dart
void _updateConnectivity(bool hasInternet) {
  _lastProbeTime = DateTime.now();
  if (_hasInternet != hasInternet) {    // ← only on change
    _hasInternet = hasInternet;
    _connectivityController.add(hasInternet);
  }
}
```

Since the probe always returns `true` (Layer 1), `_hasInternet` was set to `true` on the very first probe after `startProbing()` and the stream **never fires `false`**. The BLoC's `_ConnectivityChanged` event is never triggered with `false`, so `MeshActive.hasInternet` stays permanently `true`.

### Layer 4: SOS Routing Uses Stale Cached Getter

In `_processIncomingPacket()`, the GOAL/RELAY decision reads:
```dart
if (_internetProbe.hasInternet) {
  _sosReceivedController.add(receivedSos);  // GOAL stream → "I Can Help"
} else {
  _relayedSosController.add(receivedSos);   // RELAY stream → Relay Mode
}
```

`hasInternet` is a simple getter (`bool get hasInternet => _hasInternet`) returning the permanently-`true` cached value. It does NOT force a fresh probe. So even if the user turned off internet 10 minutes ago, this check passes.

### Layer 5: Cloud Delivery Is Mocked → No Safety Net

```dart
if (_internetProbe.hasInternet && packet.isSos) {
  final result = await _cloudDeliveryService.uploadSos(...);
  if (result.isRight()) {
    return;  // ← STOPS forwarding! Packet terminates here.
  }
}
```

`CloudDeliveryService.uploadSos()` is a MOCK that always returns `Right(true)` after a 2-second delay. It never actually attempts an HTTP POST. So the packet is "delivered" to a fake cloud endpoint, and forwarding stops. **The SOS dies here forever.**

---

## Chain of Failure (Execution Trace)

```
1. App starts → InternetProbe.startProbing() → checkConnectivity()
2. _probeConnectivity() probes 4 endpoints in parallel
3. For '8.8.8.8': _tryHttpHead() fails → _tryDnsLookup('8.8.8.8') → TRUE (IP literal)
4. results.any() returns TRUE → _updateConnectivity(true)
5. _hasInternet = true, stream fires TRUE, BLoC sets hasInternet=true
6. User disables mobile data and WiFi
7. Next probe: _tryDnsLookup('8.8.8.8') → still TRUE (IP literal doesn't need network)
8. _updateConnectivity(true) → no change → stream doesn't fire → BLoC stays hasInternet=true
9. SOS arrives via P2P from Redmi
10. _processIncomingPacket: _internetProbe.hasInternet → true (stale!)
11. SOS emitted to GOAL stream → "I Can Help" UI shows it
12. _handleForwardOrDeliver: _internetProbe.hasInternet → true (stale!)
13. cloudDeliveryService.uploadSos() → MOCK SUCCESS → forwarding STOPS
14. Packet is DEAD. Never reaches internet. Mesh breaks.
```

---

## Fix Plan (6 Phases)

### Phase 1: Fix InternetProbe — Eliminate False Positives

**File:** `lib/features/mesh_network/data/services/internet_probe.dart`

**Problem:** IP literals in `_probeEndpoints` defeat DNS checks. DNS should never be authoritative.

**Changes:**

1. **Remove IP literals from probe endpoints list**
```dart
// BEFORE (broken):
static const List<String> _probeEndpoints = [
  'google.com', 'cloudflare.com', '8.8.8.8', '1.1.1.1',
];

// AFTER (fixed):
static const List<String> _probeEndpoints = [
  'google.com',
  'cloudflare.com',
];
```

2. **Make `_probeEndpoint()` use ONLY HTTP HEAD as authority — remove DNS/socket fallbacks**

The current 3-step chain (`HTTP → DNS → Socket`) has two unreliable fallbacks. Since `_tryHttpHead()` to `connectivitycheck.gstatic.com/generate_204` definitively proves internet access, it should be the **sole authority**. DNS and socket are supplementary at best and deceptive at worst.

```dart
// AFTER: Each endpoint probed via actual HTTP only
Future<bool> _probeEndpoint(String endpoint) async {
  try {
    return await _tryHttpConnectivityCheck(endpoint);
  } catch (e) {
    return false;
  }
}
```

3. **Add multiple HTTP check URLs for redundancy**
```dart
static const List<String> _httpCheckUrls = [
  'http://connectivitycheck.gstatic.com/generate_204',     // Google
  'http://connectivity-check.ubuntu.com/',                  // Ubuntu (200)
  'http://www.msftconnecttest.com/connecttest.txt',         // Microsoft
];
```

The probe tries these URLs. If ANY returns the expected status code, internet is confirmed. This handles the unlikely scenario where Google's URL is blocked.

4. **Shorten timings for faster detection of connectivity loss**
```dart
static const Duration _normalProbeInterval = Duration(seconds: 30);   // was 60
static const Duration _offlineProbeInterval = Duration(seconds: 10);  // was 15
static const Duration _probeTimeout = Duration(seconds: 4);           // was 5
static const Duration _cacheDuration = Duration(seconds: 10);         // was 30
```

5. **Always update `_lastProbeTime` AND `_hasInternet` even when value doesn't change — but only fire STREAM on change**
This ensures `_isCacheValid` is always current.

---

### Phase 2: Add Real-Time Connectivity Check Before Critical Decisions

**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`

**Problem:** SOS routing and cloud delivery use `_internetProbe.hasInternet` (cached getter) without forcing a fresh probe.

**Changes:**

1. **In `_processIncomingPacket()`: Force-refresh before GOAL/RELAY routing**
```dart
// BEFORE (stale cached value):
if (_internetProbe.hasInternet) {

// AFTER (fresh real-time check):
final hasInternet = await _internetProbe.checkConnectivity(forceRefresh: true);
if (hasInternet) {
```

2. **In `_handleForwardOrDeliver()`: Force-refresh before cloud delivery decision**
```dart
// BEFORE:
if (_internetProbe.hasInternet && packet.isSos) {

// AFTER:
final hasInternet = await _internetProbe.checkConnectivity(forceRefresh: true);
if (hasInternet && packet.isSos) {
```

This adds ~2-4 seconds to SOS processing (the HTTP check timeout), but **correctness is non-negotiable** for this decision. An SOS going to the wrong stream means permanent packet loss.

---

### Phase 3: Cloud Delivery Failure → Reclassify & Forward

**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`

**Problem:** If `hasInternet` is `true` but cloud delivery fails (real failure, not mock), the packet still stops. There's no fallback to relay forwarding.

**Changes:**

1. **After cloud delivery attempt fails, fall through to relay forwarding instead of just logging**

```dart
if (hasInternet && packet.isSos) {
  try {
    final result = await _cloudDeliveryService.uploadSos(
      sosPayload, packet.originatorId,
    );
    if (result.isRight()) {
      print('✅ Cloud delivery successful for packet ${packet.id}');
      return; // Only stop if ACTUALLY delivered
    }
    // Cloud delivery returned Left (failure)
    print('⚠️ Cloud delivery service returned failure, falling back to relay');
    // CRITICAL: Update internet probe to false since delivery failed
    _internetProbe.markOffline();
  } catch (e) {
    print('⚠️ Cloud delivery exception: $e — falling back to relay');
    _internetProbe.markOffline();
  }
  // Fall through to relay forwarding below
}
```

2. **Add `markOffline()` method to InternetProbe** for immediate override when cloud delivery proves no real connectivity:

```dart
/// Force-mark as offline (e.g., when cloud delivery fails despite probe saying online).
/// This triggers an immediate re-probe on next cycle.
void markOffline() {
  if (_hasInternet) {
    _hasInternet = false;
    _connectivityController.add(false);
    _lastProbeTime = null; // Invalidate cache
    _scheduleNextProbe(); // Use faster offline interval
  }
}
```

**Also fix the SOS stream routing to re-emit to the correct stream when reclassified:**

If the SOS was initially emitted to the GOAL stream but cloud delivery failed, emit it to the RELAY stream so it gets properly forwarded.

---

### Phase 4: Make Cloud Delivery Service Validate Real Connectivity

**File:** `lib/features/mesh_network/data/services/cloud_delivery_service.dart`

**Problem:** The mock always returns success, hiding the real connectivity issue.

**Changes:**

Replace the mock with a hybrid approach:
```dart
Future<Either<Failure, bool>> uploadSos(SosPayload sos, String originalSenderId) async {
  try {
    // STEP 1: Quick connectivity verification (HTTP HEAD)
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.headUrl(
        Uri.parse('http://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 3));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode != 204) {
        return Left(ServerFailure('No real internet connectivity (status: ${resp.statusCode})'));
      }
    } catch (e) {
      return Left(ServerFailure('No real internet connectivity: $e'));
    } finally {
      client.close();
    }

    // STEP 2: Actual upload (or mock for now)
    // TODO: Replace with actual HTTP POST when backend is ready
    await Future.delayed(const Duration(seconds: 1));
    print('☁️ [CloudDelivery] UPLOAD SUCCESS (verified): SOS from $originalSenderId');
    return const Right(true);
  } catch (e) {
    return Left(ServerFailure(e.toString()));
  }
}
```

This ensures that even the mock path verifies real internet before claiming success.

---

### Phase 5: Integrate `connectivity_plus` for Instant Network Change Detection

**File:** `lib/features/mesh_network/data/services/internet_probe.dart`

**Problem:** Probing every 30-60s means up to 60s of stale state. Android's `connectivity_plus` plugin can notify instantly when network interfaces change.

**Changes:**

1. **Add `connectivity_plus` listener inside InternetProbe:**
```dart
import 'package:connectivity_plus/connectivity_plus.dart';

StreamSubscription<List<ConnectivityResult>>? _platformSub;

void startProbing() {
  // Existing timer-based probing
  checkConnectivity();
  _scheduleNextProbe();

  // NEW: Listen to platform connectivity changes for instant detection
  _platformSub = Connectivity().onConnectivityChanged.listen((results) {
    print('🌐 Platform connectivity changed: $results');
    // Force an immediate re-probe
    checkConnectivity(forceRefresh: true);
  });
}

void stopProbing() {
  _probeTimer?.cancel();
  _probeTimer = null;
  _platformSub?.cancel();
  _platformSub = null;
}
```

When Android fires a network change event (WiFi/mobile toggled), we immediately re-probe with HTTP. This reduces detection latency from 30-60s to <5s.

---

### Phase 6: Propagate Connectivity Change to Metadata + Streams

**File:** `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart`  
**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`

**Problem:** Even after fixing the probe, the metadata broadcast (`net=1`, `rol=g`) and the SOS stream listeners need to react.

**Changes:**

1. **BLoC `_onConnectivityChanged` already propagates to metadata** (from our Phase 5 of the previous fix). Verify it works:
```dart
Future<void> _onConnectivityChanged(_ConnectivityChanged event, Emitter<MeshState> emit) async {
  final currentState = state;
  if (currentState is MeshActive) {
    emit(currentState.copyWith(hasInternet: event.hasInternet));
    await _repository.updateMetadata(); // ← This re-broadcasts net/rol
  }
}
```

2. **Clear stale GOAL-stream SOS alerts when node loses internet:**

When connectivity changes from `true` → `false`, any SOS alerts in the "I Can Help" list are now invalid — this node can't actually help via cloud. Clear them and re-route to relay:

```dart
if (!event.hasInternet && currentState.hasInternet) {
  // Transitioned FROM goal TO relay — clear stale goal-stream alerts
  print('⚠️ Lost internet — clearing stale responder SOS alerts');
  emit(currentState.copyWith(
    hasInternet: false,
    recentSosAlerts: [], // Clear goal-node alerts
  ));
}
```

3. **Add debug logging to `_processIncomingPacket` showing the probe result** so we can verify in logs:
```dart
final hasInternet = await _internetProbe.checkConnectivity(forceRefresh: true);
print('🚨 Repository: Internet check result: $hasInternet (for SOS routing)');
```

---

## Verification Checklist

After implementation, test the following scenarios:

| # | Scenario | Expected Result |
|---|----------|-----------------|
| 1 | D1 has NO internet, receives SOS | SOS goes to RELAY stream, NOT "I Can Help" |
| 2 | D1 has internet, receives SOS | SOS goes to GOAL stream, "I Can Help" shows it |
| 3 | D1 has internet, loses it AFTER mesh start, receives SOS | Fresh probe returns false → RELAY stream |
| 4 | D1 gains internet AFTER mesh start, receives SOS | Fresh probe returns true → GOAL stream |
| 5 | Cloud delivery fails despite probe = true | `markOffline()` called, packet falls through to relay |
| 6 | Metadata reflects internet change | `net` and `rol` in broadcast metadata update within seconds |
| 7 | `connectivity_plus` event fires on toggle | Immediate re-probe triggered |

---

## File Change Summary

| File | Changes |
|------|---------|
| `internet_probe.dart` | Remove IP literals from endpoints, HTTP-only probing, shorter intervals, add `markOffline()`, integrate `connectivity_plus` listener |
| `mesh_repository_impl.dart` | Force-refresh probe before SOS routing + cloud delivery, cloud failure fallback to relay, re-emit SOS to correct stream |
| `cloud_delivery_service.dart` | Add connectivity verification before mock/real upload |
| `mesh_bloc.dart` | Clear stale goal-stream alerts on connectivity loss |

---

## Risk Assessment

- **Phase 1-2:** Zero risk — fixes broken probing logic and adds correctness check
- **Phase 3:** Low risk — adds fallback path that only activates on failure
- **Phase 4:** Low risk — adds a quick HTTP check before mock (< 3s overhead)
- **Phase 5:** Medium risk — `connectivity_plus` may fire spurious events during P2P group formation. Mitigated by always validating with HTTP probe, not trusting the platform event alone.
- **Phase 6:** Low risk — defensive clearing of stale data

**Total added latency per SOS:** ~3-4 seconds for fresh HTTP probe (acceptable for life-safety packets that previously died silently).
