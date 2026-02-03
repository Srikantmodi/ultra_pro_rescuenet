/// Network-related constants for mesh communication.
class NetworkConstants {
  NetworkConstants._();

  // ============== WI-FI DIRECT ==============

  /// Wi-Fi Direct service type for DNS-SD
  static const String serviceType = '_rescuenet._tcp';

  /// Service instance name prefix
  static const String serviceInstancePrefix = 'RescueNode_';

  /// TCP port for socket communication
  static const int socketPort = 8988;

  /// Socket connection timeout in milliseconds
  static const int socketTimeoutMs = 5000;

  /// ACK timeout in milliseconds
  static const int ackTimeoutMs = 3000;

  // ============== DNS-SD ==============

  /// Maximum retries for DNS-SD registration
  static const int dnsSdMaxRetries = 3;

  /// Initial retry delay in milliseconds
  static const int dnsSdInitialRetryDelayMs = 500;

  /// Retry delay multiplier (exponential backoff)
  static const double dnsSdRetryMultiplier = 2.0;

  // ============== PACKET ==============

  /// Maximum packet payload size in bytes
  static const int maxPayloadSizeBytes = 65536; // 64KB

  /// Packet magic number for validation
  static const String packetMagic = 'RNET';

  /// Protocol version
  static const int protocolVersion = 1;

  // ============== CONNECTIVITY ==============

  /// Probe endpoints for internet check
  static const List<String> probeEndpoints = [
    'google.com',
    'cloudflare.com',
    '8.8.8.8',
    '1.1.1.1',
  ];

  /// Normal probe interval in seconds (when online)
  static const int normalProbeIntervalSeconds = 60;

  /// Offline probe interval in seconds (when offline)
  static const int offlineProbeIntervalSeconds = 15;

  /// Probe timeout in seconds
  static const int probeTimeoutSeconds = 5;

  // ============== TXT RECORD KEYS ==============

  /// Node ID key
  static const String txtKeyNodeId = 'id';

  /// Battery level key
  static const String txtKeyBattery = 'bat';

  /// Internet status key
  static const String txtKeyInternet = 'net';

  /// Latitude key
  static const String txtKeyLatitude = 'lat';

  /// Longitude key
  static const String txtKeyLongitude = 'lng';

  /// Signal strength key
  static const String txtKeySignal = 'sig';

  /// Triage level key
  static const String txtKeyTriage = 'tri';

  /// Role key
  static const String txtKeyRole = 'rol';

  /// Relay availability key
  static const String txtKeyRelay = 'rel';
}
