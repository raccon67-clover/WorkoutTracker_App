import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import '../models/user_profile.dart';
import '../services/database_service.dart';
import '../services/cloudinary_service.dart';
import '../services/notification_service.dart';
import '../widget_tree.dart';
import 'edit_profile_page.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _bmiCategory(double bmi) {
  if (bmi <= 0) return '-';
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}

class ProfilePage extends StatefulWidget {
  final int visitToken;

  const ProfilePage({super.key, this.visitToken = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? _profile;
  List<Map<String, dynamic>> _weightHistory = [];
  bool _loading = true;
  bool _notificationsEnabled = false;
  int _notificationHour = 18;
  int _notificationMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitToken != widget.visitToken) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    if (mounted) setState(() => _loading = true);

    UserProfile? profile;
    List<Map<String, dynamic>> history = [];
    final user = Auth().currentUser;

    final profileFuture = user == null
        ? Future<UserProfile?>.value(null)
        : DatabaseService.instance.getUserProfile(user.uid);
    final historyFuture = DatabaseService.instance.getSetting('body_weight_history_v1');
    final notificationEnabledFuture = user == null
        ? Future<String?>.value(null)
        : DatabaseService.instance.getSetting(_notificationSettingKey(user.uid, 'enabled'));
    final notificationTimeFuture = user == null
        ? Future<String?>.value(null)
        : DatabaseService.instance.getSetting(_notificationSettingKey(user.uid, 'time'));

    try {
      final results = await Future.wait<Object?>([
        profileFuture,
        historyFuture,
        notificationEnabledFuture,
        notificationTimeFuture,
      ]);
      profile = results[0] as UserProfile?;
      final raw = results[1] as String?;
      final enabledRaw = results[2] as String?;
      final timeRaw = results[3] as String?;
      _notificationsEnabled = enabledRaw == 'true';
      if (timeRaw != null) {
        final parts = timeRaw.split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);
          if (hour != null && minute != null && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
            _notificationHour = hour;
            _notificationMinute = minute;
          }
        }
      }
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          history = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Profile screen data load failed: $e');

