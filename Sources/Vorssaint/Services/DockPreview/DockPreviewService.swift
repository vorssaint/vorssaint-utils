// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

final class DockPreviewService: ObservableObject {
    static let shared = DockPreviewService()

    @Published private(set) var isRunning = false
    @Published private(set) var blockedReason: DockPreviewBlockedReason?
    /// Whether the Dock currently uses auto-hide. Surfaced so the UI can warn
    /// that this still-beta feature is rougher in that mode (the native Dock
    /// slides away mid-interaction and no public API can hold it open).
    @Published private(set) var dockAutohide = false
    @Published private(set) var dockMagnification = false
    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var currentAppName: String?
    @Published private(set) var isPinned = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settingsTimer: Timer?
    private var pendingHover: PendingHover?
    private var pendingHide: DispatchWorkItem?
    private var pendingPeekReconcile: DispatchWorkItem?
    private var lastAXMousePoint: CGPoint?
    private var lastAppKitMousePoint: CGPoint?
    private var panel: NSPanel?
    /// The window the user came from, captured when a session first opens and
    /// carried unchanged across app switches so cancelling always returns there —
    /// not to a window we only peeked. Cleared when the session fully ends.
    private var sessionOrigin: SessionOrigin?
    /// The app of the currently shown panel. `nil` means no session.
    private var currentSessionPID: pid_t?
    /// True once the cursor has reached the panel. Before this, the icon and
    /// corridor keep the session alive so the icon→panel hop survives; after it,
    /// only the panel keeps it alive, so returning to the Dock closes or switches
    /// instead of pinning the panel open on the icon (or, with auto-hide, on the
    /// ghost icon region at the screen edge).
    private var hasEnteredPanel = false
    private var activePanelFrame: CGRect?
    private var activeCorridor: HoverCorridor?
    private var activeIconFrame: CGRect?
    private var activeDockPreferences: DockPreviewPreferences?
    private var activePeekWindowID: CGWindowID?
    /// The card the cursor is currently over, reconciled into an actual peek on a
    /// short debounce so moving between cards never flickers through the origin.
    private var desiredPeek: SwitcherItem?
    private var touchedWindows: [CGWindowID: TouchedWindow] = [:]
    private var touchedApps: [pid_t: Bool] = [:]
    private var pendingMinimizeConfirmations: [CGWindowID: UUID] = [:]
    private var pinnedPanels: [UUID: DockPreviewPinnedPanel] = [:]
    private var pinnedPanelWindows: [UUID: NSPanel] = [:]
    private var dockPIDCache: pid_t?
    private var cachedPreferences: DockPreviewPreferences?

