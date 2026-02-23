# Ultra Pro RescueNet — Comprehensive Bug Fix Plan (CORRECTED)

**Date:** 2026-02-23 (Corrected: 2026-02-23)
**Test Scenario:** 3-phone mesh: OnePlus (SOS Sender) → Oppo (Relay) → Redmi (Goal)
**Observed Issues:** Routing loop in relay UI, SOS button unresponsive, high drop count

---

## CRITICAL CORRECTION — Root Cause from Device Logs

The initial analysis incorrectly assumed BUG-M1 was about metadata role priority alone.
**The TRUE root cause chain** (proven by d2_full.txt lines 170-193):

1. OnePlus sends SOS → Oppo via Wi-Fi P2P connect-and-send
2. The Wi-Fi P2P group formation gives OnePlus temporary network routing through GO's interface
3. InternetProbe runs during P2P connection and detects this as "internet": `HTTP probe result=true (✓, ✗, ✗)` — **only 1 of 3 endpoints**
4. `_buildNodeMetadata()` immediately overrides `rol=s` → `rol=g` because `hasInternet ? 'g' : _currentRole`
5. Updated metadata `{net=1, rol=g}` is re-broadcast via DNS-SD TXT record
6. Oppo discovers OnePlus with `net=1` → shows GOAL badge on the SOS SENDER

**Additionally:** d2_disc.txt shows the internet probe flapping (true→false→true within 40 seconds), causing metadata to oscillate.

**SOS triple-fire:** d2_full.txt lines 26-31 show `_onSendSos triggered` THREE TIMES within 3 seconds (15:46:18, 15:46:19, 15:46:21), creating 3 duplicate outbox packets.

---

## Bug Summary

| ID    | Severity | Title                                       | Status     |
|-------|----------|---------------------------------------------|------------|
| BUG-P1 | 🔴 Critical | InternetProbe false positive via P2P link (1/3 = true) | Open |
| BUG-P2 | 🔴 Critical | InternetProbe flapping — no debounce/stabilization | Open |
| BUG-M1 | 🔴 Critical | Sender role overridden by internet in `_buildNodeMetadata` | Open |
| BUG-R1 | 🔴 Critical | Relay UI shows ALL neighbors (no sender/originator filtering) | Open |
| BUG-R2 | 🟡 High     | GOAL badge solely based on `hasInternet`, ignores role | Open |
| BUG-S1 | 🟡 High     | SOS button triple-fire — debounce auto-resets too early | Open |
| BUG-S2 | 🟡 High     | No duplicate SOS guard in MeshBloc._onSendSos | Open |
| BUG-R3 | 🟠 Medium   | Drop counter inflated by retry failures | Open |

---

## Detailed Analysis & Fix Plans

---

### BUG-R1: Relay UI Shows SOS Sender as Forward Target (ROUTING LOOP)

**Observed:** Oppo relay page "Forward Targets" shows OnePlus (the SOS sender) as the #1 forward target, creating a visual loop. The screenshots show OnePlus listed with a "GOAL" badge even though it is the originator of the SOS packet.

**Root Cause:**
`relay_mode_page.dart` → `_buildForwardTargetsSection(List<NodeInfo> neighbors)` receives the RAW neighbor list from `MeshState.neighbors` and displays ALL of them sorted by a simple score. It does NOT:
1. Filter out nodes that are SOS originators
2. Filter out nodes already in any pending packet's trace
3. Apply the AI Router's eligibility filtering

The AI Router (`ai_router.dart` → `_filterEligibleNodes`) correctly excludes the originator and sender, but **the UI bypasses the AI Router entirely**.

**Fix Plan:**

**File:** `lib/features/mesh_network/presentation/pages/relay_mode_page.dart`

1. **Add packet-aware filtering to the Forward Targets display:**
   - Accept the current pending outbox packets (or at minimum the originator IDs) in the UI
   - Filter neighbor list to exclude:
     - Nodes whose `id` matches any pending packet's `originatorId`
     - Nodes with role `'sender'` (they should never be forwarding targets)
   - Show a "(sender)" or "SOS SENDER" badge on excluded nodes if they remain visible for transparency

2. **Leverage `MeshState` to carry originator exclusion data:**
   - Add `Set<String> excludedOriginatorIds` to `MeshActive` state
   - Populate from outbox/recent SOS packets
   - The relay page reads this set and filters the display list

**Simpler alternative (recommended):** Filter directly in the UI using `node.role`:
```dart
final forwardCandidates = neighbors.where((n) => n.role != NodeInfo.roleSender).toList();
```
Plus, for packets currently in the outbox, extract originator IDs and filter those too.

