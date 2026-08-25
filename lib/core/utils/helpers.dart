import 'package:flutter/material.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';

String subjectName(List<Subject> subjects, int? id) {
  if (id == null) return 'General';
  final s = subjects.where((e) => e.id == id);
  return s.isNotEmpty ? s.first.name : 'Unknown';
}

TextDirection detectDir(String t) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(t)
        ? TextDirection.rtl
        : TextDirection.ltr;