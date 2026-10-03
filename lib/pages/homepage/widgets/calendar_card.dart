import 'package:flutter/material.dart';
import '../../../main.dart' show kSurface, kAccent;
import '../../../models/workout.dart';
import '../home_helpers.dart';

class CalendarCard extends StatefulWidget {
  final Map<DateTime, List<Workout>> byDay;
  final ValueChanged<Workout> onOpenWorkout;

  const CalendarCard({super.key, required this.byDay, required this.onOpenWorkout});

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  static const int _collapsedCount = 2;

  late DateTime _month;
  DateTime? _selected;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime.utc(now.year, now.month, 1);
    _selected = dayOnly(now);
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime.utc(_month.year, _month.month + delta, 1);
    });
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .06),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _workoutTile(Workout w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onOpenWorkout(w),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: kAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  w.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final daysInMonth = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final leading = _month.weekday - 1;
    final rows = ((leading + daysInMonth) / 7).ceil();
    final selectedWorkouts = _selected == null
        ? <Workout>[]
        : (widget.byDay[_selected] ?? <Workout>[]);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _navButton(Icons.chevron_left_rounded, () => _changeMonth(-1)),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      monthNames[_month.month - 1],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_month.year}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              _navButton(Icons.chevron_right_rounded, () => _changeMonth(1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          Column(
            children: List.generate(rows, (r) {
              return Row(
                children: List.generate(7, (c) {
                  final dayNum = r * 7 + c - leading + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 46));
                  }

                  final date = DateTime.utc(_month.year, _month.month, dayNum);
                  final hasWorkout = widget.byDay.containsKey(date);
                  final isToday = date == today;
                  final isSelected = _selected == date;

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _selected = date;
                        _expanded = false;
                      }),
                      child: Container(
                        height: 42,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kAccent
                              : (hasWorkout
                                  ? kAccent.withValues(alpha: .14)
                                  : Colors.transparent),
                          borderRadius: BorderRadius.circular(14),
                          border: (isToday && !isSelected)
                              ? Border.all(color: kAccent, width: 1.5)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNum',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (hasWorkout ? Colors.white : Colors.grey[400]),
                                fontWeight: (isToday || isSelected || hasWorkout)
                                    ? FontWeight.w800
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasWorkout
                                    ? (isSelected ? Colors.white : kAccent)
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
          if (_selected != null) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: .08), height: 1),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  formatShort(_selected!),
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (selectedWorkouts.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Rest day. No workouts logged.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              )
            else ...[
              if (_expanded)
                // Expanded: scrolls inside a fixed-height box so the page never gets long.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: selectedWorkouts.map(_workoutTile).toList(),
                  ),
                )
              else
                ...selectedWorkouts.take(_collapsedCount).map(_workoutTile),
              if (selectedWorkouts.length > _collapsedCount)
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _expanded
                          ? 'Show less'
                          : 'Show ${selectedWorkouts.length - _collapsedCount} more',
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}