---

### BUG-R2: Sender Node Shown With "GOAL" Badge

**Observed:** OnePlus has internet and appears with a green "GOAL" badge on the Oppo relay page, even though it is the SOS sender.

**Root Cause (Dual):**

1. **Metadata priority bug** (`mesh_repository_impl.dart` line ~466):
   ```dart
   'rol': hasInternet ? 'g' : _currentRole,
   ```
   If OnePlus has internet AND has sent an SOS (`_currentRole = 's'`), the metadata still broadcasts `rol=g` because internet check takes precedence. Other nodes see OnePlus as a "goal" node.

2. **UI badge logic** (`relay_mode_page.dart` line ~415):
   ```dart
   final isGoal = node.hasInternet;
   ```
   The "GOAL" badge is based solely on `hasInternet`, ignoring the node's actual role.

**Fix Plan:**

**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`
- Change metadata role priority: **Sender role MUST take precedence over goal**
  ```dart
  // FIX BUG-R2: Sender role takes precedence — a node that sent an SOS
  // should NEVER advertise as goal, even if it has internet.
  // Other nodes must not route the sender's own SOS back to it.
  'rol': _currentRole == 's' ? 's' : (hasInternet ? 'g' : _currentRole),
  ```

**File:** `lib/features/mesh_network/presentation/pages/relay_mode_page.dart`
- Fix the "GOAL" badge to also check role:
  ```dart
  final isGoal = node.hasInternet && node.role != NodeInfo.roleSender;
  ```

---

### BUG-R3: Forward Targets List Shows Raw Unfiltered Neighbors

**Observed:** The relay page shows every discovered neighbor regardless of their routing eligibility. This confuses operators who assume the listed nodes are actual forwarding candidates.

**Root Cause:** `_buildForwardTargetsSection` receives raw `state.neighbors` and sorts purely by local `_calculateNodeScore()` without any awareness of:
- Pending packets and their traces
- Originator IDs (sender nodes to exclude)
- AI Router filtering rules (stale, in-trace, not available for relay)

**Fix Plan:**

**File:** `lib/features/mesh_network/presentation/pages/relay_mode_page.dart`

1. Create a `_getFilteredForwardTargets(List<NodeInfo> neighbors)` method that:
   - Filters out `role == 'sender'` nodes
   - Filters out nodes that appear as `originatorId` in any pending outbox packet
   - Optionally annotates remaining nodes (e.g., "AI PICK", "LOW BATTERY")

2. For advanced display, split the list into:
   - **Viable Targets**: Nodes the AI Router would actually select
   - **Excluded Nodes**: Shown grayed out with reason (e.g., "SOS Sender", "Stale", "Low Battery")

**File:** `lib/features/mesh_network/presentation/bloc/mesh/mesh_state.dart`

3. Add `pendingOriginatorIds` or `excludedNodeIds` field to `MeshActive`:
   ```dart
   final Set<String> sosOriginatorIds; // IDs of SOS originators in outbox
   ```

**File:** `lib/features/mesh_network/presentation/bloc/mesh/mesh_bloc.dart`

4. Update `_onRelayedSosReceived` to track the originator ID:
   ```dart
   emit(currentState.copyWith(
     relayedSosCount: currentState.relayedSosCount + 1,
     sosOriginatorIds: {...currentState.sosOriginatorIds, event.sos.packet.originatorId},
   ));
   ```

---

### BUG-R4: "Dropped" Counter Inflated

**Observed:** Screenshot shows 6 "Dropped" after just 1-2 SOS packets. The "Dropped" label maps to `stats.packetsFailed`.

**Root Cause:** The `RelayOrchestrator` retries every 10 seconds. Each retry where no viable route exists counts as a failure:
- Packet is in outbox
- Orchestrator runs `_processPacket` → AI Router filters out sender → 0 eligible nodes → counted as `_packetsFailed++`
- After 3 consecutive failures, orchestrator pauses 30 seconds then resets counter

So the Dropped count accumulates rapidly for packets that have no viable route (e.g., the only neighbor is the sender). The count represents **retry failures**, not unique dropped packets.

**Fix Plan:**

**File:** `lib/features/mesh_network/data/services/relay_orchestrator.dart`

1. **Distinguish between "no route, will retry" and "permanently dropped":**
   ```dart
   int _retryFailures = 0;    // Temporary failures
   int _permanentDrops = 0;   // TTL expired / max retries exceeded
   ```

2. Only increment `_permanentDrops` when a packet is actually removed from the outbox (TTL expired or max retries). Expose both counts in `RelayStats`.

**File:** `lib/features/mesh_network/presentation/pages/relay_mode_page.dart`

3. Change "Dropped" label to show permanent drops only. Add a separate indicator for retry failures if needed:
   ```dart
   value: stats.permanentDrops.toString(),
   label: 'Dropped',
   ```

4. **Add "Pending" stat card** to show packets still waiting for a route:
   ```dart
   value: stats.pendingCount.toString(),
   label: 'Pending',
   ```

---

### BUG-S1: SOS Button Requires 2-3 Clicks

**Observed:** User has to tap the "SEND EMERGENCY SOS" button multiple times before it responds.

**Root Cause (Multi-factor):**

1. **Auto-start delay:** When mesh is in `MeshReady` state (most common for survivors), the first tap triggers:
   - `_sendSos()` → BLoC `_onSendSos` detects `MeshReady` → emits `MeshLoading` → starts mesh (async, involves native Wi-Fi P2P init) → emits `MeshActive` → sends SOS
   - This takes several seconds during which the button shows "CONNECTING TO MESH..." but may not be obvious enough

2. **Debounce guard blocks second tap:** `_isSendingInProgress = true` fires immediately, blocking for 3 seconds. If the first tap's auto-start takes longer than 3 seconds, the guard resets but the first operation may still be in flight.

3. **BlocListener confirmation delay:** The `_awaitingSosConfirmation` flag only triggers the SnackBar + pop when `state.activeSosId != null`. If the BLoC handler is slow (due to auto-start), the user sees nothing and taps again.

4. **State type check mismatch in SOS form page:**
   ```dart
   final isMeshActive = state is MeshActive;
   final isLoading = state is MeshLoading;
   ```
   The `SosFormPage` uses the **old bloc** (`mesh/mesh_bloc.dart` with `MeshState` base class), but the new bloc events (`mesh_bloc.dart` at root `bloc/`) use `MeshActive`, `MeshReady`, etc. as separate subclasses. The `state is MeshActive` check may conflict.

**Fix Plan:**

**File:** `lib/features/mesh_network/presentation/pages/sos_form_page.dart`

1. **Show immediate loading feedback on first tap:**
   ```dart
   void _sendSos() {
     if (_isSendingInProgress) return;
     _isSendingInProgress = true;
     
     setState(() => _isSubmitting = true); // Show loading spinner IMMEDIATELY
     
     // ... rest of send logic
   }
   ```

2. **Add `_isSubmitting` state to show inline progress indicator** before the BLoC even processes the event. This gives instant visual feedback.

3. **Remove the 3-second auto-reset debounce** and instead tie the guard to actual BLoC state transitions:
   ```dart
   // Reset on BLoC state change (success or error)
   if (state is MeshActive && state.activeSosId != null) {
     _isSendingInProgress = false;
     _isSubmitting = false;
     // success path...
   } else if (state is MeshError) {
     _isSendingInProgress = false;
     _isSubmitting = false;
     // error path...
   }
   ```

4. **Pre-start mesh when SOS form opens** (if in `MeshReady`):
   ```dart
   @override
   void initState() {
     super.initState();
     _loadLocation();
     _scanDevices();
     _ensureMeshActive(); // NEW: pre-start mesh before user taps SOS
   }
   
   void _ensureMeshActive() {
     final state = context.read<MeshBloc>().state;
     if (state is MeshReady) {
       context.read<MeshBloc>().add(const MeshStart());
     }
   }
   ```
   This way, by the time the user fills the form and taps Send, the mesh is already active.

---

### BUG-S2: No Immediate Visual Feedback on SOS Tap

**Observed:** After tapping SOS, there's a noticeable delay with no visual change, making users think the button didn't register.

**Fix Plan:**

**File:** `lib/features/mesh_network/presentation/pages/sos_form_page.dart`

1. Add `_isSubmitting` bool state variable
2. When `_sendSos()` is called, immediately `setState(() => _isSubmitting = true)`
3. In `_buildSosButton()`, when `_isSubmitting` is true:
   - Show a CircularProgressIndicator
   - Change button text to "SENDING SOS..."
   - Disable the button (`onPressed: null`)
4. Reset `_isSubmitting` in BlocListener on success or error

---

### BUG-M1: Metadata Role Priority Override

**Observed:** A node that sends an SOS while having internet broadcasts `rol=g` instead of `rol=s`, causing other nodes to see it as a goal and try to route packets TO it.

**Root Cause:** In `_buildNodeMetadata()`:
```dart
'rol': hasInternet ? 'g' : _currentRole,
```
Internet takes precedence over sender role.

**Fix Plan:**

**File:** `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart`

```dart
// FIX BUG-M1: Sender role MUST override goal.
// A node that sent an SOS must never advertise as goal — its own SOS would
// be routed back to itself, creating a mesh loop.
String _computeRole(bool hasInternet) {
  if (_currentRole == 's') return 's';  // Sender always takes priority
  if (hasInternet) return 'g';           // Goal if has internet
  return _currentRole;                   // Default (relay)
}
```

Update `_buildNodeMetadata()`:
```dart
'rol': _computeRole(hasInternet),
```

---

### BUG-M2: `packet.sender` May Return Self After Hop Addition

**Observed:** After a relay node adds its own hop via `addHop(nodeId)`, `packet.sender` (which returns `trace.last`) points to the relay node itself, not the node that sent it.

**Root Cause:** The `sender` getter returns `lastHop` = `trace.last`. After the receiving node adds its own hop, `trace.last` is now itself. The intent of `sender` is to identify the **previous** node that delivered this packet.

This doesn't break forwarding (because the AI Router checks `packet.hasVisited(node.id)` which covers the originator), but it means the "sender exclusion" rule in NeighborScorer effectively becomes a self-exclusion:
```dart
if (packet.sender == neighbor.id) {  // After addHop, sender == self, not previous hop
  return penaltySender;
}
```

**Fix Plan:**

**File:** `lib/features/mesh_network/domain/entities/mesh_packet.dart`

Change `sender` to return the **second-to-last** entry (the true previous hop), or better, return the entry before `currentNodeId`:

```dart
/// Returns the node that delivered this packet to us (= the hop before the last).
/// If trace has < 2 entries, returns null (we are the originator).
String? get previousHop {
  if (trace.length < 2) return null;
  return trace[trace.length - 2];
}

