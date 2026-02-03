import '../../entities/mesh_packet.dart';

/// Checks packet integrity.
class IntegrityChecker {
  IntegrityChecker();

  /// Check if packet is valid.
  IntegrityResult check(MeshPacket packet) {
    final errors = <String>[];

    // Check ID
    if (packet.id.isEmpty) {
      errors.add('Empty packet ID');
    }

    // Check originator
    if (packet.originatorId.isEmpty) {
      errors.add('Empty originator ID');
    }

    // Check trace
    if (packet.trace.isEmpty) {
      errors.add('Empty trace');
    }

    // Check trace contains originator
    if (packet.trace.isNotEmpty && packet.trace.first != packet.originatorId) {
      errors.add('First trace entry is not originator');
    }

    // Check TTL
    if (packet.ttl < 0) {
      errors.add('Negative TTL');
    }

    if (packet.ttl > 100) {
      errors.add('TTL exceeds maximum (100)');
    }

    // Check timestamp
    final packetTime = DateTime.fromMillisecondsSinceEpoch(packet.timestamp);
    if (packetTime.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      errors.add('Timestamp is in the future');
    }

    if (packetTime.isBefore(DateTime.now().subtract(const Duration(hours: 24)))) {
      errors.add('Timestamp is too old (>24 hours)');
    }

    // Check priority
    if (packet.priority < 0 || packet.priority > 10) {
      errors.add('Priority out of range (0-10)');
    }

    // Check for trace loop
    final traceSet = packet.trace.toSet();
    if (traceSet.length != packet.trace.length) {
      errors.add('Loop detected in trace');
    }

    return IntegrityResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Quick validation (just essential checks).
  bool isValid(MeshPacket packet) {
    return packet.id.isNotEmpty &&
        packet.originatorId.isNotEmpty &&
        packet.ttl >= 0 &&
        packet.ttl <= 100;
  }
}

/// Result of integrity check.
class IntegrityResult {
  final bool isValid;
  final List<String> errors;

  const IntegrityResult({
    required this.isValid,
    required this.errors,
  });

  @override
  String toString() {
    if (isValid) return 'IntegrityResult: Valid';
    return 'IntegrityResult: Invalid - ${errors.join(", ")}';
  }
}
