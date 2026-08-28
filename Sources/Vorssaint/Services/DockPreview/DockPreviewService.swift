// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

@discardableResult
private func requestDockPreviewApplicationQuit(_ item: SwitcherItem) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: item.pid),
          !app.isTerminated else { return false }
    return app.terminate()
}

final class DockPreviewService: ObservableObject {
    static let shared = DockPreviewService()

    @Published private(set) var isRunning = false
    @Published private(set) var blockedReason: DockPreviewBlockedReason?
    /// Whether the Dock currently uses auto-hide. Surfaced so the UI can warn
    /// that this still-beta feature is rougher in that mode (the native Dock
    /// slides away mid-interaction and no public API can hold it open).
    @Published private(set) var dockAutohide = false
    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var currentAppName: String?
    @Published private(set) var isPinned = false
    /// Which edge the Dock is on, so the panel can run its cards along it.
    @Published private(set) var orientation: DockPreviewOrientation = .bottom
    private var isDraggingWindow = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settingsTimer: Timer?
    private var dockVisibilityTimer: Timer?
    private var didReattachForSession = false
    private var reattachGraceFrame: CGRect?
    /// Where the pointer was when the panel moved out from under it. The grace
    /// region covers a pointer that has not moved; once this one genuinely
    /// travels, it is judged against the panel where the panel actually is.
    private var reattachGraceOrigin: CGPoint?
    private var pendingHover: PendingHover?
    private var pendingHide: DispatchWorkItem?
    private var lastMoveSampledAt: TimeInterval = 0
    private var pendingMove: DispatchWorkItem?
    private var pendingMovePoint: CGPoint?
    private var lastAXMousePoint: CGPoint?
    private var lastAppKitMousePoint: CGPoint?
    private var panel: NSPanel?
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
        let enabled = AppFeature.dockPreview.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled)
        cachedPreferences = readDockPreferences()
        dockAutohide = cachedPreferences?.autohide ?? false

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
            endSession()
            closeAllPinnedPanels()
            isRunning = false
            return
        }

        if dockProcessID() == nil {
            blockedReason = .dockUnavailable
            stopTap()
            endSession()
            closeAllPinnedPanels()
            isRunning = false
            return
        }

        startTap()
    }

    func stop() {
        stopSettingsTimer()
        stopTap()
        endSession()
        closeAllPinnedPanels()
        isRunning = false
        blockedReason = nil
    }

    func preview(_ item: SwitcherItem) {
        guard isVisible, windows.contains(item) else { return }
        cancelPendingHide()
        selectedWindowID = item.windowID
    }

    /// Whether a preview panel (session or pinned) covers the given top-left-
    /// origin global point. DockClickService asks before treating a click near
    /// the Dock as an icon click: panels can dip into the Dock's edge band and
    /// their card clicks must stay theirs. Main-thread only, like all panel
    /// state here.
    func panelCovers(axPoint: CGPoint) -> Bool {
        let point = appKitPoint(fromAX: axPoint)
        if isVisible, activePanelFrame?.contains(point) == true { return true }
        return pinnedPanelWindows.values.contains { $0.isVisible && $0.frame.contains(point) }
    }

    /// A Dock icon click was handled — and swallowed — by DockClickService, so
    /// the listen-only tap here never sees that mouseDown. Mirror what a native
    /// Dock click does to the session so the panel cannot stay open with stale
    /// window state.
    func dockClickWasHandled() {
        cancelPendingHover()
        guard isVisible else { return }
        let decision = DockPreviewSupport.mouseDownDecision(isVisible: isVisible,
                                                            isPinned: isPinned,
                                                            isInsidePanel: false)
        if decision.shouldEndSession {
            endSession()
        } else {
            cancelPendingHide()
        }
    }

    func endPreview(_ item: SwitcherItem) {
        guard isVisible else { return }
        guard selectedWindowID == item.windowID else { return }
        selectedWindowID = nil
    }

    func commit(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        endSession()
        WindowActivator.activate(item)
    }

    func closePreviewPanel() {
        guard isVisible else { return }
        endSession()
    }

    func close(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              let windowID = item.windowID
        else { return }

        DockPreviewSupport.performCloseAction(
            quitAppOnClose: UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewQuitAppOnClose),
            requestQuit: { requestDockPreviewApplicationQuit(item) },
            closeWindow: {
                WindowActivator.closeWindowIncludingHiddenState(item) { [weak self] didClose in
                    guard didClose, let self else { return }
                    if self.selectedWindowID == windowID {
                        self.selectedWindowID = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        self?.finishClosing(item, windowID: windowID, attempt: 0)
                    }
                }
            }
        )
    }

    func toggleMinimized(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              let windowID = item.windowID,
              !item.isFullscreen
        else { return }

        let shouldMinimize = !item.isMinimized
        guard WindowActivator.setWindowMinimized(shouldMinimize,
                                                 windowID: windowID,
                                                 pid: item.windowOwnerPID) else { return }
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: item.windowOwnerPID,
                                     minimized: shouldMinimize,
                                     attempt: 0)
    }

    // MARK: - Drag to place

    /// Lifts a preview card into a pointer-following stand-in. The real window
    /// is not touched until the drop, so an abandoned drag changes nothing.
    ///
    /// Minimized and fullscreen windows are refused: a minimized window has no
    /// on-screen position to aim at, and a fullscreen one owns its Space and
    /// ignores the position it is given.
    func beginWindowDrag(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              DockPreviewSupport.canDragToPlace(hasWindowID: item.windowID != nil,
                                                isFullscreen: item.isFullscreen),
              let image = item.previewWindowID.flatMap({ previews[$0] })
        else { return }

        isDraggingWindow = true
        cancelPendingHide()
        cancelPendingHover()
        DockPreviewDragGhost.shared.begin(image: image, at: NSEvent.mouseLocation)
    }

    func updateWindowDrag() {
        guard isDraggingWindow else { return }
        DockPreviewDragGhost.shared.move(to: NSEvent.mouseLocation)
    }

    /// Drops the window where the stand-in was: its top-left corner goes to the
    /// pointer and the window keeps the size the user gave it, restored and
    /// carried to this desktop if it was somewhere else. The session ends
    /// either way, so a drop that could not move the window still gets the user
    /// out of the panel instead of leaving it hanging over the desktop.
    func endWindowDrag(_ item: SwitcherItem) {
        guard isDraggingWindow else { return }
        isDraggingWindow = false
        DockPreviewDragGhost.shared.end()

        guard item.windowID != nil else {
            endSession()
            return
        }
        let pointer = NSEvent.mouseLocation
        let visibleFrame = (NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.withMouse)?.visibleFrame ?? .zero
        let origin = axPoint(fromAppKit: DockPreviewSupport.dragOrigin(
            pointer: pointer,
            windowSize: item.frame.size,
            visibleFrame: visibleFrame
        ))
        let moved = WindowActivator.place(item, origin: origin, pointer: pointer)
        endSession()
        if moved {
            WindowActivator.activate(item)
            WindowActivator.focusPlacedWindow(item)
        }
    }

    func togglePinned() {
        guard isVisible, let panel, !windows.isEmpty else { return }
        createPinnedPanel(from: panel.frame)
        endSession()
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
        cancelPendingMove()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let point = event.location
        // The tap sees every mouse move on the whole screen, and nearly all of
        // them happen far from the Dock with nothing open — paying a closure
        // allocation and a main-queue hop for each one keeps the CPU warm all
        // day. The tap's run-loop source lives on the main run loop, so this
        // callback already runs on the main thread and may read panel state
        // and settle those moves synchronously for free.
        if type == .mouseMoved {
            if discardFarMouseMove(axPoint: point) {
                cancelPendingMove()
                return Unmanaged.passUnretained(event)
            }
            guard admitMouseMove(axPoint: point) else {
                return Unmanaged.passUnretained(event)
            }
        } else {
            cancelPendingMove()
        }
        DispatchQueue.main.async { [weak self] in
            self?.handleOnMain(type: type, axPoint: point)
        }
        return Unmanaged.passUnretained(event)
    }

    /// The synchronous twin of handleMouseMoved's cheapest path: no session on
    /// screen, no hover pending and the cursor outside the Dock's edge strip
    /// means the move only needs its position recorded (the deferred hide and
    /// switch re-confirmations read these) — everything else falls through to
    /// the full handler.
    private func discardFarMouseMove(axPoint: CGPoint) -> Bool {
        guard isRunning, !isVisible, pendingHover == nil else { return false }
        let point = appKitPoint(fromAX: axPoint)
        guard !isNearDock(point) else { return false }
        lastAXMousePoint = axPoint
        lastAppKitMousePoint = point
        return true
    }

    /// Lets one move per display frame reach the AX path and retains the
    /// newest dropped point, so a cursor that comes to rest still opens the
    /// intended preview.
    private func admitMouseMove(axPoint: CGPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMoveSampledAt < DockPreviewSupport.mouseMoveSampleInterval else {
            lastMoveSampledAt = now
            cancelPendingMove()
            return true
        }
        pendingMovePoint = axPoint
        guard pendingMove == nil else { return false }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMove = nil
            self.lastMoveSampledAt = ProcessInfo.processInfo.systemUptime
            guard let point = self.pendingMovePoint else { return }
            self.pendingMovePoint = nil
            self.handleOnMain(type: .mouseMoved, axPoint: point)
        }
        pendingMove = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.mouseMoveSampleInterval,
                                      execute: work)
        return false
    }

    private func cancelPendingMove() {
        pendingMove?.cancel()
        pendingMove = nil
        pendingMovePoint = nil
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
        // A drag owns the pointer until it lifts. Without this the pointer
        // leaving the panel would arm the hide, and passing over another Dock
        // icon would swap the panel out from under the window being carried.
        guard !isDraggingWindow else { return }
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
                startDockVisibilityTimerIfNeeded()
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
        let band = DockPreviewSupport.dockProximityBand(tileSize: preferences.hoverTileSize)
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
            reattachGraceFrame = nil
            return .panel
        }
        // The panel moved out from under a pointer that never left it; where it
        // used to be still counts until the pointer reaches where it is now.
        if reattachGraceFrame?.insetBy(dx: -DockPreviewSupport.panelStayMargin,
                                       dy: -DockPreviewSupport.panelStayMargin).contains(point) == true,
           let origin = reattachGraceOrigin,
           hypot(point.x - origin.x, point.y - origin.y) <= DockPreviewSupport.reattachGraceTravel {
            return .panel
        }
        // Moving away is an answer: the region the panel vacated stops standing
        // in for it, so leaving does not have to clear a rectangle that no
        // longer has a panel in it.
        reattachGraceFrame = nil
        reattachGraceOrigin = nil
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
                                                                   isInsidePanel: isInsidePanel)
        if !initialDecision.shouldEndSession {
            cancelPendingHide()
            cancelPendingHover()
            return
        }
        endSession()
    }

    private func scheduleHideIfStillOutside() {
        guard !isPinned, !isDraggingWindow else { return }
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            guard let point = self.lastAppKitMousePoint,
                  let axPoint = self.lastAXMousePoint else {
                self.endSession()
                return
            }
            switch self.currentZone(point: point, axPoint: axPoint) {
            case .panel, .openingPath:
                return
            case .ownIcon:
                // Closes only once the panel was actually used; an unentered
                // panel keeps resting on its opener icon.
                if self.hasEnteredPanel { self.endSession() }
            case .otherIcon(let hit):
                self.scheduleHover(hit, delay: DockPreviewSupport.switchDelay)
            case .outside:
                self.endSession()
            }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.hideDelay, execute: work)
    }

    // MARK: - Sessions

    private var openDelay: TimeInterval {
        DockPreviewSupport.openDelay(
            milliseconds: UserDefaults.standard.integer(forKey: DefaultsKey.dockPreviewOpenDelay))
    }

    private func scheduleHover(_ hit: DockHit, delay: TimeInterval? = nil) {
        // Same app already arming: let the existing timer run to completion rather
        // than restarting it on every move, so a resting cursor isn't starved by
        // a one-frame Dock hit-test miss.
        if let pendingHover,
           pendingHover.app.processIdentifier == hit.app.processIdentifier,
           pendingHover.iconFrame.insetBy(dx: -6, dy: -6).intersects(hit.iconFrame) {
            return
        }

        cancelPendingHover()
        let delay = delay ?? openDelay
        let token = UUID()
        let work = DispatchWorkItem { [weak self] in
            self?.beginHoverIfStillValid(token: token, initialHit: hit)
        }
        pendingHover = PendingHover(token: token, app: hit.app, iconFrame: hit.iconFrame, workItem: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        schedulePrefetch(token: token, pid: hit.app.processIdentifier, delay: delay)
    }

    /// Reads the app's window list part-way through the arming delay, so the
    /// panel the timer opens has one ready instead of reading it on the way up.
    ///
    /// Skipped while a panel is up: a switch runs on a delay as short as the
    /// reading's own head start, so the reading would land the moment the
    /// cursor does, and a reading under way cannot be called back.
    private func schedulePrefetch(token: UUID, pid: pid_t, delay: TimeInterval) {
        guard !isVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingHover?.token == token else { return }
            let list = Self.previewableWindows(for: pid)
            // The list took Accessibility round trips to read: the hover it was
            // taken for can have been cancelled or handed on in the meantime.
            guard self.pendingHover?.token == token else { return }
            self.pendingHover?.windows = list
        }
        pendingHover?.prefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.prefetchDelay(openDelay: delay),
                                      execute: work)
    }

    private static func previewableWindows(for pid: pid_t) -> [SwitcherItem] {
        WindowEnumerator.listWindows(for: pid, maximumCount: 12)
            .filter { $0.windowID != nil }
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
        // A prefetched list counts only for the app it was taken for: a hover
        // handed over to a neighbouring icon must not open on the previous
        // app's windows.
        let prefetched = pendingHover.flatMap {
            $0.app.processIdentifier == hit.app.processIdentifier ? $0.windows : nil
        }
        cancelPendingHover()
        cancelPendingHide()

        let list = prefetched ?? Self.previewableWindows(for: hit.app.processIdentifier)
        // An app with no real windows shows nothing; if a panel is already up
        // (the user moved here from another app), close it cleanly.
        guard !list.isEmpty else {
            if isVisible { endSession() }
            return
        }

        // Switching apps keeps the panel on screen and re-points it at the app
        // under the cursor without changing the frontmost application.
        if isVisible {
            tearDownVisuals()
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

        WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 420 * PreviewSizing.scale) { [weak self] windowID, image in
            guard let self, self.isVisible, self.windows.contains(where: { $0.previewWindowID == windowID }) else { return }
            self.previews[windowID] = image
        }

        showPanel(for: hit, itemCount: list.count)
    }

    /// Fully ends the session and tears down the panel.
    private func endSession() {
        isDraggingWindow = false
        DockPreviewDragGhost.shared.end()
        cancelPendingHover()
        cancelPendingHide()
        WindowPreviewProvider.shared.cancel()
        dockVisibilityTimer?.invalidate()
        dockVisibilityTimer = nil
        tearDownVisuals()
        isPinned = false
        panel?.orderOut(nil)
    }

    /// Clears all per-app panel state while leaving the panel window available
    /// so the same session can be re-pointed during a Dock switch.
    private func tearDownVisuals() {
        cancelPendingMinimizeConfirmations()

        windows = []
        previews = [:]
        selectedWindowID = nil
        currentAppName = nil
        currentSessionPID = nil
        isPinned = false
        activePanelFrame = nil
        didReattachForSession = false
        reattachGraceFrame = nil
        reattachGraceOrigin = nil
        dockVisibilityTimer?.invalidate()
        dockVisibilityTimer = nil
        activeCorridor = nil
        activeIconFrame = nil
        activeDockPreferences = nil
    }

    private func cancelPendingHover() {
        pendingHover?.workItem.cancel()
        pendingHover?.prefetchWorkItem?.cancel()
        pendingHover = nil
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func cancelPendingMinimizeConfirmations() {
        pendingMinimizeConfirmations.removeAll()
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
        guard isVisible,
              pendingMinimizeConfirmations[windowID] == token,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let isMinimized = WindowActivator.windowIsMinimized(windowID: windowID, pid: pid)
        if isMinimized == minimized {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID,
                                minimized: minimized)
            return
        }

        guard attempt + 1 < DockPreviewMinimizeConfirmation.delays.count else {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID,
                                minimized: isMinimized)
            return
        }

        _ = WindowActivator.setWindowMinimized(minimized, windowID: windowID, pid: pid)
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: pid,
                                     minimized: minimized,
                                     attempt: attempt + 1)
    }

    private func applyMinimizedState(windowID: CGWindowID,
                                     minimized: Bool) {
        windows = windows.map { candidate in
            candidate.windowID == windowID ? candidate.withMinimized(minimized) : candidate
        }

        if minimized {
            if selectedWindowID == windowID {
                selectedWindowID = nil
            }
        } else {
            selectedWindowID = windowID
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
        let state = DockPreviewSupport.closeState(
            afterRemoving: closedWindowID,
            windowIDs: windows.compactMap(\.windowID),
            selectedWindowID: selectedWindowID
        )
        let remaining = Set(state.remainingWindowIDs)

        windows = windows.filter { item in
            guard let windowID = item.windowID else { return false }
            return remaining.contains(windowID)
        }
        previews = previews.filter { remaining.contains($0.key) }
        selectedWindowID = state.selectedWindowID

        if state.shouldEndSession {
            endSession()
        } else {
            resizePanelForCurrentWindows()
        }
    }

    // MARK: - Panel

    private func showPanel(for hit: DockHit, itemCount: Int) {
        let panel = ensurePanel()
        let screenVisibleFrame = visibleFrameForScreen(containing: hit.iconFrame)
        let size = DockPreviewSupport.panelSize(itemCount: itemCount,
                                                screenVisibleFrame: screenVisibleFrame,
                                                isPinned: false,
                                                orientation: hit.preferences.orientation)
        let gap = hit.preferences.autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
        let frame = DockPreviewSupport.panelFrame(anchor: hit.iconFrame,
                                                  panelSize: size,
                                                  screenVisibleFrame: screenVisibleFrame,
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
        orientation = hit.preferences.orientation

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

        let screenVisibleFrame = visibleFrameForScreen(containing: iconFrame)
        let size = DockPreviewSupport.panelSize(itemCount: windows.count,
                                                screenVisibleFrame: screenVisibleFrame,
                                                isPinned: false,
                                                orientation: preferences.orientation)
        let gap = preferences.autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
        let dockAnchoredFrame = DockPreviewSupport.panelFrame(anchor: iconFrame,
                                                              panelSize: size,
                                                              screenVisibleFrame: screenVisibleFrame,
                                                              orientation: preferences.orientation,
                                                              gap: gap)
        let frame = DockPreviewSupport.resizedPanelFrame(
            dockAnchoredFrame,
            didReattachForSession: didReattachForSession,
            screenVisibleFrame: screenVisibleFrame,
            orientation: preferences.orientation
        )
        activePanelFrame = frame
        activeCorridor = DockPreviewSupport.hoverCorridor(
            iconFrame: iconFrame,
            panelFrame: frame,
            orientation: preferences.orientation
        )
        panel.setFrame(frame, display: true, animate: true)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    /// The Dock owns its auto-hide reveal region; another process cannot extend
    /// it to cover this panel. Once the cursor reaches the panel, watch the
    /// Dock's real on-screen window and pull the preview to the vacated edge if
    /// the Dock slides away, so the interaction remains attached and usable.
    private func startDockVisibilityTimerIfNeeded() {
        guard DockPreviewSupport.shouldStartDockVisibilityTimer(
            hasActiveTimer: dockVisibilityTimer != nil,
            didReattachForSession: didReattachForSession,
            autohide: activeDockPreferences?.autohide == true
        )
        else { return }

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self,
                  self.isVisible,
                  self.hasEnteredPanel,
                  let dockPID = self.dockProcessID()
            else {
                timer.invalidate()
                self?.dockVisibilityTimer = nil
                return
            }
            guard !Self.dockIsRevealed(dockPID: dockPID) else { return }
            self.reattachPanelToScreenEdge()
            timer.invalidate()
            self.dockVisibilityTimer = nil
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        dockVisibilityTimer = timer
    }

    private func reattachPanelToScreenEdge() {
        guard let panel,
              let frame = activePanelFrame,
              let preferences = activeDockPreferences
        else { return }
        didReattachForSession = true
        let edgeFrame = clampedPanelFrame(DockPreviewSupport.panelFrameWhenDockHidden(
            frame,
            screenVisibleFrame: visibleFrameForScreen(containing: frame),
            orientation: preferences.orientation
        ))
        // The pointer is resting on the panel and has not moved, but the panel
        // is about to slide out from under it by the Dock's thickness — far
        // more than panelStayMargin. The frame it was resting on keeps counting
        // as the panel until the pointer reaches the new one, so the preview
        // this repositioning exists to keep usable does not dismiss itself.
        reattachGraceFrame = frame
        reattachGraceOrigin = lastAppKitMousePoint
        activePanelFrame = edgeFrame
        // Not animated: this service's event tap is served by the main run
        // loop, and setFrame(display:animate:) blocks it for the animation's
        // duration, queueing every mouse event behind a one-shot jump.
        panel.setFrame(edgeFrame, display: true)
    }

    /// Whether the Dock's layer-20 strip is currently on screen. With
    /// auto-hide, WindowServer removes this window from the on-screen list once
    /// its slide-out completes.
    private static func dockIsRevealed(dockPID: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return true }
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        return list.contains { window in
            (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dockPID
                && (window[kCGWindowLayer as String] as? Int) == dockLevel
        }
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = visibleFrameForScreen(containing: frame)
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

    private func visibleFrameForScreen(containing rect: CGRect) -> CGRect {
        let point = rect.center
        return (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.withMouse)?.visibleFrame
            ?? NSScreen.pointerVisibleFrame
    }

    // MARK: - Dock hit testing

    private func dockHit(at axPoint: CGPoint) -> DockHit? {
        guard let preferences = cachedPreferences ?? readDockPreferences(),
              let dockPID = dockProcessID()
        else { return nil }
        guard DockClickSupport.dockOwnsPoint(
            axPoint,
            windows: Self.onScreenWindows(),
            dockProcessID: dockPID,
            dockLayer: Int(CGWindowLevelForKey(.dockWindow)),
            ownProcessID: getpid()
        ) else { return nil }

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

    private static func onScreenWindows() -> [MouseAppExceptionSupport.Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return MouseAppExceptionSupport.windows(from: list)
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
        // This only tracks the user editing the Dock itself (position, size,
        // autohide, magnification) — rare events with no notification API.
        // Each poll copies the whole com.apple.dock domain, so it runs on a
        // slow beat and the full (tap/session/pid) resync below only happens
        // when something actually changed.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            let fresh = self.readDockPreferences()
            // Resync on a real change — or while blocked, so a Dock that was
            // restarting (or briefly unavailable) still brings the tap back.
            if fresh != self.cachedPreferences || !self.isRunning {
                self.syncWithPreferences()
            }
        }
        timer.tolerance = 2.5
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
            magnification: boolValue(domain["magnification"]),
            magnifiedTileSize: doubleValue(domain["largesize"])
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
    /// The reading armed by `schedulePrefetch`. Nil until it lands, and dropped
    /// with the hover it belongs to.
    var prefetchWorkItem: DispatchWorkItem?
    var windows: [SwitcherItem]?
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
              let windowID = item.windowID
        else { return }

        DockPreviewSupport.performCloseAction(
            quitAppOnClose: UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewQuitAppOnClose),
            requestQuit: { requestDockPreviewApplicationQuit(item) },
            closeWindow: {
                WindowActivator.closeWindowIncludingHiddenState(item) { [weak self] didClose in
                    guard didClose else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        self?.finishClosing(item, windowID: windowID, attempt: 0)
                    }
                }
            }
        )
    }

    func toggleMinimized(_ item: SwitcherItem) {
        guard windows.contains(item),
              let windowID = item.windowID,
              !item.isFullscreen
        else { return }

        let shouldMinimize = !item.isMinimized
        guard WindowActivator.setWindowMinimized(shouldMinimize,
                                                 windowID: windowID,
                                                 pid: item.windowOwnerPID) else { return }
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: item.windowOwnerPID,
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
                                                screenVisibleFrame: visibleFrameForScreen(containing: panel.frame),
                                                isPinned: true)
        var frame = panel.frame
        frame.size = size
        panel.setFrame(clampedPanelFrame(frame), display: true, animate: true)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = visibleFrameForScreen(containing: frame)
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

    private func visibleFrameForScreen(containing rect: CGRect) -> CGRect {
        let point = rect.center
        return (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.withMouse)?.visibleFrame
            ?? NSScreen.pointerVisibleFrame
    }
}
