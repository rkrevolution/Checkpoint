#!/bin/bash
# Build a Release copy and install it to /Applications (replacing any existing Checkpoint.app),
# then launch it. Use this copy for everyday use and "Start at Login".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DerivedData"
BUILT="$DD/Build/Products/Release/Checkpoint.app"
DEST="/Applications/Checkpoint.app"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "Building Release..."
xcodebuild -project "$ROOT/Checkpoint.xcodeproj" -scheme Checkpoint -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DD" -quiet \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    CURRENT_PROJECT_VERSION="$(git -C "$ROOT" rev-list --count HEAD)" \
    build

if pgrep -f "$DEST/Contents/MacOS/Checkpoint" >/dev/null; then
    echo "Quitting the installed copy..."
    osascript -e 'tell application id "RkRev.Checkpoint" to quit' 2>/dev/null || true
    sleep 2
fi

rm -rf "$DEST"
ditto "$BUILT" "$DEST"
open "$DEST"
echo "Installed $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString) ($(defaults read "$DEST/Contents/Info" CFBundleVersion)) to $DEST"
