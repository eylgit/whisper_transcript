#!/bin/bash
# Runs the unit tests.
#
# Building the app needs only the Command Line Tools, but XCTest ships with
# Xcode, so the tests do need it. This finds a toolchain that has XCTest
# without changing your global `xcode-select` setting.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCTEST_REL="Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"

find_developer_dir() {
    local current
    current="$(xcode-select -p 2>/dev/null || true)"
    if [ -n "$current" ] && [ -d "$current/$XCTEST_REL" ]; then
        echo "$current"; return 0
    fi
    for app in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
        [ -d "$app/Contents/Developer/$XCTEST_REL" ] && { echo "$app/Contents/Developer"; return 0; }
    done
    return 1
}

if ! DEVELOPER_DIR="$(find_developer_dir)"; then
    cat >&2 <<'MSG'
error: could not find XCTest.

Building Transcribe needs only the Xcode Command Line Tools, but the tests are
written against XCTest, which is only distributed inside Xcode itself. Install
Xcode from the App Store and re-run; nothing else about the project changes.
MSG
    exit 1
fi
export DEVELOPER_DIR
echo "==> toolchain: $DEVELOPER_DIR"

# A separate scratch path from `swift build`. The two toolchains produce
# incompatible object files, and sharing .build makes the linker fail with a
# confusing missing-main-symbol error.
exec swift test --package-path "$ROOT" --scratch-path "$ROOT/.build-test" "$@"
