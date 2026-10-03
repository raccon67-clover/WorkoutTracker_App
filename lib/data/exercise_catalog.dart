import 'dart:math' as math;
import 'package:flutter/material.dart';

enum Equipment {

  barbell('Barbell', Icons.fitness_center_rounded, true),
  dumbbell('Dumbbells', Icons.fitness_center_rounded, true),
  machine('Machines', Icons.settings_rounded, true),
  cable('Cables', Icons.cable_rounded, true),
  cardioMachine('Cardio machine', Icons.directions_run_rounded, true),

  bodyweight('Bodyweight', Icons.accessibility_new_rounded, false),
  kettlebell('Kettlebell', Icons.sports_handball_rounded, false),
  bands('Resistance bands', Icons.all_inclusive_rounded, false),
  pullUpBar('Pull-up bar', Icons.horizontal_rule_rounded, false),
  other('Other', Icons.category_rounded, false);

  final String label;
  final IconData icon;
  final bool isGym;
  const Equipment(this.label, this.icon, this.isGym);
}

enum Muscle {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  arms('Arms'),
  legs('Legs'),
  core('Core'),
  cardio('Cardio'),
  fullBody('Full body');

  final String label;
  const Muscle(this.label);
}


enum ExerciseKind { strength, timed, cardio }

class CatalogExercise {
  final String name;
  final Muscle muscle;
  final Equipment equipment;
  final ExerciseKind kind;

  const CatalogExercise(
    this.name,
    this.muscle,
    this.equipment, [
    this.kind = ExerciseKind.strength,
  ]);

  String get subtitle => '${muscle.label} · ${equipment.label}';
}

class ExerciseCatalog {


  static CatalogExercise? byName(String name) {
    final n = name.trim().toLowerCase();
    for (final e in all) {
      if (e.name.toLowerCase() == n) return e;
    }
    return null;
  }


  static List<CatalogExercise> search({
    String query = '',
    Set<Equipment> equipment = const {},
    Muscle? muscle,
  }) {
    final pool = all.where((e) {
      if (equipment.isNotEmpty && !equipment.contains(e.equipment)) return false;
      if (muscle != null && e.muscle != muscle) return false;
      return true;
    }).toList();

    if (normalize(query).isEmpty) return pool;

    final scored = <MapEntry<CatalogExercise, double>>[];
    for (final e in pool) {
      final s = matchScore(query, e.name, extra: _extraFor(e));
      if (s > 0) scored.add(MapEntry(e, s));
    }
    scored.sort((a, b) {
      final c = b.value.compareTo(a.value);
      if (c != 0) return c;
      return a.key.name.length.compareTo(b.key.name.length);
    });
    return scored.map((e) => e.key).toList();
  }


  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static String _singular(String t) {
    if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }


  static double matchScore(String query, String name, {String extra = ''}) {
    final q = normalize(query);
    if (q.isEmpty) return 1;

    final nameNorm = normalize(name);
    final nameWords = nameNorm.split(' ');
    final extraWords =
        normalize(extra).split(' ').where((w) => w.isNotEmpty).toList();
    final tokens = q.split(' ').map(_singular).toList();

    var total = 0.0;
    var matched = true;
    for (final t in tokens) {
      final s = _tokenScore(t, nameWords, extraWords);
      if (s <= 0) {
        matched = false;
        break;
      }
      total += s;
    }

    final compactName = nameWords.join();
    final compactQuery = tokens.join();
    if (!matched) {

      if (compactQuery.length >= 3 && compactName.contains(compactQuery)) {
        total = 3.0;
        matched = true;
      }
    }
    if (!matched) return 0;

    if (nameNorm == q) total += 6;
    if (nameNorm.startsWith(q)) total += 3;
    if (compactName.startsWith(compactQuery)) total += 1;
    return total;
  }

  static double _tokenScore(
    String token,
    List<String> nameWords,
    List<String> extraWords,
  ) {
    var best = 0.0;

    for (var i = 0; i < nameWords.length; i++) {
      final w = nameWords[i];
      if (w == token) {
        best = math.max(best, i == 0 ? 4.0 : 3.5);
      } else if (w.startsWith(token)) {
        best = math.max(best, i == 0 ? 3.2 : 3.0);
      } else if (token.length >= 3 && w.contains(token)) {
        best = math.max(best, 2.0);
      }
    }
    if (best > 0) return best;

    for (final w in extraWords) {
      if (w == token || w.startsWith(token)) {
        best = math.max(best, 1.6);
      } else if (token.length >= 3 && w.contains(token)) {
        best = math.max(best, 1.0);
      }
    }
    if (best > 0) return best;


    if (token.length >= 4) {
      final maxDist = token.length >= 8 ? 2 : 1;
      for (final w in nameWords) {
        final prefix = w.length > token.length ? w.substring(0, token.length) : w;
        final d = math.min(_lev(token, w), _lev(token, prefix));
        if (d <= maxDist) best = math.max(best, 1.2 - 0.2 * d);
      }
      if (best > 0) return best;
      for (final w in extraWords) {
        if (_lev(token, w) <= maxDist) best = math.max(best, 0.5);
      }
    }
    return best;
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[b.length];
  }


