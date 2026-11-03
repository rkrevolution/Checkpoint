#!/bin/bash
# Build the current branch (Debug) and launch it, replacing any copy this script started before.
# Extra arguments are passed to the app as launch-argument settings, e.g.:
#   scripts/run.sh -checkpointInterval 60 -jitterRange 0
# (Launch-argument settings apply to that run only; saved preferences aren't changed.)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DerivedData"
APP="$DD/Build/Products/Debug/Checkpoint.app"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

pkill -f "$APP/Contents/MacOS/Checkpoint" 2>/dev/null || true

echo "Building $(git -C "$ROOT" rev-parse --abbrev-ref HEAD) (Debug)..."
xcodebuild -project "$ROOT/Checkpoint.xcodeproj" -scheme Checkpoint -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DD" -quiet \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    CURRENT_PROJECT_VERSION="$(git -C "$ROOT" rev-list --count HEAD)" \
    build

open -n "$APP" --args "$@"
echo "Launched. Logs: log stream --predicate 'subsystem == \"com.rkrev.checkpoint\"'"
