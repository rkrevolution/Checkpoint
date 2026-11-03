# Checkpoint

Native macOS menu bar app (Swift, SwiftUI + AppKit) that interrupts hyperfocus at intervals with the time, elapsed time, the current objective and a grounding question. Built for ADHD time blindness. Product spec: `checkpoint_spec_v1.2.md`.

## Build and test

Requires Xcode 26.2+ (deployment target macOS 26.2). If `xcode-select` points at the Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The Command Line Tools alone can't build the SwiftUI code (missing macro plugins).

```bash
xcodebuild test -project Checkpoint.xcodeproj -scheme Checkpoint -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

- `scripts/run.sh [launch args]` builds the current branch (Debug) and launches it, replacing the copy it started before. Launch args set settings for that run only, e.g. `-checkpointInterval 60 -jitterRange 0`.
- `scripts/install.sh` builds Release and installs it to `/Applications` (the everyday copy).
- `scripts/e2e.sh [--quick]` runs the end-to-end test (shows windows on screen while it runs).
- Builds from the scripts are signed to run locally (no team needed) and take their build number from the git commit count. Debug builds show a DEV badge on the Dock icon.
- Debug builds add a **Debug** submenu in the menu bar (check in in 10 s, simulate screensaver / lock / Focus, reset first launch). Use it for manual testing.
- Logs: `log stream --predicate 'subsystem == "com.rkrev.checkpoint"'`.
- CI (`.github/workflows/ci.yml`) builds and tests every PR and push to `main`; the shared scheme lives in `Checkpoint.xcodeproj/xcshareddata`.

## Layout

- `Checkpoint/App` — `AppDelegate` owns the services, the scheduling gates, snooze and away handling.
- `Checkpoint/Services` — timer, schedule rules, question bank, history log, Focus observer.
- `Checkpoint/UI` — checkpoint card and window controllers, menu bar item, prompts.
- `Checkpoint/Settings` — the Preferences tabs.
- `Checkpoint/Resources/questions.json` — built-in questions; the source of truth for categories.
- The Xcode project uses folder-synced groups: adding or deleting a file needs no `project.pbxproj` edit.

## Rules

**Behaviour on macOS**
- Never show anything over the screensaver or lock screen. Checkpoint windows use `.statusBar` level or lower, never `.screenSaver`.
- While the user is away (system or display sleep, screensaver, screen lock) nothing fires and nothing plays a sound; any open card and its overlays are dismissed. New away-like states go through `beginAway` / `endAway` in `AppDelegate`.
- Silent failure is the worst failure for this app: a time-blind user won't notice check-ins stopped. Prefer visible state and logging over quietly doing nothing.

**Code**
- Log with `os.Logger` (subsystem `com.rkrev.checkpoint`, category = type name).
- Don't swallow errors with `try?` when saving or exporting user data; log them and surface them in the UI where the user acted.
- Change checkpoint state only via `AppState.transition(to:)`. Never let Focus or other automatic events override `.paused`.
- Every path that presents a checkpoint must re-check the away state, schedule and Focus gates, except an explicit manual check-in.
- Debug-only code goes inside `#if DEBUG`; Release builds must not contain it.
- The project builds in Swift 5 mode with default `MainActor` isolation. Wrap main-queue notification callbacks in `MainActor.assumeIsolated`, and mark pure helpers `nonisolated` when tests call them synchronously.
- Settings are read from `UserDefaults.standard` by key; keep defaults in `AppDelegate`'s `register(defaults:)` in sync with any `@AppStorage` default (#16 replaces this with a typed settings type).

**Tests**
- Swift Testing (`@Test`, `#expect`) in `CheckpointTests/CheckpointTests.swift`.
- Add a test for each bug fix or rule where the logic is testable without UI.
- Known issue: some tests write to the real `UserDefaults.standard` domain (#16 fixes this). Don't add new tests that do.

## Workflow

- Work on a branch, one PR per batch of related issues; never commit directly to `main`.
- Reference issues in commits with `Fixes #N`.
- PR descriptions include a test plan; CI must pass before merging.
- Versioning: `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build), tagged `vX.Y` on release (#27).
