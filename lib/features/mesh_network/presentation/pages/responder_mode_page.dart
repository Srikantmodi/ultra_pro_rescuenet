import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/mesh_bloc.dart';
import '../../domain/entities/sos_payload.dart';
import '../../domain/entities/mesh_packet.dart';
import '../../data/repositories/mesh_repository_impl.dart';

/// Responder Mode Page - For users who can help others.
/// Listens for incoming SOS alerts and displays them with location.
class ResponderModePage extends StatefulWidget {
  const ResponderModePage({super.key});

  @override
  State<ResponderModePage> createState() => _ResponderModePageState();
}

class _ResponderModePageState extends State<ResponderModePage> {
  bool _isListening = false;
  ReceivedSos? _selectedSos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _selectedSos != null
                ? _buildSosDetailView(_selectedSos!)
                : _buildMainContent(),
          ),
          if (_isListening) _buildBottomStatusBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
        onPressed: () {
          if (_selectedSos != null) {
            setState(() => _selectedSos = null);
          } else {
            Navigator.of(context).pop();
          }
        },
        tooltip: _selectedSos != null ? 'Back to list' : 'Go back',
      ),
      title: Text(
        _selectedSos != null ? 'Emergency Details' : 'Responder Mode',
        style: const TextStyle(
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
            color: _isListening
                ? AppTheme.success.withValues(alpha: 0.15)
                : AppTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isListening ? Icons.hearing_rounded : Icons.hearing_disabled_rounded,
                color: _isListening
                    ? AppTheme.success
                    : AppTheme.textDim,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _isListening ? 'Listening' : 'Idle',
                style: TextStyle(
                  color: _isListening
                      ? AppTheme.success
                      : AppTheme.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return BlocBuilder<MeshBloc, MeshState>(
      builder: (context, state) {
        final sosAlerts = state is MeshActive ? state.recentSosAlerts : <ReceivedSos>[];
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 24),
              _buildIncomingEmergenciesSection(sosAlerts),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          // Heart with hand icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _isListening
                  ? AppTheme.success.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              color: AppTheme.success,
              size: 42,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isListening ? 'Listening for SOS...' : 'Ready to Help',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isListening
                ? 'Incoming emergencies will appear below'
                : 'Start listening to receive emergency alerts',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Start/Stop Listening Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _toggleListening,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isListening
                    ? AppTheme.danger
                    : AppTheme.success,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                ),
                elevation: 0,
              ),
              child: Text(
                _isListening ? 'STOP LISTENING' : 'START LISTENING',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Debug Inject Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _injectTestAlert,
              icon: const Text('🐛', style: TextStyle(fontSize: 16)),
              label: const Text(
                'TEST: Inject Alert (Debug)',
                style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF334155)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingEmergenciesSection(List<ReceivedSos> sosAlerts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.warning,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Incoming Emergencies',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sosAlerts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  _isListening ? Icons.radar : Icons.hearing_disabled_rounded,
                  color: AppTheme.textDim,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  _isListening
                      ? 'No emergencies yet...'
                      : 'Start listening to receive alerts',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        else
          ...sosAlerts.map((sos) => _buildSosCard(sos)),
      ],
    );
  }

  Widget _buildSosCard(ReceivedSos receivedSos) {
    final payload = receivedSos.sos;
    return Semantics(
      button: true,
      label: '${payload.emergencyType.displayName} emergency from ${payload.senderName}',
      child: GestureDetector(
        onTap: () => setState(() => _selectedSos = receivedSos),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            border: Border.all(
              color: _getSeverityColor(payload.triageLevel).withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Emergency Type Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getSeverityColor(payload.triageLevel).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                ),
                child: Center(
                  child: Text(
                    _getEmergencyEmoji(payload.emergencyType),
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.emergencyType.displayName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${payload.senderName} • ${payload.ageString}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _getSeverityColor(payload.triageLevel),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  payload.triageLevel.displayName.split(' ').first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSosDetailView(ReceivedSos receivedSos) {
    final payload = receivedSos.sos;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map showing sender location
          SizedBox(
            height: 250,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(payload.latitude, payload.longitude),
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.rescuenet.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(payload.latitude, payload.longitude),
                      width: 100,
                      height: 100,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getSeverityColor(payload.triageLevel),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'SOS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: _getSeverityColor(payload.triageLevel),
                            size: 48,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with emergency type
                Row(
                  children: [
                    Text(
                      _getEmergencyEmoji(payload.emergencyType),
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            payload.emergencyType.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            payload.triageLevel.displayName,
                            style: TextStyle(
                              color: _getSeverityColor(payload.triageLevel),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Sender', payload.senderName),
                _buildDetailRow('Location',
                    '${payload.latitude.toStringAsFixed(6)}, ${payload.longitude.toStringAsFixed(6)}'),
                _buildDetailRow('Accuracy', '${payload.locationAccuracy.toStringAsFixed(0)}m'),
                _buildDetailRow('Time', payload.ageString),
                if (payload.medicalConditions.isNotEmpty)
                  _buildDetailRow('Medical',
                      payload.medicalConditions.map((c) => c.displayName).join(', ')),
                if (payload.requiredSupplies.isNotEmpty)
                  _buildDetailRow('Supplies',
                      payload.requiredSupplies.map((s) => s.displayName).join(', ')),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Implement cloud save
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Saved to cloud for further action'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        },
                        icon: const Icon(Icons.cloud_upload, size: 20),
                        label: const Text('Save to Cloud'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Navigate to help
                        },
                        icon: const Icon(Icons.directions, size: 20),
                        label: const Text('Navigate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: AppTheme.success,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text(
            'Listening for emergency signals',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleListening() {
    setState(() => _isListening = !_isListening);
    
    if (_isListening) {
      context.read<MeshBloc>().add(const MeshStart());
    } else {
      context.read<MeshBloc>().add(const MeshStop());
    }
  }

  void _injectTestAlert() {
    final testPayload = SosPayload.create(
      sosId: 'test-${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'test-device',
      senderName: 'Test User',
      latitude: 28.6139,
      longitude: 77.2090,
      locationAccuracy: 15.0,
      emergencyType: EmergencyType.medical,
      triageLevel: TriageLevel.critical,
      numberOfPeople: 1,
      medicalConditions: [MedicalCondition.chestPain],
      requiredSupplies: [SupplyType.firstAidKit, SupplyType.oxygen],
    );
    
    // Create a test packet for ReceivedSos
    final testPacket = MeshPacket.createSos(
      originatorId: 'test-device',
      sosPayload: testPayload.toJsonString(),
    );
    
    final testSos = ReceivedSos(
      packet: testPacket,
      sos: testPayload,
      receivedAt: DateTime.now(),
      senderIp: '192.168.49.1',
    );
    
    // Show the test alert
    setState(() {
      _selectedSos = testSos;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test alert injected'),
        backgroundColor: Color(0xFFFBBF24),
      ),
    );
  }

  Color _getSeverityColor(TriageLevel level) {
    switch (level) {
      case TriageLevel.critical:
      case TriageLevel.red:
        return const Color(0xFFEF4444);
      case TriageLevel.high:
      case TriageLevel.yellow:
        return const Color(0xFFFBBF24);
      case TriageLevel.medium:
        return const Color(0xFF3B82F6);
      case TriageLevel.low:
      case TriageLevel.green:
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _getEmergencyEmoji(EmergencyType type) {
    switch (type) {
      case EmergencyType.medical:
        return '🏥';
      case EmergencyType.fire:
        return '🔥';
      case EmergencyType.flood:
        return '🌊';
      case EmergencyType.earthquake:
        return '🌍';
      case EmergencyType.trapped:
        return '🚧';
      case EmergencyType.injury:
        return '🩹';
      default:
        return '⚠️';
    }
  }
}
