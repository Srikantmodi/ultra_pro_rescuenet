import 'package:equatable/equatable.dart';
import '../../domain/entities/node_info.dart';

/// Model for node metadata storage and serialization.
class NodeMetadataModel extends Equatable {
  final String id;
  final String deviceAddress;
  final String displayName;
  final int batteryLevel;
  final bool hasInternet;
  final double latitude;
  final double longitude;
  final int lastSeenMs;
  final int signalStrength;
  final String triageLevel;
  final String role;
  final bool isAvailableForRelay;

  const NodeMetadataModel({
    required this.id,
    required this.deviceAddress,
    required this.displayName,
    required this.batteryLevel,
    required this.hasInternet,
    required this.latitude,
    required this.longitude,
    required this.lastSeenMs,
    required this.signalStrength,
    required this.triageLevel,
    required this.role,
    required this.isAvailableForRelay,
  });

  /// Create from NodeInfo entity.
  factory NodeMetadataModel.fromEntity(NodeInfo entity) {
    return NodeMetadataModel(
      id: entity.id,
      deviceAddress: entity.deviceAddress,
      displayName: entity.displayName,
      batteryLevel: entity.batteryLevel,
      hasInternet: entity.hasInternet,
      latitude: entity.latitude,
      longitude: entity.longitude,
      lastSeenMs: entity.lastSeen.millisecondsSinceEpoch,
      signalStrength: entity.signalStrength,
      triageLevel: entity.triageLevel,
      role: entity.role,
      isAvailableForRelay: entity.isAvailableForRelay,
    );
  }

  /// Convert to NodeInfo entity.
  NodeInfo toEntity() {
    return NodeInfo(
      id: id,
      deviceAddress: deviceAddress,
      displayName: displayName,
      batteryLevel: batteryLevel,
      hasInternet: hasInternet,
      latitude: latitude,
      longitude: longitude,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
      signalStrength: signalStrength,
      triageLevel: triageLevel,
      role: role,
      isAvailableForRelay: isAvailableForRelay,
    );
  }

  /// Create from JSON.
  factory NodeMetadataModel.fromJson(Map<String, dynamic> json) {
    return NodeMetadataModel(
      id: json['id'] as String,
      deviceAddress: json['deviceAddress'] as String? ?? '02:00:00:00:00:00',
      displayName: json['displayName'] as String? ?? '',
      batteryLevel: json['batteryLevel'] as int? ?? 0,
      hasInternet: json['hasInternet'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      lastSeenMs: json['lastSeenMs'] as int? ?? 0,
      signalStrength: json['signalStrength'] as int? ?? -100,
      triageLevel: json['triageLevel'] as String? ?? NodeInfo.triageNone,
      role: json['role'] as String? ?? NodeInfo.roleIdle,
      isAvailableForRelay: json['isAvailableForRelay'] as bool? ?? true,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceAddress': deviceAddress,
      'displayName': displayName,
      'batteryLevel': batteryLevel,
      'hasInternet': hasInternet,
      'latitude': latitude,
      'longitude': longitude,
      'lastSeenMs': lastSeenMs,
      'signalStrength': signalStrength,
      'triageLevel': triageLevel,
      'role': role,
      'isAvailableForRelay': isAvailableForRelay,
    };
  }

  @override
  List<Object?> get props => [id, lastSeenMs];
}
