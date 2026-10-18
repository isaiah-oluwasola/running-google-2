import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config.dart';

/// Firebase Auth with Google / Apple, same Firebase project as index.html.
class AuthService {
  AuthService._();

  static final FirebaseAuth _fa = FirebaseAuth.instance;

  static Stream<User?> get authChanges => _fa.authStateChanges();
  static User? get currentUser => _fa.currentUser;

  static Future<UserCredential> signInWithGoogle() async {
    final google = GoogleSignIn(scopes: const ['email']);
    await google.signOut(); // always show the account picker (prompt: select_account)
    final account = await google.signIn();
    if (account == null) throw const AuthCancelled();
    final auth = await account.authentication;
    return _fa.signInWithCredential(GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    ));
  }

  static Future<UserCredential> signInWithApple() async {
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      webAuthenticationOptions: Platform.isAndroid
          ? WebAuthenticationOptions(
              clientId: AppConfig.appleServiceId,
              redirectUri: Uri.parse(AppConfig.appleRedirectUri),
            )
          : null,
    );
    final credential = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      accessToken: apple.authorizationCode,
    );
    final result = await _fa.signInWithCredential(credential);
    final user = result.user;
    if (user != null && (user.displayName ?? '').isEmpty && apple.givenName != null) {
      await user.updateDisplayName('${apple.givenName} ${apple.familyName ?? ''}'.trim());
    }
    return result;
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _fa.signOut();
  }
}

class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// Turns Firebase error codes into the same messages index.html shows.
String explainAuthError(Object error) {
  if (error is AuthCancelled) return '';
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      case 'configuration-not-found':
        return "Sign-in isn't enabled for this Firebase project yet. Enable the provider in the Firebase console.";
      case 'network-request-failed':
        return 'Network error reaching Firebase — check your internet connection.';
      default:
        return error.message ?? 'Sign-in failed for an unknown reason.';
    }
  }
  return 'Sign-in failed: $error';
}
