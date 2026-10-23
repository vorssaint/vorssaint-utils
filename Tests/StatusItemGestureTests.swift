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
        testIconArea(suite)
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
                     && click.deadline(hold) == 1.5,
                     "the threshold is not crossed early")
        suite.expect(click.expired(at: 1.5, settings: hold).isEmpty
                     && click.deadline(hold) == nil && click.watchesForRelease,
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
                     "a right click, teardown or a changed preference cancels the release")

        // The button has already taken a left press in flight: a middle press
        // on the icon then must not leave that click with no outcome.
        for (held, expected) in [(false, StatusItemGesture.Result.single(point)), (true, .quick(.screenshot))] {
            let both = StatusItemGesture.Settings(middle: .keepAwake, hold: .screenshot)
            click = StatusItemGesture()
            _ = click.leftDown(at: point, time: 1)
            if held { _ = click.expired(at: 1.6, settings: both) }
            click.middleDown(settings: both)
            suite.expect(click.middleUp(at: point, settings: both).isEmpty
                         && click.leftUp(at: point, time: held ? 2 : 1.1, settings: both) == [expected],
                         "a left press keeps the icon over a middle press (held: \(held))")
        }
    }

    private static func testMiddleClick(_ suite: TestSuite, point: CGPoint, outside: CGPoint,
                                       middle: StatusItemGesture.Settings) {
        var click = StatusItemGesture()
        click.middleDown(settings: middle)
        suite.expect(click.isActive && !click.watchesForRelease,
                     "a middle click arrives with its own release from the tap")
        suite.expect(click.middleUp(at: point, settings: middle) == [.quick(.keepAwake)],
                     "the middle release commits once")

        // The tap reports no drags, only the release: a middle click is
        // judged by where it comes up, against the same area as a hold.
        let icon = StatusItemGesture.hitArea(of: CGRect(x: 105, y: 288, width: 30, height: 24))!
        click = StatusItemGesture()
        click.middleDown(settings: middle, within: icon)
        suite.expect(click.middleUp(at: outside, settings: middle).isEmpty && !click.isActive,
                     "a middle release dragged off the icon cancels it")

        click = StatusItemGesture()
        click.middleDown(settings: .init())
        suite.expect(click.middleUp(at: point, settings: .init()).isEmpty
                     && !click.isActive,
                     "with no middle action assigned nothing runs")
    }

    private static func testPreferences(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "vorss.tests.status-action")!
        defer { defaults.removePersistentDomain(forName: "vorss.tests.status-action") }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
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
        defaults.set(false, forKey: AppFeature.keepAwake.availabilityKey)
        let uninstalled = StatusItemGesture.Settings.saved(defaults: defaults)
        suite.expect(uninstalled.middle == .none && !uninstalled.isEnabled && !uninstalled.needsAccessibility
                     && defaults.string(forKey: DefaultsKey.statusItemMiddleClickAction)
                        == StatusItemQuickAction.keepAwake.rawValue,
                     "an uninstalled target runs nothing and keeps its saved assignment")
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            !StatusItemQuickActionStrings.localized(language).title.isEmpty
                && StatusItemQuickAction.allCases.allSatisfy { !$0.title(language).isEmpty }
        }, "every supported language labels the choices")
        suite.expect(StatusItemQuickAction.allCases.allSatisfy { $0.title(.ja) != $0.title(.enUS) },
                     "every choice is labelled in the language asked for, not the app's")
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
                     && StatusItemGesture.claims(justOutside, frame: StatusItemGesture.hitArea(of: frame)),
                     "a release just off the edge counts only within the icon's hit area")
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
    /// points, and a box around the press point cancelled every long press
    /// there. "Drag away" means leaving the icon, whatever the item's width.
    private static func testIconArea(_ suite: TestSuite) {
        let hold = StatusItemGesture.Settings(hold: .screenshot)
        let icon = CGRect(x: 105, y: 288, width: 30, height: 24)
        let area = StatusItemGesture.hitArea(of: icon)!
        let point = CGPoint(x: 120, y: 300)

        var resting = StatusItemGesture()
        _ = resting.leftDown(at: point, time: 1, within: area)
        resting.moved(to: CGPoint(x: 132, y: 308))
        suite.expect(resting.isActive && resting.leftUp(at: CGPoint(x: 132, y: 308), time: 2, settings: hold)
                        == [.quick(.screenshot)],
                     "a hold survives the drift of a finger resting on a trackpad")

        var edge = StatusItemGesture()
        _ = edge.leftDown(at: CGPoint(x: 106, y: 300), time: 1, within: area)
        suite.expect(edge.leftUp(at: CGPoint(x: 134, y: 300), time: 1.1, settings: hold)
                        == [.single(CGPoint(x: 134, y: 300))],
                     "a click that slides across a narrow icon is still a click on it")

        var away = StatusItemGesture()
        _ = away.leftDown(at: point, time: 1, within: area)
        away.moved(to: CGPoint(x: area.maxX + 1, y: point.y))
        suite.expect(!away.isActive && away.leftUp(at: point, time: 2, settings: hold).isEmpty,
                     "leaving the icon cancels the hold for good")

        // A countdown or metric in the title widens the item; the slack below
        // the menu bar must not grow with it.
        let wide = StatusItemGesture.hitArea(of: CGRect(x: 600, y: 776, width: 120, height: 24))!
        var below = StatusItemGesture()
        _ = below.leftDown(at: CGPoint(x: 660, y: 788), time: 1, within: wide)
        _ = below.expired(at: 1.6, settings: hold)
        suite.expect(below.leftUp(at: CGPoint(x: 660, y: 738), time: 2, settings: hold).isEmpty,
                     "a release well below a wide item runs nothing")
        suite.expect(StatusItemGesture.hitArea(of: nil) == nil && StatusItemGesture.hitArea(of: .zero) == nil,
                     "an unknown icon has no area to stay in")
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
        suite.expect(press.deadline(settings) == nil && press.watchesForRelease,
                     "a held press is still watched until the real release")

        var middle = StatusItemGesture()
        middle.middleDown(settings: settings)
        suite.expect(!middle.watchesForRelease,
                     "a middle click arrives with its own release from the tap")
    }
}
