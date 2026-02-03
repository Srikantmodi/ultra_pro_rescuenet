import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

/// Professional mechanical slide-to-activate SOS button.
class SosButton extends StatefulWidget {
  final VoidCallback onConfirmed;
  final double width;
  final double height;

  const SosButton({
    super.key,
    required this.onConfirmed,
    this.width = 300,
    this.height = 76,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with TickerProviderStateMixin {
  double _dragPosition = 0;
  bool _isConfirmed = false;
  late AnimationController _pulseController;
  late AnimationController _confirmController;

  double get _sliderWidth => widget.width - widget.height;
  double get _progress => (_dragPosition / _sliderWidth).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _confirmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isConfirmed) return;
    setState(() {
      _dragPosition += details.delta.dx;
      _dragPosition = _dragPosition.clamp(0.0, _sliderWidth);
    });

    if (_progress > 0.9) {
      _confirm();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isConfirmed) return;
    if (_progress < 0.9) {
      // Snap back
      setState(() {
        _dragPosition = 0;
      });
    }
  }

  void _confirm() {
    setState(() {
      _isConfirmed = true;
      _dragPosition = _sliderWidth;
    });
    HapticFeedback.heavyImpact();
    _confirmController.forward();
    
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onConfirmed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _confirmController]),
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(widget.height / 2),
            border: Border.all(
              color: _isConfirmed ? AppTheme.success : AppTheme.danger.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              // Pulsing glow when idle
              if (!_isConfirmed)
                BoxShadow(
                  color: AppTheme.danger.withValues(alpha: 0.2 * _pulseController.value),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              // Inner shadow for depth
              const BoxShadow(
                color: Colors.black,
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 1. Caution Stripes Background
              if (!_isConfirmed)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.height / 2),
                    child: CustomPaint(
                      painter: _StripesPainter(
                        color: AppTheme.warning.withValues(alpha: 0.05),
                        spacing: 15,
                      ),
                    ),
                  ),
                ),

              // 2. Text Label
              Center(
                child: Opacity(
                  opacity: (1 - _progress).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'SLIDE FOR SOS',
                        style: TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          fontSize: 14,
                          shadows: [
                            Shadow(color: AppTheme.danger.withValues(alpha: 0.5), blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: AppTheme.danger.withValues(alpha: 0.8)),
                      Icon(Icons.chevron_right, color: AppTheme.danger.withValues(alpha: 0.5)),
                      Icon(Icons.chevron_right, color: AppTheme.danger.withValues(alpha: 0.3)),
                    ],
                  ),
                ),
              ),

              // 3. Success State
              if (_isConfirmed)
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: AppTheme.success, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'SOS TRANSMITTED',
                        style: TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(color: AppTheme.success.withValues(alpha: 0.5), blurRadius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 4. Slider Knob (Mechanical Switch)
              Positioned(
                left: _dragPosition + 4, // Padding
                top: 4,
                bottom: 4,
                child: GestureDetector(
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: Container(
                    width: widget.height - 8,
                    height: widget.height - 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isConfirmed 
                          ? [Colors.white, AppTheme.success]
                          : [Colors.grey[200]!, Colors.grey[400]!],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 4,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: widget.height * 0.5,
                        height: widget.height * 0.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isConfirmed ? AppTheme.success : AppTheme.danger,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isConfirmed
                              ? [Colors.white, AppTheme.success]
                              : [Colors.red[400]!, AppTheme.danger],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isConfirmed ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 1,
                            )
                          ],
                        ),
                        child: Icon(
                          _isConfirmed ? Icons.check : Icons.sos,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StripesPainter extends CustomPainter {
  final Color color;
  final double spacing;

  _StripesPainter({required this.color, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2; // Thicker stripes

    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i, size.height),
        Offset(i + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
