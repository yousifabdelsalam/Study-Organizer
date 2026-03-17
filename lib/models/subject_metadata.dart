import 'package:equatable/equatable.dart';

class SubjectMetadata extends Equatable {
  final int subjectId;
  final String instructorFocus;

  const SubjectMetadata({
    required this.subjectId,
    this.instructorFocus = '',
  });

  Map<String, dynamic> toMap() => {
        'subjectId': subjectId,
        'instructor_focus': instructorFocus,
      };

  factory SubjectMetadata.fromMap(Map<String, dynamic> m) => SubjectMetadata(
        subjectId: m['subjectId'] ?? 0,
        instructorFocus: m['instructor_focus'] ?? '',
      );

  @override
  List<Object?> get props => [subjectId, instructorFocus];
}
