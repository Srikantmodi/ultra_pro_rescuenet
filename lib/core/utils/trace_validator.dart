import '../../features/mesh_network/domain/entities/mesh_packet.dart';

/// Validates packet traces for loop detection and integrity.
class TraceValidator {
  TraceValidator._();

  /// Check if trace contains a loop (duplicate node IDs).
  static bool hasLoop(List<String> trace) {
    final seen = <String>{};
    for (final nodeId in trace) {
      if (seen.contains(nodeId)) {
        return true;
      }
      seen.add(nodeId);
    }
    return false;
  }

  /// Check if packet has visited a specific node.
  static bool hasVisited(MeshPacket packet, String nodeId) {
    return packet.trace.contains(nodeId);
  }

  /// Check if adding a node would create a loop.
  static bool wouldCreateLoop(MeshPacket packet, String nodeId) {
    return packet.trace.contains(nodeId);
  }

  /// Get the number of hops in the trace.
  static int getHopCount(MeshPacket packet) {
    return packet.trace.length;
  }

  /// Check if packet has exceeded maximum hops.
  static bool hasExceededMaxHops(MeshPacket packet, {int maxHops = 10}) {
    return packet.trace.length >= maxHops;
  }

  /// Validate trace integrity.
  static TraceValidationResult validateTrace(MeshPacket packet) {
    final trace = packet.trace;

    // Check for empty trace
    if (trace.isEmpty) {
      return TraceValidationResult(
        isValid: false,
        reason: 'Empty trace',
      );
    }

    // Check for loop
    if (hasLoop(trace)) {
      return TraceValidationResult(
        isValid: false,
        reason: 'Loop detected in trace',
        loopNode: _findLoopNode(trace),
      );
    }

    // Check first node is originator
    if (trace.first != packet.originatorId) {
      return TraceValidationResult(
        isValid: false,
        reason: 'First node in trace is not originator',
      );
    }

    // Check for empty node IDs
    if (trace.any((id) => id.isEmpty)) {
      return TraceValidationResult(
        isValid: false,
        reason: 'Trace contains empty node ID',
      );
    }

    return const TraceValidationResult(isValid: true);
  }

  static String? _findLoopNode(List<String> trace) {
    final seen = <String>{};
    for (final nodeId in trace) {
      if (seen.contains(nodeId)) {
        return nodeId;
      }
      seen.add(nodeId);
    }
    return null;
  }

  /// Detect repeating patterns in trace.
  static bool hasRepeatingPattern(List<String> trace, {int minLength = 2}) {
    if (trace.length < minLength * 2) return false;

    for (int patternLength = minLength;
        patternLength <= trace.length ~/ 2;
        patternLength++) {
      if (_checkPattern(trace, patternLength)) {
        return true;
      }
    }
    return false;
  }

  static bool _checkPattern(List<String> trace, int patternLength) {
    if (trace.length < patternLength * 2) return false;

    final lastChunk = trace.sublist(trace.length - patternLength);
    final previousChunk = trace.sublist(
      trace.length - patternLength * 2,
      trace.length - patternLength,
    );

    for (int i = 0; i < patternLength; i++) {
      if (lastChunk[i] != previousChunk[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Result of trace validation.
class TraceValidationResult {
  final bool isValid;
  final String? reason;
  final String? loopNode;

  const TraceValidationResult({
    required this.isValid,
    this.reason,
    this.loopNode,
  });
}
