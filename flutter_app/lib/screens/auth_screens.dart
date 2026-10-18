import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/auth.dart';
import '../services/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Decides what to show based on Firebase sign-in + Supabase profile.
/// Mirrors handleUserAuth() in index.html.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _loadedUid;
  Future<Profile?>? _profileFuture;
  Profile? _profile;
  User? _pendingUser; // signed in with Firebase but no profile yet

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authChanges,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        final user = snap.data;
        if (user == null) {
          _loadedUid = null;
          _profile = null;
          _pendingUser = null;
          return const AuthScreen();
        }
        if (_loadedUid != user.uid) {
          _loadedUid = user.uid;
          _profileFuture = _load(user);
        }
        if (_pendingUser?.uid == user.uid) {
          return UsernameScreen(
            user: user,
            onCreated: (profile) async {
              _pendingUser = null;
              await AppState.instance.startSession(profile);
              if (mounted) setState(() => _profile = profile);
            },
          );
        }
        if (_profile != null) return const HomeScreen();

        return FutureBuilder<Profile?>(
          future: _profileFuture,
          builder: (context, pSnap) {
            if (pSnap.connectionState != ConnectionState.done) return const _Splash(text: 'Signing you in…');
            if (pSnap.hasError) {
              return _ErrorRetry(
                message: 'Error loading profile — check Supabase setup.\n${pSnap.error}',
                onRetry: () => setState(() => _profileFuture = _load(user)),
              );
            }
            return const _Splash(text: 'Signing you in…');
          },
        );
      },
    );
  }

  Future<Profile?> _load(User user) async {
    final profile = await Backend.fetchProfile(user.uid);
    if (!mounted) return null;
    if (profile == null) {
      setState(() => _pendingUser = user);
      return null;
    }
    await AppState.instance.startSession(profile);
    if (mounted) setState(() => _profile = profile);
    return profile;
  }
}

class _Splash extends StatelessWidget {
  final String? text;
  const _Splash({this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppColors.accent),
          if (text != null) ...[
            const SizedBox(height: 16),
            Text(text!, style: const TextStyle(color: AppColors.textDim)),
          ],
        ]),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

/// Sign-in screen (index.html #screen-auth).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _signIn(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      final msg = explainAuthError(e);
      if (msg.isNotEmpty) showToast(msg, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _agreed && !_busy;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentDark]),
                ),
                child: const Icon(Icons.chat_bubble_rounded, size: 42, color: AppColors.onAccent),
              ),
              const SizedBox(height: 20),
              const Text('Hey App',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 8),
              const Text(
                'Connect with people around the world. Chat, share, and make meaningful connections.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agreed,
                    activeColor: AppColors.accent,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(children: [
                        const Text('I agree to the ', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TermsScreen()),
                          ),
                          child: const Text('Terms & Conditions',
                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AuthButton(
                label: 'Continue with Google',
                icon: Icons.g_mobiledata,
                background: Colors.white,
                foreground: const Color(0xFF1A1A2E),
                onPressed: enabled ? () => _signIn(AuthService.signInWithGoogle) : null,
              ),
              const SizedBox(height: 12),
              _AuthButton(
                label: 'Continue with Apple',
                icon: Icons.phone_iphone,
                background: const Color(0xFF1A1A2E),
                foreground: Colors.white,
                onPressed: enabled ? () => _signIn(AuthService.signInWithApple) : null,
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(color: AppColors.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  const _AuthButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: foreground),
        label: Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          disabledBackgroundColor: background.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Terms & Conditions text from index.html (#screen-terms).
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = <List<String>>[
    [
      '1. Acceptance of Terms',
      'By using HeyApp ("we", "us", "our"), you agree to comply with and be bound by these Terms & Conditions. If you do not agree, please do not use our platform.'
    ],
    [
      '2. User Accounts',
      'You are responsible for maintaining the confidentiality of your account credentials. You agree to provide accurate information and update it as needed. You must be at least 13 years old to use HeyApp.'
    ],
    [
      '3. User Conduct',
      'You agree to use HeyApp responsibly and not to: harass, abuse, or harm others; share illegal or harmful content; impersonate others or use false identities; engage in spam or unsolicited messaging; or violate any applicable laws or regulations.'
    ],
    [
      '4. Content Ownership',
      'You retain ownership of all content you post on HeyApp. By posting content, you grant us a license to store, display, and transmit it as necessary to provide our services.'
    ],
    [
      '5. Privacy',
      'We respect your privacy. Our Privacy Policy explains how we collect, use, and protect your data. By using HeyApp, you consent to our privacy practices.'
    ],
    [
      '6. Termination',
      'We reserve the right to suspend or terminate your account if you violate these Terms. You may delete your account at any time through your profile settings.'
    ],
    [
      '7. Limitation of Liability',
      'HeyApp is provided "as is" without warranties of any kind. We are not liable for any damages arising from your use of the platform, including but not limited to data loss, interrupted service, or interactions with other users.'
    ],
    [
      '8. Changes to Terms',
      'We may update these Terms from time to time. We will notify you of any material changes. Continued use of HeyApp constitutes acceptance of the updated Terms.'
    ],
    [
      '9. Contact',
      'For questions about these Terms, please contact us at: support@heyapp.com'
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('HeyApp Terms & Conditions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Last Updated: August 7, 2026', style: TextStyle(color: AppColors.textFaint)),
          const SizedBox(height: 16),
          for (final s in _sections) ...[
            Text(s[0], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(s[1], style: const TextStyle(color: AppColors.textDim, height: 1.5)),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('I Agree'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Username setup for new users (#screen-username).
class UsernameScreen extends StatefulWidget {
  final User user;
  final Future<void> Function(Profile profile) onCreated;

  const UsernameScreen({super.key, required this.user, required this.onCreated});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final username = _controller.text.trim().toLowerCase();
    if (username.isEmpty) return setState(() => _error = 'Please enter a username');
    if (!usernamePattern.hasMatch(username)) {
      return setState(() => _error = 'Username must be 3-20 characters (letters, numbers, underscores)');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await Backend.usernameTaken(username)) {
        setState(() => _error = 'Username already taken. Please choose another.');
        return;
      }
      final user = widget.user;
      final name = user.displayName ?? user.email?.split('@').first ?? 'User';
      final profile = await Backend.createProfile(
        id: user.uid,
        name: name,
        username: username,
        email: user.email,
      );
      showToast('Welcome to HeyApp, @$username! 🎉');
      await widget.onCreated(profile);
    } catch (_) {
      setState(() => _error = 'Failed to create account. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Choose a username',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('3-20 characters: letters, numbers and underscores.',
                  style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _continue(),
                decoration: const InputDecoration(prefixText: '@', hintText: 'username'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _continue,
                  child: Text(_busy ? 'Creating…' : 'Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
