import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/workout.dart';
import '../models/exercise.dart';
import '../models/user_profile.dart';
import '../models/exercise_set.dart';
import 'profile_notifier.dart';


class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;
  SharedPreferences? _prefs;

  static const _webWorkoutsPrefix = 'workout_tracker_web_workouts_v3_';
  static const _webGuestKey = 'guest';
  static const _webProfilePrefix = 'workout_tracker_web_profile_';
  static const _webSettingPrefix = 'workout_tracker_web_setting_';
  static const _cloudWorkoutsCollection = 'user_workouts';
  static const _cloudCustomWorkoutsCollection = 'user_custom_workouts';

  String get _webWorkoutsKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return '$_webWorkoutsPrefix${uid ?? _webGuestKey}';
  }

  String _webUserSettingKey(String key) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? _webGuestKey;
    return '$_webSettingPrefix${uid}_$key';
  }

  Future<SharedPreferences> get _webStorage async {
    return _prefs ??= await SharedPreferences.getInstance();
  }


  Future<Database> get database async {
    if (kIsWeb) {
      throw StateError('SQLite database is not used on Web.');
    }
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'workout_tracker.db');

    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE user_profiles ADD COLUMN updated_at INTEGER',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS app_settings '
              '(key TEXT PRIMARY KEY, value TEXT)',
            );
          }
          if (oldVersion < 4) {
            await _createSetsTable(db);
          }
          if (oldVersion < 5) {
            await db.execute('ALTER TABLE workouts ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0');
          }
          if (oldVersion < 6) {
            await db.execute('ALTER TABLE workouts ADD COLUMN is_suggested INTEGER NOT NULL DEFAULT 0');
          }
          if (oldVersion < 7) {
            await db.execute('ALTER TABLE user_profiles ADD COLUMN profile_image_url TEXT');
          }
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS app_settings '
            '(key TEXT PRIMARY KEY, value TEXT)',
          );
          await _createSetsTable(db);

          await db.execute('''
            CREATE TABLE workouts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              date TEXT NOT NULL,
              notes TEXT,
              duration_seconds INTEGER NOT NULL DEFAULT 0,
              is_suggested INTEGER NOT NULL DEFAULT 0
            )
          ''');

          await db.execute('''
            CREATE TABLE exercises (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              workout_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              sets INTEGER NOT NULL,
              reps INTEGER NOT NULL,
              weight REAL NOT NULL DEFAULT 0,
              duration_seconds INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (workout_id) REFERENCES workouts (id) ON DELETE CASCADE
            )
          ''');

          await db.execute('''
            CREATE TABLE user_profiles (
              uid TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              age INTEGER NOT NULL,
              gender TEXT,
              weight REAL,
              height REAL,
              fitness_goal TEXT,
              fitness_level TEXT,
              injuries TEXT,
              onboarding_completed INTEGER NOT NULL DEFAULT 0,
              profile_image_url TEXT,
              updated_at INTEGER
            )
          ''');
        },
      ),
    );
  }

  Future<void> _createSetsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exercise_id INTEGER NOT NULL,
        set_number INTEGER NOT NULL,
        reps INTEGER NOT NULL DEFAULT 0,
        weight REAL NOT NULL DEFAULT 0,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sets_exercise ON exercise_sets (exercise_id)',
    );
  }


  Future<List<Map<String, dynamic>>> _webReadWorkouts() async {
    final prefs = await _webStorage;
    final raw = prefs.getString(_webWorkoutsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (e) {
      debugPrint('Web workout storage read failed: $e');
      return [];
    }
  }

  Future<void> _webWriteWorkouts(List<Map<String, dynamic>> workouts) async {
    final prefs = await _webStorage;
    await prefs.setString(_webWorkoutsKey, jsonEncode(workouts));
  }

  int _nextWebId(List<Map<String, dynamic>> rows, String key) {
    var max = 0;
    for (final row in rows) {
      final value = row[key];
      if (value is num && value.toInt() > max) max = value.toInt();
    }
    return max + 1;
  }

  List<Map<String, dynamic>> _webExercises(Map<String, dynamic> workout) {
    final raw = workout['exercises'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  List<Map<String, dynamic>> _webSets(Map<String, dynamic> exercise) {
    final raw = exercise['set_rows'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Workout _webWorkoutFromRow(Map<String, dynamic> row) {
    return Workout(
      id: (row['id'] as num?)?.toInt(),
      name: row['name'] as String,
      date: DateTime.parse(row['date'] as String),
      notes: row['notes'] as String?,
      durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
      isSuggested: (row['is_suggested'] as num?)?.toInt() == 1 || row['is_suggested'] == true,
      exercises: _webExercises(row).map((e) {
        return Exercise(
          id: (e['id'] as num?)?.toInt(),
          workoutId: (row['id'] as num).toInt(),
          name: e['name'] as String,
          sets: (e['sets'] as num?)?.toInt() ?? _webSets(e).length,
          reps: (e['reps'] as num?)?.toInt() ?? 0,
          durationSeconds: (e['duration_seconds'] as num?)?.toInt() ?? 0,
        );
      }).toList(),
    );
  }

  Future<int> _webSaveWorkout(Workout workout, List<ExerciseWithSets> items) async {
    final rows = await _webReadWorkouts();
    final workoutId = _nextWebId(rows, 'id');
    var nextExerciseId = 1;
    var nextSetId = 1;
    for (final row in rows) {
      for (final e in _webExercises(row)) {
        final id = (e['id'] as num?)?.toInt() ?? 0;
        if (id >= nextExerciseId) nextExerciseId = id + 1;
        for (final s in _webSets(e)) {
          final sid = (s['id'] as num?)?.toInt() ?? 0;
          if (sid >= nextSetId) nextSetId = sid + 1;
        }
      }
    }

    final exerciseRows = <Map<String, dynamic>>[];
    for (final item in items) {
      final exerciseId = nextExerciseId++;
      exerciseRows.add({
        'id': exerciseId,
        'name': item.exercise.name,
        'sets': item.sets.length,
        'reps': item.exercise.reps,
        'duration_seconds': item.exercise.durationSeconds,
        'set_rows': item.sets.map((s) => {
          'id': nextSetId++,
          'set_number': s.setNumber,
          'reps': s.reps,
          'duration_seconds': s.durationSeconds,
        }).toList(),
      });
    }

    rows.add({
      'id': workoutId,
      'name': workout.name,
      'date': workout.date.toIso8601String(),
      'notes': workout.notes,
      'duration_seconds': workout.durationSeconds,
      'is_suggested': workout.isSuggested ? 1 : 0,
      'exercises': exerciseRows,
    });
    await _webWriteWorkouts(rows);
    return workoutId;
  }


  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  String _workoutCloudKey(Map<String, dynamic> row) {
    final exercises = _webExercises(row).map((e) {
      final sets = _webSets(e).map((s) =>
          '${s['set_number'] ?? 0}:${s['reps'] ?? 0}:${s['duration_seconds'] ?? 0}').join(',');
      return '${e['name'] ?? ''}:$sets';
    }).join('|');
    return '${row['date'] ?? ''}|${row['name'] ?? ''}|${row['duration_seconds'] ?? 0}|$exercises';
  }

  Future<List<Map<String, dynamic>>> _readCloudWorkoutRows() async {
    final uid = _currentUid;
    if (uid == null) return [];
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_cloudWorkoutsCollection)
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = doc.data();
      final raw = data?['workouts'];
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (e) {
      debugPrint('Cloud workout read failed: $e');
      return [];
    }
  }

  Future<void> _writeCloudWorkoutRows(List<Map<String, dynamic>> rows) async {
    final uid = _currentUid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection(_cloudWorkoutsCollection)
        .doc(uid)
        .set({
      'uid': uid,
      'workouts': rows,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _upsertCloudWorkoutRow(Map<String, dynamic> row) async {
    final uid = _currentUid;
    if (uid == null) return;

    try {
      final cloudRows = await _readCloudWorkoutRows();
      final key = _workoutCloudKey(row);
      final index = cloudRows.indexWhere((item) {
        final existingKey = item['cloud_key']?.toString();
        return existingKey == key || _workoutCloudKey(item) == key;
      });

      final copy = Map<String, dynamic>.from(row);
      copy['cloud_key'] = key;

      if (index >= 0) {
        cloudRows[index] = copy;
      } else {
        cloudRows.add(copy);
      }

      await _writeCloudWorkoutRows(cloudRows);
    } catch (e) {
      debugPrint('Cloud workout save failed: $e');
    }
  }

  Future<void> _syncCloudWorkoutsToLocal() async {
    if (!kIsWeb || _currentUid == null) return;

    try {
      final cloudRows = await _readCloudWorkoutRows();
      if (cloudRows.isEmpty) return;

      final localRows = await _webReadWorkouts();
      final localKeys = <String>{
        for (final row in localRows) _workoutCloudKey(row),
      };
      var nextId = _nextWebId(localRows, 'id');
      var nextExerciseId = 1;
      var nextSetId = 1;

      for (final row in localRows) {
        for (final exercise in _webExercises(row)) {
          final id = (exercise['id'] as num?)?.toInt() ?? 0;
          if (id >= nextExerciseId) nextExerciseId = id + 1;
          for (final set in _webSets(exercise)) {
            final id = (set['id'] as num?)?.toInt() ?? 0;
            if (id >= nextSetId) nextSetId = id + 1;
          }
        }
      }

      var changed = false;
      for (final raw in cloudRows) {
        final row = Map<String, dynamic>.from(raw);
        final key = row['cloud_key']?.toString().isNotEmpty == true
            ? row['cloud_key'].toString()
            : _workoutCloudKey(row);
        if (localKeys.contains(key)) continue;

        row['id'] = nextId++;
        final exerciseRows = <Map<String, dynamic>>[];
        for (final rawExercise in _webExercises(row)) {
          final exercise = Map<String, dynamic>.from(rawExercise);
          exercise['id'] = nextExerciseId++;
          final setRows = <Map<String, dynamic>>[];
          for (final rawSet in _webSets(exercise)) {
            final set = Map<String, dynamic>.from(rawSet);
            set['id'] = nextSetId++;
            setRows.add(set);
          }
          exercise['set_rows'] = setRows;
          exerciseRows.add(exercise);
        }
        row['exercises'] = exerciseRows;
        localRows.add(row);
        localKeys.add(key);
        changed = true;
      }

      if (changed) await _webWriteWorkouts(localRows);
    } catch (e) {
      debugPrint('Cloud workout sync failed: $e');
    }
  }

  Future<String?> getCloudCustomWorkouts() async {
    final uid = _currentUid;
    if (uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_cloudCustomWorkoutsCollection)
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = doc.data();
      final workouts = data?['workouts'];
      if (workouts is! List) return null;
      return jsonEncode(workouts);
    } catch (e) {
      debugPrint('Cloud custom workout read failed: $e');
      return null;
    }
  }

  Future<void> _saveCloudCustomWorkouts(String json) async {
    final uid = _currentUid;
    if (uid == null) return;
    final decoded = jsonDecode(json);
    await FirebaseFirestore.instance
        .collection(_cloudCustomWorkoutsCollection)
        .doc(uid)
        .set({
      'uid': uid,
      'workouts': decoded is List ? decoded : [],
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _syncCustomWorkoutsFromCloud() async {
    if (!kIsWeb || _currentUid == null) return;
    final cloud = await getCloudCustomWorkouts();
    if (cloud == null || cloud.isEmpty) return;
    await setSetting(customWorkoutsSettingKey, cloud);
  }

  Future<int> insertWorkout(Workout workout) async {
    if (kIsWeb) return _webSaveWorkout(workout, []);
    final db = await database;
    return db.insert('workouts', workout.toMap()..remove('id'));
  }

  Future<List<Workout>> getAllWorkouts() async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      rows.sort((a, b) => DateTime.parse(b['date'] as String)
          .compareTo(DateTime.parse(a['date'] as String)));
      return rows.map(_webWorkoutFromRow).toList();
    }
    final db = await database;
    final rows = await db.query('workouts', orderBy: 'date DESC');
    final result = <Workout>[];
    for (final row in rows) {
      final workout = Workout.fromMap(row);
      final exercises = await getExercisesForWorkout(workout.id!);
      result.add(workout.copyWith(exercises: exercises));
    }
    return result;
  }

  Future<Workout?> getWorkoutWithExercises(int workoutId) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      for (final row in rows) {
        if ((row['id'] as num?)?.toInt() == workoutId) {
          return _webWorkoutFromRow(row);
        }
      }
      return null;
    }
    final db = await database;
    final workoutRows = await db.query(
      'workouts',
      where: 'id = ?',
      whereArgs: [workoutId],
    );
    if (workoutRows.isEmpty) return null;
    final exercises = await getExercisesForWorkout(workoutId);
    return Workout.fromMap(workoutRows.first).copyWith(exercises: exercises);
  }

  Future<int> updateWorkout(Workout workout) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final index = rows.indexWhere((r) => (r['id'] as num?)?.toInt() == workout.id);
      if (index < 0) return 0;
      rows[index]['name'] = workout.name;
      rows[index]['date'] = workout.date.toIso8601String();
      rows[index]['notes'] = workout.notes;
      rows[index]['duration_seconds'] = workout.durationSeconds;
      rows[index]['is_suggested'] = workout.isSuggested ? 1 : 0;
      await _webWriteWorkouts(rows);
      return 1;
    }
    final db = await database;
    return db.update('workouts', workout.toMap(), where: 'id = ?', whereArgs: [workout.id]);
  }

  Future<void> replaceWorkout(Workout workout, List<ExerciseWithSets> items) async {
    if (workout.id == null) throw ArgumentError('Workout id is required');
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final index = rows.indexWhere((r) => (r['id'] as num?)?.toInt() == workout.id);
      if (index < 0) throw StateError('Workout not found');
      var nextExerciseId = 1;
      var nextSetId = 1;
      for (final row in rows) {
        for (final e in _webExercises(row)) {
          final eid = (e['id'] as num?)?.toInt() ?? 0;
          if (eid >= nextExerciseId) nextExerciseId = eid + 1;
          for (final set in _webSets(e)) {
            final sid = (set['id'] as num?)?.toInt() ?? 0;
            if (sid >= nextSetId) nextSetId = sid + 1;
          }
        }
      }
      final exerciseRows = <Map<String, dynamic>>[];
      for (final item in items) {
        final exerciseId = nextExerciseId++;
        exerciseRows.add({
          'id': exerciseId,
          'name': item.exercise.name,
          'sets': item.sets.length,
          'reps': item.exercise.reps,
          'duration_seconds': item.exercise.durationSeconds,
          'set_rows': item.sets.map((set) => {
            'id': nextSetId++,
            'set_number': set.setNumber,
            'reps': set.reps,
            'duration_seconds': set.durationSeconds,
          }).toList(),
        });
      }
      rows[index] = {
        'id': workout.id,
        'name': workout.name,
        'date': workout.date.toIso8601String(),
        'notes': workout.notes,
        'duration_seconds': workout.durationSeconds,
        'is_suggested': workout.isSuggested ? 1 : 0,
        'exercises': exerciseRows,
      };
      await _webWriteWorkouts(rows);
      return;
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'exercise_sets',
        where: 'exercise_id IN (SELECT id FROM exercises WHERE workout_id = ?)',
        whereArgs: [workout.id],
      );
      await txn.delete('exercises', where: 'workout_id = ?', whereArgs: [workout.id]);
      await txn.update('workouts', workout.toMap(), where: 'id = ?', whereArgs: [workout.id]);
      for (final item in items) {
        final exerciseId = await txn.insert(
          'exercises',
          item.exercise.copyWith(workoutId: workout.id).toMap()..remove('id'),
        );
        for (final set in item.sets) {
          await txn.insert('exercise_sets', {
            'exercise_id': exerciseId,
            'set_number': set.setNumber,
            'reps': set.reps,
            'weight': 0,
            'duration_seconds': set.durationSeconds,
          });
        }
      }
    });
  }

  Future<int> deleteWorkout(int workoutId) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final before = rows.length;
      rows.removeWhere((r) => (r['id'] as num?)?.toInt() == workoutId);
      if (rows.length != before) await _webWriteWorkouts(rows);
      return before - rows.length;
    }
    final db = await database;
    return db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM exercise_sets WHERE exercise_id IN '
        '(SELECT id FROM exercises WHERE workout_id = ?)',
        [workoutId],
      );
      await txn.delete('exercises', where: 'workout_id = ?', whereArgs: [workoutId]);
      return txn.delete('workouts', where: 'id = ?', whereArgs: [workoutId]);
    });
  }

  Future<int> saveWorkout(Workout workout, List<ExerciseWithSets> items) async {
    if (kIsWeb) {
      final workoutId = await _webSaveWorkout(workout, items);
      final rows = await _webReadWorkouts();
      final index = rows.indexWhere((r) => (r['id'] as num?)?.toInt() == workoutId);
      if (index >= 0) {
        await _upsertCloudWorkoutRow(rows[index]);
      }
      return workoutId;
    }

    final db = await database;
    final workoutId = await db.transaction((txn) async {
      final workoutId = await txn.insert('workouts', workout.toMap()..remove('id'));
      for (final item in items) {
        final exerciseId = await txn.insert(
          'exercises',
          item.exercise.copyWith(workoutId: workoutId).toMap()..remove('id'),
        );
        for (final s in item.sets) {
          await txn.insert('exercise_sets', {
            'exercise_id': exerciseId,
            'set_number': s.setNumber,
            'reps': s.reps,
            'weight': 0,
            'duration_seconds': s.durationSeconds,
          });
        }
      }
      return workoutId;
    });

    return workoutId;
  }


  Future<int> insertExercise(Exercise exercise) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final workout = rows.firstWhere(
        (r) => (r['id'] as num?)?.toInt() == exercise.workoutId,
        orElse: () => <String, dynamic>{},
      );
      if (workout.isEmpty) return 0;
      final id = _nextWebId(
        rows.expand((r) => _webExercises(r)).toList(),
        'id',
      );
      final e = exercise.copyWith(id: id);
      final exercises = _webExercises(workout);
      exercises.add(e.toMap()..remove('workout_id'));
      workout['exercises'] = exercises;
      await _webWriteWorkouts(rows);
      return id;
    }
    final db = await database;
    return db.insert('exercises', exercise.toMap()..remove('id'));
  }

  Future<List<Exercise>> getExercisesForWorkout(int workoutId) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final row = rows.firstWhere(
        (r) => (r['id'] as num?)?.toInt() == workoutId,
        orElse: () => <String, dynamic>{},
      );
      if (row.isEmpty) return [];
      return _webWorkoutFromRow(row).exercises;
    }
    final db = await database;
    final rows = await db.query('exercises', where: 'workout_id = ?', whereArgs: [workoutId]);
    return rows.map((r) => Exercise.fromMap(r)).toList();
  }

  Future<int> updateExercise(Exercise exercise) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      for (final workout in rows) {
        final exercises = _webExercises(workout);
        final index = exercises.indexWhere((e) => (e['id'] as num?)?.toInt() == exercise.id);
        if (index >= 0) {
          final oldSets = exercises[index]['set_rows'];
          exercises[index] = exercise.toMap()..remove('workout_id');
          exercises[index]['set_rows'] = oldSets;
          await _webWriteWorkouts(rows);
          return 1;
        }
      }
      return 0;
    }
    final db = await database;
    return db.update('exercises', exercise.toMap(), where: 'id = ?', whereArgs: [exercise.id]);
  }

  Future<int> deleteExercise(int exerciseId) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      for (final workout in rows) {
        final exercises = _webExercises(workout);
        final before = exercises.length;
        exercises.removeWhere((e) => (e['id'] as num?)?.toInt() == exerciseId);
        if (before != exercises.length) {
          await _webWriteWorkouts(rows);
          return 1;
        }
      }
      return 0;
    }
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete('exercise_sets', where: 'exercise_id = ?', whereArgs: [exerciseId]);
      return txn.delete('exercises', where: 'id = ?', whereArgs: [exerciseId]);
    });
  }


  Future<bool> _writeLocalProfile(UserProfile profile) async {
    if (kIsWeb) {
      try {
        final prefs = await _webStorage;
        await prefs.setString(
          '$_webProfilePrefix${profile.uid}',
          jsonEncode(profile.toMap()),
        );
        return true;
      } catch (e) {
        debugPrint('Web profile save failed: $e');
        return false;
      }
    }
    try {
      final db = await database;
      await db.insert('user_profiles', profile.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (e) {
      debugPrint('Local profile save failed: $e');
      return false;
    }
  }

  Future<bool> _writeCloudProfile(UserProfile profile) async {
    try {
      await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(profile.uid)
          .set(profile.toMap())
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (e) {
      debugPrint('Cloud profile save failed: $e');
      return false;
    }
  }

  Future<UserProfile?> _readLocalProfile(String uid) async {
    if (kIsWeb) {
      try {
        final prefs = await _webStorage;
        final raw = prefs.getString('$_webProfilePrefix$uid');
        if (raw != null) return UserProfile.fromMap(jsonDecode(raw));
      } catch (e) {
        debugPrint('Web profile load failed: $e');
      }
      return null;
    }
    try {
      final db = await database;
      final rows = await db.query('user_profiles', where: 'uid = ?', whereArgs: [uid]);
      if (rows.isNotEmpty) return UserProfile.fromMap(rows.first);
    } catch (e) {
      debugPrint('Local profile load failed: $e');
    }
    return null;
  }

  Future<UserProfile?> _readCloudProfile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final data = doc.data();
      if (data != null) return UserProfile.fromMap(data);
    } catch (e) {
      debugPrint('Cloud profile load failed: $e');
    }
    return null;
  }

  UserProfile? _pickBest(UserProfile? a, UserProfile? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.onboardingCompleted != b.onboardingCompleted) {
      return a.onboardingCompleted ? a : b;
    }
    return (b.updatedAt ?? 0) > (a.updatedAt ?? 0) ? b : a;
  }

  Future<void> upsertUserProfile(
    UserProfile profile, {
    bool requireCloud = false,
  }) async {
    if (!profile.onboardingCompleted) {
      final existing = await _readLocalProfile(profile.uid);
      if (existing != null && existing.onboardingCompleted) return;
    }

    final stamped = profile.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    final localOk = await _writeLocalProfile(stamped);
    final cloudOk = await _writeCloudProfile(stamped);

    if ((!localOk && !cloudOk) || (requireCloud && !cloudOk)) {
      throw Exception('Could not save your profile. Please try again.');
    }

    // Tell the rest of the app (like Home) right away.
    ProfileNotifier.current.value = stamped;
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final results = await Future.wait<UserProfile?>([
      _readLocalProfile(uid),
      _readCloudProfile(uid),
    ]);

    final local = results[0];
    final cloud = results[1];
    final best = _pickBest(local, cloud);

    if (best != null && (local == null || best.updatedAt != local.updatedAt)) {
      await _writeLocalProfile(best);
    }

    return best;
  }

  Future<void> _syncWithCloud(String uid, UserProfile local) async {
    try {
      final cloud = await _readCloudProfile(uid);
      if (cloud == null) {
        await _writeCloudProfile(local);
        return;
      }
      if (cloud.onboardingCompleted == local.onboardingCompleted && cloud.updatedAt == local.updatedAt) {
        return;
      }
      final best = _pickBest(cloud, local);
      if (identical(best, cloud)) {
        await _writeLocalProfile(cloud);
      } else if (best != null) {
        await _writeCloudProfile(best);
      }
    } catch (e) {
      debugPrint('Profile sync failed: $e');
    }
  }


  Future<String?> getSetting(String key) async {
    if (kIsWeb) {
      final prefs = await _webStorage;
      return prefs.getString(_webUserSettingKey(key));
    }
    final db = await database;
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    if (kIsWeb) {
      final prefs = await _webStorage;
      await prefs.setString(_webUserSettingKey(key), value);
      return;
    }
    final db = await database;
    await db.insert('app_settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }


  static const customWorkoutsSettingKey = 'custom_workouts_v1';
  static const activeWorkoutSettingKey = 'active_workout_v1';

  Future<String?> getCustomWorkouts() async {
    await _syncCustomWorkoutsFromCloud();
    return getSetting(customWorkoutsSettingKey);
  }

  Future<void> saveCustomWorkouts(
    String json, {
    bool requireCloud = false,
  }) async {
    await setSetting(customWorkoutsSettingKey, json);
    try {
      await _saveCloudCustomWorkouts(json);
    } catch (e) {
      debugPrint('Cloud custom workout save failed: $e');
      if (requireCloud && _currentUid != null) rethrow;
    }
  }

  Future<void> saveActiveWorkout(String json) => setSetting(activeWorkoutSettingKey, json);

  Future<String?> getActiveWorkout() => getSetting(activeWorkoutSettingKey);

  Future<void> clearActiveWorkout() => setSetting(activeWorkoutSettingKey, '');


  Future<List<String>> getRecentExerciseNames({int limit = 8}) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final latest = <String, DateTime>{};
      for (final workout in rows) {
        final date = DateTime.parse(workout['date'] as String);
        for (final e in _webExercises(workout)) {
          final name = e['name'] as String;
          final key = name.toLowerCase();
          if (!latest.containsKey(key) || date.isAfter(latest[key]!)) latest[key] = date;
        }
      }
      final entries = latest.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return entries.take(limit).map((e) => e.key).toList();
    }
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.name AS name, MAX(w.date) AS last_date
      FROM exercises e JOIN workouts w ON e.workout_id = w.id
      GROUP BY LOWER(e.name) ORDER BY last_date DESC LIMIT ?
    ''', [limit]);
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<Map<String, dynamic>?> getLastPerformance(String exerciseName) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final sessions = await getExerciseSessions(exerciseName);
      if (sessions.isEmpty) return null;
      final last = sessions.last;
      final first = last.sets.isNotEmpty ? last.sets.last : const ExerciseSet(exerciseId: 0, setNumber: 1);
      return {
        'sets': last.sets.length,
        'reps': first.reps,
        'duration_seconds': first.durationSeconds,
        'date': last.date.toIso8601String(),
      };
    }
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.sets, e.reps, e.weight, e.duration_seconds, w.date
      FROM exercises e JOIN workouts w ON e.workout_id = w.id
      WHERE e.name = ? COLLATE NOCASE ORDER BY w.date DESC, e.id DESC LIMIT 1
    ''', [exerciseName]);
    return rows.isEmpty ? null : rows.first;
  }


  List<ExerciseSet> _legacySets(int exerciseId, Map<String, dynamic> row) {
    final count = (row['sum_sets'] as num).toInt();
    return List.generate(
      count < 1 ? 1 : count,
      (i) => ExerciseSet(
        exerciseId: exerciseId,
        setNumber: i + 1,
        reps: (row['sum_reps'] as num).toInt(),
        durationSeconds: (row['sum_duration'] as num).toInt(),
      ),
    );
  }

  Future<Map<int, List<ExerciseSet>>> getSetsForWorkout(int workoutId) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final workout = await getWorkoutWithExercises(workoutId);
      final rows = await _webReadWorkouts();
      final raw = rows.firstWhere(
        (r) => (r['id'] as num?)?.toInt() == workoutId,
        orElse: () => <String, dynamic>{},
      );
      final result = <int, List<ExerciseSet>>{};
      if (raw.isEmpty) return result;
      for (final e in _webExercises(raw)) {
        final id = (e['id'] as num).toInt();
        final sets = _webSets(e);
        result[id] = sets.isNotEmpty
            ? sets.map((s) => ExerciseSet(
                  id: (s['id'] as num?)?.toInt(),
                  exerciseId: id,
                  setNumber: (s['set_number'] as num).toInt(),
                  reps: (s['reps'] as num).toInt(),
                  durationSeconds: (s['duration_seconds'] as num).toInt(),
                )).toList()
            : _legacySets(id, e.map((k, v) => MapEntry('sum_$k', v)));
      }

      if (workout == null) return result;
      return result;
    }
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.* FROM exercise_sets s JOIN exercises e ON s.exercise_id = e.id
      WHERE e.workout_id = ? ORDER BY s.exercise_id ASC, s.set_number ASC
    ''', [workoutId]);
    final result = <int, List<ExerciseSet>>{};
    for (final r in rows) {
      final s = ExerciseSet.fromMap(r);
      result.putIfAbsent(s.exerciseId, () => []).add(s);
    }
    return result;
  }

  Future<List<ExerciseSet>> getLastSets(String exerciseName) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final sessions = await getExerciseSessions(exerciseName);
      return sessions.isEmpty ? [] : sessions.last.sets;
    }
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.id AS id, e.sets AS sum_sets, e.reps AS sum_reps,
             e.weight AS sum_weight, e.duration_seconds AS sum_duration
      FROM exercises e JOIN workouts w ON e.workout_id = w.id
      WHERE e.name = ? COLLATE NOCASE ORDER BY w.date DESC, e.id DESC LIMIT 1
    ''', [exerciseName]);
    if (rows.isEmpty) return [];
    final id = (rows.first['id'] as num).toInt();
    final setRows = await db.query('exercise_sets', where: 'exercise_id = ?', whereArgs: [id], orderBy: 'set_number ASC');
    if (setRows.isNotEmpty) return setRows.map(ExerciseSet.fromMap).toList();
    return _legacySets(id, rows.first);
  }

  Future<List<ExerciseSession>> getExerciseSessions(String exerciseName) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final result = <ExerciseSession>[];
      rows.sort((a, b) => DateTime.parse(a['date'] as String).compareTo(DateTime.parse(b['date'] as String)));
      for (final workout in rows) {
        for (final e in _webExercises(workout)) {
          if ((e['name'] as String).toLowerCase() != exerciseName.toLowerCase()) continue;
          final id = (e['id'] as num).toInt();
          final rawSets = _webSets(e);
          final sets = rawSets.isNotEmpty
              ? rawSets.map((s) => ExerciseSet(
                    id: (s['id'] as num?)?.toInt(),
                    exerciseId: id,
                    setNumber: (s['set_number'] as num).toInt(),
                    reps: (s['reps'] as num).toInt(),
                    durationSeconds: (s['duration_seconds'] as num).toInt(),
                  )).toList()
              : _legacySets(id, {
                  'sum_sets': e['sets'] ?? 1,
                  'sum_reps': e['reps'] ?? 0,
                          'sum_duration': e['duration_seconds'] ?? 0,
                });
          result.add(ExerciseSession(
            exerciseId: id,
            date: DateTime.parse(workout['date'] as String),
            sets: sets,
          ));
        }
      }
      return result;
    }

    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.id AS exercise_id, e.sets AS sum_sets, e.reps AS sum_reps,
             e.weight AS sum_weight, e.duration_seconds AS sum_duration,
             w.date AS date, s.set_number AS set_number, s.reps AS set_reps,
             s.weight AS set_weight, s.duration_seconds AS set_duration
      FROM exercises e JOIN workouts w ON e.workout_id = w.id
      LEFT JOIN exercise_sets s ON s.exercise_id = e.id
      WHERE e.name = ? COLLATE NOCASE
      ORDER BY w.date ASC, e.id ASC, s.set_number ASC
    ''', [exerciseName]);

    final order = <int>[];
    final dates = <int, DateTime>{};
    final sets = <int, List<ExerciseSet>>{};
    final firstRow = <int, Map<String, dynamic>>{};

    for (final r in rows) {
      final id = (r['exercise_id'] as num).toInt();
      if (!sets.containsKey(id)) {
        order.add(id);
        dates[id] = DateTime.parse(r['date'] as String);
        sets[id] = [];
        firstRow[id] = r;
      }
      if (r['set_number'] != null) {
        sets[id]!.add(ExerciseSet(
          exerciseId: id,
          setNumber: (r['set_number'] as num).toInt(),
          reps: (r['set_reps'] as num).toInt(),
          durationSeconds: (r['set_duration'] as num).toInt(),
        ));
      }
    }

    return order.map((id) {
      var list = sets[id]!;
      if (list.isEmpty) list = _legacySets(id, firstRow[id]!);
      return ExerciseSession(exerciseId: id, date: dates[id]!, sets: list);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getLoggedExerciseSummaries() async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final groups = <String, Map<String, dynamic>>{};
      for (final workout in rows) {
        final date = DateTime.parse(workout['date'] as String);
        for (final e in _webExercises(workout)) {
          final name = e['name'] as String;
          final key = name.toLowerCase();
          final rawSets = _webSets(e);
          final reps = rawSets.isEmpty
              ? [(e['reps'] as num?)?.toInt() ?? 0]
              : rawSets.map((s) => (s['reps'] as num?)?.toInt() ?? 0).toList();
          final durations = rawSets.isEmpty
              ? [(e['duration_seconds'] as num?)?.toInt() ?? 0]
              : rawSets.map((s) => (s['duration_seconds'] as num?)?.toInt() ?? 0).toList();
          final existing = groups[key];
          if (existing == null) {
            groups[key] = {
              'name': name,
              'sessions': 1,
              'last_date': date.toIso8601String(),
              'best_reps': reps.fold<int>(0, (m, v) => v > m ? v : m),
              'best_duration': durations.fold<int>(0, (m, v) => v > m ? v : m),
              '_workouts': <String>{workout['id'].toString()},
            };
          } else {
            final ids = existing['_workouts'] as Set<String>;
            if (ids.add(workout['id'].toString())) existing['sessions'] = ids.length;
            if (date.isAfter(DateTime.parse(existing['last_date'] as String))) {
              existing['last_date'] = date.toIso8601String();
            }
            final br = reps.fold<int>(0, (m, v) => v > m ? v : m);
            final bd = durations.fold<int>(0, (m, v) => v > m ? v : m);
            if (br > (existing['best_reps'] as num).toInt()) existing['best_reps'] = br;
            if (bd > (existing['best_duration'] as num).toInt()) existing['best_duration'] = bd;
          }
        }
      }
      final result = groups.values.map((r) {
        final copy = Map<String, dynamic>.from(r)..remove('_workouts');
        return copy;
      }).toList();
      result.sort((a, b) => DateTime.parse(b['last_date'] as String).compareTo(DateTime.parse(a['last_date'] as String)));
      return result;
    }

    final db = await database;
    return db.rawQuery('''
      SELECT e.name AS name, COUNT(DISTINCT e.workout_id) AS sessions,
             MAX(w.date) AS last_date,
             MAX(COALESCE(s.reps, e.reps)) AS best_reps,
             MAX(COALESCE(s.duration_seconds, e.duration_seconds)) AS best_duration
      FROM exercises e JOIN workouts w ON e.workout_id = w.id
      LEFT JOIN exercise_sets s ON s.exercise_id = e.id
      GROUP BY LOWER(e.name) ORDER BY last_date DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getExerciseHistory(String exerciseName) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final sessions = await getExerciseSessions(exerciseName);
      return sessions.map((s) => {
        'sets': s.sets.length,
        'reps': s.bestReps,
        'date': s.date.toIso8601String(),
      }).toList();
    }
    final db = await database;
    return db.rawQuery('''
      SELECT e.sets, e.reps, w.date
      FROM exercises e JOIN workouts w ON e.workout_id = w.id
      WHERE e.name = ? ORDER BY w.date ASC
    ''', [exerciseName]);
  }
}