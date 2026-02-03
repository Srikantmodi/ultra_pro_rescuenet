import 'package:flutter/material.dart';

/// Toggle button for discovery mode.
class DiscoveryToggle extends StatelessWidget {
  final bool isDiscovering;
  final VoidCallback onToggle;

  const DiscoveryToggle({
    super.key,
    required this.isDiscovering,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDiscovering
                ? [Colors.cyan.shade700, Colors.cyan.shade500]
                : [Colors.grey.shade700, Colors.grey.shade600],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: isDiscovering
              ? [
                  BoxShadow(
                    color: Colors.cyan.withAlpha(100),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              turns: isDiscovering ? 1 : 0,
              duration: const Duration(seconds: 2),
              child: Icon(
                isDiscovering ? Icons.radar : Icons.wifi_find,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isDiscovering ? 'Discovering...' : 'Start Discovery',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
