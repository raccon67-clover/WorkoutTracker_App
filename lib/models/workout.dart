import 'exercise.dart';

class Workout {
  final int? id;
  final String name;
  final DateTime date;
  final String? notes;
  final int durationSeconds;
  final List<Exercise> exercises;
  final bool isSuggested;

  Workout({
    this.id,
    required this.name,
    required this.date,
    this.notes,
    this.durationSeconds = 0,
    this.exercises = const [],
    this.isSuggested = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'date': date.toIso8601String(),
        'notes': notes,
        'duration_seconds': durationSeconds,
        'is_suggested': isSuggested ? 1 : 0,
      };

  factory Workout.fromMap(Map<String, dynamic> map) => Workout(
        id: map['id'] as int?,
        name: map['name'] as String,
        date: DateTime.parse(map['date'] as String),
        notes: map['notes'] as String?,
        durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
        isSuggested: (map['is_suggested'] as num?)?.toInt() == 1 || map['is_suggested'] == true,
      );

  Workout copyWith({
    int? id,
    String? name,
    DateTime? date,
    String? notes,
    int? durationSeconds,
    List<Exercise>? exercises,
    bool? isSuggested,
  }) => Workout(
        id: id ?? this.id,
        name: name ?? this.name,
        date: date ?? this.date,
        notes: notes ?? this.notes,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        exercises: exercises ?? this.exercises,
        isSuggested: isSuggested ?? this.isSuggested,
      );
}
