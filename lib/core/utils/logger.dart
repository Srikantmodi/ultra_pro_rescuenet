import 'package:flutter/foundation.dart';

/// Application logger with log levels and formatting.
class Logger {
  final String tag;
  final bool enabled;

  const Logger(this.tag, {this.enabled = true});

  /// Log debug message.
  void d(String message, [Object? data]) {
    if (!enabled || !kDebugMode) return;
    _log('D', message, data);
  }

  /// Log info message.
  void i(String message, [Object? data]) {
    if (!enabled) return;
    _log('I', message, data);
  }

  /// Log warning message.
  void w(String message, [Object? data]) {
    if (!enabled) return;
    _log('W', message, data);
  }

  /// Log error message.
  void e(String message, [Object? error, StackTrace? stackTrace]) {
    if (!enabled) return;
    _log('E', message, error);
    if (stackTrace != null && kDebugMode) {
      print(stackTrace);
    }
  }

  void _log(String level, String message, [Object? data]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final prefix = '[$timestamp] [$level/$tag]';

    if (kDebugMode) {
      if (data != null) {
        debugPrint('$prefix $message: $data');
      } else {
        debugPrint('$prefix $message');
      }
    }
  }
  /// Create a child logger with a sub-tag.
  Logger child(String childTag) {
    return Logger('$tag.$childTag', enabled: enabled);
  }
}

/// Global loggers for different modules.
class Loggers {
  Loggers._();

  static const mesh = Logger('Mesh');
  static const routing = Logger('Routing');
  static const discovery = Logger('Discovery');
  static const socket = Logger('Socket');
  static const storage = Logger('Storage');
  static const ui = Logger('UI');
  static const location = Logger('Location');
}

/// Log levels.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

extension LogLevelExtension on LogLevel {
  String get prefix {
    switch (this) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  String get emoji {
    switch (this) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }
}
