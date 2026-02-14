# RescueNet Pro - Design Document

## 1. System Architecture Overview

### 1.1 High-Level Architecture

RescueNet Pro follows a **Clean Architecture** pattern with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  (Flutter UI, BLoC State Management, Pages, Widgets)        │
└─────────────────────────────────────────────────────────────┘
                            ↓ ↑
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  (Entities, Use Cases, Repository Interfaces, Services)     │
└─────────────────────────────────────────────────────────────┘
                            ↓ ↑
┌─────────────────────────────────────────────────────────────┐
│                       Data Layer                             │
│  (Repository Impl, Data Sources, Models, Services)          │
└─────────────────────────────────────────────────────────────┘
                            ↓ ↑
┌─────────────────────────────────────────────────────────────┐
│                    Platform Layer                            │
│  (Android Native: Wi-Fi P2P, Sockets, Permissions)          │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Technology Stack

**Frontend (Flutter)**
- Flutter SDK 3.10.7+
- Dart language
- BLoC pattern for state management
- GetIt for dependency injection
- Hive for local storage

**Backend (Android Native)**
- Kotlin for native Android code
- Wi-Fi P2P Manager for device discovery
- Socket programming for data transmission
- Foreground Service for background operations

**Key Libraries**
- flutter_bloc: State management
- equatable: Value equality
- dartz: Functional programming
- hive: Local database
- geolocator: GPS location
- flutter_map: Map visualization
- connectivity_plus: Network status
- permission_handler: Runtime permissions

---

## 2. Architectural Layers


### 2.1 Presentation Layer

**Responsibility**: User interface and user interaction handling

**Components**:

1. **Pages**
   - `HomePage`: Role selection screen
   - `SosFormPage`: Emergency SOS creation form
   - `ResponderModePage`: View and respond to SOS alerts
   - `RelayModePage`: Relay node dashboard
   - `DiagnosticPage`: System diagnostics and debugging
   - `DashboardPage`: Network overview
   - `SettingsPage`: App configuration

2. **BLoC (Business Logic Components)**
   - `MeshBloc`: Main state management for mesh network
   - `ConnectivityBloc`: Network connectivity state
   - `DiscoveryBloc`: Device discovery state
   - `TransmissionBloc`: Packet transmission state

3. **Widgets**
   - `SosButton`: Emergency SOS trigger
   - `TacticalMapView`: Map with mesh nodes
   - `TacticalBackground`: Themed background
   - Status indicators, node lists, packet history

**State Management Pattern**:
```dart
Events → BLoC → States → UI Updates
```

**Key States**:
- `MeshInitial`: Before initialization
- `MeshLoading`: Initializing
- `MeshReady`: Initialized but not active
- `MeshActive`: Mesh network running
- `MeshError`: Error state

### 2.2 Domain Layer

**Responsibility**: Business logic and core entities (framework-independent)

**Entities**:

1. **MeshPacket**
   - Unique ID (UUID)
   - Originator ID
   - Payload (JSON string)
   - Trace (list of visited node IDs)
   - TTL (Time-To-Live, max 10 hops)
   - Timestamp
   - Priority (0-3, where 3 is critical SOS)
   - Packet Type (SOS, ACK, Status, Data)

2. **NodeInfo**
   - Node ID
   - Device address (MAC)
   - Display name
   - Battery level (0-100)
   - Has internet (Goal Node flag)
   - GPS coordinates (lat/lng)
   - Last seen timestamp
   - Signal strength (dBm)
   - Triage level
   - Role (sender/relay/goal/idle)

3. **SosPayload**
   - SOS ID
   - Sender info
   - Location (lat/lng, accuracy)
   - Emergency type
   - Triage level
   - Number of people
   - Medical conditions
   - Required supplies
   - Additional notes
   - Timestamp

4. **RoutingEntry**
   - Destination node ID
   - Next hop node ID
   - Hop count
   - Last updated

**Use Cases**:

1. **Discovery**
   - `StartDiscoveryUseCase`: Initialize device discovery
   - `StopDiscoveryUseCase`: Stop discovery
   - `UpdateMetadataUseCase`: Update broadcast metadata

2. **Transmission**
   - `BroadcastSosUseCase`: Send SOS alert
   - `RelayPacketUseCase`: Forward packet to next hop
   - `AcknowledgePacketUseCase`: Send ACK response