      if (profile == null && user != null) {
        try {
          profile = await DatabaseService.instance.getUserProfile(user.uid);
        } catch (retryError) {
          debugPrint('Profile retry failed: $retryError');
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _weightHistory = history;
      _loading = false;
    });
  }

  String _notificationSettingKey(String uid, String key) =>
      'workout_notifications_${uid}_$key';

  String _formatReminderTime() {
    final hour12 = _notificationHour % 12 == 0 ? 12 : _notificationHour % 12;
    final suffix = _notificationHour >= 12 ? 'PM' : 'AM';
    return '$hour12:${_notificationMinute.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _setWorkoutReminders(bool enabled) async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workout notifications are available on Android and iOS.'),
          ),
        );
      }
      return;
    }

    final user = Auth().currentUser;
    if (user == null) return;

    if (!enabled) {
      await NotificationService.instance.cancelWorkoutReminder();
      await DatabaseService.instance.setSetting(
        _notificationSettingKey(user.uid, 'enabled'),
        'false',
      );
      if (!mounted) return;
      setState(() => _notificationsEnabled = false);
      return;
    }

    final granted = await NotificationService.instance.requestPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification permission was not granted.'),
        ),
      );
      return;
    }

    try {
      await NotificationService.instance.scheduleDailyWorkoutReminder(
        hour: _notificationHour,
        minute: _notificationMinute,
      );
      await DatabaseService.instance.setSetting(
        _notificationSettingKey(user.uid, 'enabled'),
        'true',
      );
      await DatabaseService.instance.setSetting(
        _notificationSettingKey(user.uid, 'time'),
        '${_notificationHour.toString().padLeft(2, '0')}:${_notificationMinute.toString().padLeft(2, '0')}',
      );
      if (!mounted) return;
      setState(() => _notificationsEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daily reminder set for ${_formatReminderTime()}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule reminder: $e')),
      );
    }
  }

  Future<void> _changeReminderTime() async {
    final user = Auth().currentUser;
    if (user == null) return;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _notificationHour, minute: _notificationMinute),
    );
    if (picked == null) return;

    setState(() {
      _notificationHour = picked.hour;
      _notificationMinute = picked.minute;
    });

    if (!_notificationsEnabled) return;

    try {
      await NotificationService.instance.scheduleDailyWorkoutReminder(
        hour: picked.hour,
        minute: picked.minute,
      );
      await DatabaseService.instance.setSetting(
        _notificationSettingKey(user.uid, 'time'),
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reminder moved to ${_formatReminderTime()}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update reminder: $e')),
      );
    }
  }

  Widget _notificationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.notifications_active_outlined, color: kAccent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workout reminders',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Get a daily reminder to stay on track.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _notificationsEnabled,
                onChanged: _setWorkoutReminders,
                activeTrackColor: kAccent,
              ),
            ],
          ),
          if (_notificationsEnabled) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _changeReminderTime,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded, color: kAccent, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Daily reminder time',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Text(
                      _formatReminderTime(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changeProfilePhoto() async {
    final user = Auth().currentUser;
    final p = _profile;
    if (user == null || p == null) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null) return;

    if (!CloudinaryService.instance.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloudinary is not configured yet.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await CloudinaryService.instance.uploadImage(
        bytes: bytes,
        fileName: file.name,
        folder: 'workout_tracker/profile_images/${user.uid}',
      );
      final updated = p.copyWith(
        profileImageUrl: url,
        onboardingCompleted: true,
      );
      await DatabaseService.instance.upsertUserProfile(updated);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $e')),
      );
    }
  }

  Future<void> _editProfile() async {
    final p = _profile;
    if (p == null) return;

    final updated = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(profile: p)),
    );

    if (updated == null || !mounted) return;
    setState(() => _profile = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  Future<void> _updateWeight() async {
    final p = _profile;
    if (p == null) return;

    final controller = TextEditingController(
      text: p.weight != null ? p.weight!.toStringAsFixed(1) : '',
    );

    final newWeight = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Update weight', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 22),
          decoration: const InputDecoration(suffixText: 'kg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0 || value > 500) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter a valid weight')),
                );
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newWeight == null) return;

    final updated = p.copyWith(weight: newWeight, onboardingCompleted: true);

    try {
      final history = List<Map<String, dynamic>>.from(_weightHistory);
      history.add({'date': DateTime.now().toIso8601String(), 'weight': newWeight});
      history.sort((a, b) => DateTime.parse(b['date'] as String).compareTo(DateTime.parse(a['date'] as String)));
      if (history.length > 30) history.removeRange(30, history.length);
      await DatabaseService.instance.setSetting('body_weight_history_v1', jsonEncode(history));
      await DatabaseService.instance.upsertUserProfile(updated);
      if (!mounted) return;
      setState(() { _profile = updated; _weightHistory = history; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weight updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Widget _bodyWeightHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Body Weight History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_weightHistory.isEmpty)
          Text('Your body-weight entries will appear here.', style: TextStyle(color: Colors.grey[600], fontSize: 12))
        else
          ..._weightHistory.take(6).map((entry) {
            final date = DateTime.parse(entry['date'] as String);
            final value = (entry['weight'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text('${date.day}/${date.month}/${date.year}', style: TextStyle(color: Colors.grey[500], fontSize: 12))),
                Text('${value.toStringAsFixed(1)} kg', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            );
          }),
      ]),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await Auth().signOut();
    if (!mounted) return;


    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WidgetTree()),
      (route) => false,
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kAccent, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: kAccent, size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _bmiCard(double bmi) {

    final fraction = ((bmi - 15) / 25).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Body Mass Index',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                _bmiCategory(bmi),
                style: const TextStyle(
                  color: kAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bmi > 0 ? bmi.toStringAsFixed(1) : '-',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 35,
                              child: Container(height: 8, color: Colors.lightBlue),
                            ),
                            Expanded(
                              flex: 65,
                              child: Container(height: 8, color: Colors.green),
                            ),
                            Expanded(
                              flex: 50,
                              child: Container(height: 8, color: Colors.amber),
                            ),
                            Expanded(
                              flex: 100,
                              child: Container(height: 8, color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (bmi > 0)
                      Positioned(
                        left: (fraction * w) - 7,
                        top: 4,
                        child: Container(
                          width: 14,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: kBackground, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('15', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              Text('18.5', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              Text('25', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              Text('30', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              Text('40', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Auth().currentUser;
    final p = _profile;
    final name = p?.name ?? user?.displayName ?? 'Athlete';

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : RefreshIndicator(
                onRefresh: _loadProfile,
                color: kAccent,
                backgroundColor: kSurface,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _loading ? null : _changeProfilePhoto,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    color: kAccent,
                                    shape: BoxShape.circle,
                                    image: p?.profileImageUrl != null && p!.profileImageUrl!.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(p.profileImageUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: p?.profileImageUrl == null || p!.profileImageUrl!.isEmpty
                                      ? Text(
                                          _initials(name),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 34,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: kAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: kBackground, width: 3),
                                    ),
                                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(color: Colors.grey[500], fontSize: 13),
                          ),
                          if (p != null) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                if (p.fitnessGoal != null)
                                  _chip(Icons.flag_rounded, p.fitnessGoal!),
                                if (p.fitnessLevel != null)
                                  _chip(Icons.bar_chart_rounded, p.fitnessLevel!),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (p == null)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Could not load your profile data.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _loading = true);
                                _loadProfile();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Try again'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.grey[700]!),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      const Text(
                        'Body Stats',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _infoTile(Icons.cake_outlined, 'Age', '${p.age}'),
                          const SizedBox(width: 12),
                          _infoTile(Icons.person_outline_rounded, 'Gender', p.gender ?? '-'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _infoTile(
                            Icons.monitor_weight_outlined,
                            'Weight',
                            p.weight != null ? '${p.weight!.toStringAsFixed(1)} kg' : '-',
                          ),
                          const SizedBox(width: 12),
                          _infoTile(
                            Icons.height_rounded,
                            'Height',
                            p.height != null ? '${p.height!.toStringAsFixed(0)} cm' : '-',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _bodyWeightHistoryCard(),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _editProfile,
                          icon: const Icon(Icons.person_outline_rounded, size: 18),
                          label: const Text('Edit profile'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _updateWeight,
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Update weight'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.grey[700]!),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    const Text(
                      'Reminders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _notificationCard(),
                    const SizedBox(height: 28),
                    const Text(
                      'Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.email_outlined, color: kAccent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              user?.email ?? 'No email',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        label: const Text('Sign Out'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}