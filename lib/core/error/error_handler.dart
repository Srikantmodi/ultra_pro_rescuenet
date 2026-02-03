import 'package:flutter/foundation.dart';
import 'failures.dart';
import 'exceptions.dart';

/// Centralized error handler for the application.
class ErrorHandler {
  ErrorHandler._();

  /// Global error callback
  static void Function(Object error, StackTrace? stackTrace)? onError;

  /// Handle an error and convert to Failure.
  static Failure handle(Object error, [StackTrace? stackTrace]) {
    // Log the error
    _logError(error, stackTrace);

    // Notify global handler
    onError?.call(error, stackTrace);

    // Convert to appropriate Failure
    return _convertToFailure(error);
  }

  /// Log error to console (and potentially to analytics).
  static void _logError(Object error, StackTrace? stackTrace) {
    if (kDebugMode) {
      print('❌ ERROR: $error');
      if (stackTrace != null) {
        print('Stack trace:\n$stackTrace');
      }
    }
  }

  /// Convert various error types to Failure.
  static Failure _convertToFailure(Object error) {
    if (error is Failure) {
      return error;
    }

    if (error is AppException) {
      return error.toFailure();
    }

    if (error is FormatException) {
      return SerializationFailure('Invalid data format: ${error.message}');
    }

    if (error is StateError) {
      return ValidationFailure(error.message);
    }

    if (error is ArgumentError) {
      return ValidationFailure(error.message?.toString() ?? 'Invalid argument');
    }

    // Generic unexpected error
    return UnexpectedFailure(error.toString());
  }

  /// Handle async errors safely.
  static Future<T?> runSafely<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, s) {
      handle(e, s);
      return null;
    }
  }

  /// Handle sync errors safely.
  static T? runSafelySync<T>(T Function() action) {
    try {
      return action();
    } catch (e, s) {
      handle(e, s);
      return null;
    }
  }
}
