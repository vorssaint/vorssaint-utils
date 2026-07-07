// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Taskbar-style Dock clicks: clicking the Dock icon of the app that is
/// already frontmost minimizes its windows, like traditional taskbars; the
/// Dock's native behavior (activate, restore, modifier shortcuts) is left
/// untouched for every other click. Requires Accessibility.
final class DockClickService {
    static let shared = DockClickService()

    private struct ActionRecord {
        let kind: DockClickAction
        let time: CFAbsoluteTime
        /// The windows the action targeted, so a follow-up toggle can undo
        /// exactly them even while the AX state is still settling.
        let targets: [AXUIElement]
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dockPIDCache: pid_t?
    /// Last handled click per app: follow-up clicks toggle from this record
    /// instead of re-deriving from ambiguous mid-animation AX state. The tap
    /// runs on the main run loop, so both dictionaries are main-thread-only.
    private var lastAction: [pid_t: ActionRecord] = [:]
    private var pendingSweeps: [pid_t: DispatchWorkItem] = [:]

    private init() {}

    func syncWithPreferences() {
        let minimizeEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickMinimize)
        let cycleEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickCycleWindows)
        if (minimizeEnabled || cycleEnabled), Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    private func start() {
        guard tap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<DockClickService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        for (_, sweep) in pendingSweeps { sweep.cancel() }
        pendingSweeps = [:]
        lastAction = [:]
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }

        // Modifier clicks keep the Dock's native shortcuts (⌘ reveal, ⌥ hide…).
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        else { return Unmanaged.passUnretained(event) }

        let point = event.location
        guard Self.insideDockStrip(point) else {
            return Unmanaged.passUnretained(event)
        }

        // A Dock Preview panel can dip into the Dock's edge band; those clicks
        // belong to its cards, not to the icons underneath.
        guard !DockPreviewService.shared.panelCovers(axPoint: point) else {
            return Unmanaged.passUnretained(event)
        }

        // The edge band exists on every display and with auto-hide even while
        // the Dock is off screen, but the AX item frames below keep reporting
        // the parked layout and only match along the Dock's long axis — a
        // click near the edge of a Dock-less display whose long-axis
        // coordinate lines up with an icon would minimize or restore apps out
        // of thin air. Only clicks inside the Dock strip that is actually on
        // screen can mean an icon.
        guard let dockPID = dockProcessID(),
              let dockBounds = Self.revealedDockBounds(dockPID: dockPID),
              dockBounds.insetBy(dx: -8, dy: -8).contains(point) else {
            return Unmanaged.passUnretained(event)
        }

