# SOS Relay Forwarding Fix Plan

## Problem Statement
SOS packet sending works perfectly between 2 devices (Sender → Goal), but **3-device relay forwarding** (Sender → Relay → Goal) only works **once** and then fails on subsequent attempts. The SOS reaches the Relay node but cannot be automatically forwarded to the Goal node reliably.

---

## Root Cause Analysis

After deep analysis of the entire Dart + Kotlin stack, **7 root causes** were identified. They compound each other — fixing any single one alone won't solve the problem.

### ROOT CAUSE 1: `SocketServerManager` Binds to P2P Interface — Dies After Disconnect (CRITICAL)

**File:** `SocketServerManager.kt` → `detectP2pBindAddress()`

The socket server tries to bind to the P2P group owner interface (`p2p-wlan0-x` with address `192.168.49.x`). When the first `connectAndSendPacket` cycle completes and the P2P group is torn down via `removeGroup()`, the P2P network interface **disappears**. The `ServerSocket` bound to that interface can no longer accept new connections — it's dead.

**Why it worked once:** Before the first P2P connection, no P2P interface exists, so the server binds to `0.0.0.0` (all interfaces). The first relay connection creates a P2P group, and when the receiver's server loops back to `accept()`, it still works because it's bound to all interfaces. However, during the *next* mesh node startup or server restart, `detectP2pBindAddress()` finds the now-stale P2P interface and binds to it specifically. When that interface goes away, the server is dead.

**Impact:** After the first successful relay, the Goal node's packet server is bound to a dead interface. All subsequent relay attempts fail silently because no server is listening.

### ROOT CAUSE 2: `restartDiscoveryAfterSend()` Does a Full Reset — Kills Active Discovery Session (CRITICAL)

**File:** `WifiP2pHandler.kt` → `restartDiscoveryAfterSend()`

After every successful `connectAndSendPacket`, `restartDiscoveryAfterSend()` calls `clearServiceRequests()` then `addServiceRequestAndDiscover()`. This **nukes the entire DNS-SD session** and starts from scratch. The problem:

1. DNS-SD service discovery takes 10-30 seconds to propagate and find neighbors
2. During this reset window, the relay node has **zero neighbors** visible
3. If a new SOS arrives during this window, `_forwardPacket()` sees no neighbors → fails
4. The outbox stores it, but the orchestrator also sees no neighbors for the next 10-30 seconds
5. By the time neighbors reappear, the orchestrator may have already exhausted its retry window or the node was marked stale

**This is why the first relay works but subsequent ones fail** — the discovery session is reset after each send.

### ROOT CAUSE 3: Relay Node Loses Neighbor Visibility After P2P Group Teardown (HIGH)

**File:** `ConnectionManager.kt` → `connect()` always calls `removeGroup()` first

Every `connectAndSendPacket` flow starts with `removeGroup()` in `ConnectionManager.connect()`. This:
1. Tears down any existing P2P group
2. Disrupts the Wi-Fi radio state (P2P and regular Wi-Fi share the same radio)
3. **Clears the peer cache** in the Wi-Fi framework
4. Service discovery stops working until re-initiated

Combined with ROOT CAUSE 2, after a successful send, the relay node enters a dead period where it cannot:
- See any neighbors (discovery reset)
- Accept any connections (group torn down)
- Forward any packets (no targets)

### ROOT CAUSE 4: `isConnecting` Guard Never Resets on Timeout Paths (MEDIUM)

**File:** `WifiP2pHandler.kt` → `connectAndSendPacket()`

The `isConnecting` flag is set to `true` before `connectAndSendPacket` and should be reset to `false` in all completion paths. However, if `ConnectionManager.connect()` internally times out during group formation (after `maxConnectionAttempts` polling cycles), the `onFailure` callback does reset `isConnecting`. But if the coroutine scope is cancelled or the `socket.connect()` hangs beyond the 10s timeout and throws, the catch block does handle it.

**However**, there's a subtle race: if two packets arrive in quick succession at the relay node, the second one gets `BUSY` error and goes to outbox. This is by design but reduces effective throughput.

### ROOT CAUSE 5: Outbox Stores Packet Without Hop — Orchestrator Re-adds Same Hop on Each Retry (MEDIUM)

**File:** `mesh_repository_impl.dart` → `_handleForwardOrDeliver()`

