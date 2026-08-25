// weekly_briefing_page.dart — Full-screen Weekly Intelligence Briefing viewer

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_intelligence_engine.dart';
import 'package:study_organizer/core/widgets/glass.dart';

class WeeklyBriefingPage extends StatefulWidget {
  const WeeklyBriefingPage({super.key});
  @override State<WeeklyBriefingPage> createState() => _WeeklyBriefingPageState();
}

class _WeeklyBriefingPageState extends State<WeeklyBriefingPage> {
  String?     _briefing;
  bool        _loading   = false;
  bool        _generating = false;
  bool        _speaking  = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _setupTTS();
    _loadSaved();
  }

  @override
  void dispose() { _tts.stop(); super.dispose(); }

  Future<void> _setupTTS() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
  }

  Future<void> _loadSaved() async {
    setState(() => _loading = true);
    final saved = await NovaIntelligenceEngine.loadLatestBriefing();
    if (mounted) setState(() { _briefing = saved; _loading = false; });
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final state = context.read<AppBloc>().state;
    final text  = await NovaIntelligenceEngine.generateWeeklyBriefing(
      subjects:  state.subjects,
      tasks:     state.tasks,
      timetable: state.timetable,
      absences:  state.absences,
      marks:     state.marks,
      topics:    state.topics,
    );
    if (mounted) setState(() { _briefing = text.isEmpty ? null : text; _generating = false; });
  }

  Future<void> _toggleSpeak() async {
    if (_briefing == null) return;
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
    } else {
      setState(() => _speaking = true);
      // Condensed TTS: first 2000 chars only to keep it ~60 sec
      final condensed = _briefing!.length > 2000 ? _briefing!.substring(0, 2000) : _briefing!;
      await _tts.speak(condensed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12122A),
        title: const Row(children: [
          Icon(Icons.radar_rounded, color: Color(0xFF39FF14), size: 20),
          SizedBox(width: 8),
          Text('Weekly Intel Briefing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          if (_briefing != null)
            IconButton(
              icon: Icon(_speaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
                  color: const Color(0xFF39FF14)),
              tooltip: _speaking ? 'Stop' : 'Read Aloud',
              onPressed: _toggleSpeak,
            ),
          IconButton(
            icon: _generating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39FF14)))
                : const Icon(Icons.refresh_rounded, color: Colors.white54),
            tooltip: 'Regenerate',
            onPressed: _generating ? null : _generate,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
          : _briefing == null
          ? _emptyState()
          : _briefingContent(),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.radar_rounded, color: Color(0xFF39FF14), size: 64),
      const SizedBox(height: 16),
      const Text('No briefing yet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Generated every Friday at 9 PM.\nOr tap generate now.',
          style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF39FF14).withOpacity(0.15),
          foregroundColor: const Color(0xFF39FF14),
          side: const BorderSide(color: Color(0xFF39FF14)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        icon: _generating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39FF14)))
            : const Icon(Icons.bolt_rounded),
        label: Text(_generating ? 'Generating...' : 'Generate Now'),
        onPressed: _generating ? null : _generate,
      ),
    ]),
  );

  Widget _briefingContent() {
    final text = _briefing!;
    // Parse sections: ALL-CAPS header + colon
    final lines = text.split('\n');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.35)),
            boxShadow: [BoxShadow(color: const Color(0xFF39FF14).withOpacity(0.06), blurRadius: 20)],
          ),
          child: Row(children: [
            const Icon(Icons.radar_rounded, color: Color(0xFF39FF14), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NOVA  INTELLIGENCE  BRIEFING', style: TextStyle(
                color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.w900,
                letterSpacing: 2, fontFamily: 'Courier',
              )),
              Text('Generated ${_briefingDate()}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ])),
            if (_speaking)
              const Icon(Icons.graphic_eq_rounded, color: Color(0xFF39FF14), size: 20),
          ]),
        ),
        // Briefing text — parse sections for visual hierarchy
        ..._parseSections(lines),
      ],
    );
  }

  List<Widget> _parseSections(List<String> lines) {
    final widgets = <Widget>[];
    final sectionContent = StringBuffer();
    String? currentSection;

    void flushSection() {
      if (sectionContent.isEmpty && currentSection == null) return;
      final body = sectionContent.toString().trim();
      if (currentSection != null) {
        widgets.add(_sectionCard(currentSection!, body));
      } else if (body.isNotEmpty) {
        widgets.add(_textBlock(body));
      }
      sectionContent.clear();
      currentSection = null;
    }

    for (final line in lines) {
      // Detect ALL-CAPS section header: "THREAT ASSESSMENT:" etc.
      final isHeader = RegExp(r'^[A-Z][A-Z\s\+\&]{3,}:').hasMatch(line.trim());
      if (isHeader) {
        flushSection();
        currentSection = line.trim();
      } else {
        if (sectionContent.isNotEmpty) sectionContent.write('\n');
        sectionContent.write(line);
      }
    }
    flushSection();
    return widgets;
  }

  Widget _sectionCard(String header, String body) {
    Color headerColor = const Color(0xFF9D97FF);
    if (header.contains('THREAT'))    headerColor = Colors.redAccent;
    if (header.contains('A+') || header.contains('PROBABILITY')) headerColor = const Color(0xFF2ED573);
    if (header.contains('ONE THING')) headerColor = Colors.orangeAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headerColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(header, style: TextStyle(color: headerColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
      ]),
    );
  }

  Widget _textBlock(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5)),
  );

  String _briefingDate() {
    final n = DateTime.now();
    return '${n.day}/${n.month}/${n.year}';
  }
}
