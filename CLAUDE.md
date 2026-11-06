# Checkpoint

Native macOS menu bar app (Swift, SwiftUI + AppKit) that interrupts hyperfocus at intervals with the time, elapsed time, the current objective and a grounding question. Built for ADHD time blindness. Product spec: `checkpoint_spec_v1.2.md`.

## Build and test

Requires Xcode 26.2+ (deployment target macOS 26.2). If `xcode-select` points at the Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The Command Line Tools alone can't build the SwiftUI code (missing macro plugins).

```bash
xcodebuild test -project Checkpoint.xcodeproj -scheme Checkpoint -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

- `scripts/run.sh [launch args]` builds the current branch (Debug) and launches it, replacing the copy it started before. Launch args set settings for that run only, e.g. `-checkpointInterval 60 -randomness off`.
- `scripts/install.sh` builds Release and installs it to `/Applications` (the everyday copy).
- `scripts/e2e.sh [--quick]` runs the end-to-end test (shows windows on screen while it runs).
- Builds from the scripts are signed to run locally (no team needed) and take their build number from the git commit count. Debug builds show a DEV badge on the Dock icon.
- Debug builds add a **Debug** submenu in the menu bar (check in in 10 s, simulate screensaver / lock / Focus, reset first launch). Use it for manual testing.
- Logs: `log stream --predicate 'subsystem == "com.rkrev.checkpoint"'`.
- CI (`.github/workflows/ci.yml`) builds and tests every PR and push to `main`; the shared scheme lives in `Checkpoint.xcodeproj/xcshareddata`.

## Layout

- `Checkpoint/App` — `AppDelegate` owns the services, the scheduling gates, snooze and away handling (for now; see "Planned restructure" below).
- `Checkpoint/Services` — timer, schedule rules, question bank, history log, Focus observer.
- `Checkpoint/UI` — checkpoint card and window controllers, menu bar item, prompts.
- `Checkpoint/Settings` — the Preferences tabs.
- `Checkpoint/Resources/questions.json` — built-in questions; the source of truth for categories.
- `docs/panels.md` — why each panel exists, what it shows, when it appears; `docs/ux-flow.md` — user flow and state diagrams (Mermaid) plus the UX review. Update both when a panel or the user loop changes. `docs/research-basis.md` — evidence behind design choices.
- The Xcode project uses folder-synced groups: adding or deleting a file needs no `project.pbxproj` edit.

## Engineering standards (required)

Every change follows these; reviews check them.

**DRY: one source of truth**
- One definition per setting key and default, per rule (e.g. "can a check-in show now?"), per user-facing string that appears in several places, and per formatting helper (`DurationText`, `ObjectiveName`, `AppInfo`). Reuse before adding.
- No copy-pasted logic across paths; extract a shared function or type and test it once.

**CRUD for user data**
- Every kind of user data (check-in history, objective sessions, parked thoughts, custom questions and categories, goals) has one owning store with a consistent API: **create, read, update, delete**, plus delete-all where the UI offers clearing.
- The UI offers what users reasonably expect for that data (e.g. delete one history entry, edit a parked thought, fix a wrongly tracked stretch), and "Clear history" clears every kind of history the app keeps.
- Stores persist atomically, never lose data on a failed write, surface errors (no silent `try?` on user data), and are testable with an injected location. Today's stores don't all meet this yet: #71.

**Swift best practices**
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for naming; clarity at the point of use.
- Value types (`struct`, `enum`) for models; classes only for identity or shared state. Enums instead of string constants for fixed choices.
- Tightest access control that works (`private` by default); no new globals or singletons beyond system ones.
- No force unwraps (`!`) or `try!` outside tests and provably safe constants; handle optionals and errors explicitly.
- Concurrency: UI and app state on the main actor; mark pure helpers `nonisolated`; no data races (the project is moving to Swift 6 checking).
- Dependency injection (clock, `UserDefaults`, file locations) so logic is unit-testable without the real app or real user data.
- SwiftUI: views hold no business logic; state lives in observable models; views never write settings as a side effect of appearing.
- Small, focused types and functions; comments explain *why*, not *what*.
- New logic comes with tests; CI must pass (lint is tracked in #72).

## Planned restructure

`AppDelegate.swift` (~1,150 lines) is due to be restructured, behaviour-neutral, in the **Code cleanup** milestone: plan [#68](https://github.com/rkrevolution/Checkpoint/issues/68), in order **#16** typed settings (`AppSettings`, done) → **#17** one `CheckInGate` for "can a check-in show now?" (done) → **#18** split into `CheckInScheduler`, `PresenceMonitor`, `WindowRouter` and `Diagnostics`. Each issue has a detailed plan and acceptance criteria.

Until then:
- **Don't grow `AppDelegate`.** Put new logic in its own type (with tests) and only wire it up in `AppDelegate`.
- **Don't add "not now" checks** in individual paths; add them to `CheckInGate` with a test row.
- New settings: add the key, default and typed property to `AppSettings` only.

## Rules

**Behaviour on macOS**
- Never show anything over the screensaver or lock screen. Checkpoint windows use `.statusBar` level or lower, never `.screenSaver`.
- While the user is away (system or display sleep, screensaver, screen lock) nothing fires and nothing plays a sound; any open card and its overlays are dismissed. New away-like states go through `beginAway` / `endAway` in `AppDelegate`.
- Silent failure is the worst failure for this app: a time-blind user won't notice check-ins stopped. Prefer visible state and logging over quietly doing nothing.

**Code**
- Log with `os.Logger` (subsystem `com.rkrev.checkpoint`, category = type name).
- Don't swallow errors with `try?` when saving or exporting user data; log them and surface them in the UI where the user acted.
- Change checkpoint state only via `AppState.transition(to:)`. Never let Focus or other automatic events override `.paused`.
- Every path that presents a checkpoint asks `CheckInGate.block(_:_:)` first (scheduled, snooze return, after a call, manual). Manual requests skip only the schedule, Focus and call checks.
- Debug-only code goes inside `#if DEBUG`; Release builds must not contain it.
- The project builds in Swift 5 mode with default `MainActor` isolation. Wrap main-queue notification callbacks in `MainActor.assumeIsolated`, and mark pure helpers `nonisolated` when tests call them synchronously.
- Preferences go through `AppSettings` (`Checkpoint/Model/AppSettings.swift`): one key, type and default each, no raw string keys elsewhere. Views bind with `@AppStorage(AppSettings.Key.x.rawValue) var x = AppSettings.Default.x`. Never change a key's raw value (it's the stored name). Current work (`currentObjective`, `currentIfThenPlan`) and internal state are not preferences; they belong to their owning type (#68).

**Tests**
- Swift Testing (`@Test`, `#expect`) in `CheckpointTests/CheckpointTests.swift`.
- Add a test for each bug fix or rule where the logic is testable without UI.
- Tests never touch `UserDefaults.standard`: use `isolatedSettings()` or a `UserDefaults(suiteName:)` suite.
- The test host runs as the real app (same bundle ID and preferences). Don't render or instantiate Settings views in tests: their `@AppStorage` reads and writes the user's real settings (this once reset a user's interval to 1 minute).

## Workflow

- Work on a branch, one PR per batch of related issues; never commit directly to `main`.
- Reference issues in commits with `Fixes #N`.
- PR descriptions include a test plan; CI must pass before merging.
- Versioning: `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build), tagged `vX.Y` on release (#27).
