import 'package:equatable/equatable.dart';

/// Result of a packet transmission attempt.
class TransmissionResult extends Equatable {
  /// Whether the transmission was successful.
  final bool isSuccess;

  /// Target node ID.
  final String targetNodeId;

  /// Packet ID that was transmitted.
  final String packetId;

  /// Time taken for transmission in milliseconds.
  final int durationMs;

  /// Whether ACK was received.
  final bool ackReceived;

  /// Error message if failed.
  final String? errorMessage;

  /// Which attempt number this was.
  final int attemptNumber;

  /// When the transmission occurred.
  final DateTime timestamp;

  const TransmissionResult({
    required this.isSuccess,
    required this.targetNodeId,
    required this.packetId,
    required this.durationMs,
    required this.ackReceived,
    this.errorMessage,
    this.attemptNumber = 1,
    required this.timestamp,
  });

  /// Create a successful result.
  factory TransmissionResult.success({
    required String targetNodeId,
    required String packetId,
    required int durationMs,
    int attemptNumber = 1,
  }) {
    return TransmissionResult(
      isSuccess: true,
      targetNodeId: targetNodeId,
      packetId: packetId,
      durationMs: durationMs,
      ackReceived: true,
      attemptNumber: attemptNumber,
      timestamp: DateTime.now(),
    );
  }

  /// Create a failed result.
  factory TransmissionResult.failure({
    required String targetNodeId,
    required String packetId,
    required String error,
    int durationMs = 0,
    int attemptNumber = 1,
  }) {
    return TransmissionResult(
      isSuccess: false,
      targetNodeId: targetNodeId,
      packetId: packetId,
      durationMs: durationMs,
      ackReceived: false,
      errorMessage: error,
      attemptNumber: attemptNumber,
      timestamp: DateTime.now(),
    );
  }

  /// Create a timeout result.
  factory TransmissionResult.timeout({
    required String targetNodeId,
    required String packetId,
    required int timeoutMs,
    int attemptNumber = 1,
  }) {
    return TransmissionResult(
      isSuccess: false,
      targetNodeId: targetNodeId,
      packetId: packetId,
      durationMs: timeoutMs,
      ackReceived: false,
      errorMessage: 'Transmission timeout after ${timeoutMs}ms',
      attemptNumber: attemptNumber,
      timestamp: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [isSuccess, targetNodeId, packetId, timestamp];

  @override
  String toString() {
    if (isSuccess) {
      return 'TransmissionResult.success(target: $targetNodeId, packet: ${packetId.substring(0, 8)}, ${durationMs}ms)';
    } else {
      return 'TransmissionResult.failure(target: $targetNodeId, error: $errorMessage)';
    }
  }
}
