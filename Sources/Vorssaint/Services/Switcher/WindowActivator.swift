// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

private let switcherAXPressedNotification = "AXPressed"

/// Brings a switcher selection to the front: unminimizes if needed, makes the
/// exact window the app's focused/main Accessibility window and activates the
/// owning app. The initial exact-window path fronts the window synchronously,
/// then performs remote Accessibility focus off the keyboard callback.
enum WindowActivator {
    private static let focusRetryDelay: TimeInterval = 0.12
    private static let fullscreenFocusRetryDelays: [TimeInterval] = [0.18, 0.38, 0.68]
    fileprivate static let activationAXQueue = DispatchQueue(label: "com.vorssaint.switcher-activation-ax",
                                                               qos: .userInitiated)
    /// Reads of another process run here. A read can wait for the whole
    /// Accessibility timeout of an app that does not answer, and it never
    /// changes what the user sees. Keeping it off the write lane is what stops
    /// a stalled read of the previous switch from standing in front of the
    /// next switch's first focus.
    ///
    /// The lane is serial on purpose. The observations of one activation have
    /// an order — the initial minimized observation answers before the passes
    /// that compare against it — and a serial lane keeps that order without
    /// a second mechanism. The price is that a stalled read holds up the next
    /// activation's observations, never its first focus.
    fileprivate static let activationObservationQueue = DispatchQueue(
        label: "com.vorssaint.switcher-activation-observation",
        qos: .userInitiated)
    private static let activationMainQueue = DispatchQueue.main
    private static var pendingMinimizeRestore: SwitcherWindowMinimizeRestore?
    private static var pendingWindowClose: SwitcherPendingWindowClose?
    private static let activationLock = NSLock()
    private static var activationGeneration: UInt64 = 0
    private static var activationGenerationsByPID: [pid_t: UInt64] = [:]

    /// Runs one observation on the observation lane. The caller keeps the
    /// decision that follows on the main thread and the writes that follow
    /// the decision on the write lane.
    fileprivate static func runObservation(_ work: @escaping () -> Void) {
        activationObservationQueue.async(execute: work)
    }

    static func activate(_ item: SwitcherItem,
                         retry: Bool = true,
                         sourceWasFullscreen: Bool = false,
                         sourcePID: pid_t? = nil,
                         handoffSourcePID: pid_t? = nil,
                         sourceWindowID: CGWindowID? = nil,
                         sourceWindowOwnerPID: pid_t? = nil,
                         windowServerSnapshot: SwitcherWindowServerSnapshot? = nil) {
        let generation = supersedePendingActivations(for: item.pid)
        // The source window is staged behind the target once per activation.
        // The state belongs to this generation: a later activation starts with
        // an unstaged source.
        let stagingState = SwitcherSourceStagingState(generation: generation)

        if item.pid == ProcessInfo.processInfo.processIdentifier {
            activateOwnWindow(item)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: item.pid) else {
            return
        }
        // Only the delayed focus guards may treat a caller's handoff app as
        // the source. The minimize restore, source staging and Space hops stay
        // limited to the App Switcher session source.
        let retrySourcePID = SwitcherSupport.focusRetrySourcePID(
            sessionSourcePID: sourcePID,
            handoffSourcePID: handoffSourcePID,
            targetPID: item.pid
        )
        let windowOwnerPID = item.windowOwnerPID

        // Unhiding an app that is not hidden still brings every one of its
        // windows forward (measured on macOS 27.2), so a window selection
        // raised its siblings before fronting the window (issue #1503).
        let appIsHidden = app.isHidden
        if appIsHidden { app.unhide() }
        let activationPlan = SwitcherSupport.activationPlan(
            targetsSpecificWindow: item.windowID != nil
        )
        guard let windowID = item.windowID else {
            let retryState = retry && sourceWasFullscreen
                ? SwitcherAppActivationRetryState(targetPID: item.pid)
                : nil
            activateApp(app, plan: activationPlan)
            if let bundleURL = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            }
            if let retryState {
                scheduleAppActivationRetries(targetPID: item.pid,
                                             sourcePID: retrySourcePID,
                                             plan: activationPlan,
                                             state: retryState,
                                             generation: generation,
                                             delays: Self.fullscreenFocusRetryDelays)
            }
            return
        }
        // The list's own answer is a hint, not evidence. The state is read
        // fresh on every switch, including when the list already said the
        // window is minimized: the list was taken when the switch began, and
        // the user can have restored the window since. Only an answer that
        // came back "restored" can count as restored; a state neither source
        // can answer falls back to the list instead of becoming an answer.
        let itemReportedMinimized = item.isMinimized
        // One Accessibility element for the target window, shared by the
        // steps of this activation: the minimized-state read, the
        // minimize/restore observer and the window preparation all need the
        // very same window, and an app answers its window list once per
        // copy. The element is resolved for the exact window id and lives
        // inside this activation only.
        let targetWindow = SwitcherActivationTargetWindow(windowID: windowID) {
            targetWindowElement(windowID: windowID,
                                pid: windowOwnerPID)
        }
        let liveMinimizedRead = activationMinimizedState(target: targetWindow,
                                                         pid: windowOwnerPID)
        let liveMinimizedState = liveMinimizedRead.state
        let targetStartedMinimized = liveMinimizedState ?? itemReportedMinimized
        // A window parked on a Space that is not visible cannot be reached by
        // the Accessibility passes below; the hop travels there first and then
        // runs the same focus pass on arrival (issue #339). A minimized window
        // keeps its Accessibility element and can be deminiaturized directly
        // on the regular path without relying on Space shortcuts being enabled.
        let spaceHopStarted = !targetStartedMinimized
            && SpaceHop.beginIfNeeded(windowID: windowID,
                                      appPID: item.pid,
                                      windowOwnerPID: windowOwnerPID,
                                      sourcePID: sourcePID,
                                      app: app)
        if spaceHopStarted {
            return
        }
        // Keep the baseline before prepare/front. A current all-ID query can
        // validate the earlier complete owner map without copying every
        // window's properties again. Any new ID or missing target falls back.
        let initialSnapshotTaken = retry || sourceWasFullscreen || item.isFullscreen
        var knownWindowIDs: Set<CGWindowID> = []
        var usedValidatedSnapshot = false
        if initialSnapshotTaken, !targetStartedMinimized,
           !sourceWasFullscreen, !item.isFullscreen,
           let windowServerSnapshot {
            let currentIDs = SpaceWindowBridge.allWindowIDs()
            if let currentIDs,
               let validated = windowServerSnapshot.activationWindowIDs(
                   ownerPID: windowOwnerPID, targetWindowID: windowID,
                   currentWindowIDs: currentIDs) {
                knownWindowIDs = validated
                usedValidatedSnapshot = true
            }
        }
        if initialSnapshotTaken, !usedValidatedSnapshot {
            knownWindowIDs = windowIDs(ownerPID: windowOwnerPID, options: .optionAll)
        }
        watchTargetMinimizeIfNeeded(windowID: windowID,
                                    targetPID: item.pid,
                                    targetWindowOwnerPID: windowOwnerPID,
                                    sourcePID: sourcePID,
                                    sourceWindowID: sourceWindowID,
                                    sourceWindowOwnerPID: sourceWindowOwnerPID,
                                    activationPlan: activationPlan,
                                    generation: generation,
                                    targetWindow: targetWindow)
        // Preparing a minimized window here would deminiaturize it while its
        // app is still in the background. The window server shows the
        // restoring window above the old app, then drops it beneath that app
        // again until activation, which reads as a flash. Leave the window
        // alone: the exact-window front below activates its app, and the
        // focus pass restores and focuses the window once the app is front.
        if !targetStartedMinimized {
            prepareWindowForActivation(windowID: windowID, pid: windowOwnerPID,
                                       target: targetWindow)
        }
        if sourceWasFullscreen || item.isFullscreen {
            let retryState = SwitcherWindowFocusRetryState(
                targetWindowID: windowID,
                targetStartedMinimized: targetStartedMinimized,
                targetWasObservedRestored: liveMinimizedState == false,
                knownWindowIDs: knownWindowIDs
            )
            scheduleInitialMinimizedStateObservation(
                retryState,
                windowID: windowID,
                pid: windowOwnerPID,
                generation: generation)
            activateApp(app,
                        plan: activationPlan,
                        windowID: windowID,
                        windowOwnerPID: windowOwnerPID,
                        generation: generation)
            let retryDelays = retry
                ? Self.fullscreenFocusRetryDelays
                : [Self.fullscreenFocusRetryDelays[0]]
            scheduleFocusRetries(windowID: windowID,
                                 targetPID: item.pid,
                                 targetWindowOwnerPID: windowOwnerPID,
                                 sourcePID: sourcePID,
                                 retrySourcePID: retrySourcePID,
                                 sourceWindowID: sourceWindowID,
                                 sourceWindowOwnerPID: sourceWindowOwnerPID,
                                 state: retryState,
                                 stagingState: stagingState,
                                 activationPlan: activationPlan,
                                 generation: generation,
                                 delays: retryDelays,
                                 stopsWhenTargetFocused: false)
            return
        }

