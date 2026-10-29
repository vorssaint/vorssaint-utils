// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum NotchSliderEditingTests {
    static func run(_ suite: TestSuite) {
        SliderScrollRoutingTests.run(suite)
        var editing = NotchSliderEditing()
        var position = 32.0
        var callbacks: [Bool] = []
        var commits: [Double] = []
        let changed: (Bool) -> Void = { isEditing in
            callbacks.append(isEditing)
            if !isEditing { commits.append(position) }
        }
        editing.valueChanged({ position = 75 }, onEditingChanged: changed)
        suite.expect(position == 75 && commits == [75] && callbacks == [true, false],
               "an accessibility value action commits the new playback position without requiring mouse tracking")
        editing.valueChanged({ position = 76 }, onEditingChanged: changed)
        editing.valueChanged({ position = 77 }, onEditingChanged: changed)
        suite.expect(commits == [75, 76, 77] && callbacks == [true, false, true, false, true, false],
               "consecutive keyboard changes each complete their own edit after updating the bound value")

        callbacks = []; commits = []
        editing.trackingChanged(true, onEditingChanged: changed)
        for value in 0...100 {
            editing.valueChanged({ position = Double(value) }, onEditingChanged: changed)
        }
        suite.expect(position == 100 && callbacks == [true] && commits.isEmpty,
               "continuous mouse movement updates the thumb without submitting a seek for every sample")
        editing.trackingChanged(false, onEditingChanged: changed)
        suite.expect(callbacks == [true, false] && commits == [100],
               "finishing a drag commits its final bound position exactly once")
        editing.trackingChanged(false, onEditingChanged: changed)
        suite.expect(commits == [100], "a repeated native tracking-end callback cannot submit the drag again")
        editing.valueChanged({ position = 110 }, onEditingChanged: changed)
        suite.expect(commits == [100, 110] && callbacks.suffix(2) == [true, false],
               "keyboard or accessibility input after a drag still receives a complete edit cycle")

        var levels: [Double] = []
        editing.valueChanged({ levels.append(0.25) }, onEditingChanged: nil)
        editing.trackingChanged(true, onEditingChanged: nil)
        editing.valueChanged({ levels.append(0.5) }, onEditingChanged: nil)
        editing.trackingChanged(false, onEditingChanged: nil)
        editing.valueChanged({ levels.append(0.75) }, onEditingChanged: nil)
        suite.expect(levels == [0.25, 0.5, 0.75],
               "volume and brightness controls without an editing callback retain exactly one value write per action")

        let easing = NotchSliderEasing(from: 0.8, to: 0.6, start: 10)
        let midway = easing.value(at: 10 + NotchSliderEasing.duration / 2)
        let end = easing.value(at: 10 + NotchSliderEasing.duration)
        suite.expect(easing.value(at: 10) == (0.8, false) && !midway.done && midway.value < 0.7 && midway.value > 0.6
                     && end == (0.6, true) && easing.value(at: 99) == (0.6, true),
               "a level moved from outside the slider eases out from where it was drawn and lands exactly on the new one")
        suite.expect(NotchSliderEasing.eases(enabled: true, onScreen: true, reduceMotion: false, tracking: false)
                     && !NotchSliderEasing.eases(enabled: true, onScreen: false, reduceMotion: false, tracking: false)
                     && !NotchSliderEasing.eases(enabled: true, onScreen: true, reduceMotion: true, tracking: false)
                     && !NotchSliderEasing.eases(enabled: true, onScreen: true, reduceMotion: false, tracking: true)
                     && !NotchSliderEasing.eases(enabled: false, onScreen: true, reduceMotion: false, tracking: false),
               "only a level slider on screen, not dragged and without reduced motion eases; a page that opens starts at its level")

        let range = 0.0...1.0
        var wheel = SliderScroll()
        suite.expect(wheel.handle(.none, dx: 0, dy: 1, precise: false, inverted: false,
                                  timestamp: 0, current: 0.5, range: range) == .move(0.55)
                     && wheel.handle(.none, dx: 0, dy: -3, precise: false, inverted: false,
                                     timestamp: 1, current: 0.55, range: range) == .move(0.5)
                     && wheel.handle(.none, dx: 0, dy: -1, precise: false, inverted: true,
                                     timestamp: 2, current: 0.5, range: range) == .move(0.55),
               "a wheel notch moves the level one step up or down, whatever the wheel's acceleration or natural scrolling")
        suite.expect(wheel.handle(.none, dx: 0, dy: 1, precise: false, inverted: false,
                                  timestamp: 3, current: 0.98, range: range) == .move(1)
                     && wheel.handle(.none, dx: 0, dy: 1, precise: false, inverted: false,
                                     timestamp: 4, current: 2, range: 0...4) == .move(2.2),
               "a scrolled level stops at the end of its range and steps by the range it spans")
        suite.expect(SliderScroll.step(dx: 10, dy: 0, precise: true, inverted: true) > 0
                     && SliderScroll.step(dx: -10, dy: 0, precise: true, inverted: false) > 0
                     && SliderScroll.step(dx: 0, dy: -10, precise: true, inverted: true) > 0
                     && SliderScroll.step(dx: 2, dy: -10, precise: true, inverted: true) == 10 * SliderScroll.pointStep,
               "fingers moving up or right raise the level along the gesture's main axis")

        var pad = SliderScroll()
        suite.expect(pad.handle(.changed, dx: 0, dy: -40, precise: true, inverted: true,
                                timestamp: 0, current: 0.5, range: range) == .pass,
               "a trackpad scroll that began elsewhere keeps scrolling the list when a bar slides under the pointer")
        suite.expect(pad.handle(.began, dx: 0, dy: -20, precise: true, inverted: true,
                                timestamp: 1, current: 0.5, range: range) == .move(0.6)
                     && pad.handle(.changed, dx: 0, dy: -20, precise: true, inverted: true,
                                   timestamp: 1.1, current: 0.5, range: range) == .move(0.7),
               "a gesture that starts on the bar follows the fingers from where it is heading, ahead of a level that settles late")
        suite.expect(pad.handle(.ended, dx: 0, dy: 0, precise: true, inverted: true,
                                timestamp: 1.2, current: 0.7, range: range) == .hold
                     && pad.handle(.none, dx: 0, dy: -30, precise: true, inverted: true,
                                   timestamp: 1.3, current: 0.7, range: range) == .hold
                     && pad.handle(.momentum, dx: 0, dy: -30, precise: true, inverted: true,
                                   timestamp: 1.4, current: 0.7, range: range) == .hold,
               "the flick after a gesture on the bar neither moves the level nor scrolls the list")
        suite.expect(pad.handle(.changed, dx: 0, dy: -30, precise: true, inverted: true,
                                timestamp: 5, current: 0.7, range: range) == .pass
                     && pad.handle(.momentum, dx: 0, dy: -30, precise: true, inverted: true,
                                   timestamp: 5.1, current: 0.7, range: range) == .pass,
               "once another gesture scrolls past the bar, its momentum goes back to the list")
    }
}
