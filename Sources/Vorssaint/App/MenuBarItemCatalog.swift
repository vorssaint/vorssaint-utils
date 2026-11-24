// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

struct OrganizerMenuBarItem: Identifiable {
    let descriptor: MenuBarItemDescriptor
    let application: NSRunningApplication
    let element: AXUIElement
    var id: String { descriptor.id }
    var bundleID: String { descriptor.bundleID }
    var name: String { application.localizedName ?? descriptor.title }
}

final class MenuBarItemPressToken {
    private let lock = NSLock()
    private var cancelled = false
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Enumerates status items, never the application's ordinary menu titles.
/// Slow or unresponsive owners are read off the main thread with bounded waits.
final class MenuBarItemCatalog {
    private let queue = DispatchQueue(label: "com.vorssaint.menu-bar-catalog", qos: .utility)
    private let interactionQueue = DispatchQueue(label: "com.vorssaint.menu-bar-press", qos: .userInitiated)

    func scanClockFrames(completion: @escaping ([CGRect]) -> Void) {
        let agents = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.bundleIdentifier == "com.apple.controlcenter"
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        queue.async {
            var frames: [CGRect] = []
            if AXIsProcessTrusted() {
                for agent in agents {
                    let root = AXUIElementCreateApplication(agent.processIdentifier)
                    AXUIElementSetMessagingTimeout(root, 0.15)
                    var remaining = 256
                    func visit(_ element: AXUIElement, depth: Int) {
                        guard depth < 6, remaining > 0 else { return }
                        remaining -= 1
                        if Self.string(kAXIdentifierAttribute, from: element) == "com.apple.menuextra.clock",
                           let frame = Self.frame(of: element), frame.width > 0, frame.height > 0 {
                            frames.append(MenuBarItemSupport.cocoaFrame(accessibilityFrame: frame, primaryTop: top))
                            return
                        }
                        for child in Self.elements(kAXChildrenAttribute, from: element) {
                            visit(child, depth: depth + 1)
                        }
                    }
                    if let extras = Self.element(kAXExtrasMenuBarAttribute, from: root) { visit(extras, depth: 0) }
                    for window in Self.elements(kAXWindowsAttribute, from: root) { visit(window, depth: 0) }
                }
            }
            DispatchQueue.main.async { completion(frames) }
        }
    }

