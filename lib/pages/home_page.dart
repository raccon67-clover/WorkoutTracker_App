import 'package:flutter/material.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import 'homepage/dashboard_tab.dart';
import 'homepage/workout_suggestion.dart';
import 'log_workout_page.dart';
import 'profile_page.dart';
import 'progress_page.dart';
import 'workout_history_page.dart';
import 'exercise_library_page.dart';
import '../data/exercise_catalog.dart';
import '../models/workout.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  int _dashRefreshToken = 0;
  List<CatalogExercise> _pendingExercises = const [];
  bool _workoutActive = false;

  int _logVisit = 0;
  int _profileVisit = 0;
  int _launchToken = 0;
  Suggestion? _launch;

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.add_circle_rounded, label: 'Log'),
    _NavItem(icon: Icons.history_rounded, label: 'History'),
    _NavItem(icon: Icons.insights_rounded, label: 'Progress'),
    _NavItem(icon: Icons.person_rounded, label: 'Profile'),
  ];

  void _goToTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 1) _logVisit++;
      if (index == 4) _profileVisit++;
    });
  }

  void _openExerciseLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseLibraryPage(
          onAddToLog: (exercises) {
            setState(() {
              _pendingExercises = exercises;
              _logVisit++;
              _currentIndex = 1;
            });
          },
        ),
      ),
    );
  }

  void _startSuggestion(Suggestion s) {
    setState(() {
      _launch = s;
      _launchToken++;
      _logVisit++;
      _currentIndex = 1;
    });
  }

  void _repeatWorkout(Workout workout) {
    final selected = workout.exercises
        .map((e) => ExerciseCatalog.byName(e.name))
        .whereType<CatalogExercise>()
        .toList();

    setState(() {
      _pendingExercises = selected;
      _logVisit++;
      _currentIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      DashboardTab(
        refreshToken: _dashRefreshToken,
        onGoToTab: _goToTab,
        onStartSuggestion: _startSuggestion,
        onOpenExerciseLibrary: _openExerciseLibrary,
      ),
      LogWorkoutPage(
        initialExercises: _pendingExercises,
        initialExercisesToken: _logVisit,
        launch: _launch,
        launchToken: _launchToken,
        visitToken: _logVisit,
        onSaved: () {
          _dashRefreshToken++;
          _goToTab(0);
        },
        onLaunchConsumed: () {
          if (mounted && _launch != null) setState(() => _launch = null);
        },
        onInitialExercisesConsumed: () {
          if (mounted && _pendingExercises.isNotEmpty) {
            setState(() => _pendingExercises = const []);
          }
        },
        onSessionChanged: (active) {
          if (mounted && _workoutActive != active) {
            setState(() => _workoutActive = active);
          }
        },
      ),
      WorkoutHistoryPage(
        refreshToken: _dashRefreshToken,
        onRepeatWorkout: _repeatWorkout,
      ),
      ProgressPage(refreshToken: _dashRefreshToken),
      ProfilePage(visitToken: _profileVisit),
    ];

    return PopScope(
      // On the Home tab, Back exits the app as normal.
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // During a workout / summary, the Log page handles Back itself.
        if (_workoutActive) return;
        _goToTab(0);
      },
      child: Scaffold(
        backgroundColor: kBackground,
        body: IndexedStack(index: _currentIndex, children: tabs),
        bottomNavigationBar: _workoutActive
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    height: 66,
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: List.generate(_navItems.length, (index) {
                        final item = _navItems[index];
                        final selected = _currentIndex == index;
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goToTab(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? kAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: selected
                                        ? Colors.white
                                        : Colors.grey[500],
                                    size: 23,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: selected
                                          ? Colors.white
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}