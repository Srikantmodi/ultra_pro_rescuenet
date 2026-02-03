import '../../entities/mesh_packet.dart';
import 'integrity_checker.dart';
import 'loop_detector.dart';

/// Validates incoming packets.
class PacketValidator {
  final IntegrityChecker _integrityChecker;
  final LoopDetector _loopDetector;

  PacketValidator({
    IntegrityChecker? integrityChecker,
    LoopDetector? loopDetector,
  })  : _integrityChecker = integrityChecker ?? IntegrityChecker(),
        _loopDetector = loopDetector ?? LoopDetector();

  /// Validate a packet.
  ValidationResult validate({
    required MeshPacket packet,
    required String myNodeId,
    Set<String>? seenPacketIds,
  }) {
    final errors = <String>[];

    // Check integrity
    final integrityResult = _integrityChecker.check(packet);
    if (!integrityResult.isValid) {
      errors.addAll(integrityResult.errors);
    }

    // Check for duplicate
    if (seenPacketIds != null && seenPacketIds.contains(packet.id)) {
      return ValidationResult.duplicate(packet.id);
    }

    // Check loop
    final loopResult = _loopDetector.shouldProcessPacket(
      packet: packet,
      currentNodeId: myNodeId,
    );
    if (!loopResult.shouldProcess) {
      errors.add(loopResult.message ?? loopResult.reason?.name ?? 'Loop detected');
    }

    // Check if expired
    if (!packet.isAlive) {
      errors.add('Packet TTL expired');
    }

    if (errors.isEmpty) {
      return ValidationResult.valid();
    } else {
      return ValidationResult.invalid(errors);
    }
  }

  /// Quick check if packet is processable.
  bool canProcess({
    required MeshPacket packet,
    required String myNodeId,
  }) {
    if (!_integrityChecker.isValid(packet)) return false;
    if (!packet.isAlive) return false;

    final loopResult = _loopDetector.shouldProcessPacket(
      packet: packet,
      currentNodeId: myNodeId,
    );
    return loopResult.shouldProcess;
  }
}

/// Result of packet validation.
class ValidationResult {
  final bool isValid;
  final bool isDuplicate;
  final List<String> errors;

  const ValidationResult._({
    required this.isValid,
    this.isDuplicate = false,
    this.errors = const [],
  });

  factory ValidationResult.valid() {
    return const ValidationResult._(isValid: true);
  }

  factory ValidationResult.invalid(List<String> errors) {
    return ValidationResult._(isValid: false, errors: errors);
  }

  factory ValidationResult.duplicate(String packetId) {
    return ValidationResult._(
      isValid: false,
      isDuplicate: true,
      errors: ['Duplicate packet: $packetId'],
    );
  }

  @override
  String toString() {
    if (isValid) return 'ValidationResult: Valid';
    if (isDuplicate) return 'ValidationResult: Duplicate';
    return 'ValidationResult: Invalid - ${errors.join(", ")}';
  }
}
