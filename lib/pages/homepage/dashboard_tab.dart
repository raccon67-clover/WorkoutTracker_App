import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../main.dart' show kSurface, kAccent;
import '../../models/user_profile.dart';
import '../../models/workout.dart';
import '../../services/database_service.dart';
import '../../services/profile_notifier.dart';
import '../notifications_page.dart';
import '../workout_detail_page.dart';
import 'home_helpers.dart';
import 'workout_suggestion.dart';
import 'widgets/calendar_card.dart';
import 'widgets/home_header.dart';
import 'widgets/recent_workouts.dart';
import 'widgets/section_title.dart';
import 'widgets/suggestion_card.dart';
import 'widgets/summary_banner.dart';
import 'widgets/tip_card.dart';
import 'widgets/weekly_chart_card.dart';

class DashboardTab extends StatefulWidget {
  final ValueChanged<int> onGoToTab;
  final ValueChanged<Suggestion>? onStartSuggestion;
  final VoidCallback? onOpenExerciseLibrary;
  final int refreshToken;

  const DashboardTab({
    super.key,
    required this.onGoToTab,
    this.onStartSuggestion,
    this.onOpenExerciseLibrary,
    this.refreshToken = 0,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  UserProfile? _profile;
  List<Workout> _workouts = [];
  Map<DateTime, List<Workout>> _byDay = {};
  List<int> _weekSets = List<int>.filled(7, 0);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ProfileNotifier.current.addListener(_onProfileChanged);
    _loadData();
  }

  @override
  void dispose() {
    ProfileNotifier.current.removeListener(_onProfileChanged);
    super.dispose();
  }

  // Called instantly whenever the profile is saved anywhere in the app.
  void _onProfileChanged() {
    final p = ProfileNotifier.current.value;
    final uid = Auth().currentUser?.uid;
    if (!mounted || p == null || p.uid != uid) return;
    setState(() => _profile = p);
  }

  @override
  void didUpdateWidget(DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.refreshToken != oldWidget.refreshToken) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    UserProfile? profile;
    List<Workout> workouts = [];
    final weekSets = List<int>.filled(7, 0);

    try {
      final user = Auth().currentUser;

      if (user != null) {
        profile = await DatabaseService.instance
            .getUserProfile(user.uid)
            .timeout(
              const Duration(seconds: 6),
            );
      }

      workouts = await DatabaseService.instance
          .getAllWorkouts()
          .timeout(
            const Duration(seconds: 6),
          );

      final today = dayOnly(DateTime.now());

      for (final workout in workouts) {
        final diff = today
            .difference(dayOnly(workout.date))
            .inDays;

        if (diff >= 0 &&
            diff < 7 &&
            workout.id != null) {
          final exercises =
              await DatabaseService.instance
                  .getExercisesForWorkout(workout.id!)
                  .timeout(
                    const Duration(seconds: 6),
                  );

          weekSets[6 - diff] += exercises.fold<int>(
            0,
            (sum, exercise) => sum + exercise.sets,
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Dashboard load failed: $e',
      );
    }

    final byDay = <DateTime, List<Workout>>{};

    for (final workout in workouts) {
      byDay
          .putIfAbsent(
            dayOnly(workout.date),
            () => [],
          )
          .add(workout);
    }

    if (!mounted) return;

    // If the profile was saved while this was loading, keep the newer one.
    final saved = ProfileNotifier.current.value;
    final newest = (saved != null &&
            saved.uid == Auth().currentUser?.uid &&
            (profile == null ||
                (saved.updatedAt ?? 0) >= (profile.updatedAt ?? 0)))
        ? saved
        : profile;

    setState(() {
      _profile = newest;
      _workouts = workouts;
      _byDay = byDay;
      _weekSets = weekSets;
      _loading = false;
    });
  }

  Future<void> _openWorkout(Workout workout) async {
    if (workout.id == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDetailPage(
          workoutId: workout.id!,
          showRepeat: false,
        ),
      ),
    );

    if (mounted) {
      _loadData();
    }
  }

  int get _streak {
    final today = dayOnly(DateTime.now());

    var cursor = _byDay.containsKey(today)
        ? today
        : today.subtract(
            const Duration(days: 1),
          );

    var count = 0;

    while (_byDay.containsKey(cursor)) {
      count++;

      cursor = cursor.subtract(
        const Duration(days: 1),
      );
    }

    return count;
  }

  int get _daysThisWeek {
    final today = dayOnly(DateTime.now());

    final start = today.subtract(
      Duration(days: today.weekday - 1),
    );

    final end = start.add(
      const Duration(days: 7),
    );

    return _byDay.keys
        .where(
          (date) =>
              !date.isBefore(start) &&
              date.isBefore(end),
        )
        .length;
  }

  int get _weeklyGoal {
    switch (_profile?.fitnessLevel) {
      case 'Advanced':
        return 5;
      case 'Intermediate':
        return 4;
      default:
        return 3;
    }
  }

  bool get _workedOutToday {
    return _byDay.containsKey(
      dayOnly(DateTime.now()),
    );
  }

  Suggestion _buildSuggestion() {
    return buildSuggestion(
      profile: _profile,
      workouts: _workouts,
    );
  }

  void _startSuggestion() {
    final suggestion = _buildSuggestion();
    final callback = widget.onStartSuggestion;

    if (callback != null) {
      callback(suggestion);
    } else {
      widget.onGoToTab(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: kAccent,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: kAccent,
              backgroundColor: kSurface,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  24,
                ),
                children: [
                  HomeHeader(
                    profile: _profile,
                    onAvatarTap: () =>
                        widget.onGoToTab(4),
                    onBellTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _HomeSearchCard(
                    onTap:
                        widget.onOpenExerciseLibrary,
                  ),
                  const SizedBox(height: 18),
                  SummaryBanner(
                    done: _daysThisWeek,
                    goal: _weeklyGoal,
                    streak: _streak,
                  ),
                  const SectionTitle(
                    'Workout Calendar',
                  ),
                  CalendarCard(
                    byDay: _byDay,
                    onOpenWorkout: _openWorkout,
                  ),
                  const SectionTitle(
                    'This Week',
                  ),
                  WeeklyChartCard(
                    values: _weekSets,
                  ),
                  SectionTitle(
                    _workedOutToday
                        ? 'Suggested Next Session'
                        : 'Suggested For Today',
                  ),
                  SuggestionCard(
                    suggestion: _buildSuggestion(),
                    onStart: _startSuggestion,
                  ),
                  SectionTitle(
                    'Recent Workouts',
                    trailing: TextButton(
                      onPressed: () =>
                          widget.onGoToTab(2),
                      child: const Text(
                        'See all',
                      ),
                    ),
                  ),
                  RecentWorkouts(
                    workouts: _workouts,
                    onOpen: _openWorkout,
                  ),
                  const SizedBox(height: 20),
                  const TipCard(),
                ],
              ),
            ),
    );
  }
}

class _HomeSearchCard extends StatelessWidget {
  final VoidCallback? onTap;

  const _HomeSearchCard({
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: kAccent.withValues(alpha: .12),
        highlightColor: kAccent.withValues(alpha: .06),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: kAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search exercises or workouts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
  }
}