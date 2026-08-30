import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/timetable/data/models/timetable.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/features/topics/data/models/topic.dart';
import 'package:study_organizer/features/notes/data/models/subject_note.dart';
import 'package:study_organizer/features/documents/data/models/study_document.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';
import 'package:study_organizer/features/documents/data/services/document_search_indexer.dart';
import 'package:study_organizer/features/speech_engine/data/services/audio_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ACTION TYPES
// ─────────────────────────────────────────────────────────────────────────────
enum JarvisActionType {
  navigatePage,
  navigateTab,
  addTask,
  updateTask,
  deleteTask,
  completeTask,
  addAbsence,
  deleteAbsence,
  queryAbsences,
  addNote,
  deleteNote,
  queryNotes,
  addSubject,
  deleteSubject,
  addTimetable,
  deleteTimetable,
  addMark,
  addReminder,
  pomodoroStart,
  pomodoroStop,
  pomodoroReset,
  pomodoroMode,
  querySchedule,
  needsMoreInfo,
  multipleActions,
  brainChat,
  unknown,
}

class JarvisAction {
  final JarvisActionType type;
  final String spokenResponse;
  final dynamic payload;
  final String transcription;
  final String? followUpQuestion;

  const JarvisAction({
    required this.type,
    required this.spokenResponse,
    required this.payload,
    required this.transcription,
    this.followUpQuestion,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const String _prefGroqKey = 'groq_api_key';
const String _kGroqKeyFallback =
    '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';

class JarvisService {
  // ── API key ───────────────────────────────────────────────────────────────
  static Future<String?> _getGroqKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefGroqKey);
    return (saved != null && saved.isNotEmpty) ? saved : _kGroqKeyFallback;
  }

  static Future<void> setGroqKey(String key) async =>
      (await SharedPreferences.getInstance()).setString(
        _prefGroqKey,
        key.trim(),
      );

  // ── Recording state ───────────────────────────────────────────────────────
  static AudioRecorder? _recorder;
  static String? _recPath;
  static bool _isStreaming = false;
  static bool _isRecording = false;
  static bool useEnglish = true;

  // Silence detection config — tuned for speed
  static const int _pollMs = 150; // faster polling
  static const double _silenceDbLevel = -32.0; // slightly less sensitive
  static const int _minRecordMs = 600; // don't cut off too early
  static const int _maxRecordMs = 15000; // safety cutoff at 15s
  static Timer? _pollTimer;
  static int _silenceMs = 0;
  static DateTime? _streamStart;

  static final StreamController<String> _transcriptStreamCtrl =
      StreamController<String>.broadcast();
  static Stream<String> get transcriptStream => _transcriptStreamCtrl.stream;
  static bool get isListeningLive => _isStreaming;
  static bool get isRecording => _isRecording;

  // ── Multi-turn state ──────────────────────────────────────────────────────
  static String? _pendingAction;
  static Map<String, dynamic> _pendingPayload = {};
  static bool get hasPendingAction => _pendingAction != null;
  static void clearPending() {
    _pendingAction = null;
    _pendingPayload = {};
  }

  static String _jarvisName = 'NOVA';
  static void setJarvisName(String name) =>
      _jarvisName = name.trim().isEmpty ? 'NOVA' : name.trim();

  // ── Permission ────────────────────────────────────────────────────────────
  static Future<bool> _hasPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAP-TO-TALK: tap = start, silence auto-submits, tap again = force stop
  // ─────────────────────────────────────────────────────────────────────────
  static Future<bool> startListeningStream({
    required void Function(String text, bool isFinal) onResult,
    required void Function(String finalText) onDone,
    int silenceSeconds = 1,
  }) async {
    if (_isStreaming || _isRecording) return false;
    if (!await _hasPermission()) return false;

    _recorder?.dispose();
    _recorder = AudioRecorder();

    final dir = await getTemporaryDirectory();
    _recPath =
        '${dir.path}/nova_live_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _silenceMs = 0;
    _streamStart = DateTime.now();

    try {
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 32000, // lower bitrate = smaller file = faster upload
        ),
        path: _recPath!,
      );
    } catch (e) {
      debugPrint('[NOVA] Record start error: $e');
      return false;
    }

