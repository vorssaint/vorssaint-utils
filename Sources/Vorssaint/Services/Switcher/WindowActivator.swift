// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Brings a switcher selection to the front: unminimizes if needed, makes the
/// exact window the app's focused/main Accessibility window and activates the
/// owning app. The focus pass is repeated after activation because Space changes
/// are asynchronous and some apps settle their main window one run-loop later.
enum WindowActivator {
    private static let focusRetryDelay: TimeInterval = 0.12
    private static let fullscreenFocusRetryDelays: [TimeInterval] = [0.18, 0.38, 0.68]

    static func activate(_ item: SwitcherItem,
                         retry: Bool = true,
                         sourceWasFullscreen: Bool = false,
                         sourcePID: pid_t? = nil) {
        if item.pid == ProcessInfo.processInfo.processIdentifier {
            activateOwnWindow(item)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }

        app.unhide()
        guard let windowID = item.windowID else {
            activateApp(app)
            return
        }
        let activateAllWindows = !item.isMinimized && !item.isFullscreen
        if sourceWasFullscreen || item.isFullscreen {
            activateApp(app, allWindows: activateAllWindows)
            guard retry else {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.fullscreenFocusRetryDelays[0]) {
                    guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else { return }
                    activateApp(app, allWindows: activateAllWindows)
                    focusWindow(windowID: windowID, pid: item.pid)
                }
                return
            }
            scheduleFocusRetries(windowID: windowID,
                                  pid: item.pid,
                                  sourcePID: sourcePID,
                                  activateAllWindows: activateAllWindows,
                                  delays: Self.fullscreenFocusRetryDelays)
            return
        }

        activateApp(app, allWindows: activateAllWindows)
        focusWindow(windowID: windowID, pid: item.pid)

        guard retry else { return }
        scheduleFocusRetries(windowID: windowID,
                              pid: item.pid,
                              sourcePID: sourcePID,
                              activateAllWindows: activateAllWindows,
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
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindowResolver.windowID(for: value as! AXUIElement)
    }

    static func windowIsMinimized(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return false }
        var minimized: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) == .success
        else { return false }
        return (minimized as? Bool) == true
    }

    static func setWindowMinimized(_ minimized: Bool, windowID: CGWindowID, pid: pid_t) {
        guard Permissions.shared.accessibility else { return }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return }
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString,
                                     minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func closeWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return false }
            window.close()
            return true
        }

        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axWindow = axElement(windowID: windowID, in: axApp),
              let closeButton = elementAttribute(axWindow, kAXCloseButtonAttribute as String),
              boolAttribute(closeButton, kAXEnabledAttribute as String, default: true)
        else { return false }

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
                                             pid: pid_t,
                                             sourcePID: pid_t?,
                                             activateAllWindows: Bool,
                                             delays: [TimeInterval]) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard shouldContinueFocusRetry(targetPID: pid, sourcePID: sourcePID),
                      let app = NSRunningApplication(processIdentifier: pid),
                      !app.isTerminated else { return }
                activateApp(app, allWindows: activateAllWindows)
                focusWindow(windowID: windowID, pid: pid)
            }
        }
    }

    private static func shouldContinueFocusRetry(targetPID: pid_t, sourcePID: pid_t?) -> Bool {
        guard let sourcePID,
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return true }
        return frontmostPID == targetPID
            || frontmostPID == sourcePID
            || frontmostPID == ProcessInfo.processInfo.processIdentifier
    }

    @discardableResult
    private static func focusWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.shared.accessibility else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axWindow = axElement(windowID: windowID, in: axApp) else { return false }

        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
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

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String, default defaultValue: Bool) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return defaultValue }
        return (value as? Bool) ?? defaultValue
    }
}
