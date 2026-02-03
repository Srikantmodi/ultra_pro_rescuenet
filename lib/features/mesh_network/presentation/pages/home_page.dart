import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:battery_plus/battery_plus.dart';
import '../bloc/mesh_bloc.dart';
import '../../../../core/platform/permission_manager.dart';
import 'sos_form_page.dart';
import 'responder_mode_page.dart';
import 'relay_mode_page.dart';

/// Home page - main screen of the RescueNet app with role selection.
///
/// Features:
/// - RescueNet logo and branding
/// - Three role selection cards (I Need Help, I Can Help, Relay Mode)
/// - Bottom status bar with battery, relay status, P2P status
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _batteryLevel = 100;
  final Battery _battery = Battery();

  @override
  void initState() {
    super.initState();
    // Initialize mesh network on app start
    context.read<MeshBloc>().add(const MeshInitialize());
    _getBatteryLevel();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    // Small delay to ensure UI is ready
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final permissionManager = PermissionManager();
    final status = await permissionManager.checkPermissions();

    if (!status.allGranted && mounted) {
      // Show explanation dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('Permissions Required', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RescueNet Pro needs the following permissions to function:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              _buildPermissionRow(
                icon: Icons.wifi_tethering,
                title: 'Wi-Fi Direct',
                subtitle: 'To connect with nearby devices'
              ),
              const SizedBox(height: 8),
              _buildPermissionRow(
                icon: Icons.location_on,
                title: 'Location',
                subtitle: 'Required for device discovery'
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                permissionManager.requestPermissions();
              },
              child: const Text('Grant Access', style: TextStyle(color: Color(0xFF10B981))),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPermissionRow({required IconData icon, required String title, required String subtitle}) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF10B981), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
      }
    } catch (e) {
      // Battery info not available
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: BlocConsumer<MeshBloc, MeshState>(
          listener: (context, state) {
            if (state is MeshError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${state.message}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                const Spacer(flex: 1),
                // Logo
                _buildLogo(),
                const SizedBox(height: 16),
                // Title
                _buildTitle(),
                const Spacer(flex: 1),
                // Role Selection
                _buildRoleSection(context, state),
                const Spacer(flex: 1),
                // Tagline
                _buildTagline(),
                const SizedBox(height: 24),
                // Bottom Status Bar
                _buildStatusBar(state),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE53935), width: 3),
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Signal waves
            for (int i = 0; i < 3; i++)
              Container(
                width: 50 + (i * 20.0),
                height: 50 + (i * 20.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE53935).withValues(alpha: 0.3 - (i * 0.1)),
                    width: 2,
                  ),
                ),
              ),
            // Center icon
            const Icon(
              Icons.cell_tower,
              color: Color(0xFFE53935),
              size: 48,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const Column(
      children: [
        Text(
          'RescueNet',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'AI-Powered Mesh Emergency Network',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSection(BuildContext context, MeshState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Select Your Role',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // I Need Help Card
          _buildRoleCard(
            icon: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'SOS',
                  style: TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            title: 'I Need Help',
            subtitle: 'Send emergency SOS through mesh network',
            accentColor: const Color(0xFFE53935),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => BlocProvider.value(
                    value: context.read<MeshBloc>(),
                    child: const SosFormPage(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // I Can Help Card
          _buildRoleCard(
            icon: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1A3D2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.favorite,
                color: Color(0xFF10B981),
                size: 24,
              ),
            ),
            title: 'I Can Help',
            subtitle: 'Receive and respond to emergencies',
            accentColor: const Color(0xFF10B981),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => BlocProvider.value(
                    value: context.read<MeshBloc>(),
                    child: const ResponderModePage(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // Relay Mode Card
          _buildRoleCard(
            icon: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2E4A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.router,
                color: Color(0xFF3B82F6),
                size: 24,
              ),
            ),
            title: 'Relay Mode',
            subtitle: 'Act as a silent relay node in the network',
            accentColor: const Color(0xFF3B82F6),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => BlocProvider.value(
                    value: context.read<MeshBloc>(),
                    child: const RelayModePage(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required Widget icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF1F2937),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[600],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagline() {
    return const Text(
      'Works without internet • Peer-to-peer mesh',
      style: TextStyle(
        fontSize: 12,
        color: Color(0xFF4B5563),
      ),
    );
  }

  Widget _buildStatusBar(MeshState state) {
    final isP2PReady = state is MeshActive || state is MeshReady;
    final isRelayNode = state is MeshActive;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1F2937),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Battery
          Row(
            children: [
              Icon(
                _batteryLevel > 20 ? Icons.battery_std : Icons.battery_alert,
                color: _batteryLevel > 20 ? const Color(0xFF10B981) : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '$_batteryLevel%',
                style: TextStyle(
                  fontSize: 13,
                  color: _batteryLevel > 20 ? const Color(0xFF10B981) : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // Relay Node Status
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRelayNode ? const Color(0xFF3B82F6) : Colors.grey,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Relay Node',
                style: TextStyle(
                  fontSize: 13,
                  color: isRelayNode ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // P2P Status
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: isP2PReady ? const Color(0xFF10B981) : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'P2P Ready',
                style: TextStyle(
                  fontSize: 13,
                  color: isP2PReady ? const Color(0xFF10B981) : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
