import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Low-level wrapper around the phone's notification system.
/// What to send and when is decided in `notification_coordinator.dart`.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  // Notification ids used by the app.
  static const int legacyReminderId = 1001; // old single daily reminder
  static const int reminderBaseId = 2000; // + day offset (0..13)
  static const int streakBaseId = 2100; // + day offset (0..13)
  static const int weeklySummaryId = 2200;
  static const int _testNotificationId = 9001;

  static const String actionStartWorkout = 'start_workout';

  // Android notification channels can't be changed after they are created, so
  // an improved look uses a new channel id. The old one is removed on init.
  static const String _oldChannelId = 'workout_reminders';
  static const String _channelId = 'workout_reminders_v2';
  static const String _channelName = 'Workout reminders';
  static const String _channelDescription =
      'Reminders, streak alerts and weekly summaries.';

  /// Set to true when the user taps "Start workout" on a notification.
  /// The Home screen listens to this and jumps to the Log tab.
  final ValueNotifier<bool> openLogRequest = ValueNotifier<bool>(false);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    // Notifications are scheduled by absolute instant (see scheduleAt), so the
    // zone only has to be consistent. This works in every country.
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onResponse,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.deleteNotificationChannel(_oldChannelId);
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max, // lets it drop down as a banner
          showBadge: true,
        ),
      );
    }

    _initialized = true;
  }

  void _onResponse(NotificationResponse response) {
    if (response.actionId == actionStartWorkout) {
      openLogRequest.value = true;
    }
  }

  /// If the app was opened by tapping "Start workout" while it was closed,
  /// returns true once (then forgets it).
  Future<bool> consumeLaunchAction() async {
    if (kIsWeb) return false;
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return false;
    return details.notificationResponse?.actionId == actionStartWorkout;
  }

  NotificationDetails _details(String title, String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        icon: 'ic_notification', // white dumbbell in res/drawable
        color: const Color(0xFFE53935), // app accent red
        number: 1, // badge count on the app icon (launcher permitting)
        channelShowBadge: true,
        ticker: 'Workout Tracker',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Workout Tracker',
        ),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            actionStartWorkout,
            'Start workout',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
      ),
    );
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return androidGranted ?? iosGranted ?? false;
  }

  /// Removes every notification this app has scheduled.
  Future<void> cancelAllScheduled() async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(legacyReminderId);
    for (var i = 0; i < 14; i++) {
      await _plugin.cancel(reminderBaseId + i);
      await _plugin.cancel(streakBaseId + i);
    }
    await _plugin.cancel(weeklySummaryId);
  }

  /// Shows a notification immediately so you can see how it looks.
  Future<void> showTestNotification(String title, String body) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.show(_testNotificationId, title, body, _details(title, body));
  }

  /// Schedules a single notification at [when] (device local time).
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await initialize();

    // `when` is device-local time; converting by instant keeps the reminder
    // at the right wall-clock time wherever the device is.
    final scheduled = tz.TZDateTime.from(
      DateTime(when.year, when.month, when.day, when.hour, when.minute),
      tz.local,
    );
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      _details(title, body),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}