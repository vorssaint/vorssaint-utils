// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// One menu command of the app in front, as the bar offers it.
struct CommandBarMenuItem {
    /// Menu titles from the bar down to the parent, for example ["Format", "Font"].
    let path: [String]
    let title: String
    /// The item's own keyboard shortcut, when it has one. This is the whole
    /// point: the bar runs the command today and teaches the shortcut for
    /// tomorrow.
    let shortcut: String?
    let element: AXUIElement
}

/// Reads the menu bar of whichever app is in front and lets the command bar
/// run any of its commands. This is what makes the bar reach past Vorssaint:
/// every menu of every app becomes searchable by name.
///
/// The whole walk happens away from the main thread and behind a per-app
/// cache. Menus are lazily built by their owners, so the walk asks for
/// children rather than opening anything on screen.
enum CommandBarMenus {
    /// Deep enough for the real nesting apps use, shallow enough that a
    /// pathological tree cannot cost a walk.
    private static let maximumDepth = 4
    private static let maximumItems = 400
    /// Menus a person never means to run from a search field, and that would
    /// either close the bar's own host or confuse the list.
    private static let skippedTopLevelTitles: Set<String> = ["Apple", "Window", "Help"]

    /// The menu commands of `pid`, or an empty list when the app has no menu
    /// bar or Accessibility is not granted. Blocking: callers run it on a
    /// background queue.
    static func items(for pid: pid_t) -> [CommandBarMenuItem] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        // A hung app must not hold the walk: the AX timeout is process wide,
        // so every call here is on a short leash.
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let menuBar = copyElement(app, kAXMenuBarAttribute) else { return [] }

        var collected: [CommandBarMenuItem] = []
        for menu in children(of: menuBar) {
            guard let title = copyString(menu, kAXTitleAttribute), !title.isEmpty,
                  !skippedTopLevelTitles.contains(title) else { continue }
            // The bar of a menu holds one submenu per title; its children are
            // the commands.
            for child in children(of: menu) {
                collect(child, path: [title], into: &collected, depth: 1)
                if collected.count >= maximumItems { return collected }
            }
        }
        return collected
    }

    private static func collect(_ element: AXUIElement,
                                path: [String],
                                into collected: inout [CommandBarMenuItem],
                                depth: Int) {
        guard depth <= maximumDepth, collected.count < maximumItems else { return }
        let role = copyString(element, kAXRoleAttribute)
        if role == kAXMenuRole as String {
            for child in children(of: element) {
                collect(child, path: path, into: &collected, depth: depth + 1)
            }
            return
        }
        guard role == kAXMenuItemRole as String,
              let title = copyString(element, kAXTitleAttribute),
              !title.isEmpty else { return }

        let submenus = children(of: element)
        if !submenus.isEmpty {
            // A title that only opens another menu is not a command.
            for child in submenus {
                collect(child, path: path + [title], into: &collected, depth: depth + 1)
            }
            return
        }
        guard isEnabled(element) else { return }
        collected.append(CommandBarMenuItem(path: path,
                                            title: title,
                                            shortcut: shortcut(of: element),
                                            element: element))
    }

    /// Presses a menu command. The bar never activates, so the app that owns
    /// the menu is still the front one and the command lands where expected.
    @discardableResult
    static func press(_ item: CommandBarMenuItem) -> Bool {
        AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }

    // MARK: - Accessibility reading

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let raw = copyValue(element, kAXChildrenAttribute) else { return [] }
        // The type has to be checked before the cast: a wrong cast on an AX
        // value is a crash, not a nil.
        guard CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
        return (raw as? [AXUIElement]) ?? []
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == CFStringGetTypeID() else { return nil }
        return (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        guard let raw = copyValue(element, kAXEnabledAttribute),
              CFGetTypeID(raw) == CFBooleanGetTypeID() else { return true }
        return (raw as? Bool) ?? true
    }

    /// The item's shortcut written the way the menu writes it, from the
    /// command character and the modifier mask macOS exposes.
    private static func shortcut(of element: AXUIElement) -> String? {
        guard let character = copyString(element, "AXMenuItemCmdChar"), !character.isEmpty
        else { return nil }
        var modifiers = 0
        if let raw = copyValue(element, "AXMenuItemCmdModifiers"),
           CFGetTypeID(raw) == CFNumberGetTypeID() {
            modifiers = (raw as? Int) ?? 0
        }
        // The classic Carbon mask: shift is bit 0, option bit 1, control bit 2,
        // and bit 3 is the one that DROPS Command. Written in the order macOS
        // writes modifiers.
        var glyphs = ""
        if modifiers & 0x04 != 0 { glyphs += "⌃" }
        if modifiers & 0x02 != 0 { glyphs += "⌥" }
        if modifiers & 0x01 != 0 { glyphs += "⇧" }
        if modifiers & 0x08 == 0 { glyphs += "⌘" }
        return glyphs + character.uppercased()
    }
}