3. **Processing**
   - `ProcessIncomingPacketUseCase`: Handle received packets
   - `ValidatePacketUseCase`: Validate packet integrity
   - `DeduplicatePacketUseCase`: Check for duplicates

**Services**:

1. **Routing**
   - `AiRouter`: Main routing decision engine
   - `NeighborScorer`: Q-Learning based scoring algorithm
   - `RouteOptimizer`: Route optimization logic

2. **Relay**
   - `RelayOrchestrator`: Manages relay operations
   - `PacketQueue`: Priority queue for pending packets
   - `RetryManager`: Handles failed packet retries

3. **Validation**
   - `PacketValidator`: Validates packet structure
   - `TraceValidator`: Validates packet trace
   - `TtlValidator`: Validates TTL

### 2.3 Data Layer

**Responsibility**: Data access and external communication

**Repositories** (Implementations):

1. **MeshRepositoryImpl**
   - Coordinates mesh network operations
   - Manages data sources
   - Implements domain repository interfaces

2. **NodeRepositoryImpl**
   - Manages node information
   - Handles node discovery data

3. **RoutingRepositoryImpl**
   - Manages routing table
   - Handles route updates

**Data Sources**:

1. **Remote (Wi-Fi P2P)**
   - `WifiP2pSource`: Flutter-Native bridge for Wi-Fi P2P
   - Handles device discovery
   - Manages connections
   - Sends/receives packets

2. **Local (Storage)**
   - `OutboxBox`: Hive box for pending packets
   - `SeenPacketCache`: LRU cache for deduplication
   - `NodeCache`: Cached node information
   - `RoutingTableCache`: Cached routing data

**Services**:

1. **CloudDeliveryService**
   - Delivers packets to cloud when internet available
   - HTTP client for API calls

2. **InternetProbe**
   - Periodically checks internet connectivity
   - Marks device as Goal Node when online

3. **RelayOrchestrator**
   - Background relay loop (every 10 seconds)
   - Processes outbox packets
   - Applies AI routing
   - Manages retries

**Models** (Data Transfer Objects):
- `MeshPacketModel`: Serializable packet
- `NodeMetadataModel`: Serializable node info
- `RoutingTableModel`: Serializable routing table
- `AckPacketModel`: Acknowledgment packet

### 2.4 Platform Layer (Android Native)

**Responsibility**: Android-specific implementations

**Components**:

1. **MainActivity.kt**
   - Flutter activity
   - Initializes Wi-Fi P2P Manager
   - Registers broadcast receivers
   - Sets up method/event channels

2. **WifiP2pHandler.kt**
   - Handles Wi-Fi Direct operations
   - DNS-SD service registration
   - Service discovery
   - Peer discovery
   - Connection management
   - Socket communication

3. **MeshService.kt**
   - Foreground service for background operation
   - Maintains wake lock
   - Shows persistent notification

4. **ConnectionManager.kt**
   - Manages Wi-Fi P2P connections
   - Handles connection lifecycle
   - Group formation and removal

5. **SocketServerManager.kt**
   - TCP socket server on port 8888
   - Receives incoming packets
   - Sends ACK/NAK responses

6. **GeneralHandler.kt**
   - Permission management
   - Device info provider
   - Battery status

7. **DiagnosticUtils.kt**
   - Wi-Fi P2P readiness checks
   - Permission status
   - Network diagnostics

---

## 3. Core Algorithms

### 3.1 AI-Powered Routing Algorithm

**Q-Learning Inspired Scoring**:

```
Score = (Internet Weight × Has Internet) +
        (Battery Weight × Normalized Battery) +
        (Signal Weight × Normalized Signal)

Where:
- Internet Weight = 50 points
- Battery Weight = 25 points
- Signal Weight = 10 points
- Normalized Battery = battery_level / 100
- Normalized Signal = (signal_strength + 90) / 60
```

**Routing Decision Process**:

1. **Filter Phase**
   - Remove nodes in packet trace (loop prevention)
   - Remove packet originator
   - Remove sender (immediate loop prevention)
   - Remove stale nodes (not seen in 2 minutes)
   - Remove unavailable nodes (unless SOS packet)

2. **Scoring Phase**
   - Calculate score for each eligible node
   - Apply Q-Learning formula
   - Sort by score (descending)

