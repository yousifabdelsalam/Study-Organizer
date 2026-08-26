import 'dart:math';
import 'package:flutter/material.dart';

class GlitchWidget extends StatefulWidget {
  final Widget child;
  const GlitchWidget({super.key, required this.child});
  @override
  State<GlitchWidget> createState() => _GlitchState();
}

class _GlitchState extends State<GlitchWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  final Random _r = Random();

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Transform.translate(
      offset: Offset((_r.nextDouble() - 0.5) * 9, (_r.nextDouble() - 0.5) * 5),
      child: Stack(
        children: [
          Transform.translate(
            offset: const Offset(5, 0),
            child: Opacity(
              opacity: 0.5,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  1,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0.6,
                  0,
                ]),
                child: widget.child,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(-5, 0),
            child: Opacity(
              opacity: 0.5,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0.6,
                  0,
                ]),
                child: widget.child,
              ),
            ),
          ),
          Opacity(opacity: 0.75, child: widget.child),
        ],
      ),
    ),
  );
}
