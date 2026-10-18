# HeyApp — native Flutter Android app

A native Flutter port of `../index.html`. It uses the same Supabase project (tables
`profiles`, `messages`, `groups`, `group_members`), the same Firebase project
(`sayhi-2026`) for sign-in, and the same realtime channels, so existing users and data
carry over and web and app users can message and call each other.

## What's ported

| index.html feature | Flutter |
|---|---|
| Google / Apple sign-in (Firebase) | `services/auth.dart` (google_sign_in, sign_in_with_apple) |
| Username setup for new users | `screens/auth_screens.dart` (`UsernameScreen`) |
| Chats list (DMs + groups), unread badges | `screens/home_screen.dart` (`ChatsTab`) |
| 1:1 and group chat, realtime delivery | `screens/chat_screen.dart`, `services/realtime.dart` |
| Typing indicator (DM) | `chat_screen.dart` (broadcast `typing-<a>-<b>`) |
| Read receipts | `Backend.markRead` |
| Reactions (long-press) | `chat_screen.dart` (`messages.reaction`) |
| Translate messages | `services/ai.dart` + Settings → Translate messages |
| Voice input | `chat_screen.dart` (speech_to_text) |
| Image messages (data URLs) | `models.dart` (`Message.imageBytes`) |
| Search users, start chat | `screens/home_screen.dart` (`SearchTab`) |
| Create / name / info / add members / leave group | `screens/group_screens.dart` |
| Audio & video calls (WebRTC), busy/reject/cancel, mid-call video upgrade, camera flip, mute, speaker | `services/calls.dart`, `widgets/call_overlay.dart` |
| AI image generation | `screens/generate_screen.dart`, `services/ai.dart` |
| Settings: edit name, theme, translation language, terms, logout | `screens/home_screen.dart` (`SettingsTab`) |
| Terms & Conditions | `screens/auth_screens.dart` (`TermsScreen`) |

Preferences use the same keys as the web app (`sayhi_theme`, `sayhi_translate_lang`).

## Not ported (because the web app never ran them)

- **Smart replies, tone check, summarizer:** these call `puter.ai`, but `index.html`
  never loads the Puter SDK, so these features were always disabled. They are left out.
- **File upload:** the web app shows "coming soon", so it isn't implemented.
- **Group calls:** the web app shows "coming soon", so it isn't implemented.

## Build

Requirements: Flutter 3.27+ (stable), JDK 17, Android SDK.

1. In the Firebase console (project `sayhi-2026`), add an Android app with package name
   `com.heyapp.heyapp`, then download `google-services.json` into
   `flutter_app/android/app/` **after** the first `flutter create` (the build script
   creates `android/` for you; run it once, then copy the file and run again).
   Add your debug and release **SHA-1** fingerprints to that Android app, or Google
   sign-in will fail.
2. Run:
   ```bash
   cd flutter_app
   IMAGE_API_TOKEN=... ./build_apk.sh
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`

`minSdk` is **24 (Android 7.0)**. `firebase_core` 5.x and `firebase_auth` 7.x require it.
Going lower would mean dropping Firebase Auth, which would change every user's ID and
break existing accounts.

## Configuration

- `IMAGE_API_TOKEN` is passed at build time (`--dart-define`) and is not in the source.
  The web app still hard-codes the same token in `index.html`, so **rotate that token**.
- Sign in with Apple on Android needs `APPLE_SERVICE_ID` and `APPLE_REDIRECT_URI`
  (an Apple "Service ID" with a web redirect). Without them, Apple sign-in fails on Android.
- Supabase: the app uses the same anon key and the same tables as the web app. Row
  Level Security must allow what the app does (the web app relies on the same policies).

## Known limitations / things to test

- **Not compiled in the authoring environment.** The sandbox used to write this could not
  reach the Flutter, Dart or pub.dev servers, so it has not been run or analysed. Run
  `flutter analyze` and test on a device before release.
- Generated images are shared through a chat picker (the web app shared to the open chat).
- Realtime and call signalling use the same Supabase broadcast channels as the web app,
  so the protocol is compatible, but calls across networks still need TURN for some
  networks (only public STUN servers are configured, as in the web app).
