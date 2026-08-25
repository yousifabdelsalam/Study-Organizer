import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding, margin;
  final double radius;
  const Glass(
      {super.key,
        required this.child,
        this.padding,
        this.margin,
        this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: d
            ? const Color(0xFF1A1A3E).withOpacity(0.55)
            : Colors.white.withOpacity(0.75),
        border: Border.all(
            color: d
                ? Colors.white.withOpacity(0.07)
                : Colors.white.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
              color: d
                  ? Colors.black.withOpacity(0.25)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child:
        Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
      ),
    );
  }
}