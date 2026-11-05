// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

/// Production opening and availability methods run with inert presentation
/// doubles. Feature choices live only in a disposable test preferences domain.
enum NotchDestinationContract {
    enum ReviewDefaults { static var current: UserDefaults! }
    enum NotchContentTransition { case none, reveal, replace }
    /// Like AppKit while Vorssaint stays active, makeKey and resignKey leave
    /// the app's key window as it was; tests set that record by hand.
    final class Panel {
        var isKeyWindow = true
        var acceptsKeyFocus = false
        var isVisible = true
        var isOnActiveSpace = true
        var canBecomeMain = false
        var keyRequests = 0
        func makeKey() { keyRequests += 1 }
        func resignKey() { isKeyWindow = false }
    }
    enum NSWorkspace { static let shared = Workspace() }
    final class Workspace { var frontmostApplication: RunningApplication? }
    struct RunningApplication { let processIdentifier: Int32 }
    final class Host { func containsHover(_ point: CGPoint) -> Bool { false } }
    enum NSEvent { static let mouseLocation = CGPoint.zero }
    final class AppDelegate { func closePopover(preservingNotch: Bool) {} }
    final class Application {
        let delegate: AnyObject? = nil
        var keyWindow: Panel?
        var orderedWindows: [Panel] = []
    }
    static let NSApp = Application()
    enum ClipboardHistoryService {
        static let shared = Reader()
        struct Reader { func rememberPasteTarget() {} }
    }
    enum QuickLauncherService { static var shared = QuickLauncherContract.Launcher() }
    enum MenuPanelFocus {
        static let shared = Focus()
        final class Focus {
            var normalRequests = 0
            func showNormalPanel() { normalRequests += 1 }
        }
    }
    final class Timer {
        var running = true
        var syncs = 0
        var suspensions = 0
        func syncWithPreferences() { running = true; syncs += 1 }
        func suspend() { running = false; suspensions += 1 }
    }
    enum NotchTimerService { static var shared = Timer() }
    enum PreciseVolumeRollerService {
        static let shared = Service()
        struct Service { func syncWithPreferences() {} }
    }
    final class Brightness {
        var syncs = 0
        func syncWithPreferences() { syncs += 1 }
    }
    enum BrightnessService { static var shared = Brightness() }
    final class LockScreen {
        var syncs: [NotchSessionState] = []
        var sounds: [Bool] = []
        var onSync: (() -> Void)?
        func sync(_ session: NotchSessionState) { syncs.append(session); onSync?() }
        func playSound(locking: Bool) { sounds.append(locking) }
    }
    enum NotchLockScreenService { static var shared = LockScreen() }
    final class CountdownCalendar {
        var countdown: NotchCalendarCountdown?
        var revealing: String?
    }
    enum NotchCalendarService { static var shared = CountdownCalendar() }
    final class Hotkey {
        var onPress: (() -> Void)?
        var refuses = false
        var requests: [Bool] = []
        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool {
            requests.append(enabled)
            return !(enabled && refuses)
        }
    }
    enum ShortcutCapture { static var isCapturing = false }

