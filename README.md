# Checkpoint

**A tap on the shoulder for the hyperfocused.**

The ADHD brain has two time modes: *now* and *not now*. Hours vanish. Priorities drift. You look up and it's dark outside. Checkpoint is a macOS menu bar app that periodically breaks through the tunnel: it shows you the time, how long you've been on what you meant to do, and asks one grounding question. You answer with one tap and go back to work.

It's a time perception prosthetic. Corrective lensing, not discipline.

## Status

**Working and in daily-use testing (version 1.0, unreleased).** All core features are built, tested and merged to `main`; CI builds and runs unit and end-to-end tests on every pull request.

| | |
|---|---|
| **Works** | Unpredictable check-ins; time on your current objective (menu bar, card, Today); On track / Drifted / Switched answers; estimates vs actual; parked thoughts; Today window; goals; holds check-ins during calls; never shows over the screensaver or lock screen; warns if check-ins stop |
| **Known issues** | [#49](../../issues/49) pausing from the menu leaves an open card · [#50](../../issues/50) menu bar shows "Focus" when Respect Focus is off · [#51](../../issues/51) / [#43](../../issues/43) a new day only starts at launch · [#52](../../issues/52) a held check-in can be followed by another soon after · [#2](../../issues/2) Focus detection probably doesn't work on current macOS |
| **Not proven** | Built on well-documented ideas (see [Research basis](#research-basis)), but the app itself hasn't been studied. Whether it helps *you* shows after a few weeks of use; the data (answers, time per task, estimate accuracy) is recorded locally. |
| **Next** | A few weeks of real use. Then: [#40](../../issues/40) "is it working?" trends, [#13](../../issues/13) calendar warnings, [#16](../../issues/16)/[#17](../../issues/17) internal cleanup. Full plan: [roadmap #31](../../issues/31). |

## How it works

1. **Set what you're working on.** One line, a recent one with one tap, and optionally how long it should take and an "if I drift, I will…" plan.
2. **Work.** The menu bar shows how long you've been on it. No countdown: check-ins come at unpredictable times so you can't brace for them.
3. **Check in.** A card shows the time, your objective and time on it (red once past your estimate), and a question. Answer **On track**, **Drifted** (see your plan, park the distraction) or **Switched** (pick what you're on now).
4. **Review.** **Today…** in the menu shows your day: time per objective, estimate accuracy, check-in answers, parked thoughts.

Being interruptive is the point. It has to break through hyperfocus to work. It stays out of the way when it should: during calls (held until you hang up), while you're away (sleep, lock, screensaver), and from screen shares (the card is hidden from capture).

![A checkpoint prompt showing the time, elapsed duration, current objective, and a grounding question](screenshot-checkpoint.png)

*Screenshots show an earlier version; the card now has On track / Drifted / Switched and time on your objective.*

## Features

- **Check-ins:** intervals from 1 min to 2 hours with random timing; snooze with limits; active hours (including overnight) and weekday skipping; full-screen dim option; sound choice.
- **Time visible:** time on the current objective in the menu bar, on the card and in Settings › Now; time away and idle stretches aren't counted.
- **Re-orienting:** one-tap On track / Drifted / Switched; if-then plan; recent objectives; parked thoughts (from the card or the menu).
- **Time sense:** optional estimates with "1 h 20 min of ~1 h" progress, and weekly estimate accuracy in Today.
- **Goals:** up to three lines kept in view in the menu, on check-ins and in Today.
- **Respectful:** holds check-ins during calls (microphone or camera in use), hides from screen sharing, pauses while away, respects Focus (see #2), **⌃⌥⌘P** pauses from any app.
- **Reliable:** warns in the menu bar if check-ins ever stop, with a Restart action.
- **Private:** no network, no telemetry. History, sessions and parked thoughts stay in `~/Library/Application Support/Checkpoint`.

![Welcome screen with interval picker and quick setup](screenshot-welcome.png)
![General settings with interval, active hours, and login toggle](screenshot-settings.png)
![Response history showing completed and snoozed checkpoints with timestamps](screenshot-history.png)

## Research basis

Checkpoint is informed by research rather than proven by it. Time perception problems in ADHD are well documented, and its core mechanism (an unpredictable cue to check whether you're on task, with the time made visible) mirrors cued self-monitoring, which works well for children with ADHD. Most direct evidence comes from children, and the app itself hasn't been studied. See [docs/research-basis.md](docs/research-basis.md) for each design choice, the evidence behind it, and how strong it is, including the CBT program for adult ADHD that several features draw on. What each panel is for and how it fits the loop is in [docs/panels.md](docs/panels.md); the user flow, app states and UX review are in [docs/ux-flow.md](docs/ux-flow.md).

## Install and run

Requires macOS 26.2+ and Xcode 26.2+ (the Command Line Tools alone can't build the SwiftUI code).

```bash
git clone https://github.com/rkrevolution/Checkpoint.git
cd Checkpoint
scripts/install.sh   # build Release, install to /Applications, launch (everyday copy)
scripts/run.sh       # build the current branch (Debug) and launch it, for development
```

Or open `Checkpoint.xcodeproj` and press ⌘R. Debug copies show a **DEV** badge on the Dock icon, an orange menu bar icon, and a Debug menu for testing (check in now, simulate screensaver, lock, Focus or a call). Clicking the Dock icon opens Settings.

## Development

- **Tests:** `xcodebuild test -project Checkpoint.xcodeproj -scheme Checkpoint -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` (unit tests use isolated settings and a fake clock).
- **End-to-end:** `scripts/e2e.sh --quick` drives the real app with throwaway data and checks its log (windows appear on screen while it runs).
- **CI:** `.github/workflows/ci.yml` runs both on every pull request and push to `main`.
- **Conventions:** see [CLAUDE.md](CLAUDE.md). Work on a branch, one PR per batch, `Fixes #N` in commits.

## Session overview (2 November 2026)

Checkpoint started the day as a working Swift prototype. In one development session it went from prototype to a tested, documented app:

- **Reliability:** never shows over the screensaver or lock screen; pauses while away; fixed Focus/pause conflicts, snooze loops, lost objective edits, Preferences not opening, a card that could get stuck "presenting", and errors that failed silently. ([#23](../../pull/23), [#28](../../pull/28), [#36](../../pull/36))
- **Time visible:** time on the current objective, a stall warning, if-then plans. ([#37](../../pull/37))
- **Feedback loop:** On track / Drifted / Switched, parked thoughts, estimates vs actual, the Today window, idle-aware time. ([#38](../../pull/38), [#39](../../pull/39))
- **Everyday use:** weekday skipping setting, ⌃⌥⌘P shortcut, simple goals, holding check-ins during calls and hiding from screen shares. ([#45](../../pull/45), [#47](../../pull/47), [#48](../../pull/48))
- **Engineering:** CI with unit and end-to-end tests, `run.sh`/`install.sh`, version display and DEV badge, `CLAUDE.md`, research and UX docs. Footprint about 46 MB and 0% CPU when idle.
- **Decisions:** stay native Swift (not Electron or Tauri); free-text objectives with recent suggestions rather than a dropdown; goals kept to three simple lines rather than a full goal hierarchy; an independent review's proposal to slim the card, prompt and settings was **declined for now**, and its bug findings were filed as #49–#52.
- **Tracking:** 20 issues closed; remaining work is on the [issues page](../../issues) and the [roadmap](../../issues/31).

## License

Personal use. No license currently specified.
