# Sourced by every android/tools script. Everything large lives under $PIRU_ANDROID, which
# defaults to the build SSD; set it to put the toolchains somewhere else.
export PIRU_ANDROID="${PIRU_ANDROID:-/Volumes/Ugreen/Projects/piru-android}"
export SWIFT_VERSION_TAG="swift-6.4.0-RELEASE"
export SQLITE_AMALGAMATION="sqlite-amalgamation-3530400"
export TOOLCHAINS=
export PATH="$PIRU_ANDROID/toolchains/$SWIFT_VERSION_TAG.xctoolchain/usr/bin:$PATH"
export ANDROID_NDK_HOME="$PIRU_ANDROID/android-ndk-r30"
export ANDROID_HOME="$PIRU_ANDROID/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="$PIRU_ANDROID/avd"
export GRADLE_USER_HOME="$PIRU_ANDROID/gradle-home"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# An emulator on another Mac: PIRU_ADB_SSH=user@host routes adb through that host's adb
# server over an SSH tunnel, so every tool here drives its emulator.
if [[ -n "${PIRU_ADB_SSH:-}" ]]; then
  export ADB_SERVER_SOCKET=tcp:localhost:5038
  pgrep -f "5038:localhost:5037" > /dev/null \
    || ssh -f -N -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -L 5038:localhost:5037 "$PIRU_ADB_SSH"
fi
