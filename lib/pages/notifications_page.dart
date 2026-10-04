import 'package:flutter/material.dart';

import '../main.dart' show kBackground, kSurface, kAccent;
import '../services/notification_coordinator.dart';

/// The list opened by the bell on the Home screen.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _inbox = NotificationInbox.instance;
  Set<String> _unreadWhenOpened = {};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    await _inbox.load();
    _unreadWhenOpened = {
      for (final i in _inbox.items)
        if (!i.read) i.id,
    };
    if (mounted) setState(() => _ready = true);
    // Opening the list counts as reading it, so the red number clears.
    await _inbox.markAllRead();
  }

  IconData _icon(String type) {
    switch (type) {
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'summary':
        return Icons.bar_chart_rounded;
      case 'test':
        return Icons.notifications_active_rounded;
      default:
        return Icons.fitness_center_rounded;
    }
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time =
        '$h12:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, $time';
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Clear all notifications?'),
        content: const Text('This removes every message from this list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    if (ok == true) await _inbox.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          AnimatedBuilder(
            animation: _inbox,
            builder: (_, __) => _inbox.items.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear all',
                    onPressed: _confirmClear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : AnimatedBuilder(
              animation: _inbox,
              builder: (_, __) {
                final items = _inbox.items;
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 54, color: Colors.grey[700]),
                          const SizedBox(height: 14),
                          const Text(
                            'No notifications yet',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Turn on workout reminders in Profile and your reminders, streak alerts and weekly summaries will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final isNew = _unreadWhenOpened.contains(n.id);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isNew
                              ? kAccent.withValues(alpha: .55)
                              : Colors.white.withValues(alpha: .05),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: kAccent.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(_icon(n.type), color: kAccent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        n.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ),
                                    if (isNew)
                                      Container(
                                        width: 9,
                                        height: 9,
                                        decoration: const BoxDecoration(
                                          color: kAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  n.body,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _when(n.time),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}