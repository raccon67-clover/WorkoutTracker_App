import 'package:flutter/material.dart';

import '../data/exercise_catalog.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import '../models/exercise_set.dart';
import '../models/workout.dart';
import '../services/database_service.dart';
import 'homepage/home_helpers.dart';

String _dayLabel(DateTime d) => '${d.day} ${monthShort[d.month - 1]}';

String _exerciseImageUrl(String name) {
  final slug = name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-').replaceAll(RegExp(r'^-|-$'), '');
  return 'https://exercise-dataset.com/images/flat/$slug-start.webp';
}

String _duration(int seconds) {
  if (seconds <= 0) return '0m';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

class _Summary {
  final String name;
  final int sessions;
  final DateTime lastDate;
  final int bestReps;
  final int bestDuration;

  const _Summary({
    required this.name,
    required this.sessions,
    required this.lastDate,
    required this.bestReps,
    required this.bestDuration,
  });

  ExerciseKind get kind =>
      ExerciseCatalog.byName(name)?.kind ?? ExerciseKind.strength;

  String get bestLabel {
    switch (kind) {
      case ExerciseKind.cardio:
        return '${(bestDuration / 60).round()} min';
      case ExerciseKind.timed:
        return '${bestDuration}s';
      case ExerciseKind.strength:
        return '$bestReps reps';
    }
  }
}

class ProgressPage extends StatefulWidget {
  final int refreshToken;

  const ProgressPage({super.key, this.refreshToken = 0});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final _searchController = TextEditingController();
  List<_Summary> _items = [];
  List<Workout> _workouts = [];
  bool _loading = true;
  String? _error;
  int _rangeDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProgressPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await DatabaseService.instance.getLoggedExerciseSummaries();
      final workouts = await DatabaseService.instance.getAllWorkouts();
      final items = rows
          .map(
            (r) => _Summary(
              name: r['name'] as String,
              sessions: (r['sessions'] as num).toInt(),
              lastDate: DateTime.parse(r['last_date'] as String),
              bestReps: (r['best_reps'] as num?)?.toInt() ?? 0,
              bestDuration: (r['best_duration'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _items = items;
        _workouts = workouts;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<_Summary> get _filtered {
    final q = ExerciseCatalog.normalize(_searchController.text);
    if (q.isEmpty) return _items;
    return _items.where((s) {
      final cat = ExerciseCatalog.byName(s.name);
      final extra = cat == null
          ? ''
          : '${cat.muscle.label} ${cat.equipment.label}';
      return ExerciseCatalog.matchScore(q, s.name, extra: extra) > 0;
    }).toList();
  }

  DateTime get _weekStart {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  int get _thisWeek =>
      _workouts.where((w) => !w.date.isBefore(_weekStart)).length;

  int get _streak {
    final days = _workouts
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet();
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (days.contains(cursor)) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  int get _totalSets => _workouts.fold<int>(
        0,
        (sum, workout) =>
            sum + workout.exercises.fold<int>(0, (s, e) => s + e.sets),
      );

  int get _totalReps => _workouts.fold<int>(
        0,
        (sum, workout) =>
            sum + workout.exercises.fold<int>(0, (s, e) => s + e.reps),
      );

  int get _totalDuration =>
      _workouts.fold<int>(0, (sum, workout) => sum + workout.durationSeconds);

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: kAccent, size: 19),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget _rangePicker() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final days in const [7, 30, 90])
            GestureDetector(
              onTap: () => setState(() => _rangeDays = days),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _rangeDays == days ? kAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  '${days}D',
                  style: TextStyle(
                    color: _rangeDays == days ? Colors.white : Colors.grey[500],
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _weeklyChart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: _rangeDays - 1));
    final values = List<int>.filled(7, 0);
    final bucketSize = (_rangeDays / 7).ceil();

    for (final w in _workouts) {
      final d = DateTime(w.date.year, w.date.month, w.date.day);
      final dayIndex = d.difference(start).inDays;
      if (dayIndex < 0 || dayIndex >= _rangeDays) continue;
      final bucket = (dayIndex ~/ bucketSize).clamp(0, 6).toInt();
      values[bucket]++;
    }

    final maxValue = values.fold<int>(1, (m, v) => v > m ? v : m);
    final total = values.fold<int>(0, (s, v) => s + v);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'workouts · last $_rangeDays days',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              _rangePicker(),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final endDay =
                    start.add(Duration(days: ((i + 1) * bucketSize) - 1));
                final label = _rangeDays == 7
                    ? _weekday(endDay.weekday)
                    : '${endDay.month}/${endDay.day}';
                final fill = values[i] == 0
                    ? 0.0
                    : 10.0 + (values[i] / maxValue) * 70.0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        values[i] > 0 ? '${values[i]}' : '',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 24,
                        height: 80,
                        alignment: Alignment.bottomCenter,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          width: 24,
                          height: fill,
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(color: Colors.grey[600], fontSize: 9.5),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(int value) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value - 1];

  Future<void> _open(_Summary s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExerciseProgressPage(name: s.name)),
    );
  }

  Widget _exerciseTile(_Summary s) {
    final cat = ExerciseCatalog.byName(s.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
      ),
      child: ListTile(
        onTap: () => _open(s),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Image.network(
            _exerciseImageUrl(s.name),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 52,
              height: 52,
              color: kBackground,
              child: Icon(cat?.equipment.icon ?? Icons.fitness_center_rounded, color: kAccent),
            ),
          ),
        ),
        title: Text(
          s.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${s.sessions} session${s.sessions == 1 ? '' : 's'} · ${_dayLabel(s.lastDate)}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              s.bestLabel,
              style: const TextStyle(color: kAccent, fontWeight: FontWeight.w800),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_rounded, color: Colors.grey[600], size: 11),
                const SizedBox(width: 3),
                Text('best', style: TextStyle(color: Colors.grey[600], fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: kAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null)
            Text(trailing, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('Progress'), backgroundColor: kBackground),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : RefreshIndicator(
              onRefresh: _load,
              color: kAccent,
              backgroundColor: kSurface,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
                      child: Text(_error!, style: const TextStyle(color: Colors.white)),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your training at a glance',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Consistency, volume and time, all in one place.',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Row(children: [
                      _stat(Icons.fitness_center_rounded, '${_workouts.length}', 'Workouts'),
                      const SizedBox(width: 12),
                      _stat(Icons.calendar_today_rounded, '$_thisWeek', 'This week'),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      _stat(Icons.local_fire_department_rounded, '$_streak', 'Day streak'),
                      const SizedBox(width: 12),
                      _stat(Icons.timer_rounded, _duration(_totalDuration), 'Workout time'),
                    ]),
                    _sectionTitle(
                      'Activity',
                      trailing: '$_totalSets sets · $_totalReps reps',
                    ),
                    _weeklyChart(),
                    _sectionTitle('Exercise progress'),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search your exercises',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                        filled: true,
                        fillColor: kSurface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          children: [
                            Icon(Icons.insights_rounded, size: 44, color: Colors.grey[700]),
                            const SizedBox(height: 10),
                            Text(
                              'Complete a workout to build exercise progress here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    else
                      ...list.map(_exerciseTile),
                  ],
                ],
              ),
            ),
    );
  }
}