3. **Selection Phase**
   - Select highest-scoring node
   - Return null if no viable candidates

**Special Cases**:
- Goal Nodes (has internet) get +50 bonus
- SOS packets bypass availability filter
- Stale nodes are always excluded

### 3.2 Loop Prevention

**Trace-Based Prevention**:
- Each packet maintains ordered list of visited node IDs
- Before forwarding, check if target node is in trace
- Reject packet if loop detected

**TTL-Based Prevention**:
- Each packet has TTL (default 10)
- TTL decrements at each hop
- Packet dropped when TTL reaches 0

**Sender Exclusion**:
- Never forward packet back to sender
- Sender is second-to-last node in trace

### 3.3 Packet Deduplication

**Seen Packet Cache**:
- LRU cache with max 1000 entries
- Key: Packet ID
- Value: Timestamp
- Packets in cache are rejected

**Cache Eviction**:
- Least recently used packets evicted first
- Automatic cleanup on size limit

### 3.4 Retry Logic

**Exponential Backoff**:
- Initial retry delay: 2 seconds
- Max retries: 5
- Backoff multiplier: 2x
- Max delay: 32 seconds

**Retry Conditions**:
- Connection failure
- Transmission timeout
- NAK response
- No viable route (temporary)

**Abort Conditions**:
- TTL expired
- Max retries exceeded
- Packet too old (60 minutes)

---

## 4. Data Flow Diagrams

### 4.1 SOS Sending Flow

```
User (SOS Form)
    ↓
[Fill Emergency Details]
    ↓
[Tap "Send SOS"]
    ↓
MeshBloc (MeshSendSos event)
    ↓
MeshRepository.sendSos()
    ↓
Create MeshPacket (priority=3, type=SOS)
    ↓
Add to Outbox
    ↓
RelayOrchestrator (background loop)
    ↓
Get Neighbors from Discovery
    ↓
AiRouter.selectBestNode()
    ↓
[Filter → Score → Select]
    ↓
WifiP2pSource.connectAndSend()
    ↓
[Native: Connect via Wi-Fi P2P]
    ↓
[Native: Send via Socket]
    ↓
[Native: Wait for ACK]
    ↓
Success → Remove from Outbox
Failure → Retry with backoff
```

### 4.2 Packet Receiving Flow

```
[Native: Socket Server receives packet]
    ↓
SocketServerManager.onPacketReceived()
    ↓
[Send to Flutter via Event Channel]
    ↓
WifiP2pSource.packetStream
    ↓
MeshRepository.processIncomingPacket()
    ↓
[Check Seen Cache]
    ↓
Duplicate? → Drop
    ↓
[Validate Packet]
    ↓
Invalid? → Drop
    ↓
[Check if for me]
    ↓
Has Internet? → Deliver to Cloud
    ↓
[Add to Outbox for relay]
    ↓
[Emit to UI if SOS]
    ↓
RelayOrchestrator picks up from Outbox
```

### 4.3 Discovery Flow

```
[User starts mesh node]
    ↓
MeshBloc.add(MeshStart)
    ↓
MeshRepository.startMesh()
    ↓
WifiP2pSource.startMeshNode(metadata)
    ↓
[Native: Register DNS-SD Service]
    ↓
[Native: Start Service Discovery]
    ↓
[Native: Start Peer Discovery]
    ↓
[Native: Setup DNS-SD Listeners]
    ↓
[Refresh every 15 seconds]
    ↓
[On Service Found]
    ↓
[Parse TXT Record]
    ↓
Create NodeInfo
    ↓
[Send to Flutter via Event Channel]
    ↓
MeshRepository.neighborsStream
    ↓
MeshBloc updates state
    ↓
UI displays neighbors
```

---

## 5. Database Schema

### 5.1 Hive Boxes

**OutboxBox** (Pending Packets)
```dart
{
  'packet_id': {
    'packet': MeshPacketModel,
    'retryCount': int,
    'lastAttempt': DateTime,
    'createdAt': DateTime,
  }
}
```

**SeenPacketCache** (Deduplication)
```dart
{
  'packet_id': DateTime (last seen)
}
```

**NodeCache** (Discovered Nodes)
```dart
{
  'node_id': NodeMetadataModel
}
```

**RoutingTableCache** (Routes)
```dart
{
  'destination_id': RoutingEntry
}
```

