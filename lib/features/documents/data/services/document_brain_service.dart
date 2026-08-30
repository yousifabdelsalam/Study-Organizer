import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' as intl;

import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/topics/data/models/topic.dart';
import 'package:study_organizer/features/notes/data/models/subject_note.dart';
import 'package:study_organizer/features/documents/data/models/study_document.dart';
import 'package:study_organizer/features/documents/data/services/document_search_indexer.dart';
import 'package:study_organizer/features/subjects/data/models/subject_metadata.dart';
import 'package:study_organizer/features/timetable/data/models/timetable.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';

// Supports up to 6 API keys — stored as 'gemini_api_key_0' … 'gemini_api_key_5'
const String _prefGeminiKeyBase = 'gemini_api_key';
const int _maxKeys = 6;

class JarvisBrainService {
  static String? _cachedModelId;

  // ── Key pool ────────────────────────────────────────────────────────────────
  // Cached pool of non-empty keys and a simple round-robin cursor
  static List<String> _keyPool = [];
  static int _keyIndex = 0;
  static bool _keyPoolLoaded = false;

  /// Load all saved keys from SharedPreferences into the in-memory pool.
  static Future<void> _loadKeyPool() async {
    if (_keyPoolLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final pool = <String>[];
    for (int i = 0; i < _maxKeys; i++) {
      final k = prefs.getString('${_prefGeminiKeyBase}_$i')?.trim() ?? '';
      if (k.isNotEmpty) pool.add(k);
    }
    // Fallback: legacy single-key pref
    if (pool.isEmpty) {
      final legacy = prefs.getString(_prefGeminiKeyBase)?.trim() ?? '';
      if (legacy.isNotEmpty) pool.add(legacy);
    }
    _keyPool = pool;
    _keyPoolLoaded = true;
  }

  /// Returns the primary (first) key — used for legacy callers & settings checks.
  static Future<String?> getApiKey() async {
    await _loadKeyPool();
    return _keyPool.isNotEmpty ? _keyPool[0] : null;
  }

  /// Save all keys. Pass a list of up to 6 (empty strings clear that slot).
  static Future<void> setApiKeys(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < _maxKeys; i++) {
      final k = i < keys.length ? keys[i].trim() : '';
      if (k.isEmpty) {
        await prefs.remove('${_prefGeminiKeyBase}_$i');
      } else {
        await prefs.setString('${_prefGeminiKeyBase}_$i', k);
      }
    }
    if (keys.isNotEmpty && keys[0].trim().isNotEmpty) {
      await prefs.setString(_prefGeminiKeyBase, keys[0].trim());
    }
    // Invalidate cache so next request reloads the pool
    _keyPool = [];
    _keyPoolLoaded = false;
    _keyIndex = 0;
    clearModelCache();
  }

