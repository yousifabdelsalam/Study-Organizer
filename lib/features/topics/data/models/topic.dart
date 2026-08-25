import 'dart:convert';
import 'package:equatable/equatable.dart';

class StudyTopic extends Equatable {
  final int? id;
  final int subjectId;
  final String title;
  final int stage;
  final DateTime? lastStudied;
  final DateTime? nextReview;
  final bool customReview;
  final String notes; // NEW: user notes about the topic
  final List<String> prerequisites; // NEW: for Cascade Mapper

  const StudyTopic({
    this.id,
    required this.subjectId,
    required this.title,
    this.stage = 0,
    this.lastStudied,
    this.nextReview,
    this.customReview = false,
    this.notes = '',
    this.prerequisites = const [],
  });

  StudyTopic advanceStage() {
    final now = DateTime.now();
    const intervals = [1, 3, 7, 14, 30];
    final daysToAdd = stage < intervals.length ? intervals[stage] : 30;
    return copyWith(
      stage: (stage + 1).clamp(0, 5),
      lastStudied: now,
      nextReview: stage >= 4 ? null : now.add(Duration(days: daysToAdd)),
      customReview: false,
    );
  }

  StudyTopic resetToNew() {
    return StudyTopic(
      id: id,
      subjectId: subjectId,
      title: title,
      stage: 0,
      lastStudied: null,
      nextReview: null,
      customReview: false,
      notes: notes,
      prerequisites: prerequisites,
    );
  }

  StudyTopic withCustomReview(DateTime date) {
    return copyWith(nextReview: date, customReview: true);
  }

  bool get isDueToday {
    if (nextReview == null) return stage == 0;
    final today = DateTime.now();
    return nextReview!.isBefore(
      DateTime(today.year, today.month, today.day + 1),
    );
  }

  int get currentLayer {
    if (stage == 0) return 1;
    if (stage == 1) return 2;
    if (stage == 2) return 3;
    return 4; // 4 means mastered/advanced spaced repetition
  }

  bool get isMastered => stage >= 5;

  String get stageLabel {
    const labels = [
      'New',
      'Seen once',
      'Reviewed',
      'Familiar',
      'Well known',
      'Mastered',
    ];
    return labels[stage.clamp(0, 5)];
  }

  String get nextReviewLabel {
    if (isMastered) return 'Mastered ✓';
    if (nextReview == null) return 'Review now';
    final diff = nextReview!.difference(DateTime.now()).inDays;
    if (diff < 0) return 'Overdue!';
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'In $diff days';
  }

  StudyTopic copyWith({
    int? id,
    int? subjectId,
    String? title,
    int? stage,
    DateTime? lastStudied,
    DateTime? nextReview,
    bool? customReview,
    String? notes,
    List<String>? prerequisites,
  }) {
    return StudyTopic(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      stage: stage ?? this.stage,
      lastStudied: lastStudied ?? this.lastStudied,
      nextReview: nextReview ?? this.nextReview,
      customReview: customReview ?? this.customReview,
      notes: notes ?? this.notes,
      prerequisites: prerequisites ?? this.prerequisites,
    );
  }

  Map<String, dynamic> toMap() => {
    'subjectId': subjectId,
    'title': title,
    'stage': stage,
    'lastStudied': lastStudied?.toIso8601String(),
    'nextReview': nextReview?.toIso8601String(),
    'notes': notes,
    'prerequisites': jsonEncode(prerequisites),
  };

  factory StudyTopic.fromMap(Map<String, dynamic> map) {
    List<String> parsedPrereqs = [];
    if (map['prerequisites'] != null) {
      try {
        final decoded = jsonDecode(map['prerequisites']);
        if (decoded is List) parsedPrereqs = decoded.cast<String>();
      } catch (_) {}
    }
    return StudyTopic(
      id: map['id'],
      subjectId: map['subjectId'],
      title: map['title'],
      stage: map['stage'] ?? 0,
      lastStudied: map['lastStudied'] != null
          ? DateTime.tryParse(map['lastStudied'])
          : null,
      nextReview: map['nextReview'] != null
          ? DateTime.tryParse(map['nextReview'])
          : null,
      customReview: false,
      notes: map['notes'] ?? '',
      prerequisites: parsedPrereqs,
    );
  }

  @override
  List<Object?> get props => [
    id,
    subjectId,
    title,
    stage,
    nextReview,
    customReview,
    notes,
    prerequisites,
  ];
}
