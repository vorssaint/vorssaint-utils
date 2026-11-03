// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Runs the production button handler without installing a tap or posting
/// events. Only defaults, app exceptions and the outgoing actions are fixtures.
enum MouseSpacesGestureTapTests {
    enum StandardDefaults { static var standard = Foundation.UserDefaults() }

    final class Exceptions {
        static let shared = Exceptions()
        var excluded = false
        func excludesActionTarget(_ scope: MouseExceptionScope, at point: CGPoint) -> Bool { excluded }
    }

    final class Service {
        typealias UserDefaults = StandardDefaults
        typealias MouseAppExceptions = Exceptions
        static let replayedPressMarker: Int64 = 0x564F5253
        static var isCaptureActive = false
        var isCapturing = false
        var isCapturingSpacesGesture = false
        var isDraining = false
        var restartAfterDrain = false
        var isRunning = true
        var tap: CFMachPort?
        var mappings: [Int64: GlobalShortcut] = [:]
        var consumedButtons: Set<Int64> = []
        var sideWheelGesture = MouseButtonShortcutSupport.SideWheelGestureGate()
        var spacesButton: Int64?
        var spacesGesture: SpacesGesturePress?
        var actions: [MouseSpacesGestureSupport.Action] = []
        var replayed: [CGEvent] = []
        var custodyAtSync: Set<Int64> = []
        var onInputSeen: ((Int64) -> Void)?
        var lastInputSeen: Int64? {
            didSet {
                if let lastInputSeen { onInputSeen?(lastInputSeen) }
            }
        }

        func syncWithPreferences() {
            custodyAtSync = consumedButtons
            spacesButton = MouseButtonShortcutSupport.spacesGestureButton(UserDefaults.standard)
        }
        func tearDownTap(replayPendingSpacesPress: Bool = true) {}
        func flushSpacesPress(proxy: CGEventTapProxy?, at point: CGPoint?) {}
        func handleSideWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? { Unmanaged.passUnretained(event) }
        func post(_ shortcut: GlobalShortcut) {}
        func perform(_ action: MouseSpacesGestureSupport.Action) { actions.append(action) }
        func recordReplay(_ event: CGEvent) { replayed.append(event) }
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.mouse-spaces-tap.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: name)!
        StandardDefaults.standard = defaults
        defer {
            defaults.removePersistentDomain(forName: name)
            Exceptions.shared.excluded = false
            Service.isCaptureActive = false
        }
        defaults.set(true, forKey: AppFeature.mouseButtonShortcuts.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.mouseSpacesGestureEnabled)
        defaults.set(2, forKey: DefaultsKey.mouseSpacesGestureButton)

