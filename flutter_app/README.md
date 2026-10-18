# HeyApp — Flutter Android wrapper

This folder wraps the web app in `../index.html` in a Flutter app and builds an
Android APK.

## Build

On a machine with the Flutter SDK (stable), JDK 17 and the Android SDK:

```bash
cd flutter_app
chmod +x build_apk.sh
./build_apk.sh
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

The script:

1. Generates the Android host project on first run (`flutter create`).
2. Sets `minSdk = 21` (Android 5.0). That is the lowest API level Flutter
   supports, so this is the smallest SDK the app can target.
3. Adds the internet, camera and microphone permissions.
4. Copies `../index.html` into `assets/web/` (the copy is git-ignored, so
   `index.html` stays the only source of truth).
5. Runs `flutter build apk --release` for arm, arm64 and x86_64.

## Important limitations

- **Not verified in this sandbox.** The build environment here cannot reach the
  Flutter, Dart, Android SDK, Gradle or pub.dev servers, so the APK was not built
  or run. Run `build_apk.sh` on your own machine and test on a device.
- **Google / Apple sign-in** uses `signInWithPopup` / `signInWithRedirect`.
  Embedded WebViews generally block these OAuth flows, so login will likely fail
  inside the app. The usual fix is a native sign-in (`google_sign_in` /
  `sign_in_with_apple`) that passes the resulting Firebase credential to the
  web app.
- **Older Android = older WebView.** Android 5.x uses an updatable system
  WebView. The web app uses modern JavaScript (Supabase, Firebase SDK v10), so
  devices on very old WebView versions may fail to run it. Raising `minSdk`
  (e.g. to 24) improves compatibility at the cost of older devices.
- **Package name** is `com.heyapp.heyapp`. Change `--org` in `build_apk.sh` if you
  need a different one.
- Web app features depending on browser APIs (speech recognition, the
  translation and AI endpoints) depend on what the device's WebView supports.
