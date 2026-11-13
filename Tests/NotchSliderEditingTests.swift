// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum NotchSliderEditingTests {
    static func run(_ suite: TestSuite) {
        SliderScrollRoutingTests.run(suite)
        NotchLevelTrackingTests.run(suite)
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

        func level(_ outcome: SliderScroll.Outcome) -> Double? {
            if case .move(let value) = outcome { return value }
            return nil
        }

        var pad = SliderScroll()
        suite.expect(pad.handle(.changed, dx: 0, dy: -40, precise: true, inverted: true,
                                timestamp: 0, current: 0.5, range: range) == .pass,
               "a trackpad scroll that began elsewhere keeps scrolling the list when a bar slides under the pointer")
        let first = level(pad.handle(.began, dx: 0, dy: -20, precise: true, inverted: true,
                                     timestamp: 1, current: 0.5, range: range)) ?? 0
        let second = level(pad.handle(.changed, dx: 0, dy: -20, precise: true, inverted: true,
                                      timestamp: 1.1, current: 0.5, range: range)) ?? 0
        suite.expect(first > 0.5 && second > first,
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

        var swipe = SliderScroll()
        swipe.verticalOnly = true
        suite.expect(swipe.handle(.began, dx: 0, dy: 0, precise: true, inverted: true,
                                  timestamp: 10, current: 0.5, range: range) == .hold
                     && swipe.handle(.changed, dx: -3, dy: 1, precise: true, inverted: true,
                                     timestamp: 10.1, current: 0.5, range: range) == .hold
                     && swipe.handle(.changed, dx: -20, dy: -2, precise: true, inverted: true,
                                     timestamp: 10.2, current: 0.5, range: range) == .pass,
               "a sideways swipe that starts on a fader goes to the strip without moving the level")
        suite.expect(swipe.handle(.changed, dx: 0, dy: -30, precise: true, inverted: true,
                                  timestamp: 10.3, current: 0.5, range: range) == .pass
                     && swipe.handle(.ended, dx: 0, dy: 0, precise: true, inverted: true,
                                     timestamp: 10.4, current: 0.5, range: range) == .pass
                     && swipe.handle(.none, dx: 0, dy: -4, precise: true, inverted: true,
                                     timestamp: 10.45, current: 0.5, range: range) == .pass
                     && swipe.handle(.momentum, dx: -30, dy: -5, precise: true, inverted: true,
                                     timestamp: 10.5, current: 0.5, range: range) == .pass,
               "the strip keeps a sideways swipe through drift, a vertical phaseless tail and momentum")
        suite.expect(swipe.handle(.none, dx: 0, dy: -4, precise: true, inverted: true,
                                  timestamp: 11, current: 0.5, range: range) == .move(0.52),
               "an independent precise wheel after the lift gap can adjust the fader again")

        var arriving = SliderScroll()
        arriving.verticalOnly = true
        suite.expect(arriving.handle(.ended, dx: 0, dy: 0, precise: true, inverted: true,
                                     timestamp: 12, current: 0.5, range: range) == .pass
                     && arriving.handle(.none, dx: 0, dy: -4, precise: true, inverted: true,
                                        timestamp: 12.1, current: 0.5, range: range) == .pass
                     && arriving.handle(.momentum, dx: 12, dy: 0, precise: true, inverted: true,
                                        timestamp: 12.7, current: 0.5, range: range) == .pass
                     && arriving.handle(.none, dx: 0, dy: -4, precise: true, inverted: true,
                                        timestamp: 12.8, current: 0.5, range: range) == .pass,
               "a fader scrolled under the pointer at lift or during momentum leaves the strip in control")

        var diagonal = SliderScroll()
        diagonal.verticalOnly = true
        _ = diagonal.handle(.began, dx: 0, dy: 0, precise: true, inverted: true,
                            timestamp: 20, current: 0.5, range: range)
        suite.expect(diagonal.handle(.changed, dx: 10, dy: -10, precise: true, inverted: true,
                                     timestamp: 20.1, current: 0.5, range: range) == .pass,
               "a swipe that is not clearly vertical scrolls the strip rather than changing the level")

        var wobble = SliderScroll()
        wobble.verticalOnly = true
        _ = wobble.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                          timestamp: 21, current: 0.5, range: range)
        var outcome = SliderScroll.Outcome.hold
        for sample in 0..<SliderScroll.maxPendingSamples {
            outcome = wobble.handle(.changed, dx: sample.isMultiple(of: 2) ? 1 : -1, dy: 0,
                                    precise: true, inverted: false, timestamp: 21.1, current: 0.5, range: range)
        }
        suite.expect(outcome == .pass && !wobble.isChoosingAxis,
                     "movement that keeps reversing below the threshold hands the buffered events to the strip")

        var fader = SliderScroll()
        fader.verticalOnly = true
        var late = SliderScroll()
        late.verticalOnly = true
        _ = late.handle(.began, dx: 0, dy: 0, precise: true, inverted: true,
                        timestamp: 30, current: 0.5, range: range)
        let without = level(late.handle(.changed, dx: 0, dy: -16, precise: true, inverted: true,
                                        timestamp: 30.1, current: 0.5, range: range)) ?? 0
        let held = fader.handle(.began, dx: 0, dy: -4, precise: true, inverted: true,
                                timestamp: 30, current: 0.5, range: range)
        let settled = level(fader.handle(.changed, dx: 0, dy: -16, precise: true, inverted: true,
                                         timestamp: 30.1, current: 0.5, range: range)) ?? 0
        suite.expect(held == .hold && without > 0.5 && settled > without,
               "a vertical swipe on a fader moves it by all its travel, including what it waited for")
        var straight = fader
        let still = fader.handle(.changed, dx: 40, dy: 0, precise: true, inverted: true,
                                 timestamp: 30.2, current: 0.6, range: range)
        _ = straight.handle(.changed, dx: 0, dy: 0, precise: true, inverted: true,
                            timestamp: 30.2, current: 0.6, range: range)
        let drifting = fader.handle(.changed, dx: 40, dy: -20, precise: true, inverted: true,
                                    timestamp: 30.3, current: 0.6, range: range)
        let upright = straight.handle(.changed, dx: 0, dy: -20, precise: true, inverted: true,
                                      timestamp: 30.3, current: 0.6, range: range)
        suite.expect(still == .hold && (level(drifting) ?? 0) > settled && drifting == upright,
               "a vertical swipe that drifts sideways keeps the fader but moves it only by its vertical travel")
        suite.expect(fader.handle(.ended, dx: 0, dy: 0, precise: true, inverted: true,
                                  timestamp: 30.4, current: 0.7, range: range) == .hold
                     && fader.handle(.momentum, dx: 30, dy: -30, precise: true, inverted: true,
                                     timestamp: 30.5, current: 0.7, range: range) == .hold,
               "the flick after a vertical swipe on a fader still neither moves it nor scrolls the strip")

        var tilt = SliderScroll()
        tilt.verticalOnly = true
        suite.expect(tilt.handle(.none, dx: 1, dy: 0, precise: false, inverted: false,
                                 timestamp: 40, current: 0.5, range: range) == .pass
                     && tilt.handle(.none, dx: 0, dy: 1, precise: false, inverted: false,
                                    timestamp: 41, current: 0.5, range: range) == .move(0.55),
               "a sideways wheel passes a fader to the strip while the vertical wheel still steps it")

        var bar = SliderScroll()
        suite.expect((level(bar.handle(.began, dx: -20, dy: 0, precise: true, inverted: false,
                                       timestamp: 50, current: 0.5, range: range)) ?? 0) > 0.5,
               "a horizontal bar still follows a sideways swipe at once")

        suite.expect(SliderScroll.gain(speed: 0) == SliderScroll.fineGain
                     && SliderScroll.gain(speed: SliderScroll.slowSpeed) == SliderScroll.fineGain
                     && SliderScroll.gain(speed: 1e9) == SliderScroll.fastGain
                     && SliderScroll.gain(speed: .infinity) == SliderScroll.fineGain,
               "a swipe's gain stays between its fine and fast limits, whatever the measured speed")
        let speeds = stride(from: 10.0, to: 3000, by: 10).map(SliderScroll.gain(speed:))
        suite.expect(zip(speeds, speeds.dropFirst()).allSatisfy { $0 <= $1 && $1 / $0 < 1.5 },
               "a swipe's gain only rises with speed and has no sudden jump")

        func moved(points: Double, events: Int, seconds: Double) -> Double {
            var scroll = SliderScroll()
            var level = 0.1
            _ = scroll.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                              timestamp: 0, current: level, range: 0...100)
            for event in 1...events {
                if case .move(let next) = scroll.handle(.changed, dx: 0, dy: points / Double(events), precise: true,
                                                        inverted: false, timestamp: seconds * Double(event) / Double(events),
                                                        current: level, range: 0...100) {
                    level = next
                }
            }
            return level - 0.1
        }
        let slow = moved(points: 20, events: 40, seconds: 2)
        let fast = moved(points: 20, events: 2, seconds: 0.016)
        suite.expect(slow > 0 && slow <= 20 * SliderScroll.pointStep * 100 * SliderScroll.fineGain * 1.01,
               "a slow swipe moves the level at its fine rate, for small adjustments (moved \(slow))")
        let far = moved(points: 150, events: 12, seconds: 0.1)
        suite.expect(fast > slow && far > 150 * SliderScroll.pointStep * 100,
               "the same travel moves further when fast, and a fast swipe covers more than the plain rate (slow \(slow), fast \(fast), far \(far))")
        suite.expect(far <= 150 * SliderScroll.pointStep * 100 * SliderScroll.fastGain,
               "a fast swipe's gain is capped, so a flick's reach is bounded (far \(far))")

        var boost = SliderScroll()
        boost.stop = 1
        var boosted = 0.9
        _ = boost.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                         timestamp: 0, current: boosted, range: 0...2)
        for event in 1...20 {
            if case .move(let next) = boost.handle(.changed, dx: 0, dy: 100, precise: true, inverted: false,
                                                   timestamp: Double(event) * 0.01, current: boosted, range: 0...2) {
                boosted = next
            }
        }
        suite.expect(boosted == 1 && boost.takeSnap(),
                     "a really fast swipe stops at the top of the normal range, with one click (level \(boosted))")
        suite.expect(!boost.takeSnap(), "a snap clicks only once")
        if case .move = boost.handle(.changed, dx: 0, dy: 3, precise: true, inverted: false,
                                     timestamp: 0.5, current: boosted, range: 0...2) {
            suite.expect(false, "a swipe caught as a flick stays caught as it slows")
        }
        func rising(from start: Double, points: Double, perSecond: Double) -> (level: Double, snapped: Bool) {
            var scroll = SliderScroll()
            scroll.stop = 1
            var value = start
            var snapped = false
            _ = scroll.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                              timestamp: 0, current: value, range: 0...2)
            let step = points >= 0 ? 2.0 : -2.0
            for event in 1...Int(abs(points) / 2) {
                if case .move(let next) = scroll.handle(.changed, dx: 0, dy: step, precise: true, inverted: false,
                                                        timestamp: Double(event) * 2 / perSecond,
                                                        current: value, range: 0...2) { value = next }
                if scroll.takeSnap() { snapped = true }
            }
            return (value, snapped)
        }
        let unhurried = rising(from: 0.97, points: 200, perSecond: 300)
        suite.expect(unhurried.snapped && unhurried.level > 1,
                     "a swipe below flick speed clicks at the top of the normal range and goes on (level \(unhurried.level))")
        let short = rising(from: 0.97, points: 40, perSecond: 40)
        let shorter = rising(from: 0.97, points: 10, perSecond: 40)
        suite.expect(shorter.level < 1 && shorter.level >= 0.98,
                     "a slow swipe can come to rest at 99% below the snap (level \(shorter.level))")
        suite.expect(short.snapped && short.level > 1 && short.level <= 1.05,
                     "a slow swipe past the snap can come to rest just above it, at 101% (level \(short.level))")
        let downward = rising(from: 1.03, points: -60, perSecond: 3000)
        suite.expect(downward.snapped && downward.level < 1,
                     "a fast swipe down clicks at the normal range and is not stopped there (level \(downward.level))")
        _ = boost.handle(.ended, dx: 0, dy: 0, precise: true, inverted: false,
                         timestamp: 1, current: boosted, range: 0...2)
        _ = boost.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                         timestamp: 2, current: boosted, range: 0...2)
        if case .move(let next) = boost.handle(.changed, dx: 0, dy: 100, precise: true, inverted: false,
                                               timestamp: 2.1, current: boosted, range: 0...2) { boosted = next }
        suite.expect(boosted > 1, "a new swipe from the top of the normal range can boost (level \(boosted))")
        _ = boost.handle(.ended, dx: 0, dy: 0, precise: true, inverted: false,
                         timestamp: 2.2, current: boosted, range: 0...2)
        var lowered = boosted
        _ = boost.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                         timestamp: 3, current: lowered, range: 0...2)
        for event in 1...20 {
            if case .move(let next) = boost.handle(.changed, dx: 0, dy: -100, precise: true, inverted: false,
                                                   timestamp: 3 + Double(event) * 0.01, current: lowered, range: 0...2) {
                lowered = next
            }
        }
        suite.expect(lowered < 1, "a swipe lowering a boosted level does not stop at the normal range (level \(lowered))")
        var notches = SliderScroll()
        notches.stop = 1
        suite.expect(notches.handle(.none, dx: 0, dy: 1, precise: false, inverted: false,
                                    timestamp: 0, current: 0.98, range: 0...2) == .move(1)
                     && notches.handle(.none, dx: 0, dy: 1, precise: false, inverted: false,
                                       timestamp: 1, current: 1, range: 0...2) == .move(1.05),
               "a wheel notch rests at the top of the normal range and the next one boosts, stepping by the normal range")

        var flick = SliderScroll()
        flick.stop = 1
        var flicked = 1.0
        _ = flick.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                         timestamp: 0, current: flicked, range: 0...2)
        for event in 1...5 {
            if case .move(let next) = flick.handle(.changed, dx: 0, dy: 40, precise: true, inverted: false,
                                                   timestamp: Double(event) * 0.008, current: flicked, range: 0...2) {
                flicked = next
            }
        }
        suite.expect(flicked > 1 && flicked < 2,
               "a fast swipe beyond the normal range cannot double the level (level \(flicked))")
        func boostRise(from start: Double, points: Int) -> Double {
            var scroll = SliderScroll()
            scroll.stop = 1
            var value = start
            _ = scroll.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                              timestamp: 0, current: value, range: 0...2)
            for event in 1...points {
                if case .move(let next) = scroll.handle(.changed, dx: 0, dy: 1, precise: true, inverted: false,
                                                        timestamp: Double(event) / 500, current: value, range: 0...2) {
                    value = next
                }
            }
            return value - start
        }
        suite.expect(boostRise(from: 1.01, points: 400) < boostRise(from: 1.01, points: 200) * 2,
               "one long swipe beyond the normal range slows as it goes on")
        suite.expect(abs(boostRise(from: 1.6, points: 40) - boostRise(from: 1.05, points: 40)) < 0.001,
               "a new swipe moves a boosted level just as easily wherever it starts, with no heavy top end")

        var pause = NotchSliderPause()
        pause.begin(at: 50)
        suite.expect(pause.step(to: 70, moved: 20, stop: 75) == .follow,
               "a drag short of the marker follows the pointer")
        suite.expect(pause.step(to: 76, moved: 6, stop: 75) == .hold && pause.holding,
               "a drag that crosses the marker holds there with the pointer on it")
        suite.expect(pause.step(to: 75, moved: 1, stop: 75) == .hold,
               "the hold lasts while the hand travels less than the pause")
        suite.expect(pause.step(to: 75, moved: 1.5, stop: 75) == .release(75.5) && !pause.holding,
               "past the pause the pointer is let go beyond the marker, on the side the hand moved")
        suite.expect(pause.step(to: 75, moved: 0, stop: 75) == .stay(75.5),
               "an event still reporting the held pointer leaves the level where it was let go")
        suite.expect(pause.step(to: 77, moved: 1.5, stop: 75) == .follow
                     && pause.step(to: 74, moved: -3, stop: 75) == .follow,
               "after the hold the level follows the pointer, and turning back close by does not hold again")
        suite.expect(pause.step(to: 68, moved: -6, stop: 75) == .follow
                     && pause.step(to: 76, moved: 8, stop: 75) == .hold,
               "once the pointer has moved well away, the next pass holds again")
        pause.begin(at: 80)
        suite.expect(pause.step(to: 74, moved: -6, stop: 75) == .hold
                     && pause.step(to: 75, moved: -3, stop: 75) == .release(74),
               "a hold works the same from above, letting go below the marker")
        pause.begin(at: 70)
        suite.expect(pause.step(to: 80, moved: 10, stop: 75) == .follow,
               "a move that overshoots the marker by the whole pause passes through")
        suite.expect(NotchSliderPause.arrived(from: 0.9, to: 1, stop: 1)
                     && NotchSliderPause.arrived(from: 1.2, to: 1, stop: 1)
                     && NotchSliderPause.arrived(from: 0.9, to: 1.2, stop: 1)
                     && NotchSliderPause.arrived(from: nil, to: 1, stop: 1)
                     && !NotchSliderPause.arrived(from: 1, to: 1, stop: 1)
                     && !NotchSliderPause.arrived(from: 1, to: 1.2, stop: 1)
                     && !NotchSliderPause.arrived(from: 0.5, to: 0.6, stop: 1)
                     && !NotchSliderPause.arrived(from: nil, to: 0.6, stop: 1),
               "a drag clicks once on reaching or jumping past the marker, not on leaving it")

        func leavingSteps(from start: Double, perEvent: Double, events: Int, perSecond: Double) -> [Double] {
            var scroll = SliderScroll()
            scroll.stop = 1
            var value = start
            var moves: [Double] = []
            _ = scroll.handle(.began, dx: 0, dy: 0, precise: true, inverted: false,
                              timestamp: 0, current: value, range: 0...2)
            for event in 1...events {
                if case .move(let next) = scroll.handle(.changed, dx: 0, dy: perEvent, precise: true, inverted: false,
                                                        timestamp: Double(event) * perEvent / perSecond,
                                                        current: value, range: 0...2), next > value {
                    moves.append(next - value)
                    value = next
                }
            }
            return moves
        }
        let steady = leavingSteps(from: 1, perEvent: 4, events: 40, perSecond: 500)
        suite.expect((steady.first ?? 1) <= 0.005 && (steady.prefix(8).max() ?? 1) <= 0.021,
               "a level leaving the rest goes on from 100% with no leap, even mid-swipe (steps \(steady.prefix(8)))")
        suite.expect(steady.count > 8 && steady[5] > steady[0],
               "the rate builds back up after the rest (steps \(steady.prefix(8)))")
        let large = leavingSteps(from: 1, perEvent: 30, events: 2, perSecond: 500)
        suite.expect((large.first ?? 1) <= 30 * SliderScroll.pointStep * SliderScroll.leavingGain,
               "one large event leaving the rest does not leap either (steps \(large))")

        var glide = NotchSliderGlide(drawn: 0)
        let reachedAtOnce = glide.advance(toward: 1, interval: 1.0 / 120, span: 1, reduceMotion: false)
        suite.expect(!reachedAtOnce && glide.drawn > 0 && glide.drawn < 1,
               "a scrolled bar moves part of the way each frame")
        var frames = 0
        while !glide.advance(toward: 1, interval: 1.0 / 120, span: 1, reduceMotion: false), frames < 240 { frames += 1 }
        suite.expect(glide.drawn == 1 && frames < 120, "a scrolled bar lands exactly on its level soon after (frames \(frames))")
        var instant = NotchSliderGlide(drawn: 0)
        suite.expect(instant.advance(toward: 1, interval: 1.0 / 120, span: 1, reduceMotion: true) && instant.drawn == 1,
               "with reduced motion a scrolled bar goes straight to its level")
    }
}
