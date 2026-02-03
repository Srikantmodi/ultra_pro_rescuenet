import 'package:equatable/equatable.dart';

/// Represents a data packet that travels through the mesh network.
///
/// This is the fundamental unit of data transfer in the RescueNet mesh.
/// Each packet carries:
/// - [id]: Unique identifier (UUID) for deduplication
/// - [originatorId]: The ID of the node that created this packet
/// - [payload]: The encrypted/serialized data being transported
/// - [trace]: Ordered list of node IDs this packet has visited (loop prevention)
/// - [ttl]: Time-To-Live - decrements at each hop, packet dies at 0
/// - [timestamp]: When the packet was originally created
/// - [priority]: Urgency level (0=low, 1=medium, 2=high, 3=critical/SOS)
/// - [packetType]: Type identifier for payload interpretation
class MeshPacket extends Equatable {
  /// Unique packet identifier (UUID v4)
  final String id;

  /// ID of the node that originally created this packet
  final String originatorId;

  /// The actual data payload (JSON string, encrypted if needed)
  final String payload;

  /// Ordered list of node IDs that have processed this packet.
  /// Used for loop prevention - a node in this list should never
  /// receive this packet again.
  final List<String> trace;

  /// Time-To-Live: Maximum remaining hops before packet is dropped.
  /// Default: 20 hops. Decremented at each relay.
  /// When TTL reaches 0, packet must be discarded.
  final int ttl;

  /// Unix timestamp (milliseconds) when packet was created
  final int timestamp;

  /// Priority level:
  /// - 0: Low (status updates, non-urgent)
  /// - 1: Medium (general messages)
  /// - 2: High (important alerts)
  /// - 3: Critical (SOS emergency - highest priority)
  final int priority;

  /// Type of packet for payload interpretation:
  /// - 'sos': Emergency SOS packet
  /// - 'ack': Acknowledgment packet
  /// - 'status': Node status broadcast
  /// - 'data': Generic data transfer
  final String packetType;

  /// Default TTL value for new packets
  static const int defaultTtl = 20;

  /// Priority levels as constants for type safety
  static const int priorityLow = 0;
  static const int priorityMedium = 1;
  static const int priorityHigh = 2;
  static const int priorityCritical = 3;

  /// Packet type constants
  static const String typeSos = 'sos';
  static const String typeAck = 'ack';
  static const String typeStatus = 'status';
  static const String typeData = 'data';

  const MeshPacket({
    required this.id,
    required this.originatorId,
    required this.payload,
    required this.trace,
    required this.ttl,
    required this.timestamp,
    required this.priority,
    required this.packetType,
  });

  /// Creates a new packet with default values.
  /// 
  /// The trace starts with the originator's ID since they're the first
  /// node to handle this packet.
  factory MeshPacket.create({
    required String id,
    required String originatorId,
    required String payload,
    required String packetType,
    int priority = priorityMedium,
    int? ttl,
    int? timestamp,
  }) {
    return MeshPacket(
      id: id,
      originatorId: originatorId,
      payload: payload,
      trace: [originatorId], // Originator is first in trace
      ttl: ttl ?? defaultTtl,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
      priority: priority,
      packetType: packetType,
    );
  }

  /// Creates an SOS packet with critical priority.
  factory MeshPacket.sos({
    required String id,
    required String originatorId,
    required String payload,
  }) {
    return MeshPacket.create(
      id: id,
      originatorId: originatorId,
      payload: payload,
      packetType: typeSos,
      priority: priorityCritical,
    );
  }

  /// Creates an SOS packet with SosPayload.
  /// Used by use cases that work with SosPayload directly.
  static MeshPacket createSos({
    required String originatorId,
    required dynamic sosPayload,
  }) {
    // Generate a unique ID for this packet
    final id = '${DateTime.now().millisecondsSinceEpoch}-${originatorId.hashCode}';
    final payload = sosPayload?.toJsonString?.call() ?? sosPayload?.toString() ?? '';
    
    return MeshPacket.sos(
      id: id,
      originatorId: originatorId,
      payload: payload,
    );
  }

