// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

/// Production opening and availability methods run with inert presentation
/// doubles. Feature choices live only in a disposable test preferences domain.
enum NotchDestinationContract {
    enum ReviewDefaults { static var current: UserDefaults! }
    enum NotchContentTransition { case none, reveal, replace }
    final class Panel {
        var acceptsKeyFocus = false
        func makeKey() {}
    }
    final class Host { func containsHover(_ point: CGPoint) -> Bool { false } }
    enum NSEvent { static let mouseLocation = CGPoint.zero }
    final class AppDelegate { func closePopover(preservingNotch: Bool) {} }
    struct Application { let delegate: AnyObject? = nil }
    static let NSApp = Application()
    enum ClipboardHistoryService {
        static let shared = Reader()
        struct Reader { func rememberPasteTarget() {} }
    }
    enum QuickLauncherService { static var shared = QuickLauncherContract.Launcher() }
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

    class State {
        var running = true
        var session = NotchSessionState()
        var suspended: Bool { !session.canPresent }
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var modules: [NotchModule] = []
        var selected = NotchModule.controls
        var selectedMetric: MetricDetailKind?
        var expanded = false
        var showingAppPanel = false
        var showingSections = false
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
        var presentationSyncs = 0
        var presentationTearDowns = 0
        var captureControlsCancel: (() -> Void)?
        var captureClose: (() -> Void)?
        func mutatePresentation(transitionContent: NotchContentTransition, _ change: () -> Void) { change() }
        func installEventMonitors() {}
        func syncVisibleConsumers() { requestedDetail = selectedMetric }
        func provideHapticFeedback() {}
        func endCaptureControls() {}
        func clearCapture() { captureControlsCancel = nil; captureClose = nil }
        func tearDownPresentation() { expanded = false; presentationTearDowns += 1 }
    }

