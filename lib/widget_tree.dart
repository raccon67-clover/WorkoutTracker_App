import 'package:flutter/material.dart';
import 'package:workout_app/auth.dart';
import 'package:workout_app/pages/home_page.dart';
import 'package:workout_app/pages/login_register_page.dart';
import 'package:workout_app/pages/onboarding_page.dart';
import 'package:workout_app/models/user_profile.dart';
import 'package:workout_app/services/database_service.dart';
import 'main.dart' show kBackground, kAccent;

class WidgetTree extends StatefulWidget {
  const WidgetTree({super.key});

  @override
  State<WidgetTree> createState() => _WidgetTreeState();
}

class _WidgetTreeState extends State<WidgetTree> {
  String? _profileUid;
  Future<UserProfile?>? _profileFuture;

  bool _isProfileComplete(UserProfile profile) {
    return profile.age > 0 &&
        profile.gender?.trim().isNotEmpty == true &&
        profile.weight != null &&
        profile.height != null &&
        profile.fitnessGoal?.trim().isNotEmpty == true &&
        profile.fitnessLevel?.trim().isNotEmpty == true;
  }

  Future<UserProfile?> _loadProfileFor(String uid) {
    return DatabaseService.instance.getUserProfile(uid);
  }

  Future<UserProfile?> _profileFor(String uid) {
    if (_profileUid != uid || _profileFuture == null) {
      _profileUid = uid;
      _profileFuture = _loadProfileFor(uid);
    }
    return _profileFuture!;
  }

  void _resetProfileCache() {
    _profileUid = null;
    _profileFuture = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Auth().authStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = snapshot.data;

        if (user == null) {
          _resetProfileCache();
          return const LoginPage();
        }

        if (_profileUid != user.uid) {
          _profileUid = user.uid;
          _profileFuture = _loadProfileFor(user.uid);
        }

        return FutureBuilder<UserProfile?>(
          future: _profileFuture,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            if (profileSnapshot.hasError) {
              return const _LoadingScreen();
            }

            final profile = profileSnapshot.data;

            if (profile != null && _isProfileComplete(profile)) {
              return const HomePage();
            }

            return OnboardingPage(
              key: ValueKey('onboarding-${user.uid}'),
              uid: user.uid,
              name: profile?.name.trim().isNotEmpty == true
                  ? profile!.name
                  : user.displayName?.trim().isNotEmpty == true
                      ? user.displayName!
                      : 'there',
            );
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBackground,
      body: Center(
        child: CircularProgressIndicator(color: kAccent),
      ),
    );
  }
}
