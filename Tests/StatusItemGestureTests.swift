// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum StatusItemGestureTests {
    static func run(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let outside = CGPoint(x: 145, y: 300)
        let disabled = StatusItemGesture.Settings()
        let hold = StatusItemGesture.Settings(hold: .screenshot)
        let middle = StatusItemGesture.Settings(middle: .keepAwake)

        testLeftClicks(suite, point: point, disabled: disabled, hold: hold)
        testMiddleClick(suite, point: point, outside: outside, middle: middle)
        testPreferences(suite)
        testButtonGeometry(suite)
        testDragMargin(suite)
        testReleaseWatch(suite)
        StatusItemGestureAdapterTests.run(suite)
    }

    /// A click with no gesture assigned must stay immediate: the waiting that
    /// used to live here existed only for the double click, and it is gone.
    private static func testLeftClicks(_ suite: TestSuite, point: CGPoint,
                                       disabled: StatusItemGesture.Settings,
                                       hold: StatusItemGesture.Settings) {
        var click = StatusItemGesture()
        suite.expect(click.leftDown(at: point, time: 1).isEmpty,
                     "a press never opens the panel by itself")
        suite.expect(click.leftUp(at: point, time: 1.1, settings: disabled) == [.single(point)],
                     "with nothing assigned a click lands at once")
        suite.expect(click.deadline(disabled) == nil && !click.watchesForRelease,
                     "nothing is scheduled once the click is over")

        click = StatusItemGesture()
        _ = click.leftDown(at: point, time: 1)
        suite.expect(click.watchesForRelease,
                     "a press is watched: no event will report its release")
        suite.expect(click.deadline(hold) == 1.5, "the long press waits for its threshold")
        suite.expect(click.expired(at: 1.49, settings: hold).isEmpty
                     && click.phaseName == "pressed",
                     "the threshold is not crossed early")
        suite.expect(click.expired(at: 1.5, settings: hold).isEmpty
                     && click.phaseName == "held",
                     "reaching the threshold does not run the action while held")
        suite.expect(click.leftUp(at: point, time: 2, settings: hold) == [.quick(.screenshot)],
                     "the release commits exactly one long press")

        // A short press with a hold assigned is still an ordinary click.
        click = StatusItemGesture()
        _ = click.leftDown(at: point, time: 1)
        suite.expect(click.leftUp(at: point, time: 1.3, settings: hold) == [.single(point)],
                     "a short press stays a single click")

        // A release the watcher missed is still judged on its own timing.
        click = StatusItemGesture()
        _ = click.leftDown(at: point, time: 1)
        suite.expect(click.leftUp(at: point, time: 1.8, settings: hold) == [.quick(.screenshot)],
                     "a release past the threshold is a long press on its own")

        click = StatusItemGesture()
        _ = click.leftDown(at: point, time: 1)
        click.cancel()
        suite.expect(click.leftUp(at: point, time: 2, settings: hold).isEmpty
                     && !click.isActive,
                     "Esc, teardown or a changed preference cancels the release")
    }

    private static func testMiddleClick(_ suite: TestSuite, point: CGPoint, outside: CGPoint,
                                       middle: StatusItemGesture.Settings) {
        var click = StatusItemGesture()
        click.middleDown(at: point, settings: middle)
        suite.expect(click.phaseName == "middle" && !click.watchesForRelease,
                     "a middle click arrives with its own release from the tap")
        suite.expect(click.middleUp(at: point, settings: middle) == [.quick(.keepAwake)],
                     "the middle release commits once")

        click = StatusItemGesture()
        click.middleDown(at: point, settings: middle)
        click.moved(to: outside)
        suite.expect(click.middleUp(at: point, settings: middle).isEmpty,
                     "dragging a middle click away cancels it")

        click = StatusItemGesture()
        click.middleDown(at: point, settings: .init())
        suite.expect(click.middleUp(at: point, settings: .init()).isEmpty
                     && !click.isActive,
                     "with no middle action assigned nothing runs")
    }

    private static func testPreferences(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "vorss.tests.status-action")!
        defer { defaults.removePersistentDomain(forName: "vorss.tests.status-action") }
        suite.expect(StatusItemQuickAction.saved(DefaultsKey.statusItemMiddleClickAction,
                                                 in: defaults) == .none,
                     "a missing preference is off")
        defaults.set("futureAction", forKey: DefaultsKey.statusItemMiddleClickAction)
        suite.expect(StatusItemQuickAction.saved(DefaultsKey.statusItemMiddleClickAction,
                                                 in: defaults) == .none,
                     "an unknown saved action is off")
        let keys: Set<String> = [DefaultsKey.statusItemMiddleClickAction,
                                 DefaultsKey.statusItemLongPressAction]
        suite.expect(keys.isSubset(of: SettingsBackupSupport.exportKeys()),
                     "both assignments belong in settings backups")
        let saved = StatusItemGesture.Settings.saved(defaults: defaults)
        suite.expect(saved.middle == .none && !saved.isEnabled,
                     "an unusable saved value leaves both gestures off")
        defaults.set(StatusItemQuickAction.keepAwake.rawValue,
                     forKey: DefaultsKey.statusItemMiddleClickAction)
        let assigned = StatusItemGesture.Settings.saved(defaults: defaults)
        suite.expect(assigned.middle == .keepAwake && assigned.isEnabled,
                     "a saved assignment is read back and enables the gesture")
        suite.expect(AppLanguage.allCases.allSatisfy {
            !StatusItemQuickActionStrings.localized($0).title.isEmpty
                && !StatusItemQuickAction.soundMute.title($0).isEmpty
        }, "every supported language labels the choices")
    }

    /// The one branch that must never lose a click: when the button's frame is
    /// unknown, nothing is claimed and the caller runs the normal click.
    private static func testButtonGeometry(_ suite: TestSuite) {
        let frame = CGRect(x: 900, y: 760, width: 30, height: 24)
        let middle = CGPoint(x: 915, y: 772)
        let edge = CGPoint(x: 902, y: 762)
        let justOutside = CGPoint(x: 898, y: 772)
        suite.expect(StatusItemGesture.claims(middle, frame: frame)
                     && StatusItemGesture.claims(edge, frame: frame),
                     "a click inside the button is claimed")
        suite.expect(!StatusItemGesture.claims(justOutside, frame: frame)
                     && StatusItemGesture.claims(justOutside, frame: frame,
                                                 inset: StatusItemGesture.Settings.dragTolerance),
                     "a release just off the edge counts only with the drag tolerance")
        suite.expect(!StatusItemGesture.claims(middle, frame: nil)
                     && !StatusItemGesture.claims(middle, frame: .zero),
                     "an unknown or empty frame claims nothing, so the normal click still runs")

        let top = CGPoint(x: frame.midX, y: frame.maxY)
        suite.expect(StatusItemGesture.claims(top, frame: frame),
                     "the exact top edge remains a usable menu-bar hit target")
        suite.expect(!StatusItemGesture.claims(CGPoint(x: top.x, y: top.y + 0.01), frame: frame)
                     && !StatusItemGesture.claims(CGPoint(x: frame.minX - 0.01, y: top.y), frame: frame)
                     && !StatusItemGesture.claims(CGPoint(x: frame.maxX, y: top.y), frame: frame),
                     "including the top edge does not claim points above or neighboring horizontal slots")

        // Display coordinates are top-left; AppKit screens are bottom-left.
        let flipped = StatusItemGesture.appKitPoint(displayPoint: CGPoint(x: 1112, y: 20),
                                                    primaryHeight: 1169)
        suite.expect(flipped == CGPoint(x: 1112, y: 1149),
                     "a middle click in display coordinates lands on the icon")
    }

    /// A trackpad button held still for half a second still drifts several
    /// points. The original few-point box cancelled every long press there, so
    /// both the old failure and the fix are pinned here.
    private static func testDragMargin(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let hold = StatusItemGesture.Settings(hold: .screenshot)
        let margin = StatusItemGesture.dragMargin(iconWidth: 42)
        // A finger resting on a trackpad: real, and well past the old box.
        let resting = CGPoint(x: point.x + 12, y: point.y + 8)

        var strict = StatusItemGesture()
        _ = strict.leftDown(at: point, time: 1)
        strict.moved(to: resting)
        suite.expect(!strict.isActive,
                     "the old few-point box cancelled every hold on a trackpad")

        var tolerant = StatusItemGesture()
        _ = tolerant.leftDown(at: point, time: 1)
        tolerant.moved(to: resting, tolerance: margin)
        suite.expect(tolerant.isActive, "resting drift no longer drops the press")
        suite.expect(tolerant.leftUp(at: resting, time: 2, settings: hold,
                                     tolerance: margin) == [.quick(.screenshot)],
                     "a hold survives the drift of a finger resting on a trackpad")

        var away = StatusItemGesture()
        _ = away.leftDown(at: point, time: 1)
        away.moved(to: CGPoint(x: point.x + margin + 12, y: point.y), tolerance: margin)
        suite.expect(!away.isActive
                     && away.leftUp(at: point, time: 2, settings: hold,
                                    tolerance: margin).isEmpty,
                     "leaving the icon still cancels the hold permanently")
    }

    /// The status button reports its press and never its release, so the
    /// adapter watches the physical button. Which phases need that watch is the
    /// contract that keeps the long press working.
    private static func testReleaseWatch(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let settings = StatusItemGesture.Settings(middle: .keepAwake, hold: .screenshot)

        let idle = StatusItemGesture()
        suite.expect(!idle.watchesForRelease, "a gesture at rest watches nothing")

        var press = StatusItemGesture()
        _ = press.leftDown(at: point, time: 1)
        suite.expect(press.watchesForRelease,
                     "a press is watched: no event will report its release")
        _ = press.expired(at: 1.5, settings: settings)
        suite.expect(press.phaseName == "held" && press.watchesForRelease,
                     "a held press is still watched until the real release")

        var middle = StatusItemGesture()
        middle.middleDown(at: point, settings: settings)
        suite.expect(!middle.watchesForRelease,
                     "a middle click arrives with its own release from the tap")
    }
}
