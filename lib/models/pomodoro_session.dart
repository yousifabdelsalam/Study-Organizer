import 'package:equatable/equatable.dart';

/// Represents one completed (or active) Pomodoro study session.
/// Stored in the `pomodoro_sessions` table so JARVIS can analyse patterns.
class PomodoroSession extends Equatable {
  final int? id;
  final int? subjectId; // nullable — "free" sessions have no subject
  final String? topicLabel; // e.g. "Lecture 2 – Digital System Design"
  final String mode; // 'focus' | 'shortBreak' | 'longBreak'
  final DateTime startedAt;
  final DateTime? endedAt; // null while session is still running
  final int plannedSeconds; // configured timer length
  final int actualSeconds; // seconds actually elapsed before stop/complete
  final bool completed; // true if timer ran to zero
  final String? notes; // optional voice-added note about this session

  const PomodoroSession({
    this.id,
    this.subjectId,
    this.topicLabel,
    required this.mode,
    required this.startedAt,
    this.endedAt,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.completed,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'subjectId': subjectId,
    'topicLabel': topicLabel,
    'mode': mode,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'plannedSeconds': plannedSeconds,
    'actualSeconds': actualSeconds,
    'completed': completed ? 1 : 0,
    'notes': notes,
  };

  factory PomodoroSession.fromMap(Map<String, dynamic> m) => PomodoroSession(
    id: m['id'] as int?,
    subjectId: m['subjectId'] as int?,
    topicLabel: m['topicLabel'] as String?,
    mode: (m['mode'] as String?) ?? 'focus',
    startedAt: DateTime.parse(m['startedAt'] as String),
    endedAt: m['endedAt'] != null
        ? DateTime.parse(m['endedAt'] as String)
        : null,
    plannedSeconds: (m['plannedSeconds'] as int?) ?? 0,
    actualSeconds: (m['actualSeconds'] as int?) ?? 0,
    completed: ((m['completed'] as int?) ?? 0) == 1,
    notes: m['notes'] as String?,
  );

  PomodoroSession copyWith({
    int? id,
    int? subjectId,
    String? topicLabel,
    String? mode,
    DateTime? startedAt,
    DateTime? endedAt,
    int? plannedSeconds,
    int? actualSeconds,
    bool? completed,
    String? notes,
  }) => PomodoroSession(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    topicLabel: topicLabel ?? this.topicLabel,
    mode: mode ?? this.mode,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    plannedSeconds: plannedSeconds ?? this.plannedSeconds,
    actualSeconds: actualSeconds ?? this.actualSeconds,
    completed: completed ?? this.completed,
    notes: notes ?? this.notes,
  );

  @override
  List<Object?> get props => [
    id,
    subjectId,
    topicLabel,
    mode,
    startedAt,
    endedAt,
    actualSeconds,
    completed,
  ];
}