/// For backward compat — sender = the node right before us in the trace.
String? get sender => previousHop;
```

**BUT CAUTION:** This property is called BEFORE addHop in the AI Router (since the router gets the packet as-received). So the current `trace.last` IS the previous sender at that point. The bug only manifests if `sender` is checked AFTER `addHop`. 

**Safer fix:** Document clearly and ensure `sender` is only called on the as-received packet (before addHop). Or carry an explicit `sender` field on the packet.

---

## Implementation Priority Order

| Priority | Bug ID | Effort | Impact |
|----------|--------|--------|--------|
| 1 | BUG-M1 | Small | Fixes root cause of sender appearing as goal |
| 2 | BUG-R2 | Small | Fixes GOAL badge on sender nodes |
| 3 | BUG-R1 + R3 | Medium | Filters relay UI to show only viable targets |
| 4 | BUG-S1 + S2 | Medium | SOS button responsiveness |
| 5 | BUG-R4 | Small | Accurate drop counting |
| 6 | BUG-M2 | Small | Defensive sender property fix |

---

## Files To Modify

| File | Bugs Addressed |
|------|----------------|
| `lib/features/mesh_network/data/repositories/mesh_repository_impl.dart` | BUG-M1 |
| `lib/features/mesh_network/presentation/pages/relay_mode_page.dart` | BUG-R1, R2, R3, R4 |
| `lib/features/mesh_network/presentation/pages/sos_form_page.dart` | BUG-S1, S2 |
| `lib/features/mesh_network/presentation/bloc/mesh_bloc.dart` | BUG-R3 (originator tracking) |
| `lib/features/mesh_network/presentation/bloc/mesh/mesh_state.dart` | BUG-R3 (state field) |
| `lib/features/mesh_network/data/services/relay_orchestrator.dart` | BUG-R4 |
| `lib/features/mesh_network/domain/entities/mesh_packet.dart` | BUG-M2 |

---

## Testing Checklist

After implementing fixes, verify with the 3-phone test:

- [ ] **Relay UI shows only Redmi (goal) as forward target, NOT OnePlus (sender)**
- [ ] **OnePlus broadcasts `rol=s` metadata, never `rol=g` during active SOS**
- [ ] **SOS button responds on FIRST tap with immediate loading indicator**
- [ ] **"Dropped" counter only shows permanently dropped packets, not retries**
- [ ] **Packet successfully routes: OnePlus → Oppo → Redmi (no loop)**
- [ ] **Forwarded counter increments when packet reaches Redmi**
- [ ] **No sender node appears with "GOAL" badge on any relay display**
