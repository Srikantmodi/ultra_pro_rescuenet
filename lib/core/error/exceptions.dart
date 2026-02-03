import 'failures.dart';

/// Base exception class for the application.
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(this.message, {this.code, this.originalError});

  /// Convert to Failure for domain layer.
  Failure toFailure();

  @override
  String toString() => '$runtimeType: $message${code != null ? ' ($code)' : ''}';
}

/// Exception for network-related errors.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code, super.originalError});

  @override
  Failure toFailure() => NetworkFailure(message);
}

/// Exception for Wi-Fi P2P errors.
class WifiP2pException extends AppException {
  const WifiP2pException(super.message, {super.code, super.originalError});

  @override
  Failure toFailure() => WifiP2pFailure(message);
}

/// Exception for permission-related errors.
class PermissionException extends AppException {
  final List<String> missingPermissions;

  const PermissionException(
    super.message, {
    this.missingPermissions = const [],
    super.code,
  });

  @override
  Failure toFailure() => PermissionFailure(message, missingPermissions);
}

/// Exception for storage/database errors.
class StorageException extends AppException {
  const StorageException(super.message, {super.code, super.originalError});

  @override
  Failure toFailure() => StorageFailure(message);
}

/// Exception for serialization/parsing errors.
class SerializationException extends AppException {
  const SerializationException(super.message, {super.code, super.originalError});

  @override
  Failure toFailure() => SerializationFailure(message);
}

/// Exception for validation errors.
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  const ValidationException(
    super.message, {
    this.fieldErrors,
    super.code,
  });

  @override
  Failure toFailure() => ValidationFailure(message);
}

/// Exception for timeout errors.
class TimeoutException extends AppException {
  final Duration timeout;

  const TimeoutException(
    super.message, {
    required this.timeout,
    super.code,
  });

  @override
  Failure toFailure() => TimeoutFailure(message, timeout);
}

/// Exception for location-related errors.
class LocationException extends AppException {
  const LocationException(super.message, {super.code, super.originalError});

  @override
  Failure toFailure() => LocationFailure(message);
}
