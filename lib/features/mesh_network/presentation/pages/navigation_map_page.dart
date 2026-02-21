import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Full-screen navigation map that shows the victim's SOS location,
/// the helper's live GPS position, and an OSRM walking route between them.
///
/// Accepts the victim's coordinates and emergency metadata, fetches the
/// helper's current GPS, and continuously updates the helper marker.
class NavigationMapPage extends StatefulWidget {
  /// Victim's latitude from the SOS payload.
  final double victimLatitude;

  /// Victim's longitude from the SOS payload.
  final double victimLongitude;

  /// Location accuracy in meters (used for accuracy circle radius).
  final double locationAccuracy;

  /// Victim's name for display.
  final String victimName;

  /// Emergency type label.
  final String emergencyLabel;

  /// Triage severity color.
  final Color severityColor;

  const NavigationMapPage({
    super.key,
    required this.victimLatitude,
    required this.victimLongitude,
    required this.locationAccuracy,
    required this.victimName,
    required this.emergencyLabel,
    required this.severityColor,
  });

  @override
  State<NavigationMapPage> createState() => _NavigationMapPageState();
}

class _NavigationMapPageState extends State<NavigationMapPage> {
  final MapController _mapController = MapController();

  // Helper's current position (null until GPS lock).
  LatLng? _helperPosition;

  // OSRM decoded route polyline.
  List<LatLng> _routePoints = [];

  // Route metadata.
  double? _distanceKm;
  double? _durationMin;

  // GPS subscription for real-time helper tracking.
  StreamSubscription<geo.Position>? _positionSubscription;

  // Loading / error state.
  bool _isLoadingRoute = false;
  String? _routeError;
  bool _isLocating = true;
  bool _isCenteredOnHelper = false;

  late LatLng _victimLatLng;