        activateApp(app,
                    plan: activationPlan,
                    windowID: windowID,
                    windowOwnerPID: windowOwnerPID,
                    generation: generation)
        // The first staging of an activation has nothing to skip yet, and no
        // foreground observation: the source app is the one in front.
        scheduleSourceStaging(targetWindowID: windowID,
                              targetPID: item.pid,
                              targetWindowOwnerPID: windowOwnerPID,
                              sourcePID: sourcePID,
                              sourceWindowID: sourceWindowID,
                              sourceWindowOwnerPID: sourceWindowOwnerPID,
                              activationPlan: activationPlan,
                              generation: generation,
                              stagingState: stagingState,
                              observedFrontmostPID: nil)

        guard retry else { return }
        let retryState = SwitcherWindowFocusRetryState(
            targetWindowID: windowID,
            targetStartedMinimized: targetStartedMinimized,
            targetWasObservedRestored: liveMinimizedState == false,
            knownWindowIDs: knownWindowIDs
        )
        scheduleInitialMinimizedStateObservation(
            retryState,
            windowID: windowID,
            pid: windowOwnerPID,
            generation: generation)
        scheduleFocusRetries(windowID: windowID,
                              targetPID: item.pid,
                              targetWindowOwnerPID: windowOwnerPID,
                              sourcePID: sourcePID,
                              retrySourcePID: retrySourcePID,
                              sourceWindowID: sourceWindowID,
                              sourceWindowOwnerPID: sourceWindowOwnerPID,
                              state: retryState,
                              stagingState: stagingState,
                              activationPlan: activationPlan,
                              generation: generation,
                              delays: [focusRetryDelay],
                              stopsWhenTargetFocused: true)
    }

    static func activate(pid: pid_t,
                         windowID: CGWindowID?,
                         appName: String,
                         retry: Bool = true,
                         handoffSourcePID: pid_t? = nil) {
        let item: SwitcherItem
        if let windowID {
            item = .window(id: windowID, title: appName, appName: appName,
                           pid: pid, isOnScreen: true, frame: .zero)
        } else {
            item = .appOnly(appName: appName, pid: pid)
        }
        activate(item, retry: retry, handoffSourcePID: handoffSourcePID)
    }

    /// Why a focused-window read ended the way it did. The Accessibility
    /// error is the one the read already produced, so naming it costs no
    /// extra query.
    private enum FocusedWindowOutcome {
        /// No query was made: the process is not trusted for Accessibility.
        case notReadUntrusted
        /// The query was made and the app answered with an error.
        case readFailed
        /// The query succeeded and the app reported no focused window.
        case noFocusedWindow
        /// The app reported a focused element that names no window.
        case noWindowID
        /// The query succeeded and named a window.
        case focusedWindow
    }

    private struct FocusedWindowReading {
        let windowID: CGWindowID?
        let axError: AXError?
        let outcome: FocusedWindowOutcome
    }

    static func focusedWindowID(for pid: pid_t) -> CGWindowID? {
        focusedWindowReading(for: pid).windowID
    }

    /// The single focused-window read every caller shares. It keeps the
    /// Accessibility error and the reason a read came back empty, so a log
    /// can report what was observed without asking the app a second time.
    private static func focusedWindowReading(for pid: pid_t) -> FocusedWindowReading {
        guard AXIsProcessTrusted() else {
            return FocusedWindowReading(windowID: nil, axError: nil, outcome: .notReadUntrusted)
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success else {
            return FocusedWindowReading(windowID: nil, axError: result, outcome: .readFailed)
        }
        guard let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return FocusedWindowReading(windowID: nil, axError: result, outcome: .noFocusedWindow)
        }
        let window = value as! AXUIElement
        guard let windowID = AXWindowResolver.windowID(for: window) else {
            return FocusedWindowReading(windowID: nil, axError: result, outcome: .noWindowID)
        }
        return FocusedWindowReading(windowID: windowID, axError: result, outcome: .focusedWindow)
    }

    static func windowIsMinimized(windowID: CGWindowID,
                                  pid: pid_t) -> Bool {
        windowMinimizedState(windowID: windowID, pid: pid) == true
    }

    /// Undo only a verified work-area constraint from the preview's Dock hold.
    static func restoreFrameAfterDockHold(_ item: SwitcherItem, original: CGRect,
                                         heldVisibleFrame: CGRect) {
        guard Permissions.shared.accessibility, let windowID = item.windowID else { return }
        let app = AXUIElementCreateApplication(item.windowOwnerPID)
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let window = axElement(windowID: windowID, in: app),
              !boolAttribute(window, "AXFullScreen", default: true),
              minimizedState(of: window) == false else { return }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              DockPreviewFrameSupport.wasConstrained(CGRect(origin: origin, size: size),
                                                     original: original, visibleFrame: heldVisibleFrame)
        else { return }
        origin = original.origin
        size = original.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return }
        let suspension = EnhancedUserInterfaceSuspension.suspend(forAppOf: window)
        defer { suspension?.resume() }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    /// The Accessibility element of one window of an app, resolved for the
    /// exact window id.
    ///
    /// The list read keeps the 350 ms the rest of the activation path uses.
    /// A shorter bound made a slow app give up on the shared resolution and
    /// then pay the same wait again when preparation asked for the list a
    /// second time, so the element is resolved once at this timeout instead.
    private static func targetWindowElement(windowID: CGWindowID,
                                            pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        return axElement(windowID: windowID,
                         in: axApp)
    }

    /// The fresh minimized state of an activation target, and where it came
    /// from.
    ///
    /// The window server answers this without the other app's help, so an
    /// ordinary target never waits on the Accessibility of an app that is busy
    /// answering something else. That read used to hold the main thread for
    /// as long as the app took, which was the longest wait between the
    /// release of the shortcut and the first focus. When the window server has
    /// no answer the app's own Accessibility still reads the state, with its
    /// permission and unresolved semantics unchanged: an answer that cannot
    /// be resolved stays unknown. The state is always read fresh, never taken
    /// from the switcher's own older item.
    static func activationMinimizedState(target: SwitcherActivationTargetWindow,
                                         pid: pid_t)
        -> (state: Bool?, source: SwitcherMinimizedStateSource) {
        if let state = SpaceWindowBridge.minimizedState(of: target.windowID) {
            return (state, .windowServer)
        }
        let reading = windowMinimizedState(target: target, pid: pid)
        return (reading.state, .accessibility)
    }

    /// Three-state minimized check for callers that must distinguish a window
    /// reported as restored from one that could not be resolved or queried.
    static func windowMinimizedState(windowID: CGWindowID,
                                     pid: pid_t) -> Bool? {
        let target = SwitcherActivationTargetWindow(windowID: windowID) {
            targetWindowElement(windowID: windowID,
                                pid: pid)
        }
        return windowMinimizedState(target: target, pid: pid).state
    }

    /// The same check for a target whose element is shared with the other
    /// steps of the same activation. The window lookup and the attribute
    /// read are timed apart, so a slow answer is told apart from a slow list
    /// and a slow id lookup.
    static func windowMinimizedState(target: SwitcherActivationTargetWindow,
                                     pid: pid_t)
        -> (state: Bool?, element: AXUIElement?) {
        guard Permissions.shared.accessibility else { return (nil, nil) }
        guard let axWindow = target.element() else {
            return (nil, nil)
        }
        let state = minimizedState(of: axWindow)
        return (state, axWindow)
    }

    /// Moves a window's top-left corner to a global Accessibility point.
    ///
    /// Our own windows are refused rather than special-cased: reading this
    /// process's own Accessibility tree from the main thread is the one call
    /// that can deadlock, and Vorssaint has no Dock icon to drag a preview
    /// from in the first place.
    @discardableResult
    static func setWindowOrigin(_ origin: CGPoint, windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.shared.accessibility,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return false }
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value) == .success
    }

    /// Puts a window where a drag dropped it. Every window takes the same four
    /// steps in the same order whatever state it was in, because a drop that
    /// stops to check on a minimized window feels like a different gesture from
    /// a drop that does not. Un-minimizing a window that is already out returns
    /// immediately, so the step costs one attribute read.
    ///
    /// The position goes on before the window is restored: the restore then
    /// ends at the drop point rather than flying to the window's old place.
    @discardableResult
    static func place(_ item: SwitcherItem, origin: CGPoint, pointer: CGPoint) -> Bool {
        guard Permissions.shared.accessibility,
              let windowID = item.windowID,
              item.windowOwnerPID != ProcessInfo.processInfo.processIdentifier
        else { return false }
        let pid = item.windowOwnerPID

        if item.isAppHidden {
            NSRunningApplication(processIdentifier: item.pid)?.unhide()
        }
        let placed = setWindowOrigin(origin, windowID: windowID, pid: pid)
        SpaceWindowBridge.moveToVisibleSpace(windowID, near: pointer)
        setWindowMinimized(false, windowID: windowID, pid: pid)
        return placed
    }

    /// Hands the keyboard to a window a drag just placed. Dropping a window
    /// somewhere is a request to use it, and the app-level activation that
    /// follows raises the app without saying which of its windows the user was
    /// pointing at.
    static func focusPlacedWindow(_ item: SwitcherItem) {
        guard let windowID = item.windowID,
              item.windowOwnerPID != ProcessInfo.processInfo.processIdentifier
        else { return }
        SpaceWindowBridge.frontWindow(windowID, ownerPID: item.windowOwnerPID)
    }

    @discardableResult
    static func setWindowMinimized(_ minimized: Bool, windowID: CGWindowID, pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return false }
            if minimized {
                window.miniaturize(nil)
            } else {
                window.deminiaturize(nil)
            }
            return true
        }

        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return false }
        if minimizedState(of: axWindow) == minimized { return true }

        let setResult = AXUIElementSetAttributeValue(axWindow,
                                                     kAXMinimizedAttribute as CFString,
                                                     minimized ? kCFBooleanTrue : kCFBooleanFalse)
        if setResult == .success, minimizedState(of: axWindow) == minimized {
            return true
        }

        guard minimized else {
            return setResult == .success
        }
        guard let minimizeButton = elementAttribute(axWindow, kAXMinimizeButtonAttribute as String),
              boolAttribute(minimizeButton, kAXEnabledAttribute as String, default: true)
        else {
            return setResult == .success
        }
        return AXUIElementPerformAction(minimizeButton, kAXPressAction as CFString) == .success
            || setResult == .success
    }

    static func closeWindow(windowID: CGWindowID,
                            appPID: pid_t,
                            windowOwnerPID: pid_t) -> Bool {
        if appPID == ProcessInfo.processInfo.processIdentifier {
            guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return false }
            window.close()
            return true
        }

        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(windowOwnerPID)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp),
              let closeButton = elementAttribute(axWindow, kAXCloseButtonAttribute as String),
              boolAttribute(closeButton, kAXEnabledAttribute as String, default: true)
        else { return false }

        AutoQuitService.shared.recordProgrammaticCloseRequest(pid: appPID)
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    /// Keeps the regular close path immediate. A hidden app is temporarily
    /// revealed, and a hidden-Space target reuses the verified Space hop; both
    /// paths poll until Accessibility can resolve that exact window.
    static func closeWindowIncludingHiddenState(_ item: SwitcherItem,
                                                completion: @escaping (Bool) -> Void) {
        pendingWindowClose?.cancel()
        guard let windowID = item.windowID else {
            completion(false)
            return
        }
        if closeWindow(windowID: windowID,
                       appPID: item.pid,
                       windowOwnerPID: item.windowOwnerPID) {
            completion(true)
            return
        }
        let app = NSRunningApplication(processIdentifier: item.pid)
        let appNeedsReveal = item.isAppHidden || app?.isHidden == true
        let windowNeedsSpaceHop = SpaceWindowBridge.isParkedOnHiddenSpace(windowID)
        guard appNeedsReveal || windowNeedsSpaceHop else {
            completion(false)
            return
        }
        let pending = SwitcherPendingWindowClose(item: item,
                                                 restoresHiddenApp: appNeedsReveal,
                                                 usesSpaceHop: windowNeedsSpaceHop,
                                                 completion: completion)
        pendingWindowClose = pending
        pending.start()
    }

    fileprivate static func finishPendingWindowClose(_ pending: SwitcherPendingWindowClose,
                                                     success: Bool) {
        guard pendingWindowClose === pending else { return }
        pendingWindowClose = nil
        if pending.usesSpaceHop {
            SpaceHop.cancelPending()
        }
        pending.finish(success: success)
    }

    private static func activateOwnWindow(_ item: SwitcherItem) {
        guard let windowID = item.windowID,
              let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Prefer the selected window, but retain cooperative activation when the
    /// private request or the Accessibility raise cannot be delivered. For
    /// generation-guarded commits, remote focus runs off the key callback.
    private static func activateApp(_ app: NSRunningApplication,
                                    plan: SwitcherActivationPlan,
                                    windowID: CGWindowID? = nil,
                                    windowOwnerPID: pid_t? = nil,
                                    generation: UInt64? = nil) {
        func isCurrent() -> Bool {
            generation.map { isCurrentActivation($0) } ?? true
        }
        func scheduleFocusWindow(windowID: CGWindowID,
                                 ownerPID: pid_t,
                                 fallsBackToCooperativeActivation: Bool) {
            activationAXQueue.async {
                guard isCurrent() else { return }
                let focused = focusWindow(windowID: windowID,
                                          pid: ownerPID,
                                          makeAppFrontmost: false,
                                          generation: generation)
                guard !focused, fallsBackToCooperativeActivation, isCurrent() else { return }
                activationMainQueue.async {
                    guard isCurrent(),
                          isActivationTargetFrontmost(app, windowOwnerPID: ownerPID) else { return }
                    activateAppCooperatively(app,
                                              allWindows: false)
                }
            }
        }

        if case .exactWindow(let exactWindowID) = SwitcherSupport.appActivationRoute(plan: plan,
                                                                                     windowID: windowID) {
            guard isCurrent() else { return }
            let ownerPID = windowOwnerPID ?? app.processIdentifier
            if ownerPID != app.processIdentifier {
                activateAppCooperatively(app,
                                         allWindows: false)
                guard isCurrent() else { return }
            }
            let fronted = SpaceWindowBridge.frontWindow(exactWindowID, ownerPID: ownerPID)
            // Calls without a cancellation generation retain their legacy synchronous behavior.
            if generation == nil {
                if fronted,
                   focusWindow(windowID: exactWindowID,
                               pid: ownerPID,
                               makeAppFrontmost: false) {
                    return
                }
                activateAppCooperatively(app,
                                         allWindows: false)
                if let windowID {
                    focusWindow(windowID: windowID,
                                pid: windowOwnerPID ?? app.processIdentifier,
                                makeAppFrontmost: false)
                }
                return
            }
            guard isCurrent() else { return }
            if !fronted {
                activateAppCooperatively(app,
                                         allWindows: false)
            }
            scheduleFocusWindow(windowID: exactWindowID,
                                ownerPID: ownerPID,
                                fallsBackToCooperativeActivation: fronted)
            return
        }

        activateAppCooperatively(app,
                                 allWindows: plan.activateAllWindows)
        if let windowID {
            scheduleFocusWindow(windowID: windowID,
                                ownerPID: windowOwnerPID ?? app.processIdentifier,
                                fallsBackToCooperativeActivation: false)
        }
    }

    private static func activateAppCooperatively(_ app: NSRunningApplication,
                                                 allWindows: Bool) {
        let options: NSApplication.ActivationOptions = allWindows ? [.activateAllWindows] : []
        ActivationHandoff.yield(to: app)
        // The first answer is kept as it is: the fallback only runs when the
        // first request was refused.
        let activated = app.activate(from: NSRunningApplication.current, options: options)
        if !activated {
            app.activate(options: options)
        }
    }

    private static func isActivationTargetFrontmost(_ app: NSRunningApplication,
                                                    windowOwnerPID: pid_t) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        if frontmost.processIdentifier == app.processIdentifier
            || frontmost.processIdentifier == windowOwnerPID {
            return true
        }
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return frontmost.bundleIdentifier == bundleIdentifier
    }

    static func supersedePendingActivations(for pid: pid_t) -> UInt64 {
        let generation = beginActivation(for: pid)
        cancelPendingMinimizeRestore()
        SpaceHop.cancelPending()
        return generation
    }

    private static func beginActivation(for pid: pid_t) -> UInt64 {
        activationLock.withLock {
            activationGeneration &+= 1
            activationGenerationsByPID[pid] = activationGeneration
            return activationGeneration
        }
    }

    fileprivate static func activationGeneration(for pid: pid_t) -> UInt64 {
        activationLock.withLock { activationGenerationsByPID[pid] ?? 0 }
    }

    static func isCurrentActivation(_ generation: UInt64) -> Bool {
        activationLock.withLock {
            SwitcherSupport.isCurrentActivationGeneration(
                generation,
                current: activationGeneration
            )
        }
    }

    private static func scheduleInitialMinimizedStateObservation(
        _ state: SwitcherWindowFocusRetryState,
        windowID: CGWindowID,
        pid: pid_t,
        generation: UInt64) {
        runObservation {
            guard isCurrentActivation(generation) else { return }
            state.observeInitialMinimizedState {
                windowMinimizedState(windowID: windowID, pid: pid)
            }
        }
    }

    private static func scheduleSourceStaging(targetWindowID: CGWindowID,
                                              targetPID: pid_t,
                                              targetWindowOwnerPID: pid_t,
                                              sourcePID: pid_t?,
                                              sourceWindowID: CGWindowID?,
                                              sourceWindowOwnerPID: pid_t?,
                                              activationPlan: SwitcherActivationPlan,
                                              generation: UInt64,
                                              stagingState: SwitcherSourceStagingState,
                                              observedFrontmostPID: pid_t?) {
        // A confirmed staging already left the source window behind the
        // target. Staging it again asks both apps for their window list a
        // second time, and only a source that came back to the front is no
        // longer behind the target.
        guard !SwitcherSupport.shouldSkipSourceStaging(outcome: stagingState.lastOutcome,
                                                       frontmostPID: observedFrontmostPID,
                                                       sourcePID: sourcePID) else {
            return
        }
        activationAXQueue.async {
            guard isCurrentActivation(generation) else { return }
            let outcome = stageSourceBehindTargetIfNeeded(
                targetWindowID: targetWindowID,
                targetPID: targetPID,
                targetWindowOwnerPID: targetWindowOwnerPID,
                sourcePID: sourcePID,
                sourceWindowID: sourceWindowID,
                sourceWindowOwnerPID: sourceWindowOwnerPID,
                activationPlan: activationPlan,
                generation: generation)
            stagingState.record(outcome, generation: generation)
        }
    }

    private struct FocusRetryReadings {
        let minimizedState: Bool?
        let targetWindowIDs: Set<CGWindowID>
        let focusedWindowID: CGWindowID?
    }

    private static func readFocusRetryReadings(windowID: CGWindowID,
                                               targetWindowOwnerPID: pid_t) -> FocusRetryReadings {
        let minimizedState = windowMinimizedState(windowID: windowID,
                                                  pid: targetWindowOwnerPID)
        let targetWindowIDs = windowIDs(ownerPID: targetWindowOwnerPID,
                                        options: .optionAll)
        return FocusRetryReadings(minimizedState: minimizedState,
                                  targetWindowIDs: targetWindowIDs,
                                  focusedWindowID: nil)
    }

    private static func readFocusRetryFocusedWindowID(ownerPID: pid_t,
                                                      targetWindowID: CGWindowID?,
                                                      generation: UInt64?) -> CGWindowID? {
        let reading = focusedWindowReading(for: ownerPID)
        return reading.windowID
    }

    private static func needsFocusedWindowRead(targetPID: pid_t,
                                               sourcePID: pid_t?,
                                               targetWindowOwnerPID: pid_t,
                                               frontmostPID: pid_t?,
                                               readings: FocusRetryReadings,
                                               state: SwitcherWindowFocusRetryState,
                                               ignoresForeground: Bool = false,
                                               stopsWhenTargetFocused: Bool = false) -> Bool {
        let effectiveFrontmostPID = frontmostPID == targetWindowOwnerPID
            ? targetPID
            : frontmostPID
        // A minimized target only skips the focused-window read while its
        // restoration is still unconfirmed. Once this pass reads the window as
        // restored, it is treated like any other target: read the focused
        // window so the delayed pass can stand down instead of raising an
        // already focused window a second time.
        let minimizedStillRestoring = state.targetStartedMinimized
            && readings.minimizedState != false
        if stopsWhenTargetFocused,
           !ignoresForeground,
           !minimizedStillRestoring,
           effectiveFrontmostPID == targetPID {
            return true
        }
        var focusedWindowWasConsumed = false
        func noteFocusedWindowConsumption() -> CGWindowID? {
            focusedWindowWasConsumed = true
            return nil
        }
        _ = SwitcherSupport.shouldContinueFocusRetry(
            targetPID: targetPID,
            sourcePID: sourcePID,
            frontmostPID: effectiveFrontmostPID,
            targetIsMinimized: readings.minimizedState == true,
            targetStartedMinimized: state.targetStartedMinimized,
            targetWasObservedRestored: state.targetWasObservedRestored,
            knownWindowIDs: state.knownWindowIDs,
            targetAppWindowIDs: readings.targetWindowIDs,
            targetAppFocusedWindowID: noteFocusedWindowConsumption(),
            ignoresForeground: ignoresForeground
        )
        return focusedWindowWasConsumed
    }

    private static func scheduleFocusRetries(windowID: CGWindowID,
                                             targetPID: pid_t,
                                             targetWindowOwnerPID: pid_t,
                                             sourcePID: pid_t?,
                                             retrySourcePID: pid_t?,
                                             sourceWindowID: CGWindowID?,
                                             sourceWindowOwnerPID: pid_t?,
                                             state: SwitcherWindowFocusRetryState,
                                             stagingState: SwitcherSourceStagingState,
                                             activationPlan: SwitcherActivationPlan,
                                             generation: UInt64,
                                             delays: [TimeInterval],
                                             stopsWhenTargetFocused: Bool = false,
                                             scheduledAt: DispatchTime = .now(),
                                             delayIndex: Int = 0) {
        guard delays.indices.contains(delayIndex) else { return }
        let delay = delays[delayIndex]
        // Every delay remains anchored to this chain's original schedule time.
        let deadline = scheduledAt + delay
        DispatchQueue.main.asyncAfter(deadline: deadline) {
            // Retry state belongs to main. Stale passes never enter the AX queue.
            guard state.isActive else {
                return
            }
            guard isCurrentActivation(generation) else {
                return
            }
            runObservation {
                // The baseline this pass compares against was read on this
                // lane before the pass was queued, so the lane's order is the
                // join: the baseline has answered by the time this pass
                // looks at the owner's windows.
                guard isCurrentActivation(generation) else {
                    return
                }
                let readings = readFocusRetryReadings(
                    windowID: windowID,
                    targetWindowOwnerPID: targetWindowOwnerPID)
                DispatchQueue.main.async {
                    guard state.isActive else {
                        return
                    }
                    guard isCurrentActivation(generation) else {
                        return
                    }
                    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    let needsFocusedWindow = needsFocusedWindowRead(
                        targetPID: targetPID,
                        sourcePID: retrySourcePID,
                        targetWindowOwnerPID: targetWindowOwnerPID,
                        frontmostPID: frontmostPID,
                        readings: readings,
                        state: state,
                        stopsWhenTargetFocused: stopsWhenTargetFocused
                    )
                    let continueWithReadings: (FocusRetryReadings, pid_t?, (() -> pid_t?)?) -> Void = {
                        finalReadings, initialFrontmostPID, postQueryFrontmostPID in
                        let shouldContinue = shouldContinueFocusRetry(
                            windowID: windowID,
                            targetPID: targetPID,
                            targetWindowOwnerPID: targetWindowOwnerPID,
                            sourcePID: retrySourcePID,
                            state: state,
                            readings: finalReadings,
                            frontmostPID: initialFrontmostPID,
                            frontmostAfterFocusQueryPID: postQueryFrontmostPID,
                            stopsWhenTargetFocused: stopsWhenTargetFocused)
                        guard shouldContinue,
                              let app = NSRunningApplication(processIdentifier: targetPID),
                              !app.isTerminated else { return }
                        activationAXQueue.async {
                            guard isCurrentActivation(generation) else { return }
                            prepareWindowForActivation(windowID: windowID,
                                                       pid: targetWindowOwnerPID,
                                                       generation: generation)
                            guard isCurrentActivation(generation) else { return }
                            DispatchQueue.main.async {
                                guard isCurrentActivation(generation) else { return }
                                // One foreground sample decides this round and
                                // the source staging below, so the two cannot
                                // disagree about who is in front.
                                let observedFrontmostPID =
                                    NSWorkspace.shared.frontmostApplication?.processIdentifier
                                let shouldStillContinue = shouldContinueFocusRetry(
                                    windowID: windowID,
                                    targetPID: targetPID,
                                    targetWindowOwnerPID: targetWindowOwnerPID,
                                    sourcePID: retrySourcePID,
                                    state: state,
                                    readings: finalReadings,
                                    frontmostPID: observedFrontmostPID,
                                    stopsWhenTargetFocused: stopsWhenTargetFocused
                                )
                                guard shouldStillContinue,
                                      let app = NSRunningApplication(processIdentifier: targetPID),
                                      !app.isTerminated else { return }
                                activateApp(app,
                                            plan: activationPlan,
                                            windowID: windowID,
                                            windowOwnerPID: targetWindowOwnerPID,
                                            generation: generation)
                                // The source window is only in front again when
                                // the user went back to it. The target's own
                                // activation in this round brought the target
                                // forward, so the source is behind it unless
                                // the observation above said otherwise.
                                scheduleSourceStaging(
                                    targetWindowID: windowID,
                                    targetPID: targetPID,
                                    targetWindowOwnerPID: targetWindowOwnerPID,
                                    sourcePID: sourcePID,
                                    sourceWindowID: sourceWindowID,
                                    sourceWindowOwnerPID: sourceWindowOwnerPID,
                                    activationPlan: activationPlan,
                                    generation: generation,
                                    stagingState: stagingState,
                                    observedFrontmostPID: observedFrontmostPID
                                )
                                scheduleFocusRetries(
                                    windowID: windowID,
                                    targetPID: targetPID,
                                    targetWindowOwnerPID: targetWindowOwnerPID,
                                    sourcePID: sourcePID,
                                    retrySourcePID: retrySourcePID,
                                    sourceWindowID: sourceWindowID,
                                    sourceWindowOwnerPID: sourceWindowOwnerPID,
                                    state: state,
                                    stagingState: stagingState,
                                    activationPlan: activationPlan,
                                    generation: generation,
                                    delays: delays,
                                    stopsWhenTargetFocused: stopsWhenTargetFocused,
                                    scheduledAt: scheduledAt,
                                    delayIndex: delayIndex + 1
                                )
                            }
                        }
                    }
                    guard needsFocusedWindow else {
                        continueWithReadings(readings, frontmostPID, nil)
                        return
                    }
                    runObservation {
                        guard isCurrentActivation(generation) else {
                            return
                        }
                        let focusedWindowID = readFocusRetryFocusedWindowID(
                            ownerPID: targetWindowOwnerPID,
                            targetWindowID: windowID,
                            generation: generation
                        )
                        let finalReadings = FocusRetryReadings(
                            minimizedState: readings.minimizedState,
                            targetWindowIDs: focusedWindowID.map {
                                readings.targetWindowIDs.union([$0])
                            } ?? readings.targetWindowIDs,
                            focusedWindowID: focusedWindowID
                        )
                        DispatchQueue.main.async {
                            guard isCurrentActivation(generation) else {
                                return
                            }
                            guard state.isActive else {
                                return
                            }
                            let postQueryFrontmostPID =
                                NSWorkspace.shared.frontmostApplication?.processIdentifier
                            continueWithReadings(
                                finalReadings,
                                frontmostPID,
                                { postQueryFrontmostPID }
                            )
                        }
                    }
                }
            }
        }
    }

    private static func scheduleAppActivationRetries(targetPID: pid_t,
                                                     sourcePID: pid_t?,
                                                     plan: SwitcherActivationPlan,
                                                     state: SwitcherAppActivationRetryState,
                                                     generation: UInt64,
                                                     delays: [TimeInterval]) {
        guard !delays.isEmpty else {
            state.invalidate()
            return
        }
        for (index, delay) in delays.enumerated() {
            let deadline = DispatchTime.now() + delay
            DispatchQueue.main.asyncAfter(deadline: deadline) {
                guard state.isActive else {
                    state.invalidate()
                    return
                }
                guard isCurrentActivation(generation) else {
                    state.invalidate()
                    return
                }
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                state.observe(frontmostPID: frontmostPID)
                guard SwitcherSupport.shouldContinueAppActivationRetry(
                    targetPID: targetPID,
                    sourcePID: sourcePID,
                    frontmostPID: frontmostPID,
                    targetWasObservedFrontmost: state.targetWasObservedFrontmost
                ) else {
                    state.invalidate()
                    return
                }
                guard let app = NSRunningApplication(processIdentifier: targetPID),
                      !app.isTerminated else {
                    state.invalidate()
                    return
                }
                activateApp(app, plan: plan)
                if index == delays.count - 1 {
                    state.invalidate()
                }
            }
        }
    }

    private static func windowIDs(ownerPID: pid_t,
                                  options: CGWindowListOption) -> Set<CGWindowID> {
        let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        let raw = windowInfo as? [[String: Any]] ?? []
        let windowIDs = SwitcherSupport.focusRetryWindowIDs(in: raw, ownerPID: ownerPID)
        return windowIDs
    }

    private static func shouldContinueFocusRetry(windowID: CGWindowID,
                                                 targetPID: pid_t,
                                                 targetWindowOwnerPID: pid_t,
                                                 sourcePID: pid_t?,
                                                 state: SwitcherWindowFocusRetryState,
                                                 ignoresForeground: Bool = false,
                                                 stopsWhenTargetFocused: Bool = false,
                                                 generation: UInt64? = nil) -> Bool {
        guard state.isActive else { return false }
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var readings = readFocusRetryReadings(
            windowID: windowID,
            targetWindowOwnerPID: targetWindowOwnerPID)
        if needsFocusedWindowRead(
            targetPID: targetPID,
            sourcePID: sourcePID,
            targetWindowOwnerPID: targetWindowOwnerPID,
            frontmostPID: reportedFrontmostPID,
            readings: readings,
            state: state,
            ignoresForeground: ignoresForeground,
            stopsWhenTargetFocused: stopsWhenTargetFocused
        ) {
            readings = FocusRetryReadings(
                minimizedState: readings.minimizedState,
                targetWindowIDs: readings.targetWindowIDs,
                focusedWindowID: readFocusRetryFocusedWindowID(
                    ownerPID: targetWindowOwnerPID,
                    targetWindowID: windowID,
                    generation: generation
                )
            )
        }
        return shouldContinueFocusRetry(
            windowID: windowID,
            targetPID: targetPID,
            targetWindowOwnerPID: targetWindowOwnerPID,
            sourcePID: sourcePID,
            state: state,
            readings: readings,
            frontmostPID: reportedFrontmostPID,
            ignoresForeground: ignoresForeground,
            stopsWhenTargetFocused: stopsWhenTargetFocused)
    }

    private static func shouldContinueFocusRetry(windowID: CGWindowID,
                                                 targetPID: pid_t,
                                                 targetWindowOwnerPID: pid_t,
                                                 sourcePID: pid_t?,
                                                 state: SwitcherWindowFocusRetryState,
                                                 readings: FocusRetryReadings,
                                                 frontmostPID: pid_t?,
                                                 frontmostAfterFocusQueryPID: (() -> pid_t?)? = nil,
                                                 ignoresForeground: Bool = false,
                                                 stopsWhenTargetFocused: Bool = false) -> Bool {
        guard state.isActive else { return false }
        let effectiveFrontmostPID = frontmostPID == targetWindowOwnerPID
            ? targetPID
            : frontmostPID
        let shouldContinue = state.shouldContinue(
            targetPID: targetPID,
            sourcePID: sourcePID,
            frontmostPID: effectiveFrontmostPID,
            frontmostAfterFocusQueryPID: frontmostAfterFocusQueryPID.map { read in
                {
                    let postQueryPID = read()
                    return postQueryPID == targetWindowOwnerPID ? targetPID : postQueryPID
                }
            },
            targetMinimizedState: readings.minimizedState,
            targetAppWindowIDs: readings.targetWindowIDs,
            // Use the same all-windows scope as the snapshot. The on-screen
            // list can lag a new window that Accessibility already reports
            // as focused.
            targetAppFocusedWindowID: readings.focusedWindowID,
            targetWindowIsFocused: readings.focusedWindowID == windowID,
            stopsWhenTargetFocused: stopsWhenTargetFocused,
            ignoresForeground: ignoresForeground
        )
        return shouldContinue
    }

    private static func watchTargetMinimizeIfNeeded(windowID: CGWindowID,
                                                    targetPID: pid_t,
                                                    targetWindowOwnerPID: pid_t,
                                                    sourcePID: pid_t?,
                                                    sourceWindowID: CGWindowID?,
                                                    sourceWindowOwnerPID: pid_t?,
                                                    activationPlan: SwitcherActivationPlan,
                                                    generation: UInt64,
                                                    targetWindow: SwitcherActivationTargetWindow) {
        guard activationPlan.restoreSourceWhenTargetMinimizes,
              let sourcePID,
              SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: targetPID,
                                                                     sourcePID: sourcePID,
                                                                     frontmostPID: targetPID,
                                                                     targetIsMinimized: true)
        else {
            return
        }

        // The element is resolved here, after the guard, so a switch that
        // never installs the observer does not ask the app for its window
        // list at all.
        pendingMinimizeRestore = SwitcherWindowMinimizeRestore(windowID: windowID,
                                                               targetPID: targetPID,
                                                               targetWindowOwnerPID: targetWindowOwnerPID,
                                                               sourcePID: sourcePID,
                                                               sourceWindowID: sourceWindowID,
                                                               sourceWindowOwnerPID: sourceWindowOwnerPID,
                                                               generation: generation,
                                                               axWindow: targetWindow.element())
    }

    fileprivate static func cancelPendingMinimizeRestore() {
        pendingMinimizeRestore?.invalidate()
        pendingMinimizeRestore = nil
    }

    fileprivate static func cancelPendingMinimizeRestore(_ restore: SwitcherWindowMinimizeRestore) {
        guard pendingMinimizeRestore === restore else { return }
        cancelPendingMinimizeRestore()
    }

    fileprivate static func restoreSourceAfterTargetMinimizeIntent(_ restore: SwitcherWindowMinimizeRestore,
                                                                   keepPending: Bool = false,
                                                                   allowSystemPromotion: Bool = false) {
        guard pendingMinimizeRestore === restore,
              isCurrentActivation(restore.generation) else { return }
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostPID = reportedFrontmostPID == restore.targetWindowOwnerPID
            ? restore.targetPID
            : reportedFrontmostPID
        guard SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(
                targetPID: restore.targetPID,
                sourcePID: restore.sourcePID,
                frontmostPID: frontmostPID,
                focusedWindowID: { () -> CGWindowID? in
                    let reading = focusedWindowReading(for: restore.targetWindowOwnerPID)
                    return reading.windowID
                }(),
                targetWindowID: restore.windowID,
                targetIsMinimized: windowIsMinimized(windowID: restore.windowID,
                                                     pid: restore.targetWindowOwnerPID),
                frontmostMatchesTargetBundle: restore.matchesTargetBundle(frontmostPID),
                frontmostCanBeSystemPromotion: allowSystemPromotion) else { return }
        guard activateSource(pid: restore.sourcePID,
                             windowID: restore.sourceWindowID,
                             windowOwnerPID: restore.sourceWindowOwnerPID,
                             generation: restore.generation) else {
            cancelPendingMinimizeRestore()
            return
        }

        if !keepPending {
            cancelPendingMinimizeRestore()
        }
    }

    @discardableResult
    private static func activateSource(pid: pid_t,
                                       windowID: CGWindowID?,
                                       windowOwnerPID: pid_t?,
                                       generation: UInt64? = nil) -> Bool {
        guard generation.map({ isCurrentActivation($0) }) ?? true,
              let sourceApp = NSRunningApplication(processIdentifier: pid),
              !sourceApp.isTerminated else { return false }

        if sourceApp.isHidden { sourceApp.unhide() }
        if let windowID {
            prepareWindowForActivation(windowID: windowID,
                                       pid: windowOwnerPID ?? pid,
                                       generation: generation)
        }
        guard generation.map({ isCurrentActivation($0) }) ?? true else { return false }
        // A missing source window (including a fullscreen source) is still a
        // return gesture, not a request to raise every window of that app.
        activateApp(sourceApp,
                    plan: SwitcherSupport.activationPlan(targetsSpecificWindow: true),
                    windowID: windowID,
                    windowOwnerPID: windowOwnerPID ?? pid,
                    generation: generation)
        return true
    }

    @discardableResult
    private static func prepareWindowForActivation(windowID: CGWindowID,
                                                   pid: pid_t,
                                                   generation: UInt64? = nil,
                                                   target: SwitcherActivationTargetWindow? = nil) -> Bool {
        func isCurrent() -> Bool {
            generation.map { isCurrentActivation($0) } ?? true
        }
        guard isCurrent(), Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        // The element this activation already resolved for the same window
        // is used as it is; a step that runs on its own resolves its own.
        // Asking the target object here keeps the resolution behind the
        // guards: a preparation that returns early never asks the app.
        let axWindow: AXUIElement
        if let providedWindow = target?.element() {
            guard isCurrent() else { return false }
            axWindow = providedWindow
        } else {
            guard isCurrent(),
                  let resolved = axElement(windowID: windowID,
                                          in: axApp),
                  isCurrent() else {
                return false
            }
            axWindow = resolved
        }

        var minimized: CFTypeRef?
        let minimizedResult = AXUIElementCopyAttributeValue(
            axWindow, kAXMinimizedAttribute as CFString, &minimized)
        guard isCurrent() else { return false }
        if minimizedResult == .success, (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(axWindow,
                                         kAXMinimizedAttribute as CFString,
                                         kCFBooleanFalse)
            guard isCurrent() else { return false }
        }
        AXUIElementSetAttributeValue(axApp,
                                     kAXMainWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axApp,
                                     kAXFocusedWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXMainAttribute as CFString,
                                     kCFBooleanTrue)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXFocusedAttribute as CFString,
                                     kCFBooleanTrue)
        guard isCurrent() else { return false }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return true
    }

    private static func stageSourceBehindTargetIfNeeded(targetWindowID: CGWindowID,
                                                        targetPID: pid_t,
                                                        targetWindowOwnerPID: pid_t,
                                                        sourcePID: pid_t?,
                                                        sourceWindowID: CGWindowID?,
                                                        sourceWindowOwnerPID: pid_t?,
                                                        activationPlan: SwitcherActivationPlan,
                                                        generation: UInt64) -> SwitcherSourceStagingOutcome {
        guard isCurrentActivation(generation),
              activationPlan.restoreSourceWhenTargetMinimizes,
              SwitcherSupport.shouldStageSourceBehindTarget(targetPID: targetPID,
                                                            sourcePID: sourcePID,
                                                            sourceWindowID: sourceWindowID),
              let sourcePID,
              let sourceWindowID,
              Permissions.shared.accessibility else {
            return .notApplicable
        }

        let sourceApp = AXUIElementCreateApplication(sourceWindowOwnerPID ?? sourcePID)
        let targetApp = AXUIElementCreateApplication(targetWindowOwnerPID)
        AXUIElementSetMessagingTimeout(sourceApp, 0.35)
        AXUIElementSetMessagingTimeout(targetApp, 0.35)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        let sourceWindow = axElement(windowID: sourceWindowID,
                                     in: sourceApp)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        guard let sourceWindow else {
            return .unresolved
        }
        let targetWindow = axElement(windowID: targetWindowID,
                                     in: targetApp)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        guard let targetWindow else {
            return .unresolved
        }

        var sourceMinimized: CFTypeRef?
        let minimizedResult = AXUIElementCopyAttributeValue(
            sourceWindow, kAXMinimizedAttribute as CFString, &sourceMinimized)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        // A minimized source window cannot sit behind the target yet. An
        // unreadable minimized state is not a minimized window, so the staging
        // still runs, but it cannot be confirmed either.
        if minimizedResult == .success, (sourceMinimized as? Bool) == true {
            return .sourceMinimized
        }

        // Do not pull the source back over an already-active target. Keep the
        // target raise below: foreground/focus alone does not prove it is onscreen.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetIsFrontmost = frontmostPID == targetPID || frontmostPID == targetWindowOwnerPID
        if targetIsFrontmost,
           windowIsVisiblyFocused(windowID: targetWindowID,
                                  pid: targetWindowOwnerPID,
                                  window: targetWindow),
           isCurrentActivation(generation) {
            return minimizedResult == .success ? .staged : .unresolved
        }
        let sourceReady = targetIsFrontmost
            || AXUIElementPerformAction(sourceWindow, kAXRaiseAction as CFString) == .success
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        let targetRaiseResult = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        let mainWindowResult = AXUIElementSetAttributeValue(targetApp,
                                                             kAXMainWindowAttribute as CFString,
                                                             targetWindow)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        let focusedWindowResult = AXUIElementSetAttributeValue(targetApp,
                                                                kAXFocusedWindowAttribute as CFString,
                                                                targetWindow)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        let windowMainResult = AXUIElementSetAttributeValue(targetWindow,
                                                             kAXMainAttribute as CFString,
                                                             kCFBooleanTrue)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        let windowFocusedResult = AXUIElementSetAttributeValue(targetWindow,
                                                                kAXFocusedAttribute as CFString,
                                                                kCFBooleanTrue)
        guard isCurrentActivation(generation) else {
            return .unresolved
        }
        // Only confirmed source placement and target operations finish staging.
        // Otherwise the next retry pass stages it again.
        let staged = minimizedResult == .success
            && sourceReady
            && targetRaiseResult == .success
            && mainWindowResult == .success
            && focusedWindowResult == .success
            && windowMainResult == .success
            && windowFocusedResult == .success
        return staged ? .staged : .unresolved
    }

    private static func windowIsVisiblyFocused(windowID: CGWindowID,
                                               pid: pid_t,
                                               window: AXUIElement) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              minimizedState(of: window) == false,
              focusedWindowID(for: pid) == windowID,
              let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]],
              let frontWindow = onscreen.first(where: {
                  ($0[kCGWindowLayer as String] as? Int) == 0
              }) else { return false }
        return (frontWindow[kCGWindowNumber as String] as? CGWindowID) == windowID
    }

    // AXMinimized changes at the start of the Dock animation. Its completion
    // notification is the boundary for focus writes, not that early state read.
    // Generated switcher passes wait on the AX lane, never the keyboard callback.
    // Unsupported/missing notifications retain the normal focus fallback.
    private static func restoreWindowBeforeFocus(_ window: AXUIElement,
                                                 pid: pid_t,
                                                 generation: UInt64?) -> Bool {
        guard let generation else {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            return false
        }
        var observer: AXObserver?
        let created = AXObserverCreate(pid, { _, _, _, context in
            context?.assumingMemoryBound(to: Bool.self).pointee = true
        }, &observer)
        guard created == .success, let observer else {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            return false
        }
        var completed = false
        return withUnsafeMutablePointer(to: &completed) { completion in
            let notification = kAXWindowDeminiaturizedNotification as CFString
            guard AXObserverAddNotification(observer, window, notification, completion) == .success else {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                return false
            }
            let runLoop = CFRunLoopGetCurrent()
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            defer {
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
                AXObserverRemoveNotification(observer, window, notification)
            }
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                               kCFBooleanFalse) == .success else { return false }
            let deadline = DispatchTime.now() + 0.5
            while !completion.pointee,
                  isCurrentActivation(generation),
                  DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds {
                CFRunLoopRunInMode(.defaultMode, 0.01, true)
            }
            return completion.pointee
        }
    }

    @discardableResult
    private static func focusWindow(windowID: CGWindowID,
                                    pid: pid_t,
                                    makeAppFrontmost: Bool = true,
                                    generation: UInt64? = nil) -> Bool {
        func isCurrent() -> Bool {
            generation.map { isCurrentActivation($0) } ?? true
        }
        guard isCurrent(), Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard isCurrent(),
              let axWindow = axElement(windowID: windowID,
                                      in: axApp),
              isCurrent() else {
            return false
        }

        var minimized: CFTypeRef?
        let minimizedResult = AXUIElementCopyAttributeValue(
            axWindow, kAXMinimizedAttribute as CFString, &minimized)
        guard isCurrent() else { return false }
        if minimizedResult == .success, (minimized as? Bool) == true {
            let completed = restoreWindowBeforeFocus(axWindow, pid: pid, generation: generation)
            guard isCurrent() else { return false }
            if completed,
               windowIsVisiblyFocused(windowID: windowID, pid: pid, window: axWindow),
               isCurrent() {
                return true
            }
        }

        if makeAppFrontmost {
            AXUIElementSetAttributeValue(axApp,
                                         kAXFrontmostAttribute as CFString,
                                         kCFBooleanTrue)
            guard isCurrent() else { return false }
        }
        AXUIElementSetAttributeValue(axApp,
                                     kAXMainWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axApp,
                                     kAXFocusedWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        let raised = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXMainAttribute as CFString,
                                     kCFBooleanTrue)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXFocusedAttribute as CFString,
                                     kCFBooleanTrue)
        return isCurrent() && raised == .success
    }

    /// Every window the owner has right now, in the scope the retry guard
    /// compares against. Taken by a hop at the moment it begins.
    static func focusSnapshot(ownerPID: pid_t) -> Set<CGWindowID> {
        windowIDs(ownerPID: ownerPID,
                  options: .optionAll)
    }

    /// Focus pass run by SpaceHop once the target window's Space became
    /// visible and Accessibility can finally describe the window.
    ///
    /// Its pulses run up to a second after the switch, long enough for the
    /// user to open a window in the app they just reached — Command-N right
    /// after switching away from a fullscreen app lands here. They consult the
    /// same guard as every other delayed pass, so a window the app did not
    /// have when the hop began ends them instead of being covered.
    static func focusAfterSpaceHop(windowID: CGWindowID,
                                   appPID: pid_t,
                                   windowOwnerPID: pid_t,
                                   sourcePID: pid_t?,
                                   state: SwitcherWindowFocusRetryState) {
        // The generation here is looked up by app, not handed over by the
        // hop: it is a fallback, and it is never the session's own number.
        let generation = activationGeneration(for: appPID)
        guard isCurrentActivation(generation),
              let app = NSRunningApplication(processIdentifier: appPID),
              !app.isTerminated else {
            return
        }
        // Travelling fronts whatever tops each desktop on the way, so this
        // pass judges the app's own focus rather than who is in front.
        guard shouldContinueFocusRetry(windowID: windowID,
                                       targetPID: appPID,
                                       targetWindowOwnerPID: windowOwnerPID,
                                       sourcePID: sourcePID,
                                       state: state,
                                       ignoresForeground: true,
                                       generation: generation) else {
            return
        }
        prepareWindowForActivation(windowID: windowID,
                                   pid: windowOwnerPID,
                                   generation: generation)
        guard isCurrentActivation(generation) else { return }
        activateApp(app,
                    plan: SwitcherSupport.activationPlan(targetsSpecificWindow: true),
                    windowID: windowID,
                    windowOwnerPID: windowOwnerPID,
                    generation: generation)
    }

    /// Finds the Accessibility element of one window of an app. Asking for the
    /// window list and asking each window for its WindowServer id are two
    /// separate questions to the other process, and a stalled app can answer
    /// neither. Development builds time the two apart, with the number of
    /// windows listed and the number of ids resolved, so a slow list and a slow
    /// id lookup are told apart instead of arriving as one long wait.
    private static func axElement(windowID: CGWindowID,
                                  in axApp: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let listResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard listResult == .success,
              let axWindows = value as? [AXUIElement]
        else { return nil }

        for axWindow in axWindows {
            let resolvedWindowID = AXWindowResolver.windowID(for: axWindow)
            if resolvedWindowID == windowID {
                return axWindow
            }
        }
        return nil
    }

    fileprivate static func axElementForMinimizeRestore(windowID: CGWindowID,
                                                        in axApp: AXUIElement) -> AXUIElement? {
        axElement(windowID: windowID,
                  in: axApp)
    }

    fileprivate static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    fileprivate static func boolAttribute(_ element: AXUIElement, _ attribute: String, default defaultValue: Bool) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return defaultValue }
        return (value as? Bool) ?? defaultValue
    }

    private static func minimizedState(of axWindow: AXUIElement) -> Bool? {
        SwitcherActivationTargetWindow.minimizedState(of: axWindow)
    }
}

