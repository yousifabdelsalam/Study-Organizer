// nova_settings_page.dart — All NOVA settings in one place
// Home location, daily check-ins, distraction watchdog.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/services/NovaElevenLabsService.dart';
import '../services/nova_location_service.dart';
import '../services/nova_watchdog_service.dart';
import '../services/notifications.dart';
import '../services/jarvis_brain_service.dart';
import '../services/jarvis_service.dart';

class NovaSettingsPage extends StatefulWidget {
  const NovaSettingsPage({super.key});
  @override
  State<NovaSettingsPage> createState() => _NovaSettingsPageState();
}

class _NovaSettingsPageState extends State<NovaSettingsPage> {
  // ── Location ──
  bool _homeSet = false;
  bool _savingHome = false;
  bool _elevenLabsEnabled = false;
  bool _testingVoice = false;
  String? _voiceTestError;

  // ── Check-in slots (up to 3) ──
  final List<TimeOfDay?> _checkins = [
    const TimeOfDay(hour: 7, minute: 0), // morning
    const TimeOfDay(hour: 14, minute: 0), // afternoon
    null, // evening (off)
  ];
  final List<bool> _checkinEnabled = [true, true, false];

  // ── Watchdog ──
  List<Map<String, dynamic>> _watchedApps = [];
  bool _watchdogEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await NovaLocationService.checkHomeSet();
    final apps = await NovaWatchdogService.getWatchedApps();
    final prefs = await SharedPreferences.getInstance();
    _elevenLabsEnabled = await NovaElevenLabsService.isEnabled();
    if (mounted) {
      setState(() {
        _homeSet = NovaLocationService.hasHomeSet;
        _watchedApps = apps;
        _watchdogEnabled = apps.isNotEmpty;

        for (int i = 0; i < 3; i++) {
          final en = prefs.getBool('nova_checkin_en_$i');
          if (en != null) _checkinEnabled[i] = en;
          final hh = prefs.getInt('nova_checkin_h_$i');
          final mm = prefs.getInt('nova_checkin_m_$i');
          if (hh != null && mm != null) {
            _checkins[i] = TimeOfDay(hour: hh, minute: mm);
          } else if (en == false) {
            _checkins[i] = null;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12122A),
        title: const Row(
          children: [
            Icon(Icons.psychology_rounded, color: Color(0xFF39FF14), size: 22),
            SizedBox(width: 8),
            Text(
              'NOVA Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('🔑 Cloud AI Integrations'),
          _apiKeysCard(),
          const SizedBox(height: 16),
          _sectionHeader('🎙️ NOVA Voice (ElevenLabs)'),
          _elevenLabsCard(),
          const SizedBox(height: 16),
          _sectionHeader('🛡️ Distraction Guard'),
          _watchdogCard(),
        ],
      ),
    );
  }

  Widget _elevenLabsCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enable toggle
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use ElevenLabs AI Voice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Replaces robot TTS with your custom NOVA/Jarvis voice.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _elevenLabsEnabled,
                onChanged: (v) async {
                  await NovaElevenLabsService.setEnabled(v);
                  if (mounted)
                    setState(() {
                      _elevenLabsEnabled = v;
                      _voiceTestError = null;
                    });
                },
                activeColor: const Color(0xFF39FF14),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // API Key field
          _apiKeyRow('ElevenLabs API Key', 'elevenlabs_api_key'),
          const SizedBox(height: 8),

          // Voice ID field
          _apiKeyRow('Voice ID', 'elevenlabs_voice_id'),

          const SizedBox(height: 6),
          // How to find voice ID hint
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2139),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '📋 How to find your Voice ID:\n'
              '1. Go to elevenlabs.io → My Voices\n'
              '2. Click your Jarvis/NOVA voice\n'
              '3. Copy the ID shown below the voice name\n'
              '   (looks like: AbCdEfGhIj1234)\n\n'
              '🔑 API Key: elevenlabs.io → Profile → API Key\n'
              '   (starts with "sk_...")',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Voice settings info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.auto_fix_high_rounded,
                  color: Color(0xFF9D97FF),
                  size: 14,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Model: eleven_turbo_v2_5 — lowest latency for real-time chat.\n'
                    'Stability: 0.4 | Similarity: 0.9 — tuned for NOVA/Jarvis style.',
                    style: TextStyle(
                      color: Color(0xFF9D97FF),
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Test button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _elevenLabsEnabled
                    ? const Color(0xFF39FF14).withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
                foregroundColor: _elevenLabsEnabled
                    ? const Color(0xFF39FF14)
                    : Colors.white38,
                side: BorderSide(
                  color: _elevenLabsEnabled
                      ? const Color(0xFF39FF14).withOpacity(0.5)
                      : Colors.white12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _testingVoice
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF39FF14),
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_testingVoice ? 'Testing...' : 'Test NOVA Voice'),
              onPressed: (_elevenLabsEnabled && !_testingVoice)
                  ? _testVoice
                  : null,
            ),
          ),

