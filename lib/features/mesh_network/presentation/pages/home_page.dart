import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:battery_plus/battery_plus.dart';
import '../bloc/mesh_bloc.dart';
import '../../../../core/platform/permission_manager.dart';
import '../../../../core/theme/app_theme.dart';
import 'sos_form_page.dart';
import 'responder_mode_page.dart';
import 'relay_mode_page.dart';

/// Home page - main screen of the RescueNet app with role selection.
///
/// Modern, accessible design with:
/// - Clear visual hierarchy
/// - Minimum 48dp touch targets (WCAG compliant)
/// - High contrast text (AA compliant)
/// - Semantic labels for screen readers
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
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final permissionManager = PermissionManager();
    final status = await permissionManager.checkPermissions();

    if (!status.allGranted && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
          ),
          title: const Text(
            'Permissions Required',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RescueNet needs these permissions to connect with nearby devices during emergencies:',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _buildPermissionRow(
                icon: Icons.wifi_tethering_rounded,
                title: 'Wi-Fi Direct',
                subtitle: 'Connect with nearby devices',
              ),
              const SizedBox(height: 12),
              _buildPermissionRow(
                icon: Icons.location_on_rounded,
                title: 'Location',
                subtitle: 'Share your location in emergencies',
              ),
            ],
          ),
          actions: [
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  permissionManager.requestPermissions();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.success,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: const Text(
                  'Grant Access',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.success, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
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
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: BlocConsumer<MeshBloc, MeshState>(
          listener: (context, state) {
            if (state is MeshError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // Logo & Title
                  _buildHeader(),
                  const SizedBox(height: 40),
                  // Role Selection Cards
                  Expanded(
                    child: _buildRoleSection(context, state),
                  ),
                  // Bottom Status Bar
                  _buildStatusBar(state),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo
        Semantics(
          label: 'RescueNet Logo',
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.danger.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.danger, width: 2),
            ),
            child: const Center(
              child: Icon(
                Icons.cell_tower_rounded,
                color: AppTheme.danger,
                size: 48,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // App Name
        const Text(
          'RescueNet',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        // Tagline
        const Text(
          'Emergency Mesh Network',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSection(BuildContext context, MeshState state) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What would you like to do?',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // I Need Help - Primary Action
          _buildRoleCard(
            icon: Icons.sos_rounded,
            iconColor: AppTheme.danger,
            title: 'I Need Help',
            subtitle: 'Send an emergency SOS to nearby rescuers',
            isPrimary: true,
            onTap: () => _navigateTo(context, const SosFormPage()),
          ),
          const SizedBox(height: 12),
          // I Can Help
          _buildRoleCard(
            icon: Icons.volunteer_activism_rounded,
            iconColor: AppTheme.success,
            title: 'I Can Help',
            subtitle: 'Receive and respond to emergency alerts',
            onTap: () => _navigateTo(context, const ResponderModePage()),
          ),
          const SizedBox(height: 12),
          // Relay Mode
          _buildRoleCard(
            icon: Icons.router_rounded,
            iconColor: AppTheme.primary,
            title: 'Relay Mode',
            subtitle: 'Help extend the network by relaying messages',
            onTap: () => _navigateTo(context, const RelayModePage()),
          ),
          const SizedBox(height: 24),
          // Info section
          _buildInfoSection(),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BlocProvider.value(
          value: context.read<MeshBloc>(),
          child: page,
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isPrimary = false,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              border: Border.all(
                color: isPrimary ? iconColor.withValues(alpha: 0.5) : AppTheme.surfaceHighlight,
                width: isPrimary ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Icon Container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isPrimary ? iconColor : AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textDim,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Works without internet using peer-to-peer mesh networking',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(MeshState state) {
    final isP2PReady = state is MeshActive || state is MeshReady;
    final isRelayActive = state is MeshActive;

    return Semantics(
      label: 'Status bar. Battery: $_batteryLevel percent. ${isRelayActive ? "Relay active" : "Relay inactive"}. ${isP2PReady ? "P2P ready" : "P2P not ready"}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        ),
        child: Row(
          children: [
            // Battery Status
            _buildStatusIndicator(
              icon: _batteryLevel > 20
                  ? Icons.battery_std_rounded
                  : Icons.battery_alert_rounded,
              label: '$_batteryLevel%',
              isActive: _batteryLevel > 20,
              activeColor: AppTheme.success,
              inactiveColor: AppTheme.warning,
            ),
            const SizedBox(width: 24),
            // Relay Status
            _buildStatusIndicator(
              icon: Icons.router_rounded,
              label: 'Relay',
              isActive: isRelayActive,
              activeColor: AppTheme.primary,
            ),
            const SizedBox(width: 24),
            // P2P Status
            _buildStatusIndicator(
              icon: Icons.wifi_tethering_rounded,
              label: 'P2P',
              isActive: isP2PReady,
              activeColor: AppTheme.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    Color? inactiveColor,
  }) {
    final color = isActive ? activeColor : (inactiveColor ?? AppTheme.textDim);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
