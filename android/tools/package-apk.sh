#!/bin/zsh
# Packages the Android Swift that build-app.sh compiled into a debug APK, and installs it on
# the running emulator when one is attached. Prints the APK path.
set -e
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
# The app depends on the included skipstone build's Piru project, which packages
# <its build dir>/jni-libs; build-app.sh compiled into the root build's copy.
INCLUDED="$PIRU_ANDROID/stage/.build/plugins/outputs/stage/Piru/destination/skipstone/Piru/build"
mkdir -p "$INCLUDED"
ln -sfn "$PIRU_ANDROID/stage/.build/Android/Piru/jni-libs" "$INCLUDED/jni-libs"
cd "$PIRU_ANDROID/stage/Android"
LOG="$PIRU_ANDROID/build/gradle.log"
SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 SKIP_BRIDGE_ROBOLECTRIC_BUILD_DISABLED=1 \
    gradle assembleDebug --console=plain > "$LOG" 2>&1 || { grep -E '^e: |What went wrong' -A4 "$LOG" | head -40; exit 1; }
APK="$PIRU_ANDROID/stage/.build/Android/app/outputs/apk/debug/app-debug.apk"
echo "$APK"
if adb get-state > /dev/null 2>&1; then
    adb install -r "$APK" > /dev/null && echo "installed on $(adb get-serialno)"
fi
