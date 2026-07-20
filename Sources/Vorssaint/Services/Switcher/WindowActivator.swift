// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

private let switcherAXPressedNotification = "AXPressed"

/// Brings a switcher selection to the front: unminimizes if needed, makes the
/// exact window the app's focused/main Accessibility window and activates the
/// owning app. The focus pass is repeated after activation because Space changes
/// are asynchronous and some apps settle their main window one run-loop later.
enum WindowActivator {
    private static let focusRetryDelay: TimeInterval = 0.12
    private static let fullscreenFocusRetryDelays: [TimeInterval] = [0.18, 0.38, 0.68]
    private static var pendingMinimizeRestore: SwitcherWindowMinimizeRestore?

    static func activate(_ item: SwitcherItem,
                         retry: Bool = true,
                         sourceWasFullscreen: Bool = false,
                         sourcePID: pid_t? = nil,
                         sourceWindowID: CGWindowID? = nil,
                         sourceWindowOwnerPID: pid_t? = nil) {
        cancelPendingMinimizeRestore()

        if item.pid == ProcessInfo.processInfo.processIdentifier {
            activateOwnWindow(item)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        let windowOwnerPID = item.windowOwnerPID

        app.unhide()
        let activationPlan = SwitcherSupport.activationPlan(
            targetsSpecificWindow: item.windowID != nil
        )
        guard let windowID = item.windowID else {
            let retryState = retry && sourceWasFullscreen
                ? SwitcherAppActivationRetryState(targetPID: item.pid)
                : nil
            activateApp(app, allWindows: activationPlan.activateAllWindows)
            if let retryState {
                scheduleAppActivationRetries(targetPID: item.pid,
                                             sourcePID: sourcePID,
                                             allWindows: activationPlan.activateAllWindows,
                                             state: retryState,
                                             delays: Self.fullscreenFocusRetryDelays)
            }
            return
        }
        watchTargetMinimizeIfNeeded(windowID: windowID,
                                    targetPID: item.pid,
                                    targetWindowOwnerPID: windowOwnerPID,
                                    sourcePID: sourcePID,
                                    sourceWindowID: sourceWindowID,
                                    sourceWindowOwnerPID: sourceWindowOwnerPID,
                                    activationPlan: activationPlan)
        prepareWindowForActivation(windowID: windowID, pid: windowOwnerPID)
        if sourceWasFullscreen || item.isFullscreen {
            activateApp(app, allWindows: activationPlan.activateAllWindows)
            guard retry else {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.fullscreenFocusRetryDelays[0]) {
                    guard !windowIsMinimized(windowID: windowID, pid: windowOwnerPID),
                          let app = NSRunningApplication(processIdentifier: item.pid),
                          !app.isTerminated else { return }
                    prepareWindowForActivation(windowID: windowID, pid: windowOwnerPID)
                    activateApp(app, allWindows: activationPlan.activateAllWindows)
                    focusWindow(windowID: windowID,
                                pid: windowOwnerPID,
                                makeAppFrontmost: activationPlan.makeAppFrontmostAfterActivation)
                    stageSourceBehindTargetIfNeeded(targetWindowID: windowID,
                                                    targetPID: item.pid,
                                                    targetWindowOwnerPID: windowOwnerPID,
                                                    sourcePID: sourcePID,
                                                    sourceWindowID: sourceWindowID,
                                                    sourceWindowOwnerPID: sourceWindowOwnerPID,
                                                    activationPlan: activationPlan)
                }
                return
            }
            scheduleFocusRetries(windowID: windowID,
                                  targetPID: item.pid,
                                  targetWindowOwnerPID: windowOwnerPID,
                                  sourcePID: sourcePID,
                                  sourceWindowID: sourceWindowID,
                                  sourceWindowOwnerPID: sourceWindowOwnerPID,
                                  activationPlan: activationPlan,
                                  delays: Self.fullscreenFocusRetryDelays)
            return
        }

        activateApp(app, allWindows: activationPlan.activateAllWindows)
        focusWindow(windowID: windowID,
                    pid: windowOwnerPID,
                    makeAppFrontmost: activationPlan.makeAppFrontmostAfterActivation)
        stageSourceBehindTargetIfNeeded(targetWindowID: windowID,
                                        targetPID: item.pid,
                                        targetWindowOwnerPID: windowOwnerPID,
                                        sourcePID: sourcePID,
                                        sourceWindowID: sourceWindowID,
                                        sourceWindowOwnerPID: sourceWindowOwnerPID,
                                        activationPlan: activationPlan)

        guard retry else { return }
        scheduleFocusRetries(windowID: windowID,
                              targetPID: item.pid,
                              targetWindowOwnerPID: windowOwnerPID,
                              sourcePID: sourcePID,
                              sourceWindowID: sourceWindowID,
                              sourceWindowOwnerPID: sourceWindowOwnerPID,
                              activationPlan: activationPlan,
                              delays: [focusRetryDelay])
    }

