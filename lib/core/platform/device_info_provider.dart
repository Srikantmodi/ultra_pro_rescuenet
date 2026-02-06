import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

/// Provides device information for mesh network identification.
class DeviceInfoProvider {
  DeviceInfoProvider._();

  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  /// Get unique device identifier.
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      // Open box for device settings
      final box = await Hive.openBox('device_settings');
      String? id = box.get('device_id');
      
      if (id == null) {
        // Generate new persistent UUID
        id = const Uuid().v4();
        // Take first 8 chars to make it readable but unique enough for small mesh
        // Or keep full UUID if needed. User liked "RescueNet-1762" style.
        // Let's store full UUID but maybe use a shorter version for display if needed.
        // For distinctness, let's keep full UUID or at least a longer segment.
        // The previous "RescueNet-XXXX" logic in Kotlin used the ID passed to it.
        // If we pass a full UUID, the service name might get long.
        // But let's stick to standard UUID for unique ID.
        await box.put('device_id', id);
      }
      
      _cachedDeviceId = id;
    } catch (e) {
      // Fallback if Hive fails
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