    class State {
        func setClipboardPagePointerInside(_ inside: Bool) {}
        var acceptsUserInteraction = true
        func collapse() { expanded = false }
        var hiddenInFullscreen = false
        var running = true
        var session = NotchSessionState()
        var suspended: Bool { !session.canPresent }
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var modules: [NotchModule] = []
        var selected = NotchModule.controls
        var temporaryPageReturnModule: NotchModule?
        var selectedMetric: MetricDetailKind?
        var expanded = false
        var showsKeyboardFocus = false
        var showingAppPanel = false
        var showingSections = false
        var showingCommandBar = false
        var commandBarClosings = 0
        func commandBarDidClose() { commandBarClosings += 1 }
        var sectionQuery = ""
        var sectionRow = 0
        var highlightedSection: NotchModule?
        var peeking = false
        var pinned = false
        var openedByHover = false
        var inside = false
        var notice: NotchNotice?
        var noticeExpanded = false
        var noticeWork: DispatchWorkItem?
        var compactActivity: NotchCompactActivity?
        var hoverState = NotchHoverState()
        var hoverWork: DispatchWorkItem?
        var requestedDetail: MetricDetailKind?
        var detailHasPage = false
        var pageLayers: [NotchModule: () -> Void] = [:]
        var clipboardPreviewClose: (() -> Void)?
        func closeClipboardPreview() {
            let close = clipboardPreviewClose
            clipboardPreviewClose = nil
            close?()
        }
        var captureControls: AnyObject?
        var heldDrag = false
        var presentationSyncs = 0
        var presentationTearDowns = 0
        var captureControlsCancel: (() -> Void)?
        var captureClose: (() -> Void)?
        func mutatePresentation(transitionContent: NotchContentTransition, _ change: () -> Void) { change() }
        func installEventMonitors() {}
        func syncVisibleConsumers() { requestedDetail = selectedMetric }
        func provideHapticFeedback() {}
        func endCaptureControls() {}
        let hotkey = Hotkey()
        var shortcutFailureWrites = 0
        var shortcutRegistrationFailed = false { didSet { shortcutFailureWrites += 1 } }
        var captureControlsExpansions = 0
        func expandCaptureControls() { captureControlsExpansions += 1 }
        func clearCapture() { captureControlsCancel = nil; captureClose = nil }
        func tearDownPresentation() { expanded = false; presentationTearDowns += 1 }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-destinations"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        ReviewDefaults.current = defaults
        let previousLauncherDefaults = QuickLauncherContract.ReviewDefaults.current
        QuickLauncherContract.ReviewDefaults.current = defaults
        defer {
            QuickLauncherContract.ReviewDefaults.current = previousLauncherDefaults
            ReviewDefaults.current = nil
            defaults.removePersistentDomain(forName: domain)
            QuickLauncherService.shared = QuickLauncherContract.Launcher()
            NotchTimerService.shared = Timer()
        }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        let focus = Service()
        focus.showsKeyboardFocus = true
        focus.open(.controls)
        suite.expect(!focus.showsKeyboardFocus, "reopening the island clears the previous automatic focus indicator")
        focus.showsKeyboardFocus = true
        focus.open(.music)
        suite.expect(focus.showsKeyboardFocus, "changing pages in the open island preserves keyboard focus visibility")
        focus.collapse()
        focus.open(.controls, takeFocus: false)
        suite.expect(!focus.showsKeyboardFocus, "hover opening starts without an automatic focus indicator")
        scratchpadContracts(defaults: defaults, suite: suite)
        reopeningContracts(defaults: defaults, suite: suite)
        clipboardShortcutDestinationContracts(defaults: defaults, suite: suite)
        countdownContracts(defaults: defaults, suite: suite)
        stepBackContracts(suite)
        // A page opened while the Command Bar is in the island takes its place.
        let barHost = Service()
        barHost.expanded = true
        barHost.showingCommandBar = true
        barHost.modules = NotchSupport.modules(in: defaults)
        barHost.open(.controls)
        suite.expect(barHost.expanded && !barHost.showingCommandBar && barHost.selected == .controls
                     && barHost.commandBarClosings == 1,
                     "opening a page in place of the Command Bar closes the bar once")
        barHost.open(.controls)
        suite.expect(barHost.commandBarClosings == 1, "opening a page without the bar leaves the bar alone")
        for resting in [NotchIdleContent.none, .music] {
            defaults.set(resting.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            let service = Service()
            service.open(.music)
            suite.expect(service.expanded && service.selected == .music && service.panel?.acceptsKeyFocus == true,
                   "hiding automatic music preserves explicit opening of its controls")
            service.open(.controls)
            suite.expect(service.expanded && service.selected == .controls
                   && NotchSupport.controls(in: defaults).contains(.music),
                   "hiding automatic music preserves playback controls on the island's home page")
        }
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        let families: [(MetricDetailKind, AppFeature)] = [
            (.cpu, .monitorCPU), (.gpu, .monitorGPU), (.memory, .monitorMemory),
            (.network, .monitorNetwork), (.disk, .monitorDisk),
            (.battery, .monitorPower), (.power, .monitorPower), (.fan, .fanControl),
            (.connectedDevices, .connectedDevices),
        ]
        for (metric, feature) in families {
            let service = Service()
            service.open(.system, pinned: true, metric: metric)
            suite.expect(service.selectedMetric == metric, "an available metric opens its own detail")
            defaults.set(false, forKey: feature.availabilityKey)
            service.syncWithPreferences()
            suite.expect(service.selectedMetric == nil && service.requestedDetail == nil,
                   "removing the selected metric clears its detail even when other system families remain")
            service.open(.system, metric: metric, sections: true)
            service.open(.system, metric: metric)
            suite.expect(service.selectedMetric == nil,
                   "a retained gallery argument cannot restore a metric removed from the hub")
            defaults.set(true, forKey: feature.availabilityKey)
        }
        let service = Service()
        service.open(.system, metric: .cpu)
        for (_, feature) in families { defaults.set(false, forKey: feature.availabilityKey) }
        service.syncWithPreferences()
        suite.expect(!service.modules.contains(.system) && service.selected == .controls
               && service.selectedMetric == nil && service.requestedDetail == nil,
               "removing the last system family selects an available module without keeping its old detail")
        defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
        service.open(.system, metric: .fan)
        suite.expect(service.modules.contains(.system) && service.selectedMetric == .fan,
               "a separately installed fan feature exposes System and retains its direct detail")

        QuickLauncherService.shared = QuickLauncherContract.Launcher()
        let launcher = QuickLauncherService.shared
        let firstPresentation = launcher.presentationID
        service.open(.tools)
        suite.expect(service.selected == .tools && launcher.selectedIndex == 0 && launcher.presentationID != firstPresentation,
               "opening Tools inside the island prepares keyboard selection on its first presentation")
        QuickLauncherContract.events.removeAll()
        let enter = QuickLauncherContract.NSEvent(keyCode: UInt16(kVK_Return))
        suite.expect(launcher.handlePanelKey(enter, flow: .columns(rows: 2)) == nil
               && QuickLauncherContract.events == ["keepAwake.toggle"],
               "Return works immediately after the island opens Tools")
        let unchangedPresentation = launcher.presentationID
        service.open(.tools)
        suite.expect(launcher.presentationID == unchangedPresentation,
               "reopening the same visible Tools destination does not reset its working presentation")
        launcher.activeUtility = .urlCleaner
        service.open(.controls)
        service.open(.tools)
        suite.expect(launcher.activeUtility == .urlCleaner,
               "navigation preserves a still-available hosted utility")
        service.open(.controls)
        defaults.set(false, forKey: AppFeature.urlCleaner.availabilityKey)
        service.open(.tools)
        suite.expect(launcher.activeUtility == nil,
               "returning to Tools after removal cannot revive its previous utility")
        service.open(.controls)
        launcher.candidates = []
        service.open(.tools)
        suite.expect(launcher.selectedIndex == nil, "an empty Tools module leaves keyboard activation without a target")
        sessionContracts(suite)
        lockScreenContracts(defaults: defaults, suite: suite)
        shortcutContracts(defaults: defaults, suite: suite)
        captureControlsContracts(suite)
    }

