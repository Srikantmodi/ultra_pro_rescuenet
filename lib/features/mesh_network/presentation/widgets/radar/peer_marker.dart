import 'package:flutter/material.dart';
import '../../../domain/entities/node_info.dart';

/// Marker for peer nodes on radar/map.
class PeerMarker extends StatelessWidget {
  final NodeInfo node;
  final bool isSelected;
  final VoidCallback? onTap;
  final double size;

  const PeerMarker({
    super.key,
    required this.node,
    this.isSelected = false,
    this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    Color markerColor = _getMarkerColor();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: markerColor.withAlpha(isSelected ? 200 : 150),
          border: Border.all(
            color: isSelected ? Colors.white : markerColor,
            width: isSelected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: markerColor.withAlpha(100),
              blurRadius: isSelected ? 12 : 6,
              spreadRadius: isSelected ? 2 : 0,
            ),
          ],
        ),
        child: Center(
          child: _getMarkerIcon(),
        ),
      ),
    );
  }

  Color _getMarkerColor() {
    // Triage level priority
    switch (node.triageLevel) {
      case NodeInfo.triageRed:
        return Colors.red;
      case NodeInfo.triageYellow:
        return Colors.orange;
      case NodeInfo.triageGreen:
        return Colors.green;
    }

    // Internet status
    if (node.hasInternet) return Colors.green;

    // Default
    return Colors.blue;
  }

  Widget _getMarkerIcon() {
    IconData icon;
    double iconSize = size * 0.5;

    if (node.triageLevel == NodeInfo.triageRed) {
      icon = Icons.sos;
    } else if (node.hasInternet) {
      icon = Icons.wifi;
    } else if (node.batteryLevel < 20) {
      icon = Icons.battery_alert;
    } else {
      icon = Icons.smartphone;
    }

    return Icon(
      icon,
      color: Colors.white,
      size: iconSize,
    );
  }
}

/// Mini marker for dense displays.
class MiniPeerMarker extends StatelessWidget {
  final NodeInfo node;
  final double size;

  const MiniPeerMarker({
    super.key,
    required this.node,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    Color color = node.hasInternet
        ? Colors.green
        : node.triageLevel != NodeInfo.triageNone
            ? Colors.orange
            : Colors.blue;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 1),
      ),
    );
  }
}
