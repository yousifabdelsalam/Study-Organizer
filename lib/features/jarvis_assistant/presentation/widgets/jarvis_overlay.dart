import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:study_organizer/features/speech_engine/data/services/eleven_labs_service.dart';
import 'package:study_organizer/features/speech_engine/data/services/vad_service.dart';
import 'package:study_organizer/features/speech_engine/data/services/audio_service.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';

import 'package:study_organizer/features/jarvis_assistant/data/services/jarvis_service.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';
import 'package:study_organizer/features/jarvis_assistant/data/services/jarvis_navigator.dart';

import 'package:study_organizer/core/database/database_helper.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/notes/data/models/subject_note.dart';
import 'package:study_organizer/features/reminders/data/models/reminder.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/features/quizzes/presentation/pages/quiz_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a chat room
// ─────────────────────────────────────────────────────────────────────────────
class JarvisChatRoom {
  final String id;
  String name;
  final List<Map<String, String>>
  messages; // [{role: user/jarvis, content: ...}]
  final DateTime createdAt;

  JarvisChatRoom({
    required this.id,
    required this.name,
    required this.messages,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'messages': messages,
    'createdAt': createdAt.toIso8601String(),
  };

  factory JarvisChatRoom.fromJson(Map<String, dynamic> j) => JarvisChatRoom(
    id: j['id'] ?? '',
    name: j['name'] ?? 'Chat',
    messages:
        (j['messages'] as List<dynamic>?)
            ?.map((e) => Map<String, String>.from(e as Map))
            .toList() ??
        [],
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat Room Manager (SQLite + SharedPreferences for active room)
// ─────────────────────────────────────────────────────────────────────────────
class ChatRoomManager {
  static const _activeKey = 'jarvis_active_room';
  static const _jarvisNameKey = 'jarvis_custom_name';

  // ── DB helpers ──────────────────────────────────────────────────────────────
  static Future<Database> get _db async {
    return DatabaseHelper.instance.database;
  }

  static Future<List<JarvisChatRoom>> load() async {
    try {
      final db = await _db;
      final rows = await db.query(
        'jarvis_chat_rooms',
        orderBy: 'createdAt ASC',
      );
      if (rows.isEmpty) return [];
      return rows.map((r) {
        try {
          final msgs = jsonDecode(r['messages'] as String) as List<dynamic>;
          return JarvisChatRoom(
            id: r['id'] as String,
            name: r['name'] as String,
            messages: msgs
                .map((e) => Map<String, String>.from(e as Map))
                .toList(),
            createdAt:
                DateTime.tryParse(r['createdAt'] as String? ?? '') ??
                DateTime.now(),
          );
        } catch (_) {
          return JarvisChatRoom(
            id: r['id'] as String,
            name: r['name'] as String,
            messages: [],
            createdAt: DateTime.now(),
          );
        }
      }).toList();
    } catch (e) {
      // Fallback to SharedPreferences if DB not ready yet
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('jarvis_chat_rooms');
        if (raw == null) return [];
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => JarvisChatRoom.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<void> save(List<JarvisChatRoom> rooms) async {
    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.delete('jarvis_chat_rooms');
        for (final room in rooms) {
          await txn.insert('jarvis_chat_rooms', {
            'id': room.id,
            'name': room.name,
            'messages': jsonEncode(room.messages),
            'createdAt': room.createdAt.toIso8601String(),
          });
        }
      });
    } catch (e) {
      // Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'jarvis_chat_rooms',
        jsonEncode(rooms.map((r) => r.toJson()).toList()),
      );
    }
  }

  static Future<void> saveRoom(JarvisChatRoom room) async {
    try {
      final db = await _db;
      await db.insert('jarvis_chat_rooms', {
        'id': room.id,
        'name': room.name,
        'messages': jsonEncode(room.messages),
        'createdAt': room.createdAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('saveRoom error: $e');
    }
  }

  static Future<String?> getActiveRoomId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  static Future<void> setActiveRoomId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
  }

  static Future<String> getJarvisName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_jarvisNameKey) ?? 'NOVA';
  }

