import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:study_organizer/core/widgets/glass.dart';

class LegendaryCelebrationOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  const LegendaryCelebrationOverlay({super.key, required this.onDismiss});

  @override
  State<LegendaryCelebrationOverlay> createState() =>
      _LegendaryCelebrationOverlayState();
}

class _LegendaryCelebrationOverlayState
    extends State<LegendaryCelebrationOverlay>
    with TickerProviderStateMixin {
  late List<ConfettiController> _fireworks;
  late AnimationController _colorCtrl;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  Timer? _barrageTimer;

  @override
  void initState() {
    super.initState();
    _fireworks = List.generate(
      5,
      (_) => ConfettiController(duration: const Duration(milliseconds: 800)),
    );
    _startFireworksBarrage();
    _colorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);
  }

  void _startFireworksBarrage() {
    int index = 0;
    _barrageTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      _fireworks[index % 5].play();
      index++;
    });
  }

  @override
  void dispose() {
    for (var c in _fireworks) c.dispose();
    _colorCtrl.dispose();
    _scaleCtrl.dispose();
    _barrageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorCtrl,
      builder: (context, child) {
        final color = HSVColor.fromAHSV(
          0.85,
          _colorCtrl.value * 360,
          1.0,
          1.0,
        ).toColor();
        return Stack(
          children: [
            ModalBarrier(color: color, dismissible: false),
            Align(
              alignment: const Alignment(-0.8, -0.8),
              child: _buildFirework(0),
            ),
            Align(
              alignment: const Alignment(0.8, -0.8),
              child: _buildFirework(1),
            ),
            Align(
              alignment: const Alignment(0, -0.5),
              child: _buildFirework(2),
            ),
            Align(
              alignment: const Alignment(-0.8, 0.5),
              child: _buildFirework(3),
            ),
            Align(
              alignment: const Alignment(0.8, 0.5),
              child: _buildFirework(4),
            ),
            Center(
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Glass(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 100,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 24),
                      _buildShakingText("LEGENDARY!"),
                      const SizedBox(height: 12),
                      const Text(
                        "FULL MARK ACQUIRED",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: widget.onDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        child: const Text(
                          "I AM UNSTOPPABLE",
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFirework(int index) {
    return ConfettiWidget(
      confettiController: _fireworks[index],
      blastDirectionality: BlastDirectionality.explosive,
      shouldLoop: false,
      colors: const [Colors.white, Colors.yellow, Colors.cyan, Colors.lime],
      minBlastForce: 20,
      maxBlastForce: 50,
      numberOfParticles: 15,
    );
  }

  Widget _buildShakingText(String text) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 50), (i) => i),
      builder: (context, snapshot) {
        final offset = snapshot.hasData
            ? Offset(
                (Random().nextDouble() - 0.5) * 6,
                (Random().nextDouble() - 0.5) * 6,
              )
            : Offset.zero;
        return Transform.translate(
          offset: offset,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 10,
                  offset: Offset(2, 2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
