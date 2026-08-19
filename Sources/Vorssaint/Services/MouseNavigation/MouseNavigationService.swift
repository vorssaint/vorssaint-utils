// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import UniformTypeIdentifiers

/// Turns the standard Back and Forward side buttons into the matching app
/// commands. File managers and browsers expose those commands as Command-[ and
/// Command-], or wherever the current keyboard puts them (see
/// `MouseNavigationKeys`); other apps keep working when they provide the same
/// menu command.
/// Apps that handle the side buttons themselves (some browsers, virtual
/// machines, remote screens) receive the untouched events instead. Nothing is installed
/// while the opt-in feature is off. Requires Accessibility for the modifying
/// event tap and menu action.
final class MouseNavigationService: ObservableObject {
    static let shared = MouseNavigationService()

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Buttons whose current press started over a pass-through app. The Up
    /// and Drag of a gesture must follow its Down: splitting the pair would
    /// leave the target app with an unmatched mouse event. Only touched from
    /// the tap callback, which runs on the main run loop.
    private var passThroughButtons: Set<Int64> = []
    /// Alive only while the tap is, like every other resource here.
    private var keyboardObserver: NSObjectProtocol?
    /// Registered web handlers that should keep their native side-button events.
    /// Resolved outside the tap callback so its hot path only reads memory.
    private var webURLHandlers: Set<String> = []
    private var webHandlerObservers: [NSObjectProtocol] = []
    private var webHandlerRefreshWork: DispatchWorkItem?
    private var webHandlerRefreshGeneration = 0

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.mouseNavigation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.mouseNavigationEnabled)
        if wanted, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    private func start() {
        guard tap == nil else {
            isRunning = true
            return
        }
        webURLHandlers = Self.registeredWebURLHandlers()
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MouseNavigationService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            webURLHandlers.removeAll()
            isRunning = false
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        observeWebHandlerChanges()
        // Which keys carry Back and Forward depends on the keyboard in use, so
        // the answer is asked for now and again on every keyboard change.
        MouseNavigationKeys.refresh()
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in MouseNavigationKeys.refresh() }
        isRunning = true
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let keyboardObserver {
            DistributedNotificationCenter.default().removeObserver(keyboardObserver)
        }
        keyboardObserver = nil
        webHandlerRefreshGeneration += 1
        webHandlerRefreshWork?.cancel()
        webHandlerRefreshWork = nil
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in webHandlerObservers { workspaceCenter.removeObserver(observer) }
        webHandlerObservers.removeAll()
        MouseNavigationKeys.reset()
        webURLHandlers.removeAll()
        tap = nil
        runLoopSource = nil
        passThroughButtons.removeAll()
        isRunning = false
    }

    private func observeWebHandlerChanges() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
        ]
        webHandlerObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication)?.processIdentifier
                guard MouseNavigationSupport.shouldRefreshWebHandlers(
                    isApplicationActivation: notification.name
                        == NSWorkspace.didActivateApplicationNotification,
                    activatedPID: activatedPID,
                    ownPID: ProcessInfo.processInfo.processIdentifier
                ) else { return }
                self?.scheduleWebHandlerRefresh()
            }
        }
    }

    private func scheduleWebHandlerRefresh() {
        webHandlerRefreshGeneration += 1
        let generation = webHandlerRefreshGeneration
        webHandlerRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.tap != nil,
                  self.webHandlerRefreshGeneration == generation else { return }
            self.webHandlerRefreshWork = nil
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let handlers = MouseNavigationService.registeredWebURLHandlers()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.tap != nil,
                          self.webHandlerRefreshGeneration == generation else { return }
                    self.webURLHandlers = handlers
                }
            }
        }
        webHandlerRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged,
              let direction = MouseNavigationSupport.direction(forButtonNumber: buttonNumber) else {
            return Unmanaged.passUnretained(event)
        }

        // A side button claimed as the radial menu's summoner, or carrying a
        // mouse button shortcut, belongs to that feature. This tap runs at
        // the HID level, before those session taps, so the whole gesture
        // passes through untouched for the owner to take downstream; the
        // other side button keeps navigating. While the shortcut capture row
        // is listening, every press belongs to it, including a button with no
        // mapping yet, or the capture could never see the button it is asked
        // to watch for.
        if RadialMenuSupport.claimsMouseButton(buttonNumber)
            || MouseButtonShortcutSupport.claimsButton(buttonNumber)
            || MouseButtonShortcutService.isCaptureActive {
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            // Apps that consume the side buttons themselves keep the raw
            // event; replacing it would drop navigation the user already had,
            // and none of them has a menu command the AX path could press.
            // The same goes for an app the user put on the exception list.
            // Checked only on Down (never per Drag), and both answers come
            // from cached state, so the tap callback stays cheap.
            if MouseNavigationSupport.shouldPassThrough(
                bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                webURLHandlers: webURLHandlers)
                || MouseAppExceptions.shared.excludesActionTarget(.navigation, at: event.location) {
                passThroughButtons.insert(buttonNumber)
                return Unmanaged.passUnretained(event)
            }
            passThroughButtons.remove(buttonNumber)
            // Leave the event-tap callback immediately; AX menu traversal can
            // take a few milliseconds and must never let the tap time out.
            DispatchQueue.main.async { [weak self] in
                self?.perform(direction)
            }
            return nil
        }

        if passThroughButtons.contains(buttonNumber) {
            if type == .otherMouseUp { passThroughButtons.remove(buttonNumber) }
            return Unmanaged.passUnretained(event)
        }
        // Swallow the full side-button gesture. Letting its Up or Drag through
        // after replacing the Down leaves apps with an unmatched mouse event.
        return nil
    }

    private static func registeredWebURLHandlers() -> Set<String> {
        guard let url = URL(string: "https://example.invalid") else { return [] }
        let urlHandlers = Set(NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap {
            Bundle(url: $0)?.bundleIdentifier
        })
        let documentHandlers = Set(NSWorkspace.shared.urlsForApplications(toOpen: UTType.html).compactMap {
            Bundle(url: $0)?.bundleIdentifier
        })
        return MouseNavigationSupport.nativeWebHandlers(
            urlHandlers: urlHandlers, documentHandlers: documentHandlers)
    }

    private enum MenuPressOutcome {
        case pressed
        case pressFailed
        case noNavigationCommand
    }

    private func perform(_ direction: MouseNavigationDirection) {
        switch pressMenuItem(shortcut: MouseNavigationKeys.shortcut(for: direction)) {
        case .pressed:
            return
        case .pressFailed:
            postCommand(direction)
        case .noNavigationCommand:
            // No verified Back or Forward in this app. Posting the shortcut
            // blindly is not an option: the same keys deeper in other menus
            // are editing commands (shift code left, rearrange layers) and a
            // stray side click must never touch the document.
            return
        }
    }

    /// Prefer the app's actual enabled menu item. This preserves app-specific
    /// behavior, and the shortcut looked for is the one this keyboard carries.
    /// The synthetic shortcut below is only a fallback when the found item
    /// refuses AXPress.
    private func pressMenuItem(shortcut: MouseNavigationKeys.Shortcut) -> MenuPressOutcome {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .noNavigationCommand }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // A busy target must not hold Vorssaint's main thread for AX's
        // multi-second default timeout. Child menu elements get the same
        // bound as they are traversed below.
        AXUIElementSetMessagingTimeout(application, 0.35)
        guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, from: application) else {
            return .noNavigationCommand
        }
        var visited = 0
        guard let item = findMenuItem(in: menuBar,
                                      shortcut: shortcut,
                                      depth: 0,
                                      visited: &visited) else { return .noNavigationCommand }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            ? .pressed : .pressFailed
    }

    private func findMenuItem(in element: AXUIElement,
                              shortcut: MouseNavigationKeys.Shortcut,
                              depth: Int,
                              visited: inout Int) -> AXUIElement? {
        // Depth 3 is a direct item of a top level menu (bar, bar item, menu,
        // item). Back and Forward always live there (Go, History); the same
        // key equivalents inside submenus belong to editing commands and are
        // deliberately out of reach. This also keeps the traversal short.
        guard depth <= 3, visited < 600 else { return nil }
        visited += 1
        AXUIElementSetMessagingTimeout(element, 0.35)

        let command: String? = attribute(kAXMenuItemCmdCharAttribute, from: element)
        let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, from: element)
        let enabled: NSNumber? = attribute(kAXEnabledAttribute, from: element)
        if MouseNavigationSupport.matchesCommand(menuCharacter: command,
                                                 menuModifiers: modifiers?.uint32Value,
                                                 character: shortcut.character,
                                                 modifiers: shortcut.menuModifiers),
           enabled?.boolValue != false {
            return element
        }

        // Items at the depth cap cannot host a match below them; skipping
        // the children copy saves one AX round trip per menu item.
        guard depth < 3 else { return nil }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
        for child in children {
            if let match = findMenuItem(in: child,
                                        shortcut: shortcut,
                                        depth: depth + 1,
                                        visited: &visited) {
                return match
            }
        }
        return nil
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func postCommand(_ direction: MouseNavigationDirection) {
        // The key that carries the command is the one this keyboard would use,
        // which is not the bracket key on keyboards that cannot type brackets
        // without Option.
        guard let stroke = MouseNavigationKeys.keyStroke(
            for: MouseNavigationKeys.shortcut(for: direction).character) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: stroke.keyCode,
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: stroke.keyCode,
                               keyDown: false) else { return }
        // No keyboardSetUnicodeString: a forced character string on a
        // shortcut event breaks menu key equivalent dispatch in the target
        // app, so the command would arrive and still do nothing. The virtual
        // key plus the modifier flags are all a shortcut needs.
        let flags: CGEventFlags = stroke.needsShift ? [.maskCommand, .maskShift] : .maskCommand
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
