import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../auth.dart';
import 'database_service.dart';

/// Sends a one-time "welcome and thanks" email to a new user's own address.
///
/// It uses EmailJS (emailjs.com), which sends the email from your Gmail
/// without needing a server. Fill in the three values below from your EmailJS
/// dashboard. Until they are filled in, nothing is sent and nothing breaks.
class WelcomeEmailService {
  WelcomeEmailService._();
  static final instance = WelcomeEmailService._();

  // ---- Paste your three EmailJS values here ------------------------------
  static const String serviceId = 'YOUR_SERVICE_ID';
  static const String templateId = 'YOUR_TEMPLATE_ID';
  static const String publicKey = 'YOUR_PUBLIC_KEY';
  // ------------------------------------------------------------------------

  static const String _appName = 'Workout Tracker';

  // Only accounts made recently get the email, so people who signed up long
  // ago are not suddenly emailed after an update.
  static const Duration _newAccountWindow = Duration(days: 3);

  bool get _configured =>
      !serviceId.startsWith('YOUR_') &&
      !templateId.startsWith('YOUR_') &&
      !publicKey.startsWith('YOUR_');

  String _flagKey(String uid) => 'welcome_email_sent_$uid';

  Future<void> sendIfFirstTime() async {
    if (!_configured) return;
    try {
      final user = Auth().currentUser;
      final email = user?.email;
      if (user == null || email == null || email.isEmpty) return;

      final created = user.metadata.creationTime;
      if (created == null ||
          DateTime.now().difference(created) > _newAccountWindow) {
        return;
      }

      final db = DatabaseService.instance;
      if (await db.getSetting(_flagKey(user.uid)) == 'true') return;

      // Mark first so a quick restart can't send it twice.
      await db.setSetting(_flagKey(user.uid), 'true');

      final name = (user.displayName != null && user.displayName!.trim().isNotEmpty)
          ? user.displayName!.trim().split(' ').first
          : email.split('@').first;

      final response = await http
          .post(
            Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
            headers: {
              'Content-Type': 'application/json',
              'origin': 'http://localhost',
            },
            body: jsonEncode({
              'service_id': serviceId,
              'template_id': templateId,
              'user_id': publicKey,
              'template_params': {
                'to_email': email,
                'to_name': name,
                'app_name': _appName,
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('Welcome email failed: ${response.statusCode} ${response.body}');
        // Allow a retry next time the app opens.
        await db.setSetting(_flagKey(user.uid), 'false');
      }
    } catch (e) {
      debugPrint('Welcome email error: $e');
      try {
        final uid = Auth().currentUser?.uid;
        if (uid != null) {
          await DatabaseService.instance.setSetting(_flagKey(uid), 'false');
        }
      } catch (_) {}
    }
  }
}