import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:battery_plus/battery_plus.dart';
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
  int _lastRelayedCount = 0;
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
      backgroundColor: const Color(0xFF0F172A),
      appBar: _buildAppBar(),
      body: BlocConsumer<MeshBloc, MeshState>(
        listener: (context, state) {
          // FIX C-4: Sync local _isRelaying with actual BLoC state
          // Prevents desync where button says "Active" but BLoC is in MeshReady.
          final shouldBeRelaying = state is MeshActive;
          if (_isRelaying != shouldBeRelaying) {
            setState(() => _isRelaying = shouldBeRelaying);
          }
          
          // Auto-add packet log entry when new SOS is relayed
          if (state is MeshActive && state.relayedSosCount > _lastRelayedCount) {
            _addLogEntry('SOS packet received & forwarding...', true);
            _lastRelayedCount = state.relayedSosCount;
          }
        },
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
          final relayedSosCount = state is MeshActive ? state.relayedSosCount : 0;
          
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
                _buildStatsRow(relayStats, relayedSosCount),
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
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Relay Mode',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        Container(
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
      ],
    );
  }

  Widget _buildStatusCard(String nodeId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRelaying
              ? const Color(0xFF10B981)
              : const Color(0xFF334155),
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
                    ? const Color(0xFF10B981)
                    : const Color(0xFF475569),
                width: 3,
              ),
              color: _isRelaying
                  ? const Color(0xFF10B981).withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Center(
              child: Icon(
                Icons.router,
                color: _isRelaying
                    ? const Color(0xFF10B981)
                    : const Color(0xFF64748B),
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isRelaying ? 'RELAY ACTIVE' : 'RELAY INACTIVE',
            style: TextStyle(
              color: _isRelaying
                  ? const Color(0xFF10B981)
                  : const Color(0xFF94A3B8),
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Node ID: $nodeId',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),
          // Start/Stop Relay Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _toggleRelay,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRelaying
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
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
        ],
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
                const Icon(
                  Icons.cell_tower,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Forward Targets',
                  style: TextStyle(
                    color: Colors.white,
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
                    icon: const Icon(Icons.refresh, color: Color(0xFF10B981), size: 20),
                    onPressed: () {
                      _addLogEntry('Refreshing scan...', true);
                      context.read<MeshBloc>().add(const MeshStart());
                    },
                    tooltip: 'Refresh Scan',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${sortedNeighbors.length} nodes',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: sortedNeighbors.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        if (_isRelaying) ...[
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Scanning for nearby nodes...',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ensure nearby devices have WiFi Direct enabled',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          Icon(
                            Icons.wifi_off,
                            color: Colors.grey[600],
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start relay to scan for nodes',
                            style: TextStyle(
                              color: Colors.grey[600],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: showBorder
            ? const Border(top: BorderSide(color: Color(0xFF334155)))
            : null,
        color: isAiPick
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
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
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isGoal ? Icons.cell_tower : Icons.smartphone,
              color: isGoal ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isGoal) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.wifi,
                        color: Color(0xFF10B981),
                        size: 14,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${node.deviceAddress} • 10m',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
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
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              if (isGoal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
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
                    color: const Color(0xFFEF4444),
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
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(RelayStats stats, int relayedSosCount) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.sos,
            iconColor: const Color(0xFFFBBF24),
            value: relayedSosCount.toString(),
            label: 'SOS Relayed',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle,
            iconColor: const Color(0xFF10B981),
            value: stats.packetsSent.toString(),
            label: 'Forwarded',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.cancel,
            iconColor: const Color(0xFFEF4444),
            value: stats.packetsFailed.toString(),
            label: 'Dropped',
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPacketLogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.history,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'Packet Log',
              style: TextStyle(
                color: Colors.white,
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
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: _packetLog.isEmpty
              ? Center(
                  child: Text(
                    _isRelaying
                        ? 'Waiting for packets...'
                        : 'Start relay to see packet log',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
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
                ? const Color(0xFF10B981)
                : const Color(0xFFEF4444),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            entry.timestamp,
            style: const TextStyle(
              color: Color(0xFF64748B),
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
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Permissions Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Wi-Fi Direct requires Location and Wi-Fi permissions to discover nearby devices. Please grant all requested permissions.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _checkAndRequestPermissions();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
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
    if (_batteryLevel >= 50) return const Color(0xFF10B981);
    if (_batteryLevel >= 20) return const Color(0xFFFBBF24);
    return const Color(0xFFEF4444);
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