    static func run(expect: (Bool, String) -> Void) {
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
        reopeningContracts(defaults: defaults, expect: expect)
        for resting in [NotchIdleContent.none, .music] {
            defaults.set(resting.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            let service = Service()
            service.open(.music)
            expect(service.expanded && service.selected == .music && service.panel?.acceptsKeyFocus == true,
                   "hiding automatic music preserves explicit opening of its controls")
            service.open(.controls)
            expect(service.expanded && service.selected == .controls
                   && NotchSupport.controls(in: defaults).contains(.music),
                   "hiding automatic music preserves playback controls on the island's home page")
        }
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        let families: [(MetricDetailKind, AppFeature)] = [
            (.cpu, .monitorCPU), (.gpu, .monitorGPU), (.memory, .monitorMemory),
            (.network, .monitorNetwork), (.disk, .monitorDisk),
            (.battery, .monitorPower), (.power, .monitorPower), (.fan, .fanControl),
        ]
        for (metric, feature) in families {
            let service = Service()
            service.open(.system, pinned: true, metric: metric)
            expect(service.selectedMetric == metric, "an available metric opens its own detail")
            defaults.set(false, forKey: feature.availabilityKey)
            service.syncWithPreferences()
            expect(service.selectedMetric == nil && service.requestedDetail == nil,
                   "removing the selected metric clears its detail even when other system families remain")
            service.open(.system, metric: metric, sections: true)
            service.open(.system, metric: metric)
            expect(service.selectedMetric == nil,
                   "a retained gallery argument cannot restore a metric removed from the hub")
            defaults.set(true, forKey: feature.availabilityKey)
        }
        let service = Service()
        service.open(.system, metric: .cpu)
        for (_, feature) in families { defaults.set(false, forKey: feature.availabilityKey) }
        service.syncWithPreferences()
        expect(!service.modules.contains(.system) && service.selected == .controls
               && service.selectedMetric == nil && service.requestedDetail == nil,
               "removing the last system family selects an available module without keeping its old detail")
        defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
        service.open(.system, metric: .fan)
        expect(!service.modules.contains(.system) && service.selectedMetric == .fan,
               "a separately installed fan feature retains its direct detail without other system modules")

        QuickLauncherService.shared = QuickLauncherContract.Launcher()
        let launcher = QuickLauncherService.shared
        let firstPresentation = launcher.presentationID
        service.open(.tools)
        expect(service.selected == .tools && launcher.selectedIndex == 0 && launcher.presentationID != firstPresentation,
               "opening Tools inside the island prepares keyboard selection on its first presentation")
        QuickLauncherContract.events.removeAll()
        let enter = QuickLauncherContract.NSEvent(keyCode: UInt16(kVK_Return))
        expect(launcher.handlePanelKey(enter, flow: .columns(rows: 2)) == nil
               && QuickLauncherContract.events == ["keepAwake.toggle"],
               "Return works immediately after the island opens Tools")
        let unchangedPresentation = launcher.presentationID
        service.open(.tools)
        expect(launcher.presentationID == unchangedPresentation,
               "reopening the same visible Tools destination does not reset its working presentation")
        launcher.activeUtility = .urlCleaner
        service.open(.controls)
        service.open(.tools)
        expect(launcher.activeUtility == .urlCleaner,
               "navigation preserves a still-available hosted utility")
        service.open(.controls)
        defaults.set(false, forKey: AppFeature.urlCleaner.availabilityKey)
        service.open(.tools)
        expect(launcher.activeUtility == nil,
               "returning to Tools after removal cannot revive its previous utility")
        service.open(.controls)
        launcher.candidates = []
        service.open(.tools)
        expect(launcher.selectedIndex == nil, "an empty Tools module leaves keyboard activation without a target")
        sessionContracts(expect: expect)
    }

    private static func reopeningContracts(defaults: UserDefaults, expect: (Bool, String) -> Void) {
        expect(Defaults.registeredDefaults[DefaultsKey.notchReturnHome] as? Bool == false,
               "returning home is opt-in and preserves the existing opening behavior")
        expect(Defaults.registeredDefaults[DefaultsKey.notchHomeModule] as? String == NotchModule.controls.rawValue,
               "the previously available home option keeps Controls as its initial destination")
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            let payload = SettingsBackupSupport.payload(appVersion: "test") {
                if $0 == DefaultsKey.notchReturnHome { return returnHome }
                if $0 == DefaultsKey.notchHomeModule { return NotchModule.music.rawValue }
                if $0 == DefaultsKey.notchHideUntilHover { return true }
                if $0 == DefaultsKey.notchHoverDelay { return 0.65 }
                return nil
            }
            let data = try? JSONSerialization.data(withJSONObject: payload)
            let decoded = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let restored = decoded.flatMap { SettingsBackupSupport.sanitizedSettings(from: $0) }
            expect(restored?[DefaultsKey.notchReturnHome] as? Bool == returnHome
                   && restored?[DefaultsKey.notchHomeModule] as? String == NotchModule.music.rawValue
                   && restored?[DefaultsKey.notchHoverDelay] as? Double == 0.65
                   && restored?[DefaultsKey.notchHideUntilHover] as? Bool == true,
                   "the opening behavior, selected page and activation time survive backup and restore")

            let service = Service()
            service.open(.files)
            service.open()
            expect(service.selected == .files, "an already open island does not jump away from the current page")
            service.expanded = false
            service.open()
            expect(service.selected == (returnHome ? .controls : .files),
                   "reopening either restores the last page or returns home according to the preference")
            service.expanded = false
            service.open(.music)
            expect(service.selected == .music, "an explicit destination always wins over the opening preference")
            defaults.set("controls", forKey: DefaultsKey.notchHiddenModules)
            defaults.set("files,music", forKey: DefaultsKey.notchModuleOrder)
            service.expanded = false
            service.open()
            expect(service.selected == (returnHome ? .files : .music),
                   "a hidden home page falls back to the first visible page without unhiding controls")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
            defaults.set("", forKey: DefaultsKey.notchModuleOrder)
        }
        defaults.set(true, forKey: DefaultsKey.notchReturnHome)
        for page in NotchSupport.modules(in: defaults) {
            defaults.set(page.rawValue, forKey: DefaultsKey.notchHomeModule)
            let service = Service()
            service.open()
            expect(service.selected == page, "each available page can be chosen for reopening: \(page.rawValue)")
            service.open(.files)
            expect(service.selected == .files, "a saved opening page never overrides explicit navigation")
            defaults.set(page.rawValue, forKey: DefaultsKey.notchHiddenModules)
            service.expanded = false
            service.open()
            expect(service.selected == NotchSupport.modules(in: defaults).first,
                   "hiding the saved opening page falls back to an available page")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        }
        defaults.set("unknown-page", forKey: DefaultsKey.notchHomeModule)
        let invalid = Service()
        invalid.open()
        expect(invalid.selected == .controls, "a malformed saved page falls back to Controls")
        defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
        activityContracts(defaults: defaults, expect: expect)
    }

