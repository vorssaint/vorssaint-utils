// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Where Back and Forward actually sit on the current keyboard.
///
/// Apps declare both commands as Command-[ and Command-], but on keyboards
/// where the brackets can only be typed with Option, macOS moves the shortcut
/// to a key that can be reached and the app's menu shows that other key
/// instead. Looking for a literal bracket in the menu then finds nothing at
/// all. The same move happens the other way around, mirrored, when the
/// interface reads right to left.
///
/// macOS does not say where it moved the shortcut to, but it performs the same
/// move on a menu of ours, and the keys it writes back there are the ones the
/// app in front is showing too. The Settings Go menu declares both commands,
/// so its items carry the answer. Without that menu, a hidden pair of items
/// declaring the brackets is added to the app's menu for one turn of the run
/// loop instead. Main thread only, like everything that touches the menu.
enum MouseNavigationKeys {
    /// The key a command ended up on, and the modifiers a menu reports for it.
    struct Shortcut: Equatable {
        var character: String
        var menuModifiers: UInt32
    }

    private static var resolved: [MouseNavigationDirection: Shortcut] = [:]

    /// What to look for in the menu of the app in front. The Go item is read
    /// on every click, since macOS keeps it on the current keyboard. Until the
    /// system has answered, the declared bracket with Command alone stands in,
    /// which is already the right answer on every keyboard that can type it.
    static func shortcut(for direction: MouseNavigationDirection) -> Shortcut {
        if let item = NSApp?.mainMenu.flatMap({ SettingsWindow.navigationItem(for: direction, in: $0) }),
           let shortcut = shortcut(of: item) {
            return shortcut
        }
        return resolved[direction] ?? Shortcut(
            character: MouseNavigationSupport.commandCharacter(for: direction),
            menuModifiers: 0)
    }

    /// Asks the system where it put the two shortcuts. The answer only lands on
    /// the next turn of the run loop, so nothing is known when this returns;
    /// it is asked once when the feature starts and again whenever the keyboard
    /// changes, both far ahead of any click.
    static func refresh() {
        guard let mainMenu = NSApp?.mainMenu else { return }
        // macOS gives a shortcut only to the first item that declares it, so a
        // hidden pair beside the Go menu would come back with no key at all.
        guard MouseNavigationDirection.allCases.contains(where: {
            SettingsWindow.navigationItem(for: $0, in: mainMenu) == nil
        }) else { return }
        let host = NSMenuItem()
        // The app's menu bar is visible while one of its own windows is
        // focused, so the probe must never be drawable.
        host.isHidden = true
        let menu = NSMenu()
        let probes = MouseNavigationDirection.allCases.map { direction -> (MouseNavigationDirection, NSMenuItem) in
            let item = NSMenuItem(title: "",
                                  action: nil,
                                  keyEquivalent: MouseNavigationSupport.commandCharacter(for: direction))
            item.keyEquivalentModifierMask = .command
            item.isHidden = true
            menu.addItem(item)
            return (direction, item)
        }
        host.submenu = menu
        mainMenu.addItem(host)

        DispatchQueue.main.async {
            for (direction, item) in probes {
                resolved[direction] = shortcut(of: item)
            }
            mainMenu.removeItem(host)
        }
    }

    /// What to look for, most likely first: the key the Go item carries, then
    /// the declared bracket. AppKit may re-localize an inactive app's menu only
    /// once it is active, so after a switch to a keyboard that types brackets
    /// the Go item can still carry the key of the one before; the bracket is
    /// what the app in front shows then.
    static func candidates(for direction: MouseNavigationDirection) -> [Shortcut] {
        let declared = Shortcut(character: MouseNavigationSupport.commandCharacter(for: direction), menuModifiers: 0)
        let current = shortcut(for: direction)
        return current == declared ? [current] : [current, declared]
    }

    /// The key macOS left on an item declaring one of the commands, or nil
    /// when the item carries none.
    private static func shortcut(of item: NSMenuItem) -> Shortcut? {
        guard let character = MouseNavigationSupport
            .sanitizedCommandCharacter(item.keyEquivalent) else { return nil }
        let mask = item.keyEquivalentModifierMask
        return Shortcut(
            character: character,
            menuModifiers: MouseNavigationSupport.menuModifiers(
                shift: mask.contains(.shift),
                option: mask.contains(.option),
                control: mask.contains(.control),
                command: mask.contains(.command),
                character: character))
    }

    /// Forgets the answer, so the declared brackets stand in again until the
    /// next one arrives.
    static func reset() { resolved.removeAll() }

    /// The key a finger would press for a character on the current keyboard,
    /// for the rare fallback that has to type the shortcut instead of pressing
    /// the menu item. Nil when no key produces it without Option, which is the
    /// case the system's own move exists to avoid.
    static func keyStroke(for character: String) -> (keyCode: CGKeyCode, needsShift: Bool)? {
        guard Thread.isMainThread,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        // Plain keys first: a shortcut that needs Shift is a worse match than
        // the same character sitting on a key of its own.
        for needsShift in [false, true] {
            for keyCode in UInt16(0)...127 where producedCharacter(from: data, keyCode: keyCode, shift: needsShift) == character {
                return (CGKeyCode(keyCode), needsShift)
            }
        }
        return nil
    }

    private static func producedCharacter(from layout: Data, keyCode: UInt16, shift: Bool) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let modifiers = shift ? UInt32(shiftKey >> 8) : 0
        let status = layout.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(base,
                                  keyCode,
                                  UInt16(kUCKeyActionDown),
                                  modifiers,
                                  UInt32(LMGetKbdType()),
                                  UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState,
                                  characters.count,
                                  &length,
                                  &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
