class UserProfile {
  final String uid;
  final String name;
  final int age;
  final String? gender;
  final double? weight;
  final double? height;
  final String? fitnessGoal;
  final String? fitnessLevel;
  final String? injuries;
  final bool onboardingCompleted;
  final String? profileImageUrl;


  final int? updatedAt;

  UserProfile({
    required this.uid,
    required this.name,
    required this.age,
    this.gender,
    this.weight,
    this.height,
    this.fitnessGoal,
    this.fitnessLevel,
    this.injuries,
    this.onboardingCompleted = false,
    this.profileImageUrl,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'age': age,
      'gender': gender,
      'weight': weight,
      'height': height,
      'fitness_goal': fitnessGoal,
      'fitness_level': fitnessLevel,
      'injuries': injuries,
      'onboarding_completed': onboardingCompleted ? 1 : 0,
      'profile_image_url': profileImageUrl,
      'updated_at': updatedAt,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String,
      name: map['name'] as String,
      age: (map['age'] as num).toInt(),
      gender: map['gender'] as String?,
      weight: (map['weight'] as num?)?.toDouble(),
      height: (map['height'] as num?)?.toDouble(),
      fitnessGoal: map['fitness_goal'] as String?,
      fitnessLevel: map['fitness_level'] as String?,
      injuries: map['injuries'] as String?,
      onboardingCompleted: map['onboarding_completed'] is bool
          ? map['onboarding_completed'] as bool
          : ((map['onboarding_completed'] as num?)?.toInt() ?? 0) == 1,
      profileImageUrl: map['profile_image_url'] as String?,
      updatedAt: (map['updated_at'] as num?)?.toInt(),
    );
  }

  UserProfile copyWith({
    String? uid,
    String? name,
    int? age,
    String? gender,
    double? weight,
    double? height,
    String? fitnessGoal,
    String? fitnessLevel,
    String? injuries,
    bool? onboardingCompleted,
    String? profileImageUrl,
    int? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      fitnessGoal: fitnessGoal ?? this.fitnessGoal,
      fitnessLevel: fitnessLevel ?? this.fitnessLevel,
      injuries: injuries ?? this.injuries,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get bmi {
    if (weight == null || height == null) return 0;
    final heightInMeters = height! / 100;
    if (heightInMeters <= 0) return 0;
    return weight! / (heightInMeters * heightInMeters);
  }
}
