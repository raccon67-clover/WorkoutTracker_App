class Exercise {
  final int? id;
  final int workoutId;
  final String name;
  final int sets;
  final int reps;
  final int durationSeconds;

  Exercise({
    this.id,
    required this.workoutId,
    required this.name,
    required this.sets,
    required this.reps,
    this.durationSeconds = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'workout_id': workoutId,
        'name': name,
        'sets': sets,
        'reps': reps,
        'duration_seconds': durationSeconds,
      };

  factory Exercise.fromMap(Map<String, dynamic> map) => Exercise(
        id: map['id'] as int?,
        workoutId: (map['workout_id'] as num).toInt(),
        name: map['name'] as String,
        sets: (map['sets'] as num?)?.toInt() ?? 0,
        reps: (map['reps'] as num?)?.toInt() ?? 0,
        durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      );

  Exercise copyWith({
    int? id,
    int? workoutId,
    String? name,
    int? sets,
    int? reps,
    int? durationSeconds,
  }) => Exercise(
        id: id ?? this.id,
        workoutId: workoutId ?? this.workoutId,
        name: name ?? this.name,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}
