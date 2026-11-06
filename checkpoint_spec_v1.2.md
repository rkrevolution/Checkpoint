# Checkpoint — Hyperfocus Interruption & Time Awareness App for macOS
**Product Specification · Version 2.2 — Personal Machine Build**

| Field | Value |
|---|---|
| Platform | macOS 13 Ventura or later (Apple Silicon + Intel) |
| Framework | SwiftUI + AppKit (Xcode project) |
| App Type | Dock Application (`LSUIElement = false`) + Menu Bar Status Item |
| Bundle ID | `RkRev.Checkpoint` |
| Target User | Personal use — single machine, no distribution |

---

## 1. Purpose & Problem Statement

Checkpoint is a lightweight macOS app for people prone to **hyperfocus** — especially those with ADHD or similar attention profiles. It combats **time blindness** and **goal drift** by interrupting at regular intervals with a brief grounding prompt.

Checkpoint is a **time perception prosthetic**. The ADHD brain has two time modes: *now* and *not now*. Everything that isn't happening right now collapses into an undifferentiated future. Checkpoint's job is to periodically pull the user out of "now" just long enough to re-establish where they are in real time — then let them go back.

> **Core problem:** Hyperfocus causes users to lose track of time, neglect physical needs, and drift from priorities without realizing it. Internal time perception is impaired in ADHD (well documented); making time visible at the point of work is the standard clinical recommendation. See `docs/research-basis.md` for the evidence and its limits.

Checkpoint is a **tap on the shoulder**, not a journal. The user reads one question, acknowledges it, and goes back to work. Being intrusive is the point — it has to break through the hyperfocus tunnel.

**What Checkpoint does:**
- Shows the current time prominently (fights time blindness)
- Shows how long has passed since the last check-in
- Displays the user's current objective (working memory cue)
- Presents a single grounding question from a curated bank
- Requires a quick acknowledgment — no text input needed
- Stays out of the way between checkpoints (< 0.1% CPU)

**What Checkpoint is NOT:**
- Not a journal or survey — no text fields
- Not a Pomodoro timer — no work/break cycles
- Not a task manager — no to-do lists

---

## 1.5 Design Principles

> **Don't fight how the ADHD brain works. Build scaffolding that works with its actual architecture.**

- The ADHD brain doesn't lack awareness — it lacks *reliable* awareness. Checkpoint provides the reliability layer.
- Time blindness isn't a character flaw; it's a perceptual gap. Checkpoint is corrective lensing, not discipline.
- Every interaction should leave the user feeling *helped*, never *judged*. If a prompt could induce shame, it's a bug.

---

## 1.6 The Core Loop

Everything in Checkpoint serves one loop against time blindness. A feature that doesn't strengthen a step of this loop, or adds a step to the check-in card, doesn't belong in the app.

```
 ┌─► 1. Say what you're working on ──► 2. Work with time visible ──► 3. Unpredictable check-in ─┐
 │      objective (+ optional             menu bar: time on the            the real time, time on   │
 │      estimate, if-then plan)           objective; no countdown          the objective, one        │
 │                                                                         question, then "Still on  │
 │                                                                         track?" in one tap         │
 └──────────── 4. Re-orient and go back ◄──────────────────────────────────────────────────────────┘
                 On track · Drifted (see your plan, park the thought) · Switched (pick what you're on now)

 5. See your day: time per objective, estimate vs actual, check-in answers, parked thoughts
```

Rules that keep the loop honest:
- **Time counts only while you're on a stated objective and present**: not before Start, not while paused, away or idle. The card only shows an objective that is being timed; otherwise it asks what you're working on.
- **Check-ins are unpredictable** (randomness around the interval) and **evenly spaced**: the next interval starts when a check-in ends (answered or dropped), so time snoozed or with the card open never shortens the next gap.
- **The answer is always about the objective.** The grounding question is for reflection (time, priorities, body); the one-tap answer is to "Still on track?".
- **A new day is a new loop**: at midnight (or the first launch of the day) yesterday's session ends and the app asks what today is about.
- **Silent failure is the worst failure.** A time-blind user won't notice check-ins stopped, so every stall is visible in the menu bar with a way to restart.
- **Nothing over the lock screen or screensaver, and nothing while away.**