  @override
  void initState() {
    super.initState();
    _victimLatLng = LatLng(widget.victimLatitude, widget.victimLongitude);
    _initHelperLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  // ──────────────────────── GPS INIT ────────────────────────

  Future<void> _initHelperLocation() async {
    try {
      // Check permission first — the app already requests it during mesh init,
      // so this should normally be granted.
      geo.LocationPermission permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }

      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLocating = false;
            _routeError = 'Location permission denied';
          });
        }
        return;
      }

      // Get current position with a reasonable timeout.
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _helperPosition = LatLng(position.latitude, position.longitude);
        _isLocating = false;
      });

      // Fit map to show both markers.
      _fitBounds();

      // Fetch walking route.
      _fetchRoute();

      // Start continuous GPS tracking.
      _startTracking();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _routeError = 'Could not get GPS location';
        });
      }
    }
  }

  void _startTracking() {
    _positionSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5, // update every 5 meters moved
      ),
    ).listen((pos) {
      if (!mounted) return;
      final newPos = LatLng(pos.latitude, pos.longitude);
      final bool positionChanged = _helperPosition == null ||
          _helperPosition!.latitude != newPos.latitude ||
          _helperPosition!.longitude != newPos.longitude;

      setState(() => _helperPosition = newPos);

      // Re-fetch route when helper has moved significantly (>50 m).
      if (positionChanged && _routePoints.isNotEmpty) {
        final distMoved = _haversineMeters(_helperPosition!, newPos);
        if (distMoved > 50) {
          _fetchRoute();
        }
      }

      if (_isCenteredOnHelper) {
        _mapController.move(newPos, _mapController.camera.zoom);
      }
    });
  }

  // ──────────────────────── ROUTE FETCHING ────────────────────────

  /// Fetches a walking route from OSRM public demo server.
  /// Falls back to a straight-line if the API is unreachable.
  Future<void> _fetchRoute() async {
    if (_helperPosition == null) return;

    setState(() {
      _isLoadingRoute = true;
      _routeError = null;
    });

    try {
      // OSRM expects lon,lat order.
      final helperCoord =
          '${_helperPosition!.longitude},${_helperPosition!.latitude}';
      final victimCoord =
          '${_victimLatLng.longitude},${_victimLatLng.latitude}';

      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/$helperCoord;$victimCoord'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final geometry = route['geometry'];
          final coords = geometry['coordinates'] as List;
          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toDouble();

          setState(() {
            _routePoints = coords
                .map<LatLng>((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();
            _distanceKm = distance / 1000.0;
            _durationMin = duration / 60.0;
            _isLoadingRoute = false;
          });
          return;
        }
      }

      // If OSRM failed, fall back to straight line.
      _fallbackStraightLine();
    } catch (_) {
      if (mounted) _fallbackStraightLine();
    }
  }

  void _fallbackStraightLine() {
    if (_helperPosition == null) return;
    final dist = _haversineMeters(_helperPosition!, _victimLatLng);
    // Walking speed ~5 km/h = ~83 m/min.
    final estMin = dist / 83.0;

    setState(() {
      _routePoints = [_helperPosition!, _victimLatLng];
      _distanceKm = dist / 1000.0;
      _durationMin = estMin;
      _isLoadingRoute = false;
      _routeError = 'Showing straight-line (no route data)';
    });
  }

  // ──────────────────────── MAP HELPERS ────────────────────────

  void _fitBounds() {
    if (_helperPosition == null) return;

    // Compute bounds that contain both points with padding.
    final bounds = LatLngBounds.fromPoints([_helperPosition!, _victimLatLng]);

    // Use a post-frame callback so the map is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
          maxZoom: 17,
        ),
      );
    });
  }

  /// Haversine distance in meters.
  double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final h = sinDLat * sinDLat +
        cos(_deg2rad(a.latitude)) * cos(_deg2rad(b.latitude)) * sinDLng * sinDLng;
    return R * 2 * asin(sqrt(h));
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  // ──────────────────────── BUILD ────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // ── Map ──
          _buildMap(),

          // ── Top bar ──
          _buildTopBar(),

          // ── Info panel (distance / ETA) ──
          if (_helperPosition != null && _distanceKm != null) _buildInfoPanel(),

          // ── Loading overlay ──
          if (_isLocating) _buildLocatingOverlay(),

          // ── Re-center FAB ──
          if (_helperPosition != null)
            Positioned(
              bottom: 100,
              right: 16,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'center_both',
                    backgroundColor: const Color(0xFF1E293B),
                    onPressed: () {
                      setState(() => _isCenteredOnHelper = false);
                      _fitBounds();
                    },
                    child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'center_me',
                    backgroundColor: const Color(0xFF3B82F6),
                    onPressed: () {
                      setState(() => _isCenteredOnHelper = true);
                      if (_helperPosition != null) {
                        _mapController.move(_helperPosition!, 16);
                      }
                    },
                    child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────── SUB-WIDGETS ────────────────────────

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _victimLatLng,
        initialZoom: 15,
        onPositionChanged: (_, __) {
          // If user pans manually, stop auto-centering.
          // (gesture-based only — skip programmatic moves)
        },
      ),
      children: [
        // ── Tile layer ──
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.rescuenet.app',
        ),

        // ── Accuracy circle around victim ──
        if (widget.locationAccuracy > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: _victimLatLng,
                radius: widget.locationAccuracy,
                useRadiusInMeter: true,
                color: widget.severityColor.withValues(alpha: 0.10),
                borderColor: widget.severityColor.withValues(alpha: 0.40),
                borderStrokeWidth: 2,
              ),
            ],
          ),

        // ── Route polyline ──
        if (_routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 5,
                color: const Color(0xFF3B82F6),
                isDotted: false,
              ),
            ],
          ),

        // ── Markers ──
        MarkerLayer(
          markers: [
            // Victim marker (red SOS pin)
            Marker(
              point: _victimLatLng,
              width: 120,
              height: 110,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.severityColor,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: widget.severityColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      'SOS • ${widget.victimName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.location_on,
                    color: widget.severityColor,
                    size: 48,
                    shadows: [
                      Shadow(
                        color: widget.severityColor.withValues(alpha: 0.6),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Helper marker (blue "You" pin)
            if (_helperPosition != null)
              Marker(
                point: _helperPosition!,
                width: 80,
                height: 90,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Text(
                        'You',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.person_pin_circle,
                      color: Color(0xFF3B82F6),
                      size: 44,
                      shadows: [
                        Shadow(
                          color: Color(0x993B82F6),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 16,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0F172A).withValues(alpha: 0.95),
              const Color(0xFF0F172A).withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.severityColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.emergencyLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Navigating to ${widget.victimName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Row(
              children: [
                // Distance
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.straighten,
                    value: _formatDistance(_distanceKm!),
                    label: 'Distance',
                    color: const Color(0xFF3B82F6),
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: const Color(0xFF334155),
                ),
                // ETA
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.schedule,
                    value: _formatDuration(_durationMin!),
                    label: 'Walking ETA',
                    color: const Color(0xFF10B981),
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: const Color(0xFF334155),
                ),
                // Accuracy
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.gps_fixed,
                    value: '${widget.locationAccuracy.toStringAsFixed(0)}m',
                    label: 'SOS Accuracy',
                    color: widget.severityColor,
                  ),
                ),
              ],
            ),

            if (_routeError != null) ...[
              const SizedBox(height: 8),
              Text(
                _routeError!,
                style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 12,
                ),
              ),
            ],

            if (_isLoadingRoute) ...[
              const SizedBox(height: 8),
              const SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  backgroundColor: Color(0xFF334155),
                  color: Color(0xFF3B82F6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildLocatingOverlay() {
    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: widget.severityColor,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Getting your location...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This may take a few seconds',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── FORMATTERS ────────────────────────

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).toStringAsFixed(0)}m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  String _formatDuration(double minutes) {
    if (minutes < 1) {
      return '< 1 min';
    }
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} min';
    }
    final hours = (minutes / 60).floor();
    final mins = (minutes % 60).toStringAsFixed(0);
    return '${hours}h ${mins}m';
  }
}
