import 'package:equatable/equatable.dart';

class ReminderModel extends Equatable {
  final int? id;
  final String text;
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final bool isDone;

  const ReminderModel({
    this.id,
    required this.text,
    required this.date,
    this.time = '08:00',
    this.isDone = false,
  });

  /// Computed dateTime from date + time strings
  DateTime? get dateTime {
    try {
      final dp = date.split('-');
      final tp = time.split(':');
      if (dp.length < 3 || tp.length < 2) return null;
      return DateTime(
        int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]),
        int.parse(tp[0]), int.parse(tp[1]),
      );
    } catch (_) {
      return null;
    }
  }

  // REMOVED dateTime from toMap — it doesn't exist in the DB table
  Map<String, dynamic> toMap() => {
    'text': text,
    'date': date,
    'time': time,
    'isDone': isDone ? 1 : 0,
  };

  factory ReminderModel.fromMap(Map<String, dynamic> m) => ReminderModel(
    id: m['id'],
    text: m['text'] ?? '',
    date: m['date'] ?? '',
    time: m['time'] ?? '08:00',
    isDone: (m['isDone'] ?? 0) == 1,
  );

  @override
  List<Object?> get props => [id, text, date, time, isDone];
}