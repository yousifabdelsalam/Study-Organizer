import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class TimetableEntry extends Equatable {
  final int? id;
  final int? subjectId;
  final int dayOfWeek; // 1=Mon, 2=Tue, ..., 7=Sun
  final String startTime; // "08:30"
  final String endTime; // "10:00"
  final String type; // lecture, section, lab
  final String room;
  final String building;
  final String weekType; // 'both', 'odd', 'even'
  final bool isExceptional; // one-time class
  final String exceptionalDate; // ISO date e.g. '2026-03-10'

  const TimetableEntry({
    this.id,
    this.subjectId,
    this.dayOfWeek = 1,
    this.startTime = '08:00',
    this.endTime = '09:30',
    this.type = 'lecture',
    this.room = '',
    this.building = '',
    this.weekType = 'both',
    this.isExceptional = false,
    this.exceptionalDate = '',
  });

  Map<String, dynamic> toMap() => {
    'subjectId': subjectId,
    'dayOfWeek': dayOfWeek,
    'startTime': startTime,
    'endTime': endTime,
    'type': type,
    'room': room,
    'building': building,
    'weekType': weekType,
    'isExceptional': isExceptional ? 1 : 0,
    'exceptionalDate': exceptionalDate,
  };

  factory TimetableEntry.fromMap(Map<String, dynamic> m) => TimetableEntry(
    id: m['id'],
    subjectId: m['subjectId'],
    dayOfWeek: m['dayOfWeek'] ?? 1,
    startTime: m['startTime'] ?? '08:00',
    endTime: m['endTime'] ?? '09:30',
    type: m['type'] ?? 'lecture',
    room: m['room'] ?? '',
    building: m['building'] ?? '',
    weekType: m['weekType'] ?? 'both',
    isExceptional: (m['isExceptional'] ?? 0) == 1,
    exceptionalDate: m['exceptionalDate'] ?? '',
  );

  String get dayName {
    const days = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[dayOfWeek.clamp(1, 7)];
  }

  IconData get typeIcon {
    switch (type) {
      case 'section':
        return Icons.engineering_rounded;
      case 'lab':
        return Icons.science_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  String get weekTypeLabel {
    switch (weekType) {
      case 'odd':
        return 'Odd Week';
      case 'even':
        return 'Even Week';
      default:
        return 'Every Week';
    }
  }

  @override
  List<Object?> get props => [
    id,
    subjectId,
    dayOfWeek,
    startTime,
    endTime,
    type,
    weekType,
    isExceptional,
    exceptionalDate,
  ];
}