    static func activate(pid: pid_t, windowID: CGWindowID?, appName: String, retry: Bool = true) {
        let item: SwitcherItem
        if let windowID {
            item = .window(id: windowID, title: appName, appName: appName,
                           pid: pid, isOnScreen: true, frame: .zero)
        } else {
            item = .appOnly(appName: appName, pid: pid)
        }
        activate(item, retry: retry)
    }

    static func focusedWindowID(for pid: pid_t) -> CGWindowID? {
        guard Permissions.shared.accessibility else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindowResolver.windowID(for: value as! AXUIElement)
    }

    static func windowIsMinimized(windowID: CGWindowID, pid: pid_t) -> Bool {
        windowMinimizedState(windowID: windowID, pid: pid) == true
    }

    /// Three-state minimized check for guards that must fail closed: nil means
    /// the window could not be resolved or asked, so the caller cannot assume
    /// "not minimized" — hover peek treats that as hands-off, because peeking
    /// an unverifiable window is how a stale panel yanks a just-minimized
    /// window back out.
    static func windowMinimizedState(windowID: CGWindowID, pid: pid_t) -> Bool? {
        guard Permissions.shared.accessibility else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return nil }
        return minimizedState(of: axWindow)
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

    private static func activateApp(_ app: NSRunningApplication, allWindows: Bool = true) {
        NSApp.yieldActivation(to: app)
        if allWindows {
            if !app.activate(from: NSRunningApplication.current, options: [.activateAllWindows]) {
                app.activate(options: [.activateAllWindows])
            }
        } else {
            if !app.activate(from: NSRunningApplication.current, options: []) {
                app.activate(options: [])
            }
        }
    }