---

## 6. API Specifications

### 6.1 Flutter-Native Method Channel

**Channel**: `com.rescuenet/wifi_p2p/discovery`

**Methods**:

1. **startMeshNode**
   - Input: `Map<String, String>` metadata
   - Output: `bool` success
   - Description: Starts mesh node with metadata

2. **updateMetadata**
   - Input: `Map<String, String>` metadata
   - Output: `bool` success
   - Description: Updates broadcast metadata

3. **stopMeshNode**
   - Input: None
   - Output: `bool` success
   - Description: Stops mesh node

4. **connectAndSend**
   - Input: `String` deviceAddress, `String` packetJson
   - Output: `bool` success
   - Description: Connects to device and sends packet

5. **getDiagnostics**
   - Input: None
   - Output: `Map<String, dynamic>` diagnostics
   - Description: Returns system diagnostics

### 6.2 Flutter-Native Event Channel

**Channel**: `com.rescuenet/wifi_p2p/discovery_events`

**Events**:

1. **servicesFound**
   ```dart
   {
     'type': 'servicesFound',
     'services': [
       {
         'deviceName': String,
         'deviceAddress': String,
         'id': String,
         'bat': String,
         'net': String,
         'lat': String,
         'lng': String,
         'sig': String,
         'tri': String,
         'rol': String,
         'rel': String,
       }
     ]
   }
   ```

2. **packetReceived**
   ```dart
   {
     'type': 'packetReceived',
     'data': String (JSON packet)
   }
   ```

### 6.3 DNS-SD TXT Record Format

**Service Name**: `RescueNet`  
**Service Type**: `_rescuenet._tcp`

**TXT Record Keys** (abbreviated for size):
- `id`: Node ID
- `bat`: Battery level (0-100)
- `net`: Has internet (0/1)
- `lat`: Latitude (6 decimals)
- `lng`: Longitude (6 decimals)
- `sig`: Signal strength (dBm)
- `tri`: Triage level (n/g/y/r)
- `rol`: Role (s/r/g/i)
- `rel`: Available for relay (0/1)

### 6.4 Socket Protocol

**Port**: 8888  
**Protocol**: TCP

**Packet Format**:
```
[4 bytes: Packet Size (big-endian)]
[N bytes: JSON Packet Data (UTF-8)]
```

**Response**:
```
[1 byte: ACK (0x06) or NAK (0x15)]
```

---

## 7. Security Considerations

### 7.1 Current Security Measures

1. **Packet Validation**
   - JSON schema validation
   - Required field checks
   - Type validation

2. **Loop Prevention**
   - Trace validation
   - TTL enforcement
   - Sender exclusion

3. **Resource Protection**
   - Seen packet cache (prevents replay)
   - Outbox size limit
   - TTL prevents infinite propagation

4. **Input Sanitization**
   - User input validation
   - Packet size limits
   - Field length limits

### 7.2 Future Security Enhancements

1. **Encryption**
   - End-to-end encryption for packets
   - Public key infrastructure
   - Secure key exchange

2. **Authentication**
   - Node identity verification
   - Digital signatures
   - Certificate-based trust

3. **Privacy**
   - Location obfuscation options
   - Anonymous mode
   - Data minimization

---

## 8. Performance Optimization

### 8.1 Network Optimization

1. **Discovery Intervals**
   - Service discovery: 15 seconds
   - Peer discovery: 20 seconds
   - Adaptive intervals based on battery

2. **Connection Pooling**
   - Reuse connections when possible
   - Connection timeout: 10 seconds
   - Socket timeout: 5 seconds

3. **Packet Compression**
   - JSON minification
   - Future: Binary protocol

### 8.2 Memory Optimization

1. **Caching Strategy**
   - LRU cache for seen packets
   - Size limits on all caches
   - Periodic cleanup

2. **Object Pooling**
   - Reuse packet objects
   - Minimize allocations

3. **Stream Management**
   - Proper stream disposal
   - Subscription cleanup

### 8.3 Battery Optimization

1. **Wake Lock Management**
   - Partial wake lock only
   - Release when idle
   - Adaptive based on battery level

2. **Discovery Throttling**
   - Reduce frequency when battery low
   - Pause discovery when battery critical

