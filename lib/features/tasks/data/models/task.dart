import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class TaskModel extends Equatable {
  final int? id;
  final int? subjectId;
  final String title, description, type;
  final DateTime? dueDate;
  final int priority;
  final bool isCompleted;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final bool isWorking; // ← NEW
  final bool isFailed; // ← FAILED STATE

  const TaskModel({
    this.id,
    this.subjectId,
    required this.title,
    this.description = '',
    this.dueDate,
    this.priority = 2,
    this.isCompleted = false,
    this.type = 'assignment',
    this.createdAt,
    this.completedAt,
    this.isWorking = false, // ← NEW
    this.isFailed = false, // ← FAILED STATE
  });

  bool get isExam => type == 'quiz' || type == 'midterm' || type == 'final';

  bool get isTask => !isExam;

  Map<String, dynamic> toMap() => {
    'subjectId': subjectId,
    'title': title,
    'description': description,
    'dueDate': dueDate?.toIso8601String(),
    'priority': priority,
    'isCompleted': isCompleted ? 1 : 0,
    'type': type,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'isWorking': isWorking ? 1 : 0, // ← NEW
    'isFailed': isFailed ? 1 : 0, // ← FAILED STATE
  };

  factory TaskModel.fromMap(Map<String, dynamic> m) => TaskModel(
    id: m['id'],
    subjectId: m['subjectId'],
    title: m['title'] ?? '',
    description: m['description'] ?? '',
    dueDate: m['dueDate'] != null ? DateTime.tryParse(m['dueDate']) : null,
    priority: m['priority'] ?? 2,
    isCompleted: m['isCompleted'] == 1,
    type: m['type'] ?? 'assignment',
    createdAt: m['createdAt'] != null
        ? DateTime.tryParse(m['createdAt'])
        : null,
    completedAt: m['completedAt'] != null
        ? DateTime.tryParse(m['completedAt'])
        : null,
    isWorking: (m['isWorking'] ?? 0) == 1, // ← NEW
    isFailed: (m['isFailed'] ?? 0) == 1, // ← FAILED STATE
  );

  TaskModel copyWith({
    int? id,
    int? subjectId,
    String? title,
    String? description,
    DateTime? dueDate,
    int? priority,
    bool? isCompleted,
    String? type,
    DateTime? createdAt,
    DateTime? completedAt,
    bool? isWorking,
    bool? isFailed,
  }) {
    return TaskModel(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      isWorking: isWorking ?? this.isWorking,
      isFailed: isFailed ?? this.isFailed,
    );
  }

  Color get priorityColor => priority == 3
      ? const Color(0xFFFF4757)
      : priority == 2
      ? const Color(0xFFFF9F43)
      : const Color(0xFF2ED573);

  String get priorityLabel => priority == 3
      ? 'High'
      : priority == 2
      ? 'Medium'
      : 'Low';

  IconData get typeIcon {
    switch (type) {
      case 'quiz':
        return Icons.quiz_rounded;
      case 'midterm':
        return Icons.school_rounded;
      case 'final':
        return Icons.emoji_events_rounded;
      case 'project':
        return Icons.build_rounded;
      case 'report':
        return Icons.description_rounded;
      case 'presentation':
        return Icons.present_to_all_rounded;
      default:
        return Icons.assignment_rounded;
    }
  }

  @override
  List<Object?> get props => [
    id,
    title,
    isCompleted,
    priority,
    dueDate,
    type,
    completedAt,
    isWorking,
    isFailed,
  ];
}