  static List<bool> highlightMask(String query, String name) {
    final mask = List<bool>.filled(name.length, false);
    final lower = name.toLowerCase();
    for (final raw in normalize(query).split(' ')) {
      if (raw.isEmpty) continue;
      for (final t in {raw, _singular(raw)}) {
        final idx = lower.indexOf(t);
        if (idx >= 0) {
          for (var i = idx; i < idx + t.length && i < mask.length; i++) {
            mask[i] = true;
          }
          break;
        }
      }
    }
    return mask;
  }


  static final Map<String, String> _extraCache = {};

  static String _extraFor(CatalogExercise e) =>
      _extraCache.putIfAbsent(e.name, () => _buildExtra(e));

  static String _buildExtra(CatalogExercise e) {
    final n = e.name.toLowerCase();
    bool has(String s) => n.contains(s);
    final k = <String>[e.muscle.label, e.equipment.label];

    switch (e.equipment) {
      case Equipment.dumbbell:
        k.add('db');
        break;
      case Equipment.barbell:
        k.add('bb');
        break;
      case Equipment.kettlebell:
        k.add('kb');
        break;
      default:
        break;
    }

    switch (e.muscle) {
      case Muscle.chest:
        k.add('pecs pectorals');
        break;
      case Muscle.back:
        k.add('upper back');
        break;
      case Muscle.shoulders:
        k.add('delts deltoids');
        break;
      case Muscle.core:
        k.add('abs abdominals stomach');
        break;
      case Muscle.cardio:
        k.add('conditioning endurance');
        break;
      case Muscle.fullBody:
        k.add('total body');
        break;
      default:
        break;
    }

    if (has('row') || has('pulldown') || has('pull-up') || has('chin') || has('pull-apart')) {
      k.add('lats');
    }
    if (has('shrug')) k.add('traps');
    if (has('face pull') || has('rear delt')) k.add('rear delts');
    if (has('curl') && !has('leg curl')) k.add('biceps');
    if (has('tricep') || has('dip') || has('pushdown') || has('close-grip') || has('skull')) {
      k.add('triceps');
    }
    if (has('squat') || has('leg press') || has('lunge') || has('leg extension') || has('step-up')) {
      k.add('quads quadriceps thighs');
    }
    if (has('romanian') || has('leg curl') || n == 'deadlift') k.add('hamstrings');
    if (has('hip thrust') || has('glute') || has('pull-through') || has('abduction') ||
        has('lunge') || has('squat') || has('romanian') || has('step-up')) {
      k.add('glutes');
    }
    if (has('calf')) k.add('calves');
    if (has('overhead press')) k.add('ohp military press');
    if (has('romanian')) k.add('rdl');
    if (n == 'deadlift') k.add('dl');
    if (has('bench press')) k.add('bp');
    if (has('running')) k.add('run jog');
    if (has('walk')) k.add('walking');
    if (has('bike') || has('cycling')) k.add('bike cycling spin');
    if (has('treadmill')) k.add('run jog walk');
    if (has('push-up')) k.add('pushup press up');

    return k.join(' ');
  }

