import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../bloc/mesh/mesh_bloc.dart';
import '../bloc/mesh/mesh_state.dart';
import '../widgets/lists/packet_log_item.dart';
import '../../data/datasources/local/hive/boxes/outbox_box.dart';

/// Page showing packet history including outbox status.
class PacketHistoryPage extends StatefulWidget {
  const PacketHistoryPage({super.key});

  @override
  State<PacketHistoryPage> createState() => _PacketHistoryPageState();
}

class _PacketHistoryPageState extends State<PacketHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Packet History'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyan,
          tabs: const [
            Tab(text: 'Recent'),
            Tab(text: 'Outbox'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRecentTab(),
          _buildOutboxTab(),
        ],
      ),
    );
  }

  /// FIX E-4: Recent packets from BLoC state.
  Widget _buildRecentTab() {
    return BlocBuilder<MeshBloc, MeshState>(
      builder: (context, state) {
        if (state.recentPackets.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No packets yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                SizedBox(height: 8),
                Text(
                  'Packets will appear here as they are\nreceived and sent through the mesh',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: state.recentPackets.length,
          itemBuilder: (context, index) {
            final packet = state.recentPackets[index];
            return PacketLogItem(
              packet: packet,
              isIncoming: true,
              onTap: () => _showPacketDetails(context, packet),
            );
          },
        );
      },
    );
  }

  /// FIX E-4: Outbox entries showing pending/sent/failed with retry counts.
  Widget _buildOutboxTab() {
    List<OutboxEntry> entries = [];
    try {
      final outbox = GetIt.instance<OutboxBox>();
      entries = outbox.getAllEntries();
    } catch (_) {
      // OutboxBox might not be registered yet
    }

    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.outbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Outbox empty', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final statusColor = switch (entry.status.name) {
            'sent' => Colors.green,
            'failed' => Colors.red,
            _ => Colors.amber,
          };
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, color: statusColor, size: 10),
                    const SizedBox(width: 8),
                    Text(
                      entry.status.name.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      'Retry: ${entry.retryCount}/${OutboxBox.maxRetries}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'ID: ${entry.packet.id}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Added: ${DateTime.fromMillisecondsSinceEpoch(entry.addedAt).toString().substring(0, 19)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter Packets',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _FilterChip(label: 'All', isSelected: true),
              _FilterChip(label: 'SOS', isSelected: false),
              _FilterChip(label: 'Data', isSelected: false),
              _FilterChip(label: 'ACK', isSelected: false),
            ],
          ),
        );
      },
    );
  }

  void _showPacketDetails(BuildContext context, dynamic packet) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Packet Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DetailRow('ID', packet.id),
                  _DetailRow('Originator', packet.originatorId),
                  _DetailRow('TTL', '${packet.ttl}'),
                  _DetailRow('Type', packet.type.toString()),
                  _DetailRow('Hops', '${packet.trace.length}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Trace',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ...packet.trace.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${e.key + 1}. ${e.value}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _FilterChip({required this.label, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {},
        backgroundColor: const Color(0xFF2A2A3E),
        selectedColor: Colors.cyan.withAlpha(50),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
