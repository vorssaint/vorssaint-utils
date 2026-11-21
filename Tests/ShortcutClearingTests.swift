// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation

/// The generator supplies the production row actions, registrars, takeover,
/// recording lifecycle, snippet sync and backup import. Only OS calls, windows
/// and unrelated feature services are doubles. No real hotkey or tap is installed.
/// Native SwiftUI rendering and physical keyboard delivery remain integration checks.
enum ShortcutClearingTests {
    enum UserDefaults {
        static let suiteName = "vorss.tests.shortcut-clearing.\(UUID().uuidString)"
        static let standard = Foundation.UserDefaults(suiteName: suiteName)!
        static func reopened() -> Foundation.UserDefaults {
            Foundation.UserDefaults(suiteName: suiteName)!
        }
    }

    typealias EventHotKeyRef = Int
    typealias EventHandlerRef = Int

    struct RegisteredKey: Equatable {
        let code: UInt32
        let modifiers: UInt32
        init(_ shortcut: GlobalShortcut) {
            code = shortcut.carbonKeyCode
            modifiers = shortcut.carbonModifiers
        }
        init(code: UInt32, modifiers: UInt32) {
            self.code = code
            self.modifiers = modifiers
        }
    }
    static var registrations: [Int: RegisteredKey] = [:]
    static var nextReference = 0
    static var registrationAttempts = 0
    static var refuseRegistration = false

    static func GetEventDispatcherTarget() -> Int { 0 }
    @discardableResult
    static func InstallEventHandler(_ target: Int,
                                   _ handler: @escaping (Int?, Int?, UnsafeMutableRawPointer?) -> OSStatus,
                                   _ count: Int, _ spec: inout EventTypeSpec,
                                   _ data: UnsafeMutableRawPointer?, _ ref: inout EventHandlerRef?) -> OSStatus {
        ref = 1
        return noErr
    }
    @discardableResult
    static func GetEventParameter(_ event: Int, _ name: EventParamName, _ type: EventParamType,
                                 _ actualType: UnsafeMutablePointer<EventParamType>?, _ size: Int,
                                 _ actualSize: UnsafeMutablePointer<Int>?, _ id: inout EventHotKeyID) -> OSStatus {
        noErr
    }
    static func RegisterEventHotKey(_ code: UInt32, _ modifiers: UInt32, _ id: EventHotKeyID,
                                   _ target: Int, _ options: Int, _ ref: inout EventHotKeyRef?) -> OSStatus {
        registrationAttempts += 1
        guard !refuseRegistration else { return OSStatus(-1) }
        nextReference += 1
        registrations[nextReference] = RegisteredKey(code: code, modifiers: modifiers)
        ref = nextReference
        return noErr
    }
    @discardableResult
    static func UnregisterEventHotKey(_ ref: EventHotKeyRef) -> OSStatus {
        registrations.removeValue(forKey: ref)
        return noErr
    }
    static func isRegistered(_ shortcut: GlobalShortcut) -> Bool {
        registrations.values.contains(RegisteredKey(shortcut))
    }

    enum SymbolicHotKeys {
        static var shortcuts: [Int32: GlobalShortcut] = [:]
        static var enabled: [Int32: Bool] = [:]
        static let setEnabled: ((Int32, Bool) -> CGError)? = { id, value in
            enabled[id] = value
            return .success
        }
        static let isEnabled: ((Int32) -> Bool)? = { enabled[$0] ?? false }
        static func liveEntries() -> [LiveSystemShortcut]? {
            // A nonempty table avoids the production fallback to the real
            // macOS preferences plist. This disabled row reserves nothing.
            let unused = LiveSystemShortcut(id: 511, shortcut: .shelfDefault, enabled: false)
            return [unused] + shortcuts.map {
                LiveSystemShortcut(id: $0.key, shortcut: $0.value, enabled: enabled[$0.key] ?? false)
            }
        }
    }
    enum NSWorkspace {
        static let shared = Workspace()
        static let didWakeNotification = Notification.Name("fixture.shortcut.wake")
        final class Workspace { let notificationCenter = NotificationCenter() }
    }
    enum NSSound { static func beep() {} }

