import 'dart:async';
import 'package:geolocator/geolocator.dart' as geo;

/// Manages GPS location updates with intelligent filtering.
///
/// This service provides:
/// - Stream of location updates for the mesh network
/// - Movement filtering (only emit when moved > 5m)
/// - Battery-saving with configurable update intervals
/// - Error handling with fallback to last known position
///
/// The location data is used for:
/// - SOS packets (auto-fill GPS coordinates)
/// - Service Discovery metadata (broadcast our position)
/// - Distance calculations between nodes
class LocationManager {
  /// Minimum movement (in meters) to trigger a location update.
  /// Updates under this threshold are filtered to save battery.
  static const double minimumMovementMeters = 5.0;

  /// Default update interval in seconds.
  static const int defaultIntervalSeconds = 30;

  /// High accuracy update interval (for SOS mode).
  static const int highAccuracyIntervalSeconds = 5;

  final StreamController<LocationData> _locationController =
      StreamController<LocationData>.broadcast();

  LocationData? _lastKnownLocation;
  StreamSubscription<geo.Position>? _geolocatorSubscription;
  Timer? _locationTimer;
  bool _isHighAccuracyMode = false;
  String? _lastError;

  /// Stream of filtered location updates.
  ///
  /// Only emits when:
  /// 1. This is the first location, OR
  /// 2. User has moved more than [minimumMovementMeters]
  Stream<LocationData> get locationStream => _locationController.stream;

  /// The last known location, or null if never obtained.
  LocationData? get lastKnownLocation => _lastKnownLocation;

  /// Whether location tracking is currently active.
  bool get isTracking => _locationTimer != null || _geolocatorSubscription != null;

  /// Whether high accuracy mode is enabled.
  bool get isHighAccuracyMode => _isHighAccuracyMode;

  /// Last error message, if any.
  String? get lastError => _lastError;

  /// Starts location tracking with normal accuracy.
  ///
  /// This should be called when the app starts or when
  /// entering Relay mode.
  Future<void> startTracking() async {
    _isHighAccuracyMode = false;
    await _startLocationUpdates(defaultIntervalSeconds);
  }

  /// Starts location tracking with high accuracy.
  ///
  /// This should be called when entering SOS mode to ensure
  /// accurate coordinates in the emergency packet.
  Future<void> startHighAccuracyTracking() async {
    _isHighAccuracyMode = true;
    await _startLocationUpdates(highAccuracyIntervalSeconds);
  }

  /// Stops location tracking.
  void stopTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _geolocatorSubscription?.cancel();
    _geolocatorSubscription = null;
  }

  /// Gets the current location immediately.
  ///
  /// Uses high accuracy for single fetch.
  /// Returns null if location cannot be obtained.
  Future<LocationData?> getCurrentLocation() async {
    try {
      _lastError = null;
      
      // Check if location services are enabled
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _lastError = 'Location services are disabled. Please enable GPS.';
        return _lastKnownLocation;
      }

      // Check and request permission
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          _lastError = 'Location permission denied.';
          return _lastKnownLocation;
        }
      }

      if (permission == geo.LocationPermission.deniedForever) {
        _lastError = 'Location permission permanently denied. Please enable in settings.';
        return _lastKnownLocation;
      }

      // Get current position
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: _isHighAccuracyMode 
            ? geo.LocationAccuracy.best 
            : geo.LocationAccuracy.high,
      );

      final location = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );

      _updateLocation(location);
      return location;
    } catch (e) {
      _lastError = 'Failed to get location: $e';
      // Return last known if available
      return _lastKnownLocation;
    }
  }

  /// Forces an immediate location update.
  Future<void> forceUpdate() async {
    await getCurrentLocation();
  }

  Future<void> _startLocationUpdates(int intervalSeconds) async {
    // Cancel existing subscriptions
    stopTracking();

    // Get initial location
    await getCurrentLocation();

    // For high accuracy mode, use continuous stream
    if (_isHighAccuracyMode) {
      _geolocatorSubscription = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen((position) {
        final location = LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speed: position.speed,
          heading: position.heading,
          timestamp: position.timestamp,
        );
        _updateLocation(location);
      }, onError: (e) {
        _lastError = 'Location stream error: $e';
      });
    } else {
      // For normal mode, use periodic updates
      _locationTimer = Timer.periodic(
        Duration(seconds: intervalSeconds),
        (_) => getCurrentLocation(),
      );
    }
  }

  void _updateLocation(LocationData newLocation) {
    // Filter by movement threshold
    if (_lastKnownLocation != null) {
      final distance = geo.Geolocator.distanceBetween(
        _lastKnownLocation!.latitude,
        _lastKnownLocation!.longitude,
        newLocation.latitude,
        newLocation.longitude,
      );

      if (distance < minimumMovementMeters) {
        // Movement below threshold, don't emit
        // But update timestamp
        _lastKnownLocation = _lastKnownLocation!.copyWith(
          timestamp: newLocation.timestamp,
        );
        return;
      }
    }

    // Movement significant or first location
    _lastKnownLocation = newLocation;
    if (!_locationController.isClosed) {
      _locationController.add(newLocation);
    }
  }

  /// Disposes of resources.
  void dispose() {
    stopTracking();
    _locationController.close();
  }
}

/// Represents a GPS location with metadata.
class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double speed;
  final double heading;
  final DateTime timestamp;

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.timestamp,
  });

  /// Creates a location with just lat/lng and defaults.
  factory LocationData.simple({
    required double latitude,
    required double longitude,
    double accuracy = 0,
  }) {
    return LocationData(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: 0,
      speed: 0,
      heading: 0,
      timestamp: DateTime.now(),
    );
  }

  /// Whether this location is considered accurate enough for SOS.
  bool get isAccurate => accuracy <= 50;

  /// Returns a human-readable accuracy description.
  String get accuracyDescription {
    if (accuracy <= 5) return 'Excellent';
    if (accuracy <= 15) return 'Good';
    if (accuracy <= 50) return 'Fair';
    return 'Poor';
  }

  /// Formats coordinates for display.
  String get coordinatesDisplay {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  /// Creates a copy with updated fields.
  LocationData copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    DateTime? timestamp,
  }) {
    return LocationData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'LocationData('
        'lat: ${latitude.toStringAsFixed(5)}, '
        'lng: ${longitude.toStringAsFixed(5)}, '
        'acc: ${accuracy.toStringAsFixed(1)}m)';
  }
}
