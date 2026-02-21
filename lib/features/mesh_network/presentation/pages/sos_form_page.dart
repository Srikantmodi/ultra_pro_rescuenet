import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/platform/location_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/sos_payload.dart';
import '../../domain/entities/node_info.dart';
import '../bloc/mesh_bloc.dart';
import 'package:get_it/get_it.dart';

/// Emergency SOS Page - Complete form for sending emergency alerts.
///
/// Features:
/// - Interactive map with GPS location
/// - Emergency type selection with emoji icons
/// - Severity level selection
/// - Medical conditions and supplies selection
/// - Mesh network device scanning with AI pick
class SosFormPage extends StatefulWidget {
  const SosFormPage({super.key});

  @override
  State<SosFormPage> createState() => _SosFormPageState();
}

class _SosFormPageState extends State<SosFormPage> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();
  
  // Location
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _accuracy = 0.0;
  bool _isLoadingLocation = true;
  
  // Form selections
  EmergencyType _emergencyType = EmergencyType.medical;
  TriageLevel _triageLevel = TriageLevel.high;
  final Set<MedicalCondition> _medicalConditions = {};
  final Set<SupplyType> _requiredSupplies = {};
  
  // Device scanning
  List<NodeInfo> _nearbyDevices = [];
  NodeInfo? _selectedDevice;
  int? _aiPickIndex;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _scanDevices();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final locationManager = GetIt.instance<LocationManager>();
      final position = await locationManager.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _accuracy = position.accuracy;
          _isLoadingLocation = false;
        });
      } else {
        // Default to a sample location if GPS not available
        setState(() {
          _latitude = 17.47159;
          _longitude = 78.72168;
          _accuracy = 15.0;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      // Use default location on error
      setState(() {
        _latitude = 17.47159;
        _longitude = 78.72168;
        _accuracy = 15.0;
        _isLoadingLocation = false;
      });
    }
  }

  void _scanDevices() {
    // Get devices from BLoC state
    final state = context.read<MeshBloc>().state;
    if (state is MeshActive) {
      setState(() {
        _nearbyDevices = state.neighbors;
        // AI picks the device with best signal/battery combination
        if (_nearbyDevices.isNotEmpty) {
          _aiPickIndex = _findBestDevice();
          _selectedDevice = _nearbyDevices[_aiPickIndex!];
        }
      });
    }
  }

  int _findBestDevice() {
    if (_nearbyDevices.isEmpty) return 0;
    
    int bestIndex = 0;
    double bestScore = 0;
    
    for (int i = 0; i < _nearbyDevices.length; i++) {
      final device = _nearbyDevices[i];
      // Score based on signal strength and battery
      final signalScore = (device.signalStrength + 100) / 100; // Normalize -100 to 0 dBm
      final batteryScore = device.batteryLevel / 100;
      final score = (signalScore * 0.6) + (batteryScore * 0.4);
      
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    
    return bestIndex;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MeshBloc, MeshState>(
      listener: (context, state) {
        if (state is MeshActive) {
          setState(() {
            _nearbyDevices = state.neighbors;
            if (_nearbyDevices.isNotEmpty && _selectedDevice == null) {
              _aiPickIndex = _findBestDevice();
              _selectedDevice = _nearbyDevices[_aiPickIndex!];
            }
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Location Card
              _buildLocationCard(),
              const SizedBox(height: 24),
              
              // Emergency Type
              _buildSectionTitle('Emergency Type'),
              const SizedBox(height: 12),
              _buildEmergencyTypeGrid(),
              const SizedBox(height: 24),
              
              // Severity Level
              _buildSectionTitle('Severity Level'),
              const SizedBox(height: 12),
              _buildSeverityLevelRow(),
              const SizedBox(height: 24),
              
              // Your Name
              _buildSectionTitle('Your Name'),
              const SizedBox(height: 12),
              _buildNameInput(),
              const SizedBox(height: 24),
              
              // Medical Conditions
              _buildSectionTitle('Medical Conditions'),
              const SizedBox(height: 12),
              _buildMedicalConditionsWrap(),
              const SizedBox(height: 24),
              
              // Required Supplies
              _buildSectionTitle('Required Supplies'),
              const SizedBox(height: 12),
              _buildRequiredSuppliesWrap(),
              const SizedBox(height: 24),
              
              // Mesh Network Status
              _buildMeshNetworkStatus(),
              const SizedBox(height: 24),
              
              // Send SOS Button
              _buildSosButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Go back',
      ),
      title: const Text(
        'Emergency SOS',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology_rounded, color: AppTheme.success, size: 16),
              SizedBox(width: 4),
              Text(
                'AI Ready',
                style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard() {
    return Container(
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: AppTheme.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Your Location',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: () {
                      setState(() => _isLoadingLocation = true);
                      _loadLocation();
                    },
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: _isLoadingLocation ? AppTheme.textDim : AppTheme.primary,
                    ),
                    tooltip: 'Refresh location',
                  ),
                ),
              ],
            ),
          ),
          // Map
          Container(
            height: 180,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isLoadingLocation
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF3B82F6),
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(_latitude, _longitude),
                      initialZoom: 16.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.rescuenet.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_latitude, _longitude),
                            width: 80,
                            height: 80,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'YOU',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.location_on,
                                  color: Color(0xFFE53935),
                                  size: 40,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          // Coordinates
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '±${_accuracy.toStringAsFixed(0)}m accuracy',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmergencyTypeGrid() {
    final emergencyTypes = [
      (EmergencyType.medical, '🏥', 'Medical'),
      (EmergencyType.fire, '🔥', 'Fire'),
      (EmergencyType.flood, '🌊', 'Flood'),
      (EmergencyType.earthquake, '🏚️', 'Earthquake'),
      (EmergencyType.trapped, '🆘', 'Trapped/Stuck'),
      (EmergencyType.injury, '🩹', 'Injury'),
      (EmergencyType.other, '⚠️', 'Other'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: emergencyTypes.map((type) {
        final isSelected = _emergencyType == type.$1;
        return Semantics(
          button: true,
          selected: isSelected,
          label: type.$3,
          child: GestureDetector(
            onTap: () => setState(() => _emergencyType = type.$1),
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.danger.withValues(alpha: 0.15) : AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                border: Border.all(
                  color: isSelected ? AppTheme.danger : AppTheme.surfaceHighlight,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(type.$2, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 4),
                  Text(
                    type.$3,
                    style: TextStyle(
                      color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSeverityLevelRow() {
    final levels = [
      (TriageLevel.critical, 'CRITICAL', AppTheme.danger),
      (TriageLevel.high, 'High', AppTheme.warning),
      (TriageLevel.medium, 'Medium', AppTheme.textSecondary),
      (TriageLevel.low, 'Low', AppTheme.textDim),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: levels.map((level) {
          final isSelected = _triageLevel == level.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: 'Severity: ${level.$2}',
              child: GestureDetector(
                onTap: () => setState(() => _triageLevel = level.$1),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: isSelected ? level.$3 : AppTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isSelected ? level.$3 : AppTheme.surfaceHighlight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    level.$2,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNameInput() {
    return Container(
      decoration: AppTheme.cardDecoration,
      child: TextField(
        controller: _nameController,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Enter your name',
          hintStyle: const TextStyle(color: AppTheme.textDim),
          prefixIcon: const Icon(Icons.person_outline_rounded, color: AppTheme.textDim),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildMedicalConditionsWrap() {
    final conditions = [
      MedicalCondition.chestPain,
      MedicalCondition.unconscious,
      MedicalCondition.diabetic,
      MedicalCondition.heartCondition,
      MedicalCondition.allergies,
      MedicalCondition.pregnant,
      MedicalCondition.elderly,
      MedicalCondition.childInfant,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: conditions.map((condition) {
        final isSelected = _medicalConditions.contains(condition);
        return Semantics(
          button: true,
          selected: isSelected,
          label: condition.displayName,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _medicalConditions.remove(condition);
                } else {
                  _medicalConditions.add(condition);
                }
              });
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.danger.withValues(alpha: 0.15) : AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.danger : AppTheme.surfaceHighlight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                condition.displayName,
                style: TextStyle(
                  color: isSelected ? AppTheme.danger : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRequiredSuppliesWrap() {
    final supplies = [
      SupplyType.firstAidKit,
      SupplyType.water,
      SupplyType.food,
      SupplyType.medication,
      SupplyType.blankets,
      SupplyType.flashlight,
      SupplyType.radio,
      SupplyType.stretcher,
      SupplyType.oxygen,
      SupplyType.defibrillator,
      SupplyType.ropeHarness,
      SupplyType.fireExtinguisher,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: supplies.map((supply) {
        final isSelected = _requiredSupplies.contains(supply);
        return Semantics(
          button: true,
          selected: isSelected,
          label: supply.displayName,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _requiredSupplies.remove(supply);
                } else {
                  _requiredSupplies.add(supply);
                }
              });
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.success : AppTheme.surfaceHighlight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                supply.displayName,
                style: TextStyle(
                  color: isSelected ? AppTheme.success : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMeshNetworkStatus() {
    return Container(
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cell_tower_rounded,
                    color: AppTheme.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Mesh Network',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_nearbyDevices.length} nodes found',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Device List
          if (_nearbyDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.search, color: Colors.grey[600], size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Scanning for nearby devices...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_nearbyDevices.length, (index) {
              final device = _nearbyDevices[index];
              final isAiPick = index == _aiPickIndex;
              final isSelected = _selectedDevice == device;
              
              return GestureDetector(
                onTap: () => setState(() => _selectedDevice = device),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? const Color(0xFF134E4A).withValues(alpha: 0.5)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isAiPick 
                        ? Border.all(color: const Color(0xFF14B8A6), width: 2)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.smartphone,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '10m • ${device.signalStrength} dBm',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.battery_std,
                            color: device.batteryLevel > 20 
                                ? const Color(0xFF10B981) 
                                : Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${device.batteryLevel}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (isAiPick) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AI PICK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSosButton() {
    return Semantics(
      button: true,
      label: 'Send Emergency SOS',
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _sendSos,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.send_rounded, size: 22),
              SizedBox(width: 10),
              Text(
                'SEND EMERGENCY SOS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendSos() {
    final sos = SosPayload(
      sosId: const Uuid().v4(),
      senderId: 'current_node',
      senderName: _nameController.text.isEmpty ? 'Anonymous' : _nameController.text,
      latitude: _latitude,
      longitude: _longitude,
      locationAccuracy: _accuracy,
      emergencyType: _emergencyType,
      triageLevel: _triageLevel,
      numberOfPeople: 1,
      medicalConditions: _medicalConditions.toList(),
      requiredSupplies: _requiredSupplies.toList(),
      additionalNotes: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    context.read<MeshBloc>().add(MeshSendSos(sos));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🆘 SOS Alert Sent! Broadcasting to mesh network...'),
        backgroundColor: Color(0xFFE53935),
        duration: Duration(seconds: 3),
      ),
    );

    Navigator.of(context).pop();
  }
}
