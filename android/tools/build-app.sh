#!/bin/zsh
# Stages the iOS sources (stage.py) and compiles the Android app's Swift with Skip.
# Writes every distinct compiler error, relative to the staged module, to
# $PIRU_ANDROID/build/app.errors and prints the count. Extra arguments go to `skip android build`.
set -e
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
python3 "$TOOLS/stage.py"
cd "$PIRU_ANDROID/stage"
LOG="$PIRU_ANDROID/build/app.log"
set +e
skip android build --arch aarch64 --plain --ndk "$ANDROID_NDK_HOME" -Xswiftc -continue-building-after-errors "$@" > "$LOG" 2>&1
STATUS=$?
set -e
sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E '^/.*: error: ' | sed -E 's|.*/Sources/Piru/||' | sort -u > "$PIRU_ANDROID/build/app.errors" || true
echo "build status $STATUS, $(wc -l < "$PIRU_ANDROID/build/app.errors" | tr -d ' ') distinct errors"
exit $STATUS
