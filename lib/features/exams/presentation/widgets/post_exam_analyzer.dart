// post_exam_analyzer.dart — NOVA Post-Exam Review Wizard
//
// User uploads an exam image/PDF → NOVA vision extracts each question →
// NOVA asks "What did you do for Q1?" (via voice + UI) → user answers →
// NOVA generates a smart avoidance strategy → saved as SubjectNote(category: exam_mistake)
//
// Exam mistakes automatically feed into ALL NOVA plans (weekly, night-before, general chat).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/subjects/data/models/subject_note.dart';
import 'package:study_organizer/features/ai_assistant/data/services/jarvis_brain_service.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_eleven_labs_service.dart';

// ── Extracted exam question ───────────────────────────────────────────────────
class _ExamQuestion {
  final int number;
  final String text;
  final double? maxMarks;
  const _ExamQuestion({required this.number, required this.text, this.maxMarks});
}

// ── Per-question review state ─────────────────────────────────────────────────
class _ReviewEntry {
  final _ExamQuestion question;
  String whatIDid;
  String novaStrategy;
  _ReviewEntry({required this.question}) : whatIDid = '', novaStrategy = '';
}

// ─────────────────────────────────────────────────────────────────────────────
// Static entry point
// ─────────────────────────────────────────────────────────────────────────────
class PostExamAnalyzer {
  static Future<void> show(BuildContext context, Subject subject) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => BlocProvider.value(
        value: context.read<AppBloc>(),
        child: _PostExamAnalyzerSheet(subject: subject),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main sheet
// ─────────────────────────────────────────────────────────────────────────────
class _PostExamAnalyzerSheet extends StatefulWidget {
  final Subject subject;
  const _PostExamAnalyzerSheet({required this.subject});
  @override
  State<_PostExamAnalyzerSheet> createState() => _PostExamAnalyzerSheetState();
}

class _PostExamAnalyzerSheetState extends State<_PostExamAnalyzerSheet> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Upload
  String _examName = '';
  String? _fileUri;
  String? _fileMime;
  String _uploadStatus = '';
  bool _uploading = false;

  // Analyze
  List<_ReviewEntry> _entries = [];
  String _analyzeError = '';

  // Review Q&A
  int _qIdx = 0;
  final _answerCtrl = TextEditingController();
  bool _generating = false;

  // Summary edit controllers  (entry index → controller)
  final Map<int, TextEditingController> _editCtrls = {};

  Color get _color => Color(widget.subject.color);

  // ── Navigation ────────────────────────────────────────────────────────────
  void _go(int page) {
    setState(() => _page = page);
    _pageCtrl.animateToPage(page, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  // ── Step 0: Upload ────────────────────────────────────────────────────────
  Future<void> _pickAndUpload() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final file = r.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'webp'
        ? 'image/webp'
        : ext == 'png'
        ? 'image/png'
        : 'image/jpeg';

    if (mounted) setState(() { _uploading = true; _uploadStatus = 'Uploading to NOVA vision…'; _examName = file.name; });

    final result = await JarvisBrainService.uploadFileToGemini(
      bytes: bytes,
      mimeType: mime,
      displayName: file.name,
      onStatus: (s) { if (mounted) setState(() => _uploadStatus = s); },
    );

    if (!mounted) return;
    if (result == null) {
      setState(() { _uploading = false; _uploadStatus = '✗ Upload failed. Check API key.'; });
      return;
    }

    setState(() {
      _uploading = false;
      _fileUri = result['uri'];
      _fileMime = result['mimeType'];
      _uploadStatus = '✓ Uploaded! Analyzing…';
    });

    await Future.delayed(const Duration(milliseconds: 400));
    _startAnalysis();
  }

  // ── Step 1: Analyze ───────────────────────────────────────────────────────
  Future<void> _startAnalysis() async {
    _go(1);
    setState(() => _analyzeError = '');

    try {
      final apiKey = await JarvisBrainService.getApiKey();
      if (apiKey == null) {
        setState(() => _analyzeError = 'No Gemini API key. Set it in NOVA settings.');
        return;
      }

      final result = await _extractQuestions();
      if (!mounted) return;

      final questions = result['questions'] as List<_ExamQuestion>;
      final error = result['error'] as String?;

      if (questions.isEmpty) {
        setState(() => _analyzeError = error ?? 'NOVA could not extract questions. Try a clearer photo.');
        return;
      }

      setState(() {
        _entries = questions.map((q) => _ReviewEntry(question: q)).toList();
        _qIdx = 0;
      });

      NovaElevenLabsService.speak(
        'Exam loaded. I found ${questions.length} question${questions.length > 1 ? "s" : ""}. '
        'Let\'s go through each one. Question one: ${questions.first.text.length > 80 ? questions.first.text.substring(0, 80) : questions.first.text}. What did you do?',
      );
      _go(2);
    } catch (e) {
      if (mounted) setState(() => _analyzeError = 'Error: $e');
    }
  }

  /// Attempts extraction with [modelId]. Returns parsed questions or error info.
  Future<Map<String, dynamic>> _tryExtract({
    required String apiKey,
    required String modelId,
  }) async {
    const prompt = '''Extract ALL exam questions from the attached image/document.
The exam may be written in Arabic, English, or any other language — extract ALL text exactly as written.
Return ONLY a valid JSON array. No markdown, no explanation, no preamble.
Format: [{"number": 1, "text": "Full question text", "maxMarks": 10}, ...]
- number: question number (integer)
- text: complete question text exactly as written in the exam
- maxMarks: marks if visible, else null
Include sub-questions as separate entries (e.g. 1a=1, 1b=2).
If you cannot read the image clearly, still try to extract what you can see.''';

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=$apiKey';
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{
          'parts': [
            {'file_data': {'mime_type': _fileMime, 'file_uri': _fileUri}},
            {'text': prompt},
          ],
        }],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 8192, 'responseMimeType': 'application/json'},
      }),
    ).timeout(const Duration(seconds: 120));

    if (res.statusCode != 200) {
      final snippet = res.body.length > 300 ? res.body.substring(0, 300) : res.body;
      debugPrint('[PostExam] Gemini API error ($modelId) ${res.statusCode}: $snippet');
      return {'questions': <_ExamQuestion>[], 'error': 'API error ${res.statusCode} with model $modelId. Check API key or try again.'};
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      debugPrint('[PostExam] No candidates in response from $modelId');
      return {'questions': <_ExamQuestion>[], 'error': 'Gemini returned no response. The image may be too large or unreadable.'};
    }

    final parts = (candidates[0]['content']?['parts']) as List?;
    if (parts == null || parts.isEmpty) {
      debugPrint('[PostExam] No parts in response from $modelId');
      return {'questions': <_ExamQuestion>[], 'error': 'Gemini returned an empty response.'};
    }

    final raw = (parts[0]['text'] as String?)?.trim() ?? '';
    debugPrint('[PostExam] Raw response from $modelId (${raw.length} chars): ${raw.length > 500 ? raw.substring(0, 500) : raw}');

    if (raw.isEmpty) {
      return {'questions': <_ExamQuestion>[], 'error': 'Gemini returned empty text. Try a clearer photo.'};
    }

    // Clean markdown code fences
    final cleaned = raw
        .replaceAll(RegExp(r'^```(?:json)?\s*\n?', multiLine: true), '')
        .replaceAll(RegExp(r'\n?\s*```\s*$', multiLine: true), '')
        .trim();
    final si = cleaned.indexOf('[');
    final ei = cleaned.lastIndexOf(']');
    if (si < 0 || ei <= si) {
      debugPrint('[PostExam] Could not find JSON array in response from $modelId');
      return {'questions': <_ExamQuestion>[], 'error': 'Could not parse extracted questions. Raw output logged for debugging.'};
    }

    try {
      final list = jsonDecode(cleaned.substring(si, ei + 1)) as List;
      final questions = list.map((e) {
        final m = e as Map<String, dynamic>;
        final numRaw = m['number'];
        final qNum = numRaw is int ? numRaw : int.tryParse(numRaw.toString()) ?? 0;
        final marksRaw = m['maxMarks'];
        final marks = marksRaw != null ? (marksRaw is num ? marksRaw.toDouble() : double.tryParse(marksRaw.toString())) : null;
        return _ExamQuestion(number: qNum, text: m['text']?.toString() ?? '', maxMarks: marks);
      }).where((q) => q.text.isNotEmpty).toList();
      return {'questions': questions, 'error': null};
    } catch (e) {
      debugPrint('[PostExam] JSON parse error from $modelId: $e');
      return {'questions': <_ExamQuestion>[], 'error': 'Failed to parse question data. Try uploading again.'};
    }
  }

  Future<Map<String, dynamic>> _extractQuestions() async {
    final allKeys = await JarvisBrainService.getAllApiKeys();
    final validKeys = allKeys.where((k) => k.isNotEmpty).toList();
    
    if (validKeys.isEmpty) {
      return {'questions': <_ExamQuestion>[], 'error': 'No Gemini API keys found. Please add them in Settings.'};
    }

    // Models ordered by "smartness" / tier, then fallback robustness
    const modelsToTry = [
      'gemini-3.1-pro-preview', // Smartest
      'gemini-3.0-pro',
      'gemini-3.0-flash',
      'gemini-2.5-pro',
      'gemini-2.5-flash-preview-05-20', // Known fallback
      'gemini-2.5-flash',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
    ];

    String? lastError;

    // Iterate through all configured API keys
    for (int i = 0; i < validKeys.length; i++) {
        final apiKey = validKeys[i];
        final keyPreview = apiKey.length > 4 ? apiKey.substring(apiKey.length - 4) : '...';
        
        // Inside each key, try the sequence of models
        for (final modelId in modelsToTry) {
           debugPrint('[PostExam] Trying key *$keyPreview with model $modelId...');
           
           try {
              final result = await _tryExtract(apiKey: apiKey, modelId: modelId);
              final questions = result['questions'] as List<_ExamQuestion>;
              
              if (questions.isNotEmpty) {
                 debugPrint('[PostExam] Success with model $modelId using key *$keyPreview');
                 return result; // Successfully parsed questions
              }
              
              lastError = result['error'] as String?;
              debugPrint('[PostExam] Failed: $lastError');
              
              // If it's a 404 Not Found (deprecated model), just continue to next model
              if (lastError != null && lastError.contains('404')) {
                 continue;
              }
           } catch (e) {
              lastError = 'Connection error: $e';
              debugPrint('[PostExam] Exception with $modelId: $e');
              // Connection errors might affect the whole key, but let's just try the next model/key
           }
        }
    }

    return {
      'questions': <_ExamQuestion>[], 
      'error': lastError ?? 'Failed to extract questions after trying all API keys and available models.'
    };
  }

  // ── Step 2: Q&A ───────────────────────────────────────────────────────────
  Future<void> _submitAnswer() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) return;

    setState(() { _entries[_qIdx].whatIDid = answer; _generating = true; });
    _answerCtrl.clear();

    final strategy = await _genStrategy(_entries[_qIdx].question, answer);
    if (!mounted) return;

    setState(() { _entries[_qIdx].novaStrategy = strategy; _generating = false; });

    // Short voice feedback (first sentence only to stay brief)
    final brief = strategy.split('.').first;
    NovaElevenLabsService.speak(brief + '.');

    if (_qIdx < _entries.length - 1) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _qIdx++);
      final nextQ = _entries[_qIdx].question;
      NovaElevenLabsService.speak('Question ${nextQ.number}: ${nextQ.text.length > 80 ? nextQ.text.substring(0, 80) : nextQ.text}. What did you do here?');
    } else {
      await _saveAll();
      _go(3);
      NovaElevenLabsService.speak('Review complete. I\'ve saved all your mistakes. Every future plan I make will account for them.');
    }
  }

  void _skip() {
    setState(() { _entries[_qIdx].whatIDid = '(Skipped)'; });
    if (_qIdx < _entries.length - 1) {
      setState(() => _qIdx++);
    } else {
      _saveAll().then((_) => _go(3));
    }
  }

  Future<String> _genStrategy(_ExamQuestion q, String whatDid) async {
    final prompt = '''You are NOVA. A student answered a university exam question in "${widget.subject.name}".

Question: "${q.text}"
What the student did: "$whatDid"

In 2-3 sentences maximum, diagnose what likely went wrong and give ONE specific, actionable strategy to avoid this mistake next time. Be direct and smart.
Return ONLY the strategy text. No preamble. No markdown.''';

    final result = await JarvisBrainService.generateRaw(prompt: prompt, maxTokens: 250, temperature: 0.2);
    return result?.trim() ?? 'Review this question type and practice similar problems before the next exam.';
  }

  Future<void> _saveAll() async {
    final bloc = context.read<AppBloc>();
    final now = DateTime.now();
    final examLabel = _examName.isNotEmpty ? _examName : 'Exam ${DateFormat('MMM d').format(now)}';

    for (final entry in _entries) {
      if (entry.whatIDid.isEmpty || entry.whatIDid == '(Skipped)') continue;

      final content = '**Exam:** $examLabel\n'
          '**Question ${entry.question.number}:** ${entry.question.text}\n\n'
          '**What I did:** ${entry.whatIDid}\n\n'
          '**NOVA Strategy to avoid this:** ${entry.novaStrategy.isNotEmpty ? entry.novaStrategy : "Review this question type."}';

      bloc.add(AddSubjectNote(SubjectNote(
        subjectId: widget.subject.id!,
        category: 'exam_mistake',
        title: '$examLabel — Q${entry.question.number}',
        content: content,
        createdAt: now,
        updatedAt: now,
      )));
    }
  }

  Future<void> _saveEdit(int idx) async {
    final entry = _entries[idx];
    final ctrl = _editCtrls[idx];
    if (ctrl == null) return;

    final bloc = context.read<AppBloc>();
    final examLabel = _examName.isNotEmpty ? _examName : 'Exam';
    final noteTitle = '$examLabel — Q${entry.question.number}';

    final existing = bloc.state.subjectNotes
        .where((n) => n.subjectId == widget.subject.id && n.category == 'exam_mistake' && n.title == noteTitle)
        .toList();

    if (existing.isNotEmpty) {
      bloc.add(UpdateSubjectNote(existing.first.copyWith(content: ctrl.text, updatedAt: DateTime.now())));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated ✅'), backgroundColor: Color(0xFF2ED573), duration: Duration(seconds: 2)),
      );
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _pageCtrl.dispose();
    _answerCtrl.dispose();
    for (final c in _editCtrls.values) c.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [_uploadPage(), _analyzingPage(), _reviewPage(), _summaryPage()],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header() {
    const titles = ['📝 Upload Exam', '🔍 Analyzing…', '💬 Review Session', '✅ Saved'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_color.withOpacity(0.7), _color]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titles[_page],
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(widget.subject.name, style: TextStyle(color: _color, fontSize: 12)),
                  ],
                ),
              ),
              if (_page == 2 && _entries.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('${_qIdx + 1}/${_entries.length}',
                    style: TextStyle(color: _color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () { NovaElevenLabsService.stop(); Navigator.pop(context); },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i <= _page ? _color : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Page 0: Upload ────────────────────────────────────────────────────────
  Widget _uploadPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.1), shape: BoxShape.circle,
              border: Border.all(color: _color.withOpacity(0.3), width: 2),
            ),
            child: Icon(Icons.upload_file_rounded, size: 52, color: _color),
          ),
          const SizedBox(height: 24),
          const Text('Upload Your Exam',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'NOVA will scan every question and guide you through a personalized review session. Your mistakes are saved and used in all future plans.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 28),
          if (_uploadStatus.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_uploading) SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: _color, strokeWidth: 2)),
                  if (_uploading) const SizedBox(width: 10),
                  Flexible(child: Text(_uploadStatus,
                    style: TextStyle(
                      color: _uploadStatus.startsWith('✓') ? const Color(0xFF2ED573) : Colors.white70,
                      fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Pick Exam Photo / PDF', style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: _color.withOpacity(0.35),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('Supports JPG · PNG · WEBP · PDF',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
        ],
      ),
    );
  }

  // ── Page 1: Analyzing ─────────────────────────────────────────────────────
  Widget _analyzingPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _analyzeError.isNotEmpty
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 56),
                const SizedBox(height: 16),
                Text(_analyzeError, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 20),
                TextButton(onPressed: () => _go(0),
                  child: const Text('← Try Again', style: TextStyle(color: Colors.white54))),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 72, height: 72,
                  child: CircularProgressIndicator(color: _color, strokeWidth: 3)),
                const SizedBox(height: 28),
                const Text('NOVA is reading your exam…',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Vision AI is extracting every question',
                  style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
              ]),
      ),
    );
  }

  // ── Page 2: Q&A ───────────────────────────────────────────────────────────
  Widget _reviewPage() {
    if (_entries.isEmpty) return const SizedBox.shrink();
    final entry = _entries[_qIdx];
    final q = entry.question;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _color.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Q${q.number}${q.maxMarks != null ? "  (${q.maxMarks!.toStringAsFixed(0)} marks)" : ""}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(q.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // NOVA question bubble
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(color: _color.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(Icons.psychology_rounded, color: _color, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _color.withOpacity(0.08),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    'What did you do for this question, Yousif? Tell me your approach — even if you\'re not sure.',
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Generating indicator
          if (_generating)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: _color, strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('NOVA is analyzing your approach…',
                  style: TextStyle(color: _color, fontSize: 13)),
              ]),
            ),

          // NOVA strategy result
          if (entry.novaStrategy.isNotEmpty && !_generating) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1E0D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.lightbulb_rounded, color: Color(0xFF2ED573), size: 15),
                    const SizedBox(width: 6),
                    Text('NOVA Strategy', style: TextStyle(color: Colors.green.shade300, fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  Text(entry.novaStrategy, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.45)),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Answer input (only if not yet answered)
          if (entry.whatIDid.isEmpty) ...[
            TextField(
              controller: _answerCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Describe your approach, what you wrote or calculated…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.045),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _color),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _generating ? null : _submitAnswer,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Submit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _color, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      disabledBackgroundColor: _color.withOpacity(0.35),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _generating ? null : _skip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ] else ...[
            // Already answered
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: Text('✓ ${entry.whatIDid}',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            if (_qIdx < _entries.length - 1)
              ElevatedButton.icon(
                onPressed: () => setState(() => _qIdx++),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Next Question'),
                style: ElevatedButton.styleFrom(backgroundColor: _color, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              )
            else
              ElevatedButton.icon(
                onPressed: () async { await _saveAll(); _go(3); },
                icon: const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text('Finish Review'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ED573), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
          ],
        ],
      ),
    );
  }

  // ── Page 3: Summary ───────────────────────────────────────────────────────
  Widget _summaryPage() {
    final saved = _entries.where((e) => e.whatIDid.isNotEmpty && e.whatIDid != '(Skipped)').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_color.withOpacity(0.12), Colors.transparent], begin: Alignment.topLeft,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _color.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF2ED573), size: 20),
              SizedBox(width: 8),
              Text('Review Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 8),
            Text(
              '${saved.length} mistake${saved.length != 1 ? "s" : ""} saved to your ${widget.subject.name} Notes (category: Exam Mistake). '
              'NOVA will factor these into every future study plan and night-before briefing.',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.45),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        ...saved.asMap().entries.map((e) {
          final idx = _entries.indexOf(e.value);
          final entry = e.value;
          final ctrl = _editCtrls.putIfAbsent(idx, () => TextEditingController(text: entry.content));
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              iconColor: _color,
              collapsedIconColor: Colors.white38,
              title: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _color.withOpacity(0.18), borderRadius: BorderRadius.circular(6)),
                  child: Text('Q${entry.question.number}',
                    style: TextStyle(color: _color, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.question.text.length > 55 ? '${entry.question.text.substring(0, 55)}…' : entry.question.text,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Edit note content:',
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true, fillColor: Colors.white.withOpacity(0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: () => _saveEdit(idx),
                    icon: const Icon(Icons.save_rounded, size: 13),
                    label: const Text('Save Edit', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: _color),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      context.read<AppBloc>().state.subjectNotes
                          .where((n) => n.subjectId == widget.subject.id && n.category == 'exam_mistake' && n.title.contains('Q${entry.question.number}'))
                          .forEach((n) => context.read<AppBloc>().add(DeleteSubjectNote(n.id!)));
                      setState(() => _entries.remove(entry));
                    },
                    icon: const Icon(Icons.delete_rounded, size: 13, color: Colors.redAccent),
                    label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ),
                ]),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.done_all_rounded, size: 16),
          label: const Text('Done — Back to Subject'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _color, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

// ── Helper extension on _ReviewEntry ─────────────────────────────────────────
extension on _ReviewEntry {
  String get content => '**What I did:** $whatIDid\n\n**NOVA Strategy:** $novaStrategy';
}
