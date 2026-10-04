import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' show Random;

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

  Future<Database>? _dbFuture;
  String? _dbKey;
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


  /// One SQLite file per signed-in user, so accounts on the same device never
  /// see each other's workouts, settings or active workout.
  Future<Database> get database {
    if (kIsWeb) {
      return Future<Database>.error(
        StateError('SQLite database is not used on Web.'),
      );
    }

    final key = FirebaseAuth.instance.currentUser?.uid ?? _webGuestKey;
    final current = _dbFuture;
    if (current != null && _dbKey == key) return current;

    final previous = current;
    final future = () async {
      if (previous != null) {
        try {
          await (await previous).close();
        } catch (e) {
          debugPrint('Closing previous database failed: $e');
        }
      }
      return _initDb(key);
    }();

    _dbKey = key;
    _dbFuture = future;
    future.then<void>((_) {}, onError: (Object e) {
      debugPrint('Opening database failed: $e');
      if (identical(_dbFuture, future)) {
        _dbFuture = null;
        _dbKey = null;
      }
    });
    return future;
  }

  Future<Database> _initDb(String key) async {
    final dbPath = await getDatabasesPath();
    final userPath = join(dbPath, 'workout_tracker_$key.db');

    if (key != _webGuestKey) {
      await _adoptLegacyDatabase(
        key,
        join(dbPath, 'workout_tracker.db'),
        userPath,
      );
    }

    return _openDb(userPath);
  }

  /// Before this version every account shared one file. If that old file
  /// holds a profile for [uid], copy it so the person keeps their history.
  Future<void> _adoptLegacyDatabase(
    String uid,
    String legacyPath,
    String userPath,
  ) async {
    try {
      if (await databaseFactory.databaseExists(userPath)) return;
      if (!await databaseFactory.databaseExists(legacyPath)) return;

      final legacy = await _openDb(legacyPath);
      var owns = false;
      try {
        final rows = await legacy.query(
          'user_profiles',
          columns: ['uid'],
          where: 'uid = ?',
          whereArgs: [uid],
          limit: 1,
        );
        owns = rows.isNotEmpty;
      } finally {
        await legacy.close();
      }

      if (owns) await File(legacyPath).copy(userPath);
    } catch (e) {
      debugPrint('Legacy database adoption failed: $e');
    }
  }

  Future<Database> _openDb(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
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
          if (oldVersion < 8) {
            await db.execute('ALTER TABLE workouts ADD COLUMN cloud_id TEXT');
            await db.execute('ALTER TABLE workouts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
            await db.execute('ALTER TABLE workouts ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1');
            await db.execute('UPDATE workouts SET cloud_id = lower(hex(randomblob(16))) WHERE cloud_id IS NULL');
            await db.execute('UPDATE workouts SET updated_at = ${DateTime.now().millisecondsSinceEpoch}');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_workouts_cloud ON workouts (cloud_id)');
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
              is_suggested INTEGER NOT NULL DEFAULT 0,
              cloud_id TEXT,
              updated_at INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_workouts_cloud ON workouts (cloud_id)');

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
      'cloud_id': _newCloudId(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'dirty': 1,
      'exercises': exerciseRows,
    });
    await _webWriteWorkouts(rows);
    return workoutId;
  }


  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  // ---------------------------------------------------------------------
  // Workout cloud sync
  //
  // * Every workout has a stable `cloud_id`.
  // * Each workout is its own Firestore document:
  //     user_workouts/{uid}/items/{cloud_id}
  //   so there is no 1 MiB document limit and no read-modify-write races.
  // * Deletes are stored as tombstones ({deleted: true}) so they reach other
  //   devices and deleted workouts never come back.
  // * Conflicts use last-write-wins on `updated_at`.
  // * Works the same on web (shared_preferences) and mobile (SQLite).
  // ---------------------------------------------------------------------

  static const _lastPullSettingKey = 'cloud_last_pull_v1';
  static const _pendingDeletesSettingKey = 'pending_cloud_deletes_v1';
  static const _legacyMigratedSettingKey = 'legacy_cloud_workouts_migrated_v1';
  static const _customDirtySettingKey = 'custom_workouts_dirty_v1';
  static const _syncOverlapMs = 5 * 60 * 1000;
  static const _syncMinInterval = Duration(seconds: 90);
  static const _pageSize = 200;

  final Map<String, DateTime> _lastSyncAttempt = {};
  final Set<String> _syncedOnce = {};
  Future<void>? _syncFuture;
  bool _syncAgain = false;

  CollectionReference<Map<String, dynamic>> _cloudItems(String uid) {
    return FirebaseFirestore.instance
        .collection(_cloudWorkoutsCollection)
        .doc(uid)
        .collection('items');
  }

  int _asInt(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  String _newCloudId() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${random.nextInt(1 << 30).toRadixString(36)}'
        '${random.nextInt(1 << 30).toRadixString(36)}';
  }

  /// Old content-based key (kept so workouts synced by older versions of the
  /// app can be matched instead of duplicated).
  String _workoutCloudKey(Map<String, dynamic> row) {
    final exercises = _webExercises(row).map((e) {
      final sets = _webSets(e).map((s) =>
          '${s['set_number'] ?? 0}:${s['reps'] ?? 0}:${s['duration_seconds'] ?? 0}').join(',');
      return '${e['name'] ?? ''}:$sets';
    }).join('|');
    return '${row['date'] ?? ''}|${row['name'] ?? ''}|${row['duration_seconds'] ?? 0}|$exercises';
  }

  String _legacyCloudId(String key) {
    var h1 = 7;
    var h2 = 13;
    for (final unit in key.codeUnits) {
      h1 = (h1 * 31 + unit) % 4294967296;
      h2 = (h2 * 131 + unit) % 4294967296;
    }
    return 'legacy_${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}';
  }

  /// Local row (web shape) -> neutral shape without local ids.
  Map<String, dynamic> _rowToWrow(Map<String, dynamic> row) {
    return {
      'cloud_id': row['cloud_id'],
      'name': row['name'],
      'date': row['date'],
      'notes': row['notes'],
      'duration_seconds': _asInt(row['duration_seconds']),
      'is_suggested': _asInt(row['is_suggested']),
      'updated_at': _asInt(row['updated_at']),
      'exercises': [
        for (final e in _webExercises(row))
          {
            'name': e['name'],
            'sets': e['sets'] != null ? _asInt(e['sets']) : _webSets(e).length,
            'reps': _asInt(e['reps']),
            'duration_seconds': _asInt(e['duration_seconds']),
            'set_rows': [
              for (final s in _webSets(e))
                {
                  'set_number': _asInt(s['set_number']),
                  'reps': _asInt(s['reps']),
                  'duration_seconds': _asInt(s['duration_seconds']),
                },
            ],
          },
      ],
    };
  }

  Map<String, dynamic> _wrowToCloud(String uid, Map<String, dynamic> wrow) {
    return {
      'uid': uid,
      'deleted': false,
      'name': wrow['name'],
      'date': wrow['date'],
      'notes': wrow['notes'],
      'duration_seconds': _asInt(wrow['duration_seconds']),
      'is_suggested': _asInt(wrow['is_suggested']),
      'updated_at': _asInt(wrow['updated_at']),
      'exercises': wrow['exercises'],
    };
  }

  /// Keeps the old name so existing call sites keep working. Reads only wait
  /// for the network the first time in a session; after that sync runs in the
  /// background.
  Future<void> _syncCloudWorkoutsToLocal() => _syncForRead();

  Future<void> _syncForRead() async {
    final uid = _currentUid;
    if (uid == null) return;
    if (_syncedOnce.contains(uid)) {
      unawaited(syncWorkouts());
      return;
    }
    await syncWorkouts();
  }

  void _afterLocalWorkoutChange() {
    unawaited(syncWorkouts(force: true));
  }

  /// Never throws. Safe to call as often as you like.
  Future<void> syncWorkouts({bool force = false}) {
    final uid = _currentUid;
    if (uid == null) return Future<void>.value();

    final running = _syncFuture;
    if (running != null) {
      if (force) _syncAgain = true;
      return running;
    }

    if (!force) {
      final last = _lastSyncAttempt[uid];
      if (last != null && DateTime.now().difference(last) < _syncMinInterval) {
        return Future<void>.value();
      }
    }

    final future = () async {
      try {
        do {
          _syncAgain = false;
          await _runWorkoutSync(uid);
        } while (_syncAgain && _currentUid == uid);
      } catch (e) {
        debugPrint('Workout sync failed: $e');
      } finally {
        _lastSyncAttempt[uid] = DateTime.now();
        _syncedOnce.add(uid);
        _syncFuture = null;
      }
    }();
    _syncFuture = future;
    return future;
  }

  Future<void> _runWorkoutSync(String uid) async {
    final col = _cloudItems(uid);

    await _localAssignCloudIds();
    await _migrateLegacyCloudWorkouts(uid, col);
    if (_currentUid != uid) return;

    await _flushPendingDeletes(uid, col);
    if (_currentUid != uid) return;

    await _pullCloudChanges(uid, col);
    if (_currentUid != uid) return;

    await _pushDirtyWorkouts(uid, col);
  }

  // ---- pending deletes -------------------------------------------------

  Future<Map<String, int>> _loadPendingDeletes() async {
    final raw = await getSetting(_pendingDeletesSettingKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return <String, int>{
        for (final entry in decoded.entries)
          entry.key.toString(): _asInt(entry.value),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePendingDeletes(Map<String, int> pending) {
    return setSetting(_pendingDeletesSettingKey, jsonEncode(pending));
  }

  Future<void> _queueCloudDelete(String? cloudId) async {
    if (cloudId == null || cloudId.isEmpty || _currentUid == null) return;
    final pending = await _loadPendingDeletes();
    pending[cloudId] = DateTime.now().millisecondsSinceEpoch;
    await _savePendingDeletes(pending);
    _afterLocalWorkoutChange();
  }

  Future<void> _flushPendingDeletes(
    String uid,
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final pending = await _loadPendingDeletes();
    if (pending.isEmpty) return;

    final ids = pending.keys.toList();
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.skip(i).take(400).toList();
      final batch = FirebaseFirestore.instance.batch();
      for (final id in chunk) {
        batch.set(col.doc(id), {
          'uid': uid,
          'deleted': true,
          'updated_at': pending[id] ?? DateTime.now().millisecondsSinceEpoch,
        });
      }
      try {
        await batch.commit().timeout(const Duration(seconds: 15));
        chunk.forEach(pending.remove);
        await _savePendingDeletes(pending);
      } catch (e) {
        debugPrint('Cloud delete flush failed: $e');
        return;
      }
    }
  }

  // ---- legacy (single-document) migration ------------------------------

  Future<void> _migrateLegacyCloudWorkouts(
    String uid,
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    if (await getSetting(_legacyMigratedSettingKey) == '1') return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(_cloudWorkoutsCollection)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final raw = doc.data()?['workouts'];
      if (raw is List) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final item in raw.whereType<Map>()) {
          final row = Map<String, dynamic>.from(item);
          final key = row['cloud_key']?.toString().isNotEmpty == true
              ? row['cloud_key'].toString()
              : _workoutCloudKey(row);
          final id = _legacyCloudId(key);
          final ref = col.doc(id);

          final existing = await ref.get(
            const GetOptions(source: Source.server),
          );
          if (existing.exists) continue;

          final wrow = _rowToWrow(row);
          wrow['cloud_id'] = id;
          wrow['updated_at'] = now;
          if (wrow['name'] is! String || wrow['date'] is! String) continue;
          await ref.set(_wrowToCloud(uid, wrow));
        }
      }

      await setSetting(_legacyMigratedSettingKey, '1');
    } catch (e) {
      debugPrint('Legacy cloud workout migration failed: $e');
    }
  }

  // ---- pull / push -----------------------------------------------------

  Future<void> _pullCloudChanges(
    String uid,
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final lastPull =
        int.tryParse(await getSetting(_lastPullSettingKey) ?? '') ?? 0;
    final since = lastPull > 0 ? lastPull - _syncOverlapMs : 0;
    final skip = (await _loadPendingDeletes()).keys.toSet();

    var maxSeen = lastPull;
    DocumentSnapshot<Map<String, dynamic>>? cursor;

    while (true) {
      Query<Map<String, dynamic>> query = col
          .where('updated_at', isGreaterThan: since)
          .orderBy('updated_at')
          .limit(_pageSize);
      if (cursor != null) query = query.startAfterDocument(cursor);

      final snap = await query
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final docs = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['cloud_id'] = d.id;
        final updated = _asInt(data['updated_at']);
        if (updated > maxSeen) maxSeen = updated;
        docs.add(data);
      }

      if (_currentUid != uid) return;
      if (docs.isNotEmpty) await _localApplyCloudDocs(docs, skip);

      if (snap.docs.length < _pageSize) break;
      cursor = snap.docs.last;
    }

    if (maxSeen > lastPull) {
      await setSetting(_lastPullSettingKey, maxSeen.toString());
    }
  }

  Future<void> _pushDirtyWorkouts(
    String uid,
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final dirty = await _localDirtyWorkouts();
    if (dirty.isEmpty) return;

    for (var i = 0; i < dirty.length; i += 200) {
      if (_currentUid != uid) return;
      final chunk = dirty.skip(i).take(200).toList();

      final batch = FirebaseFirestore.instance.batch();
      final versions = <int, int>{};
      for (final item in chunk) {
        final wrow = item['wrow'] as Map<String, dynamic>;
        batch.set(
          col.doc(wrow['cloud_id'].toString()),
          _wrowToCloud(uid, wrow),
        );
        versions[item['local_id'] as int] = _asInt(wrow['updated_at']);
      }

      await batch.commit().timeout(const Duration(seconds: 20));
      await _localMarkClean(versions);
    }
  }

  // ---- local adapters (web + SQLite) -----------------------------------

  Future<void> _localAssignCloudIds() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (kIsWeb) {
      final rows = await _webReadWorkouts();
      final seen = <String>{
        for (final row in rows)
          if (row['cloud_id']?.toString().isNotEmpty == true)
            row['cloud_id'].toString(),
      };
      var changed = false;
      for (final row in rows) {
        if (row['cloud_id']?.toString().isNotEmpty == true) continue;
        var id = _legacyCloudId(_workoutCloudKey(row));
        if (seen.contains(id)) id = _newCloudId();
        seen.add(id);
        row['cloud_id'] = id;
        row['updated_at'] = now;
        row['dirty'] = 1;
        changed = true;
      }
      if (changed) await _webWriteWorkouts(rows);
      return;
    }

    final db = await database;
    final rows = await db.query(
      'workouts',
      columns: ['id'],
      where: "cloud_id IS NULL OR cloud_id = ''",
    );
    for (final row in rows) {
      await db.update(
        'workouts',
        {'cloud_id': _newCloudId(), 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<List<Map<String, dynamic>>> _localDirtyWorkouts() async {
    if (kIsWeb) {
      final rows = await _webReadWorkouts();
      return [
        for (final row in rows)
          if (_asInt(row['dirty']) == 1 &&
              row['cloud_id']?.toString().isNotEmpty == true)
            {'local_id': _asInt(row['id']), 'wrow': _rowToWrow(row)},
      ];
    }

    final db = await database;
    final rows = await db.query('workouts', where: 'dirty = 1');
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row['cloud_id']?.toString().isNotEmpty != true) continue;
      result.add({
        'local_id': _asInt(row['id']),
        'wrow': await _sqlToWrow(db, row),
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> _sqlToWrow(
    DatabaseExecutor db,
    Map<String, Object?> workout,
  ) async {
    final id = _asInt(workout['id']);
    final exerciseRows = await db.query(
      'exercises',
      where: 'workout_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );

    final exercises = <Map<String, dynamic>>[];
    for (final e in exerciseRows) {
      final setRows = await db.query(
        'exercise_sets',
        where: 'exercise_id = ?',
        whereArgs: [e['id']],
        orderBy: 'set_number ASC, id ASC',
      );
      exercises.add({
        'name': e['name'],
        'sets': _asInt(e['sets']),
        'reps': _asInt(e['reps']),
        'duration_seconds': _asInt(e['duration_seconds']),
        'set_rows': [
          for (final s in setRows)
            {
              'set_number': _asInt(s['set_number']),
              'reps': _asInt(s['reps']),
              'duration_seconds': _asInt(s['duration_seconds']),
            },
        ],
      });
    }

    return {
      'cloud_id': workout['cloud_id'],
      'name': workout['name'],
      'date': workout['date'],
      'notes': workout['notes'],
      'duration_seconds': _asInt(workout['duration_seconds']),
      'is_suggested': _asInt(workout['is_suggested']),
      'updated_at': _asInt(workout['updated_at']),
      'exercises': exercises,
    };
  }

  /// Clears the dirty flag, but only for rows that were not edited again
  /// while the upload was running.
  Future<void> _localMarkClean(Map<int, int> versions) async {
    if (kIsWeb) {
      final rows = await _webReadWorkouts();
      var changed = false;
      for (final row in rows) {
        final version = versions[_asInt(row['id'])];
        if (version != null &&
            _asInt(row['updated_at']) == version &&
            _asInt(row['dirty']) == 1) {
          row['dirty'] = 0;
          changed = true;
        }
      }
      if (changed) await _webWriteWorkouts(rows);
      return;
    }

    final db = await database;
    final batch = db.batch();
    versions.forEach((id, version) {
      batch.rawUpdate(
        'UPDATE workouts SET dirty = 0 WHERE id = ? AND updated_at = ?',
        [id, version],
      );
    });
    await batch.commit(noResult: true);
  }

  Future<void> _localApplyCloudDocs(
    List<Map<String, dynamic>> docs,
    Set<String> skip,
  ) {
    return kIsWeb ? _webApplyCloudDocs(docs, skip) : _sqlApplyCloudDocs(docs, skip);
  }

  Future<void> _webApplyCloudDocs(
    List<Map<String, dynamic>> docs,
    Set<String> skip,
  ) async {
    final rows = await _webReadWorkouts();
    final byCloud = <String, int>{};
    var nextWorkoutId = 1;
    var nextExerciseId = 1;
    var nextSetId = 1;

    for (var i = 0; i < rows.length; i++) {
      final cid = rows[i]['cloud_id']?.toString() ?? '';
      if (cid.isNotEmpty) byCloud[cid] = i;
      final id = _asInt(rows[i]['id']);
      if (id >= nextWorkoutId) nextWorkoutId = id + 1;
      for (final e in _webExercises(rows[i])) {
        final eid = _asInt(e['id']);
        if (eid >= nextExerciseId) nextExerciseId = eid + 1;
        for (final s in _webSets(e)) {
          final sid = _asInt(s['id']);
          if (sid >= nextSetId) nextSetId = sid + 1;
        }
      }
    }

    final removeIds = <String>{};
    var changed = false;

    for (final doc in docs) {
      final cid = doc['cloud_id'].toString();
      if (skip.contains(cid)) continue;

      final index = byCloud[cid];
      final cloudUpdated = _asInt(doc['updated_at']);
      final localUpdated =
          index == null ? -1 : _asInt(rows[index]['updated_at']);

      if (doc['deleted'] == true) {
        if (index != null && cloudUpdated >= localUpdated) {
          removeIds.add(cid);
          changed = true;
        }
        continue;
      }

      if (index != null && cloudUpdated <= localUpdated) continue;
      if (doc['name'] is! String || doc['date'] is! String) continue;

      final exercises = <Map<String, dynamic>>[];
      for (final e in _mapList(doc['exercises'])) {
        final setRows = _mapList(e['set_rows']);
        exercises.add({
          'id': nextExerciseId++,
          'name': e['name']?.toString() ?? '',
          'sets': e['sets'] != null ? _asInt(e['sets']) : setRows.length,
          'reps': _asInt(e['reps']),
          'duration_seconds': _asInt(e['duration_seconds']),
          'set_rows': [
            for (final s in setRows)
              {
                'id': nextSetId++,
                'set_number': _asInt(s['set_number']),
                'reps': _asInt(s['reps']),
                'duration_seconds': _asInt(s['duration_seconds']),
              },
          ],
        });
      }

      final row = <String, dynamic>{
        'id': index == null ? nextWorkoutId++ : _asInt(rows[index]['id']),
        'cloud_id': cid,
        'updated_at': cloudUpdated,
        'dirty': 0,
        'name': doc['name'],
        'date': doc['date'],
        'notes': doc['notes'],
        'duration_seconds': _asInt(doc['duration_seconds']),
        'is_suggested': _asInt(doc['is_suggested']),
        'exercises': exercises,
      };

      if (index == null) {
        rows.add(row);
        byCloud[cid] = rows.length - 1;
      } else {
        rows[index] = row;
      }
      changed = true;
    }

    if (removeIds.isNotEmpty) {
      rows.removeWhere((r) => removeIds.contains(r['cloud_id']?.toString()));
    }
    if (changed) await _webWriteWorkouts(rows);
  }

  Future<void> _sqlApplyCloudDocs(
    List<Map<String, dynamic>> docs,
    Set<String> skip,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final meta = await txn.query(
        'workouts',
        columns: ['id', 'cloud_id', 'updated_at'],
      );
      final byCloud = <String, Map<String, Object?>>{};
      for (final m in meta) {
        final cid = m['cloud_id']?.toString() ?? '';
        if (cid.isNotEmpty) byCloud[cid] = m;
      }

      for (final doc in docs) {
        final cid = doc['cloud_id'].toString();
        if (skip.contains(cid)) continue;

        final local = byCloud[cid];
        final cloudUpdated = _asInt(doc['updated_at']);
        final localUpdated = local == null ? -1 : _asInt(local['updated_at']);

        if (doc['deleted'] == true) {
          if (local != null && cloudUpdated >= localUpdated) {
            await _sqlDeleteWorkoutRows(txn, _asInt(local['id']));
            byCloud.remove(cid);
          }
          continue;
        }

        if (local != null && cloudUpdated <= localUpdated) continue;
        if (doc['name'] is! String || doc['date'] is! String) continue;

        final values = <String, Object?>{
          'name': doc['name'],
          'date': doc['date'],
          'notes': doc['notes'],
          'duration_seconds': _asInt(doc['duration_seconds']),
          'is_suggested': _asInt(doc['is_suggested']),
          'cloud_id': cid,
          'updated_at': cloudUpdated,
          'dirty': 0,
        };

        int id;
        if (local == null) {
          id = await txn.insert('workouts', values);
        } else {
          id = _asInt(local['id']);
          await txn.update('workouts', values, where: 'id = ?', whereArgs: [id]);
          await txn.rawDelete(
            'DELETE FROM exercise_sets WHERE exercise_id IN '
            '(SELECT id FROM exercises WHERE workout_id = ?)',
            [id],
          );
          await txn.delete('exercises', where: 'workout_id = ?', whereArgs: [id]);
        }

        for (final e in _mapList(doc['exercises'])) {
          final setRows = _mapList(e['set_rows']);
          final exerciseId = await txn.insert('exercises', {
            'workout_id': id,
            'name': e['name']?.toString() ?? '',
            'sets': e['sets'] != null ? _asInt(e['sets']) : setRows.length,
            'reps': _asInt(e['reps']),
            'weight': 0,
            'duration_seconds': _asInt(e['duration_seconds']),
          });
          for (final s in setRows) {
            await txn.insert('exercise_sets', {
              'exercise_id': exerciseId,
              'set_number': _asInt(s['set_number']),
              'reps': _asInt(s['reps']),
              'weight': 0,
              'duration_seconds': _asInt(s['duration_seconds']),
            });
          }
        }

        byCloud[cid] = {'id': id, 'cloud_id': cid, 'updated_at': cloudUpdated};
      }
    });
  }

  Future<void> _sqlDeleteWorkoutRows(DatabaseExecutor db, int workoutId) async {
    await db.rawDelete(
      'DELETE FROM exercise_sets WHERE exercise_id IN '
      '(SELECT id FROM exercises WHERE workout_id = ?)',
      [workoutId],
    );
    await db.delete('exercises', where: 'workout_id = ?', whereArgs: [workoutId]);
    await db.delete('workouts', where: 'id = ?', whereArgs: [workoutId]);
  }

  // ---- helpers used by the mutation methods ----------------------------

  void _webTouch(Map<String, dynamic> row) {
    row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    row['dirty'] = 1;
    if (row['cloud_id']?.toString().isNotEmpty != true) {
      row['cloud_id'] = _newCloudId();
    }
  }

  Future<void> _sqlTouch(DatabaseExecutor db, int workoutId) async {
    await db.rawUpdate(
      'UPDATE workouts SET updated_at = ?, dirty = 1 WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, workoutId],
    );
  }

  Map<String, Object?> _sqlNewSyncFields() => {
        'cloud_id': _newCloudId(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      };

  Map<String, Object?> _sqlTouchFields() => {
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      };

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

  final Map<String, DateTime> _lastCustomPull = {};

  Future<void> _syncCustomWorkoutsFromCloud() async {
    final uid = _currentUid;
    if (uid == null) return;

    // Local edits that never reached the cloud win and get re-uploaded.
    if (await getSetting(_customDirtySettingKey) == '1') {
      final local = await getSetting(customWorkoutsSettingKey);
      if (local != null && local.isNotEmpty) {
        try {
          await _saveCloudCustomWorkouts(local);
          await setSetting(_customDirtySettingKey, '0');
        } catch (e) {
          debugPrint('Custom workout re-upload failed: $e');
        }
      }
      return;
    }

    final last = _lastCustomPull[uid];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastCustomPull[uid] = DateTime.now();

    final cloud = await getCloudCustomWorkouts();
    if (cloud == null || cloud.isEmpty) return;
    await setSetting(customWorkoutsSettingKey, cloud);
  }

  Future<int> insertWorkout(Workout workout) async {
    if (kIsWeb) {
      final id = await _webSaveWorkout(workout, []);
      _afterLocalWorkoutChange();
      return id;
    }
    final db = await database;
    final id = await db.insert(
      'workouts',
      {...workout.toMap()..remove('id'), ..._sqlNewSyncFields()},
    );
    _afterLocalWorkoutChange();
    return id;
  }

  Future<List<Workout>> getAllWorkouts() async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      rows.sort((a, b) => DateTime.parse(b['date'] as String)
          .compareTo(DateTime.parse(a['date'] as String)));
      return rows.map(_webWorkoutFromRow).toList();
    }
    await _syncForRead();
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
      _webTouch(rows[index]);
      await _webWriteWorkouts(rows);
      _afterLocalWorkoutChange();
      return 1;
    }
    final db = await database;
    final changed = await db.update(
      'workouts',
      {...workout.toMap(), ..._sqlTouchFields()},
      where: 'id = ?',
      whereArgs: [workout.id],
    );
    if (changed > 0) _afterLocalWorkoutChange();
    return changed;
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
      final replacement = <String, dynamic>{
        'id': workout.id,
        'cloud_id': rows[index]['cloud_id'],
        'name': workout.name,
        'date': workout.date.toIso8601String(),
        'notes': workout.notes,
        'duration_seconds': workout.durationSeconds,
        'is_suggested': workout.isSuggested ? 1 : 0,
        'exercises': exerciseRows,
      };
      _webTouch(replacement);
      rows[index] = replacement;
      await _webWriteWorkouts(rows);
      _afterLocalWorkoutChange();
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
      await txn.update(
        'workouts',
        {...workout.toMap(), ..._sqlTouchFields()},
        where: 'id = ?',
        whereArgs: [workout.id],
      );
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
    _afterLocalWorkoutChange();
  }

  Future<int> deleteWorkout(int workoutId) async {
    if (kIsWeb) {
      await _syncCloudWorkoutsToLocal();
      final rows = await _webReadWorkouts();
      final before = rows.length;
      String? cloudId;
      for (final r in rows) {
        if ((r['id'] as num?)?.toInt() == workoutId) {
          cloudId = r['cloud_id']?.toString();
        }
      }
      rows.removeWhere((r) => (r['id'] as num?)?.toInt() == workoutId);
      if (rows.length != before) {
        await _webWriteWorkouts(rows);
        await _queueCloudDelete(cloudId);
      }
      return before - rows.length;
    }
    final db = await database;
    final found = await db.query(
      'workouts',
      columns: ['cloud_id'],
      where: 'id = ?',
      whereArgs: [workoutId],
    );
    final cloudId = found.isEmpty ? null : found.first['cloud_id']?.toString();
    final removed = await db.transaction((txn) async {
      await _sqlDeleteWorkoutRows(txn, workoutId);
      return found.isEmpty ? 0 : 1;
    });
    if (removed > 0) await _queueCloudDelete(cloudId);
    return removed;
  }

  Future<int> saveWorkout(Workout workout, List<ExerciseWithSets> items) async {
    if (kIsWeb) {
      final workoutId = await _webSaveWorkout(workout, items);
      _afterLocalWorkoutChange();
      return workoutId;
    }

    final db = await database;
    final workoutId = await db.transaction((txn) async {
      final workoutId = await txn.insert(
        'workouts',
        {...workout.toMap()..remove('id'), ..._sqlNewSyncFields()},
      );
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

    _afterLocalWorkoutChange();
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
      _webTouch(workout);
      await _webWriteWorkouts(rows);
      _afterLocalWorkoutChange();
      return id;
    }
    final db = await database;
    final newId = await db.insert('exercises', exercise.toMap()..remove('id'));
    await _sqlTouch(db, exercise.workoutId);
    _afterLocalWorkoutChange();
    return newId;
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
          workout['exercises'] = exercises;
          _webTouch(workout);
          await _webWriteWorkouts(rows);
          _afterLocalWorkoutChange();
          return 1;
        }
      }
      return 0;
    }
    final db = await database;
    final changed = await db.update('exercises', exercise.toMap(), where: 'id = ?', whereArgs: [exercise.id]);
    if (changed > 0) {
      await _sqlTouch(db, exercise.workoutId);
      _afterLocalWorkoutChange();
    }
    return changed;
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
          workout['exercises'] = exercises;
          _webTouch(workout);
          await _webWriteWorkouts(rows);
          _afterLocalWorkoutChange();
          return 1;
        }
      }
      return 0;
    }
    final db = await database;
    final owner = await db.query(
      'exercises',
      columns: ['workout_id'],
      where: 'id = ?',
      whereArgs: [exerciseId],
    );
    final removed = await db.transaction((txn) async {
      await txn.delete('exercise_sets', where: 'exercise_id = ?', whereArgs: [exerciseId]);
      return txn.delete('exercises', where: 'id = ?', whereArgs: [exerciseId]);
    });
    if (removed > 0 && owner.isNotEmpty) {
      await _sqlTouch(db, _asInt(owner.first['workout_id']));
      _afterLocalWorkoutChange();
    }
    return removed;
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
    unawaited(syncWorkouts());
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
    await setSetting(_customDirtySettingKey, '1');
    try {
      await _saveCloudCustomWorkouts(json);
      await setSetting(_customDirtySettingKey, '0');
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