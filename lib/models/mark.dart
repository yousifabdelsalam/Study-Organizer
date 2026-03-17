import 'package:equatable/equatable.dart';

class MarkModel extends Equatable {
  final int? id;
  final int? subjectId;
  final String category, label;
  final double obtained, total;
  final String? lossReason;
  final DateTime? createdAt;

  const MarkModel({
    this.id,
    this.subjectId,
    this.category = 'other',
    this.label = '',
    this.obtained = 0,
    this.total = 0,
    this.lossReason,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'subjectId': subjectId,
    'category': category,
    'label': label,
    'obtained': obtained,
    'total': total,
    'lossReason': lossReason,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory MarkModel.fromMap(Map<String, dynamic> m) => MarkModel(
    id: m['id'],
    subjectId: m['subjectId'],
    category: m['category'] ?? 'other',
    label: m['label'] ?? '',
    obtained: (m['obtained'] as num?)?.toDouble() ?? 0,
    total: (m['total'] as num?)?.toDouble() ?? 0,
    lossReason: m['lossReason'],
    createdAt: m['createdAt'] != null
        ? DateTime.tryParse(m['createdAt'])
        : null,
  );

  double get percentage => total > 0 ? obtained / total * 100 : 0;

  @override
  List<Object?> get props => [
    id,
    subjectId,
    category,
    obtained,
    total,
    lossReason,
    createdAt,
  ];
}