    final class Window: NSObject {
        weak var firstResponder: AnyObject?
        var acceptsFocus = true
        func makeFirstResponder(_ responder: AnyObject) -> Bool {
            guard acceptsFocus else { return false }
            firstResponder = responder
            return true
        }
    }
    class NSButton: NSObject {
        var window: Window? = Window()
        var isEnabled = true
        var title = ""
        var acceptsFirstResponder: Bool { false }
        func resignFirstResponder() -> Bool { true }
        func viewDidMoveToWindow() {}
        func performKeyEquivalent(with event: NSEvent) -> Bool { false }
        func keyDown(with event: NSEvent) {}
        func flagsChanged(with event: NSEvent) {}
    }
    enum ShortcutRecordingTap {
        static var handler: ((Int64, GlobalShortcutModifiers, CGEventFlags) -> Void)?
        static func begin(_ callback: @escaping (Int64, GlobalShortcutModifiers, CGEventFlags) -> Void) {
            handler = callback
        }
        static func end() { handler = nil }
        static func press(_ code: Int64, modifiers: GlobalShortcutModifiers = []) {
            handler?(code, modifiers, [])
        }
    }
    final class AppSwitcher {
        static let shared = AppSwitcher()
        var capturing = false
        func setCapturingShortcut(_ value: Bool) { capturing = value }
    }
    final class Suspension {
        var count = 0
        func suspendShortcut() { count += 1 }
        func suspendShortcuts() { count += 1 }
    }
    enum ShelfService { static let shared = Suspension() }
    enum ClipboardHistoryService { static let shared = Suspension() }
    enum SoundOutputSwitcher { static let shared = Suspension() }
    enum WindowLayoutService { static let shared = Suspension() }
    final class FeatureRuntime {
        static let shared = FeatureRuntime()
        var lastSynced: [AppFeature] = []
        var onSync: ([AppFeature]) -> Void = { _ in }
        func sync(_ features: [AppFeature]) {
            lastSynced = features
            onSync(features)
        }
    }

    class LibraryState {
        let hotkey = QuickToolHotkey(id: 19)
        var shortcutRegistrationFailed = false
        var isVisible = false
        var hides = 0
        var reloads = 0
        func hide() { hides += 1; isVisible = false }
        func reloadSnippets() { reloads += 1 }
        func refreshPanelLayout() {}
    }
    class RowState {
        struct English { let s = Strings.enUS }
        let l10n = English()
        let role: GlobalShortcutRole
        var includeInactiveConflicts = true
        var additionalConflict: (GlobalShortcut) -> String? = { _ in nil }
        var errorText: String?
        var pendingTakeOver: GlobalShortcut?
        var changes = 0
        var rawValue: String {
            get { UserDefaults.standard.string(forKey: role.storageKey) ?? role.defaultShortcut.storageValue }
            set { UserDefaults.standard.set(newValue, forKey: role.storageKey) }
        }
        init(_ role: GlobalShortcutRole) { self.role = role }
        func onChange() { changes += 1; sync(role) }
    }

    static func sync(_ role: GlobalShortcutRole) {
        if role == .keepAwake { HotkeyManager.shared.syncWithPreferences() }
        if role == .snippetLibrary { Library.shared.syncWithPreferences() }
    }
    static func assigned(_ role: GlobalShortcutRole) -> GlobalShortcut? {
        role.assignedShortcut(storedValue: { UserDefaults.standard.string(forKey: $0) })
    }