  /// Adds the current node's ID to the trace and decrements TTL.
  /// 
  /// This is the primary method called when a relay node processes a packet.
  /// Returns a new [MeshPacket] with:
  /// - [nodeId] appended to [trace]
  /// - [ttl] decremented by 1
  /// 
  /// **Loop Prevention**: Before calling this, the relay should check
  /// if [nodeId] is already in [trace] using [hasVisited].
  MeshPacket addHop(String nodeId) {
    if (ttl <= 0) {
      throw StateError(
        'Cannot add hop to packet with TTL <= 0. Packet ID: $id',
      );
    }
    
    if (trace.contains(nodeId)) {
      throw StateError(
        'Loop detected: Node $nodeId already in trace. Packet ID: $id, Trace: $trace',
      );
    }

    return copyWith(
      trace: [...trace, nodeId],
      ttl: ttl - 1,
    );
  }

  /// Checks if this packet has already visited the given node.
  /// 
  /// This is the primary loop prevention check. A node should NEVER
  /// process a packet that has already visited it.
  bool hasVisited(String nodeId) {
    return trace.contains(nodeId);
  }

  /// Checks if this packet is still alive (TTL > 0).
  bool get isAlive => ttl > 0;

  /// Checks if TTL has been exhausted.
  bool get isExpired => ttl <= 0;

  /// Checks if this packet originated from the given node.
  bool isFrom(String nodeId) => originatorId == nodeId;

  /// Checks if this is an SOS emergency packet.
  bool get isSos => packetType == typeSos;

  /// Returns the packet type as enum for compatibility.
  PacketType get type {
    switch (packetType) {
      case typeSos:
        return PacketType.sos;
      case typeAck:
        return PacketType.ack;
      case typeStatus:
        return PacketType.status;
      case typeData:
      default:
        return PacketType.data;
    }
  }

  /// Returns the last node that processed this packet.
  /// Returns null if trace is empty (should never happen in valid packets).
  String? get lastHop => trace.isNotEmpty ? trace.last : null;

  /// Returns the sender (previous node) of this packet.
  /// For loop prevention: this node should be excluded from forwarding candidates.
  String? get sender => trace.length >= 2 ? trace[trace.length - 2] : lastHop;

  /// Returns the number of hops this packet has traveled.
  int get hopCount => trace.length - 1; // -1 because originator is in trace

  /// Checks if the given node should process this packet.
  /// 
  /// Returns false if:
  /// - Packet has expired (TTL <= 0)
  /// - Node has already seen this packet (in trace)
  bool shouldProcessAt(String nodeId) {
    return isAlive && !hasVisited(nodeId);
  }

  /// Returns the age of this packet in milliseconds.
  int get ageMs => DateTime.now().millisecondsSinceEpoch - timestamp;

  /// Returns the age of this packet in seconds.
  double get ageSec => ageMs / 1000.0;

  /// Creates a copy of this packet with updated fields.
  MeshPacket copyWith({
    String? id,
    String? originatorId,
    String? payload,
    List<String>? trace,
    int? ttl,
    int? timestamp,
    int? priority,
    String? packetType,
  }) {
    return MeshPacket(
      id: id ?? this.id,
      originatorId: originatorId ?? this.originatorId,
      payload: payload ?? this.payload,
      trace: trace ?? List.unmodifiable(this.trace),
      ttl: ttl ?? this.ttl,
      timestamp: timestamp ?? this.timestamp,
      priority: priority ?? this.priority,
      packetType: packetType ?? this.packetType,
    );
  }

  /// Create from JSON map.
  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    return MeshPacket(
      id: json['id'] as String,
      originatorId: json['originatorId'] as String,
      payload: json['payload'] as String,
      trace: (json['trace'] as List<dynamic>).map((e) => e as String).toList(),
      ttl: json['ttl'] as int,
      timestamp: json['timestamp'] as int,
      priority: json['priority'] as int,
      packetType: json['packetType'] as String,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originatorId': originatorId,
      'payload': payload,
      'trace': trace,
      'ttl': ttl,
      'timestamp': timestamp,
      'priority': priority,
      'packetType': packetType,
    };
  }

  @override
  List<Object?> get props => [
        id,
        originatorId,
        payload,
        trace,
        ttl,
        timestamp,
        priority,
        packetType,
      ];

  @override
  String toString() {
    return 'MeshPacket('
        'id: ${id.substring(0, 8)}..., '
        'from: $originatorId, '
        'type: $packetType, '
        'priority: $priority, '
        'ttl: $ttl, '
        'hops: $hopCount, '
        'trace: [${trace.join(" → ")}]'
        ')';
  }
}

/// Packet type enum for type-safe packet type checking.
enum PacketType {
  sos,
  ack,
  status,
  data,
}