    private static func scheduleFocusRetries(windowID: CGWindowID,
                                             targetPID: pid_t,
                                             targetWindowOwnerPID: pid_t,
                                             sourcePID: pid_t?,
                                             sourceWindowID: CGWindowID?,
                                             sourceWindowOwnerPID: pid_t?,
                                             activationPlan: SwitcherActivationPlan,
                                             delays: [TimeInterval]) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard shouldContinueFocusRetry(windowID: windowID,
                                               targetPID: targetPID,
                                               targetWindowOwnerPID: targetWindowOwnerPID,
                                               sourcePID: sourcePID),
                      let app = NSRunningApplication(processIdentifier: targetPID),
                      !app.isTerminated else { return }
                prepareWindowForActivation(windowID: windowID, pid: targetWindowOwnerPID)
                activateApp(app, allWindows: activationPlan.activateAllWindows)
                focusWindow(windowID: windowID,
                            pid: targetWindowOwnerPID,
                            makeAppFrontmost: activationPlan.makeAppFrontmostAfterActivation)
                stageSourceBehindTargetIfNeeded(targetWindowID: windowID,
                                                targetPID: targetPID,
                                                targetWindowOwnerPID: targetWindowOwnerPID,
                                                sourcePID: sourcePID,
                                                sourceWindowID: sourceWindowID,
                                                sourceWindowOwnerPID: sourceWindowOwnerPID,
                                                activationPlan: activationPlan)
            }
        }
    }

    private static func scheduleAppActivationRetries(targetPID: pid_t,
                                                     sourcePID: pid_t?,
                                                     allWindows: Bool,
                                                     state: SwitcherAppActivationRetryState,
                                                     delays: [TimeInterval]) {
        guard !delays.isEmpty else {
            state.invalidate()
            return
        }
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard state.isActive else { return }
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
                activateApp(app, allWindows: allWindows)
                if index == delays.count - 1 {
                    state.invalidate()
                }
            }
        }
    }

    private static func shouldContinueFocusRetry(windowID: CGWindowID,
                                                 targetPID: pid_t,
                                                 targetWindowOwnerPID: pid_t,
                                                 sourcePID: pid_t?) -> Bool {
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostPID = reportedFrontmostPID == targetWindowOwnerPID
            ? targetPID
            : reportedFrontmostPID
        return SwitcherSupport.shouldContinueFocusRetry(
            targetPID: targetPID,
            sourcePID: sourcePID,
            frontmostPID: frontmostPID,
            targetIsMinimized: windowIsMinimized(windowID: windowID, pid: targetWindowOwnerPID)
        )
    }

    private static func watchTargetMinimizeIfNeeded(windowID: CGWindowID,
                                                    targetPID: pid_t,
                                                    targetWindowOwnerPID: pid_t,
                                                    sourcePID: pid_t?,
                                                    sourceWindowID: CGWindowID?,
                                                    sourceWindowOwnerPID: pid_t?,
                                                    activationPlan: SwitcherActivationPlan) {
        guard activationPlan.restoreSourceWhenTargetMinimizes,
              let sourcePID,
              SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: targetPID,
                                                                     sourcePID: sourcePID,
                                                                     frontmostPID: targetPID,
                                                                     targetIsMinimized: true)
        else { return }

        pendingMinimizeRestore = SwitcherWindowMinimizeRestore(windowID: windowID,
                                                               targetPID: targetPID,
                                                               targetWindowOwnerPID: targetWindowOwnerPID,
                                                               sourcePID: sourcePID,
                                                               sourceWindowID: sourceWindowID,
                                                               sourceWindowOwnerPID: sourceWindowOwnerPID)
    }

    fileprivate static func cancelPendingMinimizeRestore() {
        pendingMinimizeRestore?.invalidate()
        pendingMinimizeRestore = nil
    }

    fileprivate static func cancelPendingMinimizeRestore(_ restore: SwitcherWindowMinimizeRestore) {
        guard pendingMinimizeRestore === restore else { return }
        cancelPendingMinimizeRestore()
    }

    fileprivate static func restoreSourceAfterTargetMinimize(_ restore: SwitcherWindowMinimizeRestore) {
        guard pendingMinimizeRestore === restore else { return }
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostPID = reportedFrontmostPID == restore.targetWindowOwnerPID
            ? restore.targetPID
            : reportedFrontmostPID
        guard SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: restore.targetPID,
                                                                     sourcePID: restore.sourcePID,
                                                                     frontmostPID: frontmostPID,
                                                                     targetIsMinimized: true,
                                                                     frontmostMatchesTargetBundle: restore.matchesTargetBundle(frontmostPID),
                                                                     frontmostCanBeSystemPromotion: restore.minimizeIntentObserved),
              activateSource(pid: restore.sourcePID,
                             windowID: restore.sourceWindowID,
                             windowOwnerPID: restore.sourceWindowOwnerPID) else {
            cancelPendingMinimizeRestore()
            return
        }

        cancelPendingMinimizeRestore()
    }

    fileprivate static func restoreSourceAfterTargetMinimizeIntent(_ restore: SwitcherWindowMinimizeRestore,
                                                                   keepPending: Bool = false,
                                                                   allowSystemPromotion: Bool = false) {
        guard pendingMinimizeRestore === restore else { return }
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostPID = reportedFrontmostPID == restore.targetWindowOwnerPID
            ? restore.targetPID
            : reportedFrontmostPID
        let targetIsMinimized = windowIsMinimized(windowID: restore.windowID,
                                                  pid: restore.targetWindowOwnerPID)
        let focusedID = focusedWindowID(for: restore.targetWindowOwnerPID)
        guard SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: restore.targetPID,
                                                                           sourcePID: restore.sourcePID,
                                                                           frontmostPID: frontmostPID,
                                                                           focusedWindowID: focusedID,
                                                                           targetWindowID: restore.windowID,
                                                                           targetIsMinimized: targetIsMinimized,
                                                                           frontmostMatchesTargetBundle: restore.matchesTargetBundle(frontmostPID),
                                                                           frontmostCanBeSystemPromotion: allowSystemPromotion) else { return }
        guard activateSource(pid: restore.sourcePID,
                             windowID: restore.sourceWindowID,
                             windowOwnerPID: restore.sourceWindowOwnerPID) else {
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
                                       windowOwnerPID: pid_t?) -> Bool {
        guard let sourceApp = NSRunningApplication(processIdentifier: pid),
              !sourceApp.isTerminated else { return false }

        sourceApp.unhide()
        if let windowID {
            prepareWindowForActivation(windowID: windowID, pid: windowOwnerPID ?? pid)
        }
        NSApp.yieldActivation(to: sourceApp)
        if !sourceApp.activate(from: NSRunningApplication.current, options: []) {
            sourceApp.activate(options: [])
        }
        if let windowID {
            focusWindow(windowID: windowID, pid: windowOwnerPID ?? pid)
        }
        return true
    }

    @discardableResult
    private static func prepareWindowForActivation(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return false }

        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return true
    }

    @discardableResult
    private static func stageSourceBehindTargetIfNeeded(targetWindowID: CGWindowID,
                                                        targetPID: pid_t,
                                                        targetWindowOwnerPID: pid_t,
                                                        sourcePID: pid_t?,
                                                        sourceWindowID: CGWindowID?,
                                                        sourceWindowOwnerPID: pid_t?,
                                                        activationPlan: SwitcherActivationPlan) -> Bool {
        guard activationPlan.restoreSourceWhenTargetMinimizes,
              SwitcherSupport.shouldStageSourceBehindTarget(targetPID: targetPID,
                                                            sourcePID: sourcePID,
                                                            sourceWindowID: sourceWindowID),
              let sourcePID,
              let sourceWindowID,
              Permissions.shared.accessibility else { return false }

        let sourceApp = AXUIElementCreateApplication(sourceWindowOwnerPID ?? sourcePID)
        let targetApp = AXUIElementCreateApplication(targetWindowOwnerPID)
        AXUIElementSetMessagingTimeout(sourceApp, 0.35)
        AXUIElementSetMessagingTimeout(targetApp, 0.35)
        guard let sourceWindow = axElement(windowID: sourceWindowID, in: sourceApp),
              let targetWindow = axElement(windowID: targetWindowID, in: targetApp) else { return false }

        var sourceMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(sourceWindow, kAXMinimizedAttribute as CFString, &sourceMinimized) == .success,
           (sourceMinimized as? Bool) == true {
            return false
        }

        AXUIElementPerformAction(sourceWindow, kAXRaiseAction as CFString)
        AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(targetApp, kAXMainWindowAttribute as CFString, targetWindow)
        AXUIElementSetAttributeValue(targetApp, kAXFocusedWindowAttribute as CFString, targetWindow)
        AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return true
    }

    @discardableResult
    private static func focusWindow(windowID: CGWindowID, pid: pid_t, makeAppFrontmost: Bool = true) -> Bool {
        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return false }

        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        if makeAppFrontmost {
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, axWindow)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return true
    }

    private static func axElement(windowID: CGWindowID, in axApp: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement]
        else { return nil }

        for axWindow in axWindows {
            if AXWindowResolver.windowID(for: axWindow) == windowID {
                return axWindow
            }
        }
        return nil
    }

    fileprivate static func axElementForMinimizeRestore(windowID: CGWindowID, in axApp: AXUIElement) -> AXUIElement? {
        axElement(windowID: windowID, in: axApp)
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
        var minimized: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) == .success,
              let minimized
        else { return nil }
        if CFGetTypeID(minimized) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((minimized as! CFBoolean))
        }
        return minimized as? Bool
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
    private var observedWindow: AXUIElement?
    private var observedTargetApp: AXUIElement?
    private var observedMinimizeButton: AXUIElement?
    private var workspaceObserver: Any?
    fileprivate var minimizeIntentObserved = false
    private var minimizeCompletionRestoreScheduled = false
    private let targetBundleIdentifier: String?
    private let sourceBundleIdentifier: String?

    init?(windowID: CGWindowID,
          targetPID: pid_t,
          targetWindowOwnerPID: pid_t,
          sourcePID: pid_t,
          sourceWindowID: CGWindowID?,
          sourceWindowOwnerPID: pid_t?) {
        guard Permissions.shared.accessibility else { return nil }

        let axApp = AXUIElementCreateApplication(targetWindowOwnerPID)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = WindowActivator.axElementForMinimizeRestore(windowID: windowID, in: axApp) else {
            return nil
        }

        var observerRef: AXObserver?
        guard AXObserverCreate(targetWindowOwnerPID,
                               switcherWindowMinimizeRestoreCallback,
                               &observerRef) == .success,
              let observer = observerRef else { return nil }

        self.windowID = windowID
        self.targetPID = targetPID
        self.targetWindowOwnerPID = targetWindowOwnerPID
        self.sourcePID = sourcePID
        self.sourceWindowID = sourceWindowID
        self.sourceWindowOwnerPID = sourceWindowOwnerPID
        self.observer = observer
        self.observedWindow = axWindow
        self.targetBundleIdentifier = NSRunningApplication(processIdentifier: targetPID)?.bundleIdentifier
        self.sourceBundleIdentifier = NSRunningApplication(processIdentifier: sourcePID)?.bundleIdentifier

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer,
                                        axWindow,
                                        kAXWindowMiniaturizedNotification as CFString,
                                        refcon) == .success else {
            self.observer = nil
            self.observedWindow = nil
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        if AXObserverAddNotification(observer,
                                     axApp,
                                     kAXFocusedWindowChangedNotification as CFString,
                                     refcon) == .success {
            observedTargetApp = axApp
        }
        if AXObserverAddNotification(observer,
                                     axApp,
                                     kAXMainWindowChangedNotification as CFString,
                                     refcon) == .success {
            observedTargetApp = axApp
        }
        if let minimizeButton = WindowActivator.elementAttribute(axWindow, kAXMinimizeButtonAttribute as String),
           AXObserverAddNotification(observer,
                                     minimizeButton,
                                     switcherAXPressedNotification as CFString,
                                     refcon) == .success {
            observedMinimizeButton = minimizeButton
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
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil

        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let observedWindow {
                AXObserverRemoveNotification(observer,
                                             observedWindow,
                                             kAXWindowMiniaturizedNotification as CFString)
            }
            if let observedTargetApp {
                AXObserverRemoveNotification(observer,
                                             observedTargetApp,
                                             kAXFocusedWindowChangedNotification as CFString)
                AXObserverRemoveNotification(observer,
                                             observedTargetApp,
                                             kAXMainWindowChangedNotification as CFString)
            }
            if let observedMinimizeButton {
                AXObserverRemoveNotification(observer,
                                             observedMinimizeButton,
                                             switcherAXPressedNotification as CFString)
            }
        }
        observer = nil
        observedWindow = nil
        observedTargetApp = nil
        observedMinimizeButton = nil
    }

    func handle(notification: String) {
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
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
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

    deinit {
        invalidate()
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
