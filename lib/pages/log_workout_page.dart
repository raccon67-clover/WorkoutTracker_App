import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, HapticFeedback, LengthLimitingTextInputFormatter;

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
const int _minCustomRestSeconds = 10;
const int _maxCustomRestSeconds = 1800; // 30 minutes
const List<int> _restPresets = [30, 60, 90, 120, 180];

/// 45 -> "45s", 60 -> "1m", 150 -> "2m 30s"
String _restLabel(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final r = seconds % 60;
  return r == 0 ? '${m}m' : '${m}m ${r}s';
}
const int _repPaceSeconds = 3;

/// Phase colours for the live session screen: red = work, blue = rest,
/// amber = paused. Colour alone tells you the phase from across the room.
const Color _kRestColor = Color(0xFF29B6F6);
const Color _kPausedColor = Color(0xFFFFB300);

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
  final int totalSets; // planned sets, for "6 of 12 sets" on early finishes
  final bool partial;

  const _Summary(
    this.name,
    this.exercises,
    this.sets,
    this.seconds, {
    this.totalSets = 0,
    this.partial = false,
  });
}

/// Button that only fires after being held down, so a stray tap can't
/// mark a set as done. A fill sweeps across while you hold.
class _HoldToConfirmButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onConfirmed;
  final Duration holdDuration;
  final double height;

  const _HoldToConfirmButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onConfirmed,
    this.holdDuration = const Duration(milliseconds: 650),
    this.height = 68,
  });

  @override
  State<_HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<_HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _c.value = 0;
          widget.onConfirmed?.call();
        }
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() {
    if (widget.onConfirmed == null) return;
    HapticFeedback.selectionClick();
    _c.forward();
  }

  void _up() {
    if (_c.status != AnimationStatus.completed) _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    final radius = BorderRadius.circular(20);
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            height: widget.height,
            color: widget.color.withValues(alpha: .28),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _c.value,
                      child: Container(color: widget.color),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 28),
                        const SizedBox(width: 10),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LeaveChoice { save, discard, stay }

typedef _NextUp = ({_ActiveExercise exercise, int setIndex});

/// Circular progress ring used for the big set / rest timer.
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}

class LogWorkoutPage extends StatefulWidget {
  final Suggestion? launch;
  final List<CatalogExercise> initialExercises;
  final int initialExercisesToken;
  final int launchToken;
  final String openCustomId;
  final int openCustomToken;
  final VoidCallback? onOpenCustomConsumed;
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
    this.openCustomId = '',
    this.openCustomToken = 0,
    this.onOpenCustomConsumed,
    this.visitToken = 0,
    this.onSaved,
    this.onLaunchConsumed,
    this.onInitialExercisesConsumed,
    this.onSessionChanged,
  });

  @override
  State<LogWorkoutPage> createState() => _LogWorkoutPageState();
}

