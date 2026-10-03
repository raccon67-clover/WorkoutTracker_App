import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';

/// Holds the most recently saved profile so other screens (like Home)
/// can update instantly without waiting for the database.
class ProfileNotifier {
  ProfileNotifier._();

  static final ValueNotifier<UserProfile?> current =
      ValueNotifier<UserProfile?>(null);
}