// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Jump to a Dock app by its number. Nine Carbon hotkeys on the Super key's
/// modifier layer (its configurable set, ⌃⌥⌘⇧ by default) each activate — or
/// launch — the app in that Dock position; with the Super key on, that layer is
/// reached as Caps Lock + the digit. Nothing is registered while the feature is
/// off.
///
/// The digit position is read live from the Dock's Accessibility tree at the
/// moment the key is pressed, so it always follows the Dock the user sees.
/// Launching itself needs no permission; reading the order needs Accessibility.
final class DockNumberSwitchService: ObservableObject {
    static let shared = DockNumberSwitchService()

    /// Why the digits are not all bound (a narrowed Super key, or a combination
    /// already taken), so the settings screen can say why instead of the keys
    /// silently doing nothing.
    @Published private(set) var status: DockNumberSwitchSupport.RegistrationStatus = .ok

    /// An id block of its own so the shared hotkey handler never collides with
    /// another feature's keys (single tools 10–24, CommandBar 200+, RadialMenu
    /// 1700+).
    private static let hotkeyIDBase: UInt32 = 1900
    private static let digitKeyCodes: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    private var hotkeys: [QuickToolHotkey] = []
    private var dockPIDCache: pid_t?

    private init() {}

    func syncWithPreferences() {
        let enabled = AppFeature.dockNumberSwitch.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.dockNumberSwitchEnabled)
        guard enabled else {
            suspend()
            status = .ok
            return
        }

        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys.removeAll()

        // The layer the Super key emits: its own configurable modifier set, so a
        // digit is reached as "Super key + digit" whatever the user narrowed it
        // to. Reading it here means a change to that preference is picked up on
        // the re-sync the Super key settings already fire (see SuperKeySettings).
        let superKeyModifiers = SuperKeySupport.modifiers(
            from: UserDefaults.standard.string(forKey: DefaultsKey.superKeyModifiers))

        // A Super key narrowed to a single modifier makes these ⌘1…⌘9 or
        // ⌃1…⌃9 — combinations this app owns nowhere but the system and every
        // browser route to tab and desktop switching; registering them would
        // break that everywhere while the toggle is on. Register nothing then.
        guard DockNumberSwitchSupport.registersDigits(forModifierCount: superKeyModifiers.count)
        else {
            // Nothing bound; the settings toggle shows this as inactive from the
            // Super key modifiers directly, so no per-digit status is needed.
            status = .ok
            return
        }

        // The enabled system hotkeys, read once from Carbon's authoritative
        // list rather than the com.apple.symbolichotkeys plist, which omits the
        // defaults the user never customized — the screenshot keys (⌘⇧3…6)
        // among them, right where a digit layer lands.
        let systemHotkeys = Self.systemHotkeys()

