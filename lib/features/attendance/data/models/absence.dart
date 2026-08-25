class Absence {
  final int? id;
  final int subjectId;
  final String date;
  final String type; // 'lecture', 'section', 'lab'

  const Absence({
    this.id,
    required this.subjectId,
    required this.date,
    this.type = 'lecture',
  });

  factory Absence.fromMap(Map<String, dynamic> map) {
    return Absence(
      id: map['id'] as int?,
      subjectId: (map['subjectId'] as int?) ?? 0,
      date: (map['date'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'lecture',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'subjectId': subjectId,
      'date': date,
      'type': type,
    };
  }

  Absence copyWith({
    int? id,
    int? subjectId,
    String? date,
    String? type,
  }) {
    return Absence(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      date: date ?? this.date,
      type: type ?? this.type,
    );
  }
}