The detailed flow and state diagrams are in `docs/ux-flow.md`; why each panel exists is in `docs/panels.md`.

---

## 1.7 Engineering Principles

Checkpoint is meant to stay small, easy to maintain and safe to extend. The architecture follows from that:

- **DRY: one source of truth.** One definition per setting (key, type and default), per rule (e.g. one gate for "can a check-in show now?"), per user-facing string used in several places, and per formatting helper. Logic is never copy-pasted across paths; it's extracted, named and tested once.
- **Small, focused types with one job each.** The app delegate only wires services together; scheduling, presence (away, idle, calls, Focus), window routing and diagnostics each live in their own type. User data has one owning store per kind with create, read, update and delete.
- **State is explicit.** Check-in state changes only through one state machine, and timers follow the state rather than running alongside it.
- **Testable by design.** Clock, settings and file locations are injected, so the loop's rules are unit-tested without the real app or the user's real data.
- **Scales by addition, not by special cases.** A new away-like state, gate or setting plugs into the existing type for it instead of adding checks to individual paths.

The current code doesn't meet all of this yet. The remaining work is planned, behaviour-neutral, in the **Code cleanup** milestone (#68: #16 typed settings → #17 one check-in gate and state-driven timers → #18 split the app delegate), with consistent stores in #71. `CLAUDE.md` holds the required engineering standards.

---

## 2. Architecture & Technical Approach

### 2.1 App Lifecycle

Checkpoint runs as a Dock app with a menu bar status item. The Dock icon provides visibility; the status item shows a live countdown. Between checkpoints the app is effectively idle — no polling, no animations, no network calls.

### 2.2 Efficiency

| Concern | Approach |
|---|---|
| Timer | Single `DispatchSourceTimer` on `.main`. Non-repeating with jitter; re-schedules after each fire. |
| UI | Modal constructed at checkpoint time, torn down after dismissal. |
| Background | Idle between checkpoints. No network, no polling. |
| Memory | Question bank is a small bundled JSON file. Target: < 25 MB at rest. |
| Persistence | `UserDefaults` for settings. Append-only `.jsonl` for response log. |

### 2.3 File Structure

```
Checkpoint/
├── App/
│   ├── CheckpointApp.swift          ← @main; Settings scene only (no WindowGroup)
│   └── AppDelegate.swift            ← NSApplicationDelegate; owns all services
├── Model/
│   ├── AppState.swift               ← ObservableObject; state machine
│   ├── CheckpointSession.swift      ← Value type for one checkpoint event
│   ├── Question.swift               ← Codable struct
│   └── Category.swift               ← Codable struct
├── Services/
│   ├── CheckpointTimer.swift        ← DispatchSourceTimer wrapper with jitter
│   ├── QuestionBank.swift           ← Loads questions.json + custom; category-aware selection
│   ├── CustomQuestionStore.swift    ← CRUD for user questions; persists to UserDefaults
│   ├── NotificationManager.swift    ← UNUserNotificationCenter permission handling
│   ├── ScheduleManager.swift        ← Active hours, weekday skips, Focus/DND checks
│   ├── FocusModeObserver.swift      ← NSDistributedNotificationCenter for DND
│   └── ResponseLog.swift            ← Appends to .jsonl; reads back for History
├── UI/
│   ├── CheckpointWindowController.swift  ← NSWindowController; modal NSWindow
│   ├── CheckpointView.swift              ← SwiftUI view inside modal
│   ├── ObjectivePromptController.swift   ← Objective prompt on launch/resume
│   ├── DaySummaryController.swift        ← End-of-day summary window
│   ├── TransitionToast.swift             ← Floating toast for objective changes
│   ├── StatusItemController.swift        ← Menu bar icon + countdown + menu
│   ├── WelcomeView.swift                 ← First-launch onboarding
│   └── WelcomeWindowController.swift     ← Window for welcome flow
├── Settings/
│   ├── SettingsView.swift                ← TabView (General, Notifications, Questions, History)
│   ├── GeneralSettingsView.swift
│   ├── NotificationsSettingsView.swift
│   ├── QuestionsSettingsView.swift
│   └── HistorySettingsView.swift
├── Resources/
│   └── questions.json
└── Assets.xcassets/
    └── AppIcon.appiconset/       ← Static icon PNGs (16–1024px)
CheckpointTests/
└── CheckpointTests.swift         ← Swift Testing suite (29 tests)
```

