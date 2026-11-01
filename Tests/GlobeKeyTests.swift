// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Drives the pure Globe key core — the press interpreter, the chord-aware
/// tracker and the gesture mapping — with synthetic timestamps. No event tap,
/// no defaults, no input source is touched.
enum GlobeKeyTests {
    static func run(_ suite: TestSuite) {
        interpreterTests(suite)
        machineTests(suite)
        mappingTests(suite)
    }

    // MARK: - The press interpreter (ported from NythralHome/globe)

    private static func interpreterTests(_ suite: TestSuite) {
        let timing = GlobePressTiming.default
        let timeout = timing.multiPressTimeout
        let long = timing.longPressDuration

        var interpreter = GlobePressInterpreter(timing: timing)
        suite.expect(interpreter.handle(.keyDown(0)) == [], "single: key down is silent")
        suite.expect(interpreter.handle(.keyUp(50_000_000)) == [], "single: key up is silent")
        suite.expect(interpreter.handle(.timer(50_000_000 + timeout - 1)) == [], "single: nothing before the timeout")
        suite.expect(interpreter.handle(.timer(50_000_000 + timeout)) == [.singlePress], "single: fires at the timeout")

        interpreter = GlobePressInterpreter(timing: timing)
        _ = interpreter.handle(.keyDown(0))
        _ = interpreter.handle(.keyUp(40_000_000))
        _ = interpreter.handle(.keyDown(120_000_000))
        _ = interpreter.handle(.keyUp(160_000_000))
        suite.expect(interpreter.handle(.timer(160_000_000 + timeout)) == [.doublePress],
                     "double: fires after the second press waits out the timeout")

        interpreter = GlobePressInterpreter(timing: timing)
        _ = interpreter.handle(.keyDown(0))
        _ = interpreter.handle(.keyUp(30_000_000))
        _ = interpreter.handle(.keyDown(100_000_000))
        _ = interpreter.handle(.keyUp(130_000_000))
        _ = interpreter.handle(.keyDown(200_000_000))
        suite.expect(interpreter.handle(.keyUp(240_000_000)) == [.triplePress],
                     "triple: fires the moment the third press releases")

        interpreter = GlobePressInterpreter(timing: timing)
        _ = interpreter.handle(.keyDown(0))
        suite.expect(interpreter.handle(.keyUp(long)) == [.longPress], "long: fires on release past the threshold")

        interpreter = GlobePressInterpreter(timing: timing)
        _ = interpreter.handle(.keyDown(0))
        suite.expect(interpreter.handle(.timer(long)) == [.longPress], "long: fires on its own deadline while held")
        suite.expect(interpreter.handle(.keyUp(long + 90_000_000)) == [], "long: the late release is silent")

        interpreter = GlobePressInterpreter(timing: timing)
        _ = interpreter.handle(.keyDown(0))
        _ = interpreter.handle(.keyUp(40_000_000))
        suite.expect(interpreter.handle(.keyDown(40_000_000 + timeout + 10_000_000)) == [.singlePress],
                     "a press past its timeout finalizes instead of joining the next press")

        suite.expect(GlobePressInterpreter.duration(from: 5, to: 3) == 0,
                     "duration never underflows on out-of-order timestamps")
    }

    // MARK: - The chord-aware tracker around it

