import 'package:equatable/equatable.dart';

class JarvisDocument extends Equatable {
  final int? id;
  final int subjectId;
  final String type; // 'document' | 'past_exam'
  final String name;
  final String content;
  final DateTime? createdAt;
  final String? fileUri;
  final String? fileMime;

  const JarvisDocument({
    this.id,
    required this.subjectId,
    required this.type,
    required this.name,
    this.content = '',
    this.createdAt,
    this.fileUri,
    this.fileMime,
  });

  bool get isPastExam => type == 'past_exam';

  Map<String, dynamic> toMap() => {
        'subjectId': subjectId,
        'type': type,
        'name': name,
        'content': content,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'fileUri': fileUri,
        'fileMime': fileMime,
      };

  factory JarvisDocument.fromMap(Map<String, dynamic> m) => JarvisDocument(
        id: m['id'],
        subjectId: m['subjectId'] ?? 0,
        type: m['type'] ?? 'document',
        name: m['name'] ?? '',
        content: m['content'] ?? '',
        createdAt: m['createdAt'] != null ? DateTime.tryParse(m['createdAt']) : null,
        fileUri: m['fileUri'],
        fileMime: m['fileMime'],
      );

  @override
  List<Object?> get props => [id, subjectId, type, name, content, fileUri, fileMime];
}
