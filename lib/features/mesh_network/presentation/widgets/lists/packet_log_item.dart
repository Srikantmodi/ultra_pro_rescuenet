import 'package:flutter/material.dart';
import '../../../domain/entities/mesh_packet.dart';

/// List item for displaying packet log entries.
class PacketLogItem extends StatelessWidget {
  final MeshPacket packet;
  final bool isIncoming;
  final VoidCallback? onTap;

  const PacketLogItem({
    super.key,
    required this.packet,
    required this.isIncoming,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFF1A1A2E),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Direction indicator
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isIncoming
                      ? Colors.blue.withAlpha(50)
                      : Colors.green.withAlpha(50),
                ),
                child: Icon(
                  isIncoming ? Icons.download : Icons.upload,
                  color: isIncoming ? Colors.blue : Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type and ID
                    Row(
                      children: [
                        _buildTypeChip(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ID: ${packet.id.substring(0, 8)}...',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Route info
                    Text(
                      'From: ${packet.originatorId.substring(0, 8)}... → ${packet.trace.length} hops',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // TTL and time
                    Row(
                      children: [
                        Text(
                          'TTL: ${packet.ttl}',
                          style: TextStyle(
                            color: packet.ttl <= 2 ? Colors.orange : Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTime(DateTime.fromMillisecondsSinceEpoch(packet.timestamp)),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Priority indicator
              if (packet.priority > 5)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.priority_high,
                    color: Colors.red,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip() {
    Color color;
    String label;
    IconData icon;

    switch (packet.type) {
      case PacketType.sos:
        color = Colors.red;
        label = 'SOS';
        icon = Icons.sos;
        break;
      case PacketType.ack:
        color = Colors.green;
        label = 'ACK';
        icon = Icons.check;
        break;
      case PacketType.status: // Used for discovery/status
        color = Colors.blue;
        label = 'STAT';
        icon = Icons.search;
        break;
      case PacketType.data:
        color = Colors.purple;
        label = 'DATA';
        icon = Icons.send;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