        func service() -> Service {
            let service = Service()
            service.syncWithPreferences()
            return service
        }
        func event(_ type: CGEventType, button: Int64 = 2, point: CGPoint = .zero) -> CGEvent {
            let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .center)!
            event.setIntegerValueField(.mouseEventButtonNumber, value: button)
            return event
        }
        func passes(_ type: CGEventType, through service: Service,
                    button: Int64 = 2, point: CGPoint = .zero) -> Bool {
            service.handle(proxy: nil, type: type, event: event(type, button: button, point: point)) != nil
        }

        suite.expect(MouseButtonShortcutSupport.claimsButton(2, defaults: defaults),
                     "an enabled middle-button Spaces binding claims the button")
        let tap = service()
        suite.expect(!passes(.otherMouseDown, through: tap) && passes(.otherMouseUp, through: tap),
                     "a short middle click holds its down and returns its release")
        suite.expect(tap.replayed.count == 1 && tap.replayed[0].type == .otherMouseDown
                && tap.replayed[0].getIntegerValueField(.mouseEventButtonNumber) == 2
                && tap.actions.isEmpty,
                     "a short middle click returns one middle down without switching Spaces")
        if let replayed = tap.replayed.first {
            suite.expect(tap.handle(proxy: nil, type: replayed.type, event: replayed) != nil
                    && tap.spacesGesture == nil,
                         "the returned middle down is not captured again")
        }

        let nudge = service()
        let releasePoint = CGPoint(x: MouseSpacesGestureSupport.spaceStep - 1, y: 0)
        suite.expect(!passes(.otherMouseDown, through: nudge)
                && !passes(.otherMouseDragged, through: nudge, point: releasePoint)
                && passes(.otherMouseUp, through: nudge, point: releasePoint)
                && nudge.actions.isEmpty && nudge.replayed.count == 1
                && nudge.replayed.first?.location == releasePoint,
                     "a middle drag below the threshold returns a complete click at the release point")

        let gestures: [(CGPoint, MouseSpacesGestureSupport.Action)] = [
            (CGPoint(x: -MouseSpacesGestureSupport.spaceStep, y: 0), .spaceLeft),
            (CGPoint(x: MouseSpacesGestureSupport.spaceStep, y: 0), .spaceRight),
            (CGPoint(x: 0, y: -MouseSpacesGestureSupport.overviewStep), .missionControl),
            (CGPoint(x: 0, y: MouseSpacesGestureSupport.overviewStep), .appExpose),
        ]
        for (point, action) in gestures {
            let drag = service()
            suite.expect(!passes(.otherMouseDown, through: drag)
                    && !passes(.otherMouseDragged, through: drag, point: point)
                    && !passes(.otherMouseUp, through: drag, point: point)
                    && drag.actions == [action] && drag.replayed.isEmpty
                    && drag.consumedButtons.isEmpty,
                         "middle-button \(action) consumes the complete drag without a stray click")
        }

        let capture = service()
        capture.setCapturing(true, forSpacesGesture: true)
        capture.onInputSeen = { _ in capture.setCapturing(false) }
        suite.expect(!passes(.otherMouseDown, through: capture)
                && capture.custodyAtSync.contains(2) && !capture.isCapturing
                && !capture.isCapturingSpacesGesture
                && !passes(.otherMouseUp, through: capture)
                && capture.actions.isEmpty && capture.replayed.isEmpty,
                     "ending Spaces capture during notification still consumes the whole middle click")
        capture.onInputSeen = nil

        let shortcutCapture = service()
        shortcutCapture.setCapturing(true)
        suite.expect(passes(.otherMouseDown, through: shortcutCapture)
                && shortcutCapture.lastInputSeen == 2
                && passes(.otherMouseUp, through: shortcutCapture),
                     "shortcut capture reports an unsupported middle click but leaves it whole")
        shortcutCapture.setCapturing(true, forSpacesGesture: true)
        suite.expect(!passes(.otherMouseDown, through: shortcutCapture)
                && !passes(.otherMouseUp, through: shortcutCapture),
                     "changing the active capture to Spaces accepts the middle button")
        shortcutCapture.setCapturing(false)

        Exceptions.shared.excluded = true
        let excluded = service()
        suite.expect(passes(.otherMouseDown, through: excluded)
                && passes(.otherMouseDragged, through: excluded, point: gestures[1].0)
                && passes(.otherMouseUp, through: excluded)
                && excluded.actions.isEmpty && excluded.replayed.isEmpty,
                     "an excluded app keeps its complete middle-button drag")
        Exceptions.shared.excluded = false

        defaults.set(true, forKey: DefaultsKey.mouseButtonShortcutsEnabled)
        defaults.set(["2": "command:11"], forKey: DefaultsKey.mouseButtonShortcuts)
        suite.expect(MouseButtonShortcutSupport.spacesGestureButton(defaults) == 2,
                     "an unsupported middle-button shortcut in imported defaults cannot block the drag")
        defaults.set(true, forKey: AppFeature.radialMenu.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.radialMenuEnabled)
        defaults.set(RadialMenuMouseTrigger.back.rawValue, forKey: DefaultsKey.radialMenuMouseButton)
        defaults.set(3, forKey: DefaultsKey.mouseSpacesGestureButton)
        suite.expect(MouseButtonShortcutSupport.spacesGestureButton(defaults) == nil
                && !MouseButtonShortcutSupport.claimsButton(3, defaults: defaults),
                     "the radial menu keeps its side button ahead of a saved Spaces binding")
        let wheel = service()
        suite.expect(passes(.otherMouseDown, through: wheel, button: 3)
                && passes(.otherMouseUp, through: wheel, button: 3),
                     "the Spaces tap leaves both halves of the radial menu's click alone")
        defaults.set(false, forKey: DefaultsKey.radialMenuEnabled)
        defaults.set(2, forKey: DefaultsKey.mouseSpacesGestureButton)
        defaults.set(false, forKey: DefaultsKey.mouseSpacesGestureEnabled)
        suite.expect(!MouseButtonShortcutSupport.claimsButton(2, defaults: defaults),
                     "a disabled Spaces gesture cannot claim the middle button")
        defaults.set(true, forKey: DefaultsKey.mouseSpacesGestureEnabled)
        defaults.set(false, forKey: AppFeature.mouseButtonShortcuts.availabilityKey)
        suite.expect(!MouseButtonShortcutSupport.claimsButton(2, defaults: defaults),
                     "uninstalling mouse button shortcuts releases the middle button")

        let payload = SettingsBackupSupport.payload(appVersion: "test", valueFor: defaults.object(forKey:))
        let restored = SettingsBackupSupport.sanitizedSettings(from: payload)
        suite.expect(restored?[DefaultsKey.mouseSpacesGestureButton] as? Int == 2
                && restored?[DefaultsKey.mouseSpacesGestureEnabled] as? Bool == true,
                     "the middle-button binding survives settings backup export and import")
    }
}
