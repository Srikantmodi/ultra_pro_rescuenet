import 'package:flutter/material.dart';

/// Badge showing internet connectivity status.
class InternetBadge extends StatelessWidget {
  final bool hasInternet;
  final bool showLabel;

  const InternetBadge({
    super.key,
    required this.hasInternet,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 12 : 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: hasInternet
            ? Colors.green.withAlpha(30)
            : Colors.orange.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasInternet
              ? Colors.green.withAlpha(100)
              : Colors.orange.withAlpha(100),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasInternet ? Icons.cloud_done : Icons.cloud_off,
            color: hasInternet ? Colors.green : Colors.orange,
            size: 16,
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              hasInternet ? 'Online' : 'Offline',
              style: TextStyle(
                color: hasInternet ? Colors.green : Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
