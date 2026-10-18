#!/usr/bin/env bash
# Builds a release APK of the native HeyApp Flutter app.
#
# Prerequisites on the build machine: Flutter SDK (stable, 3.27+), JDK 17,
# Android SDK. Place your Firebase Android config at android/app/google-services.json
# (download it from the Firebase console, project "sayhi-2026").
#
#   IMAGE_API_TOKEN=... ./build_apk.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MIN_SDK=24   # firebase_core / firebase_auth require API 24 (Android 7.0)
GEN_DIR="$(mktemp -d)"
trap 'rm -rf "$GEN_DIR"' EXIT

cd "$HERE"

# 1. Generate the Android host project if it doesn't exist yet.
if [ ! -d android ]; then
  flutter create --platforms=android --org com.heyapp --project-name heyapp "$GEN_DIR/heyapp" >/dev/null
  cp -R "$GEN_DIR/heyapp/android" ./android
fi

# 2. Pin minSdk (the template uses flutter.minSdkVersion). Handles Groovy and Kotlin DSL.
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && sed -i -E "s/flutter\.minSdkVersion/$MIN_SDK/" "$f"
done

# 3. Permissions: internet, camera/mic for calls, voice input, network state.
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("android/app/src/main/AndroidManifest.xml")
xml = p.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.MODIFY_AUDIO_SETTINGS",
]
for x in perms:
    xml = re.sub(rf'\s*<uses-permission android:name="{re.escape(x)}" />', "", xml)
block = "".join(f'    <uses-permission android:name="{x}" />\n' for x in perms)
xml = xml.replace("<application", block + "    <application", 1)
p.write_text(xml)
PY

# 4. Firebase config must be present for sign-in.
if [ ! -f android/app/google-services.json ]; then
  echo "Missing android/app/google-services.json (download from Firebase console)." >&2
  exit 1
fi

# 5. Build with the image-API token passed as a compile-time define (not committed).
flutter pub get
DEFINES=()
[ -n "${IMAGE_API_TOKEN:-}" ] && DEFINES+=(--dart-define="IMAGE_API_TOKEN=$IMAGE_API_TOKEN")
[ -n "${APPLE_SERVICE_ID:-}" ] && DEFINES+=(--dart-define="APPLE_SERVICE_ID=$APPLE_SERVICE_ID")
[ -n "${APPLE_REDIRECT_URI:-}" ] && DEFINES+=(--dart-define="APPLE_REDIRECT_URI=$APPLE_REDIRECT_URI")
flutter build apk --release "${DEFINES[@]}" --target-platform android-arm,android-arm64,android-x64

echo
echo "minSdk in use:"
grep -RhoE "minSdk(Version)? *=? *[0-9]+" android/app/build.gradle* || true
echo "APK: $HERE/build/app/outputs/flutter-apk/app-release.apk"
