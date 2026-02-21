# Role Classification & Multi-Hop Relay — Bug Analysis & Implementation Plan

## Table of Contents
1. [Target Scenario](#1-target-scenario)
2. [Bug Inventory — Root Cause Analysis](#2-bug-inventory--root-cause-analysis)
3. [Current Data Flow (Broken)](#3-current-data-flow-broken)
4. [Desired Data Flow (Fixed)](#4-desired-data-flow-fixed)
5. [Implementation Plan — Phase by Phase](#5-implementation-plan--phase-by-phase)
6. [File Change Map](#6-file-change-map)
7. [Testing Strategy](#7-testing-strategy)

---

## 1. Target Scenario

```
Device A (Victim)  ──P2P──▶  Device B (Relay, NO internet)  ──P2P──▶  Device C (Goal, HAS internet)
   role=sender                     role=relay                              role=goal
   Sends SOS                       Receives SOS                            Receives SOS
                                   ├─ Does NOT show in "I Can Help"        ├─ Shows in "I Can Help"
                                   ├─ Shows in "Relay Mode" section        ├─ Delivers to cloud
                                   ├─ Increments relay SOS counter         └─ Stops forwarding
                                   └─ Auto-forwards to Device C
```

**Key Rules:**
- A node WITHOUT internet = **relay only**. It must NEVER show SOS in "I Can Help" and must NEVER attempt cloud delivery.
- A node WITH internet = **goal node**. It shows SOS in "I Can Help" and delivers to cloud.
- Relay nodes auto-forward to the next best node. If no next node exists, the packet is stored in the outbox and retried by the `RelayOrchestrator` every 10 seconds.
- Loop prevention: packets carry a hop trace; nodes already in the trace are excluded from forwarding.

---

## 2. Bug Inventory — Root Cause Analysis

### BUG-RC1: SOS Always Emitted to UI Regardless of Internet Status

| Field | Detail |
|-------|--------|
| **File** | `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart` |
| **Method** | `_processIncomingPacket()` (lines ~310-330) |
| **Severity** | CRITICAL |

**What happens now:**
```dart
// Inside _processIncomingPacket():
if (packet.isSos) {
  final sosPayload = SosPayload.fromJsonString(packet.payload);
  _sosReceivedController.add(ReceivedSos(...));   // ◀── ALWAYS fires
}
await _handleForwardOrDeliver(packet, ...);       // Then also forwards/delivers
```

The `_sosReceivedController.add(...)` fires **unconditionally** — there is no check for `_internetProbe.hasInternet`. Every node that receives an SOS (relay OR goal) emits it to the same stream, which flows to the BLoC and then to the "I Can Help" (Responder Mode) UI.

**Root Cause:** The SOS emission was written as a "log every SOS we see" mechanism. The distinction between "this node is the final destination" vs "this node is just passing it along" was never encoded.

**Impact:**
- A relay node (no internet) incorrectly shows incoming SOS alerts in the "I Can Help" responder section.
- The user on a relay node sees help requests they cannot serve (no cloud, no internet for coordination).

---

### BUG-RC2: No Separate Stream for Relay-Mode SOS Events

| Field | Detail |
|-------|--------|
| **File** | `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart` |
| **Class Fields** | Lines ~48-50 |
| **Severity** | HIGH |

**What happens now:**
The repository has exactly **one** SOS stream:
```dart
final _sosReceivedController = StreamController<ReceivedSos>.broadcast();
Stream<ReceivedSos> get sosAlerts => _sosReceivedController.stream;
```

There is **no stream** to notify the relay mode UI that "a packet was received and is being relayed". The relay mode page (`relay_mode_page.dart`) only reads `RelayStats` (packetsSent, packetsFailed) from the `RelayOrchestrator` — it has no idea which specific SOS packets passed through this node.

**Root Cause:** The architecture was designed with only two consumers in mind: (1) responder (goal) gets SOS alerts, (2) relay gets stats. But there was no mechanism to tell the relay UI "hey, you just received SOS packet X and are forwarding it."

**Impact:**
- Relay Mode page shows "Relayed: 0" even after packets pass through, because the orchestrator stats only update when its own 10-second loop processes outbox packets — if the immediate forward in `_handleForwardOrDeliver` succeeds, the orchestrator never touches the packet and never increments `packetsSent`.
- No packet log entries appear in Relay Mode when SOS flows through.

---

### BUG-RC3: MeshBloc Adds ALL SOS to `recentSosAlerts` Without Role Check

| Field | Detail |
|-------|--------|
| **File** | `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart` |
| **Method** | `_onSosReceived()` (lines ~460-474) |
| **Severity** | HIGH |

**What happens now:**
```dart
void _onSosReceived(_SosReceived event, Emitter<MeshState> emit) {
  final currentState = state;
  if (currentState is! MeshActive) return;

  _recentSosAlerts.insert(0, event.sos);                  // ◀── No role/internet check
  if (_recentSosAlerts.length > _maxRecentAlerts) {
    _recentSosAlerts.removeLast();
  }
  emit(currentState.copyWith(
    recentSosAlerts: List.from(_recentSosAlerts),          // ◀── Goes to all UI
  ));
}
```

Even if the repository were fixed to only emit on the `sosAlerts` stream for goal nodes, the BLoC handler blindly pushes every `_SosReceived` event into `recentSosAlerts`. The `recentSosAlerts` field is then read by **both** – the Home Page badge counter AND the Responder Mode page `_buildIncomingEmergenciesSection()`.

**Root Cause:** The BLoC was designed before the relay-vs-goal distinction was formalized. It treats every SOS event as a "display to the responder" event.

**Impact:**
- Home page badge shows SOS count even on relay nodes.
- `ResponderModePage` displays SOS cards on relay nodes.

---

### BUG-RC4: Responder Mode Page Has No Internet Guard

| Field | Detail |
|-------|--------|
| **File** | `lib/features/mesh_network/presentation/pages/responder_mode_page.dart` |
| **Method** | `_buildMainContent()` (line ~137), `_buildIncomingEmergenciesSection()` (line ~214) |
| **Severity** | MEDIUM |

**What happens now:**
```dart
Widget _buildMainContent() {
  return BlocBuilder<MeshBloc, MeshState>(
    builder: (context, state) {
      final sosAlerts = state is MeshActive ? state.recentSosAlerts : <ReceivedSos>[];
      // ◀── No check: state.hasInternet — shows alerts even if this is a relay node
      ...
      _buildIncomingEmergenciesSection(sosAlerts),
    },
  );
}
```

The page reads `state.recentSosAlerts` directly without checking `state.hasInternet`. If a relay node opens this page, it will display whatever SOS alerts leaked through from BUG-RC1/RC3.

**Root Cause:** The page assumes that only goal nodes will ever have alerts in `recentSosAlerts`. No defensive guard was added.

**Impact:** Even if upstream bugs are partially fixed, this page would still render stale alerts if any slipped through. (Defense-in-depth issue.)

---

### BUG-RC5: Home Page Badge Shows SOS Count on Relay Nodes

| Field | Detail |
|-------|--------|
| **File** | `lib/features/mesh_network/presentation/pages/home_page.dart` |
| **Method** | `_buildNodeStatusBadge()` (lines ~260-310) |
| **Severity** | LOW (cosmetic, but confusing) |

**What happens now:**
```dart
final sosCount = isGoal ? activeState.recentSosAlerts.length : 0;
```

This code already has a partial guard — it only shows the count `if (isGoal)`. **However**, `isGoal` is derived from `activeState.hasInternet`, which is set by `_onConnectivityChanged`. If `hasInternet` was ever transiently true and SOS alerts were added to `recentSosAlerts` during that window, the count would be stale but technically correct.

**Root Cause:** The home page guard is correct given `hasInternet`, but it depends on the upstream bugs being fixed — if `recentSosAlerts` is polluted with relay SOS (BUG-RC3), this guard only hides the badge, it doesn't prevent the underlying data corruption.

**Impact:** Low — the badge correctly hides on relay, but navigating to Responder Mode still shows the leaked SOS.

---

### BUG-RC6: Relay Stats Counter Misses Immediate Forwards

| Field | Detail |
|-------|--------|
| **Files** | `mesh_repository_impl.dart` (`_handleForwardOrDeliver`) + `relay_orchestrator.dart` |
| **Severity** | MEDIUM |

**What happens now:**
When an SOS arrives at a relay node, `_handleForwardOrDeliver()` in the **repository** first tries an immediate forward via `_forwardPacket()`. If it succeeds, it calls `_outbox.markSent()`, and the packet is done. The `RelayOrchestrator` never sees it because its 10-second loop only picks up **pending** (unsent) packets.

The `RelayOrchestrator` is the only component that increments `_packetsSent` and emits `RelayStats`. So:
- Packet arrives → immediate forward succeeds → `_packetsSent` stays at 0.
- Relay Mode page reads `relayStats.packetsSent` = 0.
- The UI says "Relayed: 0" even though a packet was successfully relayed.

**Root Cause:** The immediate-forward path in the repository bypasses the orchestrator's stats counter. There's no callback or event to notify the orchestrator (or any stats tracker) that a packet was successfully forwarded outside its loop.

**Impact:** Relay Mode stats are always undercounted. User thinks relay is doing nothing when it's actually working.

---

## 3. Current Data Flow (Broken)

```
                          _processIncomingPacket()
                                  │
                 ┌────────────────┼────────────────┐
                 ▼                │                 ▼
          packet.isSos?           │         _handleForwardOrDeliver()
              YES                 │                 │
               │                  │        hasInternet? ──YES──▶ cloud upload
               ▼                  │                 │
    _sosReceivedController.add()  │                NO
    [FIRES UNCONDITIONALLY]       │                 │
               │                  │         persist to outbox + forward
               ▼                  │
         BLoC: _onSosReceived()   │
               │                  │
               ▼                  │
    recentSosAlerts.insert()      │
    [NO ROLE CHECK]               │
               │                  │
       ┌───────┴──────┐          │
       ▼              ▼          │
  Home Badge    ResponderMode    │
  (shows count) (shows cards)    │
  [has isGoal   [NO guard]       │
   guard]                        │
```

**Problem:** The left branch (SOS → UI) fires regardless of internet status. The right branch (forward/deliver) correctly checks internet, but the UI is already polluted.

---

## 4. Desired Data Flow (Fixed)

```
                          _processIncomingPacket()
                                  │
                          packet.isSos?
                              YES
                               │
                    ┌──────────┼──────────┐
                    │      hasInternet?    │
                    │                      │
                   YES                    NO
                    │                      │
                    ▼                      ▼
        _sosReceivedController     _relayedSosController
        .add(ReceivedSos)          .add(ReceivedSos)
                    │                      │
                    ▼                      ▼
         BLoC: _onSosReceived      BLoC: _onSosRelayed
                    │                      │
                    ▼                      ▼
         recentSosAlerts           relayedSosCount++
         (Goal nodes only)         + add to packetLog
                    │                      │
            ┌───────┴──────┐               │
            ▼              ▼               ▼
       Home Badge    ResponderMode    RelayModePage
                                     (shows count + log)
                                           │
                    ┌──────────────────────┘
                    ▼
           _handleForwardOrDeliver()
                    │
           hasInternet? ──YES──▶ cloud upload, STOP
                    │
                   NO
                    │
            persist to outbox
            attempt immediate forward
            if fail → RelayOrchestrator retries
```

---

## 5. Implementation Plan — Phase by Phase

---

### PHASE 1: Repository Layer — Split SOS Streams (Root Fix)

> **Goal:** The repository emits SOS events to the correct stream based on this node's internet status.

#### Subtask 1.1: Add `_relayedSosController` stream

**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`

**What:** Add a second `StreamController<ReceivedSos>.broadcast()` alongside the existing `_sosReceivedController`.

**Where (line ~50):** After the existing `_sosReceivedController` declaration:
```dart
// EXISTING:
final _sosReceivedController = StreamController<ReceivedSos>.broadcast();

// ADD:
final _relayedSosController = StreamController<ReceivedSos>.broadcast();
```

**Why:** We need two distinct channels:
- `_sosReceivedController` → consumed by goal nodes (shows in "I Can Help")
- `_relayedSosController` → consumed by relay nodes (shows in "Relay Mode")

#### Subtask 1.2: Add `relayedSosAlerts` getter

**File:** Same file

**What:** Add a public getter for the new stream, right after the existing `sosAlerts` getter (around line ~85):
```dart
// EXISTING:
Stream<ReceivedSos> get sosAlerts => _sosReceivedController.stream;

// ADD:
Stream<ReceivedSos> get relayedSosAlerts => _relayedSosController.stream;
```

#### Subtask 1.3: Modify `_processIncomingPacket()` — conditional SOS emission

**File:** Same file  
**Method:** `_processIncomingPacket()` (lines ~310-330)

**Current code (BROKEN):**
```dart
if (packet.isSos) {
  try {
    final sosPayload = SosPayload.fromJsonString(packet.payload);
    _sosReceivedController.add(ReceivedSos(
      packet: packet,
      sos: sosPayload,
      receivedAt: DateTime.now(),
      senderIp: received.senderIp,
    ));
  } catch (e) { ... }
}
```

**New code (FIXED):**
```dart
if (packet.isSos) {
  try {
    final sosPayload = SosPayload.fromJsonString(packet.payload);
    final receivedSos = ReceivedSos(
      packet: packet,
      sos: sosPayload,
      receivedAt: DateTime.now(),
      senderIp: received.senderIp,
    );
    
    if (_internetProbe.hasInternet) {
      // Goal node: show in "I Can Help" responder UI
      _sosReceivedController.add(receivedSos);
    } else {
      // Relay node: emit to relay stream (shows in Relay Mode UI)
      _relayedSosController.add(receivedSos);
    }
  } catch (e) { ... }
}
```

**Why this works at root level:**
- The internet check is made at the EXACT moment the packet arrives.
- `_internetProbe.hasInternet` is the same cached value used by `_buildNodeMetadata()` to set `rol: 'g'` or `rol: 'r'` — so the SOS routing is now **consistent** with how the node advertises itself to the network.
- If internet status changes AFTER the SOS was emitted, the SOS stays in whichever stream it was sent to. This is correct — the node's role at reception time determines behavior.

#### Subtask 1.4: Close `_relayedSosController` in `dispose()`

**File:** Same file  
**Method:** `dispose()` (near end of file)

**Add** `await _relayedSosController.close();` next to the existing `_sosReceivedController.close()`.

---

### PHASE 2: BLoC Layer — Wire Relay SOS Events into State

> **Goal:** The BLoC subscribes to the new relay stream and tracks relay SOS count separately from responder SOS alerts.

#### Subtask 2.1: Add `_RelayedSosReceived` event class

**File:** `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart`  
**Where:** After the existing `_SosReceived` event class (around line ~93)

```dart
/// Internal: SOS relayed through this node (no internet).
class _RelayedSosReceived extends MeshEvent {
  final ReceivedSos sos;
  const _RelayedSosReceived(this.sos);
  @override
  List<Object?> get props => [sos];
}
```

#### Subtask 2.2: Add `relayedSosCount` field to `MeshActive` state

**File:** Same file  
**Class:** `MeshActive` (around line ~150)

**Add field:**
```dart
final int relayedSosCount;
```

**Update constructor** to include `this.relayedSosCount = 0`.

**Update `copyWith()`** to include the new field:
```dart
int? relayedSosCount,
...
relayedSosCount: relayedSosCount ?? this.relayedSosCount,
```

**Update `props`** to include `relayedSosCount`.

#### Subtask 2.3: Register `_onRelayedSosReceived` handler

**File:** Same file  
**Where:** In the `MeshBloc` constructor, after the existing `on<_SosReceived>(_onSosReceived)`:

```dart
on<_RelayedSosReceived>(_onRelayedSosReceived);
```

**Add the handler method:**
```dart
/// Handles SOS that was received and relayed (not for local display as responder).
void _onRelayedSosReceived(
  _RelayedSosReceived event,
  Emitter<MeshState> emit,
) {
  final currentState = state;
  if (currentState is! MeshActive) return;

  emit(currentState.copyWith(
    relayedSosCount: currentState.relayedSosCount + 1,
  ));
}
```

**Why `relayedSosCount` (integer) instead of a list:** Relay nodes don't need to show full SOS detail cards — they just need to know "X packets relayed". This keeps state lightweight. If you later want a relay log, you can upgrade to a list.

#### Subtask 2.4: Subscribe to `relayedSosAlerts` in `_setupSubscriptions()`

**File:** Same file  
**Method:** `_setupSubscriptions()` (around line ~508)

**Add** a new subscription after the existing `_sosSubscription`:
```dart
_relayedSosSubscription = _repository.relayedSosAlerts.listen((sos) {
  add(_RelayedSosReceived(sos));
});
```

**Also add** the field declaration at class level:
```dart
StreamSubscription? _relayedSosSubscription;
```

**Also cancel** it in `close()`:
```dart
await _relayedSosSubscription?.cancel();
```

---

### PHASE 3: Relay Mode UI — Show Relayed SOS Count + Packet Log

> **Goal:** The Relay Mode page shows how many SOS packets have passed through this node, in real-time.

#### Subtask 3.1: Add "SOS Relayed" stat card to `_buildStatsRow()`

**File:** `lib/features/mesh_network/presentation/pages/relay_mode_page.dart`  
**Method:** `_buildStatsRow()` (around line ~540)

**Current code:**
```dart
Widget _buildStatsRow(RelayStats stats) {
  return Row(
    children: [
      Expanded(child: _buildStatCard(icon: Icons.check_circle, ..., value: stats.packetsSent.toString(), label: 'Relayed')),
      const SizedBox(width: 12),
      Expanded(child: _buildStatCard(icon: Icons.cancel, ..., value: stats.packetsFailed.toString(), label: 'Dropped')),
      const SizedBox(width: 12),
      Expanded(child: _buildStatCard(icon: Icons.sync, ..., value: _isRelaying ? 'Active' : 'Idle', label: 'Status')),
    ],
  );
}
```

**Change:** Accept `relayedSosCount` as a parameter and add a 4th stat card (or replace "Relayed" to use the new count instead of `stats.packetsSent` since `stats.packetsSent` only covers orchestrator sends):

```dart
Widget _buildStatsRow(RelayStats stats, int relayedSosCount) {
  return Row(
    children: [
      Expanded(child: _buildStatCard(
        icon: Icons.sos,
        iconColor: const Color(0xFFFBBF24),
        value: relayedSosCount.toString(),
        label: 'SOS Relayed',
      )),
      const SizedBox(width: 12),
      Expanded(child: _buildStatCard(
        icon: Icons.check_circle,
        iconColor: const Color(0xFF10B981),
        value: stats.packetsSent.toString(),
        label: 'Forwarded',
      )),
      const SizedBox(width: 12),
      Expanded(child: _buildStatCard(
        icon: Icons.cancel,
        iconColor: const Color(0xFFEF4444),
        value: stats.packetsFailed.toString(),
        label: 'Dropped',
      )),
    ],
  );
}
```

#### Subtask 3.2: Pass `relayedSosCount` from BLoC state to the widget

**File:** Same file  
**Method:** `build()` → `BlocConsumer` builder (around line ~65)

**Current code:**
```dart
builder: (context, state) {
  final relayStats = state is MeshActive ? state.relayStats : RelayStats(...);
  ...
  _buildStatsRow(relayStats),
}
```

**Change:**
```dart
final relayedSosCount = state is MeshActive ? state.relayedSosCount : 0;
...
_buildStatsRow(relayStats, relayedSosCount),
```

#### Subtask 3.3: Add auto-log entry when relay SOS count changes

**File:** Same file  
**Method:** Inside `BlocConsumer.listener` (around line ~60)

Add logic inside the listener to detect when `relayedSosCount` increases and call `_addLogEntry()`:

```dart
listener: (context, state) {
  // Existing isRelaying sync...
  
  // Auto-add packet log entry when new SOS relayed
  if (state is MeshActive && state.relayedSosCount > _lastRelayedCount) {
    _addLogEntry('SOS packet received & forwarding...', true);
    _lastRelayedCount = state.relayedSosCount;
  }
},
```

Add `int _lastRelayedCount = 0;` as a class field.

---

### PHASE 4: Responder Mode UI — Defense-in-Depth Guard

> **Goal:** Even if upstream has a bug, the Responder Mode page never shows SOS alerts on a relay node.

#### Subtask 4.1: Add internet guard in `_buildMainContent()`

**File:** `lib/features/mesh_network/presentation/pages/responder_mode_page.dart`  
**Method:** `_buildMainContent()` (line ~137)

**Current code:**
```dart
final sosAlerts = state is MeshActive ? state.recentSosAlerts : <ReceivedSos>[];
```

**Change to:**
```dart
// Only show SOS alerts if this node has internet (is a Goal node).
// Relay nodes should NEVER display responder alerts.
final isGoalNode = state is MeshActive && state.hasInternet;
final sosAlerts = isGoalNode ? state.recentSosAlerts : <ReceivedSos>[];
```

**Why:** This is a **defense-in-depth** measure. Even if BUG-RC1 is fixed in the repository, this guard ensures the Responder Mode page can never incorrectly render SOS on a relay node due to transient state, race conditions, or future regressions.

---

### PHASE 5: Fix Relay Stats Counter for Immediate Forwards

> **Goal:** The relay stats accurately reflect ALL packets forwarded, including those forwarded immediately (not just via the orchestrator loop).

#### Subtask 5.1: Add a relay activity event for immediate forwards in the repository

**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`  
**Method:** `_handleForwardOrDeliver()` (around line ~395)

The immediate forward currently only prints a log. We need to also notify the relay stats system.

**Option A (Recommended — Simple Counter Stream):**

Add a new simple stream in the repository:
```dart
final _immediateForwardController = StreamController<String>.broadcast(); // emits packet ID
Stream<String> get immediateForwards => _immediateForwardController.stream;
```

In `_handleForwardOrDeliver()`, after `if (forwarded)`:
```dart
if (forwarded) {
  await _outbox.markSent(packet.id);
  _immediateForwardController.add(packet.id);   // ◀── NEW
}
```

Close in `dispose()`:
```dart
await _immediateForwardController.close();
```

#### Subtask 5.2: Update RelayOrchestrator to accept external forward events

**File:** `lib/features/mesh_network/data/services/relay_orchestrator.dart`

Add a method to increment the counter externally:
```dart
/// Notifies the orchestrator that a packet was forwarded outside its loop.
void recordExternalForward() {
  _packetsSent++;
  _updateStats();
}
```

#### Subtask 5.3: Wire the stream in MeshBloc

**File:** `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart`  
**Method:** `_setupSubscriptions()`

```dart
_immediateForwardSubscription = _repository.immediateForwards.listen((_) {
  _relayOrchestrator.recordExternalForward();
});
```

Add field, cancel in `close()`.

---

### PHASE 6: Verify Role Metadata Broadcasting

> **Goal:** Confirm that the existing role metadata logic is correct and consistent.

#### Subtask 6.1: Audit `_buildNodeMetadata()` — Already Correct

**File:** `mesh_repository_impl.dart`, lines ~462-478

```dart
'rol': hasInternet ? 'g' : _currentRole,
```

This is ALREADY correct:
- `hasInternet = true` → role `'g'` (goal)
- `hasInternet = false` → `_currentRole` (defaults to `'r'` for relay, set to `'s'` when sending SOS)

**No change needed.** But verify during testing that `_currentRole` is correctly set.

#### Subtask 6.2: Audit `_onConnectivityChanged()` — Already Correct

**File:** `mesh_bloc.dart`, lines ~497-505

When connectivity changes, it already calls `_repository.updateMetadata()` which re-broadcasts the TXT record with updated `net` and `rol` values.

**No change needed.**

#### Subtask 6.3: Audit `NodeInfo.isGoalNode` — Verify Consistency

**File:** `node_info.dart`

The `isGoalNode` getter should return `hasInternet` (not `role == 'goal'`), because `hasInternet` is the authoritative source. Check that all consumers use `hasInternet` not `role`.

**Likely no change needed**, but verify.

---

## 6. File Change Map

| Phase | File | Changes |
|-------|------|---------|
| **1** | `mesh_repository_impl.dart` | Add `_relayedSosController`, `relayedSosAlerts` getter, modify `_processIncomingPacket()`, close in `dispose()` |
| **2** | `mesh_bloc.dart` | Add `_RelayedSosReceived` event, `relayedSosCount` to `MeshActive`, handler, subscription, cancel |
| **3** | `relay_mode_page.dart` | Accept + display `relayedSosCount`, add auto-log on count change |
| **4** | `responder_mode_page.dart` | Add `isGoalNode && hasInternet` guard for SOS list |
| **5** | `mesh_repository_impl.dart` | Add `_immediateForwardController` stream |
| **5** | `relay_orchestrator.dart` | Add `recordExternalForward()` method |
| **5** | `mesh_bloc.dart` | Wire immediate forward stream → orchestrator |
| **6** | N/A (audit only) | Verify existing code, no changes expected |

**Total files modified: 4** (`mesh_repository_impl.dart`, `mesh_bloc.dart`, `relay_mode_page.dart`, `responder_mode_page.dart`)  
**Total files audited: 2** (`node_info.dart`, `internet_probe.dart`)

---

## 7. Testing Strategy

### Test Case 1: Relay Node Does NOT Show SOS in "I Can Help"
1. Device B has Wi-Fi Direct ON, mobile data OFF (no internet).
2. Device A sends SOS.
3. On Device B: Open "I Can Help" → should say "No emergencies" (empty list).
4. On Device B: Open "Relay Mode" → should show "SOS Relayed: 1".

### Test Case 2: Goal Node Shows SOS in "I Can Help"
1. Device C has Wi-Fi Direct ON, mobile data ON (has internet).
2. Device A sends SOS → relayed through B → arrives at C.
3. On Device C: Open "I Can Help" → should show the SOS alert card with details.

### Test Case 3: Multi-Hop A → B → C
1. A sends SOS (sender, no internet).
2. B receives (relay, no internet) → auto-forwards to C.
3. C receives (goal, has internet) → shows in "I Can Help", delivers to cloud.
4. Verify: B's relay mode shows "SOS Relayed: 1", C's responder shows 1 alert.

### Test Case 4: Relay Node Queues When No Next Hop
1. Only A and B are nearby. C is not yet discovered.
2. A sends SOS to B.
3. B receives SOS, immediate forward fails (no neighbors).
4. Packet is in B's outbox.
5. C comes into range — RelayOrchestrator picks up packet within 10s and forwards.

### Test Case 5: Internet Status Change Mid-Session
1. Device B starts with internet (goal) → receives SOS → shows in "I Can Help".
2. B loses internet → role changes to relay.
3. New SOS arrives → should NOT appear in "I Can Help", should increment relay counter.
4. B regains internet → next SOS appears in "I Can Help" again.

### Test Case 6: Loop Prevention
1. A → B → C, C → B (C has no route forward, tries B).
2. B should reject the packet because B is already in the packet's hop trace.
3. Verify via logcat that the loop detector fires.

---

## Summary of Root Causes vs Fixes

| Root Cause | Fix Location | Fix Description |
|------------|-------------|-----------------|
| SOS emitted unconditionally | Repository `_processIncomingPacket` | Check `_internetProbe.hasInternet` before choosing stream |
| No relay SOS stream | Repository class fields | Add `_relayedSosController` + getter |
| BLoC adds all SOS to alerts | BLoC event/handler | New `_RelayedSosReceived` event wired to separate counter |
| Responder page has no guard | Responder page builder | Add `hasInternet` check before reading alerts |
| Relay stats miss immediate forwards | Repository + Orchestrator | New `immediateForwards` stream + `recordExternalForward()` |

**Implementation order matters:** Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6. Each phase can be built and tested independently, but they build on each other.