    private init() {}

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func syncWithPreferences() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled)
        cachedPreferences = readDockPreferences()
        dockAutohide = cachedPreferences?.autohide ?? false
        dockMagnification = cachedPreferences?.magnification ?? false

        if enabled {
            startSettingsTimer()
        } else {
            stopSettingsTimer()
        }

        let availability = DockPreviewSupport.availability(
            enabled: enabled,
            hasAccessibility: Permissions.shared.accessibility,
            hasScreenRecording: Permissions.shared.screenRecording,
            preferences: cachedPreferences
        )
        blockedReason = availability.blockedReason

        guard availability.canRun else {
            stopTap()
            endSession(restore: true)
            closeAllPinnedPanels()
            isRunning = false
            return
        }

        if dockProcessID() == nil {
            blockedReason = .dockUnavailable
            stopTap()
            endSession(restore: true)
            closeAllPinnedPanels()
            isRunning = false
            return
        }

        startTap()
    }

    func stop() {
        stopSettingsTimer()
        stopTap()
        endSession(restore: true)
        closeAllPinnedPanels()
        isRunning = false
        blockedReason = nil
    }

    func preview(_ item: SwitcherItem) {
        guard isVisible, windows.contains(item) else { return }
        cancelPendingHide()
        desiredPeek = item
        selectedWindowID = item.windowID
        schedulePeekReconcile()
    }

    func endPreview(_ item: SwitcherItem) {
        guard isVisible else { return }
        // Only the card that currently owns the peek may release it. If the
        // cursor has already moved to another card, that card is now in charge,
        // so a late "ended" for the old card must not undo the new peek. This is
        // what makes the reconcile order-independent across card-to-card moves.
        guard desiredPeek?.id == item.id else { return }
        desiredPeek = nil
        schedulePeekReconcile()
    }

    private func schedulePeekReconcile() {
        cancelPendingPeekReconcile()
        let work = DispatchWorkItem { [weak self] in self?.reconcilePeek() }
        pendingPeekReconcile = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.peekDelay, execute: work)
    }

    /// Brings the screen in line with `desiredPeek`: peek the hovered window, or
    /// revert to the origin when nothing is hovered. Debounced, so a flick across
    /// several cards resolves to a single activation of the final card.
    private func reconcilePeek() {
        pendingPeekReconcile = nil
        guard isVisible else { return }

        selectedWindowID = desiredPeek?.windowID

        let targetWindowID = desiredPeek?.windowID
        guard targetWindowID != activePeekWindowID else { return }

        if let item = desiredPeek {
            recordTouch(item)
            activePeekWindowID = item.windowID
            WindowActivator.activate(item, retry: false)
        } else {
            activePeekWindowID = nil
            restoreOrigin(retry: false)
        }
    }

    func commit(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        cancelPendingPeekReconcile()
        desiredPeek = nil
        endSession(restore: false)
        WindowActivator.activate(item)
    }

    func closePreviewPanel() {
        guard isVisible else { return }
        endSession(restore: true)
    }

    func close(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              let windowID = item.windowID,
              WindowActivator.closeWindow(windowID: windowID, pid: item.pid)
        else { return }

        cancelPendingPeekReconcile()
        if desiredPeek?.id == item.id {
            desiredPeek = nil
        }
        if selectedWindowID == windowID {
            selectedWindowID = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.finishClosing(item, windowID: windowID, attempt: 0)
        }
    }

    func toggleMinimized(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              let windowID = item.windowID,
              !item.isFullscreen
        else { return }

        let shouldMinimize = !item.isMinimized
        let restoreOriginAfterMinimize = DockPreviewSupport.shouldRestoreOriginAfterMinimize(
            originPID: sessionOrigin?.pid,
            originWindowID: sessionOrigin?.windowID,
            targetPID: item.pid,
            targetWindowID: windowID
        )
        guard WindowActivator.setWindowMinimized(shouldMinimize, windowID: windowID, pid: item.pid) else { return }
        if shouldMinimize && !restoreOriginAfterMinimize {
            sessionOrigin = nil
        }
        touchedWindows[windowID] = TouchedWindow(pid: item.pid, wasMinimized: false)
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: item.pid,
                                     minimized: shouldMinimize,
                                     restoreOriginAfterMinimize: restoreOriginAfterMinimize,
                                     attempt: 0)
    }

    func togglePinned() {
        guard isVisible, let panel, !windows.isEmpty else { return }
        createPinnedPanel(from: panel.frame)
        endSession(restore: true)
    }

    func selectPreviousWindow() {
        selectAdjacentWindow(offset: -1)
    }

    func selectNextWindow() {
        selectAdjacentWindow(offset: 1)
    }

    private func selectAdjacentWindow(offset: Int) {
        guard isVisible, windows.count > 1 else { return }
        let ids = windows.compactMap(\.windowID)
        guard let nextWindowID = DockPreviewSupport.adjacentWindowID(selectedWindowID: selectedWindowID,
                                                                     windowIDs: ids,
                                                                     offset: offset),
              let next = windows.first(where: { $0.windowID == nextWindowID })
        else { return }
        preview(next)
    }

    // MARK: - Event tap

    private func startTap() {
        guard tap == nil else {
            isRunning = true
            return
        }

        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<DockPreviewService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            blockedReason = .missingAccessibility
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        cancelPendingHover()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let point = event.location
        DispatchQueue.main.async { [weak self] in
            self?.handleOnMain(type: type, axPoint: point)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleOnMain(type: CGEventType, axPoint: CGPoint) {
        guard isRunning else { return }
        switch type {
        case .mouseMoved:
            handleMouseMoved(axPoint)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleMouseDown(axPoint)
        default:
            break
        }
    }

    private func handleMouseMoved(_ axPoint: CGPoint) {
        lastAXMousePoint = axPoint
        let point = appKitPoint(fromAX: axPoint)
        lastAppKitMousePoint = point

        if isVisible {
            if isPinned {
                switch currentZone(point: point, axPoint: axPoint) {
                case .panel:
                    hasEnteredPanel = true
                case .openingPath, .ownIcon, .otherIcon, .outside:
                    break
                }
                cancelPendingHide()
                cancelPendingHover()
                return
            }
            switch currentZone(point: point, axPoint: axPoint) {
            case .panel:
                hasEnteredPanel = true
                cancelPendingHide()
                cancelPendingHover()
            case .openingPath:
                // Crossing from the icon up to the panel — keep it alive.
                cancelPendingHide()
                cancelPendingHover()
            case .ownIcon:
                if hasEnteredPanel {
                    // Back on our own icon after using the panel: let it close so
                    // the Dock is free again. Moving to another icon still switches.
                    scheduleHideIfStillOutside()
                } else {
                    // Still resting on the icon that opened it, before reaching
                    // the panel — hold it open.
                    cancelPendingHide()
                    cancelPendingHover()
                }
            case .otherIcon(let hit):
                cancelPendingHide()
                scheduleHover(hit, delay: DockPreviewSupport.switchDelay)
            case .outside:
                // Don't cancel a half-armed switch here: a brief skip over dead
                // space on the way to another icon shouldn't starve it — it
                // re-confirms the cursor is on the icon before it fires anyway.
                scheduleHideIfStillOutside()
            }
            return
        }

        if let pendingHover,
           pendingHover.iconFrame.insetBy(dx: -6, dy: -6).contains(point) {
            return
        }

        // Only pay for an Accessibility hit-test when the cursor is in the Dock's
        // edge strip; running it on every move across the whole screen hammers AX.
        guard isNearDock(point) else {
            cancelPendingHover()
            return
        }

        guard let hit = dockHit(at: axPoint) else {
            cancelPendingHover()
            return
        }
        scheduleHover(hit)
    }

    /// Whether the cursor sits within the Dock's edge strip, so the expensive
    /// `dockHit` Accessibility call is worth making. Errs toward `true` when the
    /// Dock geometry is unknown so detection never silently stops working.
    private func isNearDock(_ point: CGPoint) -> Bool {
        guard let preferences = cachedPreferences else { return true }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let frame = screen?.frame else { return true }
        let band = DockPreviewSupport.dockProximityBand(tileSize: preferences.tileSize)
        switch preferences.orientation {
        case .bottom: return point.y <= frame.minY + band
        case .left: return point.x <= frame.minX + band
        case .right: return point.x >= frame.maxX - band
        }
    }

    /// Where the cursor stands relative to the live session. The corridor only
    /// counts before the cursor has reached the panel (`hasEnteredPanel`); after
    /// that, only the panel itself keeps the session alive.
    private func currentZone(point: CGPoint, axPoint: CGPoint) -> Zone {
        if activePanelFrame?.insetBy(dx: -DockPreviewSupport.panelStayMargin,
                                     dy: -DockPreviewSupport.panelStayMargin).contains(point) == true {
            return .panel
        }
        // Hit-test the Dock before the corridor so landing on a neighbouring icon
        // hands the session over even where the corridor's margin grazes its edge —
        // but only within the Dock's strip, to keep the AX hit-test off the hot path.
        if isNearDock(point), let hit = dockHit(at: axPoint) {
            return hit.app.processIdentifier == currentSessionPID ? .ownIcon : .otherIcon(hit)
        }
        if !hasEnteredPanel, activeCorridor?.contains(point) == true { return .openingPath }
        return .outside
    }

    private func handleMouseDown(_ axPoint: CGPoint) {
        guard isVisible else {
            cancelPendingHover()
            return
        }

        let point = appKitPoint(fromAX: axPoint)
        let isInsidePanel = activePanelFrame?.contains(point) == true
        let initialDecision = DockPreviewSupport.mouseDownDecision(isVisible: isVisible,
                                                                   isPinned: isPinned,
                                                                   isInsidePanel: isInsidePanel,
                                                                   clickedDock: false)
        if !initialDecision.shouldEndSession {
            cancelPendingHide()
            cancelPendingHover()
            return
        }
        // A click on the Dock (this app's icon or any other) hands activation to
        // the Dock itself, so don't fight it by restoring the previous window.
        let clickedDock = dockHit(at: axPoint) != nil
        let decision = DockPreviewSupport.mouseDownDecision(isVisible: isVisible,
                                                            isPinned: false,
                                                            isInsidePanel: false,
                                                            clickedDock: clickedDock)
        if decision.shouldEndSession {
            endSession(restore: decision.restoreOrigin)
        }
    }

    private func scheduleHideIfStillOutside() {
        guard !isPinned else { return }
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            guard let point = self.lastAppKitMousePoint,
                  let axPoint = self.lastAXMousePoint else {
                self.endSession(restore: true)
                return
            }
            switch self.currentZone(point: point, axPoint: axPoint) {
            case .panel, .openingPath:
                return
            case .ownIcon:
                // Closes only once the panel was actually used; an unentered
                // panel keeps resting on its opener icon.
                if self.hasEnteredPanel { self.endSession(restore: true) }
            case .otherIcon(let hit):
                self.scheduleHover(hit, delay: DockPreviewSupport.switchDelay)
            case .outside:
                self.endSession(restore: true)
            }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.hideDelay, execute: work)
    }

    // MARK: - Sessions

    private func scheduleHover(_ hit: DockHit, delay: TimeInterval = DockPreviewSupport.hoverDelay) {
        // Same app already arming: let the existing timer run to completion rather
        // than restarting it on every move, so a resting cursor isn't starved by
        // a one-frame Dock hit-test miss.
        if let pendingHover,
           pendingHover.app.processIdentifier == hit.app.processIdentifier,
           pendingHover.iconFrame.insetBy(dx: -6, dy: -6).intersects(hit.iconFrame) {
            return
        }

        cancelPendingHover()
        let token = UUID()
        let work = DispatchWorkItem { [weak self] in
            self?.beginHoverIfStillValid(token: token, initialHit: hit)
        }
        pendingHover = PendingHover(token: token, app: hit.app, iconFrame: hit.iconFrame, workItem: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginHoverIfStillValid(token: UUID, initialHit: DockHit) {
        guard pendingHover?.token == token else { return }
        let point = lastAXMousePoint ?? axPoint(fromAppKit: initialHit.iconFrame.center)
        guard let hit = dockHit(at: point),
              hit.app.processIdentifier == initialHit.app.processIdentifier
        else {
            cancelPendingHover()
            return
        }
        beginSession(hit)
    }

    private func beginSession(_ hit: DockHit) {
        guard !(isPinned && isVisible) else { return }
        cancelPendingHover()
        cancelPendingHide()

        let list = WindowEnumerator.listWindows(for: hit.app.processIdentifier, maximumCount: 12)
            .filter { $0.windowID != nil }
        // An app with no real windows shows nothing; if a panel is already up
        // (the user moved here from another app), close it cleanly.
        guard !list.isEmpty else {
            if isVisible { endSession(restore: true) }
            return
        }

        // Switching apps: revert the previous app's peek and bring its origin
        // back, but keep the panel on screen and carry the SAME origin into the
        // new session — the user still came from that first window.
        if isVisible {
            tearDownVisuals(restore: true, retryRestore: false)
        }

        if sessionOrigin == nil {
            let frontApp = NSWorkspace.shared.frontmostApplication
            sessionOrigin = frontApp.map {
                SessionOrigin(pid: $0.processIdentifier,
                              windowID: WindowActivator.focusedWindowID(for: $0.processIdentifier),
                              appName: $0.localizedName ?? "")
            }
        }

        currentSessionPID = hit.app.processIdentifier
        isPinned = false
        hasEnteredPanel = false
        currentAppName = hit.app.localizedName ?? hit.app.bundleIdentifier ?? ""
        windows = list
        previews = Dictionary(uniqueKeysWithValues: list.compactMap { item in
            item.previewWindowID.flatMap { id in
                WindowPreviewProvider.shared.cachedPreview(for: id).map { (id, $0) }
            }
        })
        selectedWindowID = nil
        desiredPeek = nil

        WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 420 * PreviewSizing.scale) { [weak self] windowID, image in
            guard let self, self.isVisible, self.windows.contains(where: { $0.previewWindowID == windowID }) else { return }
            self.previews[windowID] = image
        }

        showPanel(for: hit, itemCount: list.count)
    }

    /// Fully ends the session: tears down the panel and forgets the origin.
    private func endSession(restore: Bool) {
        cancelPendingHover()
        cancelPendingHide()
        WindowPreviewProvider.shared.cancel()
        tearDownVisuals(restore: restore, retryRestore: restore)
        sessionOrigin = nil
        isPinned = false
        panel?.orderOut(nil)
    }

    /// Reverts any peek and clears all per-app state, optionally restoring the
    /// origin window and the minimized/hidden state of anything we touched.
    /// Deliberately leaves `sessionOrigin` and the panel window alone so the
    /// same panel can be re-pointed at another app during a switch.
    ///
    /// `retryRestore` is false on a switch: a second, delayed origin activation
    /// would land after the new app's first peek and snatch focus back.
    private func tearDownVisuals(restore: Bool, retryRestore: Bool) {
        cancelPendingPeekReconcile()
        cancelPendingMinimizeConfirmations()

        let origin = sessionOrigin
        let touchedWindows = self.touchedWindows
        let touchedApps = self.touchedApps

        windows = []
        previews = [:]
        selectedWindowID = nil
        currentAppName = nil
        currentSessionPID = nil
        isPinned = false
        activePanelFrame = nil
        activeCorridor = nil
        activeIconFrame = nil
        activeDockPreferences = nil
        activePeekWindowID = nil
        desiredPeek = nil
        self.touchedWindows = [:]
        self.touchedApps = [:]

        guard restore else { return }
        restoreOrigin(origin, retry: retryRestore)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            for (windowID, state) in touchedWindows where state.wasMinimized {
                WindowActivator.setWindowMinimized(true, windowID: windowID, pid: state.pid)
            }
            for (pid, wasHidden) in touchedApps where wasHidden && pid != origin?.pid {
                NSRunningApplication(processIdentifier: pid)?.hide()
            }
        }
    }

    private func cancelPendingHover() {
        pendingHover?.workItem.cancel()
        pendingHover = nil
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func cancelPendingPeekReconcile() {
        pendingPeekReconcile?.cancel()
        pendingPeekReconcile = nil
    }

    private func cancelPendingMinimizeConfirmations() {
        pendingMinimizeConfirmations.removeAll()
    }

    private func scheduleMinimizeConfirmation(windowID: CGWindowID,
                                              pid: pid_t,
                                              minimized: Bool,
                                              restoreOriginAfterMinimize: Bool,
                                              attempt: Int) {
        let token = pendingMinimizeConfirmations[windowID] ?? UUID()
        pendingMinimizeConfirmations[windowID] = token
        let delay = DockPreviewMinimizeConfirmation.delay(for: attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.confirmMinimizedState(windowID: windowID,
                                        pid: pid,
                                        minimized: minimized,
                                        restoreOriginAfterMinimize: restoreOriginAfterMinimize,
                                        attempt: attempt,
                                        token: token)
        }
    }

    private func confirmMinimizedState(windowID: CGWindowID,
                                       pid: pid_t,
                                       minimized: Bool,
                                       restoreOriginAfterMinimize: Bool,
                                       attempt: Int,
                                       token: UUID) {
        guard isVisible,
              pendingMinimizeConfirmations[windowID] == token,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let isMinimized = WindowActivator.windowIsMinimized(windowID: windowID, pid: pid)
        if isMinimized == minimized {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID,
                                minimized: minimized,
                                restoreOriginAfterMinimize: restoreOriginAfterMinimize)
            return
        }

        guard attempt + 1 < DockPreviewMinimizeConfirmation.delays.count else {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID,
                                minimized: isMinimized,
                                restoreOriginAfterMinimize: false)
            return
        }

        _ = WindowActivator.setWindowMinimized(minimized, windowID: windowID, pid: pid)
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: pid,
                                     minimized: minimized,
                                     restoreOriginAfterMinimize: restoreOriginAfterMinimize,
                                     attempt: attempt + 1)
    }

    private func applyMinimizedState(windowID: CGWindowID,
                                     minimized: Bool,
                                     restoreOriginAfterMinimize: Bool) {
        windows = windows.map { candidate in
            candidate.windowID == windowID ? candidate.withMinimized(minimized) : candidate
        }

        if minimized {
            cancelPendingPeekReconcile()
            if desiredPeek?.windowID == windowID {
                desiredPeek = nil
            }
            if selectedWindowID == windowID {
                selectedWindowID = nil
            }
            if activePeekWindowID == windowID {
                activePeekWindowID = nil
                if restoreOriginAfterMinimize {
                    restoreOrigin(retry: false)
                }
            }
        } else {
            selectedWindowID = windowID
        }
    }

    private func restoreOrigin(retry: Bool) {
        restoreOrigin(sessionOrigin, retry: retry)
    }

    private func restoreOrigin(_ origin: SessionOrigin?, retry: Bool) {
        guard let origin else { return }
        WindowActivator.activate(pid: origin.pid,
                                 windowID: origin.windowID,
                                 appName: origin.appName,
                                 retry: retry)
    }

    private func recordTouch(_ item: SwitcherItem) {
        if touchedApps[item.pid] == nil {
            touchedApps[item.pid] = NSRunningApplication(processIdentifier: item.pid)?.isHidden ?? false
        }
        if let windowID = item.windowID, touchedWindows[windowID] == nil {
            touchedWindows[windowID] = TouchedWindow(
                pid: item.pid,
                wasMinimized: item.isMinimized || WindowActivator.windowIsMinimized(windowID: windowID, pid: item.pid)
            )
        }
    }

    private func finishClosing(_ item: SwitcherItem, windowID: CGWindowID, attempt: Int) {
        guard isVisible,
              currentSessionPID == item.pid,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let refreshed = WindowEnumerator.listWindows(for: item.pid, maximumCount: 12)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            guard attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishClosing(item, windowID: windowID, attempt: attempt + 1)
            }
            return
        }

        applyClosedWindowRemoval(windowID)
    }

    private func applyClosedWindowRemoval(_ closedWindowID: CGWindowID) {
        let wasActivePreview = activePeekWindowID == closedWindowID || desiredPeek?.windowID == closedWindowID
        let state = DockPreviewSupport.closeState(
            afterRemoving: closedWindowID,
            windowIDs: windows.compactMap(\.windowID),
            selectedWindowID: selectedWindowID,
            activePeekWindowID: activePeekWindowID,
            desiredWindowID: desiredPeek?.windowID
        )
        let remaining = Set(state.remainingWindowIDs)

        windows = windows.filter { item in
            guard let windowID = item.windowID else { return false }
            return remaining.contains(windowID)
        }
        previews = previews.filter { remaining.contains($0.key) }
        selectedWindowID = state.selectedWindowID
        activePeekWindowID = state.activePeekWindowID
        if state.desiredWindowID == nil {
            desiredPeek = nil
        }
        touchedWindows.removeValue(forKey: closedWindowID)

        if state.shouldEndSession {
            endSession(restore: true)
        } else {
            resizePanelForCurrentWindows()
            if wasActivePreview {
                restoreOrigin(retry: false)
            }
        }
    }

    // MARK: - Panel

    private func showPanel(for hit: DockHit, itemCount: Int) {
        let panel = ensurePanel()
        let screen = screen(containing: hit.iconFrame)
        let size = DockPreviewSupport.panelSize(itemCount: itemCount, screenVisibleFrame: screen.visibleFrame)
        let gap = hit.preferences.autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
        let frame = DockPreviewSupport.panelFrame(anchor: hit.iconFrame,
                                                  panelSize: size,
                                                  screenVisibleFrame: screen.visibleFrame,
                                                  orientation: hit.preferences.orientation,
                                                  gap: gap)
        activePanelFrame = frame
        activeCorridor = DockPreviewSupport.hoverCorridor(
            iconFrame: hit.iconFrame,
            panelFrame: frame,
            orientation: hit.preferences.orientation
        )
        activeIconFrame = hit.iconFrame
        activeDockPreferences = hit.preferences

        panel.setFrame(frame, display: true, animate: false)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    private func resizePanelForCurrentWindows() {
        guard let panel,
              panel.isVisible,
              let iconFrame = activeIconFrame,
              let preferences = activeDockPreferences
        else { return }

        let screen = screen(containing: iconFrame)
        let size = DockPreviewSupport.panelSize(itemCount: windows.count, screenVisibleFrame: screen.visibleFrame)
        let gap = preferences.autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
        let frame = DockPreviewSupport.panelFrame(anchor: iconFrame,
                                                  panelSize: size,
                                                  screenVisibleFrame: screen.visibleFrame,
                                                  orientation: preferences.orientation,
                                                  gap: gap)
        activePanelFrame = frame
        activeCorridor = DockPreviewSupport.hoverCorridor(
            iconFrame: iconFrame,
            panelFrame: frame,
            orientation: preferences.orientation
        )
        panel.setFrame(frame, display: true, animate: true)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = screen(containing: frame).visibleFrame
        let padding = DockPreviewSupport.edgePadding
        let minX = visibleFrame.minX + padding
        let maxX = visibleFrame.maxX - frame.width - padding
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - frame.height - padding

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }

        return CGRect(x: clamped(frame.minX, lower: minX, upper: maxX),
                      y: clamped(frame.minY, lower: minY, upper: maxY),
                      width: frame.width,
                      height: frame.height)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: DockPreviewPanelView(service: self))
        self.panel = panel
        return panel
    }

    private func createPinnedPanel(from sourceFrame: CGRect) {
        let pinned = DockPreviewPinnedPanel(
            appPID: windows[0].pid,
            windows: windows,
            previews: previews,
            selectedWindowID: selectedWindowID,
            currentAppName: currentAppName,
            onClose: { [weak self] id in
                self?.closePinnedPanel(id)
            }
        )
        let panel = makePinnedPanel(for: pinned)
        pinned.panel = panel
        let frame = clampedPanelFrame(sourceFrame)

        pinnedPanels[pinned.id] = pinned
        pinnedPanelWindows[pinned.id] = panel

        panel.setFrame(frame, display: true, animate: false)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    private func makePinnedPanel(for pinned: DockPreviewPinnedPanel) -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: DockPreviewPinnedPanelView(panel: pinned))
        return panel
    }

    private func closePinnedPanel(_ id: UUID) {
        if let panel = pinnedPanelWindows.removeValue(forKey: id) {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }
        pinnedPanels.removeValue(forKey: id)
    }

    private func closeAllPinnedPanels() {
        for id in Array(pinnedPanelWindows.keys) {
            closePinnedPanel(id)
        }
    }

    private func screen(containing rect: CGRect) -> NSScreen {
        let point = rect.center
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.withMouse
    }

    // MARK: - Dock hit testing

    private func dockHit(at axPoint: CGPoint) -> DockHit? {
        guard let preferences = cachedPreferences ?? readDockPreferences(),
              !preferences.magnification,
              let dockPID = dockProcessID()
        else { return nil }

        let system = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(axPoint.x), Float(axPoint.y), &rawElement) == .success,
              let element = rawElement
        else { return nil }

        for candidate in elementAndParents(from: element) {
            guard pid(of: candidate) == dockPID,
                  let frame = appKitFrame(of: candidate),
                  let app = runningApplication(forDockElement: candidate)
            else { continue }
            return DockHit(app: app, iconFrame: frame, preferences: preferences)
        }
        return nil
    }

    private func runningApplication(forDockElement element: AXUIElement) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }

        if let url = urlAttribute(element) {
            let standardized = url.standardizedFileURL.path
            if let app = running.first(where: { $0.bundleURL?.standardizedFileURL.path == standardized }) {
                return app
            }
        }

        let labels = labelCandidates(from: element)
        guard !labels.isEmpty else { return nil }
        return running.first { app in
            let names = [
                app.localizedName,
                app.bundleURL?.deletingPathExtension().lastPathComponent,
                app.bundleURL?.lastPathComponent.replacingOccurrences(of: ".app", with: ""),
            ].compactMap { $0 }.map(normalizeLabel)
            return labels.contains { label in names.contains(normalizeLabel(label)) }
        }
    }

    private func labelCandidates(from element: AXUIElement) -> [String] {
        var result: [String] = []
        for candidate in elementAndParents(from: element) {
            for attribute in [kAXTitleAttribute as String,
                              kAXDescriptionAttribute as String,
                              kAXHelpAttribute as String,
                              kAXValueAttribute as String] {
                if let value = stringAttribute(candidate, attribute), !value.isEmpty {
                    result.append(value)
                }
            }
        }
        return result
    }

    private func elementAndParents(from element: AXUIElement) -> [AXUIElement] {
        var result = [element]
        var current = element
        for _ in 0..<8 {
            guard let parent = elementAttribute(current, kAXParentAttribute as String) else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    private func dockProcessID() -> pid_t? {
        if let dockPIDCache,
           NSRunningApplication(processIdentifier: dockPIDCache)?.isTerminated == false {
            return dockPIDCache
        }
        let pid = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.dock"
        }?.processIdentifier
        dockPIDCache = pid
        return pid
    }

    // MARK: - Dock preferences

    private func startSettingsTimer() {
        guard settingsTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.syncWithPreferences()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        settingsTimer = timer
    }

    private func stopSettingsTimer() {
        settingsTimer?.invalidate()
        settingsTimer = nil
    }

    private func readDockPreferences() -> DockPreviewPreferences? {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")
            ?? UserDefaults(suiteName: "com.apple.dock")?.dictionaryRepresentation()
        guard let domain, !domain.isEmpty else {
            return nil
        }
        return DockPreviewPreferences.sanitized(
            orientation: domain["orientation"] as? String,
            autohide: boolValue(domain["autohide"]),
            tileSize: doubleValue(domain["tilesize"]),
            magnification: boolValue(domain["magnification"])
        )
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? CGFloat { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    // MARK: - AX helpers

    private func pid(of element: AXUIElement) -> pid_t? {
        var pid = pid_t()
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func appKitFrame(of element: AXUIElement) -> CGRect? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String),
              size.width > 0,
              size.height > 0
        else { return nil }
        return appKitFrame(fromAX: CGRect(origin: origin, size: size))
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return value as? String
    }

    private func urlAttribute(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let value
        else { return nil }
        return value as? URL
    }

    private func normalizeLabel(_ value: String) -> String {
        let firstLine = value.components(separatedBy: .newlines).first ?? value
        return firstLine
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func appKitPoint(fromAX point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: menuBarScreenTopY - point.y)
    }

    private func axPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: menuBarScreenTopY - point.y)
    }

    private func appKitFrame(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: menuBarScreenTopY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    private var menuBarScreenTopY: CGFloat {
        let menuBarScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }
        return (menuBarScreen ?? NSScreen.main ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }
}

