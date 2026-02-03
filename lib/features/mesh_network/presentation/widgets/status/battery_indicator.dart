import 'package:flutter/material.dart';

/// Battery level indicator widget.
class BatteryIndicator extends StatelessWidget {
  final int level;
  final bool isCharging;
  final double size;

  const BatteryIndicator({
    super.key,
    required this.level,
    this.isCharging = false,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBatteryIcon(),
        const SizedBox(width: 4),
        Text(
          '$level%',
          style: TextStyle(
            color: _getBatteryColor(),
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          _getBatteryIcon(),
          color: _getBatteryColor(),
          size: size,
        ),
        if (isCharging)
          Icon(
            Icons.bolt,
            color: Colors.yellow,
            size: size * 0.5,
          ),
      ],
    );
  }

  IconData _getBatteryIcon() {
    if (isCharging) return Icons.battery_charging_full;
    if (level >= 90) return Icons.battery_full;
    if (level >= 80) return Icons.battery_6_bar;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 40) return Icons.battery_4_bar;
    if (level >= 30) return Icons.battery_3_bar;
    if (level >= 20) return Icons.battery_2_bar;
    if (level >= 10) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }

  Color _getBatteryColor() {
    if (isCharging) return Colors.green;
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }
}