class _LogWorkoutPageState extends State<LogWorkoutPage>
    with WidgetsBindingObserver {
  final _nameController = TextEditingController(text: 'My Workout');
  final _notesController = TextEditingController();
  final List<_ActiveExercise> _exercises = [];
  final List<_CustomWorkoutTemplate> _customWorkouts = [];
  String? _editingCustomId;
  bool _buildingCustom = false;
  bool _nameMissing = false;
  bool _customPreviewing = false;

  Timer? _ticker;
  DateTime? _startedAt;
  DateTime? _workoutStartedDate;
  int _elapsedBeforeStart = 0;
  DateTime? _setEndsAt;
  DateTime? _restEndsAt;
  int _restDuration = _defaultRestSeconds;
  int _restTotal = _defaultRestSeconds;
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
    WidgetsBinding.instance.addObserver(this);
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
      _receiveExercises(widget.initialExercises);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInitialExercisesConsumed?.call();
      });
    }
  }

  @override
  void didUpdateWidget(LogWorkoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.openCustomToken != oldWidget.openCustomToken &&
        widget.openCustomId.isNotEmpty) {
      unawaited(_openSavedCustom(widget.openCustomId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOpenCustomConsumed?.call();
      });
      return;
    }

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
      _receiveExercises(widget.initialExercises);
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
    WidgetsBinding.instance.removeObserver(this);
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
      _nameMissing = false;
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
      _nameMissing = false;
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

  /// Saves the custom workout. Returns true only if it was really saved, so
  /// callers (like Start Workout) never continue without a valid name.
  Future<bool> _saveCustomTemplate() async {
    if (_isSuggestedWorkout || _exercises.isEmpty) return false;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameMissing = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give your custom workout a name.')));
      return false;
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
    return true;
  }

  /// Opens one of the saved custom workouts (picked from the Home search).
  Future<void> _openSavedCustom(String id) async {
    if (_started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish or leave your current workout first.')),
      );
      return;
    }
    if (_customWorkouts.isEmpty) await _loadCustomWorkouts();
    if (!mounted) return;
    final index = _customWorkouts.indexWhere((t) => t.id == id);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That workout could not be found.')),
      );
      return;
    }
    _previewCustomTemplate(_customWorkouts[index]);
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
    _restTotal = math.max(_restDuration, _pausedRestRemaining);
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

  /// Safety net: when the app goes to the background (call, app switch,
  /// OS killing it) store the session so nothing is lost. It comes back
  /// paused on the next launch, with the exact time left on the timers.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    if (!_started || _summary != null || _saving || _discarding) return;
    if (_completedAutomatically) return;
    final data = _stateJson()
      ..['paused'] = true
      ..['elapsedBeforeStart'] = _elapsedSeconds
      ..['pausedSetRemaining'] = _paused
          ? _pausedSetRemaining
          : (_setRunning ? _setRemaining : 0)
      ..['pausedRestRemaining'] = _paused
          ? _pausedRestRemaining
          : (_restRunning ? _restRemaining : 0);
    unawaited(DatabaseService.instance
        .saveActiveWorkout(jsonEncode(data))
        .catchError((Object e) => debugPrint('Background save failed: $e')));
  }

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
      HapticFeedback.heavyImpact(); // rest over: you can feel it without looking
      _advanceToNextSet();
      _startCurrentSet();
    } else if (_restRunning && _restEndsAt != null) {
      final left = _restRemaining;
      if (left > 0 && left <= 3) HapticFeedback.selectionClick();
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

  /// While paused the end-times are cleared, so read the frozen values.
  int get _shownSetRemaining => _paused ? _pausedSetRemaining : _setRemaining;
  int get _shownRestRemaining => _paused ? _pausedRestRemaining : _restRemaining;

  int get _totalSets => _exercises.fold<int>(0, (a, e) => a + e.sets.length);
  int get _doneSets => _exercises.fold<int>(0, (a, e) => a + e.completedCount);

  _NextUp? _nextUp() {
    if (_exercises.isEmpty) return null;
    final cur = _exercises[_currentExercise];
    if (_currentSet + 1 < cur.sets.length) {
      return (exercise: cur, setIndex: _currentSet + 1);
    }
    if (_currentExercise + 1 < _exercises.length) {
      return (exercise: _exercises[_currentExercise + 1], setIndex: 0);
    }
    return null;
  }

  void _skipRest() {
    if (!_restRunning || _paused || _saving) return;
    _restEndsAt = DateTime.now();
    _tick();
  }

  void _adjustRest(int delta) {
    if (!_restRunning || _paused || _restEndsAt == null) return;
    if (_restRemaining + delta <= 0) {
      _skipRest();
      return;
    }
    setState(() {
      _restEndsAt = _restEndsAt!.add(Duration(seconds: delta));
      if (_restRemaining > _restTotal) _restTotal = _restRemaining;
    });
  }

  /// During rest the "current" set is still the one that was just finished,
  /// so undoing = mark it not done and start it again.
  void _undoLastSet() {
    if (!_restRunning || _paused || _saving || _exercises.isEmpty) return;
    final set = _exercises[_currentExercise].sets[_currentSet];
    if (!set.completed) return;
    set.completed = false;
    HapticFeedback.lightImpact();
    _restRunning = false;
    _restEndsAt = null;
    _startCurrentSet();
  }

  void _finishSetEarly() {
    if (!_setRunning || _paused || _saving) return;
    _finishCurrentSet();
    if (mounted) setState(() {});
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

  /// Exercises sent from elsewhere (Home search, "repeat workout").
  /// Opens the Build Custom Workout screen with them already in the list.
  /// If a workout is running or the builder is already open, they are simply
  /// added to what is there.
  void _receiveExercises(List<CatalogExercise> exercises) {
    if (_started || _buildingCustom) {
      _addCatalogExercises(exercises);
      return;
    }
    _beginCreateCustom();
    _addCatalogExercises(exercises);
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
    // A workout can never start without a name, whichever button was used.
    if (_nameController.text.trim().isEmpty) {
      if (_buildingCustom) setState(() => _nameMissing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your workout a name before starting.')),
      );
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
    HapticFeedback.mediumImpact();
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
      _restTotal = duration;
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

  Future<void> _saveCompletedWorkout({bool partial = false}) async {
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
          notes: () {
            final userNotes = _notesController.text.trim();
            final doneSets = items.fold<int>(0, (a, i) => a + i.sets.length);
            final lines = [
              if (userNotes.isNotEmpty) userNotes,
              if (partial) 'Ended early · $doneSets of $_totalSets sets',
            ];
            return lines.isEmpty ? null : lines.join('\n');
          }(),
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
        totalSets: _totalSets,
        partial: partial,
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

  /// Leaving mid-workout: finished sets are never thrown away silently.
  Future<void> _leaveFromActiveWorkout() async {
    if (_saving || _discarding) return;
    final done = _doneSets;

    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(
          done > 0 ? 'End workout?' : 'Leave workout?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          done > 0
              ? "You've finished $done of $_totalSets sets in ${_clock(_elapsedSeconds)}. "
                  'Save your progress so that work counts.'
              : "You haven't finished any sets yet, so there's nothing to save.",
          style: TextStyle(color: Colors.grey[400], height: 1.35),
        ),
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.stay),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.discard),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: Text(done > 0 ? 'Discard' : 'Leave'),
          ),
          if (done > 0)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _LeaveChoice.save),
              child: const Text('Save progress'),
            ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _LeaveChoice.stay) return;

    if (choice == _LeaveChoice.save) {
      await _endEarlyAndSave();
      return;
    }

    // Discard
    _discarding = true;
    await DatabaseService.instance.clearActiveWorkout();
    widget.onSessionChanged?.call(false);
    if (!mounted) return;

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

  /// Saves only the sets that were actually completed, then shows the summary.
  Future<void> _endEarlyAndSave() async {
    if (_doneSets == 0 || _saving) return;

    // Freeze everything so no timer can complete another set mid-save.
    setState(() {
      _completedAutomatically = true;
      _elapsedBeforeStart = _elapsedSeconds;
      _startedAt = null;
      _setRunning = false;
      _restRunning = false;
      _setEndsAt = null;
      _restEndsAt = null;
    });
    _ticker?.cancel();
    _ticker = null;

    await _saveCompletedWorkout(partial: true);

    // Save failed (the success path leaves the summary showing): pick the
    // session back up instead of leaving a dead screen.
    if (mounted && _summary == null && _started) {
      setState(() {
        _paused = false;
        _startedAt = DateTime.now();
      });
      _startTicker();
      _startCurrentSet();
    }
  }

  // ─────────────────────── Live session UI ───────────────────────
  // Designed to be read at arm's length mid-set:
  //  • one huge number (reps or countdown) in a progress ring
  //  • colour = phase (red work, blue rest, amber paused)
  //  • thumb-sized controls pinned to the bottom of the screen

  Color get _phaseColor =>
      _paused ? _kPausedColor : (_restRunning ? _kRestColor : kAccent);

  static const _tabular = [FontFeature.tabularFigures()];

  Widget _sessionHeader() {
    final total = _totalSets;
    final done = _doneSets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 20, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                _clock(_elapsedSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: _tabular,
                ),
              ),
              const Spacer(),
              Text(
                '$done of $total sets done',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              backgroundColor: kSurface,
              valueColor: AlwaysStoppedAnimation<Color>(_phaseColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  Widget _ring({
    required double size,
    required double progress,
    required Color color,
    required Widget child,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0).toDouble(),
          color: color,
          track: Colors.white.withValues(alpha: .08),
          stroke: size * 0.065,
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _setSegments(_ActiveExercise ex) {
    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 6,
      children: [
        for (var i = 0; i < ex.sets.length; i++)
          Container(
            width: 30,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: ex.sets[i].completed
                  ? kAccent
                  : (i == _currentSet
                      ? Colors.white
                      : Colors.white.withValues(alpha: .15)),
            ),
          ),
      ],
    );
  }

  /// Work phase: exercise name, giant rep / time number, set position.
  Widget _workStage(BoxConstraints c) {
    final ex = _exercises[_currentExercise];
    final set = ex.sets[_currentSet];
    final target = set.target;
    final kind = ex.catalog.kind;
    final ring =
        math.min(c.maxWidth - 48, c.maxHeight - 215).clamp(160.0, 340.0).toDouble();

    final progress = !_setRunning
        ? 0.0
        : kind == ExerciseKind.strength
            ? (target == 0 ? 0.0 : _liveReps / target)
            : _setProgress(ex.catalog, target);

    final Widget center;
    if (kind == ExerciseKind.strength) {
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$_liveReps',
            style: TextStyle(
              color: Colors.white,
              fontSize: ring * .42,
              height: 1,
              fontWeight: FontWeight.w900,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'of $target reps',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    } else {
      final seconds = _setRunning
          ? _shownSetRemaining
          : _durationForSet(ex.catalog, target).inSeconds;
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _clock(seconds),
            style: TextStyle(
              color: Colors.white,
              fontSize: ring * .27,
              height: 1,
              fontWeight: FontWeight.w900,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'remaining',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    final chipLabel = _paused
        ? 'PAUSED'
        : (_saving || _completedAutomatically)
            ? 'SAVING'
            : (_setRunning ? 'WORK' : 'GET READY');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _phaseChip(chipLabel, _phaseColor),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            ex.catalog.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ex.catalog.subtitle,
          style: TextStyle(color: Colors.grey[500], fontSize: 15),
        ),
        const SizedBox(height: 18),
        _ring(size: ring, progress: progress, color: _phaseColor, child: center),
        const SizedBox(height: 18),
        Text(
          'SET ${_currentSet + 1} OF ${ex.sets.length}  ·  ${_targetLabel(ex.catalog, target)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 10),
        _setSegments(ex),
      ],
    );
  }

  /// Rest phase: big countdown, quick +/- adjust, and what's coming next.
  Widget _restStage(BoxConstraints c) {
    final next = _nextUp();
    final remaining = _shownRestRemaining;
    final total = math.max(_restTotal, remaining);
    final ring =
        math.min(c.maxWidth - 80, c.maxHeight - 250).clamp(150.0, 300.0).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _phaseChip(_paused ? 'PAUSED' : 'REST', _phaseColor),
        const SizedBox(height: 18),
        _ring(
          size: ring,
          progress: total == 0 ? 0 : remaining / total,
          color: _phaseColor,
          child: Text(
            _clock(remaining),
            style: TextStyle(
              color: Colors.white,
              fontSize: ring * .30,
              height: 1,
              fontWeight: FontWeight.w900,
              fontFeatures: _tabular,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _restAdjustButton('−15s', () => _adjustRest(-15)),
            const SizedBox(width: 12),
            _restAdjustButton('+15s', () => _adjustRest(15)),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _paused ? null : _undoLastSet,
          icon: const Icon(Icons.undo_rounded, size: 20),
          label: const Text(
            'Undo last set',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey[400],
            minimumSize: const Size(48, 48),
          ),
        ),
        const SizedBox(height: 8),
        if (next != null) _upNextCard(next),
      ],
    );
  }

  Widget _restAdjustButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: _paused ? null : onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(96, 48),
        shape: const StadiumBorder(),
        side: const BorderSide(color: Colors.white24),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }

  Widget _upNextCard(_NextUp next) {
    final ex = next.exercise;
    final target = ex.sets[next.setIndex].target;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UP NEXT',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ex.catalog.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Set ${next.setIndex + 1} of ${ex.sets.length}  ·  ${_targetLabel(ex.catalog, target)}',
            style: const TextStyle(
              color: kAccent,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// Slim "what's next" line shown during work (rest has its own big card).
  Widget _upNextStrip() {
    if (_restRunning) return const SizedBox.shrink();
    final next = _nextUp();
    final text = next == null
        ? 'Last set — finish strong'
        : '${next.exercise.catalog.name} · set ${next.setIndex + 1} of ${next.exercise.sets.length}';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            'NEXT',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Big thumb-reach controls pinned to the bottom.
  Widget _controlBar() {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    final Widget row;

    if (_paused) {
      row = SizedBox(
        width: double.infinity,
        height: 68,
        child: FilledButton.icon(
          onPressed: _saving ? null : _togglePause,
          style: FilledButton.styleFrom(shape: shape),
          icon: const Icon(Icons.play_arrow_rounded, size: 32),
          label: const Text(
            'Resume',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ),
      );
    } else {
      final inRest = _restRunning;
      row = Row(
        children: [
          Tooltip(
            message: 'Pause workout',
            child: SizedBox(
              width: 68,
              height: 68,
              child: OutlinedButton(
                onPressed: _saving ? null : _togglePause,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: shape,
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white,
                ),
                child: const Icon(Icons.pause_rounded, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: inRest
                ? SizedBox(
                    height: 68,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _skipRest,
                      style: FilledButton.styleFrom(
                        shape: shape,
                        backgroundColor: _kRestColor,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.skip_next_rounded, size: 30),
                      label: const Text(
                        'Skip rest',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                  )
                : _HoldToConfirmButton(
                    label: 'Hold to finish set',
                    icon: Icons.check_rounded,
                    color: kAccent,
                    onConfirmed:
                        (_saving || !_setRunning || _paused) ? null : _finishSetEarly,
                  ),
          ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: row,
      ),
    );
  }

  Future<void> _pickCustomRest() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _CustomRestDialog(initialSeconds: _restDuration),
    );
    if (picked != null && mounted) setState(() => _restDuration = picked);
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
          for (final seconds in _restPresets)
            ChoiceChip(
              label: Text(_restLabel(seconds)),
              selected: _restDuration == seconds,
              onSelected: (_) => setState(() => _restDuration = seconds),
              selectedColor: kAccent,
            ),
          ChoiceChip(
            avatar: const Icon(Icons.edit_rounded, size: 15),
            label: Text(
              _restPresets.contains(_restDuration) ? 'Custom' : _restLabel(_restDuration),
            ),
            selected: !_restPresets.contains(_restDuration),
            onSelected: (_) => _pickCustomRest(),
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

    // The card has a 112px image plus a text area. Text grows with the phone's
    // font-size setting, so the card height must grow with it too (that is what
    // caused "bottom overflowed by 1.00 pixels"). 156 = text area + small cushion.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final cardHeight = 112 + 156 * (textScale < 1 ? 1.0 : textScale);

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
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cardHeight,
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
                  Text('${template.exercises.length} exercises · ${_restLabel(template.restSeconds)} rest', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
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
        onChanged: (_) {
          if (_nameMissing) setState(() => _nameMissing = false);
        },
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        decoration: InputDecoration(errorText: _nameMissing ? 'Give your workout a name' : null, labelText: 'Workout name', labelStyle: const TextStyle(color: Colors.grey), hintText: 'e.g. Monday Push Day', hintStyle: TextStyle(color: Colors.grey[700]), filled: true, fillColor: kSurface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
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
          Expanded(child: FilledButton.icon(onPressed: () async { final saved = await _saveCustomTemplate(); if (saved && mounted) _startWorkout(); }, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start Workout'))),
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
                  _overviewStat(_restLabel(_restDuration), 'Rest'),
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
                  _overviewStat(_restLabel(_restDuration), 'Rest'),
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
            Text(
              s.partial ? 'Progress Saved' : 'Workout Complete!',
              style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              s.partial && s.totalSets > 0
                  ? '${s.name} · ${s.sets} of ${s.totalSets} sets'
                  : s.name,
              style: TextStyle(color: Colors.grey[500]),
            ),
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
    if (_exercises.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        _sessionHeader(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Center(
                  child: _restRunning ? _restStage(c) : _workStage(c),
                ),
              ),
            ),
          ),
        ),
        _upNextStrip(),
        _controlBar(),
      ],
    );
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
          // The "Leave" text button is wider than the app bar's default 56px
          // leading slot, which is what drew the red/striped overflow mess.
          leadingWidth: (_summary == null && _started) ? 108 : null,
          leading: _summary != null
              ? null
              : (_started
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: (_saving || _discarding) ? null : _leaveFromActiveWorkout,
                        icon: const Icon(Icons.arrow_back_rounded, size: 19),
                        label: const Text('Leave'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
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


class _CustomRestDialog extends StatefulWidget {
  final int initialSeconds;
  const _CustomRestDialog({required this.initialSeconds});

  @override
  State<_CustomRestDialog> createState() => _CustomRestDialogState();
}

class _CustomRestDialogState extends State<_CustomRestDialog> {
  late final TextEditingController _minutes =
      TextEditingController(text: '${widget.initialSeconds ~/ 60}');
  late final TextEditingController _seconds =
      TextEditingController(text: '${widget.initialSeconds % 60}');
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _submit() {
    final m = int.tryParse(_minutes.text.trim()) ?? 0;
    final s = int.tryParse(_seconds.text.trim()) ?? 0;
    final total = m * 60 + s;
    if (total < _minCustomRestSeconds || total > _maxCustomRestSeconds) {
      setState(() => _error = 'Enter between 10 seconds and 30 minutes.');
      return;
    }
    Navigator.pop(context, total);
  }

  Widget _field(TextEditingController controller, String label) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: kBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Custom rest time', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _field(_minutes, 'Minutes'),
            const SizedBox(width: 12),
            _field(_seconds, 'Seconds'),
          ]),
          const SizedBox(height: 10),
          Text(
            _error ?? 'Rest between each set, from 10 seconds up to 30 minutes.',
            style: TextStyle(
              color: _error == null ? Colors.grey[500] : Colors.redAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}