private struct DockHit {
    let app: NSRunningApplication
    let iconFrame: CGRect
    let preferences: DockPreviewPreferences
}

private enum Zone {
    case panel
    case openingPath
    case ownIcon
    case otherIcon(DockHit)
    case outside
}

private struct PendingHover {
    let token: UUID
    let app: NSRunningApplication
    let iconFrame: CGRect
    let workItem: DispatchWorkItem
}

private struct SessionOrigin {
    let pid: pid_t
    let windowID: CGWindowID?
    let appName: String
}

private struct TouchedWindow {
    let pid: pid_t
    let wasMinimized: Bool
}

private enum DockPreviewMinimizeConfirmation {
    static let delays: [TimeInterval] = [0.04, 0.12, 0.28, 0.55]

    static func delay(for attempt: Int) -> TimeInterval {
        delays[min(max(0, attempt), delays.count - 1)]
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

final class DockPreviewPinnedPanel: ObservableObject, Identifiable {
    private static let refreshInterval: TimeInterval = 0.75
    private static let maximumWindowCount = 12

    let id = UUID()
    @Published private(set) var windows: [SwitcherItem]
    @Published private(set) var previews: [CGWindowID: CGImage]
    @Published private(set) var selectedWindowID: CGWindowID?
    let currentAppName: String?

    weak var panel: NSPanel?

    private let appPID: pid_t
    private let onClose: (UUID) -> Void
    private let previewProvider = WindowPreviewProvider()
    private var refreshTimer: Timer?
    private var pendingMinimizeConfirmations: [CGWindowID: UUID] = [:]

    init(appPID: pid_t,
         windows: [SwitcherItem],
         previews: [CGWindowID: CGImage],
         selectedWindowID: CGWindowID?,
         currentAppName: String?,
         onClose: @escaping (UUID) -> Void) {
        self.appPID = appPID
        self.windows = windows
        self.previews = previews
        self.selectedWindowID = selectedWindowID
        self.currentAppName = currentAppName
        self.onClose = onClose
        startRefreshTimer()
    }

    deinit {
        refreshTimer?.invalidate()
        pendingMinimizeConfirmations.removeAll()
        previewProvider.cancel()
    }

    func preview(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        selectedWindowID = item.windowID
    }

    func endPreview(_ item: SwitcherItem) {
        guard selectedWindowID == item.windowID else { return }
    }

    func commit(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        selectedWindowID = item.windowID
        WindowActivator.activate(item)
    }

    func close(_ item: SwitcherItem) {
        guard windows.contains(item),
              let windowID = item.windowID,
              WindowActivator.closeWindow(windowID: windowID, pid: item.pid)
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.finishClosing(item, windowID: windowID, attempt: 0)
        }
    }

    func toggleMinimized(_ item: SwitcherItem) {
        guard windows.contains(item),
              let windowID = item.windowID,
              !item.isFullscreen
        else { return }

        let shouldMinimize = !item.isMinimized
        guard WindowActivator.setWindowMinimized(shouldMinimize, windowID: windowID, pid: item.pid) else { return }
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: item.pid,
                                     minimized: shouldMinimize,
                                     attempt: 0)
    }