    /// The capture controls cover the open page and hold collapsing off. While
    /// they are up, a route that opens the island expands them instead, so no
    /// page waits behind them to open by itself once they end.
    private static func captureControlsContracts(_ suite: TestSuite) {
        let shortcuts: [(String, NotchModule, (Service) -> Bool)] = [
            ("Clipboard", .clipboard, { $0.showClipboard(toggle: true) }),
            ("Scratchpad", .scratchpad, { $0.showScratchpad(toggle: true) }),
            ("quick panel", .tools, { $0.openQuickPanel(toggle: true) }),
            ("shelf", .files, { $0.openShelf(toggle: true) }),
        ]
        for (name, module, press) in shortcuts {
            let service = Service()
            service.captureControls = NSObject()
            let presses = (0..<2).map { _ in press(service) && !service.expanded }
            suite.expect(presses == [true, true] && service.captureControlsExpansions == 2,
                         "the \(name) shortcut expands the capture controls on every press instead of opening the island behind them")
            service.captureControls = nil
            suite.expect(press(service) && service.expanded && service.selected == module,
                         "once the capture controls end, the \(name) shortcut opens its page")
        }
        let page = Service()
        page.captureControls = NSObject()
        page.open(.music)
        suite.expect(!page.expanded && page.captureControlsExpansions == 1,
                     "opening a page while the capture controls are up expands them instead")
    }

    /// Escape steps back through what the island shows, then closes it.
    private static func stepBackContracts(_ suite: TestSuite) {
        let metric = Service()
        metric.open(.system)
        metric.open(.system, metric: .cpu)
        metric.stepBack()
        suite.expect(metric.expanded && metric.selected == .system && metric.selectedMetric == nil,
                     "Escape steps back from a detail opened on its page, as the Back button does")
        metric.stepBack()
        suite.expect(!metric.expanded, "Escape closes the island once nothing lies behind the page")

        let panel = Service()
        panel.open(.music)
        panel.open(.controls, appPanel: true)
        panel.stepBack()
        suite.expect(panel.expanded && panel.selected == .controls && !panel.showingAppPanel,
                     "Escape steps back from the app panel opened inside the island")

        // Closing passes for any page, so these first check a detail is open.
        for appPanel in [false, true] {
            let direct = Service()
            direct.open(appPanel ? .controls : .system, appPanel: appPanel, metric: appPanel ? nil : .cpu)
            let detail = direct.showingAppPanel || direct.selectedMetric == .cpu
            direct.stepBack()
            suite.expect(detail && !direct.expanded,
                         "a detail the island opened on closes on Escape like the menu panel (app panel: \(appPanel))")
        }

        for route in ["a metric", "the app panel"] {
            let menuBar = Service()
            menuBar.open(.music)
            if route == "a metric" { menuBar.showMetric(.cpu, toggle: true) } else { menuBar.openAppPanel(toggle: true) }
            let detail = menuBar.selectedMetric == .cpu || menuBar.showingAppPanel
            menuBar.stepBack()
            suite.expect(detail && !menuBar.expanded,
                         "\(route) opened from the menu bar over an open island closes on Escape like the menu panel")
        }
        let tile = Service()
        tile.open(.system)
        tile.showMetric(.cpu)
        tile.stepBack()
        suite.expect(tile.expanded && tile.selected == .system && tile.selectedMetric == nil,
                     "a metric opened from its tile inside the island steps back to the page")

        let switched = Service()
        switched.open(.system, metric: .cpu)
        switched.toggleSections()
        switched.toggleSections()
        switched.open(.system, metric: .memory)
        let switchedDetail = switched.selectedMetric == .memory && !switched.showingSections
        switched.stepBack()
        suite.expect(switchedDetail && !switched.expanded,
                     "passing through the gallery or switching details keeps a direct detail closing on Escape")

        let gallery = Service()
        gallery.open(.system)
        gallery.open(.system, metric: .cpu)
        gallery.toggleSections()
        gallery.toggleSections()
        gallery.stepBack()
        suite.expect(gallery.expanded && gallery.selected == .system && gallery.selectedMetric == nil,
                     "the gallery opened over a detail keeps its way back to the page")

        let reopened = Service()
        reopened.open(.system)
        reopened.open(.system, metric: .cpu)
        // Capture controls close the island without clearing its detail.
        reopened.expanded = false
        reopened.open(.system, metric: .cpu)
        let reopenedDetail = reopened.expanded && reopened.selectedMetric == .cpu
        reopened.stepBack()
        suite.expect(reopenedDetail && !reopened.expanded, "a detail the island reopens on has nothing behind it")

        var closes: [NotchModule] = []
        let layered = Service()
        layered.open(.music)
        layered.setPageLayer(.music) { closes.append(.music); layered.setPageLayer(.music, close: nil) }
        layered.setPageLayer(.calendar) { closes.append(.calendar) }
        layered.stepBack()
        suite.expect(layered.expanded && closes == [.music], "Escape closes the page's own layer before the island")
        layered.stepBack()
        suite.expect(!layered.expanded && closes == [.music], "only the visible page's layer answers Escape")

        let previewLayer = Service()
        previewLayer.open(.clipboard)
        var previewCloses = 0
        var searchCloses = 0
        previewLayer.setPageLayer(.clipboard) { searchCloses += 1 }
        previewLayer.clipboardPreviewClose = {
            previewCloses += 1
            previewLayer.clipboardPreviewClose = nil
        }
        previewLayer.stepBack()
        suite.expect(previewLayer.expanded && previewCloses == 1 && searchCloses == 0,
                     "Escape closes the attached clipboard preview before the page's search or the island")
        previewLayer.clipboardPreviewClose = { previewCloses += 1 }
        previewLayer.open(.system)
        suite.expect(previewCloses == 2 && previewLayer.clipboardPreviewClose == nil && previewLayer.selected == .system,
                     "changing island pages closes the clipboard preview instead of carrying it onto another module")

        let covered = Service()
        covered.open(.system)
        covered.setPageLayer(.system) { closes.append(.system) }
        covered.open(.system, metric: .cpu)
        covered.stepBack()
        suite.expect(covered.selectedMetric == nil && closes == [.music],
                     "a detail steps back before a layer of the page it covers")

        for blocker in ["drag", "capture"] {
            let held = Service()
            held.open(.system)
            held.open(.system, metric: .cpu)
            if blocker == "drag" { held.heldDrag = true } else { held.captureControls = NSObject() }
            held.stepBack()
            suite.expect(held.expanded && held.selectedMetric == .cpu,
                         "Escape leaves the island as it is during a \(blocker), like closing does")
        }
    }

