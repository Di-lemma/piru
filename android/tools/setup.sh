#!/bin/zsh
# One-time install of everything the Android build needs, under $PIRU_ANDROID: the swift.org
# toolchain (the Android SDK must match it exactly; Xcode's Swift is not accepted), the Swift
# SDK for Android, NDK r30, SQLite, and an emulator with an Android 36 arm64 image.
set -e
. "${0:A:h}/env.sh"
mkdir -p "$PIRU_ANDROID"/{downloads,toolchains,swift-sdks,avd}
cd "$PIRU_ANDROID/downloads"
fetch() { [[ -f "$2" ]] || curl -fL --progress-bar -o "$2" "$1"; }

fetch "https://download.swift.org/${SWIFT_VERSION_TAG:l}/xcode/$SWIFT_VERSION_TAG/$SWIFT_VERSION_TAG-osx.pkg" swift.pkg
fetch "https://download.swift.org/${SWIFT_VERSION_TAG:l}/android-sdk/$SWIFT_VERSION_TAG/${SWIFT_VERSION_TAG}_android.artifactbundle.tar.gz" android.artifactbundle.tar.gz
echo "21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43  android.artifactbundle.tar.gz" | shasum -a 256 -c
fetch https://dl.google.com/android/repository/android-ndk-r30-Darwin.zip ndk.zip
fetch "https://sqlite.org/2026/$SQLITE_AMALGAMATION.zip" sqlite.zip
fetch https://dl.google.com/android/repository/commandlinetools-mac-15641748_latest.zip cmdline-tools.zip

TOOLCHAIN="$PIRU_ANDROID/toolchains/$SWIFT_VERSION_TAG.xctoolchain"
if [[ ! -d "$TOOLCHAIN" ]]; then
  pkgutil --check-signature swift.pkg | grep -q 'Notarization: trusted'
  pkgutil --expand-full swift.pkg expanded
  mv expanded/*-package.pkg/Payload "$TOOLCHAIN"
  trash expanded
fi
swift sdk list --swift-sdks-path "$PIRU_ANDROID/swift-sdks" | grep -q android \
  || swift sdk install android.artifactbundle.tar.gz --swift-sdks-path "$PIRU_ANDROID/swift-sdks"
[[ -d "$ANDROID_NDK_HOME" ]] || unzip -qo ndk.zip -d "$PIRU_ANDROID"
sh "$PIRU_ANDROID/swift-sdks/${SWIFT_VERSION_TAG}_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh"
[[ -d "$SQLITE_AMALGAMATION" ]] || unzip -qo sqlite.zip
"${0:A:h}/build-sqlite.sh"

if [[ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]]; then
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -qo cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
  platform-tools emulator "system-images;android-36;google_apis;arm64-v8a" > /dev/null
echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd -n piru-spike \
  -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8 --force > /dev/null
echo "ready: $PIRU_ANDROID"
