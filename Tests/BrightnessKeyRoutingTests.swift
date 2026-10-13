// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import os

/// Runs both production key callbacks against changing display routes. No
/// event is posted and no real display, pointer or preference is touched.
enum BrightnessKeyRoutingTests {
    final class CGEvent {
        var flags: CGEventFlags = []
        var marker: Int64 = 0
        let location = CGPoint(x: 50, y: 50)
        let keyCode: Int
        let data1: Int
        let repeated: Bool
        init(down: Bool, repeated: Bool = false, increase: Bool = true) {
            keyCode = increase ? 144 : 145
            let mediaCode = increase ? 2 : 3
            let state = down ? 10 : 11
            data1 = (mediaCode << 16) | (state << 8) | (repeated ? 1 : 0)
            self.repeated = repeated
        }
        func getIntegerValueField(_ field: CGEventField) -> Int64 {
            switch field {
            case .keyboardEventKeycode: return Int64(keyCode)
            case .keyboardEventAutorepeat: return repeated ? 1 : 0
            default: return marker
            }
        }
        static func tapEnable(tap: Int, enable: Bool) {}
    }
    struct NSEvent {
        struct Subtype { let rawValue = 8 }
        static let mouseLocation = NSPoint(x: 50, y: 50)
        let subtype = Subtype()
        let modifierFlags: AppKit.NSEvent.ModifierFlags = []
        let data1: Int
        init?(cgEvent: CGEvent) { data1 = cgEvent.data1 }
    }
    final class NSScreen {
        static var current: UInt32 = 1
        static var screens: [NSScreen] { [NSScreen()] }
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        var deviceDescription: [NSDeviceDescriptionKey: Any] {
            [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: Self.current)]
        }
    }
    final class UserDefaults {
        static let standard = UserDefaults()
        var overlay = false
        func bool(forKey key: String) -> Bool {
            key == DefaultsKey.brightnessKeysEnabled || overlay
        }
    }
    enum NotchSupport {
        enum Kind { case brightness }
        static func routes(_ kind: Kind) -> Bool { false }
    }
    final class NotchService {
        static let shared = NotchService()
        let showsSystemFeedback = false
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        let isActive = true
    }
    enum BrightnessBridge {
        static let setBrightness: ((UInt32, Float) -> Int32)? = { _, _ in 0 }
    }
    final class Queue { func async(execute work: () -> Void) { work() } }
    enum DispatchQueue { static let main = Queue() }

    class Fixture {
        struct Route { var method: Method }
        enum Method { case system, ddc }
        struct Display { let id: UInt32; let isBuiltIn: Bool; let brightness: Double }
        static let log = Logger(subsystem: "vorssaint.tests", category: "brightness-keys")
        static var forwardedSteps = 0
        var running = true
        var keyTap: Int?
        var functionKeyTap: Int?
        var shouldStopFunctionKeyThread = false
        var inputTapsSuspended = false
        var keyOwnership = BrightnessSupport.BrightnessKeyOwnership()
        var swallowedMediaKeys = Set<Bool>()
        var swallowedKeyCodes = Set<Int>()
        var keyStep = BrightnessSupport.KeyStep.standard
        var functionKeyStep = BrightnessSupport.KeyStep.standard
        var functionKeysAdjustBrightness = true
        var functionKeysFollowPointer = true
        var functionKeySystemTarget: UInt32? = 1
        var overlayReplacesNativeOSD = false
        var brightnessOSDSupported = true
        let stateLock = NSLock()
        let keyThreadLock = NSLock()
        let displays = [Display(id: 1, isBuiltIn: true, brightness: 0.5),
                        Display(id: 2, isBuiltIn: false, brightness: 0.5)]
        var systemKeyTarget: Display? { displays.first }
        var routes: [UInt32: Route] = [1: Route(method: .system), 2: Route(method: .system)]
        var steps = 0
        func AXIsProcessTrusted() -> Bool { true }
        func tapsAreSuspended() -> Bool { inputTapsSuspended }
        func syncKeyTap() {}
        func scheduleKeyboardLightNotice() {}
        static func postSystemQuarterSteps(increase: Bool, count: Int) { forwardedSteps += count }
        func currentSystemBrightness(for id: UInt32, fallback: Double?) -> Double? { fallback }
        func setBrightness(_ value: Double, for id: UInt32, showOSD: Bool, smooth: Bool) { steps += 1 }
        func step(_ id: UInt32, method: Method, delta: Double, showOSD: Bool) { steps += 1 }
        func applyKeyStep(_ press: BrightnessSupport.BrightnessKeyEvent, to id: UInt32, method: Method) {
            steps += 1
        }
        func CGDisplayIsBuiltin(_ id: UInt32) -> UInt32 { id == 1 ? 1 : 0 }
        func CGGetDisplaysWithPoint(_ point: CGPoint, _ max: UInt32,
                                   _ display: inout UInt32, _ count: inout UInt32) -> CGError {
            display = NSScreen.current
            count = 1
            return .success
        }
    }

    static func run(_ suite: TestSuite) {
        for mediaKey in [true, false] {
            func service() -> Service {
                NSScreen.current = 1
                UserDefaults.standard.overlay = false
                Service.forwardedSteps = 0
                return Service()
            }
            func press(_ host: Service, down: Bool = true, repeated: Bool = false,
                       increase: Bool = true, flags: CGEventFlags = []) -> Bool {
                let event = CGEvent(down: down, repeated: repeated, increase: increase)
                event.flags = flags
                let result = mediaKey
                    ? host.handleKeyEvent(type: CGEventType(rawValue: 14)!, event: event)
                    : host.routeFunctionKey(type: down ? .keyDown : .keyUp, event: event)
                return result == nil
            }
            let kind = mediaKey ? "media" : "plain"
            let native = service()
            suite.expect(!press(native), "\(kind): built-in brightness starts with macOS")
            NSScreen.current = 2
            suite.expect(!press(native, repeated: true) && !press(native, down: false)
                         && native.steps == 0,
                         "\(kind): moving to an external display never steals a native repeat or release")
            suite.expect(press(native) && native.steps == 1,
                         "\(kind): a fresh external-display press can be handled")
            NSScreen.current = 1
            suite.expect(press(native, repeated: true) && press(native, down: false)
                         && native.steps == 1,
                         "\(kind): returning to the built-in display cannot leak a handled repeat or release")

            let wake = service()
            NSScreen.current = 2
            wake.routes[2] = nil
            suite.expect(!press(wake), "\(kind): a missing route leaves the press native")
            wake.routes[2] = Fixture.Route(method: .system)
            suite.expect(!press(wake, repeated: true) && !press(wake, down: false) && wake.steps == 0,
                         "\(kind): rebuilding a wake route preserves the native key's remaining events")

            let disconnect = service()
            NSScreen.current = 2
            suite.expect(press(disconnect), "\(kind): external adjustment starts before disconnect")
            disconnect.routes[2] = nil
            suite.expect(press(disconnect, repeated: true) && press(disconnect, down: false)
                         && disconnect.steps == 1,
                         "\(kind): losing a route stops adjustment without leaking half a native key")

            let visibility = service()
            suite.expect(!press(visibility), "\(kind): a native press begins with the overlay off")
            UserDefaults.standard.overlay = true
            visibility.overlayReplacesNativeOSD = true
            suite.expect(!press(visibility, repeated: true) && !press(visibility, down: false),
                         "\(kind): showing replacement feedback cannot take a native held key")
            suite.expect(press(visibility), "\(kind): fresh presses can use replacement feedback")
            UserDefaults.standard.overlay = false
            visibility.overlayReplacesNativeOSD = false
            suite.expect(press(visibility, repeated: true) && press(visibility, down: false),
                         "\(kind): hiding replacement feedback cannot leak a handled key")

            let unseen = service()
            NSScreen.current = 2
            suite.expect(!press(unseen, repeated: true) && !press(unseen, down: false),
                         "\(kind): a tap installed during a press leaves its repeat and release native")
            suite.expect(press(unseen), "\(kind): a fresh press is handled before a lost release")
            NSScreen.current = 1
            suite.expect(!press(unseen) && !press(unseen, down: false),
                         "\(kind): a fresh native press clears a previously lost handled release")

            let modified = service()
            NSScreen.current = 2
            suite.expect(!press(modified, flags: .maskAlternate)
                         && !press(modified, repeated: true) && !press(modified, down: false),
                         "\(kind): releasing Option cannot steal a system settings shortcut")
            suite.expect(press(modified) && press(modified, repeated: true, flags: .maskCommand)
                         && press(modified, down: false, flags: .maskCommand),
                         "\(kind): adding a modifier cannot leak events from a handled press")

            let fine = service()
            fine.keyStep = .quarter
            fine.functionKeyStep = .quarter
            suite.expect(press(fine) && Service.forwardedSteps == 1,
                         "\(kind): finer native steps forward a complete synthetic press")
            fine.keyStep = .standard
            fine.functionKeyStep = .standard
            suite.expect(press(fine, repeated: true) && press(fine, down: false)
                         && Service.forwardedSteps == 1,
                         "\(kind): changing step size still consumes the original release")

            let both = service()
            NSScreen.current = 2
            suite.expect(press(both) && press(both, increase: false)
                         && press(both, down: false) && press(both, down: false, increase: false),
                         "\(kind): opposite brightness keys keep independent releases")
        }
    }
}
