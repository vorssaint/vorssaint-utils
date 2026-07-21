// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    private var popoverClosedAt = Date.distantPast
    private var popoverDismissMonitor: Any?
    private var popoverLocalDismissMonitor: Any?
    private var popoverKeyboardMonitor: Any?
    private var popoverIsClosing = false
    private var popoverIsSwitchingAnchor = false
    private var metricAnchorSwitchSerial = 0
    private var popoverCloseCompletions: [() -> Void] = []
    private var isTerminating = false
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var dockPreviewIntroWindow: NSWindow?
    private var supportIntroWindow: NSWindow?
    private var updateHighlightsWindow: NSWindow?
    private var supportIntroCanClose = false
    private var updateShowcaseWindow: NSWindow?
    private var updatePreviewWindow: NSWindow?
    private let popoverOpenDuration: TimeInterval = 0.18
    private let popoverCloseDuration: TimeInterval = 0.14

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        beginStartupWatch()
        Self.boundAccessibilityWaits()

        // Finish the on-disk rename for installs carried over from a pre-2.5
        // build, or retire a leftover old-named bundle. Returns true when we are
        // quitting to relaunch under the new name, so skip the rest of startup.
        if BundleMigration.run() { return }

        // Redo a launch at login registration the system lost. The stored
        // choice is the last thing the user expressed in the app; startup
        // never turns the item off.
        LaunchAtLogin.repairAtStartup()

        // Switch back on any display a previous run left off. A run that ends
        // without putting one back leaves a screen dark with no app around to
        // offer it back, so the repair happens before anything else can care
        // about which displays are attached.
        BrightnessService.shared.restoreDisplaysLeftOff()

        // An accessory (LSUIElement) app gets no default main menu, so the standard
        // keyboard shortcuts (Cmd+H/M/W/Q and the Edit shortcuts Cmd+C/V/X/A) have
        // no menu items to fire and do nothing in the Settings window. Install one.
        installMainMenu()
        PanelLayout.resetCollapsedSectionsOnce(for: "2.15.1")

        statusController = StatusItemController()
        statusController.onLeftClick = { [weak self] in
            self?.captureStatusClick()
            self?.toggleMainPopover()
        }
        statusController.onRightClick = { [weak self] in self?.showContextMenu() }
        statusController.onMetricClick = { [weak self] metric, button in
            self?.captureStatusClick()
            self?.showMetricPanel(for: metric, anchoredTo: button)
        }
        // The shelf drop zone chip anchors itself under the menu bar icon.
        ShelfService.shared.statusItemFrameProvider = { [weak self] in
            guard let item = self?.statusController.statusItem, item.isVisible,
                  let window = self?.statusController.button?.window else { return nil }
            return window.frame
        }

        setUpPopover()
        bindManagers()

        HotkeyManager.shared.onActivate = { KeepAwakeManager.shared.toggle() }
        HotkeyManager.shared.syncWithPreferences()

        KeepAwakeManager.shared.recoverIfNeeded {
            KeepAwakeManager.shared.activateOnLaunchIfNeeded()
        }
        // One binding per feature: only available features are touched, so a
        // feature switched off in the hub never even instantiates here.
        FeatureRuntime.shared.syncAtLaunch()
        if AppFeature.monitorPower.isAvailable {
            MaxCapacityProbe.shared.refreshIfStale()
        }
        UpdateService.shared.startAutomaticChecks()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        // If Accessibility is granted while the app is running (e.g. during
        // onboarding), bring the input features up without a relaunch.
        Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.sync([
                    .scrollInverter, .smoothScroll, .mouseNavigation, .switcher,
                    .dockPreview, .finderCutPaste, .autoQuit, .dockClick,
                    .middleClick, .windowMaximizer, .keyboardDebounce, .windowLayout,
                    .textSnippets, .brightness, .radialMenu,
                ])
            }
            .store(in: &cancellables)

        Permissions.shared.$screenRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.sync([.dockPreview])
            }
            .store(in: &cancellables)

        // Keep the menu titles in step with the in-app language.
        L10n.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installMainMenu() }
            .store(in: &cancellables)

        let defaults = UserDefaults.standard
        // Whatever opens a window at startup waits for the next turn of the
        // run loop, so the menu bar icon is on screen first. A start that goes
        // wrong after this point then leaves the app reachable instead of
        // invisible. And if the previous start never finished, the extra
        // windows are skipped entirely this time: the app comes up bare rather
        // than walking into the same thing twice.
        let skipStartupWindows = startupOfPreviousRunDidNotFinish
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !defaults.bool(forKey: DefaultsKey.hasOnboarded) {
                guard !skipStartupWindows else { return }
                self.showOnboarding(mode: .full)
            } else {
                // Keep the last seen version marker current without opening
                // post-update release notes; the update flow already previews
                // them.
                defaults.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
                defaults.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
                guard !skipStartupWindows else { return }
                self.presentUpdateIntros()
            }
        }
    }

    /// Asking another app about its windows waits for that app to answer, and
    /// the wait allowed by default is a second and a half per question. An app
    /// that is busy saving, or stuck on a slow disk, would hold this one still
    /// for that long each time, and this app asks in places where the whole
    /// session is waiting on it. The limit is set once here, low enough that a
    /// slow answer is dropped rather than felt. The value matches what the
    /// window features already settled on for themselves. It applies to every
    /// question asked from this process, whichever element it is asked of, so
    /// it also covers the places that never set one of their own.
    private static func boundAccessibilityWaits() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.35)
    }

    // MARK: - Startup that did not finish

    /// A start is marked as under way before anything else happens and cleared
    /// once the app has been running healthily for a while, or when it is
    /// quit properly. Finding the mark still set means the previous run died
    /// on the way up, and this one leaves the optional windows out of it.
    private var startupOfPreviousRunDidNotFinish = false

    /// How long a run has to last before its start counts as having worked.
    /// Comfortably past the point where the reported failures happened.
    private static let healthyStartupSeconds: TimeInterval = 20

    private func beginStartupWatch() {
        let defaults = UserDefaults.standard
        startupOfPreviousRunDidNotFinish = defaults.bool(forKey: DefaultsKey.startupDidNotFinish)
        defaults.set(true, forKey: DefaultsKey.startupDidNotFinish)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.healthyStartupSeconds) {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.startupDidNotFinish)
        }
    }

    private func endStartupWatch() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.startupDidNotFinish)
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        // Quitting properly means the start worked, whenever it happened.
        endStartupWatch()
        if AppFeature.brightness.isAvailable {
            BrightnessService.shared.restoreDisplaysBeforeTermination()
        }
        ExtraBrightnessService.shared.stop()
        ProcessUsageService.shared.stopNetworkMonitoring(force: true)
        URLCleanerService.shared.stop()
        WindowMaximizer.shared.stop()
        WindowLayoutService.shared.suspend()
        KeyboardDebounceService.shared.suspend()
        TextSnippetService.shared.suspend()
        MiddleClickService.shared.suspend()
        SmoothScrollService.shared.suspend()
        MouseNavigationService.shared.suspend()
        DockPreviewService.shared.stop()
        SoundOutputSwitcher.shared.stop()
        AppVolumeMixer.shared.stopAll()
        // Puts the system input back if a microphone was chosen here: the
        // app's audio settings must not outlive the app.
        AudioInputDeviceManager.shared.stop()
        // Flushes any scratchpad edit still inside the save debounce.
        ScratchpadService.shared.suspend()
        // The clipboard history persists through an async pipeline; the last
        // mutation (often a Clear) must land before the process dies.
        if AppFeature.clipboardHistory.isAvailable {
            ClipboardHistoryService.shared.flushBeforeTermination()
        }
        KeepAwakeManager.shared.deactivate(reason: .quit)
    }

    /// The lifeline when the menu bar icon goes missing. Opening the app again
    /// from Finder, Spotlight or Launchpad while it's already running lands here:
    /// force the icon back and pop the panel so there's immediate proof the app is
    /// alive. Without this, a hidden icon would strand the app running with no way
    /// in. (A cold launch can't happen while running, so this is the recovery path.)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        // A deliberate reopen with no windows showing is the user's recovery action.
        // Rebuild the menu bar item only when it is actually missing: the
        // pre-rebuild item has a settled frame, so iconIsOnScreen() is trustworthy
        // here (the not-ready-frame caveat below only applies to a freshly created
        // item), and a dropped icon reads off-screen/zero, so recovery still gets
        // its rebuild with fresh placement. A healthy icon is left alone: on
        // macOS 27 a rebuilt item's window can keep reporting the slot it was
        // born in (the far right of the status area) while the icon draws at the
        // user's arranged spot, and that mismatch strands the panel against the
        // screen edge and survives relaunches.
        if !iconIsOnScreen() {
            statusController?.recreateStatusItem(resetPlacement: true)
        }
        // Decide on the next run-loop turn: a freshly rebuilt status item has no
        // laid-out on-screen frame yet this turn, so iconIsOnScreen() would read a
        // not-ready frame and wrongly skip the panel. After layout: pop the panel
        // when the icon is genuinely on screen, else fall back to the Settings
        // window. Either way the user ALWAYS gets back in.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.iconIsOnScreen(), !self.popover.isShown {
                self.popoverClosedAt = .distantPast
                self.togglePopover()
            }
            if !self.popover.isShown {
                self.openSettingsWindow()
            }
        }
        return true
    }

    /// Whether the menu bar icon is actually visible on a screen, rather than
    /// present in the status bar but clipped or dropped by a crowded/notched menu
    /// bar (in which case the button still has a window, just not an on-screen one).
    private func iconIsOnScreen() -> Bool {
        guard let frame = statusController?.statusItem.button?.window?.frame,
              frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func bindManagers() {
        KeepAwakeManager.shared.onSessionEnded = { reason in
            let strings = L10n.shared.s
            switch reason {
            case .timer:
                Notifier.post(title: strings.notifySessionEndedTitle, body: strings.notifySessionEndedBody)
            case .battery:
                Notifier.post(title: strings.notifyBatteryTitle, body: strings.notifyBatteryBody)
            default:
                break
            }
        }
    }

    // MARK: - Main panel

    private func setUpPopover() {
        // Application-defined (not .transient) so the panel stays open while the
        // user works in our own Settings window and sees changes live. Click
        // monitors below dismiss it when it would block that same Settings window.
        popover.behavior = .applicationDefined
        // We animate the underlying popover window ourselves so applicationDefined
        // dismissal, right-click menus and live Settings previews stay predictable.
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func togglePopover(anchor button: NSStatusBarButton? = nil) {
        if popover.isShown {
            closePopover()
            return
        }
        showPopover(anchor: button)
    }

    private func toggleMainPopover() {
        if !popover.isShown {
            MenuPanelFocus.shared.showNormalPanel()
        }
        togglePopover()
    }

    private func showMetricPanel(for metric: MenuBarMetric, anchoredTo button: NSStatusBarButton) {
        let detailKind = metric.detailKind
        if popover.isShown {
            if MenuPanelFocus.shared.activeMetric == detailKind {
                metricAnchorSwitchSerial &+= 1
                MenuPanelFocus.shared.clearMetricFocus()
                closePopover(animated: false)
                return
            }
            MenuPanelFocus.shared.focus(detailKind)
            scheduleMetricAnchorSwitch(to: detailKind, anchoredTo: button)
            return
        }
        MenuPanelFocus.shared.focus(detailKind)
        showPopover(anchor: button)
    }

    private func scheduleMetricAnchorSwitch(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        metricAnchorSwitchSerial &+= 1
        let serial = metricAnchorSwitchSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial == serial,
                  MenuPanelFocus.shared.activeMetric == detailKind else { return }
            self.reanchorMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func reanchorMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        guard popover.isShown else {
            MenuPanelFocus.shared.focus(detailKind)
            showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            return
        }
        popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        let expectedMidX = statusButtonMidX(button)
        // The panel measures itself against this while the popover lays out,
        // so it has to be right before the content is asked for its size.
        PanelInteractionState.shared.anchorScreen = statusScreen(for: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if let window = popover.contentViewController?.view.window {
            beginPopoverDriftCorrection(window: window,
                                        anchor: resolvePanelAnchor(for: button, window: window))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial > 0,
                  MenuPanelFocus.shared.activeMetric == detailKind else {
                self?.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            // The pinned anchor is the yardstick; a reported frame the system
            // has since parked out of the way is not.
            if let expectedMidX = self.popoverAnchor?.midX ?? expectedMidX,
               let popoverMidX = self.popover.contentViewController?.view.window?.frame.midX,
               abs(popoverMidX - expectedMidX) <= 34 {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.switchMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func statusButtonMidX(_ button: NSStatusBarButton) -> CGFloat? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).midX
    }

    /// Where the user last physically clicked a status button, captured at
    /// action time. The deferred metric re-shows fire up to ~0.2s after the
    /// click, and re-reading the pointer there would chase a flicked-away
    /// cursor; the captured point is immune to that. Accessibility presses
    /// (no mouse event) capture nothing, so they never "correct" toward a
    /// pointer parked anywhere on screen.
    private var lastStatusClick: (x: CGFloat, at: Date)?
    private var popoverAnchor: PanelAnchor?
    private var lastGoodPanelAnchor: PanelAnchor?
    private var popoverDriftObservers: [NSObjectProtocol] = []

    /// How long a captured click still counts as "where the icon is".
    private static let statusClickFreshness: TimeInterval = 0.5

    /// The spot an open panel holds: the horizontal middle and the top edge it
    /// must keep across content resizes, plus the screen the menu bar icon was
    /// on. The screen travels with the anchor instead of being read back from
    /// the panel's window, because a window already flung to a corner can
    /// report a different display and would then be clamped against that one.
    private struct PanelAnchor {
        let midX: CGFloat
        let top: CGFloat
        let screen: NSScreen?
        /// False when it came from a fallback, so a guess never becomes the
        /// remembered good anchor for the rest of the session.
        let trusted: Bool
        /// True when the anchor is known to beat the status item's frame from
        /// the moment the panel opens, because a physical click landed clearly
        /// outside that frame. Otherwise the anchor waits: while the frame
        /// still describes a spot in the menu bar the system places the panel
        /// better than any remembered point can, following the icon as the bar
        /// shuffles items around it.
        let overridesSoundFrame: Bool
        /// The button the anchor was taken from, so "does the frame still
        /// describe the bar?" asks the item the panel is actually hanging off
        /// (a metric item, not necessarily the main icon).
        weak var button: NSStatusBarButton?
    }

    private func captureStatusClick() {
        guard let event = NSApp.currentEvent,
              Self.statusClickEventTypes.contains(event.type) else { return }
        lastStatusClick = (NSEvent.mouseLocation.x, Date())
    }

    /// The on-screen midX the open panel must center on, or nil when the
    /// button's reported frame can be trusted. A fresh physical click landing
    /// clearly outside the frame the button claims to occupy is the macOS 27
    /// stale-frame mismatch (see StatusItemAnchorSupport): the click marks
    /// where the icon is actually drawn, so the panel centers there. The
    /// positioning rect cannot express this (AppKit intersects it with the
    /// button's bounds), so the correction moves the popover's window instead.
    private func correctedPopoverMidX(for button: NSStatusBarButton) -> CGFloat? {
        guard let click = lastStatusClick,
              Date().timeIntervalSince(click.at) < Self.statusClickFreshness,
              let reportedMidX = statusButtonMidX(button),
              StatusItemAnchorSupport.anchorDriftX(clickX: click.x,
                                                   reportedMidX: reportedMidX,
                                                   buttonWidth: button.bounds.width) != nil
        else { return nil }
        return click.x
    }

    private static let statusClickEventTypes: Set<NSEvent.EventType> = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    ]

    /// The screen the menu bar icon lives on, for the panel's height cap and
    /// for clamping it once it is open.
    private func statusScreen(for button: NSStatusBarButton) -> NSScreen? {
        if let frame = button.window?.frame,
           let hosting = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return hosting
        }
        // A window parked out of the visible area reports no screen of its own,
        // and that is exactly the state this path exists for, so fall back to
        // the display that owns the bar rather than to whichever one happens to
        // hold the key window.
        return button.window?.screen ?? NSScreen.withMenuBar
    }

    /// Whether the item the panel hangs off still reports a frame that sits in
    /// a menu bar. While it does, the system's own placement wins and the
    /// remembered anchor stays out of the way; once it stops (a bar that hides
    /// itself parks the window out of the visible area) the anchor takes over.
    private func frameStillDescribesMenuBar(_ anchor: PanelAnchor) -> Bool {
        guard let frame = anchor.button?.window?.frame else { return false }
        return StatusItemAnchorSupport.isTrustworthyStatusFrame(
            frame, screenFrames: NSScreen.screens.map(\.frame))
    }

    /// The spot the panel must hold while it is open, decided at the moment it
    /// opens: the user has just clicked the icon, so the menu bar is up and its
    /// frame is at its most trustworthy. Everything after that (a bar that
    /// slides away, a status item stranded at the slot it was born in) is read
    /// from a frame that no longer describes where the icon is.
    private func resolvePanelAnchor(for button: NSStatusBarButton, window: NSWindow) -> PanelAnchor {
        let screen = statusScreen(for: button)
        let statusFrame = button.window?.frame
        let frameIsSound = statusFrame.map {
            StatusItemAnchorSupport.isTrustworthyStatusFrame($0, screenFrames: NSScreen.screens.map(\.frame))
        } ?? false
        if frameIsSound, statusFrame != nil {
            // Where the popover has just been placed is the anchor: with a
            // sound frame the system put it exactly right, including its own
            // clamping near a screen edge, so holding that spot changes
            // nothing about how an open panel looks. It is held in reserve,
            // though, and only applied once that frame stops describing the
            // bar. A fresh physical click that clearly disagrees with the
            // frame is the stranded item instead, and then the click marks
            // where the icon really is and outranks the frame right away.
            let corrected = correctedPopoverMidX(for: button)
            return PanelAnchor(midX: corrected ?? window.frame.midX,
                               top: window.frame.maxY,
                               screen: screen,
                               trusted: true,
                               overridesSoundFrame: corrected != nil,
                               button: button)
        }
        // The frame points nowhere, so the panel it just positioned is nowhere
        // either. Best available, in order: the spot this session last held, a
        // click still fresh enough to mean something, then the corner of the
        // screen the status area lives in.
        // The remembered spot is only worth reusing while it still describes
        // somewhere that exists. One captured on a display that has since been
        // unplugged would put the panel against an edge of the display that is
        // left, which is the very thing this is here to prevent.
        if let remembered = lastGoodPanelAnchor,
           let rememberedScreen = remembered.screen,
           rememberedScreen.isStillAttached,
           rememberedScreen.displayID == screen?.displayID {
            // Reused for an item whose frame is already pointing nowhere, so it
            // has to act now rather than wait for a frame that will not recover.
            return PanelAnchor(midX: remembered.midX, top: remembered.top,
                               screen: screen, trusted: true,
                               overridesSoundFrame: true, button: button)
        }
        lastGoodPanelAnchor = nil
        let visible = screen?.visibleFrame ?? window.frame
        if let click = lastStatusClick,
           Date().timeIntervalSince(click.at) < Self.statusClickFreshness {
            return PanelAnchor(midX: click.x, top: visible.maxY, screen: screen,
                               trusted: false, overridesSoundFrame: true, button: button)
        }
        return PanelAnchor(midX: visible.maxX, top: visible.maxY, screen: screen,
                           trusted: false, overridesSoundFrame: true, button: button)
    }

    /// Slides the popover window so its center (and thus the arrow tip, which
    /// keeps its offset from the window) lands on the real icon, and keeps it
    /// there: the popover places its window again from the status item's frame
    /// on every content resize (switching panel tabs), which would fling the
    /// panel to wherever that frame currently claims to be.
    private func beginPopoverDriftCorrection(window: NSWindow, anchor: PanelAnchor) {
        endPopoverDriftCorrection()
        popoverAnchor = anchor
        if anchor.trusted { lastGoodPanelAnchor = anchor }
        PanelInteractionState.shared.anchorScreen = anchor.screen
        applyPopoverDriftFrame(window)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            popoverDriftObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let window else { return }
                self?.applyPopoverDriftFrame(window)
            })
        }
    }

    private func applyPopoverDriftFrame(_ window: NSWindow) {
        guard let anchor = popoverAnchor,
              // A healthy bar places the panel better than the anchor can, and
              // keeps it under an icon that shifts as items come and go, so the
              // anchor stays dormant until that frame stops meaning anything.
              anchor.overridesSoundFrame || !frameStillDescribesMenuBar(anchor),
              let visible = anchorVisibleFrame(anchor, window: window) else { return }
        let frame = window.frame
        let target = StatusItemAnchorSupport.pinnedPanelFrame(size: frame.size,
                                                              anchorMidX: anchor.midX,
                                                              anchorTop: anchor.top,
                                                              visibleFrame: visible)
        // The 2pt tolerance breaks the loop with our own setFrame's didMove.
        guard abs(frame.midX - target.midX) > 2 || abs(frame.maxY - target.maxY) > 2 else { return }
        window.setFrame(target, display: true)
    }

    /// The usable area the panel is clamped to. Prefers the anchor's own screen
    /// and only falls back when that display has since been unplugged.
    private func anchorVisibleFrame(_ anchor: PanelAnchor, window: NSWindow) -> CGRect? {
        if let screen = anchor.screen, screen.isStillAttached {
            return screen.visibleFrame
        }
        return (window.screen ?? NSScreen.withMenuBar)?.visibleFrame
    }

    private func endPopoverDriftCorrection() {
        popoverDriftObservers.forEach { NotificationCenter.default.removeObserver($0) }
        popoverDriftObservers.removeAll()
        popoverAnchor = nil
        // Nothing is measuring itself against a screen with the panel closed,
        // and holding one keeps a display object alive for no reason.
        PanelInteractionState.shared.anchorScreen = nil
    }

    private func switchMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        removePopoverDismissMonitor()
        popoverIsClosing = true
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak button] in
            guard let self else {
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            guard let button else {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.popoverClosedAt = .distantPast
            MenuPanelFocus.shared.focus(detailKind)
            self.showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            DispatchQueue.main.async {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
            }
        }
    }

    private func showPopover(anchor button: NSStatusBarButton? = nil,
                             allowRecentClose: Bool = false,
                             animate: Bool = true,
                             activate: Bool = true) {
        guard !popover.isShown else { return }
        // The click that just transient-dismissed the popover also lands here;
        // reopening would make the panel look impossible to close.
        guard allowRecentClose || Date().timeIntervalSince(popoverClosedAt) > 0.35 else { return }
        guard let button = button ?? statusController.button else { return }

        // The panel measures itself against this while the popover lays out, so
        // it has to be known before the content is asked for its size.
        PanelInteractionState.shared.anchorScreen = statusScreen(for: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            // Keep the panel alive next to fullscreen apps and on any Space —
            // without this it blinks shut when another display is fullscreen.
            window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces])
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
            }
            window.contentView?.layoutSubtreeIfNeeded()
            window.makeKey()
            if animate {
                animatePopoverOpen(window)
            } else {
                popoverIsClosing = false
                window.alphaValue = 1
            }
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Only arm the monitors and the anchor if the popover actually presented
        // — otherwise popoverDidClose never fires and both would leak, holding a
        // display object and a window observer for the rest of the session.
        guard popover.isShown else {
            endPopoverDriftCorrection()
            return
        }
        if let window = popover.contentViewController?.view.window {
            beginPopoverDriftCorrection(window: window,
                                        anchor: resolvePanelAnchor(for: button, window: window))
        }
        installPopoverDismissMonitor()
    }

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        // A global monitor only sees events delivered to OTHER apps, so a click in
        // another app or on the desktop dismisses the panel.
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            guard !PanelInteractionState.shared.keepsPopoverOpen else { return }
            guard self.statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            self.closePopover()
        }

        // Local events cover our own Settings window. Keep Settings + panel open
        // when they sit side by side for live reordering, but close the panel if it
        // overlaps Settings and the user clicks Settings to get it out of the way.
        popoverLocalDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if self.shouldDismissPopover(forLocalEvent: event) {
                self.closePopover()
            }
            return event
        }

        popoverKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePopoverKeyDown(event)
        }
    }

    private func removePopoverDismissMonitor() {
        if let monitor = popoverDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverDismissMonitor = nil
        }
        if let monitor = popoverLocalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalDismissMonitor = nil
        }
        if let monitor = popoverKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyboardMonitor = nil
        }
    }

    private func shouldDismissPopover(forLocalEvent event: NSEvent) -> Bool {
        guard !PanelInteractionState.shared.keepsPopoverOpen else { return false }
        guard event.window === settingsWindow,
              let settingsFrame = settingsWindow?.frame,
              let popoverFrame = popover.contentViewController?.view.window?.frame else {
            return false
        }
        return settingsFrame.intersects(popoverFrame)
    }

    private func handlePopoverKeyDown(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown,
              PanelInteractionState.shared.keepsPopoverOpen,
              isPlainPopoverHoldKey(event),
              let window = popover.contentViewController?.view.window else {
            return event
        }

        // Text controls inside the popover, especially the Homebrew search
        // field, need Space/Return delivered through AppKit's normal field
        // editor path so delegates and target/actions can submit correctly.
        if isTextEditingActive(in: window) {
            return event
        }

        if NSApp.keyWindow === window || event.window === window {
            window.firstResponder?.keyDown(with: event)
            return nil
        }
        return event
    }

    private func isPlainPopoverHoldKey(_ event: NSEvent) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
        return event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76
    }

    private func isTextEditingActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        guard let fieldEditor = window.fieldEditor(false, for: nil) else { return false }
        return responder === fieldEditor
    }

    @objc private func appResignedActive() {
        // Leaving the app entirely (e.g. ⌘Tab) dismisses the panel; switching to
        // our own Settings window keeps the app active, so it stays open.
        if popover.isShown, !PanelInteractionState.shared.keepsPopoverOpen {
            guard statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            closePopover()
        }
    }

    @objc private func appBecameActive() {
        // Coming back to the app is a good moment to surface a fresh release.
        // (Menu bar icon recovery happens on a deliberate reopen, not here: this
        // fires on every activation, so rebuilding here would cause churn/flicker.)
        UpdateService.shared.checkIfStale()
    }

    func closePopover(animated: Bool = true, after delay: TimeInterval = 0,
                      completion: (() -> Void)? = nil) {
        if delay <= 0 {
            closePopoverNow(animated: animated, completion: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.closePopoverNow(animated: animated, completion: completion)
        }
    }

    private func closePopoverNow(animated: Bool, completion: (() -> Void)?) {
        guard popover.isShown else {
            completion?()
            return
        }
        if let completion { popoverCloseCompletions.append(completion) }
        guard !popoverIsClosing else { return }
        guard animated, let window = popover.contentViewController?.view.window else {
            finishPopoverClose()
            return
        }

        popoverIsClosing = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverCloseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            window?.alphaValue = 1
            self?.finishPopoverClose()
        }
    }

    private func animatePopoverOpen(_ window: NSWindow) {
        popoverIsClosing = false
        window.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverOpenDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        } completionHandler: { [weak self, weak window] in
            guard let self,
                  self.popover.isShown,
                  window === self.popover.contentViewController?.view.window else { return }
            window?.alphaValue = 1
        }
    }

    private func finishPopoverClose() {
        guard popover.isShown else {
            popoverIsClosing = false
            runPopoverCloseCompletions()
            return
        }
        popoverIsClosing = true
        popover.performClose(nil)
        runPopoverCloseCompletions()
    }

    private func runPopoverCloseCompletions() {
        let completions = popoverCloseCompletions
        popoverCloseCompletions.removeAll()
        completions.forEach { $0() }
    }

    // The SwiftUI panel reports which monitor sections are actually visible; the
    // popover callback only handles update freshness.
    func popoverWillShow(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .menuPanelWillShow, object: nil)
        }
        SystemMonitor.shared.suppressGPUReadsForTransientUI()
        if !popoverIsSwitchingAnchor {
            UpdateService.shared.checkIfStale()
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        popoverIsClosing || !PanelInteractionState.shared.keepsPopoverOpen
    }

    func popoverDidClose(_ notification: Notification) {
        if !popoverIsSwitchingAnchor {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
        }
        if !popoverIsSwitchingAnchor {
            MenuPanelFocus.shared.clearMetricFocus()
            // Non-forced stop: the shortened lease lets nettop wind down on its
            // own within a few seconds while keeping the delta baseline, so a
            // quick reopen shows per-app rows immediately instead of re-priming.
            ProcessUsageService.shared.stopNetworkMonitoring()
            ProcessUsageService.shared.clearCachedRows()
            ResponsibleProcess.clearIconCache()
        }
        removePopoverDismissMonitor()
        endPopoverDriftCorrection()
        PanelInteractionState.shared.keepsPopoverOpen = false
        popoverClosedAt = popoverIsSwitchingAnchor ? .distantPast : Date()
        popoverIsClosing = false
        runPopoverCloseCompletions()
    }

    // MARK: - Context menu (right click)

    private func showContextMenu() {
        // The panel uses applicationDefined dismissal, so a right-click while it's
        // open won't close it on its own — and the menu would try to open behind it.
        // Close it first so the context menu always appears.
        if popover.isShown {
            closePopover { [weak self] in self?.presentContextMenu() }
            return
        }

        presentContextMenu()
    }

    private func presentContextMenu() {
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let menu = NSMenu()

        if AppFeature.keepAwake.isAvailable {
            let toggleItem = NSMenuItem(title: manager.isActive ? strings.menuDisableAwake : strings.menuEnableAwake,
                                        action: #selector(menuToggleAwake),
                                        keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
        }

        if AppFeature.keepAwake.isAvailable, !manager.isActive {
            let durationsItem = NSMenuItem(title: strings.menuActivateFor, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let options: [(String, Int)] = [(strings.minutes15, 15), (strings.minutes30, 30),
                                            (strings.hour1, 60), (strings.hours2, 120),
                                            (strings.hours4, 240), (strings.hours8, 480),
                                            (strings.indefinitely, 0)]
            for (label, minutes) in options {
                let item = NSMenuItem(title: label, action: #selector(menuActivateDuration(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                submenu.addItem(item)
            }
            durationsItem.submenu = submenu
            menu.addItem(durationsItem)
        }

        if AppFeature.cleaningMode.isAvailable {
            let cleaningItem = NSMenuItem(title: strings.cleaningMenuItem,
                                          action: #selector(menuCleaningMode), keyEquivalent: "")
            cleaningItem.target = self
            menu.addItem(cleaningItem)
        }

        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        if AppFeature.uninstaller.isAvailable {
            let uninstallItem = NSMenuItem(title: strings.uninstallerMenuItem,
                                           action: #selector(menuOpenUninstaller), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }

        if AppFeature.shelf.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) {
            let shelfItem = NSMenuItem(title: strings.shelfMenuItem,
                                       action: #selector(menuOpenShelf), keyEquivalent: "")
            shelfItem.target = self
            menu.addItem(shelfItem)
        }

        let updatesItem = NSMenuItem(title: strings.menuCheckUpdates, action: #selector(menuCheckUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: strings.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusController.statusItem.menu = menu
        statusController.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusController.statusItem.menu = nil
        }
    }

    @objc private func menuToggleAwake() {
        KeepAwakeManager.shared.toggle()
    }

    @objc private func menuCleaningMode() {
        CleaningModeManager.shared.activate()
    }

    @objc private func menuActivateDuration(_ sender: NSMenuItem) {
        KeepAwakeManager.shared.activate(minutes: sender.tag)
    }

    @objc private func menuOpenSettings() {
        openSettingsWindow()
    }

    @objc private func menuOpenUninstaller() {
        SettingsRouter.shared.page = .uninstaller
        openSettingsWindow()
    }

    @objc private func menuOpenShelf() {
        ShelfService.shared.expandDocked()
    }

    @objc private func menuCheckUpdates() {
        UpdateService.shared.check(manual: true)
        openSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: L10n.shared.s.aboutDescription,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Application menu

    /// Builds and installs the standard application menu (App / Edit / Window).
    ///
    /// Because the app runs as an accessory, AppKit never gives it the default main
    /// menu a regular app gets, so `NSApp.mainMenu` stays nil and the standard key
    /// equivalents (which live on menu items) never resolve. That is why nothing
    /// happens for Cmd+H/M/W/Q or Cmd+C/V/X/A inside the Settings window. A minimal
    /// standard menu restores them. The menu bar only appears while one of the
    /// app's own windows is focused; otherwise the app is as invisible as before.
    /// Most items use the responder chain (nil target) so they act on the key
    /// window or the focused text field; About and Settings route to our handlers.
    func installMainMenu() {
        let strings = L10n.shared.s
        let mainMenu = NSMenu()

        // Application menu (the bold, app-named first menu).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(title: strings.menuHide,
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: strings.menuHideOthers,
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: strings.menuShowAll,
                                   action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: strings.menuQuit,
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Edit menu, so text fields in Settings respond to the editing shortcuts.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: strings.menuEdit)
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: strings.menuUndo, action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: strings.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: strings.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: strings.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: strings.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: strings.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Window menu (Minimize / Zoom / Close). Settings is .miniaturizable so
        // Cmd+M actually minimizes; AppKit manages enabling once windowsMenu is set.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: strings.menuWindow)
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: strings.menuMinimize,
                                      action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: strings.menuZoom,
                                      action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: strings.menuClose,
                                      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Windows

    func openSettingsWindow() {
        // Intentionally does NOT close the panel: the panel uses applicationDefined
        // dismissal, so it stays open beside Settings for a live preview.
        let createdWindow = settingsWindow == nil
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: host)
            // .miniaturizable so the Window menu's Minimize (Cmd+M) actually works.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.contentMinSize = NSSize(width: SettingsWindowSupport.minContentWidth,
                                           height: SettingsWindowSupport.minContentHeight)
            let visible = NSScreen.pointerVisibleFrame
            let size = SettingsWindowSupport.initialContentSize(
                savedWidth: UserDefaults.standard.double(forKey: DefaultsKey.settingsWindowWidth),
                savedHeight: UserDefaults.standard.double(forKey: DefaultsKey.settingsWindowHeight),
                availableHeight: Double(visible.height - 40))
            window.setContentSize(NSSize(width: size.width, height: size.height))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.title = L10n.shared.s.settingsTitle
        if let window = settingsWindow {
            positionSettingsWindow(window, force: createdWindow)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.settingsWindow else { return }
            self.positionSettingsWindow(window, force: false)
        }
    }

    private func positionSettingsWindow(_ window: NSWindow, force: Bool) {
        window.contentView?.layoutSubtreeIfNeeded()
        let popoverWindow = popover.contentViewController?.view.window
        let visible = (popoverWindow?.screen ?? window.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 360), availableWidth)
        let height = min(max(window.frame.height, 320), availableHeight)
        var frame = force
            ? NSRect(x: visible.midX - width / 2,
                     y: visible.midY - height / 2,
                     width: width,
                     height: height)
            : NSRect(x: window.frame.minX,
                     y: window.frame.minY,
                     width: width,
                     height: height)

        if let popoverFrame = popoverWindow?.frame,
           visible.intersects(popoverFrame),
           frame.intersects(popoverFrame) {
            frame = settingsFrame(frame, avoiding: popoverFrame, in: visible)
        } else if force {
            frame.origin.x = min(max(frame.origin.x, visible.minX + margin / 2), visible.maxX - width - margin / 2)
            frame.origin.y = min(max(frame.origin.y, visible.minY + margin / 2), visible.maxY - height - margin / 2)
        }
        window.setFrame(frame.integral, display: false)
    }

    private func settingsFrame(_ frame: NSRect, avoiding popoverFrame: NSRect, in visible: NSRect) -> NSRect {
        let gap: CGFloat = 28
        let margin: CGFloat = 20
        var adjusted = frame

        let leftX = popoverFrame.minX - gap - frame.width
        let rightX = popoverFrame.maxX + gap
        if popoverFrame.midX >= visible.midX, leftX >= visible.minX + margin {
            adjusted.origin.x = min(frame.origin.x, leftX)
        } else if popoverFrame.midX < visible.midX,
                  rightX + frame.width <= visible.maxX - margin {
            adjusted.origin.x = max(frame.origin.x, rightX)
        } else {
            let belowY = popoverFrame.minY - gap - frame.height
            let aboveY = popoverFrame.maxY + gap
            if belowY >= visible.minY + margin {
                adjusted.origin.y = min(frame.origin.y, belowY)
            } else if aboveY + frame.height <= visible.maxY - margin {
                adjusted.origin.y = max(frame.origin.y, aboveY)
            }
        }

        adjusted.origin.x = min(max(adjusted.origin.x, visible.minX + margin), visible.maxX - frame.width - margin)
        adjusted.origin.y = min(max(adjusted.origin.y, visible.minY + margin), visible.maxY - frame.height - margin)
        return adjusted
    }

    /// Rebuilds the menu bar item so the icon reappears when the OS has dropped it
    /// from a crowded or notched menu bar. Backs the "Show menu bar icon" button.
    /// The rebuild can silently lose to a full bar or to a menu bar manager app
    /// stuffing the fresh item into its hidden section, so
    /// after the frame settles this checks the icon really made it on screen
    /// and, if not, says so instead of looking like the button did nothing.
    func reshowStatusItem() {
        // The button is an explicit "I want the icon back": the hide-with-
        // metrics option must not immediately re-hide what the user just
        // asked to see (and then trip the "still hidden" alert).
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarHideIconWithMetrics)
        statusController?.recreateStatusItem(resetPlacement: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.iconIsOnScreen() else { return }
            let s = L10n.shared.s
            var body = s.menuBarIconStillHiddenBody
            if let manager = Self.runningMenuBarManagerName() {
                body += "\n\n" + String(format: s.menuBarIconManagerHintFormat, manager, manager)
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = s.menuBarIconStillHiddenTitle
            alert.informativeText = body
            alert.runModal()
        }
    }

    /// Known menu bar organizers, by bundle id; any of them can be holding
    /// the icon in its hidden section, which explains it never reappearing
    /// on this machine. The hint names whichever one is running by its own
    /// localized app name.
    private static let menuBarManagerBundlePrefixes = [
        "com.jordanbaird.Ice",
        "com.surteesstudios.Bartender",
        "com.dwarvesv.minimalbar",
        "com.mortenjust.Dozer",
    ]

    private static func runningMenuBarManagerName() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            if menuBarManagerBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return app.localizedName
            }
        }
        return nil
    }

    /// Quits and reopens the app. Full Disk Access only applies to a fresh
    /// process, so this is how the uninstaller picks up a just-granted grant.
    func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.3; /usr/bin/open \"$1\"", "vorssaint-relaunch", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    func showOnboarding(mode: OnboardingMode = .full) {
        closePopover()
        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(mode: mode) { [weak self] in
            self?.markOnboardingComplete()
            Notifier.requestPermission()
            self?.onboardingWindow?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = mode.title(L10n.shared.s)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.onboardingWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    /// On launch after an update, keep the short support prompt visible once per
    /// version. The changelog itself is already shown before download.
    private func presentUpdateIntros() {
        if showUpdateHighlightsIfNeeded() { return }
        if showSupportUpdateIntroIfNeeded() { return }
        if showUpdateShowcaseIntroIfNeeded() { return }
        showDockPreviewIntroIfNeeded()
    }

    private func showUpdateHighlightsIfNeeded() -> Bool {
        guard UpdateHighlightsInfo.shouldShow(
            appVersion: AppInfo.version,
            lastSeenVersion: UserDefaults.standard.string(forKey: DefaultsKey.updateHighlightsSeenVersion)
        ) else { return false }
        // If every featured item was uninstalled in the hub there is nothing
        // to tour; mark it seen and stay quiet instead of showing an empty
        // window.
        guard UpdateHighlightsView.hasContent else {
            markUpdateHighlightsSeen()
            return false
        }
        showUpdateHighlights()
        return true
    }

    private func showUpdateHighlights() {
        closePopover()
        if let window = updateHighlightsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateHighlightsView(
            onFinish: { [weak self] in
                self?.markUpdateHighlightsSeen()
                self?.updateHighlightsWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.highlightsTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        updateHighlightsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateHighlightsWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    private func markUpdateHighlightsSeen() {
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion,
                                  forKey: DefaultsKey.updateHighlightsSeenVersion)
    }

    private func showUpdateShowcaseIntroIfNeeded() -> Bool {
        guard AppInfo.version == UpdateShowcaseInfo.releaseVersion else {
            UpdateShowcaseInfo.cleanupCache()
            return false
        }
        guard UserDefaults.standard.string(forKey: DefaultsKey.updateShowcaseIntroVersion)
                != UpdateShowcaseInfo.releaseVersion else {
            UpdateShowcaseInfo.cleanupCache()
            return false
        }
        showUpdateShowcaseIntro()
        return true
    }

    private func showUpdateShowcaseIntro() {
        closePopover()
        if let window = updateShowcaseWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateShowcaseIntroView(
            onClose: { [weak self] in
                self?.markUpdateShowcaseIntroSeen()
                self?.updateShowcaseWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.updateShowcaseTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        updateShowcaseWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateShowcaseWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    private func showSupportUpdateIntroIfNeeded() -> Bool {
        // Same shape as the showcase gate: the window belongs to one specific
        // release. Any other version never shows it, so an update that is not
        // that release cannot resurrect the ask.
        guard SupportUpdateIntroInfo.shouldShow(
            appVersion: AppInfo.version,
            lastSeenVersion: UserDefaults.standard.string(forKey: DefaultsKey.supportUpdateIntroVersion)
        ) else { return false }
        showSupportUpdateIntro()
        return true
    }

    private func showSupportUpdateIntro() {
        closePopover()
        if let window = supportIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateSupportIntroView(
            onFinish: { [weak self] in
                self?.supportIntroCanClose = true
                self?.markSupportUpdateIntroSeen()
                self?.supportIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.homebrewOfficialIntroTitle
        window.styleMask = [.titled, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        supportIntroCanClose = false
        centerIntroWindow(window)
        supportIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.supportIntroWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    /// True on the release that introduced Dock Preview, or any later one.
    private var isAtLeastDockPreviewRelease: Bool {
        let current = AppInfo.version
        let intro = DockPreviewIntroInfo.releaseVersion
        return current == intro || UpdateService.isNewer(current, than: intro)
    }

    private func showDockPreviewIntroIfNeeded() {
        // Show on the Dock Preview release or any later version, so users who
        // skip versions still get it once, and never re-show it once seen.
        guard isAtLeastDockPreviewRelease else { return }
        guard UserDefaults.standard.string(forKey: DefaultsKey.dockPreviewIntroVersion) == nil else { return }
        showDockPreviewIntro()
    }

    private func showDockPreviewIntro() {
        closePopover()
        if let window = dockPreviewIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: DockPreviewIntroView(
            onDismiss: { [weak self] in
                self?.markDockPreviewIntroSeen()
                self?.dockPreviewIntroWindow?.close()
            },
            onEnable: { [weak self] in
                UserDefaults.standard.set(true, forKey: DefaultsKey.dockPreviewEnabled)
                DockPreviewService.shared.syncWithPreferences()
                self?.markDockPreviewIntroSeen()
                self?.dockPreviewIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.dockPreviewName
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        dockPreviewIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.dockPreviewIntroWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    /// Centers one of the windows whose content decides its own size (the
    /// onboarding, the tour, the release notes and the two intros). The size
    /// always comes from the view itself: asking for any other size leaves
    /// the layout engine correcting a window that was already placed, and on
    /// some systems that ends the app instead of settling. The origin is kept
    /// inside the visible area, so a window taller than the screen starts at
    /// the top instead of hanging below it.
    private func centerIntroWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        if let fitting = window.contentViewController?.view.fittingSize,
           fitting.width > 0, fitting.height > 0 {
            window.setContentSize(fitting)
        }
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let size = window.frame.size
        let x = min(max(visible.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(visible.midY - size.height / 2, visible.minY), max(visible.minY, visible.maxY - size.height))
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// The pre-install update preview, shown before any download from BOTH the
    /// Settings install button and the menu panel's update banner (the blue
    /// button most people use), so the changelog is always seen first. In the
    /// Developer build `downloadAndInstall()` is a no-op, so confirming is safe.
    func showUpdatePreview() {
        guard case let .available(version) = UpdateService.shared.state else { return }
        closePopover()
        if let window = updatePreviewWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdatePreviewView(
            version: version,
            notes: UpdateService.shared.availableNotes,
            onUpdate: { [weak self] in
                self?.updatePreviewWindow?.close()
                UpdateService.shared.downloadAndInstall()
            },
            onCancel: { [weak self] in
                self?.updatePreviewWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.tabReleaseNotes
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        updatePreviewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updatePreviewWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        saveSettingsWindowSize(window)
    }

    /// Remembers the user-chosen Settings size (as content size, so the
    /// restore is title bar independent).
    private func saveSettingsWindowSize(_ window: NSWindow) {
        guard let size = window.contentView?.frame.size else { return }
        UserDefaults.standard.set(Double(size.width), forKey: DefaultsKey.settingsWindowWidth)
        UserDefaults.standard.set(Double(size.height), forKey: DefaultsKey.settingsWindowHeight)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === supportIntroWindow else { return true }
        return supportIntroCanClose || isTerminating
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            // Covers size changes that end without a live resize (zoom).
            saveSettingsWindowSize(window)
            return
        }
        if window === onboardingWindow {
            onboardingWindow = nil
            // Closing the window mid-flow counts as "skip" — but quitting (e.g.
            // the relaunch macOS forces after granting Screen Recording) must NOT,
            // so the flow can resume where it stopped.
            guard !isTerminating else { return }
            markOnboardingComplete()
        }
        if window === dockPreviewIntroWindow {
            dockPreviewIntroWindow = nil
            guard !isTerminating else { return }
            markDockPreviewIntroSeen()
        }
        if window === supportIntroWindow {
            supportIntroWindow = nil
            supportIntroCanClose = false
            guard !isTerminating else { return }
            markSupportUpdateIntroSeen()
        }
        if window === updateShowcaseWindow {
            updateShowcaseWindow = nil
            guard !isTerminating else { return }
            markUpdateShowcaseIntroSeen()
        }
        if window === updateHighlightsWindow {
            updateHighlightsWindow = nil
            guard !isTerminating else { return }
            markUpdateHighlightsSeen()
        }
        if window === updatePreviewWindow {
            updatePreviewWindow = nil
        }
    }

    /// Marks both the first run and this version's feature tour as seen, so
    /// neither reappears on the next launch.
    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
        UserDefaults.standard.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
        markDockPreviewIntroSeenIfCurrentUpdate()
        markSupportUpdateIntroSeenIfCurrentUpdate()
        markUpdateShowcaseIntroSeenIfCurrentUpdate()
        // A clean install that just saw everything in onboarding should not
        // then get the update tour; only people who updated get it.
        markUpdateHighlightsSeen()
    }

    private func markDockPreviewIntroSeenIfCurrentUpdate() {
        // A clean install that just finished onboarding on the Dock Preview
        // release (or later) should not then be shown the intro popup.
        guard isAtLeastDockPreviewRelease else { return }
        markDockPreviewIntroSeen()
    }

    private func markDockPreviewIntroSeen() {
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.dockPreviewIntroVersion)
    }

    private func markSupportUpdateIntroSeenIfCurrentUpdate() {
        markSupportUpdateIntroSeen()
    }

    private func markSupportUpdateIntroSeen() {
        UserDefaults.standard.set(SupportUpdateIntroInfo.releaseVersion,
                                  forKey: DefaultsKey.supportUpdateIntroVersion)
    }

    private func markUpdateShowcaseIntroSeenIfCurrentUpdate() {
        guard AppInfo.version == UpdateShowcaseInfo.releaseVersion else { return }
        markUpdateShowcaseIntroSeen()
    }

    private func markUpdateShowcaseIntroSeen() {
        UserDefaults.standard.set(UpdateShowcaseInfo.releaseVersion,
                                  forKey: DefaultsKey.updateShowcaseIntroVersion)
    }
}
