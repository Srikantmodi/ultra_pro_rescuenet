import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

/// Switch for enabling/disabling relay mode.
class RelayModeSwitch extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const RelayModeSwitch({
    super.key,
    required this.isEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled
              ? Colors.green.withAlpha(100)
              : Colors.grey.withAlpha(50),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cable,
            color: isEnabled ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Relay Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                isEnabled ? 'Forwarding packets' : 'Not relaying',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Switch(
            value: isEnabled,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            activeTrackColor: Colors.green.withAlpha(100),
          ),
        ],
      ),
    );
  }
}