    private static func machineTests(_ suite: TestSuite) {
        let timeout = GlobePressTiming.default.multiPressTimeout
        let long = GlobePressTiming.default.longPressDuration

        // A clean solo press.
        var machine = GlobeKeyMachine()
        suite.expect(machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0)) == [],
                     "solo: down is silent")
        suite.expect(machine.pendingDeadline == long, "solo: the long-press deadline is armed while held")
        suite.expect(machine.handle(.fnUp(timestamp: 50_000_000)) == [], "solo: up waits for company")
        suite.expect(machine.pendingDeadline == 50_000_000 + timeout, "solo: the multi-press deadline is armed")
        suite.expect(machine.tick(at: 50_000_000 + timeout) == [.singlePress],
                     "solo: single press fires at the deadline")

        // A double press stays two presses.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0))
        _ = machine.handle(.fnUp(timestamp: 40_000_000))
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 120_000_000))
        _ = machine.handle(.fnUp(timestamp: 160_000_000))
        suite.expect(machine.tick(at: 160_000_000 + timeout) == [.doublePress],
                     "two solo presses inside the window are a double press")

        // Globe+arrow: the chord cancels the press, and the tracker stays usable.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0))
        _ = machine.handle(.otherEvent)
        _ = machine.handle(.otherEvent)
        suite.expect(machine.handle(.fnUp(timestamp: 90_000_000)) == [], "chord: the release of a chorded press is silent")
        suite.expect(!machine.isPending, "chord: nothing stays pending")
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 200_000_000))
        _ = machine.handle(.fnUp(timestamp: 240_000_000))
        suite.expect(machine.tick(at: 240_000_000 + timeout) == [.singlePress],
                     "chord: the next clean press still works")

        // Globe pressed while a real modifier is held never becomes a gesture.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: true, timestamp: 0))
        suite.expect(machine.handle(.fnUp(timestamp: 80_000_000)) == [], "modified: the release is silent")
        suite.expect(!machine.isPending, "modified: nothing stays pending")

        // A media key while Globe is held counts as a chord.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0))
        _ = machine.handle(.otherEvent)
        suite.expect(machine.handle(.fnUp(timestamp: long + 10_000_000)) == [], "media chord: no long press either")

        // Typing between presses cancels the pending count instead of switching.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0))
        _ = machine.handle(.fnUp(timestamp: 40_000_000))
        suite.expect(machine.handle(.otherEvent) == [], "typing: the cancel itself is silent")
        suite.expect(!machine.isPending, "typing: the pending press is gone")
        suite.expect(machine.tick(at: 40_000_000 + timeout) == [],
                     "typing: the deadline fires empty")

        // A press held across a teardown must not leak into the next one.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0))
        machine.reset()
        suite.expect(!machine.fnIsDown, "reset: the held key is forgotten")
        suite.expect(machine.handle(.fnUp(timestamp: 100_000_000)) == [], "reset: the late release is ignored")
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 150_000_000))
        _ = machine.handle(.fnUp(timestamp: 190_000_000))
        suite.expect(machine.tick(at: 190_000_000 + timeout) == [.singlePress],
                     "reset: the tracker is ready for the next press")

        // A second down while the key is still down changes nothing.
        machine = GlobeKeyMachine()
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 0))
        _ = machine.handle(.fnDown(hasPrimaryModifiers: false, timestamp: 10_000_000))
        _ = machine.handle(.fnUp(timestamp: 50_000_000))
        suite.expect(machine.tick(at: 50_000_000 + timeout) == [.singlePress],
                     "duplicate down: one press is one press")
    }

    // MARK: - Gesture mapping and storage

    private static func mappingTests(_ suite: TestSuite) {
        suite.expect(GlobeKeyAction.sanitized(nil) == .none, "storage: nil is none")
        suite.expect(GlobeKeyAction.sanitized("") == .none, "storage: empty is none")
        suite.expect(GlobeKeyAction.sanitized("garbage") == .none, "storage: garbage is none")
        suite.expect(GlobeKeyAction.sanitized("inputSource:") == .none, "storage: a bare prefix is none")
        suite.expect(GlobeKeyAction.sanitized("inputSource:com.apple.keylayout.US")
            == .inputSource(id: "com.apple.keylayout.US"), "storage: a source id survives a round trip")
        suite.expect(GlobeKeyAction.sanitized("openKeyboardSettings") == .openKeyboardSettings,
                     "storage: the settings action survives a round trip")
        suite.expect(GlobeKeyAction.inputSource(id: "a:b").storageValue == "inputSource:a:b",
                     "storage: ids may contain the separator character")

        let mapping = GlobeGestureMapping(
            singlePress: .inputSource(id: "com.apple.keylayout.US"),
            doublePress: .none,
            triplePress: .none,
            longPress: .openKeyboardSettings
        )
        suite.expect(mapping.action(for: .singlePress) == .inputSource(id: "com.apple.keylayout.US"),
                     "mapping: the single press reads its own action")
        suite.expect(mapping.action(for: .longPress) == .openKeyboardSettings,
                     "mapping: the long press reads its own action")
        suite.expect(mapping.configuredSourceIDs == ["com.apple.keylayout.US"],
                     "mapping: only source actions are collected as source ids")
        suite.expect(GlobeGestureMapping.fallback.action(for: .singlePress) == .none,
                     "mapping: gestures start inert")
        suite.expect(GlobeGestureMapping.fallback.action(for: .longPress) == .openKeyboardSettings,
                     "mapping: the long press starts on the keyboard settings")
    }
}