    /// The island resigns by hand while it stays on screen. The keyboard goes
    /// back to a regular Vorssaint window only while Vorssaint is in front.
    private static func keyHandoffContracts(suite: TestSuite) {
        let vorssaint = RunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        /// Returns the windows that were made key, front to back.
        func handoff(frontmost: RunningApplication?, keyIsPanel: Bool = true, settingsVisible: Bool = true,
                     settingsIsRegular: Bool = true, otherSpaceInFront: Bool = false,
                     regularBehind: Bool = false) -> [String] {
            let service = Service()
            guard let panel = service.panel else { return ["no panel"] }
            let hidden = Panel(), otherSpace = Panel(), helper = Panel(), settings = Panel(), behind = Panel()
            for window in [hidden, otherSpace, behind] { window.canBecomeMain = true }
            hidden.isVisible = false
            otherSpace.isOnActiveSpace = false
            settings.canBecomeMain = settingsIsRegular
            settings.isVisible = settingsVisible
            let named = [("hidden", hidden), ("other Space", otherSpace), ("helper", helper),
                         ("settings", settings), ("behind", behind)]
                .filter { $0.0 != "other Space" || otherSpaceInFront }
                .filter { $0.0 != "behind" || regularBehind }
            NSApp.orderedWindows = [panel] + named.map(\.1)
            NSApp.keyWindow = keyIsPanel ? panel : nil
            NSWorkspace.shared.frontmostApplication = frontmost
            service.resignPanelKey()
            defer {
                NSApp.orderedWindows = []
                NSApp.keyWindow = nil
                NSWorkspace.shared.frontmostApplication = nil
            }
            guard !panel.isKeyWindow else { return ["island"] }
            return named.flatMap { name, window in Array(repeating: name, count: window.keyRequests) }
        }
        suite.expect(handoff(frontmost: vorssaint) == ["settings"],
                     "closing the island hands the keyboard back to Settings while Vorssaint stays active")
        suite.expect(handoff(frontmost: vorssaint, otherSpaceInFront: true, regularBehind: true) == ["settings"],
                     "closing the island hands the keyboard to the frontmost regular window on this Space")
        suite.expect(handoff(frontmost: RunningApplication(processIdentifier: 1)).isEmpty,
                     "closing the island leaves the keyboard alone while another app takes over")
        suite.expect(handoff(frontmost: vorssaint, keyIsPanel: false).isEmpty,
                     "closing the island hands nothing over once AppKit has let it go")
        suite.expect(handoff(frontmost: vorssaint, settingsVisible: false).isEmpty
                     && handoff(frontmost: vorssaint, settingsIsRegular: false).isEmpty,
                     "closing the island hands the keyboard only to a visible regular window")
    }

    private static func scratchpadContracts(defaults: UserDefaults, suite: TestSuite) {
        let service = Service()
        suite.expect(service.showScratchpad(toggle: true) && service.expanded && service.selected == .scratchpad,
                     "the Scratchpad shortcut opens its configured island destination")
        service.panel?.isKeyWindow = false
        suite.expect(service.showScratchpad(toggle: true) && service.expanded,
                     "a visible Scratchpad without keyboard focus is focused instead of closed")
        service.panel?.isKeyWindow = true
        suite.expect(service.showScratchpad(toggle: true) && !service.expanded,
                     "the shortcut closes a Scratchpad that already owns the keyboard")
        keyHandoffContracts(suite: suite)
        // While Vorssaint stays the active app, collapse() resigns by hand: the
        // flag clears, AppKit keeps the island key, and makeKey changes neither.
        NSApp.keyWindow = service.panel
        service.panel?.isKeyWindow = false
        _ = service.showScratchpad(toggle: true)
        suite.expect(service.showScratchpad(toggle: true) && !service.expanded,
                     "the shortcut closes a reopened Scratchpad AppKit still keeps as its key window")
        NSApp.keyWindow = Panel()
        _ = service.showScratchpad(toggle: true)
        suite.expect(service.showScratchpad(toggle: true) && service.expanded,
                     "a Scratchpad is focused, not closed, while another window holds the keyboard")
        NSApp.keyWindow = nil
        service.collapse()
        let detached = Service()
        _ = detached.showScratchpad(toggle: true)
        detached.panel = nil
        suite.expect(detached.showScratchpad(toggle: true) && detached.expanded,
                     "an island without a panel is never taken for the key window")
        service.panel?.isKeyWindow = true
        defaults.set(false, forKey: DefaultsKey.notchScratchpad)
        suite.expect(!service.showScratchpad() && !service.expanded,
                     "choosing a separate Scratchpad window leaves the island untouched")
        defaults.set(true, forKey: DefaultsKey.notchScratchpad)
        service.hiddenInFullscreen = true
        suite.expect(service.showScratchpad() && service.expanded,
                     "a full-screen user shortcut opens Scratchpad despite hidden automatic feedback")
        service.collapse()
        service.acceptsUserInteraction = false
        suite.expect(!service.showScratchpad() && !service.expanded,
                     "an unavailable island hands Scratchpad opening back to its ordinary window")
    }

