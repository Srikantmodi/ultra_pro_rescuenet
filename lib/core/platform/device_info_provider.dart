import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Provides device information for mesh network identification.
class DeviceInfoProvider {
  DeviceInfoProvider._();

  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  /// Get unique device identifier.
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      // Try to get Android ID via platform channel
      const channel = MethodChannel('com.rescuenet/device_info');
      final result = await channel.invokeMethod<String>('getDeviceId');
      _cachedDeviceId = result ?? _generateFallbackId();
    } catch (e) {
      _cachedDeviceId = _generateFallbackId();
    }

    return _cachedDeviceId!;
  }

  /// Get device display name.
  static Future<String> getDeviceName() async {
    if (_cachedDeviceName != null) return _cachedDeviceName!;

    try {
      const channel = MethodChannel('com.rescuenet/device_info');
      final result = await channel.invokeMethod<String>('getDeviceName');
      _cachedDeviceName = result ?? _getDefaultDeviceName();
    } catch (e) {
      _cachedDeviceName = _getDefaultDeviceName();
    }

    return _cachedDeviceName!;
  }

  /// Get operating system name.
  static String getOsName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Get platform for mesh identification.
  static String getPlatform() {
    return Platform.operatingSystem;
  }

  /// Check if running in debug mode.
  static bool get isDebugMode => kDebugMode;

  /// Generate a fallback device ID.
  static String _generateFallbackId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 100000;
    return 'device_$random';
  }

  /// Get default device name.
  static String _getDefaultDeviceName() {
    return '${getOsName()} Device';
  }

  /// Get device info summary.
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    return {
      'deviceId': await getDeviceId(),
      'deviceName': await getDeviceName(),
      'os': getOsName(),
      'platform': getPlatform(),
      'isDebug': isDebugMode,
    };
  }
}