        // The 1-based digits that could not be claimed, so the badge can name
        // exactly which numbers may not work.
        var unavailableDigits: [Int] = []
        for (index, keyCode) in Self.digitKeyCodes.enumerated() {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: superKeyModifiers)
            let slot = index + 1
            // Even on a wider layer a single digit can land on a live system
            // shortcut (⌘⇧3 is a screenshot under a ⌘⇧ Super key). RegisterEventHotKey
            // would preempt it silently, so a conflicting digit is left unclaimed
            // — the same class the recorder refuses.
            if DockNumberSwitchSupport.conflictsWithSystemHotkey(
                keyCode: shortcut.keyCode,
                carbonModifiers: shortcut.carbonModifiers,
                systemHotkeys: systemHotkeys) {
                unavailableDigits.append(slot)
                continue
            }
            let hotkey = QuickToolHotkey(id: Self.hotkeyIDBase + UInt32(index))
            hotkey.onPress = { [weak self] in self?.activate(slot: slot) }
            if !hotkey.sync(enabled: true, shortcut: shortcut) { unavailableDigits.append(slot) }
            hotkeys.append(hotkey)
        }
        status = unavailableDigits.isEmpty ? .ok : .someUnavailable(digits: unavailableDigits)
    }

    /// Unregisters every digit hotkey regardless of the preference. Used before
    /// the app tears itself down, so a shortcut is never left claimed by a
    /// process that is about to go away.
    func suspend() {
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys.removeAll()
    }

    // MARK: - Action

    /// Activates (or launches) the app at the 1-based Dock position. When that
    /// app is already frontmost the press cycles its windows instead, matching
    /// macOS ⌘`. A slot with no app behind it — the Dock has fewer apps, or it
    /// could not be read — is a quiet beep, never a wrong app.
    func activate(slot: Int) {
        guard let url = DockNumberSwitchSupport.target(in: dockApplicationURLs(), slot: slot) else {
            NSSound.beep()
            return
        }
        let running = runningApplication(for: url)
        let appIsFrontmost = running.map(Self.isFrontmost) ?? false
        switch DockNumberSwitchSupport.action(appIsFrontmost: appIsFrontmost) {
        case .cycleWindows:
            // Reuse the Dock-click feature's tested ⌘`-style cycler; it needs
            // only the pid and runs whether or not that feature is switched on.
            if let running { DockClickService.shared.cycleWindows(pid: running.processIdentifier) }
        case .activateOrLaunch:
            // openApplication both launches a quit app and activates a running
            // one, the same call the Command Bar uses to open an app row.
            NSWorkspace.shared.openApplication(at: url,
                                               configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { DispatchQueue.main.async { NSSound.beep() } }
            }
        }
    }

    /// The running app a Dock tile URL points at, matched by app bundle path the
    /// way `DockClickService` resolves a clicked tile. Nil when the app is not
    /// running (a pinned tile whose app is quit).
    private func runningApplication(for url: URL) -> NSRunningApplication? {
        let standardized = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.bundleURL?.standardizedFileURL.path == standardized
        }
    }

    /// Whether the app is the one the user is currently in. `isActive` alone can
    /// misreport for launcher-style apps, so the workspace's frontmost pid is the
    /// tiebreaker — the same check `DockClickService` uses.
    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        !app.isHidden
            && (app.isActive
                || NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier)
    }

    /// The URLs of the application tiles in the Dock, in the order they sit
    /// there. Public so the settings screen can show the current mapping.
    func dockApplicationURLs() -> [URL] {
        guard let dockPID = dockProcessID() else { return [] }
        let dockElement = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockElement, 0.35)
        guard let children = Self.elementArray(dockElement, kAXChildrenAttribute as String) else {
            return []
        }
        // Gather tiles from every AXList in tree order, not just the first, the
        // way DockClickService walks the Dock: today the tiles live in one list,
        // but if a macOS release ever splits them across lists, stopping at the
        // first would silently number only part of the Dock.
        var tiles: [DockNumberSwitchSupport.Tile] = []
        for child in children where Self.stringAttribute(child, kAXRoleAttribute as String) == "AXList" {
            guard let items = Self.elementArray(child, kAXChildrenAttribute as String) else { continue }
            tiles.append(contentsOf: items.map { item in
                DockNumberSwitchSupport.Tile(
                    subrole: Self.stringAttribute(item, kAXSubroleAttribute as String),
                    url: Self.urlAttribute(item)
                )
            })
        }
        return DockNumberSwitchSupport.applicationURLs(from: tiles)
    }

    /// The enabled system symbolic hotkeys, from Carbon's `CopySymbolicHotKeys`
    /// — the effective set including the defaults the plist never lists. The
    /// modifiers are masked to the four real ones so they compare against a
    /// shortcut's own `carbonModifiers`.
    private static func systemHotkeys() -> [DockNumberSwitchSupport.SystemHotkey] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        let mask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return entries.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let keyCode = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.int64Value,
                  let modifiers = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
            else { return nil }
            return DockNumberSwitchSupport.SystemHotkey(keyCode: keyCode,
                                                        carbonModifiers: modifiers & mask)
        }
    }

    // MARK: - Dock Accessibility helpers

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

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else { return nil }
        return array
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func urlAttribute(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFURLGetTypeID()
        else { return nil }
        return (value as! CFURL) as URL
    }
}
