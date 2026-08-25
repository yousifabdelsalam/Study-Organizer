import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/subjects/data/models/topic.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_audio_service.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/utils/helpers.dart';
import 'package:study_organizer/features/exams/presentation/widgets/layering_system_overlay.dart';

class TopicsPage extends StatefulWidget {
  const TopicsPage({super.key});
  @override
  State<TopicsPage> createState() => _TopicsPageState();
}

class _TopicsPageState extends State<TopicsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int? _filterSubjectId; // null = all subjects

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // 🔊 Warn on open if there are overdue topics
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppBloc>().state;
      final now = DateTime.now();
      final overdueCount = state.topics.where((t) =>
        !t.isMastered &&
        t.nextReview != null &&
        t.nextReview!.isBefore(now)
      ).length;
      if (overdueCount >= 3) {
        NovaAudioService.playAsset('sounds/warning_a_study_topic_is_now_officially_overdue.mp3');
      } else if (overdueCount >= 1) {
        NovaAudioService.playAsset('sounds/study_topic_will_be_overdue_soon.mp3');
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Topics'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFF6C63FF),
          labelColor: const Color(0xFF6C63FF),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.flash_on_rounded), text: 'Due Today'),
            Tab(icon: Icon(Icons.list_alt_rounded), text: 'All Topics'),
            Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Progress'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddTopic(context),
            tooltip: 'Add Topic',
          ),
        ],
      ),
      body: BlocBuilder<AppBloc, AppState>(
        builder: (ctx, state) {
          return Column(
            children: [
              // ── Subject filter strip ────────────────────────────────────────
              if (state.subjects.isNotEmpty)
                _subjectFilterStrip(state.subjects, dark),

              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _dueTab(ctx, state, dark),
                    _allTab(ctx, state, dark),
                    _progressTab(ctx, state, dark),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_topics',
        onPressed: () => _showAddTopic(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Topic'),
      ),
    );
  }

  // ── Subject filter ────────────────────────────────────────────────────────
  Widget _subjectFilterStrip(List<Subject> subjects, bool dark) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: subjects.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            final sel = _filterSubjectId == null;
            return GestureDetector(
              onTap: () => setState(() => _filterSubjectId = null),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0xFF6C63FF)
                      : const Color(0xFF6C63FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'All',
                  style: TextStyle(
                    color: sel ? Colors.white : const Color(0xFF6C63FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          final sub = subjects[i - 1];
          final sel = _filterSubjectId == sub.id;
          return GestureDetector(
            onTap: () => setState(() => _filterSubjectId = sel ? null : sub.id),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: sel
                    ? Color(sub.color)
                    : Color(sub.color).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                sub.name,
                style: TextStyle(
                  color: sel ? Colors.white : Color(sub.color),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 — DUE TODAY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _dueTab(BuildContext ctx, AppState state, bool dark) {
    final due = _filtered(state).where((t) => t.isDueToday).toList();

    if (due.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF2ED573).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2ED573),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'All caught up! 🎉',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'No topics due today',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final Map<int, List<StudyTopic>> grouped = {};
    for (final t in due) {
      grouped.putIfAbsent(t.subjectId, () => []).add(t);
    }

    final listChildren = <Widget>[];
    grouped.forEach((subjectId, topics) {
      final subject = state.subjects.firstWhere(
        (s) => s.id == subjectId,
        orElse: () => const Subject(name: 'Unknown'),
      );

      listChildren.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                color: Color(subject.color),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                subject.name,
                style: TextStyle(
                  color: Color(subject.color),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );

      for (final t in topics) {
        listChildren.add(_topicCard(ctx, t, state, true));
      }
    });

    return Column(
      children: [
        // Due count banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF6C63FF).withOpacity(0.8),
                const Color(0xFF9D97FF).withOpacity(0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.flash_on_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                '${due.length} topic${due.length == 1 ? '' : 's'} to review today',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 80),
            children: listChildren,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2 — ALL TOPICS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _allTab(BuildContext ctx, AppState state, bool dark) {
    final topics = _filtered(state)
      ..sort((a, b) {
        // Sort: overdue first, then by nextReview
        if (a.isDueToday && !b.isDueToday) return -1;
        if (!a.isDueToday && b.isDueToday) return 1;
        if (a.nextReview != null && b.nextReview != null) {
          return a.nextReview!.compareTo(b.nextReview!);
        }
        return a.title.compareTo(b.title);
      });

    if (topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_rounded,
              size: 56,
              color: Colors.grey.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            const Text(
              'No topics yet',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Add topics to track your spaced repetition',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80, top: 8),
      itemCount: topics.length,
      itemBuilder: (_, i) => _topicCard(ctx, topics[i], state, false),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3 — PROGRESS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _progressTab(BuildContext ctx, AppState state, bool dark) {
    final topics = _filtered(state);
    if (topics.isEmpty) {
      return const Center(
        child: Text('No topics yet', style: TextStyle(color: Colors.grey)),
      );
    }

    final stageCounts = List.filled(6, 0);
    for (final t in topics) {
      stageCounts[t.stage.clamp(0, 5)]++;
    }

    final mastered = stageCounts[5];
    final due = topics.where((t) => t.isDueToday).length;
    final total = topics.length;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // ── Overview cards ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Total',
                '$total',
                Icons.library_books_rounded,
                const Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                'Due Today',
                '$due',
                Icons.flash_on_rounded,
                const Color(0xFFFF9F43),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                'Mastered',
                '$mastered',
                Icons.auto_awesome_rounded,
                const Color(0xFF2ED573),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Stage breakdown ────────────────────────────────────────────────
        Glass(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stage Breakdown',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 14),
              ...List.generate(6, (stage) {
                final count = stageCounts[stage];
                final frac = total > 0 ? count / total : 0.0;
                final colors = [
                  Colors.grey,
                  const Color(0xFF6C63FF),
                  const Color(0xFF1E90FF),
                  const Color(0xFFFF9F43),
                  const Color(0xFFFF6B81),
                  const Color(0xFF2ED573),
                ];
                final labels = [
                  'New',
                  'Seen once',
                  'Reviewed',
                  'Familiar',
                  'Well known',
                  'Mastered',
                ];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          labels[stage],
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 10,
                            backgroundColor: colors[stage].withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation(colors[stage]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text(
                          '$count',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors[stage],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Per-subject breakdown ──────────────────────────────────────────
        ...state.subjects.map((sub) {
          final subTopics = state.topics
              .where((t) => t.subjectId == sub.id)
              .toList();
          if (subTopics.isEmpty) return const SizedBox.shrink();
          final subMastered = subTopics.where((t) => t.isMastered).length;
          final subDue = subTopics.where((t) => t.isDueToday).length;
          final progress = subTopics.isNotEmpty
              ? subMastered / subTopics.length
              : 0.0;

          return Glass(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(sub.color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          sub.name.isNotEmpty ? sub.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: Color(sub.color),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${subTopics.length} topics · $subDue due',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(sub.color),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Color(sub.color).withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation(Color(sub.color)),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOPIC CARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _topicCard(
    BuildContext ctx,
    StudyTopic topic,
    AppState state,
    bool isDueView,
  ) {
    final sub = state.subjects.firstWhere(
      (s) => s.id == topic.subjectId,
      orElse: () => const Subject(name: 'Unknown'),
    );
    final subColor = Color(sub.color);

    final stageColors = [
      Colors.grey,
      const Color(0xFF6C63FF),
      const Color(0xFF1E90FF),
      const Color(0xFFFF9F43),
      const Color(0xFFFF6B81),
      const Color(0xFF2ED573),
    ];
    final stageColor = stageColors[topic.stage.clamp(0, 5)];
    final isOverdue =
        topic.nextReview != null &&
        topic.nextReview!.isBefore(DateTime.now()) &&
        !topic.isMastered;

    return Glass(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            LayeringSystemOverlay.show(ctx, topic);
          },
          child: Column(
            children: [
            // ── Main row ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stage indicator dot
                  Container(
                    width: 5,
                    height: 50,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: stageColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Subject name chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: subColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            sub.name,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Topic title
                        AText(
                          topic.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Layer + Stage + last reviewed row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _chip(topic.stageLabel, stageColor),
                            if (topic.currentLayer <= 3)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                ),
                                child: Text(
                                  'Layer ${topic.currentLayer}',
                                  style: TextStyle(
                                    color: stageColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            if (topic.lastStudied != null)
                              _chip(
                                '↩ ${intl.DateFormat('MMM d').format(topic.lastStudied!)}',
                                Colors.grey,
                              ),
                            if (topic.customReview)
                              _chip('📅 Custom date', const Color(0xFF9D97FF)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Right side: due label + action dots
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isOverdue
                                      ? const Color(0xFFFF4757)
                                      : topic.isDueToday
                                      ? const Color(0xFFFF9F43)
                                      : topic.isMastered
                                      ? const Color(0xFF2ED573)
                                      : Colors.grey)
                                  .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isOverdue ? '⚠️ Overdue' : topic.nextReviewLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isOverdue
                                ? const Color(0xFFFF4757)
                                : topic.isDueToday
                                ? const Color(0xFFFF9F43)
                                : topic.isMastered
                                ? const Color(0xFF2ED573)
                                : Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Next review date text
                      if (topic.nextReview != null && !topic.isMastered)
                        Text(
                          intl.DateFormat('MMM d').format(topic.nextReview!),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Action buttons strip ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: stageColor.withOpacity(0.06),
                border: Border(
                  top: BorderSide(
                    color: stageColor.withOpacity(0.15),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Mark as reviewed
                  if (!topic.isMastered)
                    Expanded(
                      child: _actionBtn(
                        icon: Icons.check_rounded,
                        label: 'Reviewed',
                        color: const Color(0xFF2ED573),
                        onTap: () => _markReviewed(ctx, topic),
                      ),
                    ),
                  if (!topic.isMastered)
                    Container(
                      width: 1,
                      height: 32,
                      color: stageColor.withOpacity(0.15),
                    ),
                  // Set custom review date
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.calendar_today_rounded,
                      label: 'Set Date',
                      color: const Color(0xFF6C63FF),
                      onTap: () => _setCustomDate(ctx, topic),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: stageColor.withOpacity(0.15),
                  ),
                  // Reset to new
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.refresh_rounded,
                      label: 'Reset',
                      color: const Color(0xFFFF9F43),
                      onTap: () => _resetTopic(ctx, topic),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: stageColor.withOpacity(0.15),
                  ),
                  // Delete
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.delete_rounded,
                      label: 'Delete',
                      color: const Color(0xFFFF4757),
                      onTap: () => _deleteTopic(ctx, topic),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════
  void _markReviewed(BuildContext ctx, StudyTopic topic) {
    ctx.read<AppBloc>().add(ReviewTopic(topic));
    // 🔊 Sound on topic review
    if (topic.stage >= 4) {
      NovaAudioService.playAsset("sounds/that _is_one_step_closer.mp3");
    } else {
      NovaAudioService.playAsset('sounds/task_done.mp3');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                topic.stage >= 4
                    ? '🎉 Mastered: ${topic.title}'
                    : '✓ Reviewed! Next: ${topic.advanceStage().nextReviewLabel}',
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2ED573),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _setCustomDate(BuildContext ctx, StudyTopic topic) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: topic.nextReview ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Set next review date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6C63FF),
            surface: Color(0xFF1A1A3E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final updated = topic.withCustomReview(picked);
    ctx.read<AppBloc>().add(UpdateTopic(updated));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'Review set for ${intl.DateFormat('MMM d, yyyy').format(picked)}',
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _resetTopic(BuildContext ctx, StudyTopic topic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: Color(0xFFFF9F43)),
            SizedBox(width: 8),
            Text('Reset Topic?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${topic.title}"',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Stage ${topic.stage} → New\n'
              'This marks it as not yet mastered and restarts the repetition cycle.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9F43),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Reset to New'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    ctx.read<AppBloc>().add(UpdateTopic(topic.resetToNew()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Topic reset to New'),
          ],
        ),
        backgroundColor: const Color(0xFFFF9F43),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _deleteTopic(BuildContext ctx, StudyTopic topic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_rounded, color: Color(0xFFFF4757)),
            SizedBox(width: 8),
            Text('Delete Topic?'),
          ],
        ),
        content: Text('Delete "${topic.title}"?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF4757)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) ctx.read<AppBloc>().add(DeleteTopic(topic.id!));
  }

  void _showAddTopic(BuildContext context) {
    final state = context.read<AppBloc>().state;
    final titleC = TextEditingController();
    int? selectedSubjectId =
        _filterSubjectId ??
        (state.subjects.isNotEmpty ? state.subjects.first.id : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final dark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF12122A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Add Study Topic',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                // Subject selector
                DropdownButtonFormField<int>(
                  value: selectedSubjectId,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.menu_book_rounded),
                  ),
                  items: state.subjects.map((s) {
                    return DropdownMenuItem(
                      value: s.id,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Color(s.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(s.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setS(() => selectedSubjectId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleC,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Topic title',
                    prefixIcon: Icon(Icons.book_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (titleC.text.trim().isEmpty) return;
                      if (selectedSubjectId == null) return;
                      context.read<AppBloc>().add(
                        AddTopic(
                          StudyTopic(
                            subjectId: selectedSubjectId!,
                            title: titleC.text.trim(),
                          ),
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Add Topic',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  List<StudyTopic> _filtered(AppState state) {
    if (_filterSubjectId == null) return List.from(state.topics);
    return state.topics.where((t) => t.subjectId == _filterSubjectId).toList();
  }
}