### 2.4 State Machine

```swift
enum CheckpointState: Equatable {
    case idle                              // Timer running, waiting
    case triggered                         // Timer fired, building session
    case presenting                        // Modal on screen
    case snoozed(until: Date, count: Int)  // Snooze timer running
    case paused                            // User paused via menu
    case outsideHours                      // Outside active hours window
    case focusModeActive                   // System Focus/DND active
}
```

`AppState` is an `@MainActor ObservableObject` with a `transition(to:)` method. All state changes go through it.

### 2.5 Threading Rules

| Component | Rule |
|---|---|
| Timer fire | Main queue (`queue: .main` in `makeTimerSource`) |
| AppState mutations | Main thread only |
| ResponseLog file I/O | Background serial queue |
| FocusModeObserver | Callbacks dispatched to main via `Task { @MainActor }` |
| UserDefaults | Read from any thread; write from main |

### 2.6 Logging

All key components use `os.log` with subsystem `com.rkrev.checkpoint`. Categories: `AppDelegate`, `CheckpointTimer`, `ScheduleManager`. Viewable in Console.app.

---

## 3. The Checkpoint Modal

### 3.1 Trigger Flow

1. `DispatchSourceTimer` fires on interval (default 45 min) **with randomness around the configured interval** (Off / Low ±7% / Medium ±15% / High ±25%; default Medium, about ±7 min at 45 min). Randomness prevents habituation — if the user knows exactly when the checkpoint comes, they learn to brace for it and dismiss reflexively. Timer is non-repeating with fresh randomness each time, and **the next interval starts when a check-in ends** (answered, dropped after the snooze limit, or dropped by a gate), so snoozes and an open card don't shorten the next gap.
2. `ScheduleManager.shouldFire()` checks enabled flag, active hours (if toggled on), weekday skips
3. If rejected: stay idle (or transition to `.outsideHours` / `.focusModeActive`)
4. If approved: build `CheckpointSession`, transition to `.triggered`, play sound, present modal

### 3.2 Modal Window

| Property | Value |
|---|---|
| Window Level | `.statusBar` or lower — above normal windows, **never** above the screensaver or lock screen |
| Size | 420 × 380 pt (fixed) |
| Style Mask | `.titled` only — **no close button** (user must engage) |
| Background | `NSVisualEffectView` (`.hudWindow` material) |
| Position | Centered on primary screen |
| Animation | Fade-in 0.25s, fade-out 0.2s |
| Movable | Yes, by window background |

The modal is intentionally intrusive. This is the core design principle — it must break through hyperfocus.

### 3.3 Modal Layout

```
┌──────────────────────────────────┐
│                                  │
│          2:45 PM                 │  ← Large time (fights time blindness)
│     45 minutes have passed       │  ← Interval elapsed
│                                  │
│     🎯 finishing the app         │  ← Current objective (working memory cue)
│            update                │  ← Tap to edit inline
│                                  │
│  ─────────────────────────────── │
│                                  │
│   Is this still the best use     │  ← Single grounding question
│      of my time right now?       │
│                                  │
│          (  ●  )                 │  ← Optional breathing cue (pulsing circle)
│                                  │
│  Not now (5m)          [Got it]  │  ← Two buttons
│                                  │
│  ✓ 3 checkpoints today  ~45 min │  ← Footer: streak + next estimate
└──────────────────────────────────┘
```

