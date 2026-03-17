import 'package:equatable/equatable.dart';

class SubjectNote extends Equatable {
  final int? id;
  final int subjectId;
  final String category;
  final String title;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SubjectNote({
    this.id,
    required this.subjectId,
    this.category = 'General',
    required this.title,
    this.content = '',
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'subjectId': subjectId,
    'category': category,
    'title': title,
    'content': content,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory SubjectNote.fromMap(Map<String, dynamic> m) => SubjectNote(
    id: m['id'],
    subjectId: m['subjectId'] ?? 0,
    category: m['category'] ?? 'General',
    title: m['title'] ?? '',
    content: m['content'] ?? '',
    createdAt: m['createdAt'] != null ? DateTime.tryParse(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? DateTime.tryParse(m['updatedAt']) : null,
  );

  SubjectNote copyWith({
    int? id,
    int? subjectId,
    String? category,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SubjectNote(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    category: category ?? this.category,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [id, subjectId, category, title, content];
}