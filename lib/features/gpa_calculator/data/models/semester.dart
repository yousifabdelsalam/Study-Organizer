import 'package:equatable/equatable.dart';

class SemesterModel extends Equatable {
  final int? id;
  final String name;
  final double gpa;
  final int credits;
  final DateTime? createdAt;

  const SemesterModel({
    this.id,
    this.name = '',
    this.gpa = 0,
    this.credits = 0,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'gpa': gpa,
    'credits': credits,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory SemesterModel.fromMap(Map<String, dynamic> m) => SemesterModel(
    id: m['id'],
    name: m['name'] ?? '',
    gpa: (m['gpa'] as num?)?.toDouble() ?? 0,
    credits: m['credits'] ?? 0,
    createdAt: m['createdAt'] != null
        ? DateTime.tryParse(m['createdAt'])
        : null,
  );

  @override
  List<Object?> get props => [id, name, gpa, credits];
}