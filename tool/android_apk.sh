#!/usr/bin/env bash
# Builds the sideloadable Android APK and installs it on a connected device.
#
#   tool/android_apk.sh           # debug APK (default)
#   tool/android_apk.sh release   # smaller, faster; still signed with the debug key
#
# The APK ends up in app/build/app/outputs/flutter-apk/. To install by hand,
# copy it to the phone and open it (allow "Install unknown apps" once).
set -euo pipefail
cd "$(dirname "$0")/../app"

mode="${1:-debug}"
flutter build apk "--$mode"
apk="build/app/outputs/flutter-apk/app-$mode.apk"
echo "APK: app/$apk"

adb="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}/platform-tools/adb"
if [[ -x "$adb" ]] && "$adb" get-state >/dev/null 2>&1; then
  "$adb" install -r "$apk"
else
  echo "No device connected over USB debugging; install the APK by hand."
fi
