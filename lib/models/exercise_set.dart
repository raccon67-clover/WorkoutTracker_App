import '../data/exercise_catalog.dart';
import 'exercise.dart';

String fmtNum(double v) {
  var s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}

String fmtBig(double v) {
  final s = fmtNum(v.abs());
  final parts = s.split('.');
  final ip = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) buf.write(',');
    buf.write(ip[i]);
  }
  if (parts.length > 1) {
    buf.write('.');
    buf.write(parts[1]);
  }
  return (v < 0 ? '-' : '') + buf.toString();
}


class ExerciseSet {
  final int? id;
  final int exerciseId;
  final int setNumber;
  final int reps;
  final int durationSeconds;

  const ExerciseSet({
    this.id,
    required this.exerciseId,
    required this.setNumber,
    this.reps = 0,
    this.durationSeconds = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'exercise_id': exerciseId,
        'set_number': setNumber,
        'reps': reps,
        'duration_seconds': durationSeconds,
      };

  factory ExerciseSet.fromMap(Map<String, dynamic> map) {
    return ExerciseSet(
      id: map['id'] as int?,
      exerciseId: (map['exercise_id'] as num).toInt(),
      setNumber: (map['set_number'] as num).toInt(),
      reps: (map['reps'] as num?)?.toInt() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class ExerciseWithSets {
  final Exercise exercise;
  final List<ExerciseSet> sets;
  const ExerciseWithSets({required this.exercise, required this.sets});
}

class ExerciseSession {
  final int exerciseId;
  final DateTime date;
  final List<ExerciseSet> sets;

  const ExerciseSession({
    required this.exerciseId,
    required this.date,
    required this.sets,
  });

  int get totalReps => sets.fold(0, (t, s) => t + s.reps);
  int get bestReps => sets.fold(0, (m, s) => s.reps > m ? s.reps : m);
  int get bestDuration => sets.fold(0, (m, s) => s.durationSeconds > m ? s.durationSeconds : m);
  int get totalDuration => sets.fold(0, (t, s) => t + s.durationSeconds);
}

String describeSet(ExerciseKind kind, ExerciseSet s) {
  return switch (kind) {
    ExerciseKind.strength => '${s.reps} reps',
    ExerciseKind.timed => '${s.durationSeconds}s',
    ExerciseKind.cardio => '${fmtNum(s.durationSeconds / 60)} min',
  };
}

String describeSets(ExerciseKind kind, List<ExerciseSet> sets) {
  if (sets.isEmpty) return '';
  return sets.map((s) => describeSet(kind, s)).join('  ·  ');
}
