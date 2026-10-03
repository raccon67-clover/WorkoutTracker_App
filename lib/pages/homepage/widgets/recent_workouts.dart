import 'package:flutter/material.dart';
import '../../../main.dart' show kSurface, kAccent;
import '../../../models/workout.dart';
import '../home_helpers.dart';

class RecentWorkouts extends StatelessWidget {
  final List<Workout> workouts;
  final ValueChanged<Workout> onOpen;

  const RecentWorkouts({super.key, required this.workouts, required this.onOpen});

  String _subtitle(Workout w) {
    final parts = <String>['${w.exercises.length} exercises'];
    if (w.durationSeconds > 0) {
      final m = w.durationSeconds ~/ 60;
      parts.add(m > 0 ? '${m}m' : '${w.durationSeconds}s');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final recent = workouts.take(3).toList();
    if (recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(Icons.fitness_center_rounded, color: Colors.grey[700], size: 34),
            const SizedBox(height: 10),
            Text(
              'No workouts yet.\nLog your first one and it will show up here!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], height: 1.4),
            ),
          ],
        ),
      );
    }

    return Column(
      children: recent
          .map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onOpen(w),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: .05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 56,
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${w.date.day}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              monthShort[w.date.month - 1].toUpperCase(),
                              style: const TextStyle(
                                color: kAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _subtitle(w),
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey[600]),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}