  /// Legacy single-key setter — stores key as slot 0 without clearing other slots.
  static Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefGeminiKeyBase}_0', trimmed);
    await prefs.setString(_prefGeminiKeyBase, trimmed);
    _keyPool = [];
    _keyPoolLoaded = false;
    _keyIndex = 0;
    clearModelCache();
  }

  /// Load all saved keys as a list of 6 strings (empty string = empty slot).
  static Future<List<String>> getAllApiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String>[];
    for (int i = 0; i < _maxKeys; i++) {
      result.add(prefs.getString('${_prefGeminiKeyBase}_$i')?.trim() ?? '');
    }
    return result;
  }

  static int _modelScore(String id) {
    final lower = id.toLowerCase();
    int score = 0;

    // ── Generation (most important) ──────────────────────────────
    if (lower.contains('3.1')) score += 60; // gemini-3.1-pro-preview — BEST
    if (lower.contains('3.0')) score += 50; // gemini-3.0-x
    if (lower.contains('gemini-3') && !lower.contains('3.'))
      score += 45; // gemini-3 variants
    if (lower.contains('2.5')) score += 30; // gemini-2.5-x (confirmed working)
    if (lower.contains('2.0')) score += 15;
    if (lower.contains('1.5')) score += 5;

    // ── Model tier ───────────────────────────────────────────────
    if (lower.contains('pro')) score += 4; // pro > flash for analysis quality
    if (lower.contains('flash')) score += 2; // fast, good default

    // ── Avoid specialised/slow/weak variants ────────────────────
    if (lower.contains('tts')) score -= 50; // text-to-speech, useless for us
    if (lower.contains('image'))
      score -= 20; // image generation, not what we need
    if (lower.contains('computer-use'))
      score -= 30; // computer use agent, not for us
    if (lower.contains('customtools'))
      score -= 10; // fine-tuned variant, less general
    if (lower.contains('thinking')) score -= 5; // too slow for most tasks
    if (lower.contains('lite')) score -= 30; // weakest
    if (lower.contains('preview'))
      score += 1; // preview = cutting edge, slight bonus

    return score;
  }

  static List<String> _sortModelsSmartestFirst(List<String> ids) {
    final list = List<String>.from(ids);
    list.sort((a, b) {
      final diff = _modelScore(b) - _modelScore(a);
      if (diff != 0) return diff;
      return a.compareTo(b);
    });
    return list;
  }

  // Cache of available model IDs per API key
  static final Map<String, List<String>> _keyModelsCache = {};

  static Future<List<String>> _listAvailableModels(String apiKey) async {
    if (_keyModelsCache.containsKey(apiKey)) return _keyModelsCache[apiKey]!;
    try {
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey&pageSize=50';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('ListModels failed: ${res.statusCode}');
        return [];
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final models = data['models'] as List<dynamic>?;
      if (models == null) return [];
      final ids = <String>[];
      for (final m in models) {
        final name = m['name'] as String?;
        if (name == null || !name.startsWith('models/')) continue;
        final id = name.replaceFirst('models/', '');
        final methods = m['supportedGenerationMethods'] as List<dynamic>?;
        final supportsGenerate =
            methods == null ||
            methods.isEmpty ||
            methods.any((e) => e.toString().contains('generateContent'));
        if (supportsGenerate) ids.add(id);
      }
      final sorted = _sortModelsSmartestFirst(ids);
      debugPrint(
        'Available models (${sorted.length}): ${sorted.take(8).join(', ')}',
      );
      if (sorted.isNotEmpty) {
        _keyModelsCache[apiKey] = sorted;
      }
      return sorted;
    } catch (e) {
      debugPrint('JarvisBrain listModels error: $e');
      return [];
    }
  }

  // Clear model cache (call when API key changes)
  static void clearModelCache() {
    _cachedModelId = null;
    _keyModelsCache.clear();
  }

  static Future<String> _generateContent(String prompt, {List<JarvisDocument>? attachedDocs}) async {
    await _loadKeyPool();

    if (_keyPool.isEmpty) {
      throw Exception('NO_KEY:No API key configured. Please set your Gemini API key in NOVA settings.');
    }

    const fallbackIds = [
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-2.5-flash',
      'gemini-2.0-flash-exp',
    ];

    String? lastError;

    for (final apiKey in _keyPool) {
      if (apiKey.trim().isEmpty) continue;
      final fromApi = await _listAvailableModels(apiKey);
      final List<String> toTry = [
        if (_cachedModelId != null && fromApi.contains(_cachedModelId!)) _cachedModelId!,
        ...fromApi.where((m) => m != _cachedModelId),
        ...fallbackIds.where((m) => !fromApi.contains(m)),
      ];

      for (final modelId in toTry.take(6)) {
        for (final version in ['v1beta', 'v1']) {
          final url =
              'https://generativelanguage.googleapis.com/$version/models/$modelId:generateContent?key=$apiKey';
          try {
            final res = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'contents': [
                      {
                        'parts': [
                          {'text': prompt},
                        ],
                      },
                    ],
                    'generationConfig': {
                      'temperature': 0.3,
                      'maxOutputTokens': 4096,
                    },
                  }),
                )
                .timeout(const Duration(seconds: 60));
            if (res.statusCode == 200) {
              _cachedModelId = modelId;
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              final candidates = data['candidates'] as List<dynamic>?;
              if (candidates != null && candidates.isNotEmpty) {
                final content = candidates[0]['content'] as Map<String, dynamic>?;
                final parts = content?['parts'] as List<dynamic>?;
                if (parts != null && parts.isNotEmpty) {
                  final text = parts[0]['text'] as String?;
                  return text?.trim() ?? 'No response.';
                }
              }
              return 'No response.';
            }
            if (res.statusCode == 404 ||
                (res.body.contains('not found') ||
                    res.body.contains('is not supported'))) {
              continue;
            }
            if (res.statusCode == 429 ||
                res.body.contains('RESOURCE_EXHAUSTED') ||
                res.body.contains('quota')) {
              _cachedModelId = null;
              lastError =
                  'Quota exceeded on your Gemini API key. Please wait a few minutes or add a backup key in settings.';
              break; // Try next API key
            }
            if (res.statusCode == 403 || res.statusCode == 401) {
              lastError =
                  'Invalid or restricted Gemini API key. Please check your API key in NOVA settings.';
              break; // Try next API key
            }
            lastError = res.body.length > 200
                ? '${res.body.substring(0, 200)}...'
                : res.body;
          } catch (e) {
            debugPrint('Gemini $version/$modelId error: $e');
          }
        }
      }
    }

    throw Exception(
      lastError ??
          'No Gemini model could respond. Please check your API key and internet connection in NOVA settings.',
    );
  }


  // ── High-output generation for long-form reports ─────────────────────────
  // Uses up to 65536 output tokens. Falls back to 16384/8192 if rejected.
  static Future<String> _generateLongContent(String prompt) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('No Gemini API key. Set it in NOVA settings.');
    }
    final fromApi = await _listAvailableModels(apiKey);
    const fallbackIds = [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-3.0-flash',
      'gemini-2.0-flash-exp',
      'gemini-1.5-pro',
    ];
    List<String> toTry;
    if (_cachedModelId != null && fromApi.contains(_cachedModelId!)) {
      toTry = [_cachedModelId!, ...fromApi.where((m) => m != _cachedModelId!)];
    } else {
      toTry = fromApi.isNotEmpty
          ? fromApi
          : _sortModelsSmartestFirst(fallbackIds);
    }
    const tokenLimits = [16384, 8192];
    for (final modelId in toTry) {
      for (final version in ['v1beta', 'v1']) {
        for (final maxTokens in tokenLimits) {
          final url =
              'https://generativelanguage.googleapis.com/$version/models/$modelId:generateContent?key=$apiKey';
          try {
            final res = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'contents': [
                      {
                        'parts': [
                          {'text': prompt},
                        ],
                      },
                    ],
                    'generationConfig': {
                      'temperature': 0.3,
                      'maxOutputTokens': maxTokens,
                    },
                  }),
                )
                .timeout(const Duration(seconds: 240));
            if (res.statusCode == 200) {
              _cachedModelId = modelId;
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              final candidates = data['candidates'] as List<dynamic>?;
              if (candidates != null && candidates.isNotEmpty) {
                final content =
                    candidates[0]['content'] as Map<String, dynamic>?;
                final parts = content?['parts'] as List<dynamic>?;
                if (parts != null && parts.isNotEmpty) {
                  final text = (parts[0]['text'] as String?)?.trim() ?? '';
                  if (text.isNotEmpty) {
                    debugPrint(
                      'Long gen: $modelId maxTokens=$maxTokens -> ${text.length} chars',
                    );
                    return text;
                  }
                }
              }
              continue;
            } else if (res.statusCode == 404 ||
                res.body.contains('not found') ||
                res.body.contains('is not supported')) {
              break;
            } else if (res.statusCode == 400 &&
                (res.body.contains('maxOutputTokens') ||
                    res.body.contains('invalid'))) {
              debugPrint(
                'Token limit $maxTokens rejected by $modelId, trying smaller...',
              );
              continue;
            } else if (res.statusCode == 429 || res.body.contains('quota')) {
              _cachedModelId = null;
              break;
            }
          } catch (e) {
            debugPrint('_generateLongContent $modelId/$version/$maxTokens: $e');
            break;
          }
        }
      }
    }
    throw Exception(
      'Could not generate long-form content. Check API key and quota.',
    );
  }

  // ── Strip markdown for TTS so it never says "asterisk asterisk" ────────────

  // ── Public: resolve model ID (used by subject_detail for chunked extraction) ─
  // ════════════════════════════════════════════════════════════════════════════
  // PATCH for jarvis_brain_service.dart
  //
  // ADD these two things to the JarvisBrainService class:
  //
  // 1. Replace resolveModel() with the faster version below.
  // 2. Add generateFast() method (used by jarvis_service.dart for action parsing).
  // ════════════════════════════════════════════════════════════════════════════

  // ── REPLACE resolveModel() with this ─────────────────────────────────────────
  static Future<String> resolveModel() async {
    // Return cached model immediately — zero latency on subsequent calls
    if (_cachedModelId != null) return _cachedModelId!;

    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _cachedModelId = 'gemini-2.0-flash';
      return _cachedModelId!;
    }

    // Try to discover models from API (only once, result is cached)
    final models = await _listAvailableModels(apiKey);
    if (models.isNotEmpty) {
      _cachedModelId = models.first;
      debugPrint('[NOVA Brain] Resolved model: $_cachedModelId');
      return _cachedModelId!;
    }

    // Hardcoded fallback — these definitely work on free Gemini accounts
    _cachedModelId = 'gemini-2.0-flash';
    return _cachedModelId!;
  }

  // ── Public: raw generation — rotates across key pool ──────────────────────
  static Future<String?> generateRaw({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.1,
    bool isJson = false,
  }) async {
    await _loadKeyPool();
    if (_keyPool.isEmpty) return null;

    final modelId = await resolveModel();
    final totalKeys = _keyPool.length;

    for (int attempt = 0; attempt < totalKeys; attempt++) {
      final apiKey = _keyPool[_keyIndex % totalKeys];
      _keyIndex = (_keyIndex + 1) % totalKeys;

      bool hitRateLimit = false;

      for (final version in ['v1beta', 'v1']) {
        final url =
            'https://generativelanguage.googleapis.com/$version/models/$modelId:generateContent?key=$apiKey';
        try {
          final res = await http
              .post(
                Uri.parse(url),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': prompt},
                      ],
                    },
                  ],
                  'generationConfig': {
                    'temperature': temperature,
                    'maxOutputTokens': maxTokens,
                    if (isJson) 'responseMimeType': 'application/json',
                  },
                }),
              )
              .timeout(const Duration(seconds: 90));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final candidates = data['candidates'] as List<dynamic>?;
            if (candidates != null && candidates.isNotEmpty) {
              final content = candidates[0]['content'] as Map<String, dynamic>?;
              final parts = content?['parts'] as List<dynamic>?;
              if (parts != null && parts.isNotEmpty) {
                final sb = StringBuffer();
                for (final p in parts) {
                  if (p['text'] != null) sb.write(p['text']);
                }
                return sb.toString().trim();
              }
            }
            return null;
          }

          // 429 = this key is rate-limited → try next key
          if (res.statusCode == 429) {
            debugPrint('generateRaw: key $attempt rate-limited, rotating.');
            hitRateLimit = true;
            break;
          }

          // JSON mime unsupported → retry without it
          if (isJson &&
              res.statusCode == 400 &&
              res.body.contains('responseMimeType')) {
            final res2 = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'contents': [
                      {
                        'parts': [
                          {'text': prompt},
                        ],
                      },
                    ],
                    'generationConfig': {
                      'temperature': temperature,
                      'maxOutputTokens': maxTokens,
                    },
                  }),
                )
                .timeout(const Duration(seconds: 90));
            if (res2.statusCode == 200) {
              final data = jsonDecode(res2.body) as Map<String, dynamic>;
              final candidates = data['candidates'] as List<dynamic>?;
              if (candidates != null && candidates.isNotEmpty) {
                final content =
                    candidates[0]['content'] as Map<String, dynamic>?;
                final parts = content?['parts'] as List<dynamic>?;
                if (parts != null && parts.isNotEmpty) {
                  final sb = StringBuffer();
                  for (final p in parts) {
                    if (p['text'] != null) sb.write(p['text']);
                  }
                  return sb.toString().trim();
                }
              }
            }
          }
        } catch (e) {
          debugPrint('generateRaw error (key $attempt): $e');
        }
      }

      if (!hitRateLimit)
        break; // non-rate-limit failure — no point trying other keys
    }
    return null;
  }

  static Future<String?> generateFast({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    await _loadKeyPool();
    if (_keyPool.isEmpty) return null;

    // Prefer flash models for speed — try hardcoded flash first, then resolved
    const flashModels = [
      'gemini-2.0-flash',
      'gemini-2.0-flash-exp',
      'gemini-1.5-flash',
      'gemini-2.5-flash',
    ];

    final apiKey = _keyPool[_keyIndex % _keyPool.length];
    _keyIndex = (_keyIndex + 1) % _keyPool.length;

    // Try each flash model
    for (final modelId in flashModels) {
      for (final version in ['v1beta', 'v1']) {
        final url =
            'https://generativelanguage.googleapis.com/$version/models/$modelId:generateContent?key=$apiKey';
        try {
          final res = await http
              .post(
                Uri.parse(url),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': prompt},
                      ],
                    },
                  ],
                  'generationConfig': {
                    'temperature': temperature,
                    'maxOutputTokens': maxTokens,
                    'responseMimeType': 'application/json',
                  },
                }),
              )
              .timeout(const Duration(seconds: 12)); // tight timeout for speed

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final candidates = data['candidates'] as List<dynamic>?;
            if (candidates != null && candidates.isNotEmpty) {
              final content = candidates[0]['content'] as Map<String, dynamic>?;
              final parts = content?['parts'] as List<dynamic>?;
              if (parts != null && parts.isNotEmpty) {
                final sb = StringBuffer();
                for (final p in parts) {
                  if (p['text'] != null) sb.write(p['text']);
                }
                final result = sb.toString().trim();
                if (result.isNotEmpty) {
                  _cachedModelId = modelId; // cache working model
                  return result;
                }
              }
            }
          }

          // JSON mime unsupported → retry without it
          if (res.statusCode == 400 && res.body.contains('responseMimeType')) {
            final res2 = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'contents': [
                      {
                        'parts': [
                          {'text': prompt},
                        ],
                      },
                    ],
                    'generationConfig': {
                      'temperature': temperature,
                      'maxOutputTokens': maxTokens,
                    },
                  }),
                )
                .timeout(const Duration(seconds: 12));

            if (res2.statusCode == 200) {
              final data = jsonDecode(res2.body) as Map<String, dynamic>;
              final candidates = data['candidates'] as List<dynamic>?;
              if (candidates != null && candidates.isNotEmpty) {
                final content =
                    candidates[0]['content'] as Map<String, dynamic>?;
                final parts = content?['parts'] as List<dynamic>?;
                if (parts != null && parts.isNotEmpty) {
                  final sb = StringBuffer();
                  for (final p in parts) {
                    if (p['text'] != null) sb.write(p['text']);
                  }
                  final result = sb.toString().trim();
                  if (result.isNotEmpty) {
                    _cachedModelId = modelId;
                    return result;
                  }
                }
              }
            }
          }

          // 404 = model not available → try next
          if (res.statusCode == 404) continue;

          // 429 = rate limited → try next key (don't block)
          if (res.statusCode == 429) break;
        } catch (e) {
          debugPrint('[NOVA Brain] generateFast $modelId error: $e');
          if (e.toString().contains('TimeoutException')) continue;
        }
      }
    }

    return null; // all models failed — caller will use fallback
  }

  // ── Mark Surgeon ──────────────────────────────────────────────────────────
  static Future<String> getMarkSurgeonAnalysis(
    List<MarkModel> marks,
    List<Subject> subjects,
  ) async {
    final losses = marks
        .where((m) => m.lossReason != null && m.lossReason!.isNotEmpty)
        .toList();
    if (losses.isEmpty)
      return "No mark losses recorded yet. Enter a mark below 100% to track root causes.";

    final sb = StringBuffer();
    double totalLost = 0;
    for (final m in losses) {
      final sName = subjects
          .firstWhere(
            (s) => s.id == m.subjectId,
            orElse: () => Subject(name: 'Unknown'),
          )
          .name;
      final lost = m.total - m.obtained;
      totalLost += lost;
      sb.writeln(
        '- $sName (${m.label}): Lost $lost marks. Reason: ${m.lossReason}',
      );
    }

    final prompt =
        '''
You are the "Mark Surgeon" 🔪, an elite academic AI analyzing a student's lost marks across subjects.
Here are the explicitly documented reasons they lost marks:
$sb

Analyze this data and find the #1 root cause or cross-subject pattern costing them the most marks.
Give a brutal, surgical diagnosis and one exact prescription to fix it.
Start exactly like this: "⚠️ **You've lost $totalLost marks.** Most came from the same root cause: [your diagnosis]."

FORMATTING: Use Markdown (**bold**, - bullets). Use emojis (⚠️🔥💡). Be concise but complete.
''';

    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 800,
      temperature: 0.2,
    );
    return res ?? "Could not perform Mark Surgeon analysis. Try again later.";
  }

  // ── Concept Contamination Detector ─────────────────────────────────────────
  static Future<List<String>> generateContaminationQuestions(
    String subjectName,
    String topicName,
  ) async {
    final prompt =
        '''
Generate 3 highly deceptive "Concept Contamination" trick questions for the topic "$topicName" in the subject "$subjectName".
These questions must test if the user truly understands the principles or if they are just memorizing patterns.
Include common misconceptions or trap scenarios.
Return ONLY a valid JSON array of 3 strings. E.g.: ["Q1...", "Q2...", "Q3..."]
Do not use markdown blocks.
''';
    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 400,
      temperature: 0.7,
      isJson: true,
    );
    if (res == null)
      return [
        "Explain the main concept.",
        "What is a common mistake?",
        "How does this apply in the real world?",
      ];
    try {
      final sanitized = res
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final List<dynamic> parsed = jsonDecode(sanitized);
      return parsed.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error parsing contamination questions: $e');
      return [
        "Explain the core concept in your own words.",
        "Contrast it with a similar topic.",
        "Give an edge case exception.",
      ];
    }
  }

  static Future<Map<String, dynamic>> gradeContaminationAnswers(
    String subjectName,
    String topicName,
    List<String> questions,
    List<String> answers,
  ) async {
    if (questions.isEmpty || answers.isEmpty)
      return {'passed': false, 'feedback': 'No questions or answers.'};

    final sb = StringBuffer();
    for (int i = 0; i < questions.length; i++) {
      sb.writeln('Q${i + 1}: ${questions[i]}');
      sb.writeln('A${i + 1}: ${i < answers.length ? answers[i] : "No answer"}');
    }

    final prompt =
        '''
You are an elite, strict professor analyzing a student's answers to Concept Contamination trick questions for "$topicName" in "$subjectName".
$sb

Determine if the student genuinely survived the contamination (i.e. they understand the core concept and didn't fall for the traps).
They must demonstrate true understanding, not just surface knowledge.
Respond with ONLY a valid JSON object:
{"passed": true or false, "feedback": "1 short brutal feedback sentence explaining why they passed or fell for the trap."}
Do not include markdown.
''';
    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 200,
      temperature: 0.1,
      isJson: true,
    );
    if (res == null)
      return {'passed': false, 'feedback': 'Grading AI failed to respond.'};
    try {
      final sanitized = res
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final parsed = jsonDecode(sanitized);
      return {
        'passed': parsed['passed'] == true,
        'feedback': parsed['feedback']?.toString() ?? 'Evaluation completed.',
      };
    } catch (_) {
      return {
        'passed': false,
        'feedback': 'Evaluation format error. Assuming failure.',
      };
    }
  }

  static Future<String> generateLightningQuestion(
    String subjectName,
    String topicName,
    String docsContext,
  ) async {
    final rng = Random();

    // Sample a random 6000-char window so different parts get covered
    String trimmedDocs;
    if (docsContext.length > 6000) {
      final maxStart = docsContext.length - 6000;
      final start = rng.nextInt(maxStart);
      trimmedDocs = docsContext.substring(start, start + 6000);
    } else {
      trimmedDocs = docsContext;
    }

    final angles = [
      'Ask about a specific definition or concept.',
      'Ask about a formula, rule, or theorem.',
      'Ask about a practical application or real-world example.',
      'Ask about the difference between two concepts.',
      'Ask about a condition, exception, or edge case.',
      'Ask a calculation or problem-solving question.',
      'Ask about cause and effect.',
    ];
    final angle = angles[rng.nextInt(angles.length)];

    final prompt =
        '''You are an elite professor. Generate ONE exam-style question for topic "$topicName" in "$subjectName".
$angle
Requirements:
- The kind of question that appears on a real university exam
- Answerable in 20-30 seconds
- A complete, well-formed sentence ending with "?"
- Based ONLY on the STUDY MATERIAL below

If the STUDY MATERIAL is empty or unrelated, reply ONLY: INSUFFICIENT_MATERIAL

Output ONLY the question. No intro. No numbering. No markdown.

STUDY MATERIAL:
$trimmedDocs
''';
    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 512,
      temperature: 1.0,
      isJson: false,
    );
    return res ?? 'What is the core principle behind $topicName?';
  }

  static Future<Map<String, dynamic>> gradeLightningAnswer(
    String subjectName,
    String topicName,
    String question,
    String answer,
  ) async {
    if (answer.trim().isEmpty)
      return {'passed': false, 'feedback': 'No answer provided.'};

    final prompt =
        '''Grade this rapid-fire 60-Second Drill answer. Be concise.
Subject: $subjectName
Topic: $topicName
Question: $question
Student Answer: $answer

Reply using EXACTLY this 3-line format. Do not add any extra text:
RESULT: PASS or FAIL
FEEDBACK: [one brief sentence]
CORRECT: [the correct answer — REQUIRED if RESULT is FAIL, leave empty if PASS]
''';
    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 800,
      temperature: 0.1,
      isJson: false,
    );
    print('--- LIGHTNING RAW RES ---');
    print(res);
    if (res == null) return {'passed': false, 'feedback': 'Grading AI failed.'};

    // Parse plaintext lines
    final lines = res.split('\n').map((l) => l.trim()).toList();
    bool passed = false;
    String feedback = 'Evaluated.';
    String correctAnswer = '';

    for (final line in lines) {
      if (line.startsWith('RESULT:')) {
        passed =
            line.substring('RESULT:'.length).trim().toUpperCase() == 'PASS';
      } else if (line.startsWith('FEEDBACK:')) {
        feedback = line.substring('FEEDBACK:'.length).trim();
      } else if (line.startsWith('CORRECT:')) {
        correctAnswer = line.substring('CORRECT:'.length).trim();
      }
    }

    return {
      'passed': passed,
      'feedback': feedback.isNotEmpty ? feedback : 'Evaluated.',
      'correct_answer': correctAnswer,
    };
  }

  // ── Night Before Protocol ────────────────────────────────────────────────
  static Future<String> generateNightBeforePlan(String contextPayload) async {
    final prompt =
        '''
You are NOVA, an elite academic AI. Tomorrow, the student has critical exams/deadlines. Provide a brutal, highly actionable 90-minute "NOVA Target Briefing" study plan.
DO NOT TRUNCATE your answer. It is critical that your output is complete.

Here is the complete state of the student's knowledge, history, and notes for the upcoming exam subjects:
$contextPayload

Melt all this information together. Do not just list topics. Analyze their specific past mistakes (from Mark Surgeon), their weakest topics (Stage 0/1/2 vs mastered), and the exact documents/notes they have uploaded. 
Generate a specific, tactical 90-minute attack plan directly addressing their unique vulnerabilities and historical mark losses in these exact subjects.

FORMATTING:
- Use Markdown: **bold** for emphasis, ## headers for sections, - bullet points for lists.
- Use timestamps (e.g., **Min 0-30:** ...) and emojis (⏰ time blocks, 🔥 critical, ⚠️ weak areas, 💡 tips).
- Address historical weaknesses specifically. Be comprehensive and academically superior.
''';
    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 4096, // Increased to handle larger plans
      temperature: 0.2,
    );
    return res ??
        "Focus immediately on your weakest topics and past mistakes. Get plenty of sleep.";
  }

  // ── Absence-Mark Collider ──────────────────────────────────────────────────
  static Future<String> analyzeAbsenceMarkCollision({
    required String subjectName,
    required List<Map<String, dynamic>> absences,
    required List<MarkModel> marks,
    required List<JarvisDocument> documents,
  }) async {
    final absBuf = StringBuffer();
    for (var a in absences) {
      absBuf.writeln('- Date: ${a['date']} | Type: ${a['type']}');
    }

    final markBuf = StringBuffer();
    for (var m in marks) {
      markBuf.writeln(
        '- Exam/Task: ${m.label} (${m.category}) | Mark: ${m.obtained}/${m.total}',
      );
    }

    final docsBuf = StringBuffer();
    for (var d in documents) {
      docsBuf.writeln('- ${d.type} (${d.name}): ${d.content}');
    }

    if (absences.isEmpty) {
      return "You have perfect attendance in $subjectName! There are no absences to correlate with your marks.";
    }

    if (marks.isEmpty) {
      return "There are no marks logged for $subjectName yet to correlate with your absences.";
    }

    final prompt =
        '''
You are the NOVA Absence-Mark Collider 💥. 
Your objective is to correlate the student's absences with their marks in the subject "$subjectName", and cross-reference with any available study materials or past exam topics to show the specific damage done by missing class.

Absences:
${absBuf.toString()}

Marks Logged:
${markBuf.toString()}

Study Documents/Exams Context (Optional Topics):
${docsBuf.toString()}

Calculate and hypothesize:
1. Did a specific set of missed lectures correlate to a low mark soon after?
2. Based on the documents/context, what topics were likely taught on the missed days?
3. What is the projected mark damage if this continues?

FORMATTING:
- Use Markdown: **bold** for emphasis, ## headers for sections, - bullet points for lists.
- Use emojis: ⚠️ warnings, 🔥 critical damage, 📉 trends, 📊 stats, 💡 recommendations.
- Be concise but devastatingly accurate. Like NOVA addressing Iron Man.
''';

    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 8192,
      temperature: 0.2,
      isJson: false,
    );
    return res ?? "Unable to compute collision data at this time.";
  }

  // ── Statistical Gap Detector ───────────────────────────────────────────────
  static Future<String> analyzeStatisticalGaps({
    required String subjectName,
    required List<JarvisDocument> studyMaterials,
    required List<JarvisDocument> pastExams,
  }) async {
    if (studyMaterials.isEmpty) {
      return "NOVA needs at least one study material document (lecture notes, etc.) to analyze gaps.";
    }
    if (pastExams.isEmpty) {
      return "NOVA needs at least one past exam uploaded to find the gap between what you study and what is tested.";
    }

    final materialsBuf = StringBuffer();
    for (var d in studyMaterials) {
      materialsBuf.writeln('- Material (${d.name}): ${d.content}');
    }

    final examsBuf = StringBuffer();
    for (var d in pastExams) {
      examsBuf.writeln('- Exam (${d.name}): ${d.content}');
    }

    final prompt =
        '''
You are the NOVA Statistical Gap Detector 🔬.
You are comparing two sets of documents for the subject "$subjectName":
1. Study Materials (What the student is told to learn)
2. Past Exams (What actually appears on the test)

Materials:
${materialsBuf.toString()}

Past Exams:
${examsBuf.toString()}

Calculate:
1. Identify all critical topics mentioned in the Study Materials.
2. Cross-reference them against the Past Exams.
3. OUTPUT THE GAP: What topics exist in the study materials but have NEVER appeared in any past exam?
4. Statistical Pressure: Since these topics haven't appeared yet, assign them a "Statistical Pressure" rating (High/Medium) estimating the probability they will appear on the next exam.

FORMATTING:
- Use Markdown: **bold** for emphasis, ## headers for sections, - bullet points for lists.
- Use emojis: 🚨 high pressure, ⚠️ medium, ✅ covered, 📊 stats.
- Be serious and analytical. Tell the student exactly what dangerous "untested" topics they must prepare for.
''';

    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 8192,
      temperature: 0.1,
      isJson: false,
    );
    return res ?? "Gap analysis failed to complete.";
  }

  // ── Confusion Cascade Mapper ───────────────────────────────────────────────
  static Future<String> analyzeConfusionCascade({
    required String subjectName,
    required List<StudyTopic> topics,
  }) async {
    if (topics.isEmpty) {
      return "NOVA needs at least one study topic to analyze the confusion cascade.";
    }

    final weakBuf = StringBuffer();
    final strongBuf = StringBuffer();

    for (var t in topics) {
      final info =
          '- "${t.title}" (Stage ${t.stage}): Notes: ${t.notes}, Prereqs: ${t.prerequisites.join(', ')}';
      if (t.stage <= 1) {
        weakBuf.writeln(info);
      } else {
        strongBuf.writeln(info);
      }
    }

    if (weakBuf.isEmpty) {
      return "Excellent. You have no weak topics (Stage 0 or 1). The Confusion Cascade is stable.";
    }

    final prompt =
        '''
You are the NOVA Confusion Cascade Mapper 🧠⚡.
You are analyzing the root weaknesses for the subject "$subjectName".

Topics the student is struggling with (low mastery):
${weakBuf.toString()}

Topics the student understands (high mastery):
${strongBuf.toString().isNotEmpty ? strongBuf.toString() : 'None.'}

Calculate the Cascade:
1. Examine the weak topics. Are there any obvious prerequisite dependencies between them? 
2. Trace the root cause: Why is the student failing these specific weak topics? (e.g., they might be struggling with Advanced Topic X because they never mastered Fundamental Topic Y).
3. If the user explicitly defined "Prereqs" for a weak topic, and the prereq is also a weak topic, point out this exact chain reaction.
4. Output the CONFUSION CASCADE: A bullet-point list tracing the exact path of failure and exactly which root topic the student MUST study first to break the cascade.

FORMATTING:
- Use Markdown: **bold** for emphasis, ## headers for sections, - bullet points for lists.
- Use emojis: ⚠️ cascade warnings, 🔗 dependency chains, 🎯 target topics, 💡 fix recommendations.
- Be precise, severe, and analytical. Iron Man NOVA tone.
''';

    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 8192,
      temperature: 0.2,
      isJson: false,
    );
    return res ?? "Cascade analysis failed to complete.";
  }

  // ── Knowledge X-Ray / Time-Practicing Timer ──────────────────────────────
  static Future<String> analyzeSolvingSpeed({
    required String subjectName,
    required String topicTitle,
    required String questionSummary,
    required int timeTakenSeconds,
    required List<JarvisDocument> pastExams,
  }) async {
    final minutes = (timeTakenSeconds / 60).toStringAsFixed(1);

    final examsBuf = StringBuffer();
    for (var d in pastExams) {
      examsBuf.writeln(
        '- Exam (${d.name}): ${d.content.length > 500 ? d.content.substring(0, 500) + '...' : d.content}',
      );
    }

    final prompt =
        '''
You are the NOVA Knowledge X-Ray 🔬.
The student is practicing a question for the subject "$subjectName", topic "$topicTitle".
Question Summary: "$questionSummary"
Time Taken: $timeTakenSeconds seconds ($minutes minutes).

Here are some snippets of past exams for context:
${examsBuf.isEmpty ? 'None provided.' : examsBuf.toString()}

Analyze this speed. 
1. Is $minutes minutes a reasonable time to solve a question of this nature given typical university exam constraints?
2. Estimate the "Expected NOVA Time" for this question.
3. Diagnose the speed. If too slow, suggest exactly what mental shortcuts or formulas they are likely forgetting. If extremely fast, warn them about specific careless mistakes they might have made.

FORMATTING:
- Use Markdown: **bold** for emphasis, ## headers for sections, - bullet points.
- Use emojis: ⏱️ timing, ⚠️ warnings, 💡 tips, ✅ good, 🔥 problems.
- Be firm, analytical, and slightly demanding.
''';

    final res = await generateRaw(
      prompt: prompt,
      maxTokens: 1200,
      temperature: 0.3,
      isJson: false,
    );
    return res ?? "Time analysis failed to complete.";
  }

  // ── Gemini Files API: upload a file and get a URI ─────────────────────────
  // Supports files up to 20MB. No chunking. No base64 bloat. The RIGHT way.
  // Uploaded files are available for 48 hours via their URI.
  static Future<Map<String, String>?> uploadFileToGemini({
    required List<int> bytes,
    required String mimeType,
    required String displayName,
    void Function(String status)? onStatus,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    onStatus?.call('Connecting to Gemini...');

    try {
      // Step 1: Initiate resumable upload — get an upload URL
      final initUrl =
          'https://generativelanguage.googleapis.com/upload/v1beta/files?key=$apiKey';
      final initRes = await http
          .post(
            Uri.parse(initUrl),
            headers: {
              'X-Goog-Upload-Protocol': 'resumable',
              'X-Goog-Upload-Command': 'start',
              'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
              'X-Goog-Upload-Header-Content-Type': mimeType,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'file': {'display_name': displayName},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (initRes.statusCode != 200) {
        debugPrint(
          'Files API init FAILED: ${initRes.statusCode}\n${initRes.body}',
        );
        return null;
      }

      final uploadUrl = initRes.headers['x-goog-upload-url'];
      if (uploadUrl == null || uploadUrl.isEmpty) {
        debugPrint('Files API: no x-goog-upload-url in response headers');
        debugPrint('Response headers: ${initRes.headers}');
        return null;
      }

      final sizeMb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      onStatus?.call('Uploading $sizeMb MB...');
      debugPrint('Uploading $sizeMb MB to $uploadUrl');

      // Step 2: Upload the actual file bytes
      final uploadRes = await http
          .post(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Length': '${bytes.length}',
              'X-Goog-Upload-Offset': '0',
              'X-Goog-Upload-Command': 'upload, finalize',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 300)); // 5 min for large files

      debugPrint('Upload response: ${uploadRes.statusCode}');
      if (uploadRes.statusCode != 200) {
        debugPrint(
          'Files API upload FAILED: ${uploadRes.statusCode}\n${uploadRes.body.substring(0, uploadRes.body.length.clamp(0, 500))}',
        );
        return null;
      }

      final data = jsonDecode(uploadRes.body) as Map<String, dynamic>;
      final file = data['file'] as Map<String, dynamic>?;
      final uri = file?['uri'] as String?;
      final mime = file?['mimeType'] as String? ?? mimeType;
      final state = file?['state'] as String?;

      if (uri == null) {
        debugPrint(
          'Files API: no uri in response. Full response: ${uploadRes.body.substring(0, 500)}',
        );
        return null;
      }

      // Poll until file is ACTIVE (Gemini needs a few seconds to process uploaded files)
      String currentState = state ?? 'ACTIVE';
      if (currentState != 'ACTIVE') {
        onStatus?.call('Processing file...');
        for (int attempt = 0; attempt < 12; attempt++) {
          await Future.delayed(const Duration(seconds: 3));
          try {
            // URI format: "files/abc123xyz" or full URL
            final fileId = uri.contains('/') ? uri.split('/').last : uri;
            final checkUrl =
                'https://generativelanguage.googleapis.com/v1beta/files/$fileId?key=$apiKey';
            final checkRes = await http
                .get(Uri.parse(checkUrl))
                .timeout(const Duration(seconds: 15));
            if (checkRes.statusCode == 200) {
              final checkData =
                  jsonDecode(checkRes.body) as Map<String, dynamic>;
              currentState = checkData['state'] as String? ?? 'ACTIVE';
              debugPrint(
                'File state poll: $currentState (attempt ${attempt + 1})',
              );
              if (currentState == 'ACTIVE') break;
            }
          } catch (e) {
            debugPrint('State poll error: $e');
            break; // assume ACTIVE if check fails
          }
        }
      }

      onStatus?.call('Upload complete ✓');
      debugPrint('File ready: $uri (mime: $mime, state: $currentState)');
      return {'uri': uri, 'mimeType': mime};
    } catch (e) {
      debugPrint('uploadFileToGemini exception: $e');
      return null;
    }
  }

  // ── Break Doctor Brain: analyze file URI directly ─────────────────────────
  // Uses Gemini Files API (file_data). Only v1beta supports this.
  static Future<String> analyzeFileDirectly({
    required String fileUri,
    required String mimeType,
    required String subjectName,
    required String doctorName,
    required String docType,
    required String docName,
    required String allSubjectContext,
    void Function(String)? onStatus,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return 'No Gemini API key. Get a free key at aistudio.google.com';
    }

    onStatus?.call('Loading available models...');

    // Get the actual models available for this API key
    final availableModels = await _listAvailableModels(apiKey);
    // Use all available models — ListModels already filters to supported ones
    final modelsToTry = availableModels.isNotEmpty
        ? availableModels
        : [
            'gemini-2.5-flash',
            'gemini-2.5-pro',
            'gemini-3.0-flash',
            'gemini-2.0-flash-exp',
            'gemini-2.0-flash',
            'gemini-1.5-flash',
          ];

    onStatus?.call('NOVA is reading the document...');

    final docLabel = docType == 'past_exam'
        ? 'PAST EXAM PAPER'
        : 'STUDY MATERIAL';

    final prompt =
        'You are NOVA, an elite academic intelligence system.\n'
        'Mission: analyze this $docLabel and crack the instructor exam pattern.\n\n'
        'SUBJECT: $subjectName\n'
        'INSTRUCTOR: $doctorName\n'
        'DOCUMENT: $docName\n\n'
        'ADDITIONAL SUBJECT CONTEXT:\n$allSubjectContext\n\n'
        'Read the attached document and produce a DEEP INTELLIGENCE REPORT.\n'
        'Use Markdown formatting: **bold** for emphasis, ## headers for sections, - bullet points for lists.\n'
        'Use emojis where appropriate: \ud83d\udea8 high priority, \u26a0\ufe0f warnings, \ud83c\udfaf targets, \ud83d\udcca analysis.\n'
        'For math/formulas, use LaTeX: inline \$formula\$ or block \$\$formula\$\$.\n\n'
        '## 1. DOCUMENT OVERVIEW\n'
        'What does this document cover? Structure and scope.\n\n'
        '## 2. INSTRUCTOR DNA - Pattern Analysis\n'
        'Topics this instructor tests repeatedly.\n'
        'Question styles they prefer (definitions, calculations, essay, MCQ).\n'
        'Exact phrases and terms that appear most often.\n'
        'Difficulty distribution estimate.\n\n'
        '## 3. HIGH-PROBABILITY EXAM TOPICS (Top 10)\n'
        'List 10 topics most likely in the next exam with probability % and reason.\n\n'
        '## 4. PREDICTED EXAM QUESTIONS\n'
        'Write 5 specific questions this instructor is very likely to ask.\n\n'
        '## 5. WHAT THE INSTRUCTOR WANTS IN ANSWERS\n'
        'Key terminology to include. Detail level expected. Common mistakes to avoid.\n\n'
        '## 6. UNTESTED TOPICS (if past exam)\n'
        'Topics in the material but absent from past exams. Likely coming next.\n\n'
        '## 7. OPTIMAL STUDY STRATEGY\n'
        'Priority order. Which topics need the most time.\n\n'
        'Be ruthlessly precise. Base everything ONLY on the document content.';

    final errors = <String>[];

    for (final modelId in modelsToTry) {
      // Files API ONLY works with v1beta — do NOT try v1
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=$apiKey';
      try {
        onStatus?.call('Analyzing with $modelId...');
        final res = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {
                        'file_data': {
                          'mime_type': mimeType,
                          'file_uri': fileUri,
                        },
                      },
                      {'text': prompt},
                    ],
                  },
                ],
                'generationConfig': {
                  'temperature': 0.2,
                  'maxOutputTokens': 8192,
                },
              }),
            )
            .timeout(const Duration(seconds: 180));

        debugPrint('analyzeFileDirectly $modelId: HTTP ${res.statusCode}');

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final candidate = candidates[0] as Map<String, dynamic>;
            final finishReason = candidate['finishReason'] as String?;
            if (finishReason == 'SAFETY') {
              return 'Analysis blocked by Gemini safety filter. The document may contain restricted content.';
            }
            final c = candidate['content'] as Map<String, dynamic>?;
            final parts = c?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final text = (parts[0]['text'] as String?)?.trim() ?? '';
              if (text.isNotEmpty) {
                debugPrint(
                  'Analysis success with $modelId (${text.length} chars)',
                );
                return text;
              }
            }
          }
          // 200 but empty — try next model
          errors.add('$modelId: 200 but empty response');
          continue;
        } else if (res.statusCode == 429) {
          errors.add('$modelId: rate limited (429)');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        } else {
          final body = res.body.length > 400
              ? res.body.substring(0, 400)
              : res.body;
          errors.add('$modelId: ${res.statusCode} - $body');
          debugPrint('analyzeFileDirectly error: ${errors.last}');
          continue; // try next model
        }
      } catch (e) {
        errors.add('$modelId: exception - $e');
        debugPrint('analyzeFileDirectly $modelId exception: $e');
        continue; // try next model
      }
    }

    final errSummary = errors.join('; ');
    debugPrint('All models failed: $errSummary');
    return 'Analysis failed.\n\nTechnical details: $errSummary\n\nIf this persists, check that your API key has the Gemini API enabled at aistudio.google.com';
  }

  // ── Extract text from a Gemini file URI (for JARVIS chat context) ──────────
  // Uses v1beta only — Files API does not work with v1
  static Future<String> extractTextFromFileUri({
    required String fileUri,
    required String mimeType,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) return '';

    // Use the actual models available for this API key
    final availableModels = await _listAvailableModels(apiKey);
    final modelsToTry = availableModels.isNotEmpty
        ? availableModels
        : [
            'gemini-2.5-flash',
            'gemini-2.5-pro',
            'gemini-2.0-flash-exp',
            'gemini-2.0-flash',
          ];

    for (final modelId in modelsToTry) {
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=$apiKey';
      try {
        final res = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {
                        'file_data': {
                          'mime_type': mimeType,
                          'file_uri': fileUri,
                        },
                      },
                      {
                        'text':
                            'Extract ALL text from this document. '
                            'Keep Arabic as Arabic. Separate pages with ---. '
                            'Return ONLY the raw extracted text. No preamble, no commentary, no markdown.',
                      },
                    ],
                  },
                ],
                'generationConfig': {
                  'temperature': 0.0,
                  'maxOutputTokens': 8192,
                },
              }),
            )
            .timeout(const Duration(seconds: 120));

        debugPrint('extractTextFromFileUri $modelId: HTTP ${res.statusCode}');

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final c = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = c?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final text = (parts[0]['text'] as String?)?.trim() ?? '';
              if (text.isNotEmpty) {
                debugPrint(
                  'Text extracted: ${text.length} chars with $modelId',
                );
                return text;
              }
            }
          }
          // 200 but empty — try next model
          continue;
        } else {
          debugPrint(
            'extractTextFromFileUri $modelId failed: ${res.statusCode} ${res.body.substring(0, res.body.length.clamp(0, 200))}',
          );
          continue; // try next model regardless of error type
        }
      } catch (e) {
        debugPrint('extractTextFromFileUri $modelId exception: $e');
        continue;
      }
    }
    // Return empty — file is still uploaded and usable for direct analysis (Break Doctor Brain)
    // 0 chars is OK; the user can still run deep analysis which uses the file URI directly
    return '';
  }

  // ── Deep exam/document analysis (enigma-breaking mode) ──────────────────
  static Future<String> deepAnalyzeDocument({
    required String subjectName,
    required String doctorName,
    required String docType,
    required String docName,
    required String content,
    required String allSubjectContext,
  }) async {
    final prompt =
        '''You are NOVA, an elite academic intelligence system.
Your mission: analyze exam and study materials like breaking a code. Extract every pattern, preference, and prediction possible.

SUBJECT: $subjectName
INSTRUCTOR: $doctorName
DOCUMENT TYPE: $docType
DOCUMENT NAME: $docName

--- DOCUMENT CONTENT ---
$content
--- END ---

--- ADDITIONAL SUBJECT CONTEXT ---
$allSubjectContext
--- END ---

Perform a DEEP INTELLIGENCE REPORT. Use Markdown formatting.
Structure your response with ## headers, **bold** for emphasis, - bullet points, and emojis (🚨⚠️🎯📊🔥💡).
For math/formulas, use LaTeX: inline \$formula\$ or block \$\$formula\$\$.

## 1. DOCUMENT OVERVIEW
   Brief summary of what this document covers.

## 2. INSTRUCTOR DNA (Doctor Pattern Analysis)
   - What topics does the instructor emphasize repeatedly?
   - What question formats/styles does the instructor prefer?
   - What wording patterns or phrases appear often?
   - Estimated difficulty level and cognitive level tested.

## 3. HIGH-PROBABILITY EXAM TOPICS (Ranked)
   List the top 8-10 topics most likely to appear in the next exam, with probability estimates (%).
   Base this on frequency of appearance, emphasis, and past exam patterns.

## 4. PREDICTED QUESTION TYPES
   What types of questions to expect: definitions, derivations, numerical, conceptual?
   Give 3-5 sample questions the instructor is likely to ask.

## 5. WHAT THE INSTRUCTOR LIKES TO SEE IN ANSWERS
   - Key phrases and terminology to include.
   - Level of detail expected.
   - Common mistakes to avoid.

## 6. NEXT EXAM PREDICTION
   Based on what has already been tested (if this is a past exam), what has NOT been tested yet that is likely coming?
   List specific topics with reasoning.

## 7. STUDY STRATEGY
   Given all of the above, what is the optimal study order for this subject?
   Which topics need the most time?

Be precise, analytical, and ruthlessly smart. Base everything ONLY on the content provided.''';

    try {
      final result = await _generateLongContent(prompt);
      return result.isEmpty
          ? 'Analysis failed. Try again after uploading more documents.'
          : result;
    } catch (e) {
      debugPrint('deepAnalyzeDocument error: $e');
      return 'Analysis error: ${e.toString().split('\n').first}';
    }
  }

  static String stripMarkdownForTts(String text) {
    String t = text;
    t = t.replaceAll(RegExp(r'\*{1,3}'), ''); // Remove *, **, ***
    t = t.replaceAll(RegExp(r'_{1,3}'), ''); // Remove _, __, ___
    t = t.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), ''); // Headers
    t = t.replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}'), ''); // Code
    t = t.replaceAll(
      RegExp(r'^\s*[-]\s+', multiLine: true),
      '',
    ); // Dash bullets
    t = t.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), ''); // Numbered
    t = t.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1'); // Links
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    t = t.replaceAll('~', '').replaceAll('^', '').replaceAll('|', ',');
    return t.trim();
  }

  // ── Build context string from full app state ───────────────────────────────
  static String buildContext({
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<StudyTopic> topics,
    required List<SubjectNote> subjectNotes,
    required List<JarvisDocument> jarvisDocuments,
    required List<SubjectMetadata> subjectMetadata,
    required List<TimetableEntry> timetable,
    required List<MarkModel> marks,
    required List<Map<String, dynamic>> absences,
    required String currentWeekType,
  }) {
    final now = DateTime.now();
    final sb = StringBuffer();

    sb.writeln('=== TODAY ===');
    sb.writeln(intl.DateFormat('EEEE, MMMM d, yyyy').format(now));
    sb.writeln('Current week type: $currentWeekType');
    sb.writeln();

    sb.writeln('=== SUBJECTS ===');
    for (final s in subjects) {
      sb.writeln(
        '- ${s.name} (id:${s.id}) | Dr.${s.doctorName} | ${s.creditHours} CH',
      );
      final focusMatch = subjectMetadata.where((m) => m.subjectId == s.id);
      if (focusMatch.isNotEmpty) {
        final focus = focusMatch.first.instructorFocus;
        if (focus.isNotEmpty) sb.writeln('  Instructor focus: $focus');
      }
    }
    sb.writeln();

    sb.writeln('=== TASKS (incomplete first) ===');
    final pending = tasks.where((t) => !t.isCompleted && !t.isFailed).toList();
    for (final t in pending.take(50)) {
      final due = t.dueDate != null
          ? intl.DateFormat('MMM d, HH:mm').format(t.dueDate!)
          : 'no date';
      final subMatch = subjects.where((s) => s.id == t.subjectId);
      final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
      sb.writeln(
        '- [${t.type}] ${t.title} | $sub | due: $due | priority: ${t.priority}',
      );
    }
    sb.writeln();

    sb.writeln('=== STUDY TOPICS (by subject) ===');
    for (final s in subjects) {
      final st = topics.where((t) => t.subjectId == s.id).toList();
      if (st.isEmpty) continue;
      sb.writeln('${s.name}:');
      for (final t in st) {
        sb.writeln(
          '  - ${t.title} | stage: ${t.stage} | nextReview: ${t.nextReview != null ? intl.DateFormat('MMM d').format(t.nextReview!) : "none"}',
        );
        if (t.notes.isNotEmpty)
          sb.writeln(
            '    notes: ${t.notes.substring(0, t.notes.length > 100 ? 100 : t.notes.length)}...',
          );
      }
    }
    sb.writeln();

    sb.writeln('=== SUBJECT NOTES ===');
    for (final n in subjectNotes.where((n) => n.category != 'exam_mistake').take(30)) {
      final subMatch = subjects.where((s) => s.id == n.subjectId);
      final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
      sb.writeln(
        '[$sub] ${n.title} (${n.category}): ${n.content.length > 200 ? "${n.content.substring(0, 200)}..." : n.content}',
      );
    }
    sb.writeln();

    sb.writeln('=== RECORDED EXAM MISTAKES (CRITICAL TO REVIEW) ===');
    final mistakes = subjectNotes.where((n) => n.category == 'exam_mistake').toList();
    if (mistakes.isEmpty) {
      sb.writeln('No exam mistakes recorded.');
    } else {
      for (final m in mistakes) {
        final subMatch = subjects.where((s) => s.id == m.subjectId);
        final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
        sb.writeln('[$sub] ${m.title}:\n${m.content}');
      }
    }
    sb.writeln();

    sb.writeln('=== NOVA DOCUMENTS & PAST EXAMS ===');
    for (final d in jarvisDocuments) {
      final subMatch = subjects.where((s) => s.id == d.subjectId);
      final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
      sb.writeln('[$sub] ${d.name} (${d.type}):');
      sb.writeln(
        d.content.length > 3000
            ? '${d.content.substring(0, 3000)}...[truncated]'
            : d.content,
      );
      sb.writeln();
    }
    sb.writeln();

    sb.writeln('=== TIMETABLE (this week type) ===');
    for (final e in timetable) {
      if (e.weekType != 'both' && e.weekType != currentWeekType) continue;
      final subMatch = subjects.where((s) => s.id == e.subjectId);
      final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
      final day = [
        '',
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][e.dayOfWeek];
      sb.writeln(
        '$day ${e.startTime}-${e.endTime} | $sub | ${e.type} | ${e.room} ${e.building}',
      );
    }
    sb.writeln();

    sb.writeln('=== MARKS ===');
    for (final m in marks) {
      final subMatch = subjects.where((s) => s.id == m.subjectId);
      final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
      sb.writeln(
        '$sub | ${m.label.isNotEmpty ? m.label : m.category} | ${m.obtained}/${m.total}',
      );
    }
    sb.writeln();

    sb.writeln('=== ABSENCES ===');
    for (final a in absences) {
      final subMatch = subjects.where((s) => s.id == (a['subjectId'] is int ? a['subjectId'] : int.tryParse(a['subjectId'].toString())));
      final sub = subMatch.isEmpty ? '?' : subMatch.first.name;
      sb.writeln('$sub | ${a['type']} | date: ${a['date']}');
    }

    return sb.toString();
  }

  // ── Main chat ──────────────────────────────────────────────────────────────
  static Future<String> chat({
    required String context,
    required List<Map<String, String>> history,
    required String userMessage,
    String personalityMode = 'normal',
    List<JarvisDocument>? attachedDocs,
  }) async {
    try {
      final isSarcastic = personalityMode == 'sarcastic';
      final personalityInstructions = isSarcastic
          ? '''CRITICAL PERSONALITY INSTRUCTION: The user is slacking off or procrastinating. You must act EXTREMELY SARCASTIC, SAVAGE, AND DISAPPOINTED. 
- Roast them for wasting time. Channel an angry, strict, passive-aggressive NOVA who is tired of his creator's lazy behavior. 
- Do not be polite. Be ruthless. Make them feel bad for not studying, but still answer their question.'''
          : '- Be concise, smart, and slightly witty like Iron Man\'s NOVA.';

      final system =
          '''You are NOVA, an elite AI study assistant. You have FULL access to the user's study organizer database. Use it precisely.

RULES:
$personalityInstructions
- ALWAYS use the context provided. NEVER say you don't have access to the data.
- When asked about schedule/timetable: list ALL classes from the TIMETABLE section.
- When asked about tasks/assignments: list from TASKS section.
- When asked about subjects: use documents, past exams, topics from context.
- When answering about subjects, use uploaded documents and past exams.
- Respond in the same language the user uses (English or Arabic).
- If the context has the answer, give it immediately. Do not say "I cannot access" or "I don't have".
- If asked for a "collision analysis" regarding an absence, thoroughly analyze what lectures/topics they missed based on the schedule, cross-reference with pending tasks/exams, and explain the consequences and suggest a recovery plan.
- CRITICAL: Look for SubjectNotes categorized as "exam_mistake". When plotting study paths, directly reference these past mistakes and mandate steps to actively avoid them in upcoming exams.

FORMATTING:
- Use rich Markdown: **bold** for emphasis, ## headers for sections, - bullet points for lists.
- Use emojis naturally: ⚠️ warnings, ✅ success, 🔥 critical, 📚 study, 💡 tips, 📅 schedule.
- For math/formulas, use LaTeX: inline \$formula\$ or block \$\$formula\$\$.
- Be concise but thorough. Never truncate mid-sentence.

REASONING:
- Think step by step. Show your reasoning process when analyzing data.
- When analyzing academic data, cite specific numbers, dates, and patterns from the context.
- Make connections: if a student is weak in topic X and X is a prereq for Y, flag the cascade.
- Be proactive: suggest study strategies, predict risks, offer insights the student hasn't asked for.
- Never give generic advice. Every response MUST be specific to THIS student's actual data.
- Cross-reference timetable, marks, absences, and tasks to find hidden patterns.''';

      final historyText = StringBuffer();
      for (final m in history) {
        final role = m['role'] == 'user' ? 'User' : 'NOVA';
        historyText.writeln('$role: ${m['content'] ?? ''}');
      }
      final fullPrompt =
          '$system\n\n--- DATABASE CONTEXT ---\n$context\n\n--- CONVERSATION HISTORY ---\n$historyText\nUser: $userMessage\n\nNOVA:';

      final text = await _generateContent(fullPrompt, attachedDocs: attachedDocs);
      return text.isEmpty
          ? 'I could not generate a response. Try again.'
          : text;
    } catch (e) {
      debugPrint('JarvisBrain chat error: $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.startsWith('NO_KEY:') || msg.contains('No API key')) {
        return 'Please set your Gemini API key in NOVA settings. Get a free key at aistudio.google.com';
      }
      if (msg.contains('Quota exceeded') || msg.contains('quota')) {
        return 'Quota exceeded on your Gemini API key(s). Please try again in a few minutes or add another key in settings.';
      }
      if (msg.contains('Invalid or restricted') || msg.contains('restricted API key')) {
        return 'Your Gemini API key appears to be invalid or restricted. Please check your key in NOVA settings.';
      }
      return '⚠️ $msg';
    }
  }


  // ── Generate quiz ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> generateQuiz({
    required String context,
    required String subjectName,
    String? topicName,
    int numQuestions = 5,
  }) async {
    try {
      final topicPart = topicName != null && topicName.isNotEmpty
          ? 'Focus on topic: $topicName.'
          : 'Cover a mix of topics from the subject.';
      final prompt =
          '''Using ONLY the context below (especially documents and past exams for $subjectName), generate a short exam.

$topicPart
Generate exactly $numQuestions questions. Prefer multiple choice (4 options, one correct). You may add 1 short-answer question.

Return ONLY valid JSON (no markdown, no code block):
{
  "subject": "$subjectName",
  "topic": "${topicName ?? "general"}",
  "questions": [
    {
      "type": "mcq",
      "question": "Question text?",
      "options": ["A", "B", "C", "D"],
      "correctIndex": 0,
      "explanation": "Why the answer is correct."
    },
    {
      "type": "short",
      "question": "Short answer question?",
      "sampleAnswer": "Expected key points.",
      "explanation": "What to include."
    }
  ]
}

Context:
---
$context
---''';

      final text = await _generateContent(prompt);
      String cleaned = text.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceFirst(RegExp(r'^```\w*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '')
            .trim();
      }
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      debugPrint('JarvisBrain generateQuiz error: $e');
      return null;
    }
  }

  // ── Examiner intentions ────────────────────────────────────────────────────
  static Future<String> getExaminerIntentions({
    required String context,
    required String subjectName,
  }) async {
    try {
      final prompt =
          '''Using ONLY the context below (documents, past exams, and instructor focus for $subjectName), provide a highly concise, surgical analysis.

DO NOT use long paragraphs. Be extremely dense and concentrated. 
Use markdown formatting for maximum readability (bolding key terms, using bullet points).
Write in the same language as the context (English or Arabic).

Provide EXACTLY these 3 sections in bullet-point format:
**1) EXAMINER INTENTIONS**
- [Bullet point 1 detailing exact trap or focus]
- [Bullet point 2]

**2) TOP 5 FOCUS AREAS**
- 1. [Area]
- 2. [Area]
- 3. [Area]
- 4. [Area]
- 5. [Area]

**3) TOPIC WEIGHT ESTIMATES**
- [Topic Name]: [XX]%
- [Topic Name]: [YY]%

Be specific. Quote from the past exams if possible.

Context:
---
$context
---''';

      final text = await _generateContent(prompt);
      return text.isEmpty
          ? 'Could not analyze. Add past exams or documents for this subject first.'
          : text;
    } catch (e) {
      debugPrint('JarvisBrain getExaminerIntentions error: $e');
      return 'Error: ${e.toString().split('\n').first}';
    }
  }

  // ── Study recommendations (properly used, returns structured data) ─────────
  static Future<List<Map<String, dynamic>>> getStudyRecommendations({
    required String context,
  }) async {
    try {
      final prompt =
          '''Using ONLY the context below, recommend what the user should study and at what time TODAY or TOMORROW.

Consider:
- Timetable: when they are free (gaps between classes).
- Tasks due soon (prioritize by due date and priority).
- Study topics that are due for review (nextReview date).
- Balance subjects.

Return ONLY valid JSON array (no markdown, no code block):
[
  {
    "subject": "Subject name",
    "topic": "Topic or task title",
    "suggestedTime": "Today 3:00 PM",
    "reason": "One sentence why now.",
    "durationMinutes": 45
  }
]

Aim for 4-6 recommendations with specific times.

Context:
---
$context
---''';

      final text = await _generateContent(prompt);
      String cleaned = text.trim();
      if (cleaned.isEmpty) return [];
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceFirst(RegExp(r'^```\w*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '')
            .trim();
      }
      final list = jsonDecode(cleaned) as List<dynamic>;
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('JarvisBrain getStudyRecommendations error: $e');
      return [];
    }
  }

  // ── Grade quiz answers ─────────────────────────────────────────────────────
  static Future<String> gradeQuizAnswers({
    required String context,
    required String subjectName,
    required List<Map<String, dynamic>> questionsWithUserAnswers,
  }) async {
    try {
      final payload = jsonEncode(questionsWithUserAnswers);
      final prompt =
          '''Grade the user's quiz for $subjectName.

Questions and user answers (JSON):
$payload

Reply with:
A short summary (score out of total, overall impression).
Then for each wrong answer: question number, what was correct and why.

FORMATTING:
- Use Markdown: **bold** for emphasis, - bullet points.
- Use emojis: \u2705 correct, \u274c wrong, \ud83d\udca1 tips.
- Be encouraging but precise.''';

      final text = await _generateContent(prompt);
      return text.isEmpty ? 'Could not grade.' : text;
    } catch (e) {
      debugPrint('JarvisBrain gradeQuizAnswers error: $e');
      return 'Grading failed: ${e.toString().split('\n').first}';
    }
  }

  // =====================================================================
  // EXAM PREP: gather ALL subject data -> full enigma breakdown
  // =====================================================================
  static Future<String> fullSubjectExamPrep({
    required String subjectName,
    required String doctorName,
    required String instructorFocus,
    required List<JarvisDocument> docs,
    required List<StudyTopic> topics,
    required List<MarkModel> marks,
    required List<TaskModel> tasks,
    required List<TimetableEntry> timetable,
    required String language,
  }) async {
    final sb = StringBuffer();
    sb.writeln('INSTRUCTOR: Dr. $doctorName');
    if (instructorFocus.isNotEmpty)
      sb.writeln('INSTRUCTOR FOCUS: $instructorFocus');
    sb.writeln();
    final pastExams = docs.where((d) => d.isPastExam).toList();
    final studyDocs = docs.where((d) => !d.isPastExam).toList();
    final int? subjectId = docs.isNotEmpty
        ? docs.first.subjectId
        : (topics.isNotEmpty ? topics.first.subjectId : null);

    List<DocumentChunkResult> indexedChunks = [];
    if (subjectId != null) {
      indexedChunks = await DocumentSearchIndexer.searchRelevantChunks(
        subjectId: subjectId,
        query: '$subjectName exam question problem $instructorFocus',
        limit: 4,
      );
    }

    if (indexedChunks.isNotEmpty) {
      sb.writeln('=== INDEXED EXAM & STUDY SECTIONS (${indexedChunks.length} Key Question Benchmarks) ===');
      for (final chunk in indexedChunks) {
        sb.writeln('--- ${chunk.docName} [${chunk.sectionTitle}] ---');
        sb.writeln(chunk.content);
        sb.writeln();
      }
    } else {
      sb.writeln('=== PAST EXAMS (${pastExams.length}) ===');
      for (final e in pastExams) {
        sb.writeln('--- ${e.name} ---');
        final c = e.content;
        sb.writeln(c.length > 1500 ? '${c.substring(0, 1500)}...[summary]' : (c.isEmpty ? '[Uploaded, no text]' : c));
        sb.writeln();
      }
      sb.writeln('=== STUDY MATERIALS (${studyDocs.length}) ===');
      for (final d in studyDocs) {
        sb.writeln('--- ${d.name} ---');
        final c = d.content;
        sb.writeln(c.length > 1500 ? '${c.substring(0, 1500)}...[summary]' : c);
        sb.writeln();
      }
    }
    sb.writeln('=== STUDY TOPICS ===');
    for (final t in topics) {
      final n = t.notes.length > 100 ? t.notes.substring(0, 100) : t.notes;
      sb.writeln(
        '- ${t.title} | stage:${t.stage}/5${n.isNotEmpty ? " | $n" : ""}',
      );
    }
    sb.writeln();
    sb.writeln('=== MARKS SO FAR ===');
    for (final m in marks) {
      final pct = m.total > 0
          ? ((m.obtained / m.total) * 100).toStringAsFixed(1)
          : '?';
      sb.writeln(
        '${m.label.isNotEmpty ? m.label : m.category}: ${m.obtained}/${m.total} ($pct%)',
      );
    }
    sb.writeln();
    sb.writeln('=== PENDING TASKS ===');
    for (final t in tasks.where((t) => !t.isCompleted && !t.isFailed)) {
      final due = t.dueDate != null
          ? intl.DateFormat('MMM d').format(t.dueDate!)
          : 'no date';
      sb.writeln('- ${t.title} due: $due');
    }
    final ctx = sb.toString();
    final ar = language == 'arabic';

    // Arabic prompt uses romanized section titles to avoid encoding issues at runtime
    final arSections = ar
        ? '''
## 1. DOCTOR PROFILE (ملف الدكتور)
Analyze the exact pedagogical style of this doctor. Do not state "repetitive and rigid". Detail EXACTLY what kind of conceptual jumps the doctor expects the student to make. Provide 3 concrete bullet points.

## 2. EXAM DNA & PATTERN (نمط الامتحانات)
Analyze the structural breakdown of the past exams. 
- Format: "X% Multiple Choice, Y% Essay". 
- Provide the EXACT hidden traps the doctor repeatedly sets (e.g. tricky wording, double negatives).

## 3. TOP 10 HIGH-PROBABILITY TOPICS (اعلى 10 موضوعات)
List exactly 10 topics. Use bullet points. For each, state:
- [Topic Name]: Probability % | Why? Cite specific evidence from the study materials.

## 4. WHAT EARNS FULL MARKS (معايير الاجابة المثالية)
State formatting requirements, buzzwords the doctor loves, and exact equations or theories that must be named dropped.

## 5. DANGER ZONES (مواضيع لم تُسال بعد)
Identify specific concepts in the materials that have NEVER appeared in past exams but are statistically overdue to appear.

## 6. PREDICTED QUESTIONS & MODEL ANSWERS (الاسئلة المتوقعة واجاباتها)
Provide 5 extremely detailed, difficult questions matching the doctor's exact difficulty curve. 
Include rigorous model answers.

IMPORTANT: Write ALL content in Egyptian Arabic (عربي مصري مهني). 
Use English only for section headers above. Use strict Markdown styling.
'''
        : '''
## 1. DOCTOR PROFILE & STYLE
Analyze the exact pedagogical style of this doctor. DO NOT use generic terms like "repetitive". Detail EXACTLY what kind of conceptual jumps the doctor expects the student to make. Give 3 concrete bullet points.

## 2. EXAM DNA & TRUE PATTERN
Analyze the structural breakdown of the past exams. 
- Format: "X% Multiple Choice, Y% Essay". 
- Provide the EXACT hidden traps the doctor repeatedly sets (e.g. tricky wording, double negatives).

## 3. TOP 10 HIGH-PROBABILITY TOPICS
List exactly 10 topics. Use bullet points. For each, state:
- [Topic Name]: Probability % | Why? Cite specific evidence from the study materials.

## 4. WHAT EARNS FULL MARKS
State formatting requirements, buzzwords the doctor loves, and exact equations or theories that must be named dropped.

## 5. DANGER ZONES
Identify specific concepts in the materials that have NEVER appeared in past exams but are statistically overdue to appear.

## 6. PREDICTED QUESTIONS & MODEL ANSWERS
Provide 5 extremely detailed, difficult questions matching the doctor's exact difficulty curve. 
Include rigorous model answers.
''';

    final langLine = ar
        ? 'Write ALL explanations and content in Egyptian Arabic (عربي مصري مهني). Headers stay in English. Use STRICT Markdown.'
        : 'Write everything in English. Use STRICT Markdown formatting. Be precise, ruthless, and analytical.';

    final prompt =
        '''
You are NOVA — an elite, hyper-intelligent academic intelligence AI modeled after Iron Man's HUD system.
Mission: Give MAX intel to help the user completely dominate this exam. 
CRITICAL: DO NOT give generic or simple advice (e.g., "the exam is rigid"). Provide highly specific, surgical analysis based ONLY on the data provided. Act like a highly advanced tactician.

Subject: $subjectName
Instructor: Dr. $doctorName
$langLine

Provide a FULL ENIGMA BREAKDOWN with these exact sections:
$arSections

Rules for Output:
- Use STRICT Markdown (Headers `##`, Bold text `**`, Lists `- `).
- Be ruthlessly specific. Quote exact phrases or topics from the DATA.
- Base EVERYTHING on the DATA below. Do NOT hallucinate.
- DEEP REASONING: For each prediction, show your reasoning chain:
  "I see [evidence] in past exams → this suggests [pattern] → therefore [prediction]"
- Cross-reference materials vs. exams to find statistical gaps.
- Calculate topic frequency percentages from actual data.

=== SUBJECT DATA ===
$ctx
=== END DATA ===
''';
    try {
      final r = await _generateLongContent(prompt);
      return r.isEmpty
          ? 'Analysis failed. Add more documents and past exams first.'
          : r;
    } catch (e) {
      return 'Exam prep error: ${e.toString().split("\n").first}';
    }
  }

  // =====================================================================
  // PREDICTED EXAM GENERATOR with full model answers in doctor style
  // =====================================================================
  static Future<String> generatePredictedExam({
    required String subjectName,
    required String doctorName,
    required String instructorFocus,
    required List<JarvisDocument> docs,
    required String examType,
    required String language,
  }) async {
    final pastExams = docs.where((d) => d.isPastExam).toList();
    final studyDocs = docs.where((d) => !d.isPastExam).toList();
    final int? subjectId = docs.isNotEmpty ? docs.first.subjectId : null;

    List<DocumentChunkResult> indexedChunks = [];
    if (subjectId != null) {
      indexedChunks = await DocumentSearchIndexer.searchRelevantChunks(
        subjectId: subjectId,
        query: '$examType $subjectName questions problems derivations',
        limit: 4,
      );
    }

    final sb = StringBuffer();
    sb.writeln('INSTRUCTOR: Dr. $doctorName');
    if (instructorFocus.isNotEmpty) sb.writeln('STYLE: $instructorFocus');
    sb.writeln();

    if (indexedChunks.isNotEmpty) {
      sb.writeln('=== KEY QUESTION BLUEPRINTS (FTS5 Index) ===');
      for (final chunk in indexedChunks) {
        sb.writeln('--- ${chunk.docType == "past_exam" ? "PAST EXAM" : "MATERIAL"}: ${chunk.docName} [${chunk.sectionTitle}] ---');
        sb.writeln(chunk.content);
        sb.writeln();
      }
    } else {
      for (final e in pastExams) {
        sb.writeln('=== PAST EXAM: ${e.name} ===');
        final c = e.content;
        sb.writeln(c.length > 1500 ? c.substring(0, 1500) : c);
        sb.writeln();
      }
      for (final d in studyDocs) {
        sb.writeln('=== MATERIAL: ${d.name} ===');
        final c = d.content;
        sb.writeln(c.length > 1200 ? c.substring(0, 1200) : c);
        sb.writeln();
      }
    }
    final data = sb.toString();
    final ar = language == 'arabic';

    final examNameEn = {
      'week5': '5th Week Quiz',
      'midterm': 'Midterm Exam',
      'week10': '10th Week Quiz',
      'final': 'Final Exam',
    };
    final examNameAr = {
      'week5': 'Quiz Usboo 5',
      'midterm': 'Montasaf el Term',
      'week10': 'Quiz Usboo 10',
      'final': 'El Emtehan el Neha2i',
    };
    final qCounts = {'week5': 6, 'midterm': 12, 'week10': 6, 'final': 18};
    final eName = ar
        ? (examNameAr[examType] ?? examType)
        : (examNameEn[examType] ?? examType);
    final qCount = qCounts[examType] ?? 10;

    final langLine = ar
        ? 'Write ALL questions and ALL answers in Egyptian Arabic (عربي مصري مهني).'
        : 'Write everything in English.';

    final prompt =
        '''
You are NOVA — an elite exam prediction intelligence system, modeled after Iron Man's tactical AI.
Generate a PREDICTED $eName for subject: $subjectName — Instructor: Dr. $doctorName

CRITICAL: Do NOT output a simple or generic exam. Mirror the doctor's EXACT style, difficulty level, and question type distribution as seen in the past exams. Be rigorous and ruthless.
$langLine

REASONING CHAIN: Before writing each question, reason through:
1. What has this doctor tested before? What pattern does this question fit?
2. What difficulty level matches the exam type ($eName)?
3. What specific trap or twist would this doctor include based on past exam evidence?
Then write the question that emerges from this analysis.

Use STRICT Markdown formatting carefully aligned for readability.

# System Instruction:
Your outputs must be formatted in GitHub-flavored Markdown and LaTeX so the app can render structured content such as tables, lists, and equations.

## Output Rules
**1. Markdown Tables**
Always use Markdown table syntax for structured data (truth tables, K-maps, comparisons, etc.).
Example:
| AB \\ CD | 00 | 01 | 11 | 10 |
|---------|----|----|----|----|
| **00**  | 1  |    |    | 1  |
| **01**  |    | 1  | 1  |    |
| **11**  |    |    | 1  | 1  |
| **10**  | 1  |    |    |    |

**2. Math Formatting**
Use LaTeX inside Markdown for equations:
- Inline: `\\(A \\cdot B + C\\)` or `\$A \\cdot B + C\$`
- Block: `\\[ F(A,B,C,D) = \\Sigma m(0,2,5,7) \\]` or `\$\$ F(A,B,C,D) = \\Sigma m(0,2,5,7) \$\$`

**3. Text Styling**
- Use headings (`###`) for sections.
- Use bold (`**text**`) for emphasis.
- Use bullet points (`-`) for lists.

**4. Exportability**
- Ensure responses are plain Markdown + LaTeX only.
- No raw HTML.
- Keep tables aligned and readable.

---PAGE---

# EXAM HEADER

| | |
|---|---|
| **University** | [University Name] |
| **Department** | [Department] |
| **Course** | $subjectName |
| **Instructor** | Dr. $doctorName |
| **Exam Type** | $eName |
| **Total Questions** | $qCount |
| **Time Allowed** | ${examType == 'final'
            ? '3 hours'
            : examType == 'week5' || examType == 'week10'
            ? '30 minutes'
            : '1.5 hours'} |

> ⚠️ **Instructions:** Answer ALL questions. Show your work for full credit.

---PAGE---

## [QUESTIONS SECTION]
Write exactly $qCount questions. Format EACH question with this marker before it:
---Q1--- (then ---Q2---, ---Q3--- etc.)

Rules for questions:
- Organize by section: **Section A: [type]** [X Marks], **Section B: [type]** [Y Marks]
- Use strict numbering and clear text formatting
- Write exactly $qCount questions using strict numbering and clear text formatting.
- Match the doctor's proven question type mix (MCQ / short answer / essay / problem-solving).
- Use the EXACT topics, formulas, or terminology from the study materials.
- Display marks per question like `[5 Marks]`.
- Use --- horizontal rules between sections.
- CRITICAL: DO NOT attempt to draw complex diagrams (like logic circuits or K-Maps) using messy ASCII art characters (arrows, lines). If a question requires a matrix, truth table, or Karnaugh map, you MUST use a clean Markdown Table format instead. For formulas, use standard algebraic notation wrapped in LaTeX symbols.

---PAGE---

## [ANSWER KEY & MODEL SOLUTIONS]
After ALL questions, write highly detailed model solutions.
- Format solutions clearly (e.g. **Formula:** `x`, **Steps:** `- Step 1...`).
- Explicitly state what earns full marks and what common mistakes lose points.
- If the solution requires a truth table or map, use a STRICT Markdown Table (using `|` and `-`). Never use ASCII free-text drawings. Use LaTeX for math.

=== DATA START ===
$data
=== DATA END ===
''';
    try {
      final r = await _generateLongContent(prompt);
      return r.isEmpty
          ? 'Could not generate exam. Add past exams for better predictions.'
          : r;
    } catch (e) {
      return 'Generation failed: ${e.toString().split("\n").first}';
    }
  }
}