**Current Objective:** Displayed prominently with an orange target icon and semibold text. Acts as a goal reminder and a resumption cue after the interruption (Altmann & Trafton, 2002). It is not yet an implementation intention, which is a specific if-then plan (d = 0.65 across 94 tests, Gollwitzer & Sheeran, 2006; also effective for response inhibition in children with ADHD, Gawrilow & Gollwitzer, 2008); see #32 for adding one. User can tap "update" to edit inline without dismissing the modal.

**Answer:** under the question, **"Still on track?"**, answered in one tap. The question is for reflection and may be about time, priorities or the body; the answer is always about the objective.
- **"On track"** (Return key) — back to work. Logs as `completed` with the answer.
- **"Drifted"** — shows the if-then plan and an optional field to park the distraction, then back to work.
- **"Switched"** — pick a recent objective or type a new one; time is tracked on it from here.
- **"Not now (Nm)"** (Escape key) — snoozes. Logs as `snoozed`.

With no objective being timed, the card asks "What are you working on?" with recent objectives instead.

**No skip button, no required text.** This is a tap on the shoulder, not a form.

**Breathing cue:** Optional pulsing orange circle (4-second inhale/exhale cycle). Off by default. Encourages a slow breath during frustration. Slow breathing raises vagally mediated heart rate variability (Laborde et al., 2022), but this small optional cue itself is untested.

**Streak counter:** The footer shows "✓ N checkpoints today" as gentle positive reinforcement. The counter never penalizes — it only rewards showing up. Resets at midnight.

**1.5-second button delay** — buttons are disabled for 1.5s after the modal appears. Forces momentary engagement with the question instead of reflexive dismissal.

### 3.4 Snooze Behavior

- Snooze duration configurable (default 5 min)
- Max snoozes per checkpoint configurable (default 2)
- After max snoozes: auto-dismiss or force-reopen modal (configurable)
- Snooze countdown visible in menu bar status item

### 3.5 Pause / Resume

- **Menu bar menu** → Pause / Resume Checkpoints
- **Dock right-click** → Pause / Resume Checkpoints
- When paused: timer stopped. When resumed: objective prompt shown, then fresh timer from now.

---

## 4. Current Objective

The current objective is a core feature — it provides working memory scaffolding by showing the user what they declared they were working on.

### 4.1 Objective Prompt

A lightweight window (380 × 180 pt) shown:
- On every app launch (after welcome on first launch)
- On resume from pause
- On demand from menu bar ("Update Objective…")

Contains a single text field pre-filled with the last objective, "Start" button, and "Skip" button.

### 4.2 Objective Display

- **In checkpoint modal:** Orange target icon + semibold text + "update" link for inline editing
- **In menu bar:** Shown as tooltip on status item, and as disabled menu item ("Working on: …")
- **Transition toast:** When objective changes, a brief floating notification shows old → new (auto-dismisses after 3 seconds). Supports task-switching, a known EF weakness.

### 4.3 Day Summary

When active hours end (if active hours toggle is on), a summary window shows:
- Total checkpoints completed today
- All objectives worked on during the day

Helps answer "what did I even do today?" — a common ADHD struggle.

---

## 5. First-Launch Welcome

On first launch (`hasLaunchedBefore` = false), a welcome window appears:

- Sun icon + "Welcome to Checkpoint" header
- Brief ADHD-framed explanation
- **Interval picker**: 15 / 30 / 45 / 60 / 90 min (segmented, default 45)
- "How it works" bullets explaining the three actions
- Note: "Timing varies slightly each time to stay noticeable" (jitter explanation)
- "Start Checkpoints" button → saves settings, shows objective prompt, starts timer

If the user closes without tapping Start, the app starts with defaults.

---

## 6. Menu Bar Status Item

A persistent `NSStatusItem` shows the app's state at a glance:

