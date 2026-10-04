import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class EmailCheck {
  // Paste your Kickbox live key between the quotes.
  static const _kickboxApiKey = 'live_982554bf5bdfb4e39ac6d1a9faa33e35a7d90ef8b6c7d9979e8b0901197c93e6';

  // false = block registration if Kickbox can't be reached.
  static const _allowWhenServiceFails = false;

  static const _typoDomains = {
    'gmial.com': 'gmail.com',
    'gmai.com': 'gmail.com',
    'gamil.com': 'gmail.com',
    'gnail.com': 'gmail.com',
    'gmal.com': 'gmail.com',
    'gmail.con': 'gmail.com',
    'gmail.co': 'gmail.com',
    'gmail.cm': 'gmail.com',
    'gmaill.com': 'gmail.com',
    'yaho.com': 'yahoo.com',
    'yahooo.com': 'yahoo.com',
    'hotmial.com': 'hotmail.com',
    'hotmal.com': 'hotmail.com',
    'outlok.com': 'outlook.com',
    'outloook.com': 'outlook.com',
    'iclod.com': 'icloud.com',
  };

  /// Returns a message to show the user, or null if the address is fine.
  static Future<String?> problem(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    final at = email.lastIndexOf('@');
    if (at <= 0 || at == email.length - 1) return 'Enter a valid email address';

    final local = email.substring(0, at);
    final domain = email.substring(at + 1);

    final fix = _typoDomains[domain];
    if (fix != null) {
      return 'Did you mean $local@$fix? "$domain" looks like a typo.';
    }

    if (domain == 'gmail.com' || domain == 'googlemail.com') {
      final gmailProblem = _gmailUsernameProblem(local);
      if (gmailProblem != null) return gmailProblem;
    }

    if (!await _domainCanReceiveMail(domain)) {
      return 'The email domain "$domain" does not exist.';
    }

    if (_kickboxApiKey.startsWith('PASTE_')) {
      return 'Email checking is not set up yet. Add your Kickbox API key in '
          'lib/services/email_check.dart.';
    }

    final verdict = await _mailboxExists(email, domain);
    if (verdict == _Verdict.doesNotExist) {
      return 'That email address does not exist. Use a real, working email.';
    }
    if (verdict == _Verdict.checkFailed && !_allowWhenServiceFails) {
      return 'Could not check this email right now. Check your connection '
          'and try again.';
    }
    return null;
  }

  static Future<_Verdict> _mailboxExists(String email, String domain) async {
    try {
      final uri = Uri.https('api.kickbox.com', '/v2/verify', {
        'email': email,
        'apikey': _kickboxApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint('Kickbox ${res.statusCode}: ${res.body}');
      if (res.statusCode != 200) return _Verdict.checkFailed;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['success'] == false) return _Verdict.checkFailed;

      final result = json['result'];
      final isGmail = domain == 'gmail.com' || domain == 'googlemail.com';
      if (result == 'undeliverable') return _Verdict.doesNotExist;
      if (isGmail && result == 'unknown') return _Verdict.doesNotExist;
      return _Verdict.ok;
    } catch (e) {
      debugPrint('Kickbox check failed: $e');
      return _Verdict.checkFailed;
    }
  }

  static String? _gmailUsernameProblem(String local) {
    final name = local.split('+').first;
    const msg = 'That is not a valid Gmail address. Gmail usernames are '
        '6-30 characters: letters, numbers and dots only.';
    if (name.length < 6 || name.length > 30) return msg;
    if (!RegExp(r'^[a-z0-9.]+$').hasMatch(name)) return msg;
    if (name.startsWith('.') || name.endsWith('.') || name.contains('..')) {
      return msg;
    }
    return null;
  }

  static Future<bool> _domainCanReceiveMail(String domain) async {
    try {
      final mx = await _dns(domain, 'MX');
      if (mx == null) return true;
      if (mx.status == 3) return false;
      if (mx.hasAnswer) return true;
      final a = await _dns(domain, 'A');
      if (a == null) return true;
      return a.status != 3 && a.hasAnswer;
    } catch (_) {
      return true;
    }
  }

  static Future<({int status, bool hasAnswer})?> _dns(
      String domain, String type) async {
    final uri = Uri.https('dns.google', '/resolve', {
      'name': domain,
      'type': type,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final answers = json['Answer'];
    return (
      status: (json['Status'] as num?)?.toInt() ?? 0,
      hasAnswer: answers is List && answers.isNotEmpty,
    );
  }
}

enum _Verdict { ok, doesNotExist, checkFailed }