    _isStreaming = true;
    NovaAudioService.playAsset('sounds/nova_on.mp3');
    onResult('🎤 Listening…', false);
    _transcriptStreamCtrl.add('🎤 Listening…');

    _pollTimer = Timer.periodic(const Duration(milliseconds: _pollMs), (
      t,
    ) async {
      if (!_isStreaming) {
        t.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_streamStart!).inMilliseconds;

      // Hard cutoff at 15 seconds
      if (elapsed >= _maxRecordMs) {
        t.cancel();
        await stopListeningStream(onDone: onDone);
        return;
      }

      try {
        final amp = await _recorder?.getAmplitude();
        final db = amp?.current ?? _silenceDbLevel;

        if (elapsed < _minRecordMs) {
          // Don't detect silence in first 600ms — avoid cutting off immediately
          onResult('🎤 Listening…', false);
          return;
        }

        if (db < _silenceDbLevel) {
          _silenceMs += _pollMs;
          if (_silenceMs >= silenceSeconds * 1000) {
            t.cancel();
            await stopListeningStream(onDone: onDone);
          }
        } else {
          _silenceMs = 0;
        }
      } catch (_) {}
    });

    return true;
  }

  static Future<void> stopListeningStream({
    void Function(String)? onDone,
  }) async {
    if (!_isStreaming) return;
    _pollTimer?.cancel();
    _isStreaming = false;

    try {
      await _recorder?.stop();
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (e) {
      debugPrint('[NOVA] Stop error: $e');
    }

    if (_recPath == null) {
      onDone?.call('');
      return;
    }

    final file = File(_recPath!);
    final len = await file.length().catchError((_) => 0);
    if (len < 1200) {
      onDone?.call('');
      return;
    }

    //  NovaAudioService.playAsset('sounds/right_away_sir.mp3');
    final text = await _transcribe(file);
    _transcriptStreamCtrl.add(text);
    onDone?.call(text);
  }

  static Future<String> stopListeningStreamImmediate() async {
    _pollTimer?.cancel();
    _isStreaming = false;
    try {
      await _recorder?.stop();
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (_) {}
    if (_recPath == null) return '';
    final file = File(_recPath!);
    final len = await file.length().catchError((_) => 0);
    if (len < 1200) return '';
    NovaAudioService.playAsset('sounds/right_away_sir.mp3');
    return _transcribe(file);
  }

  // ── Legacy hold-to-talk ───────────────────────────────────────────────────
  static Future<bool> startRecording() async {
    if (!await _hasPermission()) return false;
    _recorder?.dispose();
    _recorder = AudioRecorder();
    final dir = await getTemporaryDirectory();
    _recPath = '${dir.path}/nova_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 32000,
      ),
      path: _recPath!,
    );
    await Future.delayed(const Duration(milliseconds: 400));
    NovaAudioService.playAsset('sounds/nova_on.mp3');
    return _isRecording = true;
  }

  static Future<JarvisAction?> stopAndProcess({
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<Map<String, dynamic>> absences,
    required List<MarkModel> marks,
    required List<TimetableEntry> timetable,
    required List<StudyTopic> topics,
    required List<SubjectNote> notes,
    required List<JarvisDocument> documents,
    String? brainContext,
    List<Map<String, String>>? brainHistory,
    String personalityMode = 'normal',
  }) async {
    if (!_isRecording) return null;
    _isRecording = false;
    await _recorder?.stop();
    await Future.delayed(const Duration(milliseconds: 200));
    final file = File(_recPath ?? '');
    if (!await file.exists() || await file.length() < 1200) {
      return _fallback(
        useEnglish ? 'Speak louder — audio was too short.' : 'تكلم بصوت أعلى.',
      );
    }
    NovaAudioService.playAsset('sounds/right_away_sir.mp3');
    final text = await _transcribe(file);
    if (text.isEmpty) {
      return _fallback(
        useEnglish
            ? 'Could not understand. Try again.'
            : 'لم أفهم. حاول مرة أخرى.',
      );
    }
    return processText(
      text,
      subjects: subjects,
      tasks: tasks,
      absences: absences,
      marks: marks,
      timetable: timetable,
      topics: topics,
      notes: notes,
      documents: documents,
      brainContext: brainContext,
      brainHistory: brainHistory,
      personalityMode: personalityMode,
    );
  }

  // ── Whisper STT ───────────────────────────────────────────────────────────
  static Future<String> _transcribe(File file) async {
    try {
      final key = await _getGroqKey();
      if (key == null || key.isEmpty) return '';

      final req = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
      );
      req.headers['Authorization'] = 'Bearer $key';
      req.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: 'audio.m4a',
        ),
      );
      req.fields['model'] = 'whisper-large-v3-turbo';
      req.fields['language'] = useEnglish ? 'en' : 'ar';
      req.fields['response_format'] = 'json';
      // temperature=0 = more accurate, faster
      req.fields['temperature'] = '0';

      final response = await req.send().timeout(const Duration(seconds: 10));
      final res = await http.Response.fromStream(response);

      if (res.statusCode == 200) {
        final text = jsonDecode(res.body)['text']?.toString().trim() ?? '';
        return _filterHallucinations(text);
      }
      debugPrint('[NOVA] Whisper error ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('[NOVA] Transcription error: $e');
    }
    return '';
  }

  /// Filter known Whisper hallucinations on silence/noise
  static String _filterHallucinations(String text) {
    if (text.isEmpty) return '';
    final lower = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
    const hallucinations = {
      'thank you',
      'thanks',
      'thank you so much',
      'thank you for watching',
      'thanks for watching',
      'bye',
      'you',
      'amen',
      'amine',
      'subscribe',
      'like and subscribe',
      'please subscribe',
    };
    if (hallucinations.contains(lower)) {
      debugPrint('[NOVA] Filtered hallucination: "$text"');
      return '';
    }
    return text;
  }

  // ── Process transcribed text through AI ──────────────────────────────────
  static Future<JarvisAction> processText(
    String text, {
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<Map<String, dynamic>> absences,
    required List<MarkModel> marks,
    required List<TimetableEntry> timetable,
    required List<StudyTopic> topics,
    required List<SubjectNote> notes,
    required List<JarvisDocument> documents,
    String? brainContext,
    List<Map<String, String>>? brainHistory,
    String personalityMode = 'normal',
  }) async {
    // 1. Multi-turn pending action takes priority
    if (_pendingAction != null) {
      return _resolvePending(text, subjects, brainContext, brainHistory);
    }

    // 2. Instant local keyword check (zero latency, no API cost)
    final activation = _checkActivationKeyword(
      text,
      timetable,
      subjects,
      tasks,
    );
    if (activation != null) return activation;

    // 3. AI processing — single unified call
    return _processWithAI(
      text,
      subjects,
      tasks,
      absences,
      marks,
      timetable,
      topics,
      notes,
      documents,
      brainContext: brainContext,
      brainHistory: brainHistory,
      personalityMode: personalityMode,
    );
  }

  // ── Instant keyword responses (no AI needed) ──────────────────────────────
  static JarvisAction? _checkActivationKeyword(
    String text,
    List<TimetableEntry> timetable,
    List<Subject> subjects,
    List<TaskModel> tasks,
  ) {
    final t = text.toLowerCase().replaceAll(RegExp(r"[^\w\s']"), '').trim();
    String? reply;

    if (_kw(t, ['are you up', 'up for me', 'you up for'])) {
      reply = "Always up for you, sir.";
    } else if (_kw(t, ['are you there', 'you there'])) {
      reply = "Always here, sir.";
    } else if (_kw(t, [
      'wake up nova',
      'nova wake',
      'hello nova',
      'hey nova',
      'hi nova',
    ])) {
      reply = "Online and ready, sir. What do you need?";
    } else if (_kw(t, ['you online', 'are you online', 'you active'])) {
      reply = "Online and fully operational, sir.";
    } else if (_kw(t, ['nova status', 'status report', 'give me a status'])) {
      final now = DateTime.now();
      final pending = tasks.where((t) => !t.isCompleted && !t.isFailed).length;
      final today = timetable.where((e) => e.dayOfWeek == now.weekday).length;
      reply =
          "Status: $today classes today, $pending pending tasks. All systems nominal, sir.";
    } else if (_kw(t, [
      'what do i have next',
      'whats next',
      "what's next",
      'next class',
      'next up',
    ])) {
      final now = DateTime.now();
      final nowMin = now.hour * 60 + now.minute;
      final todayEntries =
          timetable.where((e) => e.dayOfWeek == now.weekday).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

      TimetableEntry? next;
      for (final e in todayEntries) {
        final parts = e.startTime.split(':');
        if (parts.length < 2) continue;
        final eMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        if (eMin > nowMin) {
          next = e;
          break;
        }
      }

      if (next == null) {
        reply = "No more classes today, sir. The day is yours.";
      } else {
        final sub =
            subjects
                .where((s) => s.id == next!.subjectId)
                .map((s) => s.name)
                .firstOrNull ??
            'class';
        reply =
            "Next up: $sub at ${next.startTime}, ${next.type} in ${next.room}.";
      }
    }

    if (reply == null) return null;
    return JarvisAction(
      type: JarvisActionType.brainChat,
      spokenResponse: reply,
      payload: const {},
      transcription: text,
    );
  }

  static bool _kw(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  // ── AI processing — single call, fast model ───────────────────────────────
  static Future<JarvisAction> _processWithAI(
    String text,
    List<Subject> subjects,
    List<TaskModel> tasks,
    List<Map<String, dynamic>> absences,
    List<MarkModel> marks,
    List<TimetableEntry> timetable,
    List<StudyTopic> topics,
    List<SubjectNote> notes,
    List<JarvisDocument> documents, {
    String? brainContext,
    List<Map<String, String>>? brainHistory,
    String personalityMode = 'normal',
  }) async {
    try {
      // Find subject related to query or context
      int? targetSubjectId;
      for (final s in subjects) {
        if (s.id != null &&
            (text.toLowerCase().contains(s.name.toLowerCase()) ||
                (brainContext != null && brainContext.contains(s.name)))) {
          targetSubjectId = s.id;
          break;
        }
      }
      if (targetSubjectId == null && subjects.isNotEmpty) {
        targetSubjectId = subjects.first.id;
      }

      List<DocumentChunkResult> relevantDocChunks = [];
      if (targetSubjectId != null) {
        relevantDocChunks = await DocumentSearchIndexer.searchRelevantChunks(
          subjectId: targetSubjectId,
          query: text,
          limit: 3,
        );
      }

      final prompt = _buildUnifiedPrompt(
        DateTime.now(),
        subjects,
        tasks,
        absences,
        marks,
        timetable,
        topics,
        notes,
        documents,
        text,
        relevantDocChunks: relevantDocChunks,
        brainContext: brainContext,
        brainHistory: brainHistory,
        personalityMode: personalityMode,
      );

      // Use fast model (flash) for action parsing — lower latency
      final result = await JarvisBrainService.generateFast(
        prompt: prompt,
        maxTokens: 512, // actions don't need long responses
        temperature: 0.0, // deterministic for JSON
      );

      if (result != null && result.isNotEmpty) {
        return _parseResponse(
          result,
          text,
          subjects,
          brainContext,
          brainHistory,
          personalityMode,
        );
      }
    } catch (e) {
      debugPrint('[NOVA] AI error: $e');
    }

    // Fallback: direct brain chat if AI action parsing fails
    if (brainContext != null) {
      final reply = await JarvisBrainService.chat(
        context: brainContext,
        history: brainHistory ?? [],
        userMessage: text,
        personalityMode: personalityMode,
      );
      return JarvisAction(
        type: JarvisActionType.brainChat,
        spokenResponse: reply,
        payload: {},
        transcription: text,
      );
    }
    return _fallback(useEnglish ? 'Something went wrong.' : 'حدث خطأ.');
  }

  // ── Multi-turn resolver ───────────────────────────────────────────────────
  static Future<JarvisAction> _resolvePending(
    String userReply,
    List<Subject> subjects,
    String? brainContext,
    List<Map<String, String>>? brainHistory,
  ) async {
    final action = _pendingAction!;
    if (action == 'add_note_subject') {
      _pendingPayload['subject'] = userReply;
      _pendingAction = 'add_note_content';
      const q = 'What should the note say, sir?';
      return JarvisAction(
        type: JarvisActionType.needsMoreInfo,
        spokenResponse: q,
        followUpQuestion: q,
        payload: Map.from(_pendingPayload),
        transcription: userReply,
      );
    }
    if (action == 'add_note_content') {
      _pendingPayload['content'] = userReply;
      final p = Map<String, dynamic>.from(_pendingPayload);
      clearPending();
      final subName = p['subject']?.toString() ?? '';
      final sub = subjects.firstWhere(
        (s) => s.name.toLowerCase().contains(subName.toLowerCase()),
        orElse: () =>
            subjects.isNotEmpty ? subjects.first : Subject(name: subName),
      );
      return JarvisAction(
        type: JarvisActionType.addNote,
        spokenResponse: useEnglish
            ? 'Note added to ${sub.name}, sir.'
            : 'تمت الإضافة.',
        payload: {
          'subject': sub.name,
          'title': p['title'] ?? 'Voice Note',
          'content': p['content'],
        },
        transcription: userReply,
      );
    }
    if (action == 'add_absence_subject') {
      _pendingPayload['subject'] = userReply;
      _pendingAction = 'add_absence_type';
      const q = 'What type, sir? Lecture, section, or lab?';
      return JarvisAction(
        type: JarvisActionType.needsMoreInfo,
        spokenResponse: q,
        followUpQuestion: q,
        payload: Map.from(_pendingPayload),
        transcription: userReply,
      );
    }
    if (action == 'add_absence_type') {
      final type = _mapAbsenceType(userReply);
      _pendingPayload['type'] = type;
      final p = Map<String, dynamic>.from(_pendingPayload);
      clearPending();
      return JarvisAction(
        type: JarvisActionType.addAbsence,
        spokenResponse: useEnglish
            ? 'Absence recorded for ${p['subject']}, sir.'
            : 'تم التسجيل.',
        payload: p,
        transcription: userReply,
      );
    }
    clearPending();
    return _fallback(useEnglish ? 'Got it.' : 'حسناً.');
  }

  static String _mapAbsenceType(String r) {
    final l = r.toLowerCase();
    if (l.contains('lab') || l.contains('عملي')) return 'lab';
    if (l.contains('section') || l.contains('سكشن')) return 'section';
    return 'lecture';
  }

  // ── Unified AI Prompt (action classification + brain chat in one) ──────────
  static String _buildUnifiedPrompt(
    DateTime now,
    List<Subject> subjects,
    List<TaskModel> tasks,
    List<Map<String, dynamic>> absences,
    List<MarkModel> marks,
    List<TimetableEntry> timetable,
    List<StudyTopic> topics,
    List<SubjectNote> notes,
    List<JarvisDocument> documents,
    String userText, {
    List<DocumentChunkResult>? relevantDocChunks,
    String? brainContext,
    List<Map<String, String>>? brainHistory,
    String personalityMode = 'normal',
  }) {
    final lang = useEnglish ? 'English' : 'Arabic';
    final fmt = intl.DateFormat('yyyy-MM-dd');
    final dayFmt = intl.DateFormat('EEEE, MMM d');

    final absBuf = StringBuffer();
    for (final s in subjects) {
      final sa = absences.where((a) => a['subjectId'] == s.id).toList();
      final lc = sa.where((a) => a['type'] == 'lecture').length;
      final sc = sa.where((a) => a['type'] == 'section').length;
      final lb = sa.where((a) => a['type'] == 'lab').length;
      absBuf.write(
        '${s.name}: ${lc}L ${sc}S ${lb}Lab (max ${s.maxLectureAbs}L/${s.maxSectionAbs}S/${s.maxLabAbs}Lab); ',
      );
    }

    final upTasks =
        tasks.where((t) => !t.isCompleted && !t.isFailed && t.dueDate != null).toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    final yesterdayTime = now.subtract(const Duration(days: 1));
    final yesterdayClasses =
        timetable.where((e) => e.dayOfWeek == yesterdayTime.weekday).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final todayClasses =
        timetable.where((e) => e.dayOfWeek == now.weekday).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final recentAbsBuf = StringBuffer();
    for (final a in absences) {
      final date = a['date']?.toString() ?? '';
      if (date == fmt.format(now) || date == fmt.format(yesterdayTime)) {
        final sub = subjects
            .firstWhere(
              (s) =>
                  s.id ==
                  (a['subjectId'] is int
                      ? a['subjectId']
                      : int.tryParse(a['subjectId'].toString())),
              orElse: () => Subject(name: '?'),
            )
            .name;
        recentAbsBuf.write('$sub (${a['type']} on $date); ');
      }
    }

    final activeTopics = topics
        .where((t) => !t.isMastered)
        .take(5)
        .map((t) {
          final sn = subjects
              .firstWhere(
                (s) => s.id == t.subjectId,
                orElse: () => Subject(name: '?'),
              )
              .name;
          return '[$sn] ${t.title}';
        })
        .join('; ');

    final marksSummary = marks
        .take(6)
        .map((m) {
          final sn = subjects
              .firstWhere(
                (s) => s.id == m.subjectId,
                orElse: () => Subject(name: '?'),
              )
              .name;
          return '$sn ${m.category}/${m.label}: ${m.obtained}/${m.total}';
        })
        .join('; ');

    // Build conversation history summary (last 3 turns)
    final histBuf = StringBuffer();
    if (brainHistory != null && brainHistory.isNotEmpty) {
      final recent = brainHistory.length > 6
          ? brainHistory.sublist(brainHistory.length - 6)
          : brainHistory;
      for (final m in recent) {
        histBuf.writeln(
          '${m['role'] == 'user' ? 'User' : 'NOVA'}: ${m['content']}',
        );
      }
    }

    final personalityNote = personalityMode == 'sarcastic'
        ? 'Be SARCASTIC and SAVAGE. Roast the user for slacking but still answer.'
        : 'Be concise, smart, slightly witty like Iron Man\'s NOVA.';

    return '''You are $_jarvisName, an AI assistant for a university student.
Respond ONLY in $lang. Return ONLY valid JSON with NO markdown wrapping.

$personalityNote

TODAY: ${dayFmt.format(now)} (Yesterday was ${dayFmt.format(yesterdayTime)})
SUBJECTS: ${subjects.map((s) => s.name).join(', ')}
ABSENCES: $absBuf
RECENT ABSENCES (48h): ${recentAbsBuf.isEmpty ? 'None' : recentAbsBuf.toString()}
PENDING TASKS & EXAMS: ${upTasks.isEmpty ? 'None' : upTasks.take(8).map((t) => '${t.title} due ${fmt.format(t.dueDate!)} [${t.type}]').join(', ')}
ACTIVE TOPICS: ${activeTopics.isEmpty ? 'None' : activeTopics}
TODAY SCHEDULE: ${todayClasses.isEmpty ? 'None' : todayClasses.map((e) {
            final sn = subjects.firstWhere((s) => s.id == e.subjectId, orElse: () => Subject(name: '?')).name;
            return '${e.startTime}-${e.endTime} $sn ${e.type}';
          }).join(', ')}
YESTERDAY SCHEDULE: ${yesterdayClasses.isEmpty ? 'None' : yesterdayClasses.map((e) {
            final sn = subjects.firstWhere((s) => s.id == e.subjectId, orElse: () => Subject(name: '?')).name;
            return '${e.startTime}-${e.endTime} $sn ${e.type}';
          }).join(', ')}
MARKS: $marksSummary
${(relevantDocChunks != null && relevantDocChunks.isNotEmpty) ? '\nRELEVANT EXAM & COURSE MATERIAL EXCERPTS (FTS5 Search Index):\n${relevantDocChunks.map((c) => '• [${c.docName} - ${c.sectionTitle}]: ${c.content}').join('\n')}\n' : ''}
${histBuf.isNotEmpty ? 'CONVERSATION HISTORY:\n$histBuf' : ''}
USER: "$userText"

RULES:
- ONLY use navigate_page if user says "open", "go to", or "show me the page".
- For questions ("what is...", "do I have..."), use brain_chat and ANSWER DIRECTLY.
- If asked for a "collision analysis" regarding an absence, use brain_chat to thoroughly analyze what lectures/topics they missed based on the schedule, cross-reference with pending tasks/exams, and explain the consequences and suggest a recovery plan. Format responses beautifully.
- ALWAYS congratulate user if they mention completing something.
- Return the "spoken" field with a direct answer — never leave it empty for brain_chat.
- Keep spoken responses short (1-3 sentences max) EXCEPT for collision analysis which should be detailed.

ACTIONS: navigate_page, add_task, complete_task, delete_task, add_absence, delete_absence,
query_absences, add_note, delete_note, add_subject, delete_subject, add_mark, add_reminder,
pomodoro_start, pomodoro_stop, pomodoro_reset, pomodoro_mode, needs_more_info, brain_chat

PAGES: home=0, tasks=1, exams=2, calendar=3, subjects=4, marks=5, campus=6

JSON FORMAT:
{"action":"<action>","spoken":"<response>","payload":{}}

EXAMPLES:
{"action":"navigate_page","spoken":"Opening tasks, sir.","payload":{"page":"tasks"}}
{"action":"add_absence","spoken":"Recorded.","payload":{"subject":"Digital Systems","type":"lecture","date":"${fmt.format(now)}"}}
{"action":"brain_chat","spoken":"You have 3 pending tasks: Assignment 1 due tomorrow, Quiz prep due Friday, and Lab report due next week.","payload":{}}
{"action":"pomodoro_start","spoken":"Starting focus timer, sir.","payload":{"mode":"focus"}}

Return ONLY valid JSON. No explanation. No markdown.''';
  }

  // ── Response parser ───────────────────────────────────────────────────────
  static JarvisAction _parseResponse(
    String content,
    String transcription,
    List<Subject> subjects,
    String? brainContext,
    List<Map<String, String>>? brainHistory,
    String personalityMode,
  ) {
    try {
      var c = content.trim();
      // Strip markdown code fences
      c = c
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .replaceAll(RegExp(r'\s*```$', multiLine: true), '')
          .trim();

      // Extract first JSON object
      final s = c.indexOf('{'), e = c.lastIndexOf('}');
      if (s >= 0 && e > s) c = c.substring(s, e + 1);

      // Heal truncated JSON
      if (!c.endsWith('}')) {
        final opens = c.split('{').length - 1;
        final closes = c.split('}').length - 1;
        if (opens > closes) c += '}' * (opens - closes);
      }

      final parsed = jsonDecode(c) as Map<String, dynamic>;
      final action = parsed['action']?.toString().toLowerCase() ?? 'brain_chat';
      final spoken = parsed['spoken']?.toString() ?? '';
      final payload = parsed['payload'] ?? {};

      switch (action) {
        case 'navigate_page':
          return JarvisAction(
            type: JarvisActionType.navigatePage,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'navigate_tab':
          return JarvisAction(
            type: JarvisActionType.navigateTab,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'add_task':
          return JarvisAction(
            type: JarvisActionType.addTask,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'update_task':
          return JarvisAction(
            type: JarvisActionType.updateTask,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'delete_task':
          return JarvisAction(
            type: JarvisActionType.deleteTask,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'complete_task':
          return JarvisAction(
            type: JarvisActionType.completeTask,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'add_absence':
          return JarvisAction(
            type: JarvisActionType.addAbsence,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'delete_absence':
          return JarvisAction(
            type: JarvisActionType.deleteAbsence,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'query_absences':
          return JarvisAction(
            type: JarvisActionType.queryAbsences,
            spokenResponse: spoken,
            payload: {},
            transcription: transcription,
          );
        case 'add_note':
          return JarvisAction(
            type: JarvisActionType.addNote,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'delete_note':
          return JarvisAction(
            type: JarvisActionType.deleteNote,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'query_notes':
          return JarvisAction(
            type: JarvisActionType.queryNotes,
            spokenResponse: spoken,
            payload: {},
            transcription: transcription,
          );
        case 'add_subject':
          return JarvisAction(
            type: JarvisActionType.addSubject,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'delete_subject':
          return JarvisAction(
            type: JarvisActionType.deleteSubject,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'add_mark':
          return JarvisAction(
            type: JarvisActionType.addMark,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'add_reminder':
          return JarvisAction(
            type: JarvisActionType.addReminder,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'pomodoro_start':
          return JarvisAction(
            type: JarvisActionType.pomodoroStart,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'pomodoro_stop':
          return JarvisAction(
            type: JarvisActionType.pomodoroStop,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'pomodoro_reset':
          return JarvisAction(
            type: JarvisActionType.pomodoroReset,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'pomodoro_mode':
          return JarvisAction(
            type: JarvisActionType.pomodoroMode,
            spokenResponse: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'needs_more_info':
          final intent = payload is Map ? payload['intent']?.toString() : null;
          if (intent == 'add_note') {
            _pendingAction = 'add_note_subject';
            _pendingPayload = {'title': 'Voice Note'};
          } else if (intent == 'add_absence') {
            _pendingAction = 'add_absence_subject';
            _pendingPayload = {
              'date': intl.DateFormat('yyyy-MM-dd').format(DateTime.now()),
            };
          } else {
            _pendingAction = intent ?? 'unknown';
            _pendingPayload = {};
          }
          return JarvisAction(
            type: JarvisActionType.needsMoreInfo,
            spokenResponse: spoken,
            followUpQuestion: spoken,
            payload: payload,
            transcription: transcription,
          );
        case 'brain_chat':
        default:
          return JarvisAction(
            type: JarvisActionType.brainChat,
            spokenResponse: spoken,
            payload: {},
            transcription: transcription,
          );
      }
    } catch (e) {
      debugPrint('[NOVA] Parse error: $e\nContent: $content');
      return _fallback(
        useEnglish ? 'Could not understand. Rephrase please.' : 'لم أفهم.',
      );
    }
  }

  static void resetConversation() => clearPending();
  static void toggleLanguage() {
    useEnglish = !useEnglish;
    clearPending();
  }

  static JarvisAction _fallback(String m) => JarvisAction(
    type: JarvisActionType.unknown,
    spokenResponse: m,
    payload: {},
    transcription: '',
  );
}
