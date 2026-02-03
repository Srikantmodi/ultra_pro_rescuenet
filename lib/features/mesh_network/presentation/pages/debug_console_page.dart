import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/mesh/mesh_bloc.dart';
import '../bloc/mesh/mesh_state.dart';
import '../widgets/lists/packet_log_item.dart';

/// Debug console page for viewing logs and packets.
class DebugConsolePage extends StatefulWidget {
  const DebugConsolePage({super.key});

  @override
  State<DebugConsolePage> createState() => _DebugConsolePageState();
}

class _DebugConsolePageState extends State<DebugConsolePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: const Text('Debug Console'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyan,
          tabs: const [
            Tab(text: 'Packets'),
            Tab(text: 'Logs'),
            Tab(text: 'Stats'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPacketsTab(),
          _buildLogsTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  Widget _buildPacketsTab() {
    return BlocBuilder<MeshBloc, MeshState>(
      builder: (context, state) {
        if (state.recentPackets.isEmpty) {
          return const Center(
            child: Text(
              'No packets yet',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: state.recentPackets.length,
          itemBuilder: (context, index) {
            return PacketLogItem(
              packet: state.recentPackets[index],
              isIncoming: true,
            );
          },
        );
      },
    );
  }

  Widget _buildLogsTab() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          'No logs yet',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            _logs[index],
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsTab() {
    return BlocBuilder<MeshBloc, MeshState>(
      builder: (context, state) {
        final stats = state.statistics;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatCard('Packets Sent', stats.packetsSent),
              _buildStatCard('Packets Received', stats.packetsReceived),
              _buildStatCard('Packets Relayed', stats.packetsRelayed),
              _buildStatCard('SOS Received', stats.sosReceived, isAlert: true),
              _buildStatCard('Duplicates Dropped', stats.duplicatesDropped),
              const Divider(color: Colors.grey),
              _buildStatCard('Neighbors', state.neighborCount),
              _buildStatCard('Status', state.isActive ? 1 : 0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, int value, {bool isAlert = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            value.toString(),
            style: TextStyle(
              color: isAlert && value > 0 ? Colors.red : Colors.cyan,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}