    static func run(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: UserDefaults.suiteName)
        let registration = defaults.volatileDomain(forName: Foundation.UserDefaults.registrationDomain)
        defaults.register(defaults: Defaults.registeredDefaults)
        defaults.register(defaults: AppFeature.availabilityDefaults)
        for role in [GlobalShortcutRole.keepAwake, .snippetLibrary] {
            defaults.set(true, forKey: role.feature.availabilityKey)
            for key in role.requiredEnableKeys { defaults.set(true, forKey: key) }
        }
        let extra = QuickToolHotkey(id: 999)
        let extraShortcut = GlobalShortcut(keyCode: Int64(kVK_F18), modifiers: [.control, .shift])
        let replacement = GlobalShortcut(keyCode: Int64(kVK_F17), modifiers: [.control, .shift])
        let systemShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_4), modifiers: [.command, .shift])
        FeatureRuntime.shared.onSync = { features in
            if features.contains(.keepAwake) { sync(.keepAwake) }
            if features.contains(.textSnippets) { sync(.snippetLibrary) }
            if features.contains(.colorPicker) {
                extra.sync(enabled: true, shortcut: extraShortcut, storageKey: DefaultsKey.colorPickerShortcut)
            }
        }
        defer {
            ShortcutCapture.end()
            HotkeyManager.shared.setEnabled(false)
            QuickToolHotkey.unregisterAll()
            SystemShortcutTakeover.restoreAll()
            for role in [GlobalShortcutRole.keepAwake, .snippetLibrary] {
                SystemShortcutTakeover.setTakeOver(role.storageKey, false)
            }
            FeatureRuntime.shared.onSync = { _ in }
            ShortcutRecordingTap.end()
            defaults.removePersistentDomain(forName: UserDefaults.suiteName)
            defaults.setVolatileDomain(registration, forName: Foundation.UserDefaults.registrationDomain)
        }

        for role in [GlobalShortcutRole.keepAwake, .snippetLibrary] {
            let other: GlobalShortcutRole = role == .keepAwake ? .snippetLibrary : .keepAwake
            let row = Row(role)
            let otherRow = Row(other)
            row.rawValue = "invalid"
            sync(role)
            suite.expect(isRegistered(role.defaultShortcut),
                         "\(role) corrupt preferences retain the production fallback")
            row.reset()
            otherRow.reset()
            extra.sync(enabled: true, shortcut: extraShortcut, storageKey: DefaultsKey.colorPickerShortcut)
            let attempts = registrationAttempts
            sync(role)
            suite.expect(registrationAttempts == attempts && isRegistered(role.defaultShortcut),
                         "\(role) sync keeps one existing registration")

            // This is the same action wired to X. Clearing must keep the feature on.
            Library.shared.isVisible = true
            let hides = Library.shared.hides
            row.pendingTakeOver = replacement
            row.errorText = "old error"
            row.clear()
            suite.expect(assigned(role) == nil && !isRegistered(role.defaultShortcut)
                         && row.errorText == nil && row.pendingTakeOver == nil,
                         "\(role) X clears the preference, registration and pending row state")
            suite.expect(role.requiredEnableKeys.allSatisfy { defaults.bool(forKey: $0) }
                         && Library.shared.isVisible && Library.shared.hides == hides
                         && isRegistered(other.defaultShortcut) && isRegistered(extraShortcut),
                         "\(role) clear keeps the feature, visible library and other shortcuts available")
            let clearedAttempts = registrationAttempts
            sync(role)
            suite.expect(registrationAttempts == clearedAttempts,
                         "\(role) repeated sync never registers a cleared fallback")
            for key in role.requiredEnableKeys { defaults.set(false, forKey: key) }
            sync(role)
            for key in role.requiredEnableKeys { defaults.set(true, forKey: key) }
            sync(role)
            defaults.set(false, forKey: role.feature.availabilityKey)
            sync(role)
            defaults.set(true, forKey: role.feature.availabilityKey)
            sync(role)
            suite.expect(assigned(role) == nil && registrationAttempts == clearedAttempts,
                         "\(role) stays cleared across enable and feature availability changes")

            // A newly opened preferences reader sees the persisted sentinel.
            let reopened = UserDefaults.reopened()
            suite.expect(role.assignedShortcut(storedValue: { reopened.string(forKey: $0) }) == nil,
                         "\(role) remains cleared for a fresh preferences reader")
            let payload = SettingsBackupSupport.payload(appVersion: "test") { defaults.object(forKey: $0) }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
                let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                if let decoded, let restored = SettingsBackupSupport.sanitizedSettings(from: decoded) {
                    row.reset()
                    Backup.apply(settings: restored)
                    sync(role)
                    suite.expect(assigned(role) == nil && !isRegistered(role.defaultShortcut),
                                 "\(role) backup import removes an intervening assignment and releases its key")
                } else {
                    suite.expect(false, "\(role) exported backup can be decoded and validated")
                }
            } catch {
                suite.expect(false, "\(role) backup serializes without error \(error)")
            }

            // Once another feature uses the freed key, Reset must not steal it.
            otherRow.save(role.defaultShortcut)
            suite.expect(assigned(other) == role.defaultShortcut && isRegistered(role.defaultShortcut),
                         "another feature can use \(role)'s cleared combination")
            let beforeRejectedReset = row.changes
            row.reset()
            suite.expect(assigned(role) == nil && row.errorText != nil && row.changes == beforeRejectedReset
                         && isRegistered(role.defaultShortcut),
                         "\(role) reset rejects an occupied default without changing either binding")
            otherRow.reset()
            row.reset()
            suite.expect(assigned(role) == role.defaultShortcut && isRegistered(role.defaultShortcut)
                         && row.errorText == nil,
                         "\(role) reset restores a free default")
            row.save(replacement)
            suite.expect(assigned(role) == replacement && isRegistered(replacement)
                         && !isRegistered(role.defaultShortcut),
                         "\(role) replacement releases its previous combination")
            row.additionalConflict = { _ in "window layout" }
            row.reset()
            suite.expect(assigned(role) == replacement && row.errorText != nil && isRegistered(replacement),
                         "\(role) reset respects the caller's additional conflict check")
            row.additionalConflict = { _ in nil }
            SymbolicHotKeys.shortcuts = [28: role.defaultShortcut]
            SymbolicHotKeys.enabled = [28: true]
            row.reset()
            suite.expect(assigned(role) == replacement && row.pendingTakeOver == role.defaultShortcut
                         && isRegistered(replacement) && SymbolicHotKeys.enabled[28] == true,
                         "\(role) reset offers a macOS takeover without dropping the current binding")
            SymbolicHotKeys.shortcuts = [:]
            SymbolicHotKeys.enabled = [:]

            // Registration failure is a system result, not an assignment to revive on clear.
            row.clear()
            refuseRegistration = true
            row.reset()
            suite.expect(role == .keepAwake ? HotkeyManager.shared.registrationFailed
                         : Library.shared.shortcutRegistrationFailed,
                         "\(role) reports a refused registration")
            row.clear()
            suite.expect(!HotkeyManager.shared.registrationFailed && !Library.shared.shortcutRegistrationFailed,
                         "\(role) clear removes the stale registration error")
            refuseRegistration = false

            // Exercise real takeover ownership against a fake WindowServer table.
            SymbolicHotKeys.shortcuts = [28: systemShortcut]
            SymbolicHotKeys.enabled = [28: true]
            row.rawValue = systemShortcut.storageValue
            SystemShortcutTakeover.setTakeOver(role.storageKey, true)
            sync(role)
            suite.expect(SymbolicHotKeys.enabled[28] == false && isRegistered(systemShortcut),
                         "\(role) takes over only after registering its handler")
            SystemShortcutTakeover.setWanted([28], for: "other-owner")
            row.clear()
            suite.expect(!isRegistered(systemShortcut) && !SystemShortcutTakeover.isTakenOver(role.storageKey)
                         && SymbolicHotKeys.enabled[28] == false,
                         "\(role) clear drops its registration and opt-in while preserving another owner")
            SystemShortcutTakeover.setWanted([], for: "other-owner")
            suite.expect(SymbolicHotKeys.enabled[28] == true
                         && defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) == nil,
                         "the last release restores the macOS key and clears the crash marker")
            row.rawValue = systemShortcut.storageValue
            SymbolicHotKeys.enabled[28] = false
            SystemShortcutTakeover.setTakeOver(role.storageKey, true)
            sync(role)
            row.clear()
            suite.expect(SymbolicHotKeys.enabled[28] == false,
                         "\(role) clear never enables a macOS shortcut that was already disabled")
            SymbolicHotKeys.shortcuts = [:]
            SymbolicHotKeys.enabled = [:]

            row.reset()
            let recorder = RecorderButton()
            recorder.shortcut = role.defaultShortcut
            recorder.clearAction = row.clear
            recorder.captureAction = row.save
            var invalidCaptures = 0
            recorder.invalidAction = { invalidCaptures += 1 }
            for key in [kVK_Delete, kVK_ForwardDelete] {
                row.reset()
                let holders = [ShelfService.shared, ClipboardHistoryService.shared,
                               SoundOutputSwitcher.shared, WindowLayoutService.shared]
                let suspensionCounts = holders.map(\.count)
                recorder.beginRecording()
                suite.expect(ShortcutCapture.isCapturing && registrations.isEmpty && AppSwitcher.shared.capturing
                             && holders.map(\.count) == suspensionCounts.map { $0 + 1 },
                             "recording \(role) suspends both registrars and every other shortcut holder")
                ShortcutRecordingTap.press(Int64(key))
                suite.expect(!ShortcutCapture.isCapturing && ShortcutRecordingTap.handler == nil
                             && assigned(role) == nil && !isRegistered(role.defaultShortcut)
                             && isRegistered(other.defaultShortcut) && isRegistered(extraShortcut),
                             "\(role) deletion key \(key) clears through the recorder and restores unrelated shortcuts")
            }
            recorder.beginRecording()
            ShortcutRecordingTap.press(Int64(kVK_ANSI_A))
            suite.expect(invalidCaptures == 1 && assigned(role) == nil && ShortcutCapture.isCapturing,
                         "\(role) rejects a bare letter without changing a cleared assignment")
            ShortcutRecordingTap.press(replacement.keyCode, modifiers: replacement.modifiers)
            suite.expect(assigned(role) == replacement && isRegistered(replacement) && !ShortcutCapture.isCapturing,
                         "\(role) records a replacement after clearing")
            let modifiedDelete = GlobalShortcut(keyCode: Int64(kVK_Delete), modifiers: [.control])
            recorder.beginRecording()
            ShortcutRecordingTap.press(modifiedDelete.keyCode, modifiers: modifiedDelete.modifiers)
            suite.expect(assigned(role) == modifiedDelete && isRegistered(modifiedDelete),
                         "\(role) Control Delete remains an assignable shortcut")
            row.save(replacement)

            let exits: [(String, (RecorderButton) -> Void)] = [
                ("escape", { _ in ShortcutRecordingTap.press(Int64(kVK_Escape)) }),
                ("focus loss", { _ = $0.resignFirstResponder() }),
                ("window removal", { $0.window = nil; $0.viewDidMoveToWindow() }),
                ("window close", { NotificationCenter.default.post(name: NSWindow.willCloseNotification,
                                                                    object: $0.window) }),
                ("app deactivation", { _ in NotificationCenter.default.post(
                    name: NSApplication.didResignActiveNotification, object: nil) }),
            ]
            for (name, cancel) in exits {
                let field = RecorderButton()
                var capturesAfterExit = 0
                field.clearAction = { capturesAfterExit += 1 }
                field.captureAction = { _ in capturesAfterExit += 1 }
                field.beginRecording()
                let delayedDelivery = ShortcutRecordingTap.handler
                cancel(field)
                delayedDelivery?(Int64(kVK_Delete), [], [])
                suite.expect(!ShortcutCapture.isCapturing && !AppSwitcher.shared.capturing
                             && ShortcutRecordingTap.handler == nil && capturesAfterExit == 0
                             && assigned(role) == replacement
                             && isRegistered(replacement) && isRegistered(other.defaultShortcut)
                             && isRegistered(extraShortcut),
                             "\(role) \(name) cancels capture and restores the unchanged bindings")
            }
            suite.expect(Set(FeatureRuntime.shared.lastSynced)
                         == Set(GlobalShortcutRole.allCases.map(\.feature)).union([.windowLayout]),
                         "capture restores every feature in the production suspension contract")
            let denied = RecorderButton()
            denied.window?.acceptsFocus = false
            denied.beginRecording()
            suite.expect(!ShortcutCapture.isCapturing && isRegistered(replacement),
                         "a field that cannot take focus never suspends \(role)")

            let disabled = RecorderButton()
            disabled.beginRecording()
            for key in role.requiredEnableKeys { defaults.set(false, forKey: key) }
            disabled.stopRecording()
            suite.expect(!isRegistered(replacement) && isRegistered(other.defaultShortcut),
                         "\(role) disabled during capture stays unregistered after cancellation")
            for key in role.requiredEnableKeys { defaults.set(true, forKey: key) }
            row.reset()
        }
        let unsupported = Row(.shelf)
        let previous = unsupported.rawValue
        unsupported.clear()
        suite.expect(unsupported.rawValue == previous && unsupported.changes == 0,
                     "a role outside this change cannot be cleared by the row action")
    }
}