    func scan(application: NSRunningApplication? = nil,
              completion: @escaping ([OrganizerMenuBarItem], Bool) -> Void) {
        let running = NSWorkspace.shared.runningApplications
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let displays = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: top - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        let scanQueue = application == nil ? queue : interactionQueue
        scanQueue.async {
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion([], false) }
                return
            }
            var owners = (application.map { [$0] } ?? running)
                .map { AXUIElementCreateApplication($0.processIdentifier) }
            // On macOS 27, MenuBarAgent hosts remote application elements,
            // including helpers omitted by Workspace's application list.
            if let agent = running.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) {
                let root = AXUIElementCreateApplication(agent.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.15)
                var hostedOwners: [AXUIElement] = []
                func visit(_ element: AXUIElement, depth: Int) {
                    guard depth < 5 else { return }
                    if Self.string(kAXRoleAttribute, from: element) == kAXApplicationRole as String, depth > 0 {
                        hostedOwners.append(element)
                        return
                    }
                    for child in Self.elements(kAXChildrenAttribute, from: element) { visit(child, depth: depth + 1) }
                }
                for window in Self.elements(kAXWindowsAttribute, from: root) { visit(window, depth: 0) }
                // Prefer the live hosted surface over an owner's stale copy
                // of the same AX item after native visibility changes.
                owners.insert(contentsOf: hostedOwners, at: 0)
            }
            var items: [OrganizerMenuBarItem] = []
            var seen = Set<String>()
            for owner in owners {
                AXUIElementSetMessagingTimeout(owner, 0.15)
                var pid: pid_t = 0
                guard AXUIElementGetPid(owner, &pid) == .success,
                      let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                      application == nil || application?.processIdentifier == pid,
                      let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                      !bundle.hasPrefix("com.apple."),
                      let extras = Self.element(kAXExtrasMenuBarAttribute, from: owner) else { continue }
                let children = Self.elements(kAXChildrenAttribute, from: extras)
                for (index, child) in children.enumerated() {
                    guard Self.string(kAXRoleAttribute, from: child) == kAXMenuBarItemRole as String,
                          let frame = Self.frame(of: child), frame.width > 0, frame.height > 0,
                          displays.contains(where: { $0.intersects(frame) }) else { continue }
                    let identifier = Self.string(kAXIdentifierAttribute, from: child)
                    let id = "\(bundle)/\(pid)/\(identifier.isEmpty ? String(index) : identifier)"
                    guard seen.insert(id).inserted else { continue }
                    let title = [Self.string(kAXTitleAttribute, from: child),
                                 Self.string(kAXDescriptionAttribute, from: child), app.localizedName ?? bundle]
                        .first { !$0.isEmpty } ?? bundle
                    items.append(OrganizerMenuBarItem(descriptor: .init(id: id, bundleID: bundle, pid: pid,
                        title: title, frame: frame), application: app, element: child))
                }
            }
            DispatchQueue.main.async { completion(items, true) }
        }
    }

    /// Resolve a fresh item after lifting native visibility. Cached AX objects
    /// can belong to a destroyed MenuBarAgent surface and must not receive clicks.
    func press(_ item: OrganizerMenuBarItem, token: MenuBarItemPressToken,
               completion: @escaping (OrganizerMenuBarItem?) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        let agentPID = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.MenuBarAgent"
        }?.processIdentifier
        func retry() {
            guard token.isValid else { return }
            if !item.application.isTerminated, ProcessInfo.processInfo.systemUptime < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: attempt)
            } else { completion(nil) }
        }
        func attempt() {
            guard token.isValid else { return }
            guard !item.application.isTerminated else { completion(nil); return }
            scan(application: item.application) { current, _ in
                guard token.isValid else { return }
                guard let index = MenuBarItemSupport.activationIndex(for: item.descriptor,
                                                                     in: current.map(\.descriptor)) else {
                    retry()
                    return
                }
                let fresh = current[index]
                self.interactionQueue.async {
                    guard token.isValid else { return }
                    AXUIElementSetMessagingTimeout(fresh.element, 1)
                    var actions: CFArray?
                    AXUIElementCopyActionNames(fresh.element, &actions)
                    let names = actions as? [String] ?? []
                    let supported = [kAXPressAction as String, kAXShowMenuAction as String]
                        .filter { names.contains($0) }
                    guard token.isValid else { return }
                    var succeeded = false
                    for action in supported {
                        guard token.isValid else { return }
                        let result = AXUIElementPerformAction(fresh.element, action as CFString)
                        let selected = Self.value(kAXSelectedAttribute, from: fresh.element) as? Bool ?? false
                        if result == .success || selected { succeeded = true; break }
                    }
                    if !succeeded {
                        succeeded = Self.clickStatusItem(fresh, agentPID: agentPID, token: token)
                    }
                    DispatchQueue.main.async {
                        guard token.isValid else { return }
                        if succeeded { completion(fresh) }
                        else { retry() }
                    }
                }
            }
        }
        attempt()
    }

    /// Some third-party controls implement neither AXPress nor AXShowMenu.
    /// Click only a current, hit-tested status item using Accessibility; no
    /// screen pixels or saved coordinates are used.
    private static func clickStatusItem(_ item: OrganizerMenuBarItem, agentPID: pid_t?,
                                        token: MenuBarItemPressToken) -> Bool {
        guard token.isValid, AXIsProcessTrusted(),
              string(kAXRoleAttribute, from: item.element) == kAXMenuBarItemRole as String,
              let frame = frame(of: item.element) else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit, let hitFrame = Self.frame(of: hit) else { return false }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success,
              MenuBarItemSupport.activationHitMatches(frame: frame, itemPID: item.descriptor.pid,
                  hitFrame: hitFrame, hitPID: hitPID, menuBarAgentPID: agentPID),
              Self.frame(of: item.element) == frame, token.isValid,
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return false }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.eventSourceUserData, value: 0x564F5253)
        }
        guard token.isValid else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// MenuBarAgent menus can be absent from CGWindow metadata without Screen
    /// Recording permission. The item's selected state still tracks its menu.
    func menuIsOpen(for item: OrganizerMenuBarItem, completion: @escaping (Bool) -> Void) {
        interactionQueue.async {
            AXUIElementSetMessagingTimeout(item.element, 0.15)
            let selected = Self.value(kAXSelectedAttribute, from: item.element) as? Bool ?? false
            let expanded = Self.value(kAXExpandedAttribute, from: item.element) as? Bool ?? false
            DispatchQueue.main.async { completion(selected || expanded) }
        }
    }

    private static func value(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ attribute: String, from element: AXUIElement) -> String {
        value(attribute, from: element) as? String ?? ""
    }

    private static func element(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = value(attribute, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func elements(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        value(attribute, from: element) as? [AXUIElement] ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let rawPosition = value(kAXPositionAttribute, from: element),
              let rawSize = value(kAXSizeAttribute, from: element),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