The code stores the **original packet** (trace=[A]) in the outbox, then creates `hopAddedPacket = packet.addHop(nodeId)` for immediate forward. If immediate forward fails:
- The outbox has the packet with trace=[A]
- RelayOrchestrator picks it up and in `_attemptSend()`, does `packet.addHop(_nodeId)` → trace=[A, B]
- This is correct **once**, but if the send fails again, `_outbox.markFailed(packet.id)` increments retry count
- On the next retry, the orchestrator fetches from outbox again (trace=[A]), adds hop again (trace=[A, B])
- So this part actually works correctly per-retry

**But**: the maxRetries in OutboxBox is only **3** (aligned with RelayOrchestrator's `maxConsecutiveFailures`). Combined with the 10-30 second discovery blackout (ROOT CAUSE 2), three retries burn through quickly because:
- Retry 1: No neighbors (discovery resetting) → fail
- Retry 2: Still no neighbors (10s later) → fail  
- Retry 3: Maybe neighbors back, but connection attempt fails → fail → **packet permanently marked FAILED**

### ROOT CAUSE 6: `_relayTimer` 10-Second Interval Too Slow for Immediate Forwarding After Discovery Recovers (LOW-MEDIUM)

**File:** `relay_orchestrator.dart` → `relayInterval = Duration(seconds: 10)`

The relay orchestrator polls every 10 seconds. Combined with the discovery recovery time (10-30s from ROOT CAUSE 2), the effective relay latency can be 20-40 seconds. By then:
- The outbox retries may be exhausted
- The neighbor node may have gone stale (2-minute timeout, but close)
- The `retryDelay` of 30 seconds after 3 failures adds more delay

### ROOT CAUSE 7: No Acknowledgment-Driven Retry — Fire-and-Forget at Dart Level (LOW)

**File:** `mesh_repository_impl.dart` → `_handleForwardOrDeliver()`

When the immediate `_forwardPacket()` fails, the Dart layer simply logs it and hopes the orchestrator will retry. There's no:
- Exponential backoff
- Event-driven retry (e.g., "retry when a new neighbor appears")  
- Priority queue escalation for failed SOS packets

---

## How the Root Causes Compound (The "Works Once" Pattern)

**First SOS relay (WORKS):**
1. Relay node B has neighbors [A, C] visible from ongoing discovery
2. A sends SOS → B receives → B has C as neighbor → immediate forward succeeds
3. C receives SOS ✓

**Second SOS relay (FAILS):**  
1. After first relay, `restartDiscoveryAfterSend()` nukes B's discovery session (RC2)
2. B's neighbor list becomes empty for 10-30 seconds
3. C's server socket may be bound to dead P2P interface (RC1)
4. A sends second SOS → B receives → B has **no neighbors** → immediate forward fails
5. Packet goes to outbox → orchestrator tries in 10 seconds → still no neighbors
6. After 3 failures (30 seconds), packet is permanently marked failed (RC5)
7. Even when discovery recovers and C is visible again, the packet is dead

---

## Implementation Plan

### Phase 1: Critical Fixes (Must-Do)

#### Fix 1.1: Server Socket Must ALWAYS Bind to 0.0.0.0 (SocketServerManager.kt)
**Priority:** P0 — Without this, Goal node is deaf after first relay

**Change:** Remove `detectP2pBindAddress()` and always bind to `INADDR_ANY` (`0.0.0.0`). The P2P interface is ephemeral and unreliable. The server should accept connections on any interface. Alternatively, restart the server socket after each `removeGroup()` / disconnect.

```kotlin
// In SocketServerManager.start():
// REMOVE: val bindAddress = detectP2pBindAddress()
// ALWAYS:
serverSocket = ServerSocket(PORT)
```

**Validation:** After fix, the Goal node's server remains accessible after P2P groups form/teardown.

#### Fix 1.2: Lightweight Discovery Restart After Send (WifiP2pHandler.kt)
**Priority:** P0 — Without this, relay node is blind for 10-30 seconds after each send

**Change:** Replace `restartDiscoveryAfterSend()` with a lightweight `discoverServices()` nudge (same pattern as the refresh timer), NOT a full `clearServiceRequests → addServiceRequest → discoverServices` cycle.

```kotlin
private fun restartDiscoveryAfterSend() {
    if (!isDiscoveryActive) return
    mainHandler.postDelayed({
        Log.d(TAG, "🔄 Lightweight discovery nudge after send...")
        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Post-send discovery nudge succeeded")
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Post-send nudge failed (code: $code) — doing full reset")
                addServiceRequestAndDiscover { success ->
                    Log.d(TAG, "🔄 Post-send full reset: ${if (success) "✅" else "❌"}")
                }
            }
        })
    }, 1500)  // 1.5s delay to let P2P channel stabilize
}
```

**Validation:** After fix, neighbors reappear within 2-5 seconds of a send, not 10-30 seconds.

#### Fix 1.3: Increase Outbox Max Retries for SOS Packets (outbox_box.dart)
**Priority:** P0 — 3 retries is far too few when discovery takes 10-30 seconds

**Change:** Use a higher retry limit for SOS/critical packets, and use time-based expiry instead of attempt-count.

```dart
// In OutboxBox:
static const int maxRetries = 3;          // Keep for normal packets
static const int maxSosRetries = 10;      // SOS gets 10 retries
static const Duration sosTtl = Duration(minutes: 10);  // SOS lives 10 minutes

Future<bool> markFailed(String packetId) async {
    final entry = _box!.get(packetId);
    if (entry == null) return false;
    
    final effectiveMaxRetries = entry.packet.isSos 
        ? maxSosRetries 
        : maxRetries;
    
    final newRetryCount = entry.retryCount + 1;
    if (newRetryCount >= effectiveMaxRetries) {
        // Permanently failed
        ...
    }
    ...
}
```

### Phase 2: Robustness Improvements (Should-Do)

#### Fix 2.1: Event-Driven Relay Trigger on Neighbor Discovery (mesh_repository_impl.dart)
**Priority:** P1 — Relay should react when neighbors appear, not just poll

**Change:** When `_neighborController` emits a new neighbor list, check if there are pending outbox packets and trigger an immediate orchestrator run.

```dart
// In _setupEventListeners():
_nodeSubscription = _wifiP2pSource.discoveredNodes.listen((nodes) {
    _neighborController.add(nodes);
    
    // If we have pending packets and new neighbors appeared, force relay immediately
    if (nodes.isNotEmpty && _outbox.getPendingPackets().isNotEmpty) {
        print('🔄 New neighbors appeared with pending packets — forcing relay');
        // Don't await — fire-and-forget trigger to avoid blocking the stream
        _relayOrchestrator.forceRelay();
    }
});
```

This eliminates the 10-second polling gap — as soon as a viable neighbor appears, relay is attempted.

#### Fix 2.2: Smarter Retry Backoff with Jitter (relay_orchestrator.dart)
**Priority:** P1 — Prevent retry storms and align with discovery recovery

**Change:** Use exponential backoff with jitter for retry delays instead of fixed 30-second pause.

```dart
// Replace the fixed retryDelay with exponential backoff
Duration _getRetryDelay() {
    final baseDelay = Duration(seconds: 5);
    final backoffMs = (baseDelay.inMilliseconds * pow(1.5, _consecutiveFailures)).toInt();
    final jitterMs = Random().nextInt(2000);  // 0-2 second jitter
    return Duration(milliseconds: min(backoffMs + jitterMs, 60000));  // cap at 60s
}
```

#### Fix 2.3: Socket Server Auto-Restart After P2P Disconnect (SocketServerManager.kt)
**Priority:** P1 — Defensive measure: server should self-heal

**Change:** Add a health-check mechanism that detects when the server socket is no longer accepting connections and restarts it.

```kotlin
// In WifiP2pHandler, after disconnect in connectAndSendPacket:
connectionManager.disconnect {
    isConnecting = false
    restartDiscoveryAfterSend()
    // Ensure socket server is still alive after P2P group teardown
    ensureSocketServerRunning()
    mainHandler.post { result.success(true) }
}

private fun ensureSocketServerRunning() {
    if (socketServer == null || !socketServer!!.isRunning) {
        Log.w(TAG, "⚠️ Socket server not running after disconnect — restarting")
        socketServer?.stop()
        startSocketServer()
    }
}
```

Also add `isRunning` property to `SocketServerManager`:
```kotlin
val isRunning: Boolean get() = isRunning && serverSocket?.isClosed == false
```

### Phase 3: Reliability Enhancements (Nice-to-Have)

#### Fix 3.1: Add Relay-Specific Logging/Metrics Stream (mesh_repository_impl.dart)
**Priority:** P2 — Essential for debugging relay failures in the field

**Change:** Add a diagnostic stream that emits detailed relay attempt events:
```dart
final _relayDiagController = StreamController<RelayDiagnostic>.broadcast();
Stream<RelayDiagnostic> get relayDiagnostics => _relayDiagController.stream;

// Emit at each decision point in _handleForwardOrDeliver:
_relayDiagController.add(RelayDiagnostic(
    timestamp: DateTime.now(),
    packetId: packet.id,
    action: 'immediate_forward_attempt',
    neighborCount: neighbors.length,
    selectedNode: bestNode?.id,
    result: forwarded ? 'success' : 'failed',
));
```

#### Fix 3.2: Outbox Priority Re-queuing for Failed SOS (outbox_box.dart)
**Priority:** P2 — Failed SOS should be retried more aggressively

**Change:** When an SOS relay fails, don't increment retry count if the failure reason was "no neighbors" (transient). Only count retries when there was an actual send attempt that failed.

```dart
Future<bool> markFailed(String packetId, {bool wasTransient = false}) async {
    final entry = _box!.get(packetId);
    if (entry == null) return false;
    
    // Transient failures (no neighbors) don't count as real retries
    if (wasTransient && entry.packet.isSos) {
        final updated = entry.copyWith(
            status: OutboxStatus.pending,
            lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _box!.put(packetId, updated);
        return true;
    }
    
    // ... existing logic for real failures ...
}
```

#### Fix 3.3: Connection Cooldown Map (WifiP2pHandler.kt)
**Priority:** P2 — Don't hammer the same device with rapid reconnection attempts

**Change:** Track last connection attempt per device address and enforce a minimum cooldown.

```kotlin
private val connectionCooldowns = mutableMapOf<String, Long>()
private const val CONNECTION_COOLDOWN_MS = 5000L

fun connectAndSendPacket(...) {
    val now = System.currentTimeMillis()
    val lastAttempt = connectionCooldowns[deviceAddress] ?: 0
    if (now - lastAttempt < CONNECTION_COOLDOWN_MS) {
        Log.w(TAG, "⚠️ Cooldown active for $deviceAddress, retrying later")
        result.error("COOLDOWN", "Connection cooldown active", null)
        return
    }
    connectionCooldowns[deviceAddress] = now
    // ... proceed with connection ...
}
```

---

## Summary: Priority Order

| # | Fix | File(s) | Priority | Impact |
|---|-----|---------|----------|--------|
| 1.1 | Server bind to 0.0.0.0 | SocketServerManager.kt | P0 | Goal node deaf after 1st relay |
| 1.2 | Lightweight discovery nudge | WifiP2pHandler.kt | P0 | Relay node blind for 10-30s after send |
| 1.3 | Increase SOS retry limit | outbox_box.dart | P0 | SOS packet dies after 3 quick failures |
| 2.1 | Event-driven relay trigger | mesh_repository_impl.dart | P1 | 10s polling gap |
| 2.2 | Exponential backoff retries | relay_orchestrator.dart | P1 | Retry storm prevention |
| 2.3 | Server auto-restart | WifiP2pHandler.kt + SocketServerManager.kt | P1 | Self-healing server |
| 3.1 | Relay diagnostics stream | mesh_repository_impl.dart | P2 | Debugging visibility |
| 3.2 | Transient failure handling | outbox_box.dart | P2 | Smart retry counting |
| 3.3 | Connection cooldown | WifiP2pHandler.kt | P2 | Prevent connection storms |

---

## Testing Strategy

### Test Scenario: 3-Device Chain Relay
1. **Device A** (Sender): No internet, sends SOS
2. **Device B** (Relay): No internet, should forward
3. **Device C** (Goal): Has internet, should receive

**Test Steps:**
1. Start mesh on all 3 devices
2. Wait for neighbor discovery (verify B sees both A and C)
3. A sends SOS #1 → Verify C receives it ✓
4. Wait 30 seconds
5. A sends SOS #2 → **Verify C receives it** (this is the failure case today)
6. Repeat 5 more times at 15-second intervals
7. All 6 SOS packets should arrive at C

**What to monitor:**
- Relay node's neighbor list (should never go empty for >5 seconds)
- Goal node's socket server logs (should always show "CLIENT CONNECTED" for each relay)
- Outbox entries on relay node (should show "sent", not "failed")
