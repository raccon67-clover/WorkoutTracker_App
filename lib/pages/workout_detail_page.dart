import 'package:flutter/material.dart';

import '../data/exercise_catalog.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../models/workout.dart';
import '../services/database_service.dart';
import 'log_workout_page.dart';

class _DetailData {
  final Workout workout;
  final Map<int, List<ExerciseSet>> sets;

  const _DetailData(this.workout, this.sets);
}

String _duration(int seconds) {
  if (seconds <= 0) return '-';

  final m = seconds ~/ 60;
  final s = seconds % 60;

  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

class WorkoutDetailPage extends StatefulWidget {
  final Workout? workout;
  final int? workoutId;
  final ValueChanged<Workout>? onRepeat;

  /// Set to false to hide the Repeat button (e.g. when opened from the calendar).
  final bool showRepeat;

  const WorkoutDetailPage({
    super.key,
    this.workout,
    this.workoutId,
    this.onRepeat,
    this.showRepeat = true,
  }) : assert(workout != null || workoutId != null);

  @override
  State<WorkoutDetailPage> createState() => _WorkoutDetailPageState();
}

class _WorkoutDetailPageState extends State<WorkoutDetailPage> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final supplied = widget.workout;

    // When History passes the completed workout, use that snapshot directly.
    // This keeps History usable even if the original saved workout was deleted.
    if (supplied != null) {
      try {
        final id = supplied.id;

        if (id != null) {
          final sets = await DatabaseService.instance.getSetsForWorkout(id);

          if (sets.isNotEmpty) {
            return _DetailData(supplied, sets);
          }
        }
      } catch (e) {
      debugPrint('Loading workout sets failed: $e');
    }

      return _DetailData(supplied, {});
    }

    final id = widget.workoutId;

    if (id == null) {
      throw StateError('Workout not available');
    }

    final stored =
        await DatabaseService.instance.getWorkoutWithExercises(id);

    if (stored == null) {
      throw StateError('Workout not available');
    }

    final sets = await DatabaseService.instance.getSetsForWorkout(id);

    return _DetailData(stored, sets);
  }

  Future<void> _repeat(Workout workout) async {
    final callback = widget.onRepeat;

    if (callback != null) {
      // Change the parent HomePage to the Log tab first.
      // Then remove this History/Detail route so Back from the session
      // stays inside the Log area instead of returning to History.
      callback(workout);

      if (mounted) {
        Navigator.of(context).pop();
      }

      return;
    }

    final selected = workout.exercises
        .map((e) => ExerciseCatalog.byName(e.name))
        .whereType<CatalogExercise>()
        .toList();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LogWorkoutPage(
          initialExercises: selected,
          initialExercisesToken: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Widget _exerciseCard(
    Exercise exercise,
    List<ExerciseSet>? sets,
  ) {
    final catalog = ExerciseCatalog.byName(exercise.name);
    final kind = catalog?.kind ?? ExerciseKind.strength;
    final hasSets = sets != null && sets.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (catalog != null)
                Icon(
                  catalog.equipment.icon,
                  color: kAccent,
                  size: 19,
                ),
            ],
          ),
          if (catalog != null)
            Text(
              catalog.subtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 10),
          if (hasSets)
            ...List.generate(
              sets.length,
              (index) {
                final set = sets[index];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          'Set ${index + 1}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        describeSet(kind, set),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Text(
              '${exercise.sets} sets · ${exercise.reps} reps',
              style: TextStyle(
                color: Colors.grey[400],
              ),
            ),
        ],
      ),
    );
  }

  Widget _notAvailable() {
    return const Center(
      child: Text(
        'Workout not available',
        style: TextStyle(
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Workout Detail'),
        backgroundColor: kBackground,
      ),
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: kAccent,
              ),
            );
          }

          if (snapshot.hasError) {
            return _notAvailable();
          }

          final data = snapshot.data;

          if (data == null) {
            return _notAvailable();
          }

          final workout = data.workout;
          final setsByExercise = data.sets;

          final totalSets = workout.exercises.fold<int>(
            0,
            (sum, exercise) =>
                sum +
                (setsByExercise[exercise.id]?.length ?? exercise.sets),
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              18,
              8,
              18,
              30,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      workout.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (widget.showRepeat) ...[
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _repeat(workout),
                      icon: const Icon(
                        Icons.replay_rounded,
                        size: 17,
                      ),
                      label: const Text('Repeat'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${workout.date.day}/${workout.date.month}/${workout.date.year}'
                ' · ${workout.exercises.length} exercises'
                ' · $totalSets sets',
                style: TextStyle(
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: kAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _duration(workout.durationSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (workout.notes != null &&
                  workout.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  workout.notes!,
                  style: TextStyle(
                    color: Colors.grey[400],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Exercises',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ...workout.exercises.map(
                (exercise) => _exerciseCard(
                  exercise,
                  setsByExercise[exercise.id],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}