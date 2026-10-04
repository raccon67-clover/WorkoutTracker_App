import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../main.dart' show kAccent;
import '../../../models/user_profile.dart';
import '../../../services/notification_coordinator.dart';
import '../../../widgets/user_avatar.dart';
import '../home_helpers.dart';

class HomeHeader extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onAvatarTap;
  final VoidCallback? onBellTap;

  const HomeHeader({
    super.key,
    required this.profile,
    required this.onAvatarTap,
    this.onBellTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? Auth().currentUser?.displayName ?? 'Athlete';
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final dateLabel =
        '${weekdayShort[now.weekday - 1]}, ${now.day} ${monthShort[now.month - 1]}';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel.toUpperCase(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$greeting,',
                style: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        _NotificationBell(onTap: onBellTap),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onAvatarTap,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [kAccent, Color(0xFFB71C1C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .15), width: 2),
              boxShadow: [
                BoxShadow(
                  color: kAccent.withValues(alpha: .35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: UserAvatar(
              imageUrl: profile?.profileImageUrl,
              name: name,
              size: 50,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final VoidCallback? onTap;

  const _NotificationBell({this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationInbox.instance.unreadCount,
      builder: (context, count, _) {
        final label = count > 9 ? '9+' : '$count';
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                  child: Icon(
                    count > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF121212),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}