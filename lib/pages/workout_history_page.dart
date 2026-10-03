import 'package:flutter/material.dart';

import '../main.dart' show kBackground, kSurface, kAccent;
import '../models/workout.dart';
import '../services/database_service.dart';
import 'homepage/home_helpers.dart';
import 'homepage/widgets/section_title.dart';
import 'workout_detail_page.dart';

String _duration(int seconds) {
  if (seconds <= 0) return '0s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return s > 0 ? '${m}m ${s}s' : '${m}m';
  return '${s}s';
}

class WorkoutHistoryPage extends StatefulWidget {
  final int refreshToken;
  final ValueChanged<Workout>? onRepeatWorkout;

  const WorkoutHistoryPage({
    super.key,
    this.refreshToken = 0,
    this.onRepeatWorkout,
  });

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  late Future<List<Workout>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.instance.getAllWorkouts();
  }

  @override
  void didUpdateWidget(covariant WorkoutHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = DatabaseService.instance.getAllWorkouts();
    });
    await _future;
  }

  Future<void> _open(Workout workout) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDetailPage(
          // Pass the complete History snapshot.
          // The detail page will continue using this even if
          // the original saved/custom workout was deleted.
          workout: workout,
          onRepeat: widget.onRepeatWorkout,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  int _setCount(Workout w) =>
      w.exercises.fold<int>(0, (sum, e) => sum + e.sets);

  // ---------------------------------------------------------------- summary

  Widget _summaryCard(List<Workout> workouts) {
    final totalTime =
        workouts.fold<int>(0, (sum, w) => sum + w.durationSeconds);
    final totalSets = workouts.fold<int>(0, (sum, w) => sum + _setCount(w));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kAccent, Color(0xFFB71C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: kAccent.withValues(alpha: .30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ALL TIME',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${workouts.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  workouts.length == 1
                      ? 'workout completed'
                      : 'workouts completed',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _summaryChip(Icons.timer_rounded, _duration(totalTime), 'time'),
              const SizedBox(width: 10),
              _summaryChip(Icons.layers_rounded, '$totalSets', 'sets'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ cards

  Widget _tag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: kAccent),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateBadge(DateTime d) {
    return Container(
      width: 56,
      height: 64,
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${d.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          Text(
            monthShort[d.month - 1].toUpperCase(),
            style: const TextStyle(
              color: kAccent,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _workoutCard(Workout workout) {
    final sets = _setCount(workout);
    final title =
        workout.name.trim().isEmpty ? 'Untitled workout' : workout.name.trim();

    final names = workout.exercises.map((e) => e.name).toList();
    final preview = names.isEmpty
        ? null
        : names.length <= 2
            ? names.join(' · ')
            : '${names.take(2).join(' · ')} +${names.length - 2}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(workout),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .05)),
            ),
            child: Row(
              children: [
                _dateBadge(workout.date),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (preview != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _tag(Icons.fitness_center_rounded,
                              '${workout.exercises.length} ex'),
                          _tag(Icons.layers_rounded, '$sets sets'),
                          if (workout.durationSeconds > 0)
                            _tag(Icons.timer_outlined,
                                _duration(workout.durationSeconds)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Workout cards grouped under "October 2026"-style headers.
  List<Widget> _groupedList(List<Workout> workouts) {
    final children = <Widget>[];
    int? lastKey;

    for (final w in workouts) {
      final key = w.date.year * 100 + w.date.month;
      if (key != lastKey) {
        lastKey = key;
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: children.isEmpty ? 0 : 14,
              bottom: 10,
              left: 4,
            ),
            child: Text(
              '${monthNames[w.date.month - 1]} ${w.date.year}'.toUpperCase(),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        );
      }
      children.add(_workoutCard(w));
    }
    return children;
  }

  // ------------------------------------------------------------------ build

  Widget _emptyState() {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: kAccent,
      backgroundColor: kSurface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 90),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_rounded,
                  size: 40, color: kAccent),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text(
              'No completed workouts yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Finish a workout and it will appear here.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'History',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        centerTitle: false,
        backgroundColor: kBackground,
      ),
      body: FutureBuilder<List<Workout>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: kAccent),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load workout history.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            );
          }

          final workouts = snapshot.data ?? [];
          if (workouts.isEmpty) return _emptyState();

          return RefreshIndicator(
            onRefresh: _refresh,
            color: kAccent,
            backgroundColor: kSurface,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // Bottom padding keeps the last card clear of the floating nav.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                _summaryCard(workouts),
                const SectionTitle('Completed sessions'),
                ..._groupedList(workouts),
              ],
            ),
          );
        },
      ),
    );
  }
}