| State | Icon | Title |
|---|---|---|
| Idle | `sun.max.fill` | `Xm` (countdown to next checkpoint) |
| Presenting | `bubble.left.fill` | `Active` |
| Snoozed | `clock.arrow.circlepath` | `Xm` (countdown to snooze end) |
| Paused | `pause.circle` | `Paused` |
| Outside hours | `moon.fill` | `Off hours` |
| Focus mode | `moon.fill` | `Focus` |

Title updates every 1 second. Tooltip shows current objective.

**Menu items:**
1. Pause/Resume Checkpoints
2. Next checkpoint info (or state label)
3. "Working on: [objective]" (if set)
4. Update Objective…
5. Check In Now
6. Preferences… (⌘,)
7. Quit Checkpoint (⌘Q)

"Check In Now" triggers a checkpoint immediately (only available from idle/outsideHours states).

---

## 7. Settings (⌘,)

Four tabs in a resizable window (min 520 × 440, default 620 × 560). Uses `NSViewRepresentable` to insert `.resizable` into window style mask.

### 7.1 General

- **Enable Checkpoints**: on/off toggle
- **Interval**: picker with preset options (1, 2, 5, 10, 15, 20, 25, 30, 45 min, 1 hr, 1.5 hr, 2 hr; default 45 min)
- **Limit to active hours**: toggle (default **off** — checkpoints fire whenever app is open)
  - When on: start/end hour pickers appear (default 8 AM – 6 PM)
- **Questions per check-in**: segmented 1/2/3 (default 1)
- **Preview Checkpoint**: button to see exactly what a checkpoint looks like

### 7.2 Notifications

- **Sound**: on/off toggle + sound picker (Glass, Ping, Pop, Purr, Sosumi, Tink) + Preview button
- **Interval jitter**: slider 0–15 min (default ±10 min)
- **Snooze duration**: 1 / 5 / 10 / 15 min (default 5)
- **Max snoozes**: 1 / 2 / 3 / Unlimited (default 2)
- **After max snoozes**: auto-dismiss or force open (default auto-dismiss)
- **Breathing cue**: toggle (default off) — pulsing circle on checkpoint modal
- **Respect Focus/DND**: on/off (default on)
- **Suppress during full-screen**: on/off (default on)

### 7.3 Questions

Split panel: category sidebar + question list.

- Category sidebar with question counts
- Per-question enable/disable toggle
- Add custom questions (max 200 chars) and categories
- Delete custom questions/categories (built-in categories cannot be deleted)

### 7.4 History

- Toggle: Log responses (default on)
- Session list with outcome badges (Completed = green, Snoozed = blue)
- Filter by outcome: All / Completed / Snoozed
- Export as JSON or CSV
- Clear history with confirmation dialog

### 7.5 UserDefaults Keys

| Key | Type | Default |
|---|---|---|
| `checkpointInterval` | `Int` (seconds) | `2700` |
| `jitterRange` | `Int` (seconds) | `600` |
| `useActiveHours` | `Bool` | `false` |
| `activeHoursStart` | `Int` (hour) | `8` |
| `activeHoursEnd` | `Int` (hour) | `18` |
| `checkpointsEnabled` | `Bool` | `true` |
| `questionsPerCheckpoint` | `Int` | `1` |
| `playSoundOnCheckpoint` | `Bool` | `true` |
| `soundName` | `String` | `"Glass"` |
| `snoozeMinutes` | `Int` | `5` |
| `maxSnoozesPerCheckpoint` | `Int` | `2` |
| `afterMaxSnoozeAction` | `String` | `"autoDismiss"` |
| `respectFocusMode` | `Bool` | `true` |
| `suppressInFullScreen` | `Bool` | `true` |
| `showBreathingCue` | `Bool` | `false` |
| `skipWeekdays` | `[Int]` | `[]` |
| `disabledQuestionIDs` | `[String]` | `[]` |
| `logResponses` | `Bool` | `true` |
| `hasLaunchedBefore` | `Bool` | `false` |
| `currentObjective` | `String` | `""` |

---

## 8. Question Bank

### 8.1 Design Principles

