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