  static Future<void> setJarvisName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jarvisNameKey,
      name.trim().isEmpty ? 'NOVA' : name.trim(),
    );
  }

  static JarvisChatRoom createNew({String? name}) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return JarvisChatRoom(
      id: id,
      name: name ?? 'Chat ${DateTime.now().day}/${DateTime.now().month}',
      messages: [],
      createdAt: DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main JarvisOverlay widget
// ─────────────────────────────────────────────────────────────────────────────
class JarvisOverlay extends StatefulWidget {
  final bool autoListen;
  const JarvisOverlay({super.key, this.autoListen = false});
  static void show(BuildContext context, {bool autoListen = false}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => BlocProvider.value(
          value: context.read<AppBloc>(),
          child: JarvisOverlay(autoListen: autoListen),
        ),
      ).whenComplete(() {
        //       NovaVadService.resumeAfterJarvis();
        // Stop ElevenLabs voice when overlay closes
        // NovaElevenLabsService.stop();
      });

  @override
  State<JarvisOverlay> createState() => _JarvisOverlayState();
}

class _JarvisOverlayState extends State<JarvisOverlay>
    with TickerProviderStateMixin {
  String _status = 'Tap to speak';
  //final FlutterTts _tts = FlutterTts();
  bool _isProcessing = false;
  bool _isLiveListening = false; // true when streaming STT is active
  String _liveTranscript = '';
  final TextEditingController _textController = TextEditingController();
  bool _loadingBrain = false;
  final ScrollController _scrollController = ScrollController();

  // Chat rooms
  List<JarvisChatRoom> _rooms = [];
  JarvisChatRoom? _activeRoom;
  bool _roomsLoaded = false;
  String _jarvisName = 'NOVA';
  bool _sarcasmMode = false;

  late AnimationController _pulseController;

  void initState() {
    super.initState();
    //  _setupTTS();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _loadRooms();
    _loadJarvisName();
    _loadSarcasmMode();
    // Auto-start listening if opened by wake word
    if (widget.autoListen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _onStart();
        });
      });
    }
  }

  Future<void> _loadSarcasmMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _sarcasmMode = prefs.getBool('jarvis_sarcasm_mode') ?? false,
      );
    }
  }

  Future<void> _toggleSarcasmMode() async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !_sarcasmMode;
    await prefs.setBool('jarvis_sarcasm_mode', newVal);
    if (mounted) setState(() => _sarcasmMode = newVal);
  }

  Future<void> _loadJarvisName() async {
    final name = await ChatRoomManager.getJarvisName();
    if (mounted) setState(() => _jarvisName = name);
  }

  Future<void> _loadRooms() async {
    final rooms = await ChatRoomManager.load();
    final activeId = await ChatRoomManager.getActiveRoomId();

    if (rooms.isEmpty) {
      final newRoom = ChatRoomManager.createNew(name: 'Main Chat');
      rooms.add(newRoom);
      await ChatRoomManager.save(rooms);
    }

    JarvisChatRoom active;
    if (activeId != null) {
      active = rooms.firstWhere(
        (r) => r.id == activeId,
        orElse: () => rooms.first,
      );
    } else {
      active = rooms.first;
    }

    if (mounted) {
      setState(() {
        _rooms = rooms;
        _activeRoom = active;
        _roomsLoaded = true;
      });
      _scrollToBottom();
    }
  }

  // void _setupTTS() async {
  //   await _tts.setLanguage(JarvisService.useEnglish ? 'en-US' : 'ar-EG');
  //   await _tts.setSpeechRate(0.52); // slightly faster = more natural
  //   await _tts.setPitch(0.65);
  //   await _tts.setVolume(1.0);
  //   // Don't wait for TTS to finish before allowing next action
  //   await _tts.awaitSpeakCompletion(false);
  // }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveRooms() async {
    if (_activeRoom != null) {
      await ChatRoomManager.saveRoom(_activeRoom!);
      await ChatRoomManager.setActiveRoomId(_activeRoom!.id);
    }
  }

  void _addMessageToActive(String role, String msgContent) {
    if (_activeRoom == null) return;
    _activeRoom!.messages.add({'role': role, 'content': msgContent});
    _saveRooms();
    setState(() {});
    _scrollToBottom();
  }

  String _buildBrainContext() {
    final state = context.read<AppBloc>().state;
    return JarvisBrainService.buildContext(
      subjects: state.subjects,
      tasks: state.tasks,
      topics: state.topics,
      subjectNotes: state.subjectNotes,
      jarvisDocuments: state.jarvisDocuments,
      subjectMetadata: state.subjectMetadata,
      timetable: state.timetable,
      marks: state.marks,
      absences: state.absences,
      currentWeekType: state.currentWeekType,
    );
  }

  List<Map<String, String>> _getBrainHistory() {
    if (_activeRoom == null) return [];
    // Convert to brain history format (last 10 messages max)
    final msgs = _activeRoom!.messages;
    final start = msgs.length > 10 ? msgs.length - 10 : 0;
    return msgs
        .sublist(start)
        .map(
          (m) => {
            'role': m['role'] == 'user' ? 'user' : 'assistant',
            'content': m['content'] ?? '',
          },
        )
        .toList();
  }

  // ── Voice input (record + Whisper, tap-to-talk) ────────────────────────────
  void _onStart() async {
    if (_isProcessing || _loadingBrain) return;

    // Stop TTS if speaking
    await NovaElevenLabsService.stop();

    if (_isLiveListening) {
      // Second tap = force stop and submit
      setState(() {
        _isLiveListening = false;
        _liveTranscript = '';
        _status = '⚡ Processing…';
      });
      final text = await JarvisService.stopListeningStreamImmediate();
      if (text.trim().isNotEmpty) {
        await _submitVoiceText(text);
      } else {
        if (mounted) setState(() => _status = 'Tap to speak');
      }
      return;
    }

    final started = await JarvisService.startListeningStream(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _liveTranscript = text;
          _status = text;
        });
      },
      onDone: (finalText) async {
        if (!mounted) return;
        setState(() {
          _isLiveListening = false;
          _liveTranscript = '';
          _status = '⚡ Processing…';
        });
        if (finalText.trim().isNotEmpty) {
          await _submitVoiceText(finalText);
        } else {
          if (mounted) setState(() => _status = 'Tap to speak');
        }
      },
    );

    if (started) {
      setState(() {
        _isLiveListening = true;
        _status = '🎤 Listening…';
      });
    } else {
      setState(() => _status = 'Microphone unavailable');
    }
  }

  // Keep legacy _onEnd for Whisper mode (hold-button still works)
  void _onEnd() async {
    if (!JarvisService.isRecording) return;
    setState(() {
      _isProcessing = true;
      _status = 'Processing...';
    });

    final state = context.read<AppBloc>().state;
    final action = await JarvisService.stopAndProcess(
      subjects: state.subjects,
      tasks: state.tasks,
      absences: state.absences,
      marks: state.marks,
      timetable: state.timetable,
      topics: state.topics,
      notes: state.subjectNotes,
      documents: state.jarvisDocuments,
      brainContext: _buildBrainContext(),
      brainHistory: _getBrainHistory(),
      personalityMode: _sarcasmMode ? 'sarcastic' : 'normal',
    );

    if (action != null) await _handleAction(action);
    setState(() {
      _isProcessing = false;
      _status = 'Tap to speak';
    });
  }

  /// Submit a voice/text string through the full JARVIS pipeline.
  Future<void> _submitVoiceText(String text) async {
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _status = '⚡ Processing…';
    });

    // 🔊 Play a processing sound cue
    final textLower = text.toLowerCase();
    if (textLower.contains('schedule') ||
        textLower.contains('class') ||
        textLower.contains('timetable')) {
      NovaAudioService.playAsset('sounds/checking_the_schedule.mp3');
    } else if (textLower.contains('record') ||
        textLower.contains('absence') ||
        textLower.contains('mark') ||
        textLower.contains('grade')) {
      NovaAudioService.playAsset(
        'sounds/one_moment_accessing_your_records.mp3',
      );
    } else if (textLower.contains('document') ||
        textLower.contains('file') ||
        textLower.contains('pdf') ||
        textLower.contains('analyze')) {
      NovaAudioService.playAsset('sounds/initating_document_analysis.mp3');
    } else if (textLower.contains('exam') ||
        textLower.contains('quiz') ||
        textLower.contains('test')) {
      NovaAudioService.playAsset('sounds/initiating_exam_analysis.mp3');
    } else {}

    final state = context.read<AppBloc>().state;
    final action = await JarvisService.processText(
      text,
      subjects: state.subjects,
      tasks: state.tasks,
      absences: state.absences,
      marks: state.marks,
      timetable: state.timetable,
      topics: state.topics,
      notes: state.subjectNotes,
      documents: state.jarvisDocuments,
      brainContext: _buildBrainContext(),
      brainHistory: _getBrainHistory(),
      personalityMode: _sarcasmMode ? 'sarcastic' : 'normal',
    );

    await _handleAction(action);

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = 'Tap to speak';
      });
    }
  }

  /// Common handler after any JarvisAction is received.
  Future<void> _handleAction(JarvisAction action) async {
    _addMessageToActive(
      'user',
      action.transcription.isNotEmpty ? action.transcription : '🎤 Voice',
    );

    if (action.spokenResponse.isNotEmpty) {
      _addMessageToActive('nova', action.spokenResponse);
    }

    // Speak using ElevenLabs (or Flutter TTS fallback) — non-blocking
    if (action.spokenResponse.isNotEmpty) {
      final clean = JarvisBrainService.stripMarkdownForTts(
        action.spokenResponse,
      );
      NovaElevenLabsService.speak(clean); // fire-and-forget
    }

    await _executeAction(action);

    if (action.type == JarvisActionType.needsMoreInfo) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      _onStart();
    }
  }

  // ── Text send ───────────────────────────────────────────────────────────────
  Future<void> _sendToBrain(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loadingBrain || _activeRoom == null) return;

    await NovaElevenLabsService.stop();

    _addMessageToActive('user', trimmed);
    setState(() => _loadingBrain = true);
    _textController.clear();
    _scrollToBottom();

    final contextString = _buildBrainContext();
    final reply = await JarvisBrainService.chat(
      context: contextString,
      history: _getBrainHistory(),
      userMessage: trimmed,
      personalityMode: _sarcasmMode ? 'sarcastic' : 'normal',
      attachedDocs: context.read<AppBloc>().state.jarvisDocuments,
    );

    if (mounted) {
      _addMessageToActive('nova', reply);
      setState(() => _loadingBrain = false);
      _scrollToBottom();
      final cleanForTts = JarvisBrainService.stripMarkdownForTts(reply);
      NovaElevenLabsService.speak(cleanForTts); // fire-and-forget
    }
  }

  // ── Quick chips ──────────────────────────────────────────────────────────────
  Future<void> _onQuickRecommend() async {
    if (_activeRoom == null) return;
    _addMessageToActive(
      'user',
      'Recommend what I should study today or tomorrow with specific times',
    );
    setState(() => _loadingBrain = true);

    final context = _buildBrainContext();
    final recs = await JarvisBrainService.getStudyRecommendations(
      context: context,
    );

    if (mounted) {
      String reply;
      if (recs.isEmpty) {
        reply =
            'I could not generate recommendations. Make sure you have subjects, tasks, and timetable set up.';
      } else {
        final sb = StringBuffer('Here are your study recommendations:\n\n');
        for (var i = 0; i < recs.length; i++) {
          final r = recs[i];
          sb.writeln('${i + 1}. ${r['subject']} — ${r['topic']}');
          sb.writeln(
            '   Time: ${r['suggestedTime']}${r['durationMinutes'] != null ? ' (${r['durationMinutes']} min)' : ''}',
          );
          sb.writeln('   Reason: ${r['reason']}');
          if (i < recs.length - 1) sb.writeln();
        }
        reply = sb.toString().trim();
      }
      _addMessageToActive('nova', reply);
      setState(() => _loadingBrain = false);
      final cleanForTts = JarvisBrainService.stripMarkdownForTts(reply);
      NovaElevenLabsService.speak(cleanForTts);
    }
  }

  Future<void> _onQuickFocus() async {
    final subjects = context.read<AppBloc>().state.subjects;
    if (subjects.isEmpty) {
      await _sendToBrain('What should I focus on for my exams in general?');
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Which subject?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...subjects.map(
              (s) => ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(s.color),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  s.name,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, s.name),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.all_inclusive_rounded,
                color: Colors.white70,
                size: 20,
              ),
              title: const Text(
                'All subjects',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () => Navigator.pop(ctx, ''),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      if (chosen.isEmpty) {
        await _sendToBrain(
          'What are the examiner intentions and what should I focus on across all my subjects? Include topic weight estimates.',
        );
      } else {
        await _sendToBrain(
          'For $chosen, what are the examiner intentions, what should I focus on, and what percentage of the exam each topic might be? Use my past exams and documents.',
        );
      }
    }
  }

  Future<void> _onQuickTestMe() async {
    final state = context.read<AppBloc>().state;
    final subjects = state.subjects;
    if (subjects.isEmpty) return;

    final chosenSubject = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pick a subject to test you on:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...subjects.map(
              (s) => ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(s.color),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  s.name,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, s.name),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosenSubject == null || !mounted) return;

    _addMessageToActive('user', 'Test me on $chosenSubject');
    setState(() => _loadingBrain = true);

    final contextString = _buildBrainContext();
    final quiz = await JarvisBrainService.generateQuiz(
      context: contextString,
      subjectName: chosenSubject,
      topicName: null,
      numQuestions: 5,
    );
    if (mounted) setState(() => _loadingBrain = false);

    if (quiz != null && mounted) {
      _addMessageToActive(
        'jarvis',
        'Here is your quiz for $chosenSubject. Good luck!',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: context.read<AppBloc>(),
            child: JarvisQuizPage(quizData: quiz, subjectName: chosenSubject),
          ),
        ),
      );
    } else if (mounted) {
      _addMessageToActive(
        'jarvis',
        'Could not generate quiz. Add past exams or documents for $chosenSubject first, then try again.',
      );
    }
  }

  // ── Rooms management ────────────────────────────────────────────────────────
  void _openRoomsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12122A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Text(
                      'Chat Rooms',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFF6C63FF),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _createNewRoom();
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: _rooms.length,
                  itemBuilder: (ctx, i) {
                    final room = _rooms[i];
                    final isActive = room.id == _activeRoom?.id;
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF6C63FF).withOpacity(0.3)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.chat_bubble_rounded,
                          color: isActive
                              ? const Color(0xFF6C63FF)
                              : Colors.white54,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        room.name,
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF9D97FF)
                              : Colors.white,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${room.messages.length} messages',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Rename
                          IconButton(
                            icon: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white54,
                              size: 18,
                            ),
                            onPressed: () => _renameRoom(ctx, room, setS),
                          ),
                          // Delete (if more than 1)
                          if (_rooms.length > 1)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              onPressed: () async {
                                setS(() => _rooms.remove(room));
                                if (_activeRoom?.id == room.id) {
                                  setState(() => _activeRoom = _rooms.first);
                                }
                                await ChatRoomManager.save(_rooms);
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                      onTap: () {
                        setState(() => _activeRoom = room);
                        ChatRoomManager.setActiveRoomId(room.id);
                        Navigator.pop(ctx);
                        _scrollToBottom();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createNewRoom() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text(
          'New Chat Room',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Room name (e.g. Physics study)',
            hintStyle: TextStyle(color: Colors.white54),
          ),
          style: const TextStyle(color: Colors.white),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final newRoom = ChatRoomManager.createNew(name: name);
      setState(() {
        _rooms.add(newRoom);
        _activeRoom = newRoom;
      });
      await ChatRoomManager.save(_rooms);
      await ChatRoomManager.setActiveRoomId(newRoom.id);
    }
  }

  void _renameRoom(BuildContext ctx, JarvisChatRoom room, StateSetter setS) {
    final controller = TextEditingController(text: room.name);
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text('Rename Room', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New name'),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setS(() => room.name = newName);
                setState(() {});
                await ChatRoomManager.save(_rooms);
              }
              Navigator.pop(dCtx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Settings dialog (API keys + rename JARVIS + clear chat) ────────────────
  Future<void> _showApiKeyDialog() async {
    final existingKeys = await JarvisBrainService.getAllApiKeys();
    final keyCtrls = List.generate(
      6,
      (i) => TextEditingController(text: existingKeys[i]),
    );
    final nameCtrl = TextEditingController(text: _jarvisName);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F3A),
          title: const Text(
            'NOVA Settings',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rename JARVIS
                const Text(
                  'Assistant Name',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. NOVA, ALEX, FRIDAY...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(
                      Icons.smart_toy_rounded,
                      color: Color(0xFF6C63FF),
                      size: 20,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                // Gemini API Keys (up to 6)
                const Text(
                  'Gemini API Keys (up to 6)',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Keys rotate automatically. Get free keys at aistudio.google.com/apikey',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 8),
                ...List.generate(
                  6,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: keyCtrls[i],
                      decoration: InputDecoration(
                        hintText:
                            'Key ${i + 1}${i == 0 ? ' (primary)' : ' (optional)'}',
                        hintStyle: const TextStyle(color: Colors.white24),
                        prefixIcon: Icon(
                          Icons.key_rounded,
                          color: i == 0
                              ? const Color(0xFF4CAF50)
                              : Colors.white24,
                          size: 20,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      obscureText: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Clear specific chat room
                const Text(
                  'Clear Chat Room',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Select room to clear...',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                      dropdownColor: const Color(0xFF12122A),
                      value: null,
                      items: _rooms
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  r.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (roomId) async {
                        if (roomId == null) return;
                        final room = _rooms.firstWhere((r) => r.id == roomId);
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            backgroundColor: const Color(0xFF1A1F3A),
                            title: const Text(
                              'Clear Chat?',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: Text(
                              'Clear all messages in "${room.name}"?',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && mounted) {
                          room.messages.clear();
                          await ChatRoomManager.saveRoom(room);
                          setState(() {});
                          setS(() {});
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final keys = keyCtrls.map((c) => c.text).toList();
                await JarvisBrainService.setApiKeys(keys);
                final newName = nameCtrl.text.trim().isEmpty
                    ? 'NOVA'
                    : nameCtrl.text.trim();
                await ChatRoomManager.setJarvisName(newName);
                setState(() => _jarvisName = newName);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings saved.')),
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Execute voice actions ───────────────────────────────────────────────────
  Future<void> _executeAction(JarvisAction action) async {
    if (action.type == JarvisActionType.brainChat ||
        action.type == JarvisActionType.needsMoreInfo ||
        action.type == JarvisActionType.queryAbsences ||
        action.type == JarvisActionType.queryNotes)
      return;

    // 🔊 Query schedule — play checking sound
    if (action.type == JarvisActionType.querySchedule) {
      NovaAudioService.playAsset('sounds/checking_the_schedule.mp3');
      return;
    }

    try {
      final p = action.payload is Map<String, dynamic>
          ? action.payload as Map<String, dynamic>
          : <String, dynamic>{};
      switch (action.type) {
        // ── Navigation ──
        case JarvisActionType.navigatePage:
          JarvisNavigator.goToPage(p['page']?.toString() ?? '');
          if (mounted) Navigator.pop(context); // Auto-dismiss overlay
          break;
        case JarvisActionType.navigateTab:
          final tab = p['tab']?.toString().toLowerCase() ?? '';
          JarvisNavigator.goToCampusTab(tab == 'pomodoro' ? 1 : 0);
          if (mounted) Navigator.pop(context); // Auto-dismiss overlay
          break;

        // ── Tasks ──
        case JarvisActionType.addTask:
          _addTask(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;
        case JarvisActionType.updateTask:
          _updateTask(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;
        case JarvisActionType.deleteTask:
          _deleteTask(p);
          break;
        case JarvisActionType.completeTask:
          _completeTask(p);
          // task_done is played by app_bloc; overlay plays "that's one step closer"
          NovaAudioService.playAsset('sounds/that _is_one_step_closer.mp3');
          break;

        // ── Absences ──
        case JarvisActionType.addAbsence:
          _addAbsence(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;
        case JarvisActionType.deleteAbsence:
          _deleteAbsence(p);
          break;

        // ── Notes ──
        case JarvisActionType.addNote:
          _addNote(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;
        case JarvisActionType.deleteNote:
          _deleteNote(p);
          break;

        // ── Subjects ──
        case JarvisActionType.addSubject:
          _addSubject(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;
        case JarvisActionType.deleteSubject:
          _deleteSubject(p);
          break;

        // ── Marks ──
        case JarvisActionType.addMark:
          _addMark(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;

        // ── Reminders ──
        case JarvisActionType.addReminder:
          _addReminder(p);
          NovaAudioService.playAsset(
            'sounds/understood_compiling_the_data_now.mp3',
          );
          break;

        // ── Pomodoro ──
        case JarvisActionType.pomodoroStart:
          PomodoroCommands.start(p['mode']?.toString());
          NovaAudioService.playAsset(
            'sounds/focus_mode_engaged_block_out_all_distractions.mp3',
          );
          break;
        case JarvisActionType.pomodoroStop:
          PomodoroCommands.stop();
          NovaAudioService.playAsset('sounds/focus_session_complete.mp3');
          break;
        case JarvisActionType.pomodoroReset:
          PomodoroCommands.reset();
          break;
        case JarvisActionType.pomodoroMode:
          PomodoroCommands.switchMode(p['mode']?.toString());
          break;
          break;

        // ── Multiple ──
        case JarvisActionType.multipleActions:
          if (action.payload is List) {
            for (final item in action.payload) {
              if (item is Map<String, dynamic>)
                await _executeSingleAction(item);
            }
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('Execute action error: $e');
    }
  }

  Future<void> _executeSingleAction(Map<String, dynamic> actionData) async {
    final p = actionData['data'] as Map<String, dynamic>? ?? {};
    switch (actionData['action']?.toString().toLowerCase()) {
      case 'add_task':
        _addTask(p);
        break;
      case 'delete_task':
        _deleteTask(p);
        break;
      case 'complete_task':
        _completeTask(p);
        break;
      case 'add_subject':
        _addSubject(p);
        break;
      case 'delete_subject':
        _deleteSubject(p);
        break;
      case 'add_absence':
        _addAbsence(p);
        break;
      case 'add_note':
        _addNote(p);
        break;
    }
  }

  // ── Absence helpers ────────────────────────────────────────────────────────
  void _addAbsence(Map<String, dynamic> payload) {
    try {
      final subId = _findSubjectId(payload['subject']?.toString());
      if (subId == null) return;
      final date =
          payload['date']?.toString() ??
          DateTime.now().toIso8601String().substring(0, 10);
      final type = payload['type']?.toString() ?? 'lecture';
      context.read<AppBloc>().add(AddAbsence(subId, date, type));
    } catch (e) {
      debugPrint('addAbsence error: $e');
    }
  }

  void _deleteAbsence(Map<String, dynamic> payload) {
    try {
      final absences = context.read<AppBloc>().state.absences;
      final subId = _findSubjectId(payload['subject']?.toString());
      final date = payload['date']?.toString() ?? '';
      final type = payload['type']?.toString() ?? 'lecture';
      final match = absences.firstWhere(
        (a) =>
            a['subjectId'] == subId && a['date'] == date && a['type'] == type,
        orElse: () => {},
      );
      if (match['id'] != null) {
        context.read<AppBloc>().add(DeleteAbsence(match['id'] as int));
      }
    } catch (e) {
      debugPrint('deleteAbsence error: $e');
    }
  }

  // ── Note helpers ───────────────────────────────────────────────────────────
  void _addNote(Map<String, dynamic> payload) {
    try {
      final subId = _findSubjectId(payload['subject']?.toString());
      if (subId == null) return;
      final note = SubjectNote(
        subjectId: subId,
        category: payload['category']?.toString() ?? 'General',
        title: payload['title']?.toString() ?? 'Voice Note',
        content: payload['content']?.toString() ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      context.read<AppBloc>().add(AddSubjectNote(note));
    } catch (e) {
      debugPrint('addNote error: $e');
    }
  }

  void _deleteNote(Map<String, dynamic> payload) {
    try {
      final notes = context.read<AppBloc>().state.subjectNotes;
      final title = payload['title']?.toString().toLowerCase() ?? '';
      final note = notes.firstWhere(
        (n) => n.title.toLowerCase().contains(title),
        orElse: () => notes.first,
      );
      if (note.id != null)
        context.read<AppBloc>().add(DeleteSubjectNote(note.id!));
    } catch (e) {
      debugPrint('deleteNote error: $e');
    }
  }

  // ── Mark helper ────────────────────────────────────────────────────────────
  void _addMark(Map<String, dynamic> payload) {
    try {
      final subId = _findSubjectId(payload['subject']?.toString());
      if (subId == null) return;
      context.read<AppBloc>().add(
        AddMark(
          MarkModel(
            subjectId: subId,
            category: payload['category']?.toString() ?? 'quiz',
            label: payload['label']?.toString() ?? 'Voice',
            obtained: (payload['obtained'] as num?)?.toDouble() ?? 0,
            total: (payload['total'] as num?)?.toDouble() ?? 10,
          ),
        ),
      );
    } catch (e) {
      debugPrint('addMark error: $e');
    }
  }

  // ── Reminder helper ────────────────────────────────────────────────────────
  void _addReminder(Map<String, dynamic> payload) {
    try {
      final dateStr =
          payload['date']?.toString() ??
          DateTime.now().toIso8601String().substring(0, 10);
      final time = payload['time']?.toString() ?? '08:00';
      final text = payload['text']?.toString() ?? 'Reminder';
      context.read<AppBloc>().add(
        AddReminder(ReminderModel(text: text, date: dateStr, time: time)),
      );
    } catch (e) {
      debugPrint('addReminder error: $e');
    }
  }

  void _addTask(Map<String, dynamic> payload) {
    try {
      final task = TaskModel(
        title: payload['title'] ?? 'New Task',
        description: payload['description'] ?? '',
        subjectId: _findSubjectId(payload['subject']),
        dueDate: payload['dueDate'] != null
            ? DateTime.tryParse(payload['dueDate'])
            : null,
        priority: payload['priority'] ?? 2,
        type: payload['type'] ?? 'assignment',
      );
      context.read<AppBloc>().add(AddTask(task));
    } catch (e) {
      debugPrint('addTask error: $e');
    }
  }

  void _updateTask(Map<String, dynamic> payload) {
    try {
      final tasks = context.read<AppBloc>().state.tasks;
      final taskTitle = payload['title']?.toString().toLowerCase() ?? '';
      final task = tasks.firstWhere(
        (t) => t.title.toLowerCase().contains(taskTitle),
        orElse: () => tasks.first,
      );
      if (task.id != null) {
        final updates = <String, dynamic>{};
        if (payload['newTitle'] != null) updates['title'] = payload['newTitle'];
        if (payload['dueDate'] != null) updates['dueDate'] = payload['dueDate'];
        if (payload['priority'] != null)
          updates['priority'] = payload['priority'];
        context.read<AppBloc>().add(UpdateTask(task.id!, updates));
      }
    } catch (e) {
      debugPrint('updateTask error: $e');
    }
  }

  void _deleteTask(Map<String, dynamic> payload) {
    try {
      final tasks = context.read<AppBloc>().state.tasks;
      final taskTitle = payload['title']?.toString().toLowerCase() ?? '';
      final task = tasks.firstWhere(
        (t) => t.title.toLowerCase().contains(taskTitle),
        orElse: () => tasks.first,
      );
      if (task.id != null) context.read<AppBloc>().add(DeleteTask(task.id!));
    } catch (e) {
      debugPrint('deleteTask error: $e');
    }
  }

  void _completeTask(Map<String, dynamic> payload) {
    try {
      final tasks = context.read<AppBloc>().state.tasks;
      final taskTitle = payload['title']?.toString().toLowerCase() ?? '';
      final task = tasks.firstWhere(
        (t) => t.title.toLowerCase().contains(taskTitle),
        orElse: () => tasks.first,
      );
      if (task.id != null)
        context.read<AppBloc>().add(ToggleTask(task.id!, true));
    } catch (e) {
      debugPrint('completeTask error: $e');
    }
  }

  void _addSubject(Map<String, dynamic> payload) {
    try {
      int colorValue = 0xFF6C63FF;
      if (payload['color'] != null) {
        if (payload['color'] is String) {
          final colorStr = payload['color'].toString().replaceAll('#', '');
          colorValue = int.parse('FF$colorStr', radix: 16);
        } else if (payload['color'] is int) {
          colorValue = payload['color'];
        }
      }
      final subject = Subject(
        name: payload['name'] ?? 'New Subject',
        doctorName: payload['teacher'] ?? '',
        color: colorValue,
      );
      context.read<AppBloc>().add(AddSubject(subject));
    } catch (e) {
      debugPrint('addSubject error: $e');
    }
  }

  void _deleteSubject(Map<String, dynamic> payload) {
    try {
      final subjects = context.read<AppBloc>().state.subjects;
      final subjectName = payload['name']?.toString().toLowerCase() ?? '';
      final subject = subjects.firstWhere(
        (s) => s.name.toLowerCase().contains(subjectName),
        orElse: () => subjects.first,
      );
      if (subject.id != null)
        context.read<AppBloc>().add(DeleteSubject(subject.id!));
    } catch (e) {
      debugPrint('deleteSubject error: $e');
    }
  }

  int? _findSubjectId(String? subjectName) {
    if (subjectName == null || subjectName == 'null') return null;
    final subjects = context.read<AppBloc>().state.subjects;
    try {
      final subject = subjects.firstWhere(
        (s) => s.name.toLowerCase().contains(subjectName.toLowerCase()),
      );
      return subject.id;
    } catch (e) {
      return null;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_roomsLoaded) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E27),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      );
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF1A1F3A), Color(0xFF0A0E27)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildQuickChips(),
            Expanded(
              child: _activeRoom?.messages.isEmpty ?? true
                  ? _buildIdleState()
                  : _buildConversationList(),
            ),
            _buildInputRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8), // Adjusted padding
      child: Row(
        children: [
          // 1. Room selector button - Keep this compact
          GestureDetector(
            onTap: _openRoomsSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6C63FF).withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Color(0xFF9D97FF),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.2,
                    ), // Dynamic width
                    child: Text(
                      _activeRoom?.name ?? 'Chat',
                      style: const TextStyle(
                        color: Color(0xFF9D97FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xFF9D97FF),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 2. JARVIS title - WRAP IN EXPANDED TO PREVENT OVERFLOW
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4CAF50)],
                  ).createShader(bounds),
                  child: const Text(
                    'NOVA',
                    style: TextStyle(
                      fontSize: 18, // Reduced from 22 to fit better
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Brain · Gemini',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.4),
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 3. Action Buttons - Grouped together
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Language toggle
              GestureDetector(
                onTap: () {
                  JarvisService.toggleLanguage();
                  //    _setupTTS();
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: JarvisService.useEnglish
                          ? [const Color(0xFF4CAF50), const Color(0xFF45A049)]
                          : [const Color(0xFF6C63FF), const Color(0xFF5A52D5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    JarvisService.useEnglish ? 'EN' : 'AR',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
                icon: Icon(
                  _sarcasmMode
                      ? Icons.local_fire_department
                      : Icons.sentiment_satisfied_alt,
                  color: _sarcasmMode ? Colors.redAccent : Colors.white70,
                  size: 18,
                ),
                onPressed: _toggleSarcasmMode,
              ),
              IconButton(
                constraints: const BoxConstraints(), // Removes default padding
                padding: const EdgeInsets.all(8),
                icon: const Icon(
                  Icons.key_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                onPressed: _showApiKeyDialog,
              ),
              IconButton(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _chip('Study plan', Icons.schedule_rounded, _onQuickRecommend),
          const SizedBox(width: 8),
          _chip(
            'What to focus on?',
            Icons.lightbulb_outline_rounded,
            _onQuickFocus,
          ),
          const SizedBox(width: 8),
          _chip('Test me', Icons.quiz_rounded, _onQuickTestMe),
          const SizedBox(width: 8),
          _chip('New room', Icons.add_comment_rounded, _createNewRoom),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loadingBrain ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF9D97FF)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Container(
              width: 120 + (_pulseController.value * 20),
              height: 120 + (_pulseController.value * 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6C63FF).withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.mic_none_rounded,
                  size: 60,
                  color: const Color(0xFF6C63FF).withOpacity(0.8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Ready to help',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _activeRoom?.name ?? '',
            style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    final messages = _activeRoom?.messages ?? [];
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: messages.length + (_loadingBrain ? 1 : 0),
      itemBuilder: (context, index) {
        // Typing indicator
        if (index == messages.length) {
          return _buildTypingIndicator();
        }

        final msg = messages[index];
        final isUser = msg['role'] == 'user';
        return _buildMessageBubble(msg['content'] ?? '', isUser);
      },
    );
  }

  Widget _buildMessageBubble(String content, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: isUser ? 60 : 0,
          right: isUser ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF5A52D5)],
                )
              : null,
          color: isUser ? null : const Color(0xFF1E2139),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser
              ? null
              : Border.all(color: const Color(0xFF4CAF50).withOpacity(0.25)),
        ),
        child: MarkdownBody(
          data: content,
          selectable: true,
          builders: {
            'latex': LatexElementBuilder(
              textStyle: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF6C63FF),
              ),
            ),
          },
          extensionSet: md.ExtensionSet(
            [
              LatexBlockSyntax(),
              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            ],
            [
              LatexInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: isUser ? Colors.white : Colors.white.withOpacity(0.92),
              fontSize: 14,
              height: 1.5,
            ),
            listBullet: TextStyle(
              color: isUser ? Colors.white : Colors.white.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2139),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'NOVA is thinking...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E27).withOpacity(0.8),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !_loadingBrain,
              onSubmitted: (_) => _sendToBrain(_textController.text),
              decoration: InputDecoration(
                hintText: 'Ask NOVA anything...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: const Color(0xFF1E2139),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          _circleButton(
            onTap: _loadingBrain
                ? null
                : () => _sendToBrain(_textController.text),
            color: const Color(0xFF6C63FF),
            child: _loadingBrain
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 6),
          // Mic button
          GestureDetector(
            onTapDown: (_) => _onStart(),
            onTapUp: (_) => _onEnd(),
            onTapCancel: () => _onEnd(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: JarvisService.isRecording
                      ? [const Color(0xFFFF4757), const Color(0xFFFF6348)]
                      : [const Color(0xFF1E2139), const Color(0xFF2A2F52)],
                ),
                border: Border.all(
                  color: JarvisService.isRecording
                      ? Colors.red.withOpacity(0.5)
                      : Colors.white12,
                ),
                boxShadow: JarvisService.isRecording
                    ? [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                JarvisService.isRecording
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
                color: JarvisService.isRecording
                    ? Colors.white
                    : Colors.white54,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required VoidCallback? onTap,
    required Color color,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onTap == null ? color.withOpacity(0.4) : color,
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    NovaElevenLabsService.stop();
    JarvisService.resetConversation();
    _pulseController.dispose();
    super.dispose();
  }
}
