import 'dart:convert';

/// Network security utilities for packet encryption/validation.
///
/// Note: Full encryption is disabled by default (FeatureFlags.enableEncryption).
/// This provides basic integrity checks.
class NetworkSecurity {
  NetworkSecurity._();

  /// Simple checksum for packet integrity.
  static String calculateChecksum(String data) {
    int checksum = 0;
    for (int i = 0; i < data.length; i++) {
      checksum = (checksum + data.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return checksum.toRadixString(16).padLeft(8, '0');
  }

  /// Verify checksum.
  static bool verifyChecksum(String data, String expectedChecksum) {
    return calculateChecksum(data) == expectedChecksum;
  }

  /// Base64 encode data.
  static String encodeBase64(String data) {
    return base64.encode(utf8.encode(data));
  }

  /// Base64 decode data.
  static String decodeBase64(String encoded) {
    return utf8.decode(base64.decode(encoded));
  }

  /// Generate a simple message signature.
  /// Note: This is NOT cryptographically secure, just for basic validation.
  static String generateSignature(String message, String nodeId) {
    final combined = '$nodeId:$message';
    return calculateChecksum(combined);
  }

  /// Verify message signature.
  static bool verifySignature(String message, String nodeId, String signature) {
    return generateSignature(message, nodeId) == signature;
  }

  /// Sanitize input string (remove control characters).
  static String sanitizeInput(String input) {
    return input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  }

  /// Validate packet structure.
  static bool isValidPacketStructure(Map<String, dynamic> packet) {
    // Check required fields
    final requiredFields = ['id', 'originatorId', 'payload', 'trace', 'ttl'];
    for (final field in requiredFields) {
      if (!packet.containsKey(field)) {
        return false;
      }
    }

    // Validate types
    if (packet['id'] is! String) return false;
    if (packet['originatorId'] is! String) return false;
    if (packet['payload'] is! String) return false;
    if (packet['trace'] is! List) return false;
    if (packet['ttl'] is! int) return false;

    // Validate TTL range
    final ttl = packet['ttl'] as int;
    if (ttl < 0 || ttl > 100) return false;

    return true;
  }
}
