import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/mesh_bloc.dart';
import '../../domain/entities/node_info.dart';
import '../../data/services/relay_orchestrator.dart';

/// Relay Mode Page - Automatic packet forwarding with AI node selection.
/// Works silently in background, forwarding packets to best available nodes.
class RelayModePage extends StatefulWidget {
  const RelayModePage({super.key});

  @override
  State<RelayModePage> createState() => _RelayModePageState();
}

class _RelayModePageState extends State<RelayModePage> {
  bool _isRelaying = false;
  int _batteryLevel = 87;
  final List<PacketLogEntry> _packetLog = [];
  Timer? _scanTimer;
  
  @override
  void initState() {
    super.initState();
    _getBatteryLevel();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _getBatteryLevel() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
      }
    } catch (e) {
      // Use default
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: _buildAppBar(),
      body: BlocBuilder<MeshBloc, MeshState>(
        builder: (context, state) {
          final neighbors = state is MeshActive ? state.neighbors : <NodeInfo>[];
          final relayStats = state is MeshActive 
              ? state.relayStats 
              : const RelayStats(
                  packetsSent: 0,
                  packetsFailed: 0,
                  pendingCount: 0,
                  neighborsCount: 0,
                  isRunning: false,
                  consecutiveFailures: 0,
                );
          
          // Build UI based on state
          final currentNodeId = state.nodeId ?? 'Initializing...';
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusCard(currentNodeId),
                const SizedBox(height: 20),
                _buildForwardTargetsSection(neighbors),
                const SizedBox(height: 20),
                _buildStatsRow(relayStats),
                const SizedBox(height: 20),
                _buildPacketLogSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.backgroundPrimary,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Go back',
      ),
      title: Text(
        'Relay Mode',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        Semantics(
          label: 'Battery level $_batteryLevel percent',
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _getBatteryColor().withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getBatteryIcon(),
                  color: _getBatteryColor(),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '$_batteryLevel%',
                  style: TextStyle(
                    color: _getBatteryColor(),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(String nodeId) {
    return Semantics(
      label: _isRelaying ? 'Relay is active' : 'Relay is inactive',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.surfacePrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isRelaying
                ? AppTheme.success
                : AppTheme.borderSubtle,
            width: _isRelaying ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Router icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isRelaying
                      ? AppTheme.success
                      : AppTheme.textTertiary,
                  width: 3,
                ),
                color: _isRelaying
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              child: Center(
                child: Icon(
                  Icons.router,
                  color: _isRelaying
                      ? AppTheme.success
                      : AppTheme.textTertiary,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isRelaying ? 'RELAY ACTIVE' : 'RELAY INACTIVE',
              style: TextStyle(
                color: _isRelaying
                    ? AppTheme.success
                    : AppTheme.textSecondary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Node ID: $nodeId',
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),
            // Start/Stop Relay Button
            SizedBox(
              width: double.infinity,
              height: AppTheme.minTouchTarget,
              child: Semantics(
                button: true,
                label: _isRelaying ? 'Stop relay' : 'Start relay',
                child: ElevatedButton(
                  onPressed: _toggleRelay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRelaying
                        ? AppTheme.error
                        : AppTheme.success,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isRelaying ? 'STOP RELAY' : 'START RELAY',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardTargetsSection(List<NodeInfo> neighbors) {
    // Sort neighbors by AI score (goal nodes first, then by battery/signal)
    final sortedNeighbors = List<NodeInfo>.from(neighbors)
      ..sort((a, b) => _calculateNodeScore(b).compareTo(_calculateNodeScore(a)));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cell_tower,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Forward Targets',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (_isRelaying)
                  IconButton(
                    icon: Icon(Icons.refresh, color: AppTheme.success, size: 20),
                    onPressed: () {
                      _addLogEntry('Refreshing scan...', true);
                      context.read<MeshBloc>().add(const MeshStart());
                    },
                    tooltip: 'Refresh Scan',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                Semantics(
                  label: '${sortedNeighbors.length} nodes available',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sortedNeighbors.length} nodes',
                      style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration,
          child: sortedNeighbors.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        if (_isRelaying) ...[
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.success),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Scanning for nearby nodes...',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ensure nearby devices have WiFi Direct enabled',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          Icon(
                            Icons.wifi_off,
                            color: AppTheme.textTertiary,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start relay to scan for nodes',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : Column(
                  children: sortedNeighbors.asMap().entries.map((entry) {
                    final index = entry.key;
                    final node = entry.value;
                    final isGoal = node.hasInternet;
                    final isLowBattery = node.batteryLevel < 20;
                    final isFirstGoal = isGoal && 
                        sortedNeighbors.take(index).every((n) => !n.hasInternet);
                    
                    return _buildNodeListItem(
                      node: node,
                      isGoal: isGoal,
                      isLowBattery: isLowBattery,
                      showBorder: index > 0,
                      isAiPick: isFirstGoal || (index == 0 && !sortedNeighbors.any((n) => n.hasInternet)),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildNodeListItem({
    required NodeInfo node,
    required bool isGoal,
    required bool isLowBattery,
    required bool showBorder,
    required bool isAiPick,
  }) {
    return Semantics(
      label: '${node.displayName}, ${isGoal ? "has internet access" : "relay node"}, ${node.batteryLevel} percent battery',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: showBorder
              ? Border(top: BorderSide(color: AppTheme.borderSubtle))
              : null,
          color: isAiPick
              ? AppTheme.success.withValues(alpha: 0.1)
              : null,
          borderRadius: isAiPick ? BorderRadius.circular(8) : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isGoal
                    ? AppTheme.success.withValues(alpha: 0.2)
                    : AppTheme.surfaceSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isGoal ? Icons.cell_tower : Icons.smartphone,
                color: isGoal ? AppTheme.success : AppTheme.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          node.displayName,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGoal) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.wifi,
                          color: AppTheme.success,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.deviceAddress} • 10m',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            // Signal & Battery
            Row(
              children: [
                Text(
                  '${((node.signalStrength + 90) / 60 * 100).clamp(0, 100).round()}%',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                if (isGoal)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GOAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (isLowBattery)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LOW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Text(
                    '${node.batteryLevel}%',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(RelayStats stats) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle,
            iconColor: AppTheme.success,
            value: stats.packetsSent.toString(),
            label: 'Relayed',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.cancel,
            iconColor: AppTheme.error,
            value: stats.packetsFailed.toString(),
            label: 'Dropped',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.sync,
            iconColor: AppTheme.info,
            value: _isRelaying ? 'Active' : 'Idle',
            label: 'Status',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: AppTheme.cardDecoration,
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPacketLogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history,
              color: AppTheme.textPrimary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Packet Log',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration,
          child: _packetLog.isEmpty
              ? Center(
                  child: Text(
                    _isRelaying
                        ? 'Waiting for packets...'
                        : 'Start relay to see packet log',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                )
              : Column(
                  children: _packetLog.map((entry) => _buildLogEntry(entry)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildLogEntry(PacketLogEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            entry.success ? Icons.check_circle : Icons.error,
            color: entry.success
                ? AppTheme.success
                : AppTheme.error,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            entry.timestamp,
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRelay() async {
    if (!_isRelaying) {
      // Check permissions before starting
      final permissionsGranted = await _checkAndRequestPermissions();
      if (!permissionsGranted) {
        _showPermissionDialog();
        return;
      }
    }
    
    if (!mounted) return;
    setState(() => _isRelaying = !_isRelaying);
    
    if (_isRelaying) {
      if (!mounted) return;
      context.read<MeshBloc>().add(const MeshStart());
      _addLogEntry('Relay started', true);
      _addLogEntry('Scanning for forward targets...', true);
    } else {
      if (!mounted) return;
      context.read<MeshBloc>().add(const MeshStop());
      _addLogEntry('Relay stopped', true);
    }
  }
  
  Future<bool> _checkAndRequestPermissions() async {
    const channel = MethodChannel('com.rescuenet/wifi_p2p');
    try {
      // First check
      final checkResult = await channel.invokeMethod<Map>('checkPermissions');
      if (checkResult?['allGranted'] == true) {
        return true;
      }
      
      // Request permissions
      final requestResult = await channel.invokeMethod<Map>('requestPermissions');
      if (requestResult?['allGranted'] == true) {
        return true;
      }
      
      // Check again after request
      final finalCheck = await channel.invokeMethod<Map>('checkPermissions');
      return finalCheck?['allGranted'] == true;
    } catch (e) {
      debugPrint('Permission check error: $e');
      return false;
    }
  }
  
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Permissions Required',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          'Wi-Fi Direct requires Location and Wi-Fi permissions to discover nearby devices. Please grant all requested permissions.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _checkAndRequestPermissions();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Grant Permissions', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addLogEntry(String message, bool success) {
    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    setState(() {
      _packetLog.insert(0, PacketLogEntry(
        message: message,
        timestamp: timestamp,
        success: success,
      ));
      if (_packetLog.length > 20) {
        _packetLog.removeLast();
      }
    });
  }

  int _calculateNodeScore(NodeInfo node) {
    int score = 0;
    if (node.hasInternet) score += 50;
    score += (node.batteryLevel * 0.25).round();
    score += ((node.signalStrength + 90) * 0.17).round();
    return score;
  }

  Color _getBatteryColor() {
    if (_batteryLevel >= 50) return AppTheme.success;
    if (_batteryLevel >= 20) return AppTheme.warning;
    return AppTheme.error;
  }

  IconData _getBatteryIcon() {
    if (_batteryLevel >= 80) return Icons.battery_full;
    if (_batteryLevel >= 50) return Icons.battery_5_bar;
    if (_batteryLevel >= 20) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }
}

/// Represents a log entry for packet forwarding
class PacketLogEntry {
  final String message;
  final String timestamp;
  final bool success;

  PacketLogEntry({
    required this.message,
    required this.timestamp,
    required this.success,
  });
}
