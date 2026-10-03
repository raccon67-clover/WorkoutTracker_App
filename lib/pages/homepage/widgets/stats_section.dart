import 'package:flutter/material.dart';
import '../../../main.dart' show kSurface, kAccent;
import '../../../models/user_profile.dart';

class StatsSection extends StatelessWidget {
  final UserProfile? profile;
  const StatsSection({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        Row(children: [
          Expanded(child: StatCard(icon: Icons.monitor_weight_outlined, label: 'Body weight', value: p.weight != null ? '${p.weight!.toStringAsFixed(1)} kg' : '-')),
          const SizedBox(width: 12),
          Expanded(child: StatCard(icon: Icons.height_rounded, label: 'Height', value: p.height != null ? '${p.height!.toStringAsFixed(0)} cm' : '-')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatCard(icon: Icons.flag_rounded, label: 'Goal', value: p.fitnessGoal ?? '-')),
          const SizedBox(width: 12),
          Expanded(child: StatCard(icon: Icons.bar_chart_rounded, label: 'Experience', value: p.fitnessLevel ?? '-')),
        ]),
      ]),
    );
  }
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const StatCard({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: kAccent.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: kAccent, size: 18),
        ),
        const SizedBox(height: 12),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]),
    );
  }
}
