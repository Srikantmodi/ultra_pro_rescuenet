import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Slide-to-activate SOS button to prevent accidental triggers.
class SosButtonControl extends StatefulWidget {
  final VoidCallback onConfirmed;
  final double width;
  final double height;

  const SosButtonControl({
    super.key,
    required this.onConfirmed,
    this.width = 280,
    this.height = 60,
  });

  @override
  State<SosButtonControl> createState() => _SosButtonControlState();
}

class _SosButtonControlState extends State<SosButtonControl>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _isConfirmed = false;
  late AnimationController _pulseController;

  double get _sliderWidth => widget.width - widget.height;
  double get _progress => (_dragPosition / _sliderWidth).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition += details.delta.dx;
      _dragPosition = _dragPosition.clamp(0.0, _sliderWidth);
    });

    // Haptic at thresholds
    if (_progress > 0.5 && _progress < 0.52) {
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_progress >= 0.9) {
      _confirm();
    } else {
      setState(() => _dragPosition = 0);
    }
  }

  void _confirm() {
    setState(() {
      _isConfirmed = true;
      _dragPosition = _sliderWidth;
    });
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), widget.onConfirmed);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseScale = _isConfirmed ? 1.0 : 1.0 + (_pulseController.value * 0.03);
        return Transform.scale(
          scale: pulseScale,
          child: _buildButton(),
        );
      },
    );
  }

  Widget _buildButton() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2),
        gradient: LinearGradient(
          colors: _isConfirmed
              ? [Colors.green.shade700, Colors.green.shade500]
              : [Colors.red.shade800, Colors.red.shade600],
        ),
        boxShadow: [
          BoxShadow(
            color: (_isConfirmed ? Colors.green : Colors.red).withAlpha(100),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Progress fill
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.height / 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: widget.height + _dragPosition,
                color: _isConfirmed
                    ? Colors.green.shade400
                    : Colors.red.shade500.withAlpha(150),
              ),
            ),
          ),
          // Label
          Center(
            child: AnimatedOpacity(
              opacity: _isConfirmed ? 0 : (1 - _progress * 0.5),
              duration: const Duration(milliseconds: 100),
              child: const Text(
                'SLIDE TO SEND SOS →',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          // Confirmed text
          if (_isConfirmed)
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'SOS SENT!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          // Thumb
          Positioned(
            left: _dragPosition,
            top: 4,
            child: GestureDetector(
              onHorizontalDragUpdate: _isConfirmed ? null : _onDragUpdate,
              onHorizontalDragEnd: _isConfirmed ? null : _onDragEnd,
              child: Container(
                width: widget.height - 8,
                height: widget.height - 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(70),
                      blurRadius: 6,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _isConfirmed ? Icons.check : Icons.sos,
                  color: _isConfirmed ? Colors.green : Colors.red.shade700,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, child);
}
