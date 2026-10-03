

class Limits {
  static const int minAge = 13;
  static const int maxAge = 100;

  static const double minWeightKg = 20;
  static const double maxWeightKg = 300;

  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;
  static const int minFeet = 3;
  static const int maxFeet = 8;
  static const int maxInches = 11;

  static const int maxSets = 100;
  static const int maxReps = 1000;
  static const int maxDurationSec = 86400;

  static const int minNameLength = 2;
  static const int maxNameLength = 50;
  static const int maxWorkoutNameLength = 60;
  static const int maxNotesLength = 500;
}

class Validators {
  static String? name(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your name';
    if (s.length < Limits.minNameLength) return 'Name is too short';
    if (s.length > Limits.maxNameLength) return 'Name is too long';
    if (!RegExp(r"^[\p{L}][\p{L} .'\-]*$", unicode: true).hasMatch(s)) {
      return 'Use letters only';
    }
    return null;
  }

  static String? age(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your age';
    final n = int.tryParse(s);
    if (n == null) return 'Enter a whole number';
    if (n < Limits.minAge) return 'You must be at least ${Limits.minAge}';
    if (n > Limits.maxAge) return 'Enter a realistic age';
    return null;
  }

  static String? weight(double? value, {required bool metric}) {
    if (value == null) return 'Enter a number';
    final kg = metric ? value : value * 0.453592;
    if (kg < Limits.minWeightKg || kg > Limits.maxWeightKg) {
      return metric
          ? 'Enter ${Limits.minWeightKg.toInt()}-${Limits.maxWeightKg.toInt()} kg'
          : 'Enter ${(Limits.minWeightKg / 0.453592).round()}-${(Limits.maxWeightKg / 0.453592).round()} lb';
    }
    return null;
  }

  static String? heightCm(double? cm) {
    if (cm == null) return 'Enter a number';
    if (cm < Limits.minHeightCm || cm > Limits.maxHeightCm) {
      return 'Enter ${Limits.minHeightCm.toInt()}-${Limits.maxHeightCm.toInt()} cm';
    }
    return null;
  }

  static String? heightFeetInches(String feetText, String inchText) {
    final ft = int.tryParse(feetText.trim());
    final inch = int.tryParse(inchText.trim().isEmpty ? '0' : inchText.trim());
    if (ft == null || inch == null) return 'Enter whole numbers';
    if (ft < Limits.minFeet || ft > Limits.maxFeet) {
      return 'Feet must be ${Limits.minFeet}-${Limits.maxFeet}';
    }
    if (inch < 0 || inch > Limits.maxInches) {
      return 'Inches must be 0-${Limits.maxInches}';
    }
    return null;
  }

  static String? sets(String? v) => _intRange(v, 1, Limits.maxSets, 'Sets');
  static String? reps(String? v) => _intRange(v, 1, Limits.maxReps, 'Reps');

  static String? duration(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n == null) return 'Whole seconds only';
    if (n < 0 || n > Limits.maxDurationSec) return 'Max 24 hours';
    return null;
  }

  static String? exerciseName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter an exercise name';
    if (s.length > Limits.maxNameLength) return 'Name is too long';
    return null;
  }

  static String? workoutName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter a workout name';
    if (s.length > Limits.maxWorkoutNameLength) return 'Name is too long';
    return null;
  }

  static String? _intRange(String? v, int min, int max, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter $label';
    final n = int.tryParse(s);
    if (n == null) return 'Whole number only';
    if (n < min || n > max) return '$min-$max';
    return null;
  }
}
