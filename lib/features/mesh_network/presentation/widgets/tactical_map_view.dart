import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/node_info.dart';
import '../bloc/mesh_bloc.dart';

/// Tactical map view showing node positions and mesh network status.
///
/// This is a simplified map implementation that works offline.
/// Features:
/// - Displays nearby nodes as colored markers
/// - Shows connection lines between nodes
/// - Indicates node status (battery, internet, triage)
/// - Highlights the best route destination
///
/// For production, this would use flutter_map with offline MBTiles.
/// This simplified version provides the core visualization for demo/testing.
class TacticalMapView extends StatelessWidget {
  const TacticalMapView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MeshBloc, MeshState>(
      builder: (context, state) {
        if (state is! MeshActive) {
          return const Center(
            child: Text('Start mesh network to view map'),
          );
        }

        return _TacticalMapCanvas(
          neighbors: state.neighbors,
          hasInternet: state.hasInternet,
        );
      },
    );
  }
}

/// Canvas that draws the tactical map.
class _TacticalMapCanvas extends StatelessWidget {
  final List<NodeInfo> neighbors;
  final bool hasInternet;

  const _TacticalMapCanvas({
    required this.neighbors,
    required this.hasInternet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _TacticalMapPainter(
            neighbors: neighbors,
            hasInternet: hasInternet,
          ),
          child: Stack(
            children: [
              // Grid overlay
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(),
                ),
              ),
              // Legend
              Positioned(
                left: 12,
                bottom: 12,
                child: _MapLegend(),
              ),
              // Node count indicator
              Positioned(
                right: 12,
                top: 12,
                child: _NodeCountIndicator(count: neighbors.length),
              ),
              // Status indicator
              if (hasInternet)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _InternetIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the tactical map.
class _TacticalMapPainter extends CustomPainter {
  final List<NodeInfo> neighbors;
  final bool hasInternet;

  _TacticalMapPainter({
    required this.neighbors,
    required this.hasInternet,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 40;

    // Draw "this device" at center
    _drawCentralNode(canvas, center);

    // Draw neighbors around center
    for (int i = 0; i < neighbors.length; i++) {
      final node = neighbors[i];
      final angle = (2 * math.pi * i) / neighbors.length;
      final distance = _calculateNodeDistance(node);
      final nodeCenter = Offset(
        center.dx + math.cos(angle) * distance * maxRadius,
        center.dy + math.sin(angle) * distance * maxRadius,
      );

      // Draw connection line
      _drawConnectionLine(canvas, center, nodeCenter, node);

      // Draw node
      _drawNodeMarker(canvas, nodeCenter, node, i == 0);
    }
  }

  void _drawCentralNode(Canvas canvas, Offset center) {
    // Outer glow
    final glowPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, 40, glowPaint);

    // Main circle
    final mainPaint = Paint()
      ..color = hasInternet ? Colors.green : Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 25, mainPaint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, 25, borderPaint);

    // "You" label
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'YOU',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  void _drawConnectionLine(Canvas canvas, Offset from, Offset to, NodeInfo node) {
    final linePaint = Paint()
      ..color = _getNodeColor(node).withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, linePaint);

    // Draw signal strength dots along the line
    final distance = (to - from).distance;
    final direction = (to - from) / distance;
    final dotCount = (distance / 30).floor();

    for (int i = 1; i < dotCount; i++) {
      final dotCenter = from + direction * (i * 30);
      final dotPaint = Paint()
        ..color = _getNodeColor(node).withValues(alpha: 0.6);
      canvas.drawCircle(dotCenter, 3, dotPaint);
    }
  }

  void _drawNodeMarker(Canvas canvas, Offset center, NodeInfo node, bool isBest) {
    final nodeColor = _getNodeColor(node);

    // Best node gets special highlight
    if (isBest) {
      final glowPaint = Paint()
        ..color = nodeColor.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
      canvas.drawCircle(center, 30, glowPaint);
    }

    // Main circle
    final mainPaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 18, mainPaint);

    // Border
    final borderPaint = Paint()
      ..color = isBest ? Colors.white : Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = isBest ? 3 : 2;
    canvas.drawCircle(center, 18, borderPaint);

    // Battery indicator arc
    _drawBatteryArc(canvas, center, node.batteryLevel);

    // Internet indicator
    if (node.hasInternet) {
      _drawInternetIndicator(canvas, center);
    }

    // Node ID label
    final textPainter = TextPainter(
      text: TextSpan(
        text: node.displayName.isNotEmpty
            ? node.displayName.substring(0, math.min(3, node.displayName.length))
            : node.id.substring(0, 3),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + 22),
    );
  }

  void _drawBatteryArc(Canvas canvas, Offset center, int batteryLevel) {
    final arcPaint = Paint()
      ..color = batteryLevel > 50
          ? Colors.green
          : batteryLevel > 20
              ? Colors.orange
              : Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (batteryLevel / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 22),
      -math.pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  void _drawInternetIndicator(Canvas canvas, Offset center) {
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    // Small wifi icon
    final iconCenter = Offset(center.dx + 14, center.dy - 14);
    canvas.drawCircle(iconCenter, 6, iconPaint);
    
    final checkPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;
    canvas.drawCircle(iconCenter, 4, checkPaint);
  }

  Color _getNodeColor(NodeInfo node) {
    // Color based on triage level
    switch (node.triageLevel) {
      case NodeInfo.triageRed:
        return Colors.red;
      case NodeInfo.triageYellow:
        return Colors.orange;
      case NodeInfo.triageGreen:
        return Colors.green;
      default:
        // Color based on role/status
        if (node.hasInternet) return Colors.green;
        if (node.role == NodeInfo.roleGoal) return Colors.cyan;
        return Colors.blueGrey;
    }
  }

  double _calculateNodeDistance(NodeInfo node) {
    // Closer signal = closer to center (0.3 to 0.9)
    final signalNorm = node.normalizedSignal;
    return 0.9 - (signalNorm * 0.6);
  }

  @override
  bool shouldRepaint(covariant _TacticalMapPainter oldDelegate) {
    return oldDelegate.neighbors != neighbors ||
        oldDelegate.hasInternet != hasInternet;
  }
}

/// Grid overlay painter.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Vertical lines
    for (double x = 0; x <= size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal lines
    for (double y = 0; y <= size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Concentric circles from center
    final center = Offset(size.width / 2, size.height / 2);
    final circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (double r = 60; r < size.width / 2; r += 60) {
      canvas.drawCircle(center, r, circlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Map legend widget.
class _MapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: Colors.green, label: 'Internet/OK'),
          _LegendItem(color: Colors.blue, label: 'Relay'),
          _LegendItem(color: Colors.orange, label: 'Caution'),
          _LegendItem(color: Colors.red, label: 'Critical'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Node count indicator widget.
class _NodeCountIndicator extends StatelessWidget {
  final int count;

  const _NodeCountIndicator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: count > 0 ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: count > 0 ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people,
            color: count > 0 ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: count > 0 ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internet connectivity indicator widget.
class _InternetIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi, color: Colors.green, size: 16),
          SizedBox(width: 6),
          Text(
            'ONLINE',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