    /// What the closed island is already showing is what opening it shows.
    private static func activityContracts(defaults: UserDefaults, expect: (Bool, String) -> Void) {
        let banner = NotchNotice(event: .systemNotification, title: "Alex", detail: "Hello", symbol: "bell.fill",
                                 notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: "Hello"),
                                 notificationID: UUID())
        defaults.set(true, forKey: DefaultsKey.notchNotificationsEnabled)
        defer { defaults.set(false, forKey: DefaultsKey.notchNotificationsEnabled) }
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
            for activity in [NotchCompactActivity.timer, .downloads, .music] {
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
            let volume = Service()
            volume.notice = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill", level: 0.5)
            volume.open()
            expect(volume.notice != nil && volume.selected == .controls,
                   "system feedback keeps its own timer and never redirects an opening")
        }
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
    }

    private static func sessionContracts(expect: (Bool, String) -> Void) {
        let service = Service()
        NotchTimerService.shared = Timer()
        let timer = NotchTimerService.shared
        service.updateSession { $0.displaysSleeping = true }
        expect(timer.running && timer.suspensions == 0 && timer.syncs == 0
               && service.presentationTearDowns == 1 && !service.session.canPresent,
               "display sleep removes presentation while leaving the timer and alarm uninterrupted")
        service.updateSession { $0.sleeping = true }
        expect(!timer.running && timer.suspensions == 1 && service.presentationTearDowns == 1,
               "system sleep suspends the timer even after the display already hid the island")
        service.updateSession { $0.locked = true }
        service.updateSession { $0.displaysSleeping = false }
        service.updateSession { $0.sleeping = false }
        expect(!timer.running && timer.syncs == 0 && service.presentationSyncs == 0,
               "display and system wake cannot resume an alarm or presentation while the session is locked")
        service.updateSession { $0.locked = false }
        expect(timer.running && timer.syncs == 1 && service.presentationSyncs == 1,
               "unlocking after every sleep condition clears resumes through the normal presentation path once")

        service.updateSession { $0.displaysSleeping = true }
        service.updateSession { $0.onConsole = false }
        expect(!timer.running && timer.suspensions == 2,
               "switching users suspends an alarm even when the display is already asleep")
        service.updateSession { $0.onConsole = true }
        expect(timer.running && timer.syncs == 2 && service.presentationSyncs == 1 && !service.session.canPresent,
               "returning to the same awake session resumes only the timer while its display remains asleep")
        service.updateSession { $0.displaysSleeping = false }
        expect(timer.running && service.presentationSyncs == 2,
               "the island returns only after the display also wakes")
        service.updateSession { $0.displaysSleeping = true }
        service.updateSession { $0.locked = true }
        service.updateSession { $0.onConsole = false }
        service.updateSession { $0.locked = false }
        service.updateSession { $0.displaysSleeping = false }
        expect(!timer.running && service.presentationSyncs == 2,
               "unlock and display wake cannot resume work while another login session owns the console")
        service.running = false
        service.updateSession { $0.onConsole = true }
        expect(!timer.running && service.presentationSyncs == 2,
               "late session notifications cannot restart a stopped island or timer")
    }
}
