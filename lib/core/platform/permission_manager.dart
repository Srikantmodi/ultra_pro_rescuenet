import 'package:flutter/services.dart';

/// Manages runtime permissions for the mesh network.
class PermissionManager {
  static const _channel = MethodChannel('com.rescuenet/wifi_p2p');

  /// Check if all required permissions are granted.
  Future<PermissionStatus> checkPermissions() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkPermissions');
      return PermissionStatus(
        allGranted: result?['allGranted'] as bool? ?? false,
        hasWifiDirect: result?['hasWifiDirect'] as bool? ?? false,
        hasLocation: result?['hasLocation'] as bool? ?? false,
        hasForegroundService: result?['hasForegroundService'] as bool? ?? false,
        missing: List<String>.from(result?['missing'] ?? []),
        androidVersion: result?['androidVersion'] as int? ?? 0,
      );
    } on PlatformException catch (e) {
      return PermissionStatus(
        allGranted: false,
        hasWifiDirect: false,
        hasLocation: false,
        hasForegroundService: false,
        missing: ['Error: ${e.message}'],
        androidVersion: 0,
      );
    }
  }

  /// Request missing permissions.
  Future<bool> requestPermissions() async {
    try {
      final result = await _channel.invokeMethod<Map>('requestPermissions');
      return result?['allGranted'] as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Check if should show rationale for permissions.
  Future<bool> shouldShowRationale() async {
    try {
      final result = await _channel.invokeMethod<bool>('shouldShowRationale');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open app settings.
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException {
      // Ignore
    }
  }

  /// Get permission status for display.
  Future<List<PermissionItem>> getPermissionItems() async {
    final status = await checkPermissions();

    return [
      PermissionItem(
        name: 'Wi-Fi Direct',
        description: 'Required for mesh communication',
        isGranted: status.hasWifiDirect,
        isRequired: true,
      ),
      PermissionItem(
        name: 'Location',
        description: 'Required for Wi-Fi Direct on Android 12+',
        isGranted: status.hasLocation,
        isRequired: status.androidVersion < 33,
      ),
      PermissionItem(
        name: 'Foreground Service',
        description: 'Keep mesh running in background',
        isGranted: status.hasForegroundService,
        isRequired: true,
      ),
    ];
  }
}

/// Current permission status.
class PermissionStatus {
  final bool allGranted;
  final bool hasWifiDirect;
  final bool hasLocation;
  final bool hasForegroundService;
  final List<String> missing;
  final int androidVersion;

  const PermissionStatus({
    required this.allGranted,
    required this.hasWifiDirect,
    required this.hasLocation,
    required this.hasForegroundService,
    required this.missing,
    required this.androidVersion,
  });
}

/// Individual permission item for UI.
class PermissionItem {
  final String name;
  final String description;
  final bool isGranted;
  final bool isRequired;

  const PermissionItem({
    required this.name,
    required this.description,
    required this.isGranted,
    required this.isRequired,
  });
}
