#!/bin/bash
# End-to-end test: builds a Debug copy of Checkpoint, launches it with throwaway
# settings, drives it through Debug-only commands, and checks its log.
#
#   scripts/e2e.sh            full run (~3–4 min: includes snooze and scheduled-fire waits)
#   scripts/e2e.sh --quick    skip the scenarios that wait on real timers (~30 s)
#
# Settings are passed as launch arguments (argument domain), so your saved
# preferences are never changed. Screensaver and lock are simulated inside the
# app only; no real system notifications are broadcast.
set -uo pipefail

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/checkpoint-e2e.XXXXXX")"
LOG="$WORK/app.log"
APP="$WORK/dd/Build/Products/Debug/Checkpoint.app"
BIN="$APP/Contents/MacOS/Checkpoint"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

PASS=0
FAIL=0
APP_PID=""
LOG_PID=""

cleanup() {
    [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null
    [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT

if pgrep -f "Checkpoint.app/Contents/MacOS/Checkpoint" >/dev/null; then
    echo "Checkpoint is already running. Quit it first (it would react to the test commands too)."
    exit 2
fi

echo "Building Debug copy..."
if ! xcodebuild -project "$ROOT/Checkpoint.xcodeproj" -scheme Checkpoint -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$WORK/dd" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build >"$WORK/build.log" 2>&1; then
    tail -30 "$WORK/build.log"
    echo "Build failed (full log: $WORK/build.log)"
    exit 1
fi
if ! swiftc -O "$ROOT/scripts/e2e-send.swift" -o "$WORK/e2e-send" 2>"$WORK/send-build.log"; then
    cat "$WORK/send-build.log"; exit 1
fi

# --- helpers -----------------------------------------------------------------

send() {  # send <command>: post a Debug-only command to the app
    "$WORK/e2e-send" "com.rkrev.checkpoint.debug.$1"
}

mark() { MARK=$(wc -l <"$LOG"); }  # only log lines after the mark count

expect() {  # expect <description> <pattern> [timeout seconds]
    local desc="$1" pattern="$2" timeout="${3:-5}" waited=0
    while (( waited < timeout * 2 )); do
        if tail -n +"$((MARK + 1))" "$LOG" | grep -qF -- "$pattern"; then
            echo "  ✓ $desc"; PASS=$((PASS + 1)); return 0
        fi
        sleep 0.5; waited=$((waited + 1))
    done
    echo "  ✗ $desc (no \"$pattern\" within ${timeout}s)"; FAIL=$((FAIL + 1)); return 1
}

expect_absent() {  # expect_absent <description> <pattern> <seconds>
    local desc="$1" pattern="$2"
    sleep "$3"
    if tail -n +"$((MARK + 1))" "$LOG" | grep -qF -- "$pattern"; then
        echo "  ✗ $desc (unexpected \"$pattern\")"; FAIL=$((FAIL + 1)); return 1
    fi
    echo "  ✓ $desc"; PASS=$((PASS + 1))
}

launch() {  # launch <interval seconds>
    : >"$LOG"
    MARK=0
    log stream --style compact --level debug \
        --predicate 'subsystem == "com.rkrev.checkpoint"' >>"$LOG" 2>&1 &
    LOG_PID=$!
    sleep 1
    "$BIN" -checkpointInterval "$1" -jitterRange 0 -hasLaunchedBefore YES \
        -playSoundOnCheckpoint NO -logResponses NO -fullScreenCheckpoint YES \
        -snoozeMinutes 1 -maxSnoozesPerCheckpoint 3 -respectFocusMode YES \
        -useActiveHours NO -checkpointsEnabled YES >/dev/null 2>&1 &
    APP_PID=$!
    expect "app launches and starts its timer" "TIMER STARTING" 15
}

quit_app() {
    kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null; APP_PID=""
    kill "$LOG_PID" 2>/dev/null; wait "$LOG_PID" 2>/dev/null; LOG_PID=""
}

check_in() {  # open a card via manual check-in
    mark; send checkInNow
    expect "checkpoint fires" "CHECKPOINT FIRING" && expect "card is on screen" "Modal window visible"
}

# --- scenarios (long interval so the regular timer stays out of the way) ------

launch 3600

echo "Manual check-in"
check_in
mark; send acknowledge
expect "Got it completes the checkpoint" "CHECKPOINT COMPLETED"

echo "Screensaver while a card is open"
check_in
mark; send screensaverStart
expect "app goes away" "AWAY: screensaver"
expect "open card and overlays are dismissed" "Dismissing open checkpoint window"
mark; send checkInNow
expect "manual check-in is ignored while away" "Manual check-in ignored: user away"
mark; send screensaverStop
expect "app comes back" "BACK: screensaver"
expect "timer restarts fresh" "Timer restarted"

echo "Screensaver ends but screen is still locked"
mark; send screensaverStart; send lockStart; sleep 0.5; send screensaverStop
expect_absent "stays away until unlocked" "Timer restarted" 2
mark; send lockStop
expect "unlock resumes" "Timer restarted"

echo "Focus never overrides a manual pause"
mark; send pause; send focusOn; send focusOff; send checkInNow
expect "still paused after Focus on/off" "Manual check-in ignored: state=paused"

quit_app

if (( QUICK == 0 )); then
    launch 3600

    echo "Snoozed card comes back (waits ~60 s)"
    check_in
    mark; send snooze
    expect "snooze is recorded" "CHECKPOINT SNOOZED"
    expect "card comes back after the snooze" "presentCheckpoint: snoozeCount=1" 75

    echo "Snoozed card is dropped if Focus starts (waits ~60 s)"
    mark; send snooze
    expect "second snooze is recorded" "CHECKPOINT SNOOZED"
    send focusOn
    expect "snoozed card is dropped" "Snoozed checkpoint dropped" 75
    send focusOff

    quit_app

    launch 60
    echo "Scheduled check-in fires on its own (waits ~60 s)"
    mark
    expect "timer fires after the interval" "Timer FIRED" 75
    expect "checkpoint is shown" "CHECKPOINT FIRING" 5
    quit_app
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if (( FAIL > 0 )); then
    echo "App log kept at: $LOG"
    trap - EXIT; cleanup
    exit 1
fi
rm -rf "$WORK"
