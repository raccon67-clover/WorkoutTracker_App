import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../models/workout.dart';

class Suggestion {
  final String title;
  final String reason;
  final IconData icon;
  final List<String> exercises;

  const Suggestion({
    required this.title,
    required this.reason,
    required this.icon,
    required this.exercises,
  });
}

Suggestion suggest(String title, String reason) {
  switch (title) {
    case 'Push Day':
      return Suggestion(
        title: title,
        reason: reason,
        icon: Icons.fitness_center_rounded,
        exercises: const ['Bench Press', 'Overhead Press', 'Incline Dumbbell Press', 'Tricep Pushdown'],
      );
    case 'Pull Day':
      return Suggestion(
        title: title,
        reason: reason,
        icon: Icons.rowing_rounded,
        exercises: const ['Deadlift', 'Pull-Up', 'Barbell Row', 'Bicep Curl'],
      );
    case 'Leg Day':
      return Suggestion(
        title: title,
        reason: reason,
        icon: Icons.directions_run_rounded,
        exercises: const ['Squat', 'Romanian Deadlift', 'Leg Press', 'Calf Raise'],
      );
    case 'Upper Body':
      return Suggestion(
        title: title,
        reason: reason,
        icon: Icons.sports_gymnastics_rounded,
        exercises: const ['Bench Press', 'Pull-Up', 'Overhead Press', 'Bicep Curl'],
      );
    case 'Cardio & Core':
      return Suggestion(
        title: title,
        reason: reason,
        icon: Icons.favorite_rounded,
        exercises: const ['Running', 'Jump Rope', 'Plank', 'Crunches'],
      );
    default:
      return Suggestion(
        title: 'Full Body',
        reason: reason,
        icon: Icons.accessibility_new_rounded,
        exercises: const ['Squat', 'Bench Press', 'Barbell Row', 'Plank'],
      );
  }
}

bool _mentions(String text, List<String> words) =>
    words.any((w) => text.contains(w));


Suggestion buildSuggestion({
  UserProfile? profile,
  required List<Workout> workouts,
}) {
  final last = workouts.isNotEmpty ? workouts.first.name.toLowerCase() : '';
  final wasPush = _mentions(last, ['push', 'chest', 'shoulder', 'tricep']);
  final wasPull = _mentions(last, ['pull', 'back', 'bicep']);
  final wasLegs = _mentions(last, ['leg', 'squat', 'glute']);

  switch (profile?.fitnessGoal) {
    case 'Build Muscle':
      if (wasPush) {
        return suggest('Pull Day', 'Next up in your push, pull, legs split');
      }
      if (wasPull) {
        return suggest('Leg Day', 'Next up in your push, pull, legs split');
      }
      if (wasLegs) {
        return suggest('Push Day', 'Back to the start of your split');
      }
      return suggest('Push Day', 'A great starting point for building muscle');
    case 'Lose Weight':
      if (last.contains('cardio')) {
        return suggest('Full Body', 'Strength training keeps your metabolism up');
      }
      return suggest('Cardio & Core', 'Great for burning calories');
    case 'Improve Endurance':
      return suggest('Cardio & Core', 'Builds stamina and a strong core');
    case 'Stay Fit':
      if (last.contains('full')) {
        return suggest('Upper Body', 'Mixing it up keeps things fresh');
      }
      return suggest('Full Body', 'Hits every major muscle group');
    default:
      return suggest('Full Body', 'Hits every major muscle group');
  }
}