        // Accessibility gone (e.g. reset): the AX hit-test below would hang
        // inside the tap and freeze clicks, so let the click through untouched.
        guard AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }

        let hit = dockApplication(at: point)
        guard let app = hit, app.processIdentifier != getpid()
        else { return Unmanaged.passUnretained(event) }

        let pid = app.processIdentifier
        let now = CFAbsoluteTimeGetCurrent()
        lastAction = lastAction.filter { now - $0.value.time < DockClickSupport.toggleIntentWindow }
        let record = lastAction[pid]
        let decision = DockClickSupport.repeatDecision(lastAction: record?.kind,
                                                       elapsed: record.map { now - $0.time })
        if decision == .swallow { return nil }

        let windows = Self.standardWindows(pid: pid)
        guard !windows.hasFullscreen else { return Unmanaged.passUnretained(event) }

        let cycleEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickCycleWindows)
        let minimizeEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickMinimize)
        let action: DockClickAction
        if case .toggle(let toggled) = decision {
            action = toggled
        } else {
            action = DockClickSupport.action(appIsFrontmost: app.isActive,
                                             hasUnminimizedWindows: !windows.unminimized.isEmpty,
                                             hasMinimizedWindows: !windows.minimized.isEmpty,
                                             hasFullscreenWindows: false,
                                             hasModifiers: false,
                                             minimizeEnabled: minimizeEnabled,
                                             cycleWindowsEnabled: cycleEnabled,
                                             unminimizedWindowCount: windows.unminimized.count)
        }

        // Swallow handled clicks (or the Dock would fight us: re-activate on
        // minimize, open a brand-new window on restore) and apply the window
        // changes outside the tap callback. A swallowed click never reaches
        // Dock Preview's listen-only tap, so tell it directly — otherwise its
        // open panel keeps a pre-click idea of which windows are minimized.
        switch action {
        case .cycleWindows:
            lastAction[pid] = ActionRecord(kind: .cycleWindows, time: now, targets: [])
            let unminimized = windows.unminimized
            DispatchQueue.main.async {
                DockPreviewService.shared.dockClickWasHandled()
                Self.cycleWindows(pid: pid, windows: unminimized)
            }
            return nil
        case .minimize:
            let targets = windows.unminimized
            lastAction[pid] = ActionRecord(kind: .minimize, time: now, targets: targets)
            DispatchQueue.main.async {
                DockPreviewService.shared.dockClickWasHandled()
                Self.postMinimizeAll(pid: pid)
            }
            scheduleSweep(pid: pid, targets: targets, minimized: true,
                          delay: DockClickSupport.minimizeSweepDelay)
            return nil
        case .restore:
            // A toggle right after a minimize also re-opens the captured
            // windows whose AX state hasn't flipped yet; duplicates with the
            // live minimized list are harmless (the set is idempotent).
            var targets = windows.minimized
            if let record, record.kind == .minimize {
                targets += record.targets
            }
            lastAction[pid] = ActionRecord(kind: .restore, time: now, targets: targets)
            Self.setMinimized(false, windows: targets)
            scheduleSweep(pid: pid, targets: targets, minimized: false,
                          delay: DockClickSupport.restoreSweepDelay)
            DispatchQueue.main.async {
                DockPreviewService.shared.dockClickWasHandled()
                app.activate()
            }
            return nil
        case .passThrough:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Settling sweep

    /// Re-asserts the action once the animation settles: windows the batched
    /// Minimize All left behind (apps without the standard binding) get
    /// minimized individually, and a restore that clicked in while minimizes
    /// were still in flight re-opens the stragglers. Only the windows captured
    /// at click time are swept — re-querying at fire time would grab windows
    /// the user changed in the meantime — and each new action for the same app
    /// cancels the previous sweep, so exactly one direction wins.
    private func scheduleSweep(pid: pid_t, targets: [AXUIElement], minimized: Bool, delay: TimeInterval) {
        pendingSweeps[pid]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSweeps.removeValue(forKey: pid)
            let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
            DispatchQueue.global(qos: .userInteractive).async {
                for window in targets where Self.isMinimized(window) == !minimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
                }
            }
        }
        pendingSweeps[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func postMinimizeAll(pid: pid_t) {
        DispatchQueue.global(qos: .userInteractive).async {
            // Pressing the app's own Minimize All menu item beats synthesizing
            // ⌥⌘M: it targets the right app even if focus shifts, skips every
            // event tap in between, and is layout-independent (kVK_ANSI_M is a
            // physical key — on AZERTY it doesn't type an M at all).
            guard !pressMinimizeAllMenuItem(pid: pid) else { return }
            DispatchQueue.main.async {
                Self.postMinimizeAllShortcut()
            }
        }
    }

    /// Finds and presses the menu item bound to ⌥⌘M (Minimize All) by scanning
    /// the app's menu bar two levels deep — the item lives directly in the
    /// Window menu, so submenus are never entered. Matching by command
    /// character + modifiers instead of the localized title works in every
    /// language the target app ships.
    private static func pressMinimizeAllMenuItem(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let menuBar = elementAttribute(app, kAXMenuBarAttribute as String),
              let topLevel = elementArray(menuBar, kAXChildrenAttribute as String)
        else { return false }

        // The Window menu sits near the end of the menu bar.
        for barItem in topLevel.reversed() {
            guard let menus = elementArray(barItem, kAXChildrenAttribute as String) else { continue }
            for menu in menus {
                guard let items = elementArray(menu, kAXChildrenAttribute as String) else { continue }
                for item in items {
                    guard stringAttribute(item, "AXMenuItemCmdChar")?.uppercased() == "M",
                          intAttribute(item, "AXMenuItemCmdModifiers") == 2 // ⌥⌘
                    else { continue }
                    guard boolAttribute(item, kAXEnabledAttribute as String) != false else { return false }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    private static func postMinimizeAllShortcut() {
        // The modifier KEYS must be pressed and released explicitly, mirroring
        // real typing. Posting only the M events with ⌘⌥ flags latches those
        // modifiers into the session's flag state — every later click becomes
        // a ⌘⌥-click system-wide until the user physically presses them.
        let source = CGEventSource(stateID: .hidSystemState)
        let sequence: [(key: Int, down: Bool, flags: CGEventFlags)] = [
            (kVK_Command, true, [.maskCommand]),
            (kVK_Option, true, [.maskCommand, .maskAlternate]),
            (kVK_ANSI_M, true, [.maskCommand, .maskAlternate]),
            (kVK_ANSI_M, false, [.maskCommand, .maskAlternate]),
            (kVK_Option, false, [.maskCommand]),
            (kVK_Command, false, []),
        ]
        for step in sequence {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: CGKeyCode(step.key),
                                      keyDown: step.down) else { continue }
            event.flags = step.flags
            event.post(tap: .cghidEventTap)
        }
    }

    private static func setMinimized(_ minimized: Bool, windows: [AXUIElement]) {
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        for window in windows {
            DispatchQueue.global(qos: .userInteractive).async {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
            }
        }
    }

    /// Cycles through an app's unminimized windows by raising the rearmost one
    /// to the front, mimicking ⌘` (Command-Tilde) behavior.
    private static func cycleWindows(pid: pid_t, windows: [AXUIElement]) {
        guard windows.count > 1 else { return }

        // The AX windows array is typically front-to-back order.
        // Raise the last (rearmost) window to bring it to front.
        let app = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        let rearWindow: AXUIElement
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success,
           let focused = focusedValue {
            // Find the focused window in our list and pick the next one.
            let focusedElement = focused as! AXUIElement
            if let index = windows.firstIndex(where: { CFEqual($0, focusedElement) }) {
                let nextIndex = (index + 1) % windows.count
                rearWindow = windows[nextIndex]
            } else {
                rearWindow = windows.last!
            }
        } else {
            rearWindow = windows.last!
        }

        AXUIElementPerformAction(rearWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, rearWindow)
    }

    // MARK: - Geometry

    /// The on-screen bounds of the Dock strip, in the same top-left-origin
    /// global coordinates as event locations, or nil while it is off screen.
    /// The strip is the single layer-20 window the Dock owns; with auto-hide
    /// its on-screen state flips as it slides in and out, verified empirically
    /// on macOS 27. The bounds also pin the strip to the one display that has
    /// it, so edge clicks on other displays never reach the icon matching.
    private static func revealedDockBounds(dockPID: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dockPID,
                  (window[kCGWindowLayer as String] as? Int) == dockLevel,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 0, bounds.height > 0
            else { continue }
            return bounds
        }
        return nil
    }

    /// Cheap pre-filter before any AX call, in the event's top-left-origin
    /// global coordinates. With magnification the hovered icon can grow above
    /// the reserved strip; such clicks fall back to the Dock's native handling.
    private static func insideDockStrip(_ point: CGPoint) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        for screen in NSScreen.screens {
            let frame = axRect(screen.frame, primaryHeight: primaryHeight)
            let visible = axRect(screen.visibleFrame, primaryHeight: primaryHeight)
            if DockClickSupport.dockStripContains(point, screenFrame: frame, visibleFrame: visible) {
                return true
            }
        }
        return false
    }

    private static func axRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - Dock hit test

    /// Resolves which Dock app icon a click landed on by walking the Dock's
    /// item list and matching along the Dock's LONG axis only. Position-based
    /// AX hit-testing is useless here: macOS reports the Dock strip's AX
    /// frames shifted on the short axis (observed ~72 pt on macOS 27), while
    /// the long-axis coordinates stay truthful. The strip gate above already
    /// bounded the short axis.
    private func dockApplication(at point: CGPoint) -> NSRunningApplication? {
        guard let dockPID = dockProcessID() else { return nil }
        let dockElement = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockElement, 0.35)
        guard let children = Self.elementArray(dockElement, kAXChildrenAttribute as String) else { return nil }

        for child in children where Self.roleString(child) == "AXList" {
            guard let items = Self.elementArray(child, kAXChildrenAttribute as String),
                  let listFrame = Self.axFrame(child)
            else { continue }
            let horizontal = listFrame.width >= listFrame.height
            for item in items {
                guard let frame = Self.axFrame(item) else { continue }
                let hit = horizontal
                    ? (point.x >= frame.minX && point.x <= frame.maxX)
                    : (point.y >= frame.minY && point.y <= frame.maxY)
                guard hit, let url = Self.urlAttribute(item) else { continue }
                let standardized = url.standardizedFileURL.path
                return NSWorkspace.shared.runningApplications.first {
                    $0.activationPolicy == .regular && !$0.isTerminated
                        && $0.bundleURL?.standardizedFileURL.path == standardized
                }
            }
        }
        return nil
    }

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else { return nil }
        return array
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func roleString(_ element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute as String)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((positionValue as! AXValue), .cgPoint, &position),
              AXValueGetValue((sizeValue as! AXValue), .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: position, size: size)
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

    private static func urlAttribute(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFURLGetTypeID()
        else { return nil }
        return (value as! CFURL) as URL
    }

    // MARK: - Windows

    private static func isMinimized(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    /// The app's standard windows split by minimized state, plus whether any
    /// window is fullscreen (those can't minimize and must veto the action).
    private static func standardWindows(pid: pid_t)
        -> (unminimized: [AXUIElement], minimized: [AXUIElement], hasFullscreen: Bool) {
        let appElement = AXUIElementCreateApplication(pid)
        // This runs inside the tap callback against the app the user just
        // clicked — often one that is busy or hung. Without an explicit
        // timeout every call here would wait out the multi-second AX default
        // and stall click delivery system-wide.
        AXUIElementSetMessagingTimeout(appElement, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return ([], [], false) }
        var unminimized: [AXUIElement] = []
        var minimized: [AXUIElement] = []
        var hasFullscreen = false
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.35)
            // Role must be a real window: Finder also lists the desktop here
            // (an AXScrollArea) and it would otherwise count as a window.
            guard Self.roleString(window) == (kAXWindowRole as String) else { continue }
            guard let isWindowMinimized = isMinimized(window) else { continue }
            if isWindowMinimized {
                // No subrole check: macOS flips a minimized window's subrole
                // from AXStandardWindow to AXDialog.
                minimized.append(window)
                continue
            }
            if boolAttribute(window, "AXFullScreen") == true {
                hasFullscreen = true
                continue
            }
            if let subroleString = stringAttribute(window, kAXSubroleAttribute as String),
               subroleString != "AXStandardWindow" {
                continue
            }
            unminimized.append(window)
        }
        return (unminimized, minimized, hasFullscreen)
    }
}
