# RescueNet Pro - Requirements Document

## 1. Project Overview

### 1.1 Project Name
**RescueNet Pro** - AI-Powered Mesh Emergency Network

### 1.2 Purpose
RescueNet Pro is a production-grade offline mesh networking application designed for disaster rescue scenarios. The application enables emergency communication and SOS broadcasting in environments where traditional cellular and internet infrastructure is unavailable or compromised.

### 1.3 Target Platform
- **Primary Platform**: Android (API 29+)
- **Framework**: Flutter 3.10.7+
- **Language**: Dart (Flutter), Kotlin (Android Native)

### 1.4 Core Value Proposition
- Operates completely offline using Wi-Fi Direct peer-to-peer mesh networking
- AI-powered intelligent routing for optimal packet delivery
- Emergency SOS broadcasting with detailed medical and location information
- Self-organizing mesh network with automatic relay capabilities

---

## 2. Functional Requirements

### 2.1 User Roles

#### 2.1.1 Sender (I Need Help)
- **FR-1.1**: User can create and send emergency SOS alerts
- **FR-1.2**: User can specify emergency type (Medical, Fire, Flood, Earthquake, Trapped, Injury, Other)
- **FR-1.3**: User can set severity level (Critical/Red, High/Yellow, Medium, Low/Green)
- **FR-1.4**: User can provide personal information (name, contact)
- **FR-1.5**: User can select medical conditions from predefined list
- **FR-1.6**: User can specify required supplies
- **FR-1.7**: System automatically captures GPS location with accuracy
- **FR-1.8**: User can view nearby mesh nodes before sending
- **FR-1.9**: System shows AI-recommended best node for transmission

#### 2.1.2 Responder (I Can Help)
- **FR-2.1**: User can view incoming SOS alerts in real-time
- **FR-2.2**: User can see SOS details including location, type, severity, medical conditions
- **FR-2.3**: User can view SOS alerts on an interactive map
- **FR-2.4**: User can filter and sort SOS alerts by distance, severity, or time
- **FR-2.5**: User can acknowledge receipt of SOS alerts
- **FR-2.6**: User can view their response history

#### 2.1.3 Relay Node
- **FR-3.1**: Device automatically relays packets without user intervention
- **FR-3.2**: System runs as foreground service to maintain connectivity
- **FR-3.3**: Device broadcasts availability to mesh network
- **FR-3.4**: System displays relay statistics (packets sent, failed, pending)
- **FR-3.5**: User can view network topology and connected nodes
- **FR-3.6**: System optimizes battery usage during relay operations

### 2.2 Mesh Network Operations

#### 2.2.1 Device Discovery
- **FR-4.1**: System discovers nearby devices using Wi-Fi Direct DNS-SD
- **FR-4.2**: Discovery refreshes every 15 seconds
- **FR-4.3**: System broadcasts device metadata (battery, internet status, location, signal strength)
- **FR-4.4**: Discovered devices are displayed with real-time status
- **FR-4.5**: System filters stale devices (not seen in 2 minutes)

#### 2.2.2 Packet Routing
- **FR-5.1**: System uses AI-powered routing algorithm for packet forwarding
- **FR-5.2**: Routing considers: internet availability (+50 points), battery level (+25 points scaled), signal strength (+10 points scaled)
- **FR-5.3**: System prevents routing loops using packet trace
- **FR-5.4**: Packets have Time-To-Live (TTL) with maximum 10 hops
- **FR-5.5**: System prioritizes SOS packets (priority level 3)
- **FR-5.6**: Failed packets are queued for retry (max 5 retries)
- **FR-5.7**: System delivers packets to "Goal Nodes" (devices with internet)

#### 2.2.3 Packet Management
- **FR-6.1**: Each packet has unique ID for deduplication
- **FR-6.2**: System maintains seen packet cache (max 1000 entries)
- **FR-6.3**: Packets include originator ID, payload, trace, TTL, timestamp, priority, type
- **FR-6.4**: System supports packet types: SOS, ACK, Status, Data
- **FR-6.5**: Outbox stores pending packets (max 100, expires after 60 minutes)

#### 2.2.4 Connection Management
- **FR-7.1**: System establishes Wi-Fi Direct connections on-demand
- **FR-7.2**: Socket communication on port 8888
- **FR-7.3**: Packet transmission includes size header (4 bytes) + JSON payload
- **FR-7.4**: System waits for ACK (0x06) or NAK response
- **FR-7.5**: Connections are automatically cleaned up after transmission
- **FR-7.6**: System binds sockets to P2P interface (192.168.49.x)

### 2.3 Location Services
- **FR-8.1**: System captures GPS coordinates with accuracy measurement
- **FR-8.2**: Location updates every 30 seconds (5 seconds in high-accuracy mode)
- **FR-8.3**: Minimum movement threshold: 5 meters
- **FR-8.4**: Location displayed on interactive map (OpenStreetMap)
- **FR-8.5**: System calculates distance between nodes using Haversine formula

