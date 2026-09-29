#!/bin/zsh
# Packages the Android Swift that build-app.sh compiled into an APK (PIRU_CONFIG=release for
# the release APK, debug otherwise), and installs it on the running emulator when one is
# attached. Prints the APK path.
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
    gradle "assemble${(C)${PIRU_CONFIG:-debug}}" --console=plain > "$LOG" 2>&1 || { grep -E '^e: |What went wrong' -A4 "$LOG" | head -40; exit 1; }
CONFIG="${PIRU_CONFIG:-debug}"
APK="$PIRU_ANDROID/stage/.build/Android/app/outputs/apk/$CONFIG/app-$CONFIG.apk"
echo "$APK"
if adb get-state > /dev/null 2>&1; then
    adb install -r "$APK" > /dev/null && echo "installed on $(adb get-serialno)"
fi
