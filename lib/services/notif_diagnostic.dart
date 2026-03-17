import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/notifications.dart';
import '../bloc/app_bloc.dart';

class NotifDiagnosticPage extends StatefulWidget {
  const NotifDiagnosticPage({super.key});
  @override
  State<NotifDiagnosticPage> createState() => _NotifDiagnosticPageState();
}

class _NotifDiagnosticPageState extends State<NotifDiagnosticPage> {
  String _log = 'Tap a button to start...';
  bool _running = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadExistingLog();
  }

  Future<void> _loadExistingLog() async {
    final log = await NotifDiag.readAll();
    if (mounted) setState(() => _log = log);
    _scrollToBottom();
  }

  Future<void> _runDiagnostic({bool withTestNotif = false}) async {
    setState(() {
      _running = true;
      _log = 'Running...';
    });

    final state = context.read<AppBloc>().state;
    final subjectNames = <int, String>{};
    for (final s in state.subjects) {
      if (s.id != null) subjectNames[s.id!] = s.name;
    }

    await NotifDiag.runFull(
      entries: state.timetable,
      subjectNames: subjectNames,
      currentWeekType: state.currentWeekType,
      scheduleTestNotif: withTestNotif,
    );

    await _loadExistingLog();
    if (mounted) setState(() => _running = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121A),
        title: const Text(
          '🔬 Notification Diagnostics',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white54),
            tooltip: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _log));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
            tooltip: 'Clear log',
            onPressed: () async {
              await NotifDiag.clear();
              if (mounted) setState(() => _log = '(cleared)');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Buttons ────────────────────────────────────────────────────────
          Container(
            color: const Color(0xFF12121A),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : () => _runDiagnostic(),
                        icon: _running
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.search_rounded),
                        label: const Text('CHECK EVERYTHING'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _running
                            ? null
                            : () => _runDiagnostic(withTestNotif: true),
                        icon: const Icon(
                          Icons.notifications_active_rounded,
                          size: 18,
                        ),
                        label: const Text('CHECK + TEST'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2ED573),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _running ? null : _loadExistingLog,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('RELOAD LOG FROM DISK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Legend ─────────────────────────────────────────────────────────
          Container(
            color: const Color(0xFF0D0D15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: const [
                Text(
                  '✅ OK  ',
                  style: TextStyle(color: Color(0xFF2ED573), fontSize: 11),
                ),
                Text(
                  '❌ ERROR',
                  style: TextStyle(color: Color(0xFFFF4757), fontSize: 11),
                ),
                Spacer(),
                Text(
                  'newest at bottom',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
          // ── Log viewer ─────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _log,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}