    func closePreviewPanel() {
        refreshTimer?.invalidate()
        pendingMinimizeConfirmations.removeAll()
        previewProvider.cancel()
        onClose(id)
    }

    func selectPreviousWindow() {
        selectAdjacentWindow(offset: -1)
    }

    func selectNextWindow() {
        selectAdjacentWindow(offset: 1)
    }

    private func selectAdjacentWindow(offset: Int) {
        let ids = windows.compactMap(\.windowID)
        guard let nextWindowID = DockPreviewSupport.adjacentWindowID(selectedWindowID: selectedWindowID,
                                                                     windowIDs: ids,
                                                                     offset: offset)
        else { return }
        selectedWindowID = nextWindowID
    }

    private func scheduleMinimizeConfirmation(windowID: CGWindowID,
                                              pid: pid_t,
                                              minimized: Bool,
                                              attempt: Int) {
        let token = pendingMinimizeConfirmations[windowID] ?? UUID()
        pendingMinimizeConfirmations[windowID] = token
        let delay = DockPreviewMinimizeConfirmation.delay(for: attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.confirmMinimizedState(windowID: windowID,
                                        pid: pid,
                                        minimized: minimized,
                                        attempt: attempt,
                                        token: token)
        }
    }

    private func confirmMinimizedState(windowID: CGWindowID,
                                       pid: pid_t,
                                       minimized: Bool,
                                       attempt: Int,
                                       token: UUID) {
        guard pendingMinimizeConfirmations[windowID] == token,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let isMinimized = WindowActivator.windowIsMinimized(windowID: windowID, pid: pid)
        if isMinimized == minimized {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID, minimized: minimized)
            return
        }

