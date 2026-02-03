import 'package:flutter/material.dart';

/// Widget displaying packet counters.
class PacketCounter extends StatelessWidget {
  final int sent;
  final int received;
  final int relayed;

  const PacketCounter({
    super.key,
    required this.sent,
    required this.received,
    required this.relayed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CounterItem(
            icon: Icons.upload,
            label: 'Sent',
            count: sent,
            color: Colors.blue,
          ),
          _VerticalDivider(),
          _CounterItem(
            icon: Icons.download,
            label: 'Received',
            count: received,
            color: Colors.green,
          ),
          _VerticalDivider(),
          _CounterItem(
            icon: Icons.swap_horiz,
            label: 'Relayed',
            count: relayed,
            color: Colors.purple,
          ),
        ],
      ),
    );
  }
}

class _CounterItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _CounterItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey.withAlpha(50),
    );
  }
}
