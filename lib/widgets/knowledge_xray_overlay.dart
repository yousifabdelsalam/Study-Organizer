import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../services/jarvis_brain_service.dart';
import '../models/jarvis_document.dart';
import '../widgets/glass.dart';

class KnowledgeXRayOverlay extends StatefulWidget {
  final Subject subject;
  final StudyTopic topic;
  final List<JarvisDocument> pastExams;

  const KnowledgeXRayOverlay({
    super.key,
    required this.subject,
    required this.topic,
    required this.pastExams,
  });

  @override
  State<KnowledgeXRayOverlay> createState() => _KnowledgeXRayOverlayState();
}

class _KnowledgeXRayOverlayState extends State<KnowledgeXRayOverlay> {
  final TextEditingController _summaryCtrl = TextEditingController();

  bool _isTiming = false;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _parsedResult;
  String? _rawError;

  int _secondsPassed = 0;
  Timer? _timer;

  void _startTimer() {
    if (_summaryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a quick summary of the question first.'),
        ),
      );
      return;
    }
    setState(() {
      _isTiming = true;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsPassed++;
      });
    });
  }

  Future<void> _stopAndAnalyze() async {
    _timer?.cancel();
    setState(() {
      _isTiming = false;
      _isAnalyzing = true;
    });

    final rawRes = await JarvisBrainService.analyzeSolvingSpeed(
      subjectName: widget.subject.name,
      topicTitle: widget.topic.title,
      questionSummary: _summaryCtrl.text.trim(),
      timeTakenSeconds: _secondsPassed,
      pastExams: widget.pastExams,
    );

    if (!mounted) return;

    // Parse JSON result
    try {
      final sanitized = rawRes
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final parsed = jsonDecode(sanitized) as Map<String, dynamic>;
      setState(() {
        _isAnalyzing = false;
        _parsedResult = parsed;
      });
    } catch (_) {
      setState(() {
        _isAnalyzing = false;
        _rawError = rawRes;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _summaryCtrl.dispose();
    super.dispose();
  }

  String _formatSecs(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_rounded, color: Colors.cyanAccent, size: 36),
                  SizedBox(width: 12),
                  Text(
                    'KNOWLEDGE X-RAY',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.subject.name} • ${widget.topic.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              if (_isAnalyzing)
                const Column(
                  children: [
                    SizedBox(height: 40),
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing problem-solving speed...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                )
              else if (_parsedResult != null)
                _buildAnalysisView()
              else if (_rawError != null)
                _buildErrorView()
              else
                _buildTimerView(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerView() {
    return Glass(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _summaryCtrl,
            maxLines: 2,
            enabled: !_isTiming,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText:
                  'What question are you solving? (e.g. "Calculating flux integral")',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              _formatSecs(_secondsPassed),
              style: TextStyle(
                color: _isTiming ? Colors.cyanAccent : Colors.white54,
                fontWeight: FontWeight.w900,
                fontSize: 64,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 32),
          if (!_isTiming && _secondsPassed == 0)
            ElevatedButton(
              onPressed: _startTimer,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Start Practice Timer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            )
          else if (_isTiming)
            ElevatedButton(
              onPressed: _stopAndAnalyze,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Finish & Analyze Speed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          const SizedBox(height: 16),
          if (!_isTiming)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisView() {
    final data = _parsedResult!;
    final int estimatedSecs =
        (data['estimated_time_seconds'] as num?)?.toInt() ?? 0;
    final String verdict = data['verdict']?.toString() ?? 'GOOD';
    final int speedRating = (data['speed_rating'] as num?)?.toInt() ?? 5;
    final String diagnosis = data['diagnosis']?.toString() ?? '';
    final List<String> shortcuts =
        (data['shortcuts'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final List<String> carelessRisks =
        (data['careless_risks'] as List?)?.map((e) => e.toString()).toList() ??
        [];

    // Verdict colors
    Color verdictColor;
    String verdictLabel;
    IconData verdictIcon;
    switch (verdict) {
      case 'TOO_SLOW':
        verdictColor = Colors.redAccent;
        verdictLabel = 'TOO SLOW';
        verdictIcon = Icons.speed_rounded;
        break;
      case 'TOO_FAST':
        verdictColor = Colors.orangeAccent;
        verdictLabel = 'TOO FAST';
        verdictIcon = Icons.flash_on_rounded;
        break;
      case 'GOOD':
        verdictColor = Colors.greenAccent;
        verdictLabel = 'GOOD SPEED';
        verdictIcon = Icons.check_circle_rounded;
        break;
      default:
        verdictColor = Colors.grey;
        verdictLabel = 'N/A';
        verdictIcon = Icons.info_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Verdict badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: verdictColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: verdictColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(verdictIcon, color: verdictColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        verdictLabel,
                        style: TextStyle(
                          color: verdictColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Time comparison bar
              const Text(
                'TIME COMPARISON',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              _buildTimeBar(
                label: 'Your Time',
                seconds: _secondsPassed,
                color: verdictColor,
              ),
              const SizedBox(height: 6),
              if (estimatedSecs > 0)
                _buildTimeBar(
                  label: 'JARVIS Estimate',
                  seconds: estimatedSecs,
                  color: Colors.cyanAccent,
                  isReference: true,
                ),
              const SizedBox(height: 20),

              // Speed rating stars
              const Text(
                'SPEED RATING',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(10, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(
                      i < speedRating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i < speedRating
                          ? Colors.cyanAccent
                          : Colors.white24,
                      size: 20,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '$speedRating / 10',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Diagnosis
        Glass(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.analytics_rounded,
                    color: Colors.cyanAccent,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'DIAGNOSIS',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                diagnosis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),

        // Shortcuts (if any)
        if (shortcuts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: Colors.orangeAccent,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'MENTAL SHORTCUTS TO LEARN',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...shortcuts.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '→ ',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Careless risks (if any)
        if (carelessRisks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'CARELESS MISTAKE RISKS',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...carelessRisks.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠ ',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        Expanded(
                          child: Text(
                            r,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Close',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeBar({
    required String label,
    required int seconds,
    required Color color,
    bool isReference = false,
  }) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    final timeLabel = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

    // Max bar width based on 10 minutes
    const maxSecs = 600.0;
    final frac = (seconds / maxSecs).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isReference ? Colors.cyanAccent : color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              timeLabel,
              style: TextStyle(
                color: isReference ? Colors.cyanAccent : color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (ctx, constraints) {
            return Stack(
              children: [
                Container(
                  height: 8,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: constraints.maxWidth * frac,
                  decoration: BoxDecoration(
                    color: isReference ? Colors.cyanAccent : color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
          const SizedBox(height: 12),
          Text(
            _rawError ?? 'Unknown error',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