class ExerciseProgressPage extends StatefulWidget {
  final String name;
  const ExerciseProgressPage({super.key, required this.name});

  @override
  State<ExerciseProgressPage> createState() => _ExerciseProgressPageState();
}

class _ExerciseProgressPageState extends State<ExerciseProgressPage> {
  List<ExerciseSession> _sessions = [];
  bool _loading = true;

  ExerciseKind get _kind =>
      ExerciseCatalog.byName(widget.name)?.kind ?? ExerciseKind.strength;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions =
          await DatabaseService.instance.getExerciseSessions(widget.name);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sessions = [];
        _loading = false;
      });
    }
  }

  int _value(ExerciseSession s) {
    switch (_kind) {
      case ExerciseKind.strength:
        return s.bestReps;
      case ExerciseKind.timed:
        return s.bestDuration;
      case ExerciseKind.cardio:
        return s.totalDuration;
    }
  }

  String _primary(ExerciseSession s) {
    switch (_kind) {
      case ExerciseKind.strength:
        return '${s.bestReps} reps';
      case ExerciseKind.timed:
        return '${s.bestDuration}s';
      case ExerciseKind.cardio:
        return '${(s.totalDuration / 60).round()} min';
    }
  }

  Widget _trendChart() {
    final recent = _sessions.length > 10
        ? _sessions.sublist(_sessions.length - 10)
        : _sessions;
    if (recent.length < 2) return const SizedBox.shrink();

    final maxV = recent.fold<int>(1, (m, s) => _value(s) > m ? _value(s) : m);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent trend',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          Text(
            'Last ${recent.length} sessions',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(recent.length, (i) {
                final s = recent[i];
                final isLast = i == recent.length - 1;
                final h = 8.0 + (_value(s) / maxV) * 70.0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: h,
                        decoration: BoxDecoration(
                          color: isLast ? kAccent : kAccent.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${s.date.day}/${s.date.month}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 9),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final best = _sessions.isEmpty
        ? null
        : _sessions.reduce((a, b) => _value(a) >= _value(b) ? a : b);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: Text(widget.name), backgroundColor: kBackground),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : RefreshIndicator(
              onRefresh: _load,
              color: kAccent,
              backgroundColor: kSurface,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kAccent.withValues(alpha: .22), kSurface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: kAccent.withValues(alpha: .25)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_sessions.length}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                          Text('sessions', style: TextStyle(color: Colors.grey[500])),
                        ]),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(
                            children: [
                              const Icon(Icons.emoji_events_rounded, color: kAccent, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  best == null ? '-' : _primary(best),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kAccent, fontSize: 23, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                          Text('personal best', style: TextStyle(color: Colors.grey[500])),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _trendChart(),
                  if (_sessions.isEmpty)
                    Text('No sessions yet.', style: TextStyle(color: Colors.grey[600]))
                  else
                    ..._sessions.reversed.map(
                      (s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Icon(Icons.event_rounded, color: Colors.grey[600], size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${s.date.day}/${s.date.month}/${s.date.year}',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ),
                          Text(_primary(s), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}