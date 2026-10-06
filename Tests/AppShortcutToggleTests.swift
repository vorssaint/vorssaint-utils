// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// An app row's own key: the first press brings the app forward, and a press
/// on the app that is already in front puts it away again.
///
/// The three cases below are the ones the feature can get wrong while still
/// looking right on the first press. Each is driven through the same sequence
/// a person's hands produce, so the assertions describe presses rather than
/// the shape of the decision function.
enum AppShortcutToggleTests {
    /// One row's presses, replayed against a model of what the app is doing,
    /// so the checks read as "press, press, press" rather than as inputs.
    private struct Presses {
        private(set) var hidden = false
        private(set) var frontmost = false
        private(set) var count = 0
        /// Whether each press left the app away. A `.none` is a press that
        /// could not be attributed, which is how a launch reads here.
        private(set) var outcomes: [AppToggleAction] = []

        mutating func press(frontmost: Bool? = nil, hidden: Bool? = nil) {
            count += 1
            if let frontmost { self.frontmost = frontmost }
            if let hidden { self.hidden = hidden }
            let action = AppToggleSupport.action(forPress: count,
                                                 isFrontmost: self.frontmost,
                                                 isHidden: self.hidden)
            switch action {
            case .activate: self.hidden = false; self.frontmost = true
            case .hide: self.hidden = true; self.frontmost = false
            }
            outcomes.append(action)
        }
    }

    static func run(_ suite: TestSuite) {
        firstPressLaunches(suite)
        secondPressPutsItAway(suite)
        hiddenAppAlwaysComesBack(suite)
        rapidDoublePressNeverStrands(suite)
        pressOnABackgroundAppBringsItForward(suite)
    }

    /// The first press is a launch. There is nothing in front to hide, and a
    /// key that hid on the first press would make an app impossible to open.
    private static func firstPressLaunches(_ suite: TestSuite) {
        var presses = Presses()
        presses.press(frontmost: false, hidden: false)
        suite.expect(presses.outcomes == [.activate],
                     "the first press of an app row's key brings the app forward")
        suite.expect(!presses.hidden,
                     "an app that was never shown is not hidden by its first press")
    }

    /// The second press, on the app the first one brought forward, puts it
    /// away. This is the whole feature.
    private static func secondPressPutsItAway(_ suite: TestSuite) {
        var presses = Presses()
        presses.press(frontmost: false, hidden: false)
        presses.press()
        suite.expect(presses.outcomes == [.activate, .hide],
                     "a second press on the app now in front puts it away")
        suite.expect(presses.hidden,
                     "the app is left away after the press that meant to put it away")
    }

    /// The case the feature exists to get right. An app that is running but
    /// hidden is activated at every press count, including one high enough
    /// that a naive "press two means hide" rule would hide it a second time —
    /// which would leave an app with no key that brings it back.
    private static func hiddenAppAlwaysComesBack(_ suite: TestSuite) {
        for press in 1...12 {
            let action = AppToggleSupport.action(forPress: press,
                                                 isFrontmost: true,
                                                 isHidden: true)
            suite.expect(action == .activate,
                         "press \(press) on a hidden app brings it back rather than hiding it again")
        }
        // And the same through a replay, so the count is not what saves it.
        var presses = Presses()
        presses.press()
        presses.press()
        presses.press(frontmost: false, hidden: true)
        suite.expect(presses.outcomes == [.activate, .hide, .activate],
                     "a hidden app is recoverable after the press that hid it")
        suite.expect(!presses.hidden,
                     "the app that came back is not left away with no way to call it")
    }

    /// Two presses in quick succession, the second landing before the first
    /// has finished activating: the app is neither in front nor hidden yet.
    /// Hiding there would put away something that was never shown.
    private static func rapidDoublePressNeverStrands(_ suite: TestSuite) {
        var presses = Presses()
        presses.press(frontmost: false, hidden: false)
        presses.press(frontmost: false, hidden: false)
        suite.expect(presses.outcomes == [.activate, .activate],
                     "a second press before the app takes the front activates again instead of hiding")
        suite.expect(!presses.hidden,
                     "a double press on a row nobody has looked at yet leaves nothing hidden")

        // And the same double press once the app has actually arrived.
        var settled = Presses()
        settled.press(frontmost: false, hidden: false)
        settled.press(frontmost: true, hidden: false)
        settled.press(frontmost: false, hidden: true)
        suite.expect(settled.outcomes == [.activate, .hide, .activate],
                     "press, press, press alternates instead of latching")
        suite.expect(!settled.hidden,
                     "an odd number of presses leaves the app visible, never stranded away")
    }

    /// A press for an app the person is not looking at means "bring it here".
    /// Hiding it instead would swallow the press, and it is the case a person
    /// hits every time they press a key for a background app.
    private static func pressOnABackgroundAppBringsItForward(_ suite: TestSuite) {
        for press in 1...6 {
            let action = AppToggleSupport.action(forPress: press,
                                                 isFrontmost: false,
                                                 isHidden: false)
            suite.expect(action == .activate,
                         "press \(press) on a visible app that is not in front brings it forward")
        }
    }
}