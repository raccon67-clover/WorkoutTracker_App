import 'package:flutter/material.dart';
import '../../../main.dart' show kSurface;

const List<String> tips = [
  'Drink water before, during and after your workout to stay hydrated.',
  'Sleep is when your muscles recover. Aim for 7 to 9 hours.',
  'Warm up for 5 to 10 minutes to lower your risk of injury.',
  'Progressive overload: add a little weight or a rep each week.',
  'Protein at every meal helps your muscles repair and grow.',
  'Rest days are part of the plan, not a break from it.',
  'Consistency beats intensity. Show up even on low-energy days.',
];

class TipCard extends StatelessWidget {
  const TipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final tip = tips[dayOfYear % tips.length];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: .18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tip of the day',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}