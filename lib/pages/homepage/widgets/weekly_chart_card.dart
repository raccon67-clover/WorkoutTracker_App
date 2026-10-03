import 'package:flutter/material.dart';
import '../../../main.dart' show kSurface, kAccent;
import '../home_helpers.dart';

class WeeklyChartCard extends StatelessWidget {
  final List<int> values;
  const WeeklyChartCard({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final maxV = values.fold<int>(0, (m, v) => v > m ? v : m);
    final total = values.fold<int>(0, (s, v) => s + v);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'sets completed',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Last 7 days',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final date = today.subtract(Duration(days: 6 - i));
                final v = values[i];
                final isToday = i == 6;
                final fill = (v == 0 || maxV == 0) ? 0.0 : 10.0 + (v / maxV) * 90.0;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        v > 0 ? '$v' : '',
                        style: TextStyle(
                          color: isToday ? Colors.white : Colors.grey[400],
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 24,
                        height: 100,
                        alignment: Alignment.bottomCenter,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: fill),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, h, _) {
                            return Container(
                              width: 24,
                              height: h,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? kAccent
                                    : kAccent.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        weekdayShort[date.weekday - 1],
                        style: TextStyle(
                          color: isToday ? Colors.white : Colors.grey[600],
                          fontSize: 11,
                          fontWeight:
                              isToday ? FontWeight.w800 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}