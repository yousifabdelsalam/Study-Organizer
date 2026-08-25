// ai_service.dart — legacy service kept for compatibility
// NOTE: For new features, use JarvisBrainService instead.
// This service is kept only for any remaining legacy usages.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';

class AIService {
  static Future<String?> _getGroqKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('groq_api_key');
  }

  static Future<String> getChatResponse({
    required List<Map<String, String>> history,
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<MarkModel> marks,
  }) async {
    try {
      // Try user-saved key first, fall back to the default key
      final savedKey = await _getGroqKey();
      final groqKey = (savedKey != null && savedKey.isNotEmpty)
          ? savedKey
          : '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';
      if (groqKey.isEmpty) {
        return 'Set your Groq API key in NOVA settings to use this feature.';
      }

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $groqKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {
              'role': 'system',
              'content': 'You are NOVA, an elite Engineering study assistant. Be technical, concise, and helpful. You have access to the user\'s grades and tasks.'
            },
            ...history,
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      }
      return 'Connection issue. Status: ${response.statusCode}';
    } catch (e) {
      return 'Connection lost. Check your internet connection.';
    }
  }
}