import 'package:equatable/equatable.dart';

/// Base class for all failures in the application.
///
/// Failures are used in the domain layer to represent errors
/// without exposing implementation details.
abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType: $message';
}

/// Failure for network-related errors.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Failure for Wi-Fi P2P errors.
class WifiP2pFailure extends Failure {
  const WifiP2pFailure(super.message);
}

/// Failure for permission-related errors.
class PermissionFailure extends Failure {
  final List<String> missingPermissions;

  const PermissionFailure(super.message, [this.missingPermissions = const []]);

  @override
  List<Object?> get props => [message, missingPermissions];
}

/// Failure for storage/database errors.
class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// Failure for serialization/parsing errors.
class SerializationFailure extends Failure {
  const SerializationFailure(super.message);
}

/// Failure for validation errors.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Failure for unexpected errors.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}

/// Failure for timeout errors.
class TimeoutFailure extends Failure {
  final Duration timeout;

  const TimeoutFailure(super.message, this.timeout);

  @override
  List<Object?> get props => [message, timeout];
}

/// Failure for location-related errors.
class LocationFailure extends Failure {
  const LocationFailure(super.message);
}

/// Failure for routing errors.
class RoutingFailure extends Failure {
  const RoutingFailure(super.message);
}

/// Failure for packet processing errors.
class PacketFailure extends Failure {
  final String? packetId;

  const PacketFailure(super.message, [this.packetId]);

  @override
  List<Object?> get props => [message, packetId];
}

/// Failure for server/cloud errors.
class ServerFailure extends Failure {
  const ServerFailure(super.message);
}
