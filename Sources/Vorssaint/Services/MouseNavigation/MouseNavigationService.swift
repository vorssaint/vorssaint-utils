// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// Turns the standard Back and Forward side buttons into the matching app
/// commands. Finder and browsers expose those commands as Command-[ and
/// Command-]; other apps keep working when they provide the same menu command.
/// Nothing is installed while the opt-in feature is off. Requires
/// Accessibility for the modifying event tap and menu action.
final class MouseNavigationService: ObservableObject {
    static let shared = MouseNavigationService()

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
            isRunning = false
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged,
              let direction = MouseNavigationSupport.direction(
                forButtonNumber: event.getIntegerValueField(.mouseEventButtonNumber)) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            // Leave the event-tap callback immediately; AX menu traversal can
            // take a few milliseconds and must never let the tap time out.
            DispatchQueue.main.async { [weak self] in
                self?.perform(direction)
            }
        }
        // Swallow the full side-button gesture. Letting its Up or Drag through
        // after replacing the Down leaves apps with an unmatched mouse event.
        return nil
    }

    private enum MenuPressOutcome {
        case pressed
        case pressFailed
        case noNavigationCommand
    }

    private func perform(_ direction: MouseNavigationDirection) {
        let character = MouseNavigationSupport.commandCharacter(for: direction)
        switch pressMenuItem(commandCharacter: character) {
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
    /// behavior and remains keyboard-layout independent. The synthetic
    /// shortcut below is only a fallback when the found item refuses AXPress.
    private func pressMenuItem(commandCharacter: String) -> MenuPressOutcome {
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
                                      commandCharacter: commandCharacter,
                                      depth: 0,
                                      visited: &visited) else { return .noNavigationCommand }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            ? .pressed : .pressFailed
    }

    private func findMenuItem(in element: AXUIElement,
                              commandCharacter: String,
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
        // AX modifier value zero means Command with no additional modifiers.
        if command == commandCharacter,
           modifiers?.uint32Value == 0,
           enabled?.boolValue != false {
            return element
        }

        // Items at the depth cap cannot host a match below them; skipping
        // the children copy saves one AX round trip per menu item.
        guard depth < 3 else { return nil }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
        for child in children {
            if let match = findMenuItem(in: child,
                                        commandCharacter: commandCharacter,
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
        let keyCode = direction == .back ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(keyCode),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(keyCode),
                               keyDown: false) else { return }
        // No keyboardSetUnicodeString: a forced character string on a
        // shortcut event breaks menu key equivalent dispatch in the target
        // app, so the command would arrive and still do nothing. The virtual
        // key plus the Command flag are all a shortcut needs.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
