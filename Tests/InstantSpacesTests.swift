// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum InstantSpacesTests {
    enum SymbolicHotKeys {
        static var table: [LiveSystemShortcut]?
        static var reads: [Set<Int32>] = []
        static func entries(for ids: Set<Int32>) -> [LiveSystemShortcut]? {
            reads.append(ids)
            return table?.filter { ids.contains($0.id) }
        }
    }

    enum ShortcutCapture { static var isCapturing = false }
    enum CGEventSource {
        static var dragging = false
        static func buttonState(_ state: CGEventSourceStateID, button: CGMouseButton) -> Bool { dragging }
    }

    class KeyboardFixture {
        struct Tap { let port: CFMachPort }
        var keyboardTap: Tap?
        var swipeTap: Tap?
        var envelopeTap: Tap?
        var swipe: InstantSpacesSupport.Swipe?
        var keyboardEnabled = true
        var canRun = true
        var claimedKeys: Set<Int64> = []
        var travel: DispatchWorkItem?
        // Deliberately stale: a return to cached matching must fail these checks.
        var shortcuts = [LiveSystemShortcut(id: 81, keyCode: 124, flags: .maskControl, enabled: true)]
        var overview = false
        var actions: [InstantSpacesSupport.Action] = []
        func suspend() {}
        func syncWithPreferences() {}
        func overviewIsActive() -> Bool? { overview }
        func perform(_ action: InstantSpacesSupport.Action) -> Bool { actions.append(action); return true }
        func handleSwipe(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            Unmanaged.passUnretained(event)
        }
    }

    static func run(_ suite: TestSuite) {
        keyboardRefresh(suite)
        let bindings = [
            LiveSystemShortcut(id: 79, keyCode: 123, flags: .maskControl, enabled: true),
            LiveSystemShortcut(id: 81, keyCode: 124, flags: .maskAlternate, enabled: false),
            LiveSystemShortcut(id: 118, keyCode: 18, flags: .maskControl, enabled: true),
            LiveSystemShortcut(id: 119, keyCode: 19, flags: [], enabled: true),
        ]
        suite.expect(InstantSpacesSupport.action(keyCode: 123, flags: .maskControl,
                                                 shortcuts: bindings) == .step(-1),
                     "enabled system shortcuts keep their configured modifiers")
        suite.expect(InstantSpacesSupport.action(keyCode: 123, flags: [.maskControl, .maskCommand],
                                                 shortcuts: bindings) == nil,
                     "an extra modifier leaves other applications' shortcuts alone")
        suite.expect(InstantSpacesSupport.action(keyCode: 124, flags: .maskAlternate,
                                                 shortcuts: bindings) == nil,
                     "disabled system shortcuts are never intercepted")
        suite.expect(InstantSpacesSupport.action(keyCode: 18, flags: .maskControl,
                                                 shortcuts: bindings) == .desktop(0),
                     "direct desktop shortcuts keep system numbering")
        suite.expect(InstantSpacesSupport.action(keyCode: 19, flags: [], shortcuts: bindings) == nil,
                     "unmodified number keys remain usable for typing")
        suite.expect(InstantSpacesSupport.action(keyCode: 123, flags: .maskControl, shortcuts: []) == nil,
                     "an unavailable system shortcut table fails open")
        let fn = [LiveSystemShortcut(id: 79, keyCode: 123,
                                    flags: [.maskControl, .maskSecondaryFn], enabled: true)]
        suite.expect(InstantSpacesSupport.action(keyCode: 123, flags: .maskControl, shortcuts: fn) == nil
            && InstantSpacesSupport.action(keyCode: 123, flags: [.maskControl, .maskSecondaryFn],
                                            shortcuts: fn) == .step(-1),
                     "an explicitly configured Fn modifier is required")

        let spaces: [UInt64] = [101, 12, 700]
        suite.expect(SpaceHopSupport.desktopSpaceIDs([
            ["id64": 101, "type": 0], ["id64": 12, "type": 4],
            ["id64": 90, "type": 2], ["id64": 700, "type": 0],
        ]) == [101, 700], "desktop numbering excludes fullscreen and special Spaces")
        suite.expect(SpaceHopSupport.desktopSpaceIDs([["id64": 88]]) == nil
            && SpaceHopSupport.desktopSpaceIDs([["type": 0]]) == nil,
                     "malformed Spaces cannot shift the numbering of later desktops")
        suite.expect(InstantSpacesSupport.destination(in: spaces, current: 12, direction: 1) == 700
            && InstantSpacesSupport.destination(in: spaces, current: 12, direction: -1) == 101,
                     "navigation follows display order rather than numeric Space IDs")
        suite.expect(InstantSpacesSupport.destination(in: spaces, current: 101, direction: -1) == nil
            && InstantSpacesSupport.destination(in: spaces, current: 700, direction: 1) == nil
            && InstantSpacesSupport.destination(in: spaces, current: 999, direction: 1) == nil
            && InstantSpacesSupport.destination(in: spaces, current: 101, direction: Int.min) == nil
            && InstantSpacesSupport.destination(in: [], current: 101, direction: 1) == nil,
                     "edges and stale or missing topology never select an arbitrary Space")

        var swipe = InstantSpacesSupport.Swipe()
        suite.expect(swipe.update(progress: 0.01) == nil && swipe.update(progress: -0.02) == nil,
                     "touchdown wobble does not commit a direction")
        suite.expect(swipe.update(progress: 0.08) == 1 && swipe.update(progress: 0.8) == nil
            && swipe.update(progress: 0.7) == nil,
                     "continued motion and settling produce only one switch")
        suite.expect(swipe.update(progress: 0.5) == -1 && swipe.update(progress: 0.2) == nil
            && swipe.update(progress: 0.5) == 1,
                     "a deliberate reversal switches back without lifting fingers")
        suite.expect(swipe.finish(velocity: -400) == nil,
                     "lifting fingers does not duplicate an already committed switch")
        let flick = InstantSpacesSupport.Swipe()
        suite.expect(flick.finish(velocity: 2) == 1 && flick.finish(velocity: -2) == -1
            && flick.finish(velocity: 0) == nil && flick.finish(velocity: .nan) == nil,
                     "a quick flick uses terminal velocity, but stationary or invalid samples do nothing")
        var invalid = InstantSpacesSupport.Swipe()
        suite.expect(invalid.update(progress: .infinity) == nil && invalid.update(progress: .nan) == nil
            && invalid.update(progress: -0.1) == -1,
                     "invalid gesture samples do not poison the next real movement")

        suite.expect(InstantSpacesGesture.events(direction: 0) == nil
            && InstantSpacesGesture.events(direction: 2) == nil,
                     "invalid directions cannot create a synthetic gesture")
        if InstantSpacesGesture.isSupported {
            for direction in [-1, 1] {
                guard let events = InstantSpacesGesture.events(direction: direction) else {
                    suite.expect(false, "supported systems can serialize a complete DockSwipe")
                    continue
                }
                let phases = events.filter { $0.type.rawValue == 30 }.map {
                    $0.getIntegerValueField(CGEventField(rawValue: 132)!)
                }
                suite.expect(phases == (InstantSpacesGesture.augmented ? [1, 2, 4] : [1, 4]),
                             "a serialized gesture starts and terminates in the required order")
                suite.expect(events.allSatisfy {
                    $0.getIntegerValueField(.eventSourceUserData) == InstantSpacesGesture.marker
                }, "rebuilt synthetic events bypass physical-swipe interception")
                if let terminal = events.dropLast().last,
                   let cleanup = InstantSpacesGesture.cleanup(terminal) {
                    suite.expect(cleanup.getDoubleValueField(CGEventField(rawValue: 124)!) == 0
                        && cleanup.getDoubleValueField(CGEventField(rawValue: 129)!) == 0
                        && cleanup.getIntegerValueField(CGEventField(rawValue: 132)!) == 4,
                                 "cleanup closes the gesture without carrying another movement")
                } else {
                    suite.expect(false, "a terminal gesture can be rebuilt for cleanup")
                }
            }
        }

        suite.expect(AppFeature.availabilityDefaults[AppFeature.instantSpaces.availabilityKey] as? Bool == false
            && Defaults.registeredDefaults[DefaultsKey.instantSpacesKeyboard] as? Bool == false
            && Defaults.registeredDefaults[DefaultsKey.instantSpacesTrackpad] as? Bool == false,
                     "existing installations gain no new input interception on upgrade")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [
            DefaultsKey.instantSpacesKeyboard, DefaultsKey.instantSpacesTrackpad,
            AppFeature.instantSpaces.availabilityKey,
        ]), "both input preferences and feature availability travel in settings backups")
        suite.expect(AppFeature.instantSpaces.permissions == [.accessibility]
            && AppFeature.instantSpaces.settingsDestination == FeatureSettingsDestination(.instantSpaces),
                     "feature discovery and permission requirements route to the dedicated settings page")
        let domain = "com.vorssaint.tests.instant-spaces.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: domain) {
            defer { defaults.removePersistentDomain(forName: domain) }
            AppFeature.instantSpaces.enableOnFirstInstall(in: defaults, savedValues: [:])
            suite.expect(defaults.bool(forKey: DefaultsKey.instantSpacesKeyboard)
                && !defaults.bool(forKey: DefaultsKey.instantSpacesTrackpad),
                         "a first install enables keyboard switching and leaves swipes opt-in")
            defaults.set(false, forKey: DefaultsKey.instantSpacesKeyboard)
            defaults.set(true, forKey: DefaultsKey.instantSpacesTrackpad)
            AppFeature.instantSpaces.enableOnFirstInstall(
                in: defaults, savedValues: defaults.persistentDomain(forName: domain) ?? [:])
            suite.expect(!defaults.bool(forKey: DefaultsKey.instantSpacesKeyboard)
                && defaults.bool(forKey: DefaultsKey.instantSpacesTrackpad),
                         "reinstalling preserves a saved swipe-only configuration")
        }
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.instantSpaces(language)
            suite.expect([strings.title, strings.description, strings.keyboard, strings.keyboardCaption,
                          strings.trackpad, strings.trackpadCaption, strings.compatibility, strings.unavailable]
                .allSatisfy { !$0.isEmpty }, "Instant Spaces covers every field in \(language)")
        }
    }

    private static func keyboardRefresh(_ suite: TestSuite) {
        defer {
            SymbolicHotKeys.table = nil
            SymbolicHotKeys.reads = []
            ShortcutCapture.isCapturing = false
            CGEventSource.dragging = false
        }
        let host = KeyboardHost()
        func send(_ key: CGKeyCode, flags: CGEventFlags = .maskControl,
                  type: CGEventType = .keyDown) -> Bool {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown) else {
                suite.expect(false, "keyboard regression events can be created")
                return false
            }
            event.flags = flags
            return host.handle(proxy: OpaquePointer(bitPattern: 1)!, type: type, event: event) == nil
        }
        SymbolicHotKeys.table = host.shortcuts
        suite.expect(send(124) && host.actions == [.step(1)], "an enabled live shortcut is intercepted")
        suite.expect(send(124, type: .keyUp), "an intercepted shortcut consumes its release")

        SymbolicHotKeys.table = [LiveSystemShortcut(id: 81, keyCode: 124, flags: .maskControl, enabled: false)]
        suite.expect(!send(124) && host.actions.count == 1,
                     "disabling a shortcut takes effect without app activation or preference synchronization")
        suite.expect(!send(124, type: .keyUp), "a disabled shortcut's release retains native handling")

        SymbolicHotKeys.table = [LiveSystemShortcut(id: 81, keyCode: 47, flags: .maskAlternate, enabled: true)]
        suite.expect(!send(124), "remapping a shortcut immediately releases the previous binding")
        suite.expect(send(47, flags: .maskAlternate) && host.actions.count == 2,
                     "a new key and modifier binding works without app activation")
        _ = send(47, flags: .maskAlternate, type: .keyUp)
        SymbolicHotKeys.table = nil
        suite.expect(!send(124) && !send(47, flags: .maskAlternate) && host.actions.count == 2,
                     "a failed live lookup never falls back to a stale enabled shortcut")
        suite.expect(!SymbolicHotKeys.reads.isEmpty
            && SymbolicHotKeys.reads.allSatisfy { $0 == InstantSpacesSupport.shortcutIDs },
                     "keyboard matching reads only the known Space shortcut entries")

        SymbolicHotKeys.table = host.shortcuts
        host.claimedKeys.removeAll()
        let reads = SymbolicHotKeys.reads.count
        host.keyboardEnabled = false
        suite.expect(!send(124), "disabling keyboard switching preserves native handling")
        host.keyboardEnabled = true
        host.canRun = false
        suite.expect(!send(124), "an inactive or unavailable service preserves native handling")
        host.canRun = true
        ShortcutCapture.isCapturing = true
        suite.expect(!send(124), "shortcut capture preserves native handling")
        suite.expect(SymbolicHotKeys.reads.count == reads,
                     "inactive keyboard interception does not read the shortcut table")
        ShortcutCapture.isCapturing = false
        CGEventSource.dragging = true
        suite.expect(!send(124), "window dragging retains native handling with live shortcut matching")
        CGEventSource.dragging = false
        host.overview = true
        suite.expect(!send(124), "an overview retains native handling with live shortcut matching")
        host.overview = false
        suite.expect(!send(0, flags: []) && host.actions.count == 2,
                     "ordinary typing never starts Space navigation")
        let intercepted = send(124)
        SymbolicHotKeys.table = []
        suite.expect(intercepted && send(124, type: .keyUp),
                     "a claimed key's release stays paired when its binding changes while held")
    }
}
