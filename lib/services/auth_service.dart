import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Which login field an error should be shown against.
enum AuthField { email, password, general }

/// A login/signup error mapped to the field it belongs to.
class AuthError {
  final AuthField field;
  final String message;
  const AuthError(this.field, this.message);
}

/// Handles real accounts with **email + password**.
///
/// Sign up creates an account, stores a display name (shown next to messages),
/// and saves a `users/{uid}` profile doc. Log in signs an existing account back
/// in. The account is the user's own and works on any phone.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  /// Web/server OAuth client id (from google-services.json) used to obtain an
  /// ID token that Firebase will accept for Google sign-in.
  static const _googleServerClientId =
      '958305310400-iu1a1le283u4b5jvoks0sht3agk5s3h9.apps.googleusercontent.com';
  static bool _googleReady = false;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authState() => _auth.authStateChanges();

  String get displayName => _auth.currentUser?.displayName ?? 'Anonymous';

  /// The signed-in user's chosen avatar emoji (stored in the Firebase Auth
  /// photoURL so it's available synchronously, like [displayName]). Null if they
  /// haven't picked one (or it's an old Google photo URL).
  String? get myAvatar => _auth.currentUser?.photoURL;

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Whether the signed-in user must verify their email before using the app.
  /// True only for email/password accounts that haven't verified yet — Google
  /// sign-in accounts are already verified by Google, so they're never gated.
  bool get needsEmailVerification {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  String? get email => _auth.currentUser?.email;

  /// Sends (or re-sends) the email-verification link to the current user.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Reloads the user so [isEmailVerified] reflects the latest server state.
  Future<void> reloadUser() => _auth.currentUser?.reload() ?? Future.value();

  /// Creates a new account, sets the display name, saves the profile, and
  /// sends an email-verification link.
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    String? avatar,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(name.trim());
    if (avatar != null && avatar.isNotEmpty) {
      await user.updatePhotoURL(avatar);
    }
    await _db.collection('users').doc(user.uid).set({
      'displayName': name.trim(),
      'email': email.trim(),
      if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // Send the verification email (non-blocking for the user's first session).
    try {
      await user.sendEmailVerification();
    } catch (_) {/* ignore — they can resend from the banner */}
    // Make sure currentUser.displayName is populated for the first screen.
    await user.reload();
  }

  /// Changes the signed-in user's avatar emoji. Updates both the Firebase Auth
  /// photoURL (so it's available synchronously) and the Firestore profile.
  Future<void> updateAvatar(String avatar) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updatePhotoURL(avatar);
    await _db.collection('users').doc(user.uid).set(
      {'avatar': avatar},
      SetOptions(merge: true),
    );
    await user.reload();
  }

  /// Changes the display name shown next to the user's messages. Updates both
  /// the Firebase Auth profile and the Firestore profile doc. (Messages already
  /// sent keep the old name, since it's denormalized onto each one.)
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final trimmed = name.trim();
    await user.updateDisplayName(trimmed);
    await _db.collection('users').doc(user.uid).set(
      {'displayName': trimmed},
      SetOptions(merge: true),
    );
    await user.reload();
  }

  /// Logs an existing account in.
  Future<void> logIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sends a "reset your password" email to [email].
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Whether the signed-in user logs in with an email + password (so they have
  /// a password to change). Google-only accounts don't.
  bool get hasPasswordProvider =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  /// Changes the signed-in user's password. Firebase requires a recent login,
  /// so we re-authenticate with the current password first.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(
          code: 'no-user', message: 'You are not signed in.');
    }
    final cred = EmailAuthProvider.credential(
        email: user.email!, password: currentPassword);
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  /// Signs in with Google. Returns false if the user cancelled the chooser.
  /// Throws on real failures.
  Future<bool> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: _googleServerClientId);
      _googleReady = true;
    }
    GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
          code: 'no-id-token', message: 'Google sign-in did not return a token.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user!;
    // Save / merge a profile doc (display name shown next to messages).
    await _db.collection('users').doc(user.uid).set({
      'displayName': user.displayName ?? 'Anonymous',
      'email': user.email,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {/* not signed in with Google */}
    await _auth.signOut();
  }

  /// Classifies a login/signup error to the field it belongs to, so the UI can
  /// highlight the email field for email problems and the password field for
  /// password problems (instead of always blaming the password).
  static AuthError classifyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
        case 'user-not-found':
          return const AuthError(
              AuthField.email, 'Incorrect email address.');
        case 'email-already-in-use':
          return const AuthError(AuthField.email,
              'An account with this email already exists. Try logging in.');
        case 'wrong-password':
          return const AuthError(AuthField.password, 'Incorrect password.');
        case 'invalid-credential':
          // With email-enumeration protection, Firebase returns this for both
          // a wrong email and a wrong password. The email format is already
          // validated client-side, so we point at the password.
          return const AuthError(AuthField.password, 'Incorrect password.');
        case 'weak-password':
          return const AuthError(AuthField.password,
              'Password is too weak — use at least 6 characters.');
        case 'network-request-failed':
          return const AuthError(AuthField.general,
              'No internet connection. Check your network.');
        case 'too-many-requests':
          return const AuthError(AuthField.general,
              'Too many attempts. Wait a moment and try again.');
      }
    }
    return const AuthError(
        AuthField.general, 'Something went wrong. Please try again.');
  }

  /// Turns Firebase's error codes into friendly messages.
  static String friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'That email address doesn\'t look right.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Try logging in.';
        case 'weak-password':
          return 'Password is too weak — use at least 6 characters.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Wrong email or password.';
        case 'network-request-failed':
          return 'No internet connection. Check your network.';
        case 'too-many-requests':
          return 'Too many attempts. Wait a moment and try again.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
