import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// A professional tactical background with a subtle grid pattern.
class TacticalBackground extends StatelessWidget {
  final Widget child;

  const TacticalBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base color
        Container(color: AppTheme.background),
        
        // Grid Pattern
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(
              color: AppTheme.primary.withValues(alpha: 0.03),
              spacing: 40,
            ),
          ),
        ),

        // Vignette for focus
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  Colors.transparent,
                  AppTheme.background.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
        ),

        // Content
        child,
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double spacing;

  _GridPainter({required this.color, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
