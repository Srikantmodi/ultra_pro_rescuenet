import 'package:flutter/material.dart';

/// Signal strength bar indicator.
class SignalStrengthBar extends StatelessWidget {
  final int strength; // In dBm (-100 to 0)
  final int bars;
  final double height;

  const SignalStrengthBar({
    super.key,
    required this.strength,
    this.bars = 4,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    final activeBars = _calculateActiveBars();
    final color = _getColor();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(bars, (index) {
        final barHeight = height * (index + 1) / bars;
        final isActive = index < activeBars;

        return Container(
          width: 4,
          height: barHeight,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.grey.withAlpha(50),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  int _calculateActiveBars() {
    // Map -100 to 0 dBm to 0 to bars
    if (strength >= -50) return bars;
    if (strength >= -60) return bars - 1;
    if (strength >= -70) return bars - 2;
    if (strength >= -80) return 1;
    return 0;
  }

  Color _getColor() {
    if (strength >= -50) return Colors.green;
    if (strength >= -60) return Colors.lightGreen;
    if (strength >= -70) return Colors.orange;
    return Colors.red;
  }
}

/// Large signal strength indicator with label.
class SignalStrengthIndicator extends StatelessWidget {
  final int strength;

  const SignalStrengthIndicator({
    super.key,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SignalStrengthBar(strength: strength),
        const SizedBox(width: 8),
        Text(
          '${strength}dBm',
          style: TextStyle(
            color: _getColor(strength),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getColor(int strength) {
    if (strength >= -50) return Colors.green;
    if (strength >= -70) return Colors.orange;
    return Colors.red;
  }
}