          if (_voiceTestError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _voiceTestError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── ADD _testVoice() method ───────────────────────────────────────────────────
  Future<void> _testVoice() async {
    setState(() {
      _testingVoice = true;
      _voiceTestError = null;
    });
    final error = await NovaElevenLabsService.testConnection();
    if (mounted) {
      setState(() {
        _testingVoice = false;
        _voiceTestError = error;
      });
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ NOVA voice is working!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF1A3A1A),
          ),
        );
      }
    }
  }

  // ── API Keys Card ────────────────────────────────────────────────────────
  Widget _apiKeysCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect NOVA to the cloud. Gemini provides deep analysis, Groq provides fast voice transcription.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _apiKeyRow('Groq API Key (Voice)', 'groq_api_key'),
          const SizedBox(height: 8),
          _apiKeyRow('Gemini API Key (Analysis)', 'gemini_api_key_0'),
        ],
      ),
    );
  }

  Widget _apiKeyRow(String label, String prefKey) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () => _editApiKey(label, prefKey),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF39FF14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            backgroundColor: const Color(0xFF39FF14).withOpacity(0.1),
          ),
          child: const Text('Edit Key'),
        ),
      ],
    );
  }

  Future<void> _editApiKey(String label, String prefKey) async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(text: prefs.getString(prefKey) ?? '');

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        title: Text('Edit $label', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Paste API key here',
            hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF39FF14)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              final newKey = ctrl.text.trim();
              if (prefKey.startsWith('gemini')) {
                await JarvisBrainService.setApiKey(newKey);
              } else if (prefKey == 'groq_api_key') {
                await JarvisService.setGroqKey(newKey);
              } else {
                await prefs.setString(prefKey, newKey);
              }

              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ $label saved',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF1A3A1A),
                  ),
                );
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: Color(0xFF39FF14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Watchdog Card ─────────────────────────────────────────────────────────
  Widget _watchdogCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Track daily time on distracting apps and get alerted when you\'ve gone over.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              Switch(
                value: _watchdogEnabled,
                onChanged: (v) async {
                  setState(() => _watchdogEnabled = v);
                  if (v) {
                    await NovaWatchdogService.startWatchdog();
                  } else {
                    await NovaWatchdogService.stopWatchdog();
                  }
                },
                activeColor: const Color(0xFF39FF14),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Requires "Usage Access" permission: Settings → Apps → Special App Access → Usage Access → Study Organizer → Allow',
                    style: TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._watchedApps.map((app) => _appRow(app)),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(
              Icons.add_circle_outline,
              color: Color(0xFF6C63FF),
            ),
            label: const Text(
              'Add App',
              style: TextStyle(color: Color(0xFF6C63FF)),
            ),
            onPressed: _showAddAppSheet,
          ),
        ],
      ),
    );
  }

  Widget _appRow(Map<String, dynamic> app) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.smartphone_rounded, color: Colors.white38, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app['name'] as String,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  app['package'] as String,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Text(
              '${app['limitMinutes']} min',
              style: const TextStyle(color: Colors.orange, fontSize: 11),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              color: Colors.redAccent,
              size: 20,
            ),
            onPressed: () async {
              await NovaWatchdogService.removeApp(app['package'] as String);
              final apps = await NovaWatchdogService.getWatchedApps();
              if (mounted) setState(() => _watchedApps = apps);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAppSheet() async {
    final pkgCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '30');
    String? selectedPreset;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12122A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: StatefulBuilder(
          builder: (_, ss) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add App to Watch',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick add:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kCommonDistractors.map((d) {
                  final sel = selectedPreset == d['package'];
                  return GestureDetector(
                    onTap: () {
                      ss(() => selectedPreset = d['package']);
                      pkgCtrl.text = d['package']!;
                      nameCtrl.text = d['name']!;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFF6C63FF).withOpacity(0.3)
                            : const Color(0xFF1E2139),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? const Color(0xFF6C63FF) : Colors.white12,
                        ),
                      ),
                      child: Text(
                        d['name']!,
                        style: TextStyle(
                          color: sel ? const Color(0xFF9D97FF) : Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'App name',
                  labelStyle: TextStyle(color: Colors.white38),
                ),
              ),
              TextField(
                controller: pkgCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Package (e.g. com.instagram.android)',
                  labelStyle: TextStyle(color: Colors.white38),
                ),
              ),
              TextField(
                controller: limitCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Daily limit (minutes)',
                  labelStyle: TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final pkg = pkgCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    final limit = int.tryParse(limitCtrl.text) ?? 30;
                    if (pkg.isEmpty || name.isEmpty) return;
                    await NovaWatchdogService.addApp(pkg, name, limit);
                    final apps = await NovaWatchdogService.getWatchedApps();
                    if (mounted) setState(() => _watchedApps = apps);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text(
                    'Add App',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF12122A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
    ),
    child: child,
  );
}