/// Lives only while one explicit close request is travelling to another Space.
/// The existing Space hop owns the transition; this object merely waits for
/// the exact window to become reachable and then uses the normal close path.
fileprivate final class SwitcherPendingWindowClose {
    private static let pollInterval: TimeInterval = 0.1
    private static let timeout: TimeInterval = 4.0

    private let item: SwitcherItem
    private let restoresHiddenApp: Bool
    fileprivate let usesSpaceHop: Bool
    private let completion: (Bool) -> Void
    private let deadline: DispatchTime
    private var completed = false
    private var revealGeneration: UInt64?
    private var activationObserver: NSObjectProtocol?
    private var observedExpectedActivation: Bool
    private var appWasReactivated = false

    init(item: SwitcherItem,
         restoresHiddenApp: Bool,
         usesSpaceHop: Bool,
         completion: @escaping (Bool) -> Void) {
        self.item = item
        self.restoresHiddenApp = restoresHiddenApp
        self.usesSpaceHop = usesSpaceHop
        self.completion = completion
        self.deadline = .now() + Self.timeout
        self.observedExpectedActivation = !usesSpaceHop
    }

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.processIdentifier == self.item.pid else { return }
            if self.observedExpectedActivation {
                self.appWasReactivated = true
            } else {
                self.observedExpectedActivation = true
            }
        }
        if usesSpaceHop {
            WindowActivator.activate(item, retry: false)
        } else {
            NSRunningApplication(processIdentifier: item.pid)?.unhide()
        }
        revealGeneration = WindowActivator.activationGeneration(for: item.pid)
        poll()
    }

    func cancel() {
        WindowActivator.finishPendingWindowClose(self, success: false)
    }

    func finish(success: Bool) {
        guard !completed else { return }
        completed = true
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if restoresHiddenApp,
           let revealGeneration,
           SwitcherSupport.shouldRestoreHiddenApp(
               revealGeneration: revealGeneration,
               currentGeneration: WindowActivator.activationGeneration(for: item.pid),
               appWasReactivated: appWasReactivated
           ),
           let app = NSRunningApplication(processIdentifier: item.pid),
           !app.isTerminated,
           usesSpaceHop || !app.isActive {
            app.hide()
        }
        completion(success)
    }

    private func poll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            guard let self, !self.completed, let windowID = self.item.windowID else { return }
            if !SpaceWindowBridge.isParkedOnHiddenSpace(windowID),
               WindowActivator.closeWindow(windowID: windowID,
                                           appPID: self.item.pid,
                                           windowOwnerPID: self.item.windowOwnerPID) {
                WindowActivator.finishPendingWindowClose(self, success: true)
            } else if DispatchTime.now() < self.deadline {
                self.poll()
            } else {
                WindowActivator.finishPendingWindowClose(self, success: false)
            }
        }
    }
}

