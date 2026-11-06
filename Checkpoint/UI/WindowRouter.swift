import AppKit
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "WindowRouter")

/// Opens and tracks every window and panel (#18): the check-in card, Welcome, the objective
/// prompt (incl. "Good morning" / "Welcome back"), Today, How it works, Park a Thought and Settings.
///
/// One instance of each window at a time. Objective changes from any window go straight to
/// `ObjectiveTracker`, the single owner of what you're working on.
@MainActor
final class WindowRouter {

    private let tracker: ObjectiveTracker
    private let parkedThoughts: ParkedThoughts
    private let responseLog: ResponseLog
    private let transitionToast = TransitionToast()

    private var card: CheckpointWindowController?
    private var welcome: WelcomeWindowController?
    private var objectivePrompt: ObjectivePromptController?
    private var today: TodayWindowController?
    private var howItWorks: HowItWorksWindowController?

    init(tracker: ObjectiveTracker, parkedThoughts: ParkedThoughts, responseLog: ResponseLog) {
        self.tracker = tracker
        self.parkedThoughts = parkedThoughts
        self.responseLog = responseLog
    }

    // MARK: - State

    var isCardVisible: Bool { card?.window?.isVisible == true }
    var isShowingWelcome: Bool { welcome != nil }
    /// Welcome or the objective prompt is open (don't stack another prompt on top).
    var isPrompting: Bool { welcome != nil || objectivePrompt != nil }

    // MARK: - Check-in card

    /// Shows a check-in. Only an objective that's being timed is shown; otherwise the card asks
    /// what you're working on (#75).
    func showCard(_ session: CheckpointSession, checkInNumber: Int, allowSnooze: Bool,
                  onAnswered: @escaping (CheckpointSession) -> Void,
                  onSnoozed: @escaping (CheckpointSession) -> Void) {
        let objective = tracker.current?.objective ?? ""
        let controller = CheckpointWindowController(
            session: session,
            currentObjective: objective,
            checkpointNumber: checkInNumber,
            objectiveSession: tracker.current,
            recentObjectives: tracker.recentObjectives(limit: 10),
            allowSnooze: allowSnooze,
            onDone: { [weak self] completed, updatedObjective in
                guard let self else { return }
                self.card = nil
                log.notice("  Objective updated: \(updatedObjective != nil ? "yes" : "no")")
                if let updated = updatedObjective, !updated.isEmpty {
                    self.changeObjective(to: updated, from: objective)
                }
                if let thought = completed.parkedThought {
                    self.parkedThoughts.park(thought, objective: self.tracker.current?.objective)
                }
                onAnswered(completed)
            },
            onSnooze: { [weak self] in
                self?.card = nil
                onSnoozed(session)
            }
        )
        card = controller
        controller.showWithFade()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if controller.window?.isVisible == true {
                log.notice("✓ Modal window visible on screen")
            } else {
                log.error("✗ Modal window NOT visible — something blocked it")
            }
        }
    }

    /// Removes the card and its overlays at once, without an answer (pause, away, restart).
    func dismissCard() {
        guard let card else { return }
        log.notice("  Dismissing open checkpoint window")
        card.dismissImmediately()
        self.card = nil
    }

    // MARK: - Objective

    /// First launch. `onDone` runs when Welcome closes, however it closes.
    func showWelcome(onDone: @escaping () -> Void) {
        let controller = WelcomeWindowController { [weak self] _ in
            self?.welcome = nil
            onDone()
        }
        welcome = controller
        controller.show()
    }

    /// "Good morning" before noon, otherwise "Welcome back": launch, a new day.
    func showDayStartPrompt() {
        let hour = Calendar.current.component(.hour, from: Date())
        showObjectivePrompt(greeting: hour < 12 ? "Good morning" : "Welcome back") {
            log.notice("Objective prompt dismissed")
        }
    }

    /// "What are you working on?", prefilled with the current or last objective. A greeting
    /// ("Welcome back") adds what you were on. `onDone` runs however the prompt closes.
    func showObjectivePrompt(greeting: String? = nil, onDone: @escaping () -> Void = {}) {
        let last = tracker.lastSession
        let controller = ObjectivePromptController(
            objective: last?.objective ?? "",
            ifThenPlan: last?.ifThenPlan,
            recentObjectives: tracker.recentObjectives(limit: 10),
            initialEstimate: tracker.current?.estimateMinutes,
            greeting: greeting,
            context: greeting == nil ? nil : tracker.welcomeBackContext(),
            onStart: { [weak self] objective, plan, estimate in
                guard let self else { return }
                if !objective.isEmpty {
                    self.changeObjective(to: objective, from: self.tracker.current?.objective ?? "")
                }
                self.tracker.ifThenPlanChanged(to: plan)
                self.tracker.estimateChanged(to: estimate)
            },
            onDone: { [weak self] in
                self?.objectivePrompt = nil
                onDone()
            }
        )
        objectivePrompt = controller
        controller.show()
    }

    /// Starts timing `new` and confirms the switch with a brief toast.
    private func changeObjective(to new: String, from old: String) {
        tracker.objectiveChanged(to: new)
        transitionToast.show(from: old, to: new)
    }

    // MARK: - Other windows

    /// Today's time per objective, check-in answers and parked thoughts. With a headline (e.g. at
    /// the end of active hours) it opens fresh; otherwise an open one comes to the front.
    func showToday(headline: String? = nil) {
        if let window = today?.window, window.isVisible, headline == nil {
            today?.show()
            return
        }
        today?.close()
        let controller = TodayWindowController(
            tracker: tracker,
            parked: parkedThoughts,
            loadCheckIns: { [responseLog] in (try? responseLog.loadAll()) ?? [] },
            headline: headline
        )
        today = controller
        controller.show()
    }

    func showHowItWorks() {
        let controller = howItWorks ?? HowItWorksWindowController()
        howItWorks = controller
        controller.show()
    }

    /// Write down a distraction to deal with later (#34).
    func parkThought() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Park a thought"
        alert.informativeText = "Write it down to deal with later, then get back to what you were doing."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "e.g. reply to Sam about Friday"
        alert.accessoryView = field
        alert.addButton(withTitle: "Park It")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            parkedThoughts.park(field.stringValue, objective: tracker.current?.objective)
        }
    }

    func openSettings() {
        // macOS 14+ ignores the old `showSettingsWindow:` action, so trigger the app menu's
        // own Settings… item (the one SwiftUI's Settings scene installs) instead.
        NSApp.activate()
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            appMenu.performActionForItem(at: index)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    #if DEBUG
    func debugAcknowledge() { card?.debugAcknowledge() }
    func debugSnooze() { card?.debugSnooze() }
    #endif
}
