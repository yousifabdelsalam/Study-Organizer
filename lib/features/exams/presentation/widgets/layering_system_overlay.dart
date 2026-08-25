import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/features/subjects/data/models/topic.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_audio_service.dart';

class LayeringSystemOverlay extends StatefulWidget {
  final StudyTopic topic;

  const LayeringSystemOverlay({super.key, required this.topic});

  static Future<void> show(BuildContext context, StudyTopic topic) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Layering System',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) => LayeringSystemOverlay(topic: topic),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return BackdropFilter(
          filter: ColorFilter.mode(
            Colors.black.withOpacity(anim1.value * 0.7),
            BlendMode.srcOver,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  State<LayeringSystemOverlay> createState() => _LayeringSystemOverlayState();
}

class _LayeringSystemOverlayState extends State<LayeringSystemOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final Map<int, bool> _stepChecks = {};
  bool _readyForAdvance = false;

  @override
  void initState() {
    super.initState();
    NovaAudioService.playAsset('sounds/attention.mp3');

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleStep(int index, bool val) {
    setState(() {
      _stepChecks[index] = val;
      _readyForAdvance = _allStepsChecked();
    });
    if (val) {
      NovaAudioService.playAsset('sounds/click.mp3'); // A satisfying sound
    }
  }

  bool _allStepsChecked() {
    final layer = widget.topic.currentLayer;
    final totalSteps = layer == 1
        ? 4
        : layer == 2
        ? 3
        : 2;
    for (int i = 0; i < totalSteps; i++) {
      if (!(_stepChecks[i] ?? false)) return false;
    }
    return true;
  }

  void _advanceTopic() {
    NovaAudioService.playAsset('sounds/celebration.mp3');
    final updated = widget.topic.advanceStage();
    context.read<AppBloc>().add(UpdateTopic(updated));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Topic Advanced! Excellent work.'),
        backgroundColor: const Color(0xFF2ED573),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.topic.currentLayer;
    if (layer > 3) {
      return _buildMasteredView();
    }

    final layerColor = layer == 1
        ? const Color(0xFF1E90FF)
        : layer == 2
        ? const Color(0xFFFF9F43)
        : const Color(0xFFFF4757);

    final title = layer == 1
        ? 'LAYER 1: UNDERSTANDING'
        : layer == 2
        ? 'LAYER 2: MEMORIZATION'
        : 'LAYER 3: PRACTICE';

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Glass(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: layerColor.withOpacity(0.15),
                    border: Border(
                      bottom: BorderSide(
                        color: layerColor.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.layers_rounded,
                            color: layerColor,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: layerColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.topic.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (layer == 1) _buildLayer1Steps(),
                      if (layer == 2) _buildLayer2Steps(),
                      if (layer == 3) _buildLayer3Steps(),

                      const SizedBox(height: 32),

                      // Action Button
                      ScaleTransition(
                        scale: _readyForAdvance
                            ? _pulseAnimation
                            : const AlwaysStoppedAnimation(1.0),
                        child: ElevatedButton(
                          onPressed: _readyForAdvance ? _advanceTopic : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: layerColor,
                            disabledBackgroundColor: Colors.grey.withOpacity(
                              0.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.rocket_launch_rounded,
                                color: _readyForAdvance
                                    ? Colors.white
                                    : Colors.white30,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Mark Layer Complete',
                                style: TextStyle(
                                  color: _readyForAdvance
                                      ? Colors.white
                                      : Colors.white30,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Save for later',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayer1Steps() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInstruction(
          'Target: Do not memorize. Only seek to fully understand the concepts.',
        ),
        const SizedBox(height: 24),
        _buildCheckbox(
          0,
          'Take your time to master every single point. No rushing.',
        ),
        _buildCheckbox(
          1,
          'Visualize: See pictures, make mindmaps, connect keywords.',
        ),
        _buildCheckbox(
          2,
          'Write all alternative explanations + maps in your sketch.',
        ),
        _buildCheckbox(3, 'Solve exactly 2 examples about this topic.'),
      ],
    );
  }

  Widget _buildLayer2Steps() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInstruction('Target: Total Memorization. Use Active Recall.'),
        const SizedBox(height: 24),
        _buildCriticalCheckbox(
          0,
          'CRITICAL FIRST STEP: Get a BLANK PAPER. Write everything you can remember right now WITHOUT looking. Fight to remember.',
        ),
        _buildCheckbox(
          1,
          'Explain the topic out loud to yourself/someone else, or write a video script about it.',
        ),
        _buildCheckbox(
          2,
          'Solve ALL provided examples for this topic to confirm memorization.',
        ),
      ],
    );
  }

  Widget _buildLayer3Steps() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInstruction('Target: Deep Practice & Randomization.'),
        const SizedBox(height: 24),
        _buildCriticalCheckbox(
          0,
          'CRITICAL FIRST STEP: Get a BLANK PAPER. Write everything you can remember right now WITHOUT looking.',
        ),
        _buildCheckbox(1, 'Solve ALL questions you can find about this topic.'),
        _buildCheckbox(
          2,
          'WAIT. After a long break, solve them again in a DISORDERED, RANDOM way.',
        ),
      ],
    );
  }

  Widget _buildInstruction(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.track_changes_rounded,
            color: Colors.amber,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(int index, String text) {
    final isChecked = _stepChecks[index] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _toggleStep(index, !isChecked),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isChecked
                ? const Color(0xFF2ED573).withOpacity(0.1)
                : Colors.transparent,
            border: Border.all(
              color: isChecked
                  ? const Color(0xFF2ED573)
                  : Colors.white.withOpacity(0.2),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isChecked
                    ? Icons.task_alt_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isChecked ? const Color(0xFF2ED573) : Colors.white54,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: isChecked ? Colors.white : Colors.white70,
                    fontSize: 15,
                    height: 1.4,
                    decoration: isChecked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCriticalCheckbox(int index, String text) {
    final isChecked = _stepChecks[index] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _toggleStep(index, !isChecked),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isChecked
                ? const Color(0xFF2ED573).withOpacity(0.15)
                : const Color(0xFFFF4757).withOpacity(0.15),
            border: Border.all(
              color: isChecked
                  ? const Color(0xFF2ED573)
                  : const Color(0xFFFF4757),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isChecked
                    ? Icons.task_alt_rounded
                    : Icons.warning_amber_rounded,
                color: isChecked
                    ? const Color(0xFF2ED573)
                    : const Color(0xFFFF4757),
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                    decoration: isChecked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMasteredView() {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 400),
          child: Glass(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFF2ED573),
                  size: 72,
                ),
                const SizedBox(height: 24),
                const Text(
                  'TOPIC MASTERED',
                  style: TextStyle(
                    color: Color(0xFF2ED573),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You have successfully passed this topic through all 3 Layers of the system. It is now in maintenance mode.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ED573),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