private final class SwitcherAppActivationRetryState {
    private let targetPID: pid_t
    private var workspaceObserver: Any?
    private(set) var targetWasObservedFrontmost: Bool
    private(set) var isActive = true

    init(targetPID: pid_t) {
        self.targetPID = targetPID
        targetWasObservedFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.observe(frontmostPID: app.processIdentifier)
        }
    }

    func observe(frontmostPID: pid_t?) {
        if frontmostPID == targetPID {
            targetWasObservedFrontmost = true
        }
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }

    deinit {
        invalidate()
    }
}

fileprivate final class SwitcherWindowMinimizeRestore {
    let windowID: CGWindowID
    let targetPID: pid_t
    let targetWindowOwnerPID: pid_t
    let sourcePID: pid_t
    let sourceWindowID: CGWindowID?
    let sourceWindowOwnerPID: pid_t?

    private var observer: AXObserver?
    private var workspaceObserver: Any?
    private let lifecycleLock = NSLock()
    private var active = true
    fileprivate var minimizeIntentObserved = false
    private var minimizeCompletionRestoreScheduled = false
    private let targetBundleIdentifier: String?
    fileprivate let generation: UInt64
    private let sourceBundleIdentifier: String?

    init?(windowID: CGWindowID,
          targetPID: pid_t,
          targetWindowOwnerPID: pid_t,
          sourcePID: pid_t,
          sourceWindowID: CGWindowID?,
          sourceWindowOwnerPID: pid_t?,
          generation: UInt64,
          axWindow: AXUIElement? = nil) {
        guard Permissions.shared.accessibility else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(targetWindowOwnerPID)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        // The element of this activation's target window is used when the
        // activation already resolved it; the lookup below stays the
        // fallback for the steps that run on their own.
        let windowElement: AXUIElement
        if let provided = axWindow {
            windowElement = provided
        } else {
            guard let resolved = WindowActivator.axElementForMinimizeRestore(windowID: windowID,
                                                                            in: axApp) else {
                return nil
            }
            windowElement = resolved
        }

        var observerRef: AXObserver?
        let observerCreateResult = AXObserverCreate(targetWindowOwnerPID,
                                                    switcherWindowMinimizeRestoreCallback,
                                                    &observerRef)
        guard observerCreateResult == .success,
              let observer = observerRef else {
            return nil
        }

        self.windowID = windowID
        self.targetPID = targetPID
        self.targetWindowOwnerPID = targetWindowOwnerPID
        self.sourcePID = sourcePID
        self.sourceWindowID = sourceWindowID
        self.sourceWindowOwnerPID = sourceWindowOwnerPID
        self.generation = generation
        self.observer = observer
        self.targetBundleIdentifier = NSRunningApplication(processIdentifier: targetPID)?.bundleIdentifier
        self.sourceBundleIdentifier = NSRunningApplication(processIdentifier: sourcePID)?.bundleIdentifier

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let miniaturizedAddResult = AXObserverAddNotification(observer,
                                                              windowElement,
                                                              kAXWindowMiniaturizedNotification as CFString,
                                                              refcon)
        guard miniaturizedAddResult == .success else {
            self.observer = nil
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        let focusedAddResult = AXObserverAddNotification(observer,
                                                         axApp,
                                                         kAXFocusedWindowChangedNotification as CFString,
                                                         refcon)
        _ = focusedAddResult
        let mainAddResult = AXObserverAddNotification(observer,
                                                      axApp,
                                                      kAXMainWindowChangedNotification as CFString,
                                                      refcon)
        _ = mainAddResult
        let minimizeButton = WindowActivator.elementAttribute(windowElement,
                                                              kAXMinimizeButtonAttribute as String)
        if let minimizeButton {
            let minimizeButtonAddResult = AXObserverAddNotification(observer,
                                                                    minimizeButton,
                                                                    switcherAXPressedNotification as CFString,
                                                                    refcon)
            _ = minimizeButtonAddResult
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
    }

    func invalidate() {
        let shouldScheduleTeardown = lifecycleLock.withLock {
            guard active else { return false }
            active = false
            return true
        }
        guard shouldScheduleTeardown else { return }

        // AX callbacks belong to the main runloop. Detach the source on that
        // runloop first, then release the observer in the same turn while this
        // block still owns self. The callback refcon is unretained. Full
        // destruction does not send AXObserverRemoveNotification: the target
        // process drops the client when the observer port dies. A later path
        // that keeps the observer and drops only some notifications must still
        // remove those notifications; this activation has no such path.
        DispatchQueue.main.async { [self] in
            if let workspaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            }
            workspaceObserver = nil

            guard let source = self.observer.map(AXObserverGetRunLoopSource) else {
                return
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            withExtendedLifetime(self) {
                self.observer = nil
            }
        }
    }

    private var isActive: Bool {
        lifecycleLock.withLock { active }
    }

    func handle(notification: String) {
        guard isActive else { return }
        if notification == (kAXWindowMiniaturizedNotification as String) {
            minimizeIntentObserved = true
            scheduleMinimizeCompletionRestore()
        } else if notification == switcherAXPressedNotification {
            minimizeIntentObserved = true
            scheduleMinimizeIntentRestore()
        } else if notification == (kAXFocusedWindowChangedNotification as String)
                    || notification == (kAXMainWindowChangedNotification as String) {
            guard minimizeIntentObserved else { return }
            WindowActivator.restoreSourceAfterTargetMinimizeIntent(self)
        }
    }

    private func scheduleMinimizeIntentRestore() {
        scheduleRestorePulses(delays: [0.0, 0.01, 0.03, 0.06, 0.1, 0.16]
                              + denseRestoreDelays(from: 0.24, through: 1.0, step: 0.04),
                              completionDelay: 1.12)
    }

    private func scheduleMinimizeCompletionRestore() {
        guard !minimizeCompletionRestoreScheduled else { return }
        minimizeCompletionRestoreScheduled = true
        scheduleRestorePulses(delays: denseRestoreDelays(from: 0.0, through: 0.45, step: 0.003),
                              completionDelay: 0.5)
    }

    private func scheduleRestorePulses(delays: [TimeInterval], completionDelay: TimeInterval) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.minimizeIntentObserved else { return }
                WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                                       keepPending: true,
                                                                       allowSystemPromotion: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
            guard let self, self.minimizeIntentObserved else { return }
            WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                                   allowSystemPromotion: true)
            WindowActivator.cancelPendingMinimizeRestore(self)
        }
    }

    private func denseRestoreDelays(from start: TimeInterval,
                                    through end: TimeInterval,
                                    step: TimeInterval) -> [TimeInterval] {
        guard step > 0, end >= start else { return [] }
        var delays: [TimeInterval] = []
        var delay = start
        while delay <= end + 0.0001 {
            delays.append(delay)
            delay += step
        }
        return delays
    }

    fileprivate func matchesTargetBundle(_ pid: pid_t?) -> Bool {
        guard let pid,
              pid != targetPID,
              pid != sourcePID,
              let targetBundleIdentifier,
              targetBundleIdentifier != sourceBundleIdentifier else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == targetBundleIdentifier
    }

    fileprivate func matchesTargetBundle(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != targetPID,
              app.processIdentifier != sourcePID,
              let targetBundleIdentifier,
              targetBundleIdentifier != sourceBundleIdentifier else { return false }
        return app.bundleIdentifier == targetBundleIdentifier
    }

    fileprivate func restoreAfterTargetBundleActivation() {
        guard minimizeIntentObserved else { return }
        WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                               keepPending: true,
                                                               allowSystemPromotion: true)
    }

    private func handleAppActivation(_ notification: Notification) {
        guard isActive,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if minimizeIntentObserved {
            WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                                   keepPending: true,
                                                                   allowSystemPromotion: true)
            return
        }
        let activatedMatchesTargetBundle = app.processIdentifier == targetWindowOwnerPID
            || matchesTargetBundle(app)
        guard !SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: targetPID,
                                                                 sourcePID: sourcePID,
                                                                 activatedPID: app.processIdentifier,
                                                                 activatedMatchesTargetBundle: activatedMatchesTargetBundle) else {
            if activatedMatchesTargetBundle {
                restoreAfterTargetBundleActivation()
            }
            return
        }
        WindowActivator.cancelPendingMinimizeRestore()
    }

}

private func switcherWindowMinimizeRestoreCallback(_ observer: AXObserver,
                                                   _ element: AXUIElement,
                                                   _ notification: CFString,
                                                   _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let restore = Unmanaged<SwitcherWindowMinimizeRestore>.fromOpaque(refcon).takeUnretainedValue()
    restore.handle(notification: notification as String)
}