        guard attempt + 1 < DockPreviewMinimizeConfirmation.delays.count else {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID, minimized: isMinimized)
            return
        }

        _ = WindowActivator.setWindowMinimized(minimized, windowID: windowID, pid: pid)
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: pid,
                                     minimized: minimized,
                                     attempt: attempt + 1)
    }

    private func applyMinimizedState(windowID: CGWindowID, minimized: Bool) {
        windows = windows.map { candidate in
            candidate.windowID == windowID ? candidate.withMinimized(minimized) : candidate
        }
        selectedWindowID = minimized ? nil : windowID
    }

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshWindows()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refreshWindows() {
        let previousIDs = windows.compactMap(\.windowID)
        let refreshed = WindowEnumerator.listWindows(for: appPID, maximumCount: Self.maximumWindowCount)
            .filter { $0.windowID != nil }
        guard !refreshed.isEmpty else {
            closePreviewPanel()
            return
        }

        let refreshedIDs = refreshed.compactMap(\.windowID)
        let windowIDsChanged = refreshedIDs != previousIDs
        let windowsChanged = refreshed != windows
        let missingPreview = refreshed.contains { item in
            guard let windowID = item.previewWindowID else { return false }
            return previews[windowID] == nil
        }
        guard windowIDsChanged || windowsChanged || missingPreview else { return }

        windows = refreshed
        previews = previews.filter { refreshedIDs.contains($0.key) }
        for item in refreshed {
            guard let windowID = item.previewWindowID,
                  previews[windowID] == nil,
                  let cached = WindowPreviewProvider.shared.cachedPreview(for: windowID)
            else { continue }
            previews[windowID] = cached
        }

        if let selectedWindowID, !refreshedIDs.contains(selectedWindowID) {
            self.selectedWindowID = refreshedIDs.first
        } else if selectedWindowID == nil {
            selectedWindowID = refreshedIDs.first
        }

        if windowIDsChanged {
            resizePanel()
        }
        refreshMissingPreviews(for: refreshed,
                               windowIDsChanged: windowIDsChanged,
                               missingPreview: missingPreview)
    }

    private func refreshMissingPreviews(for items: [SwitcherItem],
                                        windowIDsChanged: Bool,
                                        missingPreview: Bool) {
        guard windowIDsChanged || missingPreview else { return }

        previewProvider.refreshPreviews(for: items, maxPixelSize: 420 * PreviewSizing.scale) { [weak self] windowID, image in
            guard let self, self.windows.contains(where: { $0.previewWindowID == windowID }) else { return }
            self.previews[windowID] = image
        }
    }

    private func finishClosing(_ item: SwitcherItem, windowID: CGWindowID, attempt: Int) {
        guard windows.contains(where: { $0.windowID == windowID }) else { return }

        let refreshed = WindowEnumerator.listWindows(for: item.pid, maximumCount: 12)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            guard attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishClosing(item, windowID: windowID, attempt: attempt + 1)
            }
            return
        }

        windows.removeAll { $0.windowID == windowID }
        previews.removeValue(forKey: windowID)
        if selectedWindowID == windowID {
            selectedWindowID = windows.first?.windowID
        }
        if windows.isEmpty {
            closePreviewPanel()
        } else {
            resizePanel()
        }
    }

    private func resizePanel() {
        guard let panel else { return }
        let size = DockPreviewSupport.panelSize(itemCount: windows.count,
                                                screenVisibleFrame: screen(containing: panel.frame).visibleFrame)
        var frame = panel.frame
        frame.size = size
        panel.setFrame(clampedPanelFrame(frame), display: true, animate: true)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = screen(containing: frame).visibleFrame
        let padding = DockPreviewSupport.edgePadding
        let minX = visibleFrame.minX + padding
        let maxX = visibleFrame.maxX - frame.width - padding
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - frame.height - padding

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }

        return CGRect(x: clamped(frame.minX, lower: minX, upper: maxX),
                      y: clamped(frame.minY, lower: minY, upper: maxY),
                      width: frame.width,
                      height: frame.height)
    }

    private func screen(containing rect: CGRect) -> NSScreen {
        let point = rect.center
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.withMouse
    }
}
