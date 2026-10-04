import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, ValueNotifier, debugPrint, kIsWeb;

import '../auth.dart';
import '../models/workout.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// One message in the in-app notification list (the bell on Home).
class InboxItem {
  final String id; // unique, e.g. "reminder-2026-10-05"
  final String type; // reminder | streak | summary | test
  final String title;
  final String body;
  final DateTime time;
  final bool read;

  const InboxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
  });

  InboxItem asRead() => InboxItem(
        id: id,
        type: type,
        title: title,
        body: body,
        time: time,
        read: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'time': time.toIso8601String(),
        'read': read,
      };

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'reminder',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        time: DateTime.parse(j['time'] as String),
        read: j['read'] == true,
      );
}

/// The list behind the bell. Stored per user in app settings.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox._();
  static final instance = NotificationInbox._();

  static const int _maxItems = 50;

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  List<InboxItem> _items = [];
  String? _loadedFor;

  List<InboxItem> get items => List.unmodifiable(_items);

  String _key(String uid) => 'notif_inbox_$uid';

  Future<void> load() async {
    final uid = Auth().currentUser?.uid;
    if (uid == null) {
      _items = [];
      _loadedFor = null;
      _publish();
      return;
    }
    if (_loadedFor == uid) return;
    try {
      final raw = await DatabaseService.instance.getSetting(_key(uid));
      if (raw == null || raw.isEmpty) {
        _items = [];
      } else {
        final list = jsonDecode(raw) as List<dynamic>;
        _items = list
            .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Inbox load failed: $e');
      _items = [];
    }
    _loadedFor = uid;
    _publish();
  }

  Future<void> _save() async {
    final uid = Auth().currentUser?.uid;
    if (uid == null) return;
    try {
      await DatabaseService.instance.setSetting(
        _key(uid),
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Inbox save failed: $e');
    }
  }

  void _publish() {
    unreadCount.value = _items.where((e) => !e.read).length;
    notifyListeners();
  }

  /// Adds an item unless one with the same id already exists.
  Future<void> add(InboxItem item) async {
    await load();
    if (_items.any((e) => e.id == item.id)) return;
    _items.add(item);
    _items.sort((a, b) => b.time.compareTo(a.time));
    if (_items.length > _maxItems) {
      _items = _items.sublist(0, _maxItems);
    }
    _publish();
    await _save();
  }

  Future<void> markAllRead() async {
    if (_items.every((e) => e.read)) return;
    _items = _items.map((e) => e.asRead()).toList();
    _publish();
    await _save();
  }

  Future<void> clear() async {
    _items = [];
    _publish();
    await _save();
  }

  /// Forget everything in memory (used when the signed-in user changes).
  void reset() {
    _items = [];
    _loadedFor = null;
    _publish();
  }
}

class _Planned {
  final String id; // inbox id
  final int notifId;
  final String type;
  final DateTime when;
  final String title;
  final String body;

  const _Planned({
    required this.id,
    required this.notifId,
    required this.type,
    required this.when,
    required this.title,
    required this.body,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'notifId': notifId,
        'type': type,
        'when': when.toIso8601String(),
        'title': title,
        'body': body,
      };

  factory _Planned.fromJson(Map<String, dynamic> j) => _Planned(
        id: j['id'] as String,
        notifId: (j['notifId'] as num).toInt(),
        type: j['type'] as String,
        when: DateTime.parse(j['when'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
      );
}

/// Decides which notifications should exist, schedules them, and keeps the
/// in-app bell in sync.
///
/// Phones can't run code at the moment a scheduled notification appears, so
/// the plan is rebuilt whenever the app opens, resumes, or a workout is saved.
/// That is what makes "skip the reminder if I already trained today" work.
class NotificationCoordinator {
  NotificationCoordinator._();
  static final instance = NotificationCoordinator._();

  static const int _horizonDays = 7;
  static const int _summaryHour = 19; // Sunday 7:00 PM
  static const int _streakWarnMinutes = 20 * 60 + 30; // 8:30 PM

  static const List<List<String>> _reminderMessages = [
    ['💪 Time to train!', 'Your workout is waiting. Even a short session counts.'],
    ['🔥 Keep the fire going', 'A quick session today keeps your momentum alive.'],
    ['🏋️ Your future self says thanks', 'Lace up and log a workout — you will feel great after.'],
    ['⏱️ 20 minutes is enough', 'No time for a full session? A short one still moves you forward.'],
    ['🚀 Let\'s go!', 'Small steps add up. Open the app and start your workout.'],
    ['💥 Show up for yourself', 'Consistency beats intensity. Log today\'s workout.'],
    ['🎯 Hit your weekly goal', 'One more session brings you closer to this week\'s target.'],
  ];

  String _enabledKey(String uid) => 'workout_notifications_${uid}_enabled';
  String _timeKey(String uid) => 'workout_notifications_${uid}_time';
  String _planKey(String uid) => 'notif_plan_$uid';

  bool _busy = false;
  bool _again = false;

  /// Rebuilds the schedule and updates the bell. Safe to call often.
  Future<void> refresh() async {
    if (kIsWeb) {
      await NotificationInbox.instance.load();
      return;
    }
    if (_busy) {
      _again = true; // run once more when the current pass finishes
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _refreshOnce();
      } while (_again);
    } catch (e) {
      debugPrint('Notification refresh failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _refreshOnce() async {
    final user = Auth().currentUser;
    if (user == null) {
      NotificationInbox.instance.reset();
      await NotificationService.instance.cancelAllScheduled();
      return;
    }
    final uid = user.uid;
    final db = DatabaseService.instance;
    final inbox = NotificationInbox.instance;

    await inbox.load();

    // 1) Anything we planned that has now fired goes into the bell.
    final oldPlan = await _readPlan(uid);
    final now = DateTime.now();
    for (final p in oldPlan) {
      if (!p.when.isAfter(now)) {
        await inbox.add(InboxItem(
          id: p.id,
          type: p.type,
          title: p.title,
          body: p.body,
          time: p.when,
        ));
      }
    }

    // 2) Rebuild the schedule.
    await NotificationService.instance.cancelAllScheduled();

    final enabled = (await db.getSetting(_enabledKey(uid))) == 'true';
    if (!enabled) {
      await db.setSetting(_planKey(uid), '[]');
      return;
    }

    var hour = 18;
    var minute = 0;
    final rawTime = await db.getSetting(_timeKey(uid));
    if (rawTime != null && rawTime.contains(':')) {
      final parts = rawTime.split(':');
      hour = int.tryParse(parts[0]) ?? 18;
      minute = int.tryParse(parts[1]) ?? 0;
    }

    final workouts = await db.getAllWorkouts();
    final plan = _buildPlan(workouts, hour, minute, now);

    for (final p in plan) {
      await NotificationService.instance.scheduleAt(
        id: p.notifId,
        when: p.when,
        title: p.title,
        body: p.body,
      );
    }
    await db.setSetting(
      _planKey(uid),
      jsonEncode(plan.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<_Planned>> _readPlan(String uid) async {
    try {
      final raw = await DatabaseService.instance.getSetting(_planKey(uid));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _Planned.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateId(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<_Planned> _buildPlan(
    List<Workout> workouts,
    int hour,
    int minute,
    DateTime now,
  ) {
    final today = _day(now);
    final trained = <DateTime>{for (final w in workouts) _day(w.date)};
    final workedOutToday = trained.contains(today);

    // Current streak (same rule as the Home screen).
    var cursor = workedOutToday ? today : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (trained.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final plan = <_Planned>[];
    final reminderMinutes = hour * 60 + minute;

    // Where the streak warning goes: 8:30 PM, unless that is too close to the
    // daily reminder, then 90 minutes after the reminder.
    var warnMinutes = _streakWarnMinutes;
    if ((warnMinutes - reminderMinutes).abs() < 60) {
      warnMinutes = reminderMinutes + 90;
    }
    final warnOk = warnMinutes <= 23 * 60 + 30;

    for (var i = 0; i < _horizonDays; i++) {
      final day = today.add(Duration(days: i));
      final skipToday = i == 0 && workedOutToday;

      // Smart reminder: nothing for a day you already trained.
      if (!skipToday) {
        final msg = _reminderMessages[
            (day.difference(DateTime(day.year, 1, 1)).inDays) %
                _reminderMessages.length];
        plan.add(_Planned(
          id: 'reminder-${_dateId(day)}',
          notifId: NotificationService.reminderBaseId + i,
          type: 'reminder',
          when: DateTime(day.year, day.month, day.day, hour, minute),
          title: msg[0],
          body: msg[1],
        ));
      }

      // Streak warning: only when we know the streak count for sure.
      //  - today, if you have not trained yet
      //  - tomorrow, if you trained today
      int? atRisk;
      if (i == 0 && !workedOutToday) atRisk = streak;
      if (i == 1 && workedOutToday) atRisk = streak;
      if (warnOk && atRisk != null && atRisk >= 2) {
        plan.add(_Planned(
          id: 'streak-${_dateId(day)}',
          notifId: NotificationService.streakBaseId + i,
          type: 'streak',
          when: DateTime(
            day.year,
            day.month,
            day.day,
            warnMinutes ~/ 60,
            warnMinutes % 60,
          ),
          title: '🔥 Your $atRisk-day streak ends tonight',
          body: 'A short session saves it. Open the app and log a quick workout.',
        ));
      }
    }

    // Weekly summary: the next Sunday at 7 PM (counts as of now; refreshed
    // every time the app opens or a workout is saved).
    var sunday = today.add(Duration(days: DateTime.sunday - today.weekday));
    if (!DateTime(sunday.year, sunday.month, sunday.day, _summaryHour)
        .isAfter(now)) {
      sunday = sunday.add(const Duration(days: 7));
    }
    final monday = sunday.subtract(const Duration(days: 6));
    final weekWorkouts = workouts.where((w) {
      final d = _day(w.date);
      return !d.isBefore(monday) && !d.isAfter(sunday);
    }).toList();
    final weekDays = {for (final w in weekWorkouts) _day(w.date)}.length;

    final String summaryBody;
    if (weekWorkouts.isEmpty) {
      summaryBody =
          'No workouts logged this week. A new week starts tomorrow — begin with a short session.';
    } else {
      final dayWord = weekDays == 1 ? 'day' : 'days';
      final wkWord = weekWorkouts.length == 1 ? 'workout' : 'workouts';
      summaryBody =
          'You trained $weekDays $dayWord this week, ${weekWorkouts.length} $wkWord total. Nice work!';
    }
    plan.add(_Planned(
      id: 'summary-${_dateId(sunday)}',
      notifId: NotificationService.weeklySummaryId,
      type: 'summary',
      when: DateTime(sunday.year, sunday.month, sunday.day, _summaryHour),
      title: '📊 Your week in review',
      body: summaryBody,
    ));

    // Only keep things that are still in the future; past ones never fired.
    plan.removeWhere((p) => !p.when.isAfter(now));
    return plan;
  }

  /// Sends a notification right now and adds it to the bell.
  Future<void> sendTest() async {
    const title = '💪 Time to train!';
    const body = 'This is how your workout reminders will look.';
    await NotificationService.instance.showTestNotification(title, body);
    await NotificationInbox.instance.add(InboxItem(
      id: 'test-${DateTime.now().millisecondsSinceEpoch}',
      type: 'test',
      title: title,
      body: body,
      time: DateTime.now(),
    ));
  }
}