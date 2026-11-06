// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// Calls the extracted production tap body. Events are never posted to macOS;
/// platform actions and layout lookup are fixtures with observable effects.
enum KeyboardRemapTapTests {
    enum AppFeature {
        static let keyboardRemap = Feature()
        final class Feature { var isAvailable = true }
    }
    final class KeyboardRemapService {
        static let shared = KeyboardRemapService()
        var ownsNativeQuit = true
    }
    enum GlobalShortcut {
        static func layoutKeyLabel(for key: Int64, usesCommand: Bool) -> String? {
            switch key { case 12: "Q"; case 17: "T"; default: nil }
        }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        var isActive = true
    }
    final class NSWorkspace {
        static let shared = NSWorkspace()
        typealias OpenConfiguration = AppKit.NSWorkspace.OpenConfiguration
        var launches = 0
        func urlForApplication(withBundleIdentifier id: String) -> URL? { URL(fileURLWithPath: "/Applications/\(id).app") }
        func openApplication(at: URL, configuration: OpenConfiguration,
                             completionHandler: ((NSRunningApplication?, Error?) -> Void)?) {
            launches += 1
        }
    }
    class Fixture {
        var statusKey: String?
        var isRunning = true
        var config = KeyboardRemapTests.fullConfiguration
        var state = KeyboardRemapSupport.State()
        let translatedSource = CGEventSource(stateID: .hidSystemState)
        var tap: CFMachPort?
        var switches = 0
        var capsToggles = 0
        var repairs = 0
        func selectNextInputSource() { switches += 1 }
        func toggleCapsLock() { capsToggles += 1 }
        func scheduleRepair() { repairs += 1 }
        func syncWithPreferences() {}
    }
    static func run(_ suite: TestSuite) {
        let service = Service()
        func event(_ key: Int64, flags: CGEventFlags = [], down: Bool = true, repeatKey: Bool = false) -> CGEvent {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down)!
            e.flags = flags
            e.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
            e.setIntegerValueField(.eventSourceUserData, value: 0)
            e.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            return e
        }
        let quitProtection = QuitService()
        let blocked = event(12, flags: .maskCommand)
        suite.expect(quitProtection.shouldYieldToKeyboardRemap(type: .keyDown, event: blocked),
                     "Quit Protection yields bare Command-Q to active safe quit regardless of tap order")
        suite.expect(!quitProtection.shouldYieldToKeyboardRemap(type: .keyDown, event: event(12, flags: [.maskCommand, .maskShift])),
                     "Quit Protection retains ownership of extra-modifier shortcuts")
        suite.expect(!quitProtection.shouldYieldToKeyboardRemap(type: .keyUp, event: blocked),
                     "Quit Protection does not start an action on release")
        KeyboardRemapService.shared.ownsNativeQuit = false
        suite.expect(!quitProtection.shouldYieldToKeyboardRemap(type: .keyDown, event: blocked),
                     "Quit Protection resumes its own handling when safe quit is disabled")
        KeyboardRemapService.shared.ownsNativeQuit = true
        suite.expect(service.handle(type: .keyDown, event: blocked) == nil, "Real tap blocks Command-Q")
        suite.expect(service.handle(type: .keyUp, event: event(12, down: false)) == nil, "Real tap swallows blocked release")
        let quit = event(12, flags: .maskAlternate)
        suite.expect(service.handle(type: .keyDown, event: quit) != nil && quit.flags == .maskCommand,
                     "Real tap replaces Option with Command on quit down")
        suite.expect(quit.getIntegerValueField(.eventSourceUserData) == OwnKeyEvent.keyboardRemapMarker,
                     "Translated quit marker: \(quit.getIntegerValueField(.eventSourceUserData)) expected \(OwnKeyEvent.keyboardRemapMarker)")
        let quitUp = event(12, down: false)
        suite.expect(service.handle(type: .keyUp, event: quitUp) != nil && quitUp.flags == .maskCommand,
                     "Real tap preserves translated quit flags on up")
        suite.expect(service.handle(type: .keyDown, event: quit) != nil,
                     "Already translated quit passes without being blocked again")
        let caps = KeyboardRemapSupport.capsTriggerKey
        _ = service.handle(type: .keyDown, event: event(caps))
        _ = service.handle(type: .keyDown, event: event(caps, repeatKey: true))
        _ = service.handle(type: .keyUp, event: event(caps, down: false))
        suite.expect(service.switches == 1, "Real tap selects language once per Caps press")
        _ = service.handle(type: .keyDown, event: event(caps, flags: .maskShift))
        _ = service.handle(type: .keyUp, event: event(caps, down: false))
        suite.expect(service.capsToggles == 1 && service.switches == 1, "Real tap distinguishes Shift-Caps from language switch")
        NSWorkspace.shared.launches = 0
        _ = service.handle(type: .keyDown, event: event(17, flags: .maskAlternate))
        _ = service.handle(type: .keyDown, event: event(17, flags: .maskAlternate, repeatKey: true))
        _ = service.handle(type: .keyUp, event: event(17, down: false))
        suite.expect(NSWorkspace.shared.launches == 1, "Real tap launches Terminal once when held")
        let ordinary = event(8, flags: .maskCommand)
        suite.expect(service.handle(type: .keyDown, event: ordinary) != nil && ordinary.flags == .maskCommand,
                     "Real tap retains Command-C")
        service.isRunning = false
        suite.expect(service.handle(type: .keyDown, event: event(12, flags: .maskCommand)) != nil,
                     "Stopped service never blocks shortcuts")
    }
}
