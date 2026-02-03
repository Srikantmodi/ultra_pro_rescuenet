import 'package:flutter/services.dart';

/// Manages Wi-Fi P2P group formation.
class GroupManager {
  static const _channel = MethodChannel('com.rescuenet/wifi_p2p/group');

  bool _isGroupOwner = false;
  String? _groupAddress;

  /// Whether this device is the group owner.
  bool get isGroupOwner => _isGroupOwner;

  /// The group owner's IP address.
  String? get groupAddress => _groupAddress;

  /// Create a new group (become group owner).
  Future<bool> createGroup() async {
    try {
      final result = await _channel.invokeMethod<Map>('createGroup');
      _isGroupOwner = result?['isOwner'] as bool? ?? false;
      _groupAddress = result?['address'] as String?;
      return _isGroupOwner;
    } on PlatformException {
      return false;
    }
  }

  /// Remove the current group.
  Future<void> removeGroup() async {
    try {
      await _channel.invokeMethod('removeGroup');
      _isGroupOwner = false;
      _groupAddress = null;
    } on PlatformException {
      // May not be in a group
    }
  }

  /// Get current group info.
  Future<GroupInfo?> getGroupInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getGroupInfo');
      if (result == null) return null;

      return GroupInfo(
        networkName: result['networkName'] as String?,
        passphrase: result['passphrase'] as String?,
        isGroupOwner: result['isOwner'] as bool? ?? false,
        ownerAddress: result['ownerAddress'] as String?,
        clientCount: result['clientCount'] as int? ?? 0,
      );
    } on PlatformException {
      return null;
    }
  }

  /// Invite a device to join the group.
  Future<bool> inviteDevice(String deviceAddress) async {
    try {
      final result = await _channel.invokeMethod<bool>('inviteDevice', {
        'deviceAddress': deviceAddress,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}

/// Information about the current group.
class GroupInfo {
  final String? networkName;
  final String? passphrase;
  final bool isGroupOwner;
  final String? ownerAddress;
  final int clientCount;

  const GroupInfo({
    this.networkName,
    this.passphrase,
    required this.isGroupOwner,
    this.ownerAddress,
    required this.clientCount,
  });
}