  static const List<CatalogExercise> all = [

    CatalogExercise('Bench Press', Muscle.chest, Equipment.barbell),
    CatalogExercise('Incline Bench Press', Muscle.chest, Equipment.barbell),
    CatalogExercise('Dumbbell Bench Press', Muscle.chest, Equipment.dumbbell),
    CatalogExercise('Incline Dumbbell Press', Muscle.chest, Equipment.dumbbell),
    CatalogExercise('Dumbbell Fly', Muscle.chest, Equipment.dumbbell),
    CatalogExercise('Chest Press Machine', Muscle.chest, Equipment.machine),
    CatalogExercise('Pec Deck', Muscle.chest, Equipment.machine),
    CatalogExercise('Cable Crossover', Muscle.chest, Equipment.cable),
    CatalogExercise('Push-Up', Muscle.chest, Equipment.bodyweight),
    CatalogExercise('Diamond Push-Up', Muscle.chest, Equipment.bodyweight),
    CatalogExercise('Chest Dip', Muscle.chest, Equipment.bodyweight),
    CatalogExercise('Band Chest Press', Muscle.chest, Equipment.bands),


    CatalogExercise('Deadlift', Muscle.back, Equipment.barbell),
    CatalogExercise('Barbell Row', Muscle.back, Equipment.barbell),
    CatalogExercise('Pendlay Row', Muscle.back, Equipment.barbell),
    CatalogExercise('One-Arm Dumbbell Row', Muscle.back, Equipment.dumbbell),
    CatalogExercise('Lat Pulldown', Muscle.back, Equipment.cable),
    CatalogExercise('Seated Cable Row', Muscle.back, Equipment.cable),
    CatalogExercise('Face Pull', Muscle.back, Equipment.cable),
    CatalogExercise('Straight-Arm Pulldown', Muscle.back, Equipment.cable),
    CatalogExercise('Seated Row Machine', Muscle.back, Equipment.machine),
    CatalogExercise('Assisted Pull-Up Machine', Muscle.back, Equipment.machine),
    CatalogExercise('Pull-Up', Muscle.back, Equipment.pullUpBar),
    CatalogExercise('Chin-Up', Muscle.back, Equipment.pullUpBar),
    CatalogExercise('Inverted Row', Muscle.back, Equipment.bodyweight),
    CatalogExercise('Superman', Muscle.back, Equipment.bodyweight),
    CatalogExercise('Band Pull-Apart', Muscle.back, Equipment.bands),
    CatalogExercise('Kettlebell Row', Muscle.back, Equipment.kettlebell),


    CatalogExercise('Overhead Press', Muscle.shoulders, Equipment.barbell),
    CatalogExercise('Dumbbell Shoulder Press', Muscle.shoulders, Equipment.dumbbell),
    CatalogExercise('Lateral Raise', Muscle.shoulders, Equipment.dumbbell),
    CatalogExercise('Front Raise', Muscle.shoulders, Equipment.dumbbell),
    CatalogExercise('Rear Delt Fly', Muscle.shoulders, Equipment.dumbbell),
    CatalogExercise('Dumbbell Shrug', Muscle.shoulders, Equipment.dumbbell),
    CatalogExercise('Shoulder Press Machine', Muscle.shoulders, Equipment.machine),
    CatalogExercise('Cable Lateral Raise', Muscle.shoulders, Equipment.cable),
    CatalogExercise('Pike Push-Up', Muscle.shoulders, Equipment.bodyweight),
    CatalogExercise('Band Lateral Raise', Muscle.shoulders, Equipment.bands),
    CatalogExercise('Kettlebell Press', Muscle.shoulders, Equipment.kettlebell),


    CatalogExercise('Barbell Curl', Muscle.arms, Equipment.barbell),
    CatalogExercise('Close-Grip Bench Press', Muscle.arms, Equipment.barbell),
    CatalogExercise('Bicep Curl', Muscle.arms, Equipment.dumbbell),
    CatalogExercise('Hammer Curl', Muscle.arms, Equipment.dumbbell),
    CatalogExercise('Concentration Curl', Muscle.arms, Equipment.dumbbell),
    CatalogExercise('Overhead Tricep Extension', Muscle.arms, Equipment.dumbbell),
    CatalogExercise('Tricep Kickback', Muscle.arms, Equipment.dumbbell),
    CatalogExercise('Tricep Pushdown', Muscle.arms, Equipment.cable),
    CatalogExercise('Cable Curl', Muscle.arms, Equipment.cable),
    CatalogExercise('Preacher Curl Machine', Muscle.arms, Equipment.machine),
    CatalogExercise('Bench Dip', Muscle.arms, Equipment.bodyweight),
    CatalogExercise('Band Curl', Muscle.arms, Equipment.bands),


    CatalogExercise('Squat', Muscle.legs, Equipment.barbell),
    CatalogExercise('Front Squat', Muscle.legs, Equipment.barbell),
    CatalogExercise('Romanian Deadlift', Muscle.legs, Equipment.barbell),
    CatalogExercise('Hip Thrust', Muscle.legs, Equipment.barbell),
    CatalogExercise('Goblet Squat', Muscle.legs, Equipment.dumbbell),
    CatalogExercise('Dumbbell Lunge', Muscle.legs, Equipment.dumbbell),
    CatalogExercise('Bulgarian Split Squat', Muscle.legs, Equipment.dumbbell),
    CatalogExercise('Dumbbell Romanian Deadlift', Muscle.legs, Equipment.dumbbell),
    CatalogExercise('Leg Press', Muscle.legs, Equipment.machine),
    CatalogExercise('Leg Extension', Muscle.legs, Equipment.machine),
    CatalogExercise('Leg Curl', Muscle.legs, Equipment.machine),
    CatalogExercise('Calf Raise', Muscle.legs, Equipment.machine),
    CatalogExercise('Hack Squat', Muscle.legs, Equipment.machine),
    CatalogExercise('Hip Abduction Machine', Muscle.legs, Equipment.machine),
    CatalogExercise('Cable Pull-Through', Muscle.legs, Equipment.cable),
    CatalogExercise('Bodyweight Squat', Muscle.legs, Equipment.bodyweight),
    CatalogExercise('Walking Lunge', Muscle.legs, Equipment.bodyweight),
    CatalogExercise('Glute Bridge', Muscle.legs, Equipment.bodyweight),
    CatalogExercise('Step-Up', Muscle.legs, Equipment.bodyweight),
    CatalogExercise('Wall Sit', Muscle.legs, Equipment.bodyweight, ExerciseKind.timed),
    CatalogExercise('Kettlebell Swing', Muscle.legs, Equipment.kettlebell),
    CatalogExercise('Kettlebell Goblet Squat', Muscle.legs, Equipment.kettlebell),
    CatalogExercise('Banded Squat', Muscle.legs, Equipment.bands),


    CatalogExercise('Plank', Muscle.core, Equipment.bodyweight, ExerciseKind.timed),
    CatalogExercise('Side Plank', Muscle.core, Equipment.bodyweight, ExerciseKind.timed),
    CatalogExercise('Crunches', Muscle.core, Equipment.bodyweight),
    CatalogExercise('Sit-Up', Muscle.core, Equipment.bodyweight),
    CatalogExercise('Russian Twist', Muscle.core, Equipment.bodyweight),
    CatalogExercise('Mountain Climber', Muscle.core, Equipment.bodyweight),
    CatalogExercise('Leg Raise', Muscle.core, Equipment.bodyweight),
    CatalogExercise('Hanging Knee Raise', Muscle.core, Equipment.pullUpBar),
    CatalogExercise('Hanging Leg Raise', Muscle.core, Equipment.pullUpBar),
    CatalogExercise('Cable Crunch', Muscle.core, Equipment.cable),
    CatalogExercise('Ab Wheel Rollout', Muscle.core, Equipment.other),
    CatalogExercise('Pallof Press', Muscle.core, Equipment.bands),


    CatalogExercise('Running', Muscle.cardio, Equipment.bodyweight, ExerciseKind.cardio),
    CatalogExercise('Treadmill', Muscle.cardio, Equipment.cardioMachine, ExerciseKind.cardio),
    CatalogExercise('Stationary Bike', Muscle.cardio, Equipment.cardioMachine, ExerciseKind.cardio),
    CatalogExercise('Rowing Machine', Muscle.cardio, Equipment.cardioMachine, ExerciseKind.cardio),
    CatalogExercise('Elliptical', Muscle.cardio, Equipment.cardioMachine, ExerciseKind.cardio),
    CatalogExercise('Stair Climber', Muscle.cardio, Equipment.cardioMachine, ExerciseKind.cardio),
    CatalogExercise('Jump Rope', Muscle.cardio, Equipment.other, ExerciseKind.cardio),
    CatalogExercise('Cycling', Muscle.cardio, Equipment.other, ExerciseKind.cardio),
    CatalogExercise('Swimming', Muscle.cardio, Equipment.other, ExerciseKind.cardio),
    CatalogExercise('Brisk Walk', Muscle.cardio, Equipment.bodyweight, ExerciseKind.cardio),
    CatalogExercise('Jumping Jacks', Muscle.cardio, Equipment.bodyweight, ExerciseKind.cardio),
    CatalogExercise('HIIT', Muscle.cardio, Equipment.bodyweight, ExerciseKind.cardio),


    CatalogExercise('Burpee', Muscle.fullBody, Equipment.bodyweight),
    CatalogExercise('Clean and Press', Muscle.fullBody, Equipment.barbell),
    CatalogExercise('Thruster', Muscle.fullBody, Equipment.dumbbell),
    CatalogExercise('Kettlebell Clean', Muscle.fullBody, Equipment.kettlebell),
    CatalogExercise('Turkish Get-Up', Muscle.fullBody, Equipment.kettlebell),
    CatalogExercise("Farmer's Carry", Muscle.fullBody, Equipment.dumbbell, ExerciseKind.timed),
  ];
}
