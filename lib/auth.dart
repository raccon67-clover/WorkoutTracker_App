import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Thrown when someone tries "Continue with Google" using an email that
/// already belongs to an email & password account in this app.
class AccountConflictException implements Exception {
  const AccountConflictException();

  static const message =
      'This email is already registered with a password. '
      'Please sign in with your email and password instead.';

  @override
  String toString() => message;
}

class Auth {
  /// Email/password accounts must click the link we email them before they
  /// can use the app. This is the ONLY way to prove an email address is real
  /// (a fake Gmail never receives the link, so it can never get in).
  static const bool requireEmailVerification = false;

  /// Set when a Google sign-in is rejected AFTER Firebase already signed the
  /// user in (the auth state flips twice, which rebuilds the login page and
  /// would otherwise lose the error). The login page shows it once.
  static String? pendingNotice;

  static String? takePendingNotice() {
    final notice = pendingNotice;
    pendingNotice = null;
    return notice;
  }

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleInitialization;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChange => _firebaseAuth.authStateChanges();

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Email/password accounts must confirm their address before using the app.
  /// Google accounts are already verified by Google.
  bool get needsEmailVerification {
    if (!requireEmailVerification) return false;
    final user = currentUser;
    if (user == null || user.emailVerified) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  Future<void> sendEmailVerification() async {
    await _firebaseAuth.currentUser?.sendEmailVerification();
  }

  /// Re-reads the account from Firebase and reports whether it is verified now.
  Future<bool> refreshEmailVerified() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = _firebaseAuth.currentUser;
    final verified = refreshed?.emailVerified ?? false;
    if (verified) {
      // Refresh the token so its "email_verified" claim is up to date.
      await refreshed?.getIdToken(true);
    }
    return verified;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      final credential = await _firebaseAuth.signInWithPopup(provider);
      await _rejectIfPasswordAccount(credential);
      return credential;
    }

    _googleInitialization ??= _googleSignIn.initialize();
    await _googleInitialization;

    final account = await _googleSignIn.authenticate();

    // Check BEFORE touching Firebase: if this email already has an
    // email/password account, don't sign in (and don't let Firebase merge).
    if (await _hasPasswordAccount(account.email)) {
      await _googleSignIn.signOut();
      throw const AccountConflictException();
    }

    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final UserCredential result;
    try {
      result = await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        await _googleSignIn.signOut();
        throw const AccountConflictException();
      }
      rethrow;
    }

    await _rejectIfPasswordAccount(result);
    return result;
  }

  /// Asks Firebase which sign-in methods exist for [email].
  ///
  /// NOTE: Firebase returns an empty list when "Email enumeration protection"
  /// is turned on in the console (Authentication > Settings > User actions).
  /// Turn it off to make this pre-check reliable. The check below
  /// ([_rejectIfPasswordAccount]) still catches the merged case either way.
  Future<bool> _hasPasswordAccount(String email) async {
    try {
      // Called dynamically so a future firebase_auth release that drops this
      // deprecated method degrades gracefully instead of breaking the build.
      final dynamic auth = _firebaseAuth;
      final methods = await auth.fetchSignInMethodsForEmail(email.trim());
      return methods is List && methods.contains('password');
    } catch (error) {
      debugPrint('Sign-in method lookup failed: $error');
      return false;
    }
  }

  /// If Firebase merged this Google sign-in into an existing email/password
  /// account, undo it and reject the sign-in.
  Future<void> _rejectIfPasswordAccount(UserCredential credential) async {
    final user = credential.user;
    if (user == null) return;

    final hasPassword = user.providerData.any((p) => p.providerId == 'password');
    if (!hasPassword) return;

    pendingNotice = AccountConflictException.message;
    try {
      await user.unlink('google.com');
    } catch (error) {
      debugPrint('Could not unlink Google from password account: $error');
    }
    await signOut();
    throw const AccountConflictException();
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (error) {
        debugPrint('Google sign-out failed: $error');
      }
    }

    await _firebaseAuth.signOut();
  }
}