3. **Background Optimization**
   - Efficient foreground service
   - Minimal CPU usage
   - Batch operations

---

## 9. Error Handling

### 9.1 Error Categories

1. **Network Errors**
   - Connection timeout
   - Connection refused
   - Socket errors
   - Wi-Fi P2P errors

2. **Validation Errors**
   - Invalid packet format
   - Missing required fields
   - TTL expired
   - Loop detected

3. **System Errors**
   - Permission denied
   - Wi-Fi disabled
   - Location unavailable
   - Storage full

### 9.2 Error Recovery Strategies

1. **Automatic Retry**
   - Connection failures
   - Temporary network issues
   - Exponential backoff

2. **Graceful Degradation**
   - Continue without GPS
   - Operate with low battery
   - Reduce discovery frequency

3. **User Notification**
   - Permission requests
   - Critical errors
   - Status updates

---

## 10. Testing Strategy

### 10.1 Unit Tests

**Domain Layer**:
- Entity validation
- Use case logic
- Routing algorithm
- Scoring calculations

**Data Layer**:
- Repository implementations
- Data source operations
- Model serialization

### 10.2 Integration Tests

**Flutter-Native Bridge**:
- Method channel calls
- Event channel streams
- Data serialization

**Mesh Network Flow**:
- End-to-end packet flow
- Discovery process
- Connection establishment

### 10.3 System Tests

**Multi-Device Testing**:
- 2-device mesh
- 5-device mesh
- 10+ device mesh

**Scenarios**:
- SOS sending and receiving
- Packet relay through multiple hops
- Network topology changes
- Battery drain testing

---

## 11. Deployment Architecture

### 11.1 Build Configuration

**Debug Build**:
- Debug symbols enabled
- Logging enabled
- No obfuscation

**Release Build**:
- ProGuard/R8 enabled
- Logging disabled
- Code obfuscation
- APK optimization

### 11.2 Distribution

**Google Play Store**:
- AAB (Android App Bundle)
- Staged rollout
- Beta testing track

**Direct APK**:
- Signed release APK
- For emergency distribution
- Sideloading support

---

## 12. Monitoring and Analytics

### 12.1 Metrics to Track

**Network Metrics**:
- Packet delivery success rate
- Average hop count
- Discovery latency
- Connection success rate

**Performance Metrics**:
- Battery drain rate
- Memory usage
- CPU usage
- Network bandwidth

**User Metrics**:
- SOS sent count
- SOS received count
- Relay operations
- Active users

### 12.2 Logging Strategy

**Log Levels**:
- ERROR: Critical failures
- WARN: Recoverable issues
- INFO: Important events
- DEBUG: Detailed debugging

**Log Categories**:
- Network operations
- Packet flow
- Discovery events
- Error conditions

---

## 13. Scalability Considerations

### 13.1 Current Limitations

- Wi-Fi Direct: 8 devices per group
- Discovery range: ~100 meters
- Packet TTL: 10 hops
- Outbox size: 100 packets

### 13.2 Scaling Strategies

1. **Horizontal Scaling**
   - Multiple mesh groups
   - Bridge nodes between groups
   - Hierarchical topology

2. **Protocol Optimization**
   - Binary protocol
   - Packet compression
   - Efficient routing tables

3. **Infrastructure Support**
   - Gateway nodes
   - Cloud relay
   - Hybrid mesh-cellular

---

## Document Control

**Version**: 1.0  
**Date**: February 14, 2026  
**Status**: Draft  
**Author**: RescueNet Development Team  
**Reviewers**: TBD  
**Approval**: TBD

---

## Appendix A: Glossary

- **Mesh Network**: Decentralized network where nodes relay data
- **Wi-Fi Direct**: Peer-to-peer Wi-Fi technology
- **DNS-SD**: DNS Service Discovery protocol
- **TTL**: Time-To-Live, hop limit for packets
- **Goal Node**: Device with internet connectivity
- **Relay Node**: Device forwarding packets
- **SOS**: Emergency distress signal
- **Triage**: Medical priority classification
- **Q-Learning**: Reinforcement learning algorithm
- **LRU**: Least Recently Used cache eviction

## Appendix B: References

- Android Wi-Fi P2P Documentation
- Flutter Documentation
- Clean Architecture by Robert C. Martin
- BLoC Pattern Documentation
- Mesh Networking Protocols
