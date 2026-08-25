import 'package:equatable/equatable.dart';

class Subject extends Equatable {
  final int? id;
  final String name, doctorName, sectionEngineer, labEngineer;
  final int color, creditHours, maxLectureAbs, maxSectionAbs, maxLabAbs;
  final bool hasSection, hasLab;

  const Subject({
    this.id,
    required this.name,
    this.doctorName = '',
    this.sectionEngineer = '',
    this.labEngineer = '',
    this.color = 0xFF6C63FF,
    this.creditHours = 3,
    this.maxLectureAbs = 4,
    this.maxSectionAbs = 4,
    this.maxLabAbs = 4,
    this.hasSection = true,
    this.hasLab = false,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'doctorName': doctorName,
    'sectionEngineer': sectionEngineer,
    'labEngineer': labEngineer,
    'color': color,
    'creditHours': creditHours,
    'maxLectureAbs': maxLectureAbs,
    'maxSectionAbs': maxSectionAbs,
    'maxLabAbs': maxLabAbs,
    'hasSection': hasSection ? 1 : 0,
    'hasLab': hasLab ? 1 : 0,
  };

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
    id: m['id'],
    name: m['name'] ?? '',
    doctorName: m['doctorName'] ?? '',
    sectionEngineer: m['sectionEngineer'] ?? '',
    labEngineer: m['labEngineer'] ?? '',
    color: m['color'] ?? 0xFF6C63FF,
    creditHours: m['creditHours'] ?? 3,
    maxLectureAbs: m['maxLectureAbs'] ?? 4,
    maxSectionAbs: m['maxSectionAbs'] ?? 4,
    maxLabAbs: m['maxLabAbs'] ?? 4,
    hasSection: (m['hasSection'] ?? 1) == 1,
    hasLab: (m['hasLab'] ?? 0) == 1,
  );

  @override
  List<Object?> get props => [id, name, doctorName, color, creditHours];
}