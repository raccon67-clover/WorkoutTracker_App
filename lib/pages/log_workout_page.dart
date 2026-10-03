import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/exercise_catalog.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../models/workout.dart';
import '../services/database_service.dart';
import 'exercise_picker_page.dart';
import 'homepage/workout_suggestion.dart';

const int _defaultSets = 3;
const int _defaultRestSeconds = 60;
const int _repPaceSeconds = 3;

String _exerciseImageUrl(String name) {
  final slug = name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-').replaceAll(RegExp(r'^-|-$'), '');
  return 'https://exercise-dataset.com/images/flat/$slug-start.webp';
}

class _SetEntry {
  int target;
  bool completed;

  _SetEntry({required this.target, this.completed = false});

  Map<String, dynamic> toJson() => {
        'target': target,
        'completed': completed,
      };

  factory _SetEntry.fromJson(Map<String, dynamic> json, int fallbackTarget) =>
      _SetEntry(
        target: (json['target'] as num?)?.toInt() ?? fallbackTarget,
        completed: json['completed'] == true,
      );
}

class _CustomWorkoutTemplate {
  final String id;
  String name;
  int restSeconds;
  List<Map<String, dynamic>> exercises;

  _CustomWorkoutTemplate({
    required this.id,
    required this.name,
    required this.restSeconds,
    required this.exercises,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'restSeconds': restSeconds,
        'exercises': exercises,
      };

  factory _CustomWorkoutTemplate.fromJson(Map<String, dynamic> json) =>
      _CustomWorkoutTemplate(
        id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name']?.toString() ?? 'Custom Workout',
        restSeconds: (json['restSeconds'] as num?)?.toInt() ?? _defaultRestSeconds,
        exercises: (json['exercises'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [],
      );
}

class _ActiveExercise {
  final CatalogExercise catalog;
  final List<_SetEntry> sets;

  _ActiveExercise(this.catalog, this.sets);

  int get completedCount => sets.where((s) => s.completed).length;

  Map<String, dynamic> toJson() => {
        'name': catalog.name,
        'sets': sets.map((s) => s.toJson()).toList(),
      };
}

/// Totals shown on the "Workout Complete" screen.
class _Summary {
  final String name;
  final int exercises;
  final int sets;
  final int seconds;

  const _Summary(this.name, this.exercises, this.sets, this.seconds);
}

class LogWorkoutPage extends StatefulWidget {
  final Suggestion? launch;
  final List<CatalogExercise> initialExercises;
  final int initialExercisesToken;
  final int launchToken;
  final int visitToken;
  final VoidCallback? onSaved;
  final VoidCallback? onLaunchConsumed;
  final VoidCallback? onInitialExercisesConsumed;
  final ValueChanged<bool>? onSessionChanged;

  const LogWorkoutPage({
    super.key,
    this.launch,
    this.initialExercises = const [],
    this.initialExercisesToken = 0,
    this.launchToken = 0,
    this.visitToken = 0,
    this.onSaved,
    this.onLaunchConsumed,
    this.onInitialExercisesConsumed,
    this.onSessionChanged,
  });

  @override
  State<LogWorkoutPage> createState() => _LogWorkoutPageState();
}

class _LogWorkoutPageState extends State<LogWorkoutPage> {
  final _nameController = TextEditingController(text: 'My Workout');
  final _notesController = TextEditingController();
  final List<_ActiveExercise> _exercises = [];
  final List<_CustomWorkoutTemplate> _customWorkouts = [];
  String? _editingCustomId;
  bool _buildingCustom = false;
  bool _customPreviewing = false;

  Timer? _ticker;
  DateTime? _startedAt;
  DateTime? _workoutStartedDate;
  int _elapsedBeforeStart = 0;
  DateTime? _setEndsAt;
  DateTime? _restEndsAt;
  int _restDuration = _defaultRestSeconds;
  int _currentExercise = 0;
  int _currentSet = 0;
  int _liveReps = 0;
  bool _started = false;
  bool _paused = false;
  bool _saving = false;
  bool _completedAutomatically = false;
  bool _setRunning = false;
  bool _restRunning = false;
  bool _discarding = false;
  bool _isSuggestedWorkout = false;
  String _suggestedPreviewReason = '';
  int _pausedSetRemaining = 0;
  int _pausedRestRemaining = 0;
  _Summary? _summary;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadCustomWorkouts();
    await _loadPausedWorkout();
    if (!mounted) return;
    if (widget.launch != null && !_started) {
      if (!_isSuggestedWorkout) {
        _prepareSuggestedPreview(widget.launch!);
        setState(() {});
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLaunchConsumed?.call();
      });
    }
    if (widget.initialExercises.isNotEmpty && _exercises.isEmpty) {
      _isSuggestedWorkout = false;
      _addCatalogExercises(widget.initialExercises);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInitialExercisesConsumed?.call();
      });
    }
  }

  @override
  void didUpdateWidget(LogWorkoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSuggestion =
        widget.launch != null && widget.launchToken != oldWidget.launchToken;
    final newCustomSelection =
        widget.initialExercisesToken != oldWidget.initialExercisesToken &&
            widget.initialExercises.isNotEmpty;

    if (newSuggestion) {
      if (!_started && widget.launch != null) {
        _prepareSuggestedPreview(widget.launch!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLaunchConsumed?.call();
      });
      return;
    }

    if (newCustomSelection) {
      _isSuggestedWorkout = false;
      _addCatalogExercises(widget.initialExercises);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInitialExercisesConsumed?.call();
      });
      return;
    }

    if (widget.visitToken != oldWidget.visitToken &&
        !_started &&
        widget.launch == null &&
        widget.initialExercises.isEmpty) {
      if (_isSuggestedWorkout) {
        _resetToCustomSetup();
      } else if (mounted) {
        setState(() => _isSuggestedWorkout = false);
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _targetFor(CatalogExercise exercise) {
    if (exercise.kind == ExerciseKind.timed) {
      if (exercise.name == 'Side Plank') return 20;
      return 30;
    }
    if (exercise.kind == ExerciseKind.cardio) {
      if (exercise.name == 'HIIT') return 1;
      return 5;
    }
    if (exercise.muscle == Muscle.core) return 12;
    return 10;
  }

  String _targetLabel(CatalogExercise exercise, int target) {
    switch (exercise.kind) {
      case ExerciseKind.strength:
        return '$target reps';
      case ExerciseKind.timed:
        return '${target}s';
      case ExerciseKind.cardio:
        return '$target min';
    }
  }

  String _targetTitle(CatalogExercise exercise) {
    switch (exercise.kind) {
      case ExerciseKind.strength:
        return 'Suggested reps';
      case ExerciseKind.timed:
        return 'Suggested time';
      case ExerciseKind.cardio:
        return 'Suggested duration';
    }
  }

  List<_SetEntry> _makeSets(CatalogExercise exercise, [int count = _defaultSets, int? customTarget]) {
    final target = customTarget ?? _targetFor(exercise);
    return List.generate(count, (_) => _SetEntry(target: target));
  }

  Future<void> _loadCustomWorkouts() async {
    try {
      final raw = await DatabaseService.instance.getCustomWorkouts();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _customWorkouts
        ..clear()
        ..addAll(decoded.whereType<Map>().map((e) =>
            _CustomWorkoutTemplate.fromJson(Map<String, dynamic>.from(e))));
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Custom workout load failed: $e');
    }
  }

  Future<void> _persistCustomWorkouts() async {
    await DatabaseService.instance.saveCustomWorkouts(
      jsonEncode(_customWorkouts.map((e) => e.toJson()).toList()),
    );
  }

  void _beginCreateCustom() {
    _ticker?.cancel();
    setState(() {
      _editingCustomId = null;
      _buildingCustom = true;
      _customPreviewing = false;
      _isSuggestedWorkout = false;
      _exercises.clear();
      _nameController.text = '';
      _notesController.clear();
      _restDuration = _defaultRestSeconds;
      _started = false;
      _paused = false;
    });
  }

  void _editCustom(_CustomWorkoutTemplate template) {
    final loaded = <CatalogExercise>[];
    final counts = <String, int>{};
    final targets = <String, int>{};
    for (final raw in template.exercises) {
      final name = raw['name']?.toString() ?? '';
      final exercise = ExerciseCatalog.byName(name);
      if (exercise == null) continue;
      loaded.add(exercise);
      final key = name.toLowerCase();
      counts[key] = (raw['sets'] as num?)?.toInt() ?? _defaultSets;
      targets[key] = (raw['target'] as num?)?.toInt() ?? _targetFor(exercise);
    }
    setState(() {
      _editingCustomId = template.id;
      _buildingCustom = true;
      _customPreviewing = false;
      _isSuggestedWorkout = false;
      _nameController.text = template.name;
      _restDuration = template.restSeconds;
      _exercises
        ..clear()
        ..addAll(loaded.map((e) => _ActiveExercise(
          e,
          _makeSets(e, counts[e.name.toLowerCase()] ?? _defaultSets, targets[e.name.toLowerCase()]),
        )));
    });
  }

  Future<void> _deleteCustom(_CustomWorkoutTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Delete custom workout?', style: TextStyle(color: Colors.white)),
        content: Text('Delete "${template.name}"?', style: TextStyle(color: Colors.grey[400])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    _customWorkouts.removeWhere((e) => e.id == template.id);
    await _persistCustomWorkouts();
    if (mounted) setState(() {});
  }

  Future<void> _saveCustomTemplate() async {
    if (_isSuggestedWorkout || _exercises.isEmpty) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give your custom workout a name.')));
      return;
    }
    final id = _editingCustomId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final template = _CustomWorkoutTemplate(
      id: id,
      name: name,
      restSeconds: _restDuration,
      exercises: _exercises.map((e) => {
        'name': e.catalog.name,
        'sets': e.sets.length,
        'target': e.sets.isEmpty ? _targetFor(e.catalog) : e.sets.first.target,
      }).toList(),
    );
    final index = _customWorkouts.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _customWorkouts[index] = template;
    } else {
      _customWorkouts.insert(0, template);
    }
    _editingCustomId = id;
    await _persistCustomWorkouts();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom workout saved.')));
    }
  }

  void _previewCustomTemplate(_CustomWorkoutTemplate template) {
    final loaded = <CatalogExercise>[];
    final counts = <String, int>{};
    final targets = <String, int>{};

    for (final raw in template.exercises) {
      final name = raw['name']?.toString() ?? '';
      final exercise = ExerciseCatalog.byName(name);
      if (exercise == null) continue;
      loaded.add(exercise);
      final key = name.toLowerCase();
      counts[key] = (raw['sets'] as num?)?.toInt() ?? _defaultSets;
      targets[key] = (raw['target'] as num?)?.toInt() ?? _targetFor(exercise);
    }

    _ticker?.cancel();
    DatabaseService.instance.clearActiveWorkout();

    setState(() {
      _customPreviewing = true;
      _buildingCustom = false;
      _isSuggestedWorkout = false;
      _editingCustomId = template.id;
      _nameController.text = template.name;
      _restDuration = template.restSeconds;
      _exercises
        ..clear()
        ..addAll(loaded.map((e) => _ActiveExercise(
          e,
          _makeSets(
            e,
            counts[e.name.toLowerCase()] ?? _defaultSets,
            targets[e.name.toLowerCase()],
          ),
        )));
      _currentExercise = 0;
      _currentSet = 0;
      _liveReps = 0;
      _started = false;
      _paused = false;
      _startedAt = null;
      _workoutStartedDate = null;
      _elapsedBeforeStart = 0;
      _setRunning = false;
      _restRunning = false;
      _setEndsAt = null;
      _restEndsAt = null;
      _completedAutomatically = false;
      _saving = false;
      _discarding = false;
    });
  }

  void _closeCustomPreview() {
    _ticker?.cancel();
    DatabaseService.instance.clearActiveWorkout();
    setState(() {
      _customPreviewing = false;
      _editingCustomId = null;
      _exercises.clear();
      _nameController.text = 'My Workout';
      _currentExercise = 0;
      _currentSet = 0;
      _liveReps = 0;
    });
  }

  void _closeCustomBuilder() {
    _ticker?.cancel();
    setState(() {
      _buildingCustom = false;
      _editingCustomId = null;
      _exercises.clear();
      _nameController.text = 'My Workout';
      _currentExercise = 0;
      _currentSet = 0;
      _liveReps = 0;
    });
  }

  void _editPreviewedCustom() {
    final template = _customWorkouts.firstWhere(
      (e) => e.id == _editingCustomId,
      orElse: () => _CustomWorkoutTemplate(
        id: '',
        name: 'Custom Workout',
        restSeconds: _defaultRestSeconds,
        exercises: [],
      ),
    );
    if (template.id.isEmpty) return;
    _customPreviewing = false;
    _editCustom(template);
  }

  Future<void> _loadPausedWorkout() async {
    try {
      final raw = await DatabaseService.instance.getActiveWorkout();
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['exercises'] is! List) return;
      _restore(data);
      if (mounted) {
        setState(() {});
        widget.onSessionChanged?.call(true);
      }
      _startTicker();
    } catch (e) {
      debugPrint('Paused workout restore failed: $e');
    }
  }

  void _restore(Map<String, dynamic> data) {
    _exercises.clear();
    _isSuggestedWorkout = data['isSuggested'] == true;
    _nameController.text = data['name']?.toString().isNotEmpty == true
        ? data['name'].toString()
        : 'My Workout';
    _notesController.text = data['notes']?.toString() ?? '';
    _elapsedBeforeStart = (data['elapsedBeforeStart'] as num?)?.toInt() ?? 0;
    _started = data['started'] == true;
    _paused = true;
    _restDuration = (data['restDuration'] as num?)?.toInt() ?? _defaultRestSeconds;
    _currentExercise = (data['currentExercise'] as num?)?.toInt() ?? 0;
    _currentSet = (data['currentSet'] as num?)?.toInt() ?? 0;
    final dateMs = (data['workoutStartedDateMs'] as num?)?.toInt();
    _workoutStartedDate = dateMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dateMs);

    final list = data['exercises'] as List? ?? const [];
    for (final raw in list) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString() ?? '';
      final catalog = ExerciseCatalog.byName(name);
      if (catalog == null) continue;
      final fallback = _targetFor(catalog);
      final setsRaw = raw['sets'] as List? ?? const [];
      final sets = setsRaw
          .whereType<Map>()
          .map((m) => _SetEntry.fromJson(Map<String, dynamic>.from(m), fallback))
          .toList();
      _exercises.add(_ActiveExercise(
        catalog,
        sets.isEmpty ? _makeSets(catalog) : sets,
      ));
    }
    if (_currentExercise >= _exercises.length) _currentExercise = 0;
    if (_exercises.isNotEmpty && _currentSet >= _exercises[_currentExercise].sets.length) {
      _currentSet = 0;
    }
    _liveReps = (data['liveReps'] as num?)?.toInt() ?? 0;
    _setRunning = data['setRunning'] == true;
    _restRunning = data['restRunning'] == true;
    _pausedSetRemaining = (data['pausedSetRemaining'] as num?)?.toInt() ?? 0;
    _pausedRestRemaining = (data['pausedRestRemaining'] as num?)?.toInt() ?? 0;
    _setEndsAt = null;
    _restEndsAt = null;
  }

  Map<String, dynamic> _stateJson() => {
        'name': _nameController.text.trim().isEmpty ? 'My Workout' : _nameController.text.trim(),
        'isSuggested': _isSuggestedWorkout,
        'notes': _notesController.text,
        'started': _started,
        'paused': _paused,
        'elapsedBeforeStart': _elapsedSeconds,
        'restDuration': _restDuration,
        'currentExercise': _currentExercise,
        'currentSet': _currentSet,
        'workoutStartedDateMs': _workoutStartedDate?.millisecondsSinceEpoch,
        'setRunning': _setRunning,
        'restRunning': _restRunning,
        'liveReps': _liveReps,
        'pausedSetRemaining': _pausedSetRemaining,
        'pausedRestRemaining': _pausedRestRemaining,
        'exercises': _exercises.map((e) => e.toJson()).toList(),
      };

  Future<void> _persistPausedState() async {
    if (!_started || !_paused) return;
    try {
      await DatabaseService.instance.saveActiveWorkout(jsonEncode(_stateJson()));
    } catch (e) {
      debugPrint('Paused workout save failed: $e');
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_started || _paused) return;
      _tick();
    });
  }

  void _tick() {
    if (_setRunning && _setEndsAt != null && !DateTime.now().isBefore(_setEndsAt!)) {
      _finishCurrentSet();
    } else if (_setRunning && _exercises.isNotEmpty) {
      final exercise = _exercises[_currentExercise];
      final set = exercise.sets[_currentSet];
      final elapsed = DateTime.now().difference(_setEndsAt!.subtract(_durationForSet(exercise.catalog, set.target))).inMilliseconds;
      final seconds = elapsed ~/ 1000;
      final nextReps = exercise.catalog.kind == ExerciseKind.strength
          ? (seconds ~/ _repPaceSeconds).clamp(0, set.target).toInt()
          : _liveReps;
      if (nextReps != _liveReps) {
        _liveReps = nextReps;
      }
    }

    if (_restRunning && _restEndsAt != null && !DateTime.now().isBefore(_restEndsAt!)) {
      _restRunning = false;
      _restEndsAt = null;
      _advanceToNextSet();
      _startCurrentSet();
    }

    if (mounted && _started && !_paused) setState(() {});
  }

  Duration _durationForSet(CatalogExercise exercise, int target) {
    switch (exercise.kind) {
      case ExerciseKind.strength:
        return Duration(seconds: target * _repPaceSeconds);
      case ExerciseKind.timed:
        return Duration(seconds: target);
      case ExerciseKind.cardio:
        return Duration(minutes: target);
    }
  }

  int get _elapsedSeconds {
    if (!_started || _startedAt == null || _paused) return _elapsedBeforeStart;
    return _elapsedBeforeStart + DateTime.now().difference(_startedAt!).inSeconds;
  }

  int get _setRemaining {
    if (_setEndsAt == null) return 0;
    final n = _setEndsAt!.difference(DateTime.now()).inMilliseconds;
    return n <= 0 ? 0 : (n / 1000).ceil();
  }

  int get _restRemaining {
    if (_restEndsAt == null) return 0;
    final n = _restEndsAt!.difference(DateTime.now()).inMilliseconds;
    return n <= 0 ? 0 : (n / 1000).ceil();
  }

  double _setProgress(CatalogExercise exercise, int target) {
    final totalSeconds = _durationForSet(exercise, target).inSeconds;
    if (totalSeconds <= 0) return 0;

    final remaining = _paused ? _pausedSetRemaining : _setRemaining;
    return (1 - (remaining / totalSeconds)).clamp(0.0, 1.0);
  }

  String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _prepareSuggestedPreview(Suggestion suggestion) {
    final names = suggestion.exercises
        .map(ExerciseCatalog.byName)
        .whereType<CatalogExercise>()
        .toList();
    if (names.isEmpty) return;

    _ticker?.cancel();
    unawaited(DatabaseService.instance.clearActiveWorkout());

    _isSuggestedWorkout = true;
    _customPreviewing = false;
    _buildingCustom = false;
    _editingCustomId = null;
    _suggestedPreviewReason = suggestion.reason;
    _nameController.text = suggestion.title;
    _restDuration = _defaultRestSeconds;
    _exercises
      ..clear()
      ..addAll(names.map((e) => _ActiveExercise(e, _makeSets(e))));
    _currentExercise = 0;
    _currentSet = 0;
    _liveReps = 0;
    _started = false;
    _paused = false;
    _startedAt = null;
    _workoutStartedDate = null;
    _elapsedBeforeStart = 0;
    _setRunning = false;
    _restRunning = false;
    _setEndsAt = null;
    _restEndsAt = null;
    _completedAutomatically = false;
    _saving = false;
    _discarding = false;
  }

  void _handleLaunch(Suggestion suggestion) {
    if (_started && _exercises.isNotEmpty) return;
    _prepareSuggestedPreview(suggestion);
    if (mounted) setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLaunchConsumed?.call();
    });
  }

  void _closeSuggestedPreview() {
    _ticker?.cancel();
    DatabaseService.instance.clearActiveWorkout();
    setState(() {
      _isSuggestedWorkout = false;
      _suggestedPreviewReason = '';
      _exercises.clear();
      _nameController.text = 'My Workout';
      _currentExercise = 0;
      _currentSet = 0;
      _liveReps = 0;
    });
  }

  void _resetToCustomSetup() {
    _ticker?.cancel();
    _started = false;
    _paused = false;
    _setRunning = false;
    _restRunning = false;
    _completedAutomatically = false;
    _setEndsAt = null;
    _restEndsAt = null;
    _startedAt = null;
    _workoutStartedDate = null;
    _elapsedBeforeStart = 0;
    _liveReps = 0;
    _currentExercise = 0;
    _currentSet = 0;
    _pausedSetRemaining = 0;
    _pausedRestRemaining = 0;
    _discarding = false;
    _saving = false;
    _completedAutomatically = false;
    _isSuggestedWorkout = false;
    _customPreviewing = false;
    _suggestedPreviewReason = '';
    _exercises.clear();
    _nameController.text = 'My Workout';
    _notesController.clear();
    if (mounted) setState(() {});
  }

  void _addCatalogExercises(List<CatalogExercise> exercises) {
    final existing = _exercises.map((e) => e.catalog.name.toLowerCase()).toSet();
    for (final c in exercises) {
      if (existing.add(c.name.toLowerCase())) {
        _exercises.add(_ActiveExercise(c, _makeSets(c)));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickExercises() async {
    final selected = await Navigator.push<List<CatalogExercise>>(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePickerPage(
          alreadyAdded: _exercises.map((e) => e.catalog.name.toLowerCase()).toSet(),
        ),
      ),
    );
    if (selected != null && selected.isNotEmpty) _addCatalogExercises(selected);
  }

  void _startWorkout() {
    if (_exercises.isEmpty) {
      _pickExercises();
      return;
    }
    setState(() {
      _started = true;
      _paused = false;
      _startedAt = DateTime.now();
      _workoutStartedDate ??= DateTime.now();
      _currentExercise = _firstIncompleteExercise();
      _currentSet = _firstIncompleteSet(_currentExercise);
      _liveReps = 0;
    });
    widget.onSessionChanged?.call(true);
    _startTicker();

    _startCurrentSet();
  }

  int _firstIncompleteExercise() {
    for (var i = 0; i < _exercises.length; i++) {
      if (_exercises[i].completedCount < _exercises[i].sets.length) return i;
    }
    return 0;
  }

  int _firstIncompleteSet(int exerciseIndex) {
    final sets = _exercises[exerciseIndex].sets;
    for (var i = 0; i < sets.length; i++) {
      if (!sets[i].completed) return i;
    }
    return 0;
  }

  void _togglePause() {
    if (!_started) return;
    if (_paused) {
      setState(() {
        _paused = false;
        _startedAt = DateTime.now();
        if (_setRunning && _pausedSetRemaining > 0) {
          _setEndsAt = DateTime.now().add(Duration(seconds: _pausedSetRemaining));
        }
        if (_restRunning && _pausedRestRemaining > 0) {
          _restEndsAt = DateTime.now().add(Duration(seconds: _pausedRestRemaining));
        }
      });
      _startTicker();
    } else {
      final setRemaining = _setRunning && _setEndsAt != null ? _setRemaining : 0;
      final restRemaining = _restRunning && _restEndsAt != null ? _restRemaining : 0;
      setState(() {
        _elapsedBeforeStart = _elapsedSeconds;
        _startedAt = null;
        _paused = true;
        _pausedSetRemaining = setRemaining;
        _pausedRestRemaining = restRemaining;
        _setEndsAt = null;
        _restEndsAt = null;
      });
      _persistPausedState();
    }
  }

  void _startCurrentSet() {
    if (_paused || _exercises.isEmpty) return;
    final exercise = _exercises[_currentExercise];
    final set = exercise.sets[_currentSet];
    if (set.completed) return;
    setState(() {
      _setRunning = true;
      _restRunning = false;
      _restEndsAt = null;
      _liveReps = 0;
      _setEndsAt = DateTime.now().add(_durationForSet(exercise.catalog, set.target));
      _pausedSetRemaining = 0;
      _pausedRestRemaining = 0;
    });
  }

  void _finishCurrentSet() {
    if (_exercises.isEmpty || _saving || _completedAutomatically) return;
    final exercise = _exercises[_currentExercise];
    final set = exercise.sets[_currentSet];
    set.completed = true;
    _setRunning = false;
    _setEndsAt = null;
    _liveReps = set.target;

    final workoutComplete = _exercises.every((e) => e.completedCount == e.sets.length);
    if (workoutComplete) {
      _restRunning = false;
      _restEndsAt = null;
      _completedAutomatically = true;

      _elapsedBeforeStart = _elapsedSeconds;
      _startedAt = null;
      _ticker?.cancel();
      _ticker = null;

      unawaited(_saveCompletedWorkout());
      return;
    }
    _startRest();
  }

  void _startRest([int? seconds]) {
    final duration = seconds ?? _restDuration;
    setState(() {
      _restDuration = duration;
      _restRunning = true;
      _restEndsAt = DateTime.now().add(Duration(seconds: duration));
      _pausedRestRemaining = 0;
    });
  }

  void _advanceToNextSet() {
    if (_exercises.isEmpty) return;
    final exercise = _exercises[_currentExercise];
    if (_currentSet + 1 < exercise.sets.length) {
      _currentSet++;
    } else if (_currentExercise + 1 < _exercises.length) {
      _currentExercise++;
      _currentSet = 0;
    } else {
      _liveReps = 0;
      return;
    }
    _liveReps = 0;
  }

  Future<void> _saveCompletedWorkout() async {
    if (_saving || !mounted || _exercises.isEmpty) return;
    setState(() => _saving = true);

    try {
      final items = <ExerciseWithSets>[];
      for (final active in _exercises) {
        final completed = <ExerciseSet>[];
        for (var i = 0; i < active.sets.length; i++) {
          final row = active.sets[i];
          if (!row.completed) continue;
          if (active.catalog.kind == ExerciseKind.strength) {
            completed.add(ExerciseSet(
              exerciseId: 0,
              setNumber: i + 1,
              reps: row.target,
            ));
          } else {
            final seconds = active.catalog.kind == ExerciseKind.cardio
                ? row.target * 60
                : row.target;
            completed.add(ExerciseSet(
              exerciseId: 0,
              setNumber: i + 1,
              durationSeconds: seconds,
            ));
          }
        }
        if (completed.isEmpty) continue;
        final reps = completed.fold<int>(0, (a, b) => a + b.reps);
        final duration = completed.fold<int>(0, (a, b) => a + b.durationSeconds);
        items.add(ExerciseWithSets(
          exercise: Exercise(
            workoutId: 0,
            name: active.catalog.name,
            sets: completed.length,
            reps: reps,
            durationSeconds: duration,
          ),
          sets: completed,
        ));
      }

      final workoutName = _nameController.text.trim();
      await DatabaseService.instance.saveWorkout(
        Workout(
          name: workoutName.isEmpty ? 'My Workout' : workoutName,
          date: _workoutStartedDate ?? DateTime.now(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          durationSeconds: _elapsedSeconds,
          isSuggested: _isSuggestedWorkout,
        ),
        items,
      );
      await DatabaseService.instance.clearActiveWorkout();
      if (!mounted) return;

      // Capture the totals BEFORE the state below gets reset.
      final summary = _Summary(
        workoutName.isEmpty ? 'My Workout' : workoutName,
        items.length,
        items.fold<int>(0, (sum, item) => sum + item.sets.length),
        _elapsedSeconds,
      );

      _ticker?.cancel();
      _ticker = null;
      setState(() {
        _saving = false;
        _started = false;
        _paused = false;
        _setRunning = false;
        _restRunning = false;
        _setEndsAt = null;
        _restEndsAt = null;
        _startedAt = null;
        _workoutStartedDate = null;
        _elapsedBeforeStart = 0;
        _liveReps = 0;
        _currentExercise = 0;
        _currentSet = 0;
        _pausedSetRemaining = 0;
        _pausedRestRemaining = 0;
        _completedAutomatically = false;
        _exercises.clear();
        _nameController.text = 'My Workout';
        _notesController.clear();
        _isSuggestedWorkout = false;
        _buildingCustom = false;
        _editingCustomId = null;
        _summary = summary; // show the "Workout Complete" screen
      });
      // NOTE: onSessionChanged(false) and onSaved() now run when the user
      // presses Done (see _doneSummary), so the bottom nav stays hidden
      // and the app doesn't jump away from the summary.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _completedAutomatically = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save workout: $e')),
      );
    }
  }

  void _doneSummary() {
    setState(() => _summary = null);
    widget.onSessionChanged?.call(false); // bottom nav comes back
    widget.onSaved?.call(); // refresh dashboard + go to Home tab
  }

  Future<bool> _discardWorkout() async {
    if (_saving || _discarding) return false;
    if (!_started) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Leave workout?', style: TextStyle(color: Colors.white)),
        content: const Text('Your current workout progress will be reset to 0. This workout will not be saved.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave & Reset')),
        ],
      ),
    );
    if (confirmed != true) return false;
    _discarding = true;
    await DatabaseService.instance.clearActiveWorkout();
    widget.onSessionChanged?.call(false);
    return true;
  }

  Future<void> _leaveFromActiveWorkout() async {
    if (_saving || _discarding) return;
    final leave = await _discardWorkout();
    if (!leave || !mounted) return;

    _ticker?.cancel();
    _started = false;
    _paused = false;
    _setRunning = false;
    _restRunning = false;
    _setEndsAt = null;
    _restEndsAt = null;
    _startedAt = null;
    _workoutStartedDate = null;
    _elapsedBeforeStart = 0;
    _liveReps = 0;
    _currentExercise = 0;
    _currentSet = 0;
    _pausedSetRemaining = 0;
    _pausedRestRemaining = 0;
    _discarding = false;
    _saving = false;
    _isSuggestedWorkout = false;
    _buildingCustom = false;
    _editingCustomId = null;
    _exercises.clear();
    _nameController.text = 'My Workout';
    _notesController.clear();
    setState(() {});
  }

  Widget _timerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Text('WORKOUT TIME', style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(_clock(_elapsedSeconds), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _togglePause,
            icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            label: Text(_paused ? 'Resume Workout' : 'Pause Workout'),
          ),
        ],
      ),
    );
  }

  Widget _activeExerciseCard() {
    final exercise = _exercises[_currentExercise];
    final set = exercise.sets[_currentSet];
    final target = set.target;
    final isLastSet = _currentSet == exercise.sets.length - 1;
    final completedSets = exercise.completedCount;
    final total = exercise.sets.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Text('EXERCISE ${_currentExercise + 1} OF ${_exercises.length}', style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          const SizedBox(height: 12),
          Container(width: 64, height: 64, decoration: BoxDecoration(color: kAccent.withValues(alpha: .14), borderRadius: BorderRadius.circular(18)), child: Icon(exercise.catalog.equipment.icon, color: kAccent, size: 32)),
          const SizedBox(height: 12),
          Text(exercise.catalog.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(exercise.catalog.subtitle, style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 18),
          Text('SET ${_currentSet + 1} OF $total', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_targetLabel(exercise.catalog, target), style: const TextStyle(color: kAccent, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(_targetTitle(exercise.catalog), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 24),
          if (_setRunning) ...[
            Text(
              exercise.catalog.kind == ExerciseKind.strength ? '$_liveReps / $target reps' : _clock(_setRemaining),
              style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              exercise.catalog.kind == ExerciseKind.strength
                  ? 'Guided rep timer · one rep every $_repPaceSeconds seconds'
                  : 'Keep going until the timer reaches zero',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: exercise.catalog.kind == ExerciseKind.strength
                  ? (target == 0 ? 0 : (_liveReps / target).clamp(0.0, 1.0))
                  : _setProgress(exercise.catalog, target),
              minHeight: 7,
              backgroundColor: kBackground,
              valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
            ),
          ] else if (_restRunning) ...[
            Text('REST', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(_clock(_restRemaining), style: const TextStyle(color: kAccent, fontSize: 48, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Next set starts automatically', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ] else if (set.completed) ...[
            const Icon(Icons.check_circle_rounded, color: kAccent, size: 52),
            const SizedBox(height: 8),
            const Text('Set complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ] else ...[
            const SizedBox(height: 8),
            const Text('Preparing next set...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                Container(width: 9, height: 9, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: i < completedSets ? kAccent : i == _currentSet ? Colors.white : Colors.grey[700])),
            ],
          ),
          if (isLastSet && exercise.completedCount == total && _currentExercise < _exercises.length - 1)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('Next: ${_exercises[_currentExercise + 1].catalog.name}', style: TextStyle(color: Colors.grey[500], fontSize: 12))),
        ],
      ),
    );
  }

  Widget _restSettings() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('REST BETWEEN SETS', style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text('Choose before starting. This stays locked during the workout.', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final seconds in const [30, 60, 90, 120, 180])
            ChoiceChip(
              label: Text(seconds >= 60 ? '${seconds ~/ 60}m' : '${seconds}s'),
              selected: _restDuration == seconds,
              onSelected: (_) => setState(() => _restDuration = seconds),
              selectedColor: kAccent,
            ),
        ]),
      ]),
    );
  }

  void _removeSetupExercise(int index) {
    if (_isSuggestedWorkout || index < 0 || index >= _exercises.length) return;
    setState(() {
      _exercises.removeAt(index);
      if (_currentExercise >= _exercises.length) _currentExercise = 0;
    });
  }

  void _changeSetupTarget(int index, int delta) {
    if (_isSuggestedWorkout || index < 0 || index >= _exercises.length) return;
    final entry = _exercises[index];
    if (entry.sets.isEmpty) return;
    final kind = entry.catalog.kind;
    final min = kind == ExerciseKind.strength ? 1 : 5;
    final max = kind == ExerciseKind.strength ? 100 : (kind == ExerciseKind.timed ? 300 : 120);
    final next = (entry.sets.first.target + delta).clamp(min, max).toInt();
    if (next == entry.sets.first.target) return;
    setState(() {
      for (final set in entry.sets) {
        set.target = next;
      }
    });
  }

  void _changeSetupSets(int index, int delta) {
    if (_isSuggestedWorkout || index < 0 || index >= _exercises.length) return;
    final entry = _exercises[index];
    final next = (entry.sets.length + delta).clamp(1, 10).toInt();
    if (next == entry.sets.length) return;
    setState(() {
      if (delta > 0) {
        entry.sets.addAll(_makeSets(entry.catalog, next - entry.sets.length, entry.sets.first.target));
      } else {
        entry.sets.removeRange(next, entry.sets.length);
      }
    });
  }

  Widget _exerciseImage(String name, {double size = 58}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        _exerciseImageUrl(name),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: kBackground,
          child: const Icon(Icons.fitness_center_rounded, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _suggestionHero(String title, String reason, List<String> exercises) {
    final first = exercises.isEmpty ? null : exercises.first;

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 112,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (first != null)
                  Image.network(
                    _exerciseImageUrl(first),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: kBackground,
                        child: const Center(
                          child: Icon(
                            Icons.fitness_center_rounded,
                            color: Colors.white24,
                            size: 36,
                          ),
                        ),
                      );
                    },
                  )
                else
                  Container(color: kBackground),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .08),
                        Colors.black.withValues(alpha: .78),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${exercises.length} exercises',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exercises.take(4).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                ),
                const Spacer(), // pushes the button to the bottom of every card
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _handleLaunch(
                      Suggestion(
                        title: title,
                        reason: reason,
                        icon: Icons.fitness_center_rounded,
                        exercises: exercises,
                      ),
                    ),
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 17,
                    ),
                    label: const Text('View Workout'),
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestedSection() {
    const suggestions = [
      ('Push Day', 'Upper-body push focus', ['Bench Press', 'Overhead Press', 'Incline Dumbbell Press', 'Tricep Pushdown']),
      ('Pull Day', 'Back and biceps focus', ['Deadlift', 'Pull-Up', 'Barbell Row', 'Bicep Curl']),
      ('Leg Day', 'Lower-body strength focus', ['Squat', 'Romanian Deadlift', 'Leg Press', 'Calf Raise']),
      ('Upper Body', 'Balanced upper-body session', ['Bench Press', 'Pull-Up', 'Overhead Press', 'Bicep Curl']),
      ('Cardio & Core', 'Stamina and core session', ['Running', 'Jump Rope', 'Plank', 'Crunches']),
      ('Full Body', 'Major muscle groups', ['Squat', 'Bench Press', 'Barbell Row', 'Plank']),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SUGGESTED WORKOUTS',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Ready-made sessions you can start immediately.',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: suggestions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 264,
          ),
          itemBuilder: (context, index) {
            final item = suggestions[index];
            return _suggestionHero(item.$1, item.$2, item.$3);
          },
        ),
      ],
    );
  }

  Widget _createCustomBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kAccent.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tune_rounded, color: kAccent, size: 26),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build your own workout',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  'Choose exercises, sets, reps, and rest.',
                  style: TextStyle(color: Colors.grey, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _beginCreateCustom,
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _customSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MY CUSTOM WORKOUTS',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text('Your workouts stay editable and separate from app suggestions.', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        const SizedBox(height: 12),
        if (_customWorkouts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.grey[600], size: 38),
              const SizedBox(height: 9),
              const Text('No custom workouts yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Build one with your own exercises, sets, reps, and rest.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              const SizedBox(height: 13),
              Text(
                'Use the Create button above to build your first one.',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ]),
          )
        else
          ..._customWorkouts.map((template) {
            final first = template.exercises.isEmpty ? null : template.exercises.first['name']?.toString();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                if (first != null) _exerciseImage(first) else Container(width: 58, height: 58, decoration: BoxDecoration(color: kBackground, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.fitness_center_rounded, color: Colors.grey)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(template.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${template.exercises.length} exercises · ${template.restSeconds}s rest', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  const SizedBox(height: 9),
                  Wrap(spacing: 6, children: [
                    OutlinedButton.icon(onPressed: () => _editCustom(template), icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Edit')),
                    FilledButton.icon(onPressed: () => _previewCustomTemplate(template), icon: const Icon(Icons.play_arrow_rounded, size: 16), label: const Text('Start')),
                  ]),
                ])),
                IconButton(tooltip: 'Delete custom workout', onPressed: () => _deleteCustom(template), icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey)),
              ]),
            );
          }),
      ],
    );
  }

  Widget _customEditor() {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
      TextField(
        controller: _nameController,
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        decoration: InputDecoration(labelText: 'Workout name', labelStyle: const TextStyle(color: Colors.grey), hintText: 'e.g. Monday Push Day', hintStyle: TextStyle(color: Colors.grey[700]), filled: true, fillColor: kSurface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
      ),
      const SizedBox(height: 14),
      if (_exercises.isEmpty)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            Icon(Icons.fitness_center_rounded, size: 42, color: Colors.grey[700]),
            const SizedBox(height: 10),
            const Text('Add exercises', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Choose the exercises you want in this custom workout.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _pickExercises, icon: const Icon(Icons.add), label: const Text('Choose exercises')),
          ]),
        )
      else ...[
        ...List.generate(_exercises.length, _setupExerciseCard),
        OutlinedButton.icon(onPressed: _pickExercises, icon: const Icon(Icons.add), label: const Text('Add exercises')),
        const SizedBox(height: 12),
        _restSettings(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _saveCustomTemplate, icon: const Icon(Icons.save_outlined), label: Text(_editingCustomId == null ? 'Save Custom' : 'Update Custom'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: () async { await _saveCustomTemplate(); if (mounted) _startWorkout(); }, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start Workout'))),
        ]),
      ],
    ]);
  }

  Widget _customOverview() {
    final totalSets = _exercises.fold<int>(0, (sum, e) => sum + e.sets.length);

    return ListView(
      key: ValueKey('custom-overview-${_editingCustomId ?? _nameController.text}'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kAccent.withValues(alpha: .20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: kAccent, size: 28),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your saved custom workout',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _overviewStat('${_exercises.length}', 'Exercises'),
                  const SizedBox(width: 10),
                  _overviewStat('$totalSets', 'Total sets'),
                  const SizedBox(width: 10),
                  _overviewStat('${_restDuration}s', 'Rest'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'EXERCISES',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: .4),
        ),
        const SizedBox(height: 10),
        ...List.generate(_exercises.length, (index) {
          final exercise = _exercises[index];
          final target = exercise.sets.isEmpty ? _targetFor(exercise.catalog) : exercise.sets.first.target;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                _exerciseImage(exercise.catalog.name, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${exercise.catalog.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        exercise.catalog.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${exercise.sets.length} sets · ${_targetLabel(exercise.catalog, target)}',
                        style: const TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, color: Colors.grey, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This is your saved workout. You can edit its exercises, sets, reps, or rest before starting.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _editPreviewedCustom,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _startWorkout,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Workout', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _suggestedOverview() {
    final totalSets = _exercises.fold<int>(0, (sum, e) => sum + e.sets.length);

    return ListView(
      key: ValueKey('suggested-overview-${widget.launchToken}'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kAccent.withValues(alpha: .20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(Icons.fitness_center_rounded, color: kAccent, size: 28),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _suggestedPreviewReason,
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _overviewStat('${_exercises.length}', 'Exercises'),
                  const SizedBox(width: 10),
                  _overviewStat('$totalSets', 'Total sets'),
                  const SizedBox(width: 10),
                  _overviewStat('${_restDuration}s', 'Rest'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'EXERCISES',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: .4),
        ),
        const SizedBox(height: 10),
        ...List.generate(_exercises.length, (index) {
          final exercise = _exercises[index];
          final target = exercise.sets.isEmpty ? _targetFor(exercise.catalog) : exercise.sets.first.target;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                _exerciseImage(exercise.catalog.name, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${exercise.catalog.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        exercise.catalog.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${exercise.sets.length} sets · ${_targetLabel(exercise.catalog, target)}',
                        style: const TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.grey, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This is a ready-made workout. Its exercises, sets, and targets are fixed for the session.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _startWorkout,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Workout', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _overviewStat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// "Workout Complete" screen with a Done button.
  Widget _summaryView() {
    final s = _summary!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(Icons.check_circle_rounded, size: 88, color: kAccent),
            const SizedBox(height: 16),
            const Text(
              'Workout Complete!',
              style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(s.name, style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 26),
            Row(
              children: [
                _overviewStat('${s.exercises}', 'Exercises'),
                const SizedBox(width: 10),
                _overviewStat('${s.sets}', 'Sets'),
                const SizedBox(width: 10),
                _overviewStat(_clock(s.seconds), 'Time'),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _doneSummary,
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupView() {
    if (_customPreviewing && !_started && _exercises.isNotEmpty) {
      return _customOverview();
    }
    if (_isSuggestedWorkout && !_started && _exercises.isNotEmpty) {
      return _suggestedOverview();
    }

    if (_buildingCustom && !_started) {
      return _customEditor();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        _createCustomBanner(),
        const SizedBox(height: 24),
        _suggestedSection(),
        const SizedBox(height: 28),
        _customSection(),
      ],
    );
  }

  Widget _setupExerciseCard(int index) {
    final e = _exercises[index];
    final target = e.sets.isEmpty ? _targetFor(e.catalog) : e.sets.first.target;
    Widget controlRow({required String label, required String value, required VoidCallback onMinus, required VoidCallback onPlus}) {
      return Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: kBackground,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: .07)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onMinus,
                  icon: const Icon(Icons.remove_rounded, size: 17),
                  color: Colors.grey[400],
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  constraints: const BoxConstraints(minWidth: 38),
                ),
                SizedBox(
                  width: 42,
                  child: Text(value, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  onPressed: onPlus,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  color: kAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  constraints: const BoxConstraints(minWidth: 38),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: kAccent.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
                child: Icon(e.catalog.equipment.icon, color: kAccent, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(e.catalog.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              IconButton(
                tooltip: 'Remove exercise',
                onPressed: () => _removeSetupExercise(index),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 14),
          controlRow(
            label: e.catalog.kind == ExerciseKind.strength
                ? 'REPS'
                : e.catalog.kind == ExerciseKind.timed
                    ? 'TIME'
                    : 'MINUTES',
            value: '$target',
            onMinus: () => _changeSetupTarget(index, -1),
            onPlus: () => _changeSetupTarget(index, 1),
          ),
          const SizedBox(height: 9),
          controlRow(
            label: 'SETS',
            value: '${e.sets.length}',
            onMinus: () => _changeSetupSets(index, -1),
            onPlus: () => _changeSetupSets(index, 1),
          ),
        ],
      ),
    );
  }

  Widget _activeView() {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
      _timerCard(),
      const SizedBox(height: 12),
      _activeExerciseCard(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While the summary is showing, Back is intercepted and acts like Done.
      canPop: (!_started || _saving) && _summary == null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_summary != null) {
          _doneSummary();
          return;
        }
        if (_saving || !_started) return;
        await _leaveFromActiveWorkout();
      },
      child: Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          backgroundColor: kBackground,
          automaticallyImplyLeading: false,
          leading: _summary != null
              ? null
              : (_started
                  ? TextButton.icon(
                      onPressed: (_saving || _discarding) ? null : _leaveFromActiveWorkout,
                      icon: const Icon(Icons.arrow_back_rounded, size: 19),
                      label: const Text('Leave'),
                    )
                  : (_buildingCustom
                      ? IconButton(
                          onPressed: _closeCustomBuilder,
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      : (_isSuggestedWorkout
                          ? IconButton(
                              onPressed: _closeSuggestedPreview,
                              icon: const Icon(Icons.arrow_back_rounded),
                            )
                          : (_customPreviewing
                              ? IconButton(
                                  onPressed: _closeCustomPreview,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                )
                              : null)))),
          title: _summary != null
              ? const Text('Summary')
              : Text(
                  _started
                      ? _nameController.text
                      : (_buildingCustom
                          ? 'Build Custom Workout'
                          : ((_isSuggestedWorkout || _customPreviewing)
                              ? 'Workout Overview'
                              : 'Start Workout')),
                ),
          actions: [
            if (_started && _saving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: _summary != null
            ? _summaryView()
            : (_started ? _activeView() : _setupView()),
      ),
    );
  }
}