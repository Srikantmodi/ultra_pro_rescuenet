import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/entities/node_info.dart';

/// Custom painter for radar display.
class RadarPainter extends CustomPainter {
  final List<NodeInfo> nodes;
  final String centerNodeId;
  final Animation<double>? animation;

  RadarPainter({
    required this.nodes,
    required this.centerNodeId,
    this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 20;

    // Draw radar circles
    _drawRadarCircles(canvas, center, maxRadius);

    // Draw radar sweep
    if (animation != null) {
      _drawRadarSweep(canvas, center, maxRadius, animation!.value);
    }

    // Draw crosshairs
    _drawCrosshairs(canvas, center, maxRadius);

    // Draw nodes
    _drawNodes(canvas, center, maxRadius);
  }

  void _drawRadarCircles(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..color = Colors.cyan.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final radius = maxRadius * (i / 4);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawRadarSweep(
    Canvas canvas,
    Offset center,
    double maxRadius,
    double progress,
  ) {
    final sweepAngle = progress * 2 * math.pi;

    final gradient = SweepGradient(
      startAngle: sweepAngle - 0.5,
      endAngle: sweepAngle,
      colors: [
        Colors.cyan.withAlpha(0),
        Colors.cyan.withAlpha(100),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: maxRadius),
      );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius),
      sweepAngle - 0.5,
      0.5,
      true,
      paint,
    );
  }

  void _drawCrosshairs(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..color = Colors.cyan.withAlpha(30)
      ..strokeWidth = 1;

    // Horizontal
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      paint,
    );

    // Vertical
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      paint,
    );
  }

  void _drawNodes(Canvas canvas, Offset center, double maxRadius) {
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];

      // Calculate position based on signal strength and index
      final signalNormalized = ((node.signalStrength + 100) / 100).clamp(0.2, 1.0);
      final distance = maxRadius * (1 - signalNormalized * 0.8);
      final angle = (i * 2 * math.pi / nodes.length) - math.pi / 2;

      final x = center.dx + distance * math.cos(angle);
      final y = center.dy + distance * math.sin(angle);

      // Draw node
      final color = node.hasInternet
          ? Colors.green
          : node.triageLevel != NodeInfo.triageNone
              ? Colors.orange
              : Colors.cyan;

      final nodePaint = Paint()..color = color;

      canvas.drawCircle(Offset(x, y), 8, nodePaint);

      // Draw glow
      final glowPaint = Paint()
        ..color = color.withAlpha(50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(x, y), 12, glowPaint);
    }

    // Draw center node
    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.animation != animation;
  }
}
