// nova_brief_card.dart
// The dashboard brief card + the "Brief paused — tap to hear" top banner.
// Styled after the dark circuit-board / neon-green aesthetic from the design refs.

import 'package:flutter/material.dart';
import 'package:study_organizer/features/nova_intelligence/data/services/nova_brief_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NovaBriefCard — sits on the dashboard, listens to novaBriefText notifier
// ─────────────────────────────────────────────────────────────────────────────
class NovaBriefCard extends StatelessWidget {
  /// Called when user taps "Hear" to replay TTS.
  final VoidCallback onHear;

  const NovaBriefCard({super.key, required this.onHear});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: novaBriefText,
      builder: (_, brief, __) {
        if (brief == null) return const SizedBox.shrink();
        return _BriefCardContent(brief: brief, onHear: onHear);
      },
    );
  }
}

class _BriefCardContent extends StatelessWidget {
  final String brief;
  final VoidCallback onHear;

  const _BriefCardContent({required this.brief, required this.onHear});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        // Dark base matching circuit-board design ref
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF39FF14).withOpacity(0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF39FF14).withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF39FF14).withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF39FF14).withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                // Animated dot
                ValueListenableBuilder<bool>(
                  valueListenable: novaBriefSpeaking,
                  builder: (_, speaking, __) => AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: speaking
                          ? const Color(0xFF39FF14)
                          : const Color(0xFF39FF14).withOpacity(0.4),
                      boxShadow: speaking
                          ? [
                              BoxShadow(
                                color: const Color(0xFF39FF14).withOpacity(0.7),
                                blurRadius: 6,
                              ),
                            ]
                          : [],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'NOVA  BRIEFING',
                  style: TextStyle(
                    color: Color(0xFF39FF14),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    fontFamily: 'Courier',
                  ),
                ),
                const Spacer(),
                // Dismiss button
                GestureDetector(
                  onTap: NovaBriefService.dismissBrief,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white38,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Brief text ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              brief,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          // ── Hear button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                // Circuit decoration line
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFF39FF14).withOpacity(0.3),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder<bool>(
                  valueListenable: novaBriefSpeaking,
                  builder: (_, speaking, __) => GestureDetector(
                    onTap: speaking ? null : onHear,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: speaking
                            ? const Color(0xFF39FF14).withOpacity(0.15)
                            : Colors.transparent,
                        border: Border.all(
                          color: speaking
                              ? const Color(0xFF39FF14)
                              : const Color(0xFF39FF14).withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            speaking
                                ? Icons.graphic_eq_rounded
                                : Icons.volume_up_rounded,
                            color: const Color(0xFF39FF14),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            speaking ? 'SPEAKING...' : 'HEAR BRIEF',
                            style: const TextStyle(
                              color: Color(0xFF39FF14),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────