    private static func reopeningContracts(defaults: UserDefaults, suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchReturnHome] as? Bool == false,
               "returning home is opt-in and preserves the existing opening behavior")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHomeModule] as? String == NotchModule.controls.rawValue,
               "the previously available home option keeps Controls as its initial destination")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchOpensActivity] as? Bool == true,
               "opening the visible activity stays the default")
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            let payload = SettingsBackupSupport.payload(appVersion: "test") {
                if $0 == DefaultsKey.notchReturnHome { return returnHome }
                if $0 == DefaultsKey.notchHomeModule { return NotchModule.music.rawValue }
                if $0 == DefaultsKey.notchOpensActivity { return false }
                if $0 == DefaultsKey.notchHideUntilHover { return true }
                if $0 == DefaultsKey.notchHoverDelay { return 0.65 }
                if $0 == DefaultsKey.notchCloseDelay { return 1.5 }
                return nil
            }
            let data = try? JSONSerialization.data(withJSONObject: payload)
            let decoded = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let restored = decoded.flatMap { SettingsBackupSupport.sanitizedSettings(from: $0) }
            suite.expect(restored?[DefaultsKey.notchReturnHome] as? Bool == returnHome
                   && restored?[DefaultsKey.notchHomeModule] as? String == NotchModule.music.rawValue
                   && restored?[DefaultsKey.notchOpensActivity] as? Bool == false
                   && restored?[DefaultsKey.notchHoverDelay] as? Double == 0.65
                   && restored?[DefaultsKey.notchCloseDelay] as? Double == 1.5
                   && restored?[DefaultsKey.notchHideUntilHover] as? Bool == true,
                   "the opening behavior, selected page, activity choice and hover timings survive backup and restore")

            let service = Service()
            service.open(.files)
            service.open()
            suite.expect(service.selected == .files, "an already open island does not jump away from the current page")
            service.expanded = false
            service.open()
            suite.expect(service.selected == (returnHome ? .controls : .files),
                   "reopening either restores the last page or returns home according to the preference")
            service.expanded = false
            service.open(.music)
            suite.expect(service.selected == .music, "an explicit destination always wins over the opening preference")
            defaults.set("controls", forKey: DefaultsKey.notchHiddenModules)
            defaults.set("files,music", forKey: DefaultsKey.notchModuleOrder)
            service.expanded = false
            service.open()
            suite.expect(service.selected == (returnHome ? .files : .music),
                   "a hidden home page falls back to the first visible page without unhiding controls")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
            defaults.set("", forKey: DefaultsKey.notchModuleOrder)
        }
        defaults.set(true, forKey: DefaultsKey.notchReturnHome)
        for page in NotchSupport.modules(in: defaults) {
            defaults.set(page.rawValue, forKey: DefaultsKey.notchHomeModule)
            let service = Service()
            service.open()
            suite.expect(service.selected == page, "each available page can be chosen for reopening: \(page.rawValue)")
            service.open(.files)
            suite.expect(service.selected == .files, "a saved opening page never overrides explicit navigation")
            defaults.set(page.rawValue, forKey: DefaultsKey.notchHiddenModules)
            service.expanded = false
            service.open()
            suite.expect(service.selected == NotchSupport.modules(in: defaults).first,
                   "hiding the saved opening page falls back to an available page")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        }
        for destination in NotchReopeningDestination.allCases {
            defaults.set(destination.rawValue, forKey: DefaultsKey.notchHomeModule)
            let service = Service()
            service.open(.files)
            service.expanded = false
            let focusRequests = MenuPanelFocus.shared.normalRequests
            service.open()
            suite.expect(service.showingAppPanel == (destination == .appPanel)
                   && service.showingSections == (destination == .explore),
                   "reopening shows the selected app panel or Explore destination")
            if destination == .explore {
                suite.expect(service.highlightedSection == .files && service.sectionQuery.isEmpty,
                       "reopening Explore highlights its current page for keyboard navigation")
            }
            suite.expect(MenuPanelFocus.shared.normalRequests - focusRequests == (destination == .appPanel ? 1 : 0),
                   "only opening the app panel resets its panel focus")
            service.expanded = false
            service.open(.music)
            suite.expect(service.selected == .music && !service.showingAppPanel && !service.showingSections,
                   "explicit page navigation wins over a saved app panel or Explore destination")

            service.expanded = false
            service.compactActivity = .timer
            service.open()
            suite.expect(service.selected == .timer && !service.showingAppPanel && !service.showingSections,
                   "a visible activity wins over a saved app panel or Explore destination")

            defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
            service.expanded = false
            service.open()
            suite.expect(service.showingAppPanel == (destination == .appPanel)
                   && service.showingSections == (destination == .explore),
                   "with activities turned off, a visible activity leaves the saved app panel or Explore destination")
            service.expanded = false
            service.openActivity(.timer)
            suite.expect(service.showingAppPanel == (destination == .appPanel)
                   && service.showingSections == (destination == .explore),
                   "with activities turned off, a tap on the activity's strip follows the reopening choice too")
            defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
            service.expanded = false
            service.openActivity(.timer)
            suite.expect(service.selected == .timer && !service.showingAppPanel && !service.showingSections,
                   "a tap on the activity's strip opens its page while activities open")
        }
        defaults.set("unknown-page", forKey: DefaultsKey.notchHomeModule)
        let invalid = Service()
        invalid.open()
        suite.expect(invalid.selected == .controls, "a malformed saved page falls back to Controls")
        defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
        activityContracts(defaults: defaults) { suite.expect($0, $1) }
    }

    private static func clipboardShortcutDestinationContracts(defaults: UserDefaults, suite: TestSuite) {
        let keys = [DefaultsKey.notchReturnHome, DefaultsKey.notchHomeModule, DefaultsKey.notchOpensActivity,
                    DefaultsKey.notchHiddenModules, DefaultsKey.notchModuleOrder]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
        defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set("", forKey: DefaultsKey.notchModuleOrder)

        for alreadyOpen in [false, true] {
            let service = Service()
            service.open(.files)
            if !alreadyOpen { service.collapse() }
            suite.expect(service.showClipboard(toggle: true) && service.expanded && service.selected == .clipboard,
                         "the history shortcut visits Clipboard from an open or collapsed island")
            service.collapse()
            suite.expect(service.reopeningModule == .files,
                         "closing shortcut history preserves the previous page for the next ordinary opening")
            service.open()
            suite.expect(service.expanded && service.selected == .files,
                         "the next ordinary opening returns to the page before shortcut history")
        }

        let repeated = Service()
        repeated.open(.music)
        repeated.collapse()
        for _ in 0..<3 {
            _ = repeated.showClipboard(toggle: true)
            _ = repeated.showClipboard(toggle: true)
            suite.expect(!repeated.expanded && repeated.reopeningModule == .music,
                         "repeated history shortcut toggles cannot replace the remembered page with Clipboard")
        }
        _ = repeated.showClipboard(toggle: true)
        repeated.open(.timer)
        repeated.collapse()
        repeated.open()
        suite.expect(repeated.selected == .timer,
                     "explicit page navigation after shortcut history becomes the next opening destination")
        _ = repeated.showClipboard(toggle: true)
        repeated.open(.clipboard)
        repeated.collapse()
        repeated.open()
        suite.expect(repeated.selected == .clipboard,
                     "explicitly choosing Clipboard after the shortcut remembers Clipboard normally")

        let direct = Service()
        direct.open(.files)
        _ = direct.showClipboard()
        direct.collapse()
        direct.open()
        suite.expect(direct.selected == .clipboard,
                     "the regular Clipboard route retains its existing remembered-page behavior")

        let peek = Service()
        peek.open(.files)
        _ = peek.showClipboard(toggle: true)
        peek.collapse()
        peek.peeking = true
        suite.expect(peek.reopeningModule == .files,
                     "a peek after shortcut history names the page that an ordinary opening will return to")
        peek.toggleSections()
        suite.expect(peek.expanded && peek.showingSections && peek.selected == .files && peek.highlightedSection == .files,
                     "Explore opened from the peek highlights the remembered page rather than temporary Clipboard")

        let visible = Service()
        visible.open(.files)
        _ = visible.showClipboard(toggle: true)
        visible.toggleSections()
        suite.expect(visible.showingSections && visible.highlightedSection == .clipboard,
                     "Explore opened from visible shortcut history still highlights its current Clipboard page")

        let hidden = Service()
        hidden.open(.music)
        _ = hidden.showClipboard(toggle: true)
        hidden.collapse()
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        hidden.open()
        suite.expect(hidden.selected == NotchSupport.modules(in: defaults).first,
                     "a previous page hidden during shortcut history falls back to an available page")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)

        for destination in [NotchModule.timer.rawValue, NotchReopeningDestination.explore.rawValue] {
            defaults.set(true, forKey: DefaultsKey.notchReturnHome)
            defaults.set(destination, forKey: DefaultsKey.notchHomeModule)
            let home = Service()
            home.open(.files)
            home.collapse()
            _ = home.showClipboard(toggle: true)
            home.collapse()
            home.open()
            suite.expect(destination == NotchModule.timer.rawValue ? home.selected == .timer
                         : home.showingSections && home.highlightedSection == .files,
                         "shortcut history preserves a configured home destination and Explore's previous-page highlight")
        }
    }

    /// A click on the event countdown leaves its event for the Calendar page
    /// only when that page is what opens.
    private static func countdownContracts(defaults: UserDefaults, suite: TestSuite) {
        let keys = [DefaultsKey.notchOpensActivity, DefaultsKey.notchReturnHome, DefaultsKey.notchHomeModule,
                    DefaultsKey.notchHiddenModules, DefaultsKey.notchModuleOrder]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
            NotchCalendarService.shared = CountdownCalendar()
        }
        let start = Date(timeIntervalSinceNow: 600)
        let event = NotchCalendarEvent(id: "event", title: "Review", calendar: "Work", start: start,
                                       end: start.addingTimeInterval(1800), allDay: false, location: "")
        NotchCalendarService.shared.countdown = NotchCalendarCountdown(event: event, ongoing: false)
        let service = Service()
        service.openCountdownEvent()
        suite.expect(service.expanded && service.selected == .calendar && NotchCalendarService.shared.revealing == event.id,
                     "a click on the event countdown opens Calendar on its event")
        defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
        defaults.set(true, forKey: DefaultsKey.notchReturnHome)
        // Controls hidden and Calendar first: the app panel opens with Calendar still selected.
        defaults.set("controls", forKey: DefaultsKey.notchHiddenModules)
        defaults.set("calendar", forKey: DefaultsKey.notchModuleOrder)
        for destination in NotchReopeningDestination.allCases {
            defaults.set(destination.rawValue, forKey: DefaultsKey.notchHomeModule)
            service.expanded = false
            service.selected = .calendar
            NotchCalendarService.shared.revealing = nil
            service.openCountdownEvent()
            suite.expect(service.expanded && service.selected == .calendar
                         && (service.showingSections || service.showingAppPanel)
                         && NotchCalendarService.shared.revealing == nil,
                         "with activities turned off, \(destination.rawValue) opened in Calendar's place keeps no event for later")
        }
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set("", forKey: DefaultsKey.notchModuleOrder)
        defaults.set(NotchModule.calendar.rawValue, forKey: DefaultsKey.notchHomeModule)
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            service.expanded = false
            service.selected = returnHome ? .controls : .calendar
            NotchCalendarService.shared.revealing = nil
            service.openCountdownEvent()
            suite.expect(service.selected == .calendar && !service.showingSections && !service.showingAppPanel
                         && NotchCalendarService.shared.revealing == event.id,
                         "with activities turned off, Calendar reopened as the last or saved page keeps its event")
        }
    }

    /// What the closed island is already showing is what opening it shows,
    /// unless the user turned that off for activities.
    private static func activityContracts(defaults: UserDefaults, expect: (Bool, String) -> Void) {
        let banner = NotchNotice(event: .systemNotification, title: "Alex", detail: "Hello", symbol: "bell.fill",
                                 notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: "Hello"),
                                 notificationID: UUID())
        defaults.set(true, forKey: DefaultsKey.notchNotificationsEnabled)
        defer { defaults.set(false, forKey: DefaultsKey.notchNotificationsEnabled) }
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
            for activity in [NotchCompactActivity.timer, .downloads, .calendar, .music, .keepAwake] {
                let service = Service()
                service.open(.files)
                service.expanded = false
                service.compactActivity = activity
                expect(service.reopeningModule == activity.module, "a visible activity is what a peek names before opening")
                service.open()
                expect(service.selected == activity.module,
                       "hovering or clicking an island that shows \(activity) opens that activity, not the reopening page")
                service.open()
                expect(service.selected == activity.module, "an already open island stays on the activity's page")
                service.open(.files)
                expect(service.selected == .files, "an explicit page still wins over the visible activity")
                service.expanded = false
                service.compactActivity = nil
                service.open()
                expect(service.selected == (returnHome ? .controls : .files),
                       "once the activity ends, reopening follows the saved preference again")

                defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
                service.open(.files)
                service.expanded = false
                service.compactActivity = activity
                expect(service.reopeningModule == (returnHome ? .controls : .files),
                       "with activities turned off, a peek over \(activity) names the reopening page")
                service.open()
                expect(service.selected == (returnHome ? .controls : .files),
                       "with activities turned off, opening an island that shows \(activity) follows the saved preference")
                service.open(activity.module)
                expect(service.selected == activity.module,
                       "with activities turned off, the page of \(activity) still opens when named")
                defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
            }
            let hidden = Service()
            defaults.set("timer", forKey: DefaultsKey.notchHiddenModules)
            hidden.syncWithPreferences()
            hidden.compactActivity = .timer
            hidden.open()
            expect(hidden.selected == .controls && !hidden.modules.contains(.timer),
                   "an activity whose page is hidden cannot open it and falls back to the reopening rule")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)

            let mirrored = Service()
            mirrored.syncWithPreferences()
            mirrored.notice = banner
            mirrored.noticeExpanded = true
            mirrored.noticeWork = DispatchWorkItem {}
            expect(mirrored.reopeningModule == .notifications, "a mirrored banner on the island points at the inbox")
            mirrored.open()
            expect(mirrored.selected == .notifications && mirrored.notice == nil && !mirrored.noticeExpanded
                   && mirrored.noticeWork == nil,
                   "opening over a held banner shows the inbox and retires the banner so it cannot return after collapsing")
            defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
            let bannerOverMusic = Service()
            bannerOverMusic.syncWithPreferences()
            bannerOverMusic.compactActivity = .music
            bannerOverMusic.notice = banner
            bannerOverMusic.open()
            expect(bannerOverMusic.selected == .notifications && bannerOverMusic.notice == nil,
                   "turning activities off still opens the inbox over a mirrored banner, which is not an activity")
            defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
            let volume = Service()
            volume.notice = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill", level: 0.5)
            volume.open()
            expect(volume.notice != nil && volume.selected == .controls,
                   "system feedback keeps its own timer and never redirects an opening")
        }
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
    }

    /// The lock screen follows the island's own teardown, so what it starts is
    /// never stopped under it. On unlock it starts leaving before the island
    /// returns and stops nothing the island takes back. The padlock plays only
    /// for a lock or unlock made at the Mac.
    private static func lockScreenContracts(defaults: UserDefaults, suite: TestSuite) {
        defer {
            NotchLockScreenService.shared = LockScreen()
            defaults.set(false, forKey: DefaultsKey.notchLockSounds)
        }
        let service = Service()
        let lockScreen = LockScreen()
        NotchLockScreenService.shared = lockScreen
        var order: [String] = []
        lockScreen.onSync = { order.append("sync after \(service.presentationTearDowns) teardowns, \(service.presentationSyncs) returns") }
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        service.updateSession { $0.locked = true }
        suite.expect(order == ["sync after 1 teardowns, 0 returns"] && lockScreen.syncs.last?.showsLockScreen == true,
                     "the lock screen takes over after the island has stopped its own sources")
        service.updateSession { $0.locked = false }
        // The first sync is the scene leaving: canPresent tells it to stop
        // none of the sources the island is about to take back.
        suite.expect(order == ["sync after 1 teardowns, 0 returns", "sync after 1 teardowns, 0 returns",
                               "sync after 1 teardowns, 1 returns"]
                     && lockScreen.syncs.count == 3 && lockScreen.syncs.dropFirst().allSatisfy { !$0.locked && $0.canPresent },
                     "on unlock the lock screen starts leaving before the island returns and stops nothing it takes back")
        suite.expect(lockScreen.sounds == [true, false], "locking and unlocking at the Mac each play their padlock")
        service.updateSession { $0.displaysSleeping = true }
        service.updateSession { $0.locked = true }
        suite.expect(lockScreen.sounds == [true, false] && lockScreen.syncs.last?.showsLockScreen == false,
                     "a lock that comes with a dark display plays nothing and shows nothing")
        service.updateSession { $0.displaysSleeping = false }
        suite.expect(lockScreen.syncs.last?.showsLockScreen == true, "waking the display shows the lock screen")
        service.updateSession { $0.screenSaverRunning = true }
        suite.expect(lockScreen.syncs.last?.showsLockScreen == false && lockScreen.sounds.count == 2,
                     "a screen saver hides the lock screen without a sound")
        service.updateSession { $0.screenSaverRunning = false }
        defaults.set(false, forKey: DefaultsKey.notchLockSounds)
        service.updateSession { $0.locked = false }
        suite.expect(lockScreen.sounds.count == 2, "with the sounds off, unlocking is silent")
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        service.updateSession { $0.locked = true }
        service.updateSession { $0.displaysSleeping = true }
        service.updateSession { $0.locked = false }
        service.updateSession { $0.displaysSleeping = false }
        suite.expect(lockScreen.sounds == [true, false, true, false],
                     "an unlock announced before the display wakes still plays its padlock")
        service.running = false
        let syncs = lockScreen.syncs.count
        service.updateSession { $0.locked = true }
        suite.expect(lockScreen.syncs.count == syncs && lockScreen.sounds.count == 4,
                     "a stopped island leaves the lock screen alone")
    }

    private static func sessionContracts(_ suite: TestSuite) {
        let service = Service()
        NotchTimerService.shared = Timer()
        let timer = NotchTimerService.shared
        // The production branch reads the brightness feature from the app's
        // own defaults; keep it installed for these checks only.
        let brightnessKey = AppFeature.brightness.availabilityKey
        let previousBrightness = UserDefaults.standard.object(forKey: brightnessKey)
        UserDefaults.standard.set(true, forKey: brightnessKey)
        defer {
            if let previousBrightness {
                UserDefaults.standard.set(previousBrightness, forKey: brightnessKey)
            } else {
                UserDefaults.standard.removeObject(forKey: brightnessKey)
            }
        }
        BrightnessService.shared = Brightness()
        service.updateSession { $0.displaysSleeping = true }
        suite.expect(timer.running && timer.suspensions == 0 && timer.syncs == 0
               && service.presentationTearDowns == 1 && !service.session.canPresent,
               "display sleep removes presentation while leaving the timer and alarm uninterrupted")
        suite.expect(BrightnessService.shared.syncs == 1,
               "the brightness keys go back to the system while the island is torn down")
        service.updateSession { $0.sleeping = true }
        suite.expect(!timer.running && timer.suspensions == 1 && service.presentationTearDowns == 1,
               "system sleep suspends the timer even after the display already hid the island")
        service.updateSession { $0.locked = true }
        service.updateSession { $0.displaysSleeping = false }
        service.updateSession { $0.sleeping = false }
        suite.expect(!timer.running && timer.syncs == 0 && service.presentationSyncs == 0,
               "display and system wake cannot resume an alarm or presentation while the session is locked")
        service.updateSession { $0.locked = false }
        suite.expect(timer.running && timer.syncs == 1 && service.presentationSyncs == 1,
               "unlocking after every sleep condition clears resumes through the normal presentation path once")

        service.updateSession { $0.displaysSleeping = true }
        service.updateSession { $0.onConsole = false }
        suite.expect(!timer.running && timer.suspensions == 2,
               "switching users suspends an alarm even when the display is already asleep")
        service.updateSession { $0.onConsole = true }
        suite.expect(timer.running && timer.syncs == 2 && service.presentationSyncs == 1 && !service.session.canPresent,
               "returning to the same awake session resumes only the timer while its display remains asleep")
        service.updateSession { $0.displaysSleeping = false }
        suite.expect(timer.running && service.presentationSyncs == 2,
               "the island returns only after the display also wakes")
        service.updateSession { $0.displaysSleeping = true }
        service.updateSession { $0.locked = true }
        service.updateSession { $0.onConsole = false }
        service.updateSession { $0.locked = false }
        service.updateSession { $0.displaysSleeping = false }
        suite.expect(!timer.running && service.presentationSyncs == 2,
               "unlock and display wake cannot resume work while another login session owns the console")
        service.running = false
        service.updateSession { $0.onConsole = true }
        suite.expect(!timer.running && service.presentationSyncs == 2,
               "late session notifications cannot restart a stopped island or timer")
    }

    /// Like a click on the closed island, the shortcut expands the capture
    /// controls while they are up and otherwise toggles the island. It holds its
    /// key only while it is on and no other shortcut is recording.
    private static func shortcutContracts(defaults: UserDefaults, suite: TestSuite) {
        defer {
            ShortcutCapture.isCapturing = false
            defaults.set(false, forKey: DefaultsKey.notchShortcutEnabled)
        }
        func pressed(captureControls: Bool = false, interactive: Bool = true, presses: Int = 1) -> Service {
            let service = Service()
            service.installHotkey()
            if captureControls { service.captureControls = NSObject() }
            service.acceptsUserInteraction = interactive
            for _ in 0..<presses { service.hotkey.onPress?() }
            return service
        }
        let capture = pressed(captureControls: true)
        suite.expect(capture.captureControlsExpansions == 1 && !capture.expanded,
                     "the island shortcut expands the capture controls instead of opening the island behind them")
        let away = [pressed(interactive: false), pressed(captureControls: true, interactive: false)]
        suite.expect(away.allSatisfy { !$0.expanded && $0.captureControlsExpansions == 0 },
                     "the island shortcut does nothing while the island does not accept user interaction")
        suite.expect(pressed().expanded && !pressed(presses: 2).expanded,
                     "the island shortcut opens the island and a second press closes it")

        let registration = Service()
        defaults.set(true, forKey: DefaultsKey.notchShortcutEnabled)
        registration.syncShortcut()
        ShortcutCapture.isCapturing = true
        registration.syncShortcut()
        ShortcutCapture.isCapturing = false
        registration.syncShortcut()
        defaults.set(false, forKey: DefaultsKey.notchShortcutEnabled)
        registration.syncShortcut()
        suite.expect(registration.hotkey.requests == [true, false, true, false],
                     "the island shortcut lets its key go while another shortcut is recording and while it is off")
        let refused = Service()
        refused.hotkey.refuses = true
        defaults.set(true, forKey: DefaultsKey.notchShortcutEnabled)
        refused.syncShortcut()
        refused.syncShortcut()
        let failed = refused.shortcutRegistrationFailed
        defaults.set(false, forKey: DefaultsKey.notchShortcutEnabled)
        refused.syncShortcut()
        refused.syncShortcut()
        suite.expect(failed && !refused.shortcutRegistrationFailed && refused.shortcutFailureWrites == 2,
                     "a refused island shortcut reports the failure and its end once each, not on every sync")
    }
}
