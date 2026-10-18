#!/usr/bin/env bash
# Builds a release APK of the HeyApp Flutter wrapper with the lowest
# supported Android minSdk (21 = Android 5.0 Lollipop).
#
# Requirements on the build machine: Flutter SDK (stable), JDK 17, Android SDK
# (platform-tools, build-tools, platform android-35 or whatever the Flutter
# template targets).
#
#   ./build_apk.sh            -> build/app/outputs/flutter-apk/app-release.apk
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
MIN_SDK=21
GEN_DIR="$(mktemp -d)"
trap 'rm -rf "$GEN_DIR"' EXIT

cd "$HERE"

# 1. Generate the Android host project (only if it doesn't exist yet).
if [ ! -d android ]; then
  flutter create --platforms=android --org com.heyapp --project-name heyapp "$GEN_DIR/heyapp" >/dev/null
  cp -R "$GEN_DIR/heyapp/android" ./android
fi

# 2. Pin minSdk to 21 (the template uses flutter.minSdkVersion).
#    Handles both build.gradle (Groovy) and build.gradle.kts (Kotlin DSL).
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && sed -i -E "s/flutter\.minSdkVersion/$MIN_SDK/" "$f"
done

# 3. Add the permissions the web app needs (internet, camera, mic for calls).
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
block = "".join(f'    <uses-permission android:name="{x}" />\n' for x in perms)
for x in perms:
    xml = re.sub(rf'\s*<uses-permission android:name="{re.escape(x)}" />', "", xml)
xml = xml.replace("<application", block + "    <application", 1)
p.write_text(xml)
PY

# 4. Bundle the web app from the repo root (single source of truth).
mkdir -p assets/web
cp "$REPO_ROOT/index.html" assets/web/index.html

# 5. Build.
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64,android-x64

echo
echo "minSdk in use:"
grep -RhoE "minSdk(Version)? *=? *[0-9]+" android/app/build.gradle* || true
echo "APK: $HERE/build/app/outputs/flutter-apk/app-release.apk"