- Questions are **grounding prompts** — they interrupt hyperfocus and reconnect the user to time, priorities, and physical state
- Grouped into categories; selection uses **recency bias** to avoid repetition
- Phrased as genuine reflection — never judgmental or shame-inducing
- **Shame-free language**: Every question must pass a shame audit. No question should imply the user is doing something wrong, wasting time, or failing. Questions assume good intent and offer perspective, not correction.
- Universal language — no corporate/team assumptions; works for anyone doing focused work
- Informed by ADHD/time-blindness research: external time cues, metacognitive scaffolding, interoceptive awareness

### 8.2 Built-In Categories (v3 — 6 categories, 27 questions)

#### Category A — Alignment & Priority (5)
- Is this still the best use of my time right now?
- What am I actually trying to accomplish right now?
- Is what I'm doing connected to what I set out to do today?
- If I had to justify the last 45 minutes, could I?
- Am I working on this because it matters, or because it's interesting?

#### Category B — Scope & Depth (5)
- Is it still reasonable for me to be spending time here?
- Have I gone deeper than this actually needs?
- Is there a simpler way to get to the same result?
- What would 'good enough' look like right now?
- Is this more detailed than the situation calls for?

#### Category C — Progress (5)
- What have I actually accomplished in the last interval?
- Could I explain what I just did in two sentences?
- How does what I've done fit into the bigger picture?
- What's the next thing that actually needs to happen?
- Am I making progress, or am I going in circles?

#### Category D — Time Awareness (4)
- How much time do I have left today for what matters most?
- What's coming up next that I should be aware of?
- Do I still have a clear picture of what I'm working toward?
- If I keep going at this pace, will I finish when I need to?

#### Category E — Body & Energy (4)
- Have I eaten, had water, or moved recently?
- Am I noticing any tension, discomfort, or fatigue?
- When did I last stand up?
- Can I sustain this energy for another interval?

#### Category F — Mindfulness & Reset (4)
- Would a short break help me right now?
- Is there anything I should write down before I forget?
- What's one thing I want to have done by the next checkpoint?
- Am I choosing what to focus on, or is it choosing me?

### 8.3 questions.json Schema

```json
{
  "version": 3,
  "categories": [
    {
      "id": "alignment",
      "name": "Alignment & Priority",
      "questions": [
        { "id": "a1", "text": "Is this still the best use of my time right now?" }
      ]
    }
  ]
}
```

### 8.4 Question Selection Algorithm

1. Get all enabled questions (question enabled + category enabled)
2. Group by category
3. Prefer categories not recently shown (`recentCategoryIds` tracking)
4. Pick one question per unique category (random within category)
5. If more needed: fill from remaining pool
6. Return shuffled

### 8.5 Custom Questions

Users can add their own questions (max 200 characters) and categories via Settings → Questions. Custom questions are stored in `UserDefaults` and merged with bundled questions at runtime. Built-in questions are never mutated.

---

## 9. Response Logging

Each checkpoint is recorded as JSON Lines at:

```
~/Library/Application Support/Checkpoint/responses.jsonl
```

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2025-03-11T14:32:00Z",
  "intervalSeconds": 2700,
  "questions": [
    { "id": "a1", "text": "Is this still the best use of my time right now?" }
  ],
  "responses": [
    { "questionId": "a1", "text": "" }
  ],
  "outcome": "completed"
}
```

`outcome`: `"completed"` or `"snoozed"`

- `completed` — user tapped "Got it"; acknowledged the checkpoint.
- `snoozed` — user tapped "Not now"; checkpoint will re-present after the snooze interval.

---

## 10. Dock Icon

Orange gradient rounded rectangle with a white sun (circle + 8 rays).

- **Asset catalog:** `Assets.xcassets/AppIcon.appiconset` — static PNGs at all 10 required sizes (16px through 1024px). These are used by Finder, the Dock bar, Spotlight, and the exported `.app` bundle.
- **Runtime:** Also set programmatically via `NSApp.applicationIconImage` in `AppDelegate.setDockIcon()` using the same design, so the icon appears correctly even during development without a clean build.

---

## 11. Out of Scope (v1.0)

- AI-generated questions
- iCloud sync
- iOS/iPadOS companion
- Integration with task managers
- Calendar/meeting awareness
- App Store distribution
- Banner or Dock Badge notification styles (modal-only is the right UX for breaking hyperfocus)
- Blackout windows (stub exists, returns false)
- Full-screen app detection (setting exists, not wired)
- Volume slider for sound
- Text input / journaling

---

## 12. Performance Targets

| Metric | Target |
|---|---|
| CPU (idle) | < 0.1% |
| CPU (modal visible) | < 5% |
| Memory at rest | < 25 MB |
| Launch to running timer | < 1 second |
| Modal appear latency | < 100 ms |

---

## 13. Logging & Diagnostics

All key components log via `os.log` (subsystem: `com.rkrev.checkpoint`) at `notice` level so logs persist to disk.

**Categories:** `AppDelegate`, `CheckpointTimer`, `ScheduleManager`

**What's logged:**
- Timer scheduling: base interval, jitter applied, actual wait, exact fire time
- Timer fires
- Gate checks: active hours, shouldFire result, focus mode status
- Checkpoint presentation and modal visibility verification
- User actions: "Got it" / "Not now" with timestamps
- Snooze scheduling
- Objective changes

**Query logs:**
```bash
log show --predicate 'subsystem == "com.rkrev.checkpoint"' --last 30m
```

Or stream live in Console.app filtered by `com.rkrev.checkpoint`.

---

## 14. Version Control

The project uses **git** (which is the same thing Xcode's Source Control uses under the hood). The repository is at the project root.

**Repository:** `/Users/spark/Desktop/Checkpoint/`
**Main branch:** `main`

---

## 15. Build & Install (Personal Use)

No developer account, App Store, or notarization required for personal use.

### Build
1. Open `Checkpoint.xcodeproj` in Xcode
2. **Product → Archive**
3. Organizer opens → select archive → **Distribute App → Copy App**
4. Export to a folder (e.g. Desktop)

### Install
1. Move `Checkpoint.app` to `/Applications`
2. Double-click to launch
3. If macOS blocks it: **System Settings → Privacy & Security → Open Anyway**

### Launch at Login (optional)
- **System Settings → General → Login Items → +** → select Checkpoint

---

## 16. Testing

Unit tests use the **Swift Testing** framework (`import Testing`) in the `CheckpointTests` target.

**Run tests:** Cmd+U in Xcode (Product → Test).

### Test Coverage (29 tests)

| Suite | Tests | What's Covered |
|---|---|---|
| `ScheduleManagerTests` | 6 | shouldFire gate checks, active hours (normal/overnight/same/off), weekday skips |
| `AppStateTests` | 6 | Initial state, transitions, duplicate transition guard, recent category tracking (max 6), full lifecycle |
| `QuestionBankTests` | 7 | Fallback loading, correct count, no excess, category diversity, all-disabled empty, recent category avoidance, no duplicates |
| `CheckpointSessionTests` | 2 | Codable round-trip (ISO8601 dates), CodingKeys `questionsShown` → `"questions"` mapping |
| `CheckpointTimerTests` | 5 | nil fire date when stopped, fire date set on start, stop clears, 60s minimum enforced, jitter within expected range |
| `IntervalPickerTests` | 3 | Snap-to-nearest option logic, edge cases, label formatting (min/hour/hours) |

### Testing Approach

- **`@MainActor` classes** (ScheduleManager, AppState, QuestionBank, CheckpointTimer) are tested via `await MainActor.run {}` blocks
- **UserDefaults** are set/reset within each test to avoid cross-test contamination
- **QuestionBank** uses the hardcoded fallback in the test target (no `questions.json` in test bundle)
- **Timer tests** set jitter to 0 for deterministic fire date assertions
- **No UI tests** — the modal, settings, and menu bar are tested manually via the Preview Checkpoint button in Settings

---

*End of Specification*
