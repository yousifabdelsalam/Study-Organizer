import 'dart:math';
import 'package:flutter/material.dart';

class ParticleData {
  final double x, y, speed, delay;
  final String char;
  const ParticleData({
    required this.x,
    required this.y,
    required this.char,
    required this.speed,
    required this.delay,
  });
}

class RainDropData {
  final double x, speed, delay;
  const RainDropData({required this.x, required this.speed, required this.delay});
}

class ParticlePainter extends CustomPainter {
  final List<ParticleData> particles;
  final double t;
  final Color color;
  ParticlePainter({
    required this.particles,
    required this.t,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final p in particles) {
      final phase = ((t * p.speed + p.delay * 0.2) % 1.0);
      final opacity = phase < 0.1
          ? phase * 10
          : phase > 0.8
          ? (1 - phase) * 5
          : 0.5;
      tp.text = TextSpan(
        text: p.char,
        style: TextStyle(
          color: color.withOpacity(opacity.clamp(0.0, 0.5)),
          fontFamily: 'Courier',
          fontSize: 10,
        ),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(p.x * size.width, (p.y - phase * 0.4) * size.height),
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter old) => old.t != t || old.color != color;
}

class RainPainter extends CustomPainter {
  final List<RainDropData> drops;
  final double t;
  final Color color;
  RainPainter({required this.drops, required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in drops) {
      final phase = (t * d.speed + d.delay * 0.1) % 1.0;
      final y = phase * (size.height + 100) - 100;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            color.withOpacity(0.15),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(d.x * size.width, y, 1, 80))
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(d.x * size.width, y),
        Offset(d.x * size.width, y + 80),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(RainPainter old) => old.t != t || old.color != color;
}

class GridPainter extends CustomPainter {
  final double t;
  final Color color;
  GridPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const step = 60.0;
    final offset = (t * step) % step;
    final paint = Paint()
      ..color = color.withOpacity(0.06)
      ..strokeWidth = 0.5;
    for (double x = -step + offset; x < size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = -step + offset; y < size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => old.t != t || old.color != color;
}

class RingsPainter extends CustomPainter {
  final double loop;
  final Color color, secondary;
  RingsPainter({
    required this.loop,
    required this.color,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;

    void ring(double r, Color c, double dash1, double dash2, double angle) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c.withOpacity(0.2);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      canvas.drawCircle(
        Offset.zero,
        r,
        paint
          ..strokeWidth = 1
          ..color = c.withOpacity(0.2),
      );
      canvas.restore();
    }

    final a1 = loop * 2 * pi;
    final a2 = -loop * 2 * pi;
    ring(size.width * 0.5, color, 10, 10, a1);
    ring(size.width * 0.47, color, 5, 15, a1);
    ring(size.width * 0.48, secondary, 15, 5, a2);
  }

  @override
  bool shouldRepaint(RingsPainter old) => old.loop != loop;
}

class CorePainter extends CustomPainter {
  final double progress, breath, burst;
  final Color color, secondary;
  CorePainter({
    required this.progress,
    required this.breath,
    required this.burst,
    required this.color,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = size.width / 2 - 10;

    // Glow background
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = color.withOpacity(0.04 + 0.04 * breath)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    // Border circle
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withOpacity(0.3 + 0.2 * breath),
    );

    // Track
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF0A0A0A),
    );

    // Progress arc
    if (progress > 0) {
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      final sweep = 2 * pi * progress;
      canvas.drawArc(
        rect,
        -pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: -pi / 2,
            endAngle: -pi / 2 + sweep,
            colors: [color, secondary],
          ).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Hex pattern overlay (subtle)
    final hexPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = color.withOpacity(0.08);
    const hexSize = 14.0;
    for (double hx = cx - r; hx < cx + r; hx += hexSize * 1.5) {
      for (double hy = cy - r; hy < cy + r; hy += hexSize * sqrt(3)) {
        final offset = ((hx - (cx - r)) / (hexSize * 1.5)).floor() % 2 == 0
            ? 0.0
            : hexSize * sqrt(3) / 2;
        final hxf = hx, hyf = hy + offset;
        if ((Offset(hxf, hyf) - Offset(cx, cy)).distance < r - 5) {
          final path = Path();
          for (int i = 0; i < 6; i++) {
            final a = i * pi / 3;
            final px = hxf + hexSize * 0.5 * cos(a);
            final py = hyf + hexSize * 0.5 * sin(a);
            if (i == 0) {
              path.moveTo(px, py);
            } else {
              path.lineTo(px, py);
            }
          }
          path.close();
          canvas.drawPath(path, hexPaint);
        }
      }
    }

    // Burst rings on completion
    if (burst > 0) {
      for (int i = 0; i < 3; i++) {
        final delay = i / 3.0;
        final phase = ((burst - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (phase <= 0) continue;
        canvas.drawCircle(
          Offset(cx, cy),
          r * 1.1 * phase,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withOpacity((1 - phase) * 0.7),
        );
      }
    }
  }

  @override
  bool shouldRepaint(CorePainter old) => true;
}

class BracketPainter extends CustomPainter {
  final int corner;
  final Color color;
  BracketPainter({required this.corner, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final w = size.width, h = size.height;
    const arm = 10.0;
    Path path;

    switch (corner) {
      case 0: // top-left
        path = Path()
          ..moveTo(0, arm)
          ..lineTo(0, 0)
          ..lineTo(arm, 0);
        break;
      case 1: // top-right
        path = Path()
          ..moveTo(w - arm, 0)
          ..lineTo(w, 0)
          ..lineTo(w, arm);
        break;
      case 2: // bottom-right
        path = Path()
          ..moveTo(w, h - arm)
          ..lineTo(w, h)
          ..lineTo(w - arm, h);
        break;
      default: // bottom-left
        path = Path()
          ..moveTo(arm, h)
          ..lineTo(0, h)
          ..lineTo(0, h - arm);
    }

    canvas.drawPath(path, paint);

    // Corner dot
    final dotPos = corner == 0
        ? Offset.zero
        : corner == 1
        ? Offset(w, 0)
        : corner == 2
        ? Offset(w, h)
        : Offset(0, h);
    canvas.drawCircle(
      dotPos,
      2.5,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(BracketPainter old) => old.color != color;
}

// Aliases for private names
typedef _Particle = ParticleData;
typedef _RainDrop = RainDropData;
typedef _ParticlePainter = ParticlePainter;
typedef _RainPainter = RainPainter;
typedef _GridPainter = GridPainter;
typedef _RingsPainter = RingsPainter;
typedef _CorePainter = CorePainter;
typedef _BracketPainter = BracketPainter;