### 2.4 Internet Connectivity
- **FR-9.1**: System probes for internet connectivity periodically
- **FR-9.2**: Devices with internet become "Goal Nodes"
- **FR-9.3**: Goal Nodes can deliver SOS to cloud services
- **FR-9.4**: System displays internet status in UI

### 2.5 Data Persistence
- **FR-10.1**: System uses Hive for local storage
- **FR-10.2**: Outbox persists pending packets across app restarts
- **FR-10.3**: Seen packet cache persists to prevent duplicate processing
- **FR-10.4**: User preferences and settings are stored locally

---

## 3. Non-Functional Requirements

### 3.1 Performance
- **NFR-1.1**: Discovery latency < 20 seconds for new devices
- **NFR-1.2**: Packet transmission latency < 5 seconds per hop
- **NFR-1.3**: UI response time < 300ms for user interactions
- **NFR-1.4**: Support up to 100 concurrent mesh nodes
- **NFR-1.5**: Memory usage < 200MB during normal operation

### 3.2 Reliability
- **NFR-2.1**: System uptime > 99% during active relay mode
- **NFR-2.2**: Packet delivery success rate > 90% within 3 hops
- **NFR-2.3**: Automatic recovery from connection failures
- **NFR-2.4**: Graceful degradation when battery < 20%
- **NFR-2.5**: No data loss during app crashes or restarts

### 3.3 Scalability
- **NFR-3.1**: Support mesh networks with 50+ nodes
- **NFR-3.2**: Handle 100+ packets per minute
- **NFR-3.3**: Efficient routing with O(n) complexity for n neighbors

### 3.4 Security
- **NFR-4.1**: Packet validation to prevent malformed data
- **NFR-4.2**: Loop prevention using trace validation
- **NFR-4.3**: TTL enforcement to prevent infinite packet propagation
- **NFR-4.4**: Input sanitization for user-provided data
- **NFR-4.5**: Secure socket communication (future: encryption)

### 3.5 Usability
- **NFR-5.1**: Intuitive UI with clear role selection
- **NFR-5.2**: Visual feedback for all network operations
- **NFR-5.3**: Accessibility support for emergency scenarios
- **NFR-5.4**: Dark theme optimized for low-light conditions
- **NFR-5.5**: Minimal user interaction required for relay mode

### 3.6 Battery Efficiency
- **NFR-6.1**: Battery drain < 10% per hour in relay mode
- **NFR-6.2**: Adaptive discovery intervals based on battery level
- **NFR-6.3**: Wake lock management for background operations
- **NFR-6.4**: Automatic power-saving mode when battery < 20%

### 3.7 Compatibility
- **NFR-7.1**: Support Android 10 (API 29) and above
- **NFR-7.2**: Support Android 14 (API 34) with updated permissions
- **NFR-7.3**: Compatible with devices supporting Wi-Fi Direct
- **NFR-7.4**: Graceful handling of missing GPS hardware

---

## 4. System Constraints

### 4.1 Hardware Requirements
- **C-1.1**: Wi-Fi Direct capable device (required)
- **C-1.2**: GPS/Location hardware (recommended)
- **C-1.3**: Minimum 2GB RAM
- **C-1.4**: Minimum 100MB storage space

### 4.2 Software Requirements
- **C-2.1**: Android 10 (API 29) or higher
- **C-2.2**: Wi-Fi enabled
- **C-2.3**: Location services enabled

### 4.3 Network Constraints
- **C-3.1**: Wi-Fi Direct range: ~100 meters line-of-sight
- **C-3.2**: Maximum 8 devices per Wi-Fi Direct group (Android limitation)
- **C-3.3**: No internet required for core functionality

### 4.4 Regulatory Constraints
- **C-4.1**: Compliance with Android permission model
- **C-4.2**: User consent required for location access
- **C-4.3**: Foreground service notification required
- **C-4.4**: Background location access for service registration (Android 10+)

---

## 5. User Interface Requirements

### 5.1 Home Screen
- **UI-1.1**: Display RescueNet logo and branding
- **UI-1.2**: Three role selection cards (I Need Help, I Can Help, Relay Mode)
- **UI-1.3**: Bottom status bar showing battery, relay status, P2P status
- **UI-1.4**: Permission request dialog on first launch

### 5.2 SOS Form Screen
- **UI-2.1**: Interactive map showing current location
- **UI-2.2**: Emergency type selection with emoji icons
- **UI-2.3**: Severity level selection with color coding
- **UI-2.4**: Name input field
- **UI-2.5**: Medical conditions selection (multi-select chips)
- **UI-2.6**: Required supplies selection (multi-select chips)
- **UI-2.7**: Mesh network status card showing nearby devices
- **UI-2.8**: AI pick indicator for recommended device
- **UI-2.9**: Large "SEND EMERGENCY SOS" button

### 5.3 Responder Screen
- **UI-3.1**: List of incoming SOS alerts
- **UI-3.2**: Map view with SOS markers
- **UI-3.3**: Filter and sort controls
- **UI-3.4**: SOS detail view with all information
- **UI-3.5**: Distance and direction to SOS location

### 5.4 Relay Mode Screen
- **UI-4.1**: Network topology visualization
- **UI-4.2**: Relay statistics dashboard
- **UI-4.3**: Connected nodes list
- **UI-4.4**: Packet flow visualization
- **UI-4.5**: Battery and performance metrics

### 5.5 Diagnostic Screen
- **UI-5.1**: Wi-Fi P2P readiness status
- **UI-5.2**: Permission status checklist
- **UI-5.3**: Network diagnostics
- **UI-5.4**: Packet history log
- **UI-5.5**: Debug console for developers

---

## 6. Integration Requirements

### 6.1 Android Platform Integration
- **INT-1.1**: Wi-Fi P2P Manager integration
- **INT-1.2**: Location Manager integration
- **INT-1.3**: Battery Manager integration
- **INT-1.4**: Connectivity Manager integration
- **INT-1.5**: Foreground Service integration

### 6.2 Flutter-Native Communication
- **INT-2.1**: Method Channel for Wi-Fi P2P operations
- **INT-2.2**: Event Channel for discovery events
- **INT-2.3**: Method Channel for permissions
- **INT-2.4**: Method Channel for device info

### 6.3 External Services (Future)
- **INT-3.1**: Cloud delivery service for Goal Nodes
- **INT-3.2**: Emergency services API integration
- **INT-3.3**: Analytics and monitoring

---

## 7. Testing Requirements

### 7.1 Unit Testing
- **T-1.1**: Test all domain entities and use cases
- **T-1.2**: Test routing algorithms
- **T-1.3**: Test packet validation logic
- **T-1.4**: Test data models and serialization

### 7.2 Integration Testing
- **T-2.1**: Test Flutter-Native communication
- **T-2.2**: Test mesh network flow end-to-end
- **T-2.3**: Test Wi-Fi P2P connection establishment
- **T-2.4**: Test packet relay scenarios

### 7.3 System Testing
- **T-3.1**: Test with multiple physical devices
- **T-3.2**: Test in various network topologies
- **T-3.3**: Test battery drain scenarios
- **T-3.4**: Test permission handling

### 7.4 User Acceptance Testing
- **T-4.1**: Test SOS sending workflow
- **T-4.2**: Test responder workflow
- **T-4.3**: Test relay mode operation
- **T-4.4**: Test UI/UX with target users

---

## 8. Deployment Requirements

### 8.1 Build Configuration
- **D-1.1**: Release build with ProGuard/R8 optimization
- **D-1.2**: Signed APK with release keystore
- **D-1.3**: Version management (semantic versioning)

### 8.2 Distribution
- **D-2.1**: Google Play Store distribution
- **D-2.2**: APK sideloading support for emergency scenarios
- **D-2.3**: Update mechanism for critical fixes

### 8.3 Documentation
- **D-3.1**: User manual for emergency responders
- **D-3.2**: Technical documentation for developers
- **D-3.3**: API documentation for native modules
- **D-3.4**: Deployment guide

---

## 9. Maintenance Requirements

### 9.1 Monitoring
- **M-1.1**: Crash reporting and analytics
- **M-1.2**: Performance monitoring
- **M-1.3**: Network statistics collection

### 9.2 Updates
- **M-2.1**: Regular security updates
- **M-2.2**: Bug fixes and improvements
- **M-2.3**: Android version compatibility updates

### 9.3 Support
- **M-3.1**: User support channels
- **M-3.2**: Issue tracking system
- **M-3.3**: Community feedback integration

---

## 10. Future Enhancements

### 10.1 Planned Features
- **F-1.1**: End-to-end encryption for packets
- **F-1.2**: Voice message support
- **F-1.3**: Photo/video attachment for SOS
- **F-1.4**: Offline maps caching
- **F-1.5**: Multi-language support
- **F-1.6**: iOS platform support
- **F-1.7**: Bluetooth mesh fallback
- **F-1.8**: Advanced network analytics
- **F-1.9**: Integration with emergency services
- **F-1.10**: Mesh network visualization in 3D

### 10.2 Research Areas
- **F-2.1**: Machine learning for routing optimization
- **F-2.2**: Predictive network topology analysis
- **F-2.3**: Energy-efficient discovery protocols
- **F-2.4**: Hybrid cellular-mesh networking

---

## 11. Success Criteria

### 11.1 Technical Success
- Successful packet delivery rate > 90%
- Network discovery time < 30 seconds
- Battery efficiency meets NFR targets
- Zero critical bugs in production

### 11.2 User Success
- Intuitive UI with minimal training required
- Successful SOS transmission in < 60 seconds
- Positive user feedback from emergency responders
- Adoption by disaster relief organizations

### 11.3 Business Success
- Deployment in real-world disaster scenarios
- Recognition by emergency management agencies
- Community contributions and ecosystem growth
- Sustainable maintenance and support model

---

## Document Control

**Version**: 1.0  
**Date**: February 14, 2026  
**Status**: Draft  
**Author**: RescueNet Development Team  
**Reviewers**: TBD  
**Approval**: TBD
