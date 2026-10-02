// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum NotchGestureTests {
    static func run(_ suite: TestSuite) {
        calendarPaging(suite)
        nativeInteractionContracts(suite)
        suite.expect(NotchGestureSupport.allowsVertical(expanded: true, inHeader: false,
                                                       musicSurface: true, control: false, scroll: false),
               "the music surface can close the expanded island without aiming at its header")
        suite.expect(!NotchGestureSupport.allowsVertical(expanded: true, inHeader: false,
                                                        musicSurface: true, control: false, scroll: true)
               && !NotchGestureSupport.allowsVertical(expanded: true, inHeader: false,
                                                     musicSurface: true, control: true, scroll: false)
               && !NotchGestureSupport.allowsVertical(expanded: true, inHeader: false,
                                                     musicSurface: false, control: false, scroll: false),
               "lyrics, queues, controls and other modules retain their own vertical input")
        suite.expect(NotchGestureSupport.allowsVertical(expanded: false, inHeader: false,
                                                       musicSurface: false, control: false, scroll: false)
               && NotchGestureSupport.allowsVertical(expanded: true, inHeader: true,
                                                    musicSurface: false, control: false, scroll: false),
               "the resting island and expanded header keep their vertical gestures")
        suite.expect(NotchSupport.compactActivity(timer: true, downloads: true, music: true) == .timer
               && NotchSupport.compactActivity(timer: false, downloads: true, music: true) == .downloads
               && NotchSupport.compactActivity(timer: false, downloads: false, agents: true,
                                               calendar: true, music: true) == .agents
               && NotchSupport.compactActivity(timer: false, downloads: false,
                                               calendar: true, music: true) == .calendar
               && NotchSupport.compactActivity(timer: false, downloads: false, music: true) == .music
               && NotchSupport.compactActivity(timer: false, downloads: false, music: false) == nil,
               "rendering and gestures use the same compact activity priority")
        suite.expect(!NotchSupport.gestureIsOverHeader(expanded: false, peeking: false, fromTop: 20, safeTop: 14)
               && NotchSupport.gestureIsOverHeader(expanded: true, peeking: false, fromTop: 20, safeTop: 14)
               && NotchSupport.gestureIsOverHeader(expanded: false, peeking: true, fromTop: 20, safeTop: 14),
               "a notchless compact strip has no invisible header blocking its lower half")
        var gesture = NotchGestureSupport()
        var time = 1.0
        func feed(_ x: Double = 0, _ y: Double = 0, began: Bool = false,
                  ended: Bool = false, momentum: Bool = false, precise: Bool = true, phased: Bool = true,
                  vertical: Bool = true, horizontal: Bool = true, expanded: Bool = false) -> NotchGestureSupport.Action? {
            time += 0.01
            return gesture.handle(x: x, y: y, timestamp: time, began: began, ended: ended,
                                  momentum: momentum, precise: precise, hasPhase: phased, allowVertical: vertical,
                                  allowHorizontal: horizontal, expanded: expanded)
        }
        suite.expect(feed(0, 5, began: true) == nil && feed(0, 10) == nil && feed(0, 10) == .open,
               "small vertical movement accumulates into one intentional opening")
        suite.expect(feed(0, -100, expanded: true) == nil,
               "the remainder of an opening gesture cannot immediately close the notch")
        suite.expect(feed(0, 0, ended: true) == nil && feed(0, -80, momentum: true, expanded: true) == nil,
               "momentum after lifting the fingers never changes presentation")
        suite.expect(feed(0, -30, began: true, expanded: true) == .close,
               "a separate upward gesture closes an expanded panel")
        suite.expect(feed(-10, 0, began: true) == nil && feed(-15, 0) == nil && feed(-20, 0) == .nextTrack,
               "a left swipe changes one track after its threshold")
        for _ in 0..<100 { suite.expect(feed(-50, 0) == nil, "one physical swipe never skips multiple tracks") }
        suite.expect(feed(45, 0, began: true) == .previousTrack, "a right swipe selects the previous track")
        suite.expect(feed(40, 40, began: true) == nil, "diagonal motion is not guessed as a track or panel gesture")
        suite.expect(feed(1, 0, began: true, expanded: true) == nil
               && feed(0, -24, expanded: true) == .close,
               "small horizontal touchdown noise cannot lock out a vertical closing swipe")
        suite.expect(feed(0, 1, began: true) == nil && feed(-40, 0) == .nextTrack,
               "small vertical touchdown noise cannot lock out a track swipe")
        suite.expect(feed(0, 0.1, began: true) == nil, "a slow swipe begins below direction slop")
        for _ in 0..<7 { suite.expect(feed(0, 0.5) == nil, "subpoint travel accumulates without firing") }
        suite.expect(feed(0, 21) == .open, "slow travel contributes to the action threshold")
        suite.expect(feed(0, 5, began: true) == nil && feed(-80, 0) == nil,
               "an established vertical gesture cannot become a track skip")
        suite.expect(feed(-20, 0, began: true) == nil && feed(-19, 0) == nil && feed(-1, 0) == .nextTrack,
               "direction selection counts each delta once toward the track threshold")
        suite.expect(feed(-50, 0, began: true, horizontal: false) == nil,
               "lists, sliders and the navigation row can keep horizontal scrolling")
        suite.expect(feed(0, -50, began: true, vertical: false, expanded: true) == nil,
               "scrolling a content list never collapses the notch")
        suite.expect(feed(-50, 0, began: true, precise: false, phased: false) == nil,
               "an ordinary wheel tilt is not treated as a trackpad swipe")
        suite.expect(feed(0, 24, began: true, precise: false, phased: false) == .open,
               "a discrete wheel step can open the notch")
        time += 0.4
        suite.expect(feed(0, -24, precise: false, phased: false, expanded: true) == .close,
               "wheel sequences expire from their timestamps without a background timer")
        suite.expect(feed(-45, 0, began: true) == .nextTrack, "a phased gesture can begin after a wheel sequence")
        time += 5
        suite.expect(feed(-100, 0) == nil,
               "holding fingers still does not unlock a second track change in the same phased gesture")
        suite.expect(feed(-15, 0, began: true) == nil, "a new phased gesture starts with its own distance")
        time += 5
        suite.expect(feed(-30, 0) == .nextTrack,
               "a paused phased gesture retains its distance until its actual end")

        suite.expect(feed(0, 0, began: true, vertical: false, horizontal: false, expanded: true) == nil,
               "a gesture that begins over a list or slider is recorded as ineligible")
        suite.expect(feed(-80, 0, expanded: true) == nil && feed(0, -80, expanded: true) == nil,
               "moving from a list or slider onto music or the header cannot steal that phased scroll")
        time += 5
        suite.expect(feed(-80, 0, expanded: true) == nil,
               "a pause cannot make an ineligible phased origin eligible")
        suite.expect(feed(0, 0, ended: true) == nil && feed(-80, 0) == nil,
               "an ended or cancelled phased sequence cannot resume from an orphan changed event")
        suite.expect(feed(-80, 0, began: true) == .nextTrack,
               "lifting fingers and starting again on music creates a new eligible gesture")
        suite.expect(feed(0, 0, began: true, horizontal: false, expanded: true) == nil
               && feed(-80, 0, expanded: true) == nil,
               "a header origin does not acquire horizontal navigation after entering the player")
        suite.expect(feed(-15, 0, began: true, vertical: false, expanded: true) == nil
               && feed(0, -80, expanded: true) == nil,
               "a horizontal player origin does not acquire collapse behavior after entering the header")
        suite.expect(feed(-30, 0, vertical: false, horizontal: false, expanded: true) == .nextTrack,
               "an eligible phased scroll remains attached to its original surface as the pointer moves")

        suite.expect(feed(-15, 0, began: true) == nil, "interruption fixture begins below the threshold")
        gesture = NotchGestureSupport()
        suite.expect(feed(-80, 0) == nil,
               "discarding a sequence for exit, modifiers, capture, or suspension rejects its continued events")
        suite.expect(feed(-80, 0, began: true) == .nextTrack,
               "a fresh physical gesture works after an interruption")
        suite.expect(feed(-15, 0, began: true) == nil, "clock-regression fixture begins below the threshold")
        time -= 1
        suite.expect(feed(-80, 0) == nil, "an out-of-order event discards a phased gesture")
        time += 1
        suite.expect(feed(-80, 0) == nil, "ordered changed events cannot revive a discarded phased gesture")
        suite.expect(feed(-15, 0, began: true) == nil && feed(-80, 0, momentum: true, phased: false) == nil
               && feed(-80, 0, momentum: true, phased: false) == nil && feed(-80, 0) == nil,
               "momentum never finishes a partial navigation or leaves a resumable phased sequence")
        suite.expect(feed(0, 24, precise: false, phased: false) == .open,
               "a real wheel event after momentum can start an independent sequence")
        time += 0.4
        suite.expect(feed(0, -24, precise: true, phased: false, expanded: true) == .close,
               "high-resolution devices without phases still use timestamp-based wheel expiration")
        suite.expect(feed(0, 0, began: true, expanded: false) == nil
               && feed(0, -30, expanded: true) == nil,
               "an external presentation change cannot reverse the vertical action chosen by its origin")
        suite.expect(feed(.nan, 0, began: true) == nil && feed(.infinity, 0) == nil,
               "malformed deltas never produce a gesture")
        suite.expect(feed(-80, 0) == nil, "invalid timing or movement cannot restart a phased gesture midway")
        suite.expect(NotchGestureSupport.movement(3, precise: true, inverted: true) == 3
               && NotchGestureSupport.movement(-3, precise: true, inverted: false) == 3
               && NotchGestureSupport.movement(-1, precise: false, inverted: false) == 24,
               "gesture direction is consistent across natural scrolling and wheel devices")

        let domain = "com.vorssaint.tests.notch-gestures"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchGestureSupport.isEnabled(in: defaults), "gestures start enabled with the island")
        defaults.set(false, forKey: DefaultsKey.notchGesturesEnabled)
        suite.expect(!NotchGestureSupport.isEnabled(in: defaults), "gestures retain an independent opt-out")
        defaults.set(true, forKey: DefaultsKey.notchGesturesEnabled)
        defaults.set(false, forKey: AppFeature.notchGestures.availabilityKey)
        suite.expect(!NotchGestureSupport.isEnabled(in: defaults), "removing gestures from the hub clears their handler")
        defaults.set(true, forKey: AppFeature.notchGestures.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchGestureSupport.isEnabled(in: defaults), "gestures cannot keep the master notch alive")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchGesturesEnabled,
                                                                 AppFeature.notchGestures.availabilityKey]),
               "gesture preferences travel in backup")
        suite.expect(AppFeature.notchGestures.permissions.isEmpty, "window-local gestures need no global input permission")
    }

    private static func calendarPaging(_ suite: TestSuite) {
        calendarDocument(suite)
        calendarLiveScrolling(suite)
        calendarMonthAlignment(suite)
        calendarMomentum(suite)
        monthDrawing(suite)
        calendarColors(suite)
        for position in [-5000.375, -17.8, -7.1, -0.25, 0, 0.25, 7.1, 17.8, 5000.375] {
            for radius in [4, 14] {
                let result = NotchCalendarScrollSupport.rebase(position: position, radius: radius)
                suite.expect(abs(Double(result.shift) + result.remainder - position) < 0.000001,
                             "recycling calendar dates preserves the exact fractional screen position")
                suite.expect(abs(result.remainder) <= Double(radius) / 2,
                             "long scrolling always recentres the document before reaching its ends")
            }
        }
        suite.expect(NotchCalendarScrollSupport.rebase(position: .nan, radius: 4).shift == 0,
                     "invalid scrolling geometry never becomes a date offset")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.date(from: DateComponents(year: 2030, month: 12, day: 1))!
        let interval = NotchCalendarSupport.carouselReadInterval(month: month, now: Date(), calendar: calendar)
        suite.expect(interval.contains(calendar.date(from: DateComponents(year: 2030, month: 11, day: 1))!)
                     && interval.contains(calendar.date(from: DateComponents(year: 2031, month: 1, day: 31))!)
                     && interval.duration < 120 * 86400,
                     "the infinite carousel prefetches neighboring months without reading intervening years")
    }

    private static func calendarDocument(_ suite: TestSuite) {
        let initial = Date()
        for (component, count, radius) in [(Calendar.Component.day, 7, 14), (.month, 1, 4)] {
            var picked: Date?
            let contentState = NotchCalendarCarouselContentState(events: [], selectedDay: initial,
                                                                 today: Calendar.current.startOfDay(for: initial))
            let carousel = NotchCalendarCarousel(date: initial, component: component,
                                                visibleCount: count, browse: { _ in },
                                                settled: { picked = $0 }, contentState: contentState) { date in
                Text(date, format: .dateTime.day())
            }
            let coordinator = carousel.makeCoordinator()
            let scroll = CalendarCarouselScrollView(frame: NSRect(x: 0, y: 0, width: 350, height: 210))
            let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.contentView = scroll
            coordinator.attach(scroll)
            scroll.layoutSubtreeIfNeeded()
            coordinator.update(carousel)
            let pitch = scroll.cellWidth
            suite.expect(pitch > 0 && scroll.documentView != nil,
                         "the native carousel has a sized scrolling document")
            let initialPosition = scroll.contentView.bounds.minX / pitch
            suite.expect(abs(initialPosition - CGFloat(radius)) < 0.001,
                         "both horizontal carousels initially show the requested dates, with a buffer on either side")
            suite.expect(Calendar.current.isDate(coordinator.centeredDate, equalTo: initial, toGranularity: component),
                         "the initially picked day occupies the middle of the week strip")
            let amount = CGFloat(radius / 2 + 2) + 0.375
            let beforeRecycling = coordinator.renderedCellUpdates
            scroll.setPosition((CGFloat(radius) + amount) * pitch, animated: false)
            let position = scroll.contentView.bounds.minX / pitch
            suite.expect(abs(position - CGFloat(radius) - 0.375) < 0.001,
                         "native offscreen date recycling retains the fractional visible position")
            suite.expect(coordinator.renderedCellUpdates - beforeRecycling == Int(amount),
                         "recycling renders only incoming offscreen dates and preserves all visible date cells")
            if component == .day {
                let highlighted = coordinator.highlightedDates
                suite.expect(highlighted.count == 1 && Calendar.current.isDate(highlighted[0], inSameDayAs: coordinator.centeredDate)
                             && picked == nil,
                             "the central day highlights live before the scroll settles or the agenda reloads")
            }
            suite.expect(scroll.documentView!.frame.height == scroll.contentView.bounds.height
                         && scroll.documentView!.frame.width > scroll.contentView.bounds.width,
                         "week and month documents scroll horizontally without a vertical document extent")
            let renderedCells = coordinator.renderedCellUpdates
            coordinator.update(carousel)
            let updated = scroll.contentView.bounds.minX / pitch
            suite.expect(abs(updated - position) < 0.001,
                         "ordinary SwiftUI content updates do not reset the native carousel offset")
            suite.expect(coordinator.renderedCellUpdates == renderedCells,
                         "unchanged SwiftUI updates reuse date cells without rendering the entire carousel again")
            scroll.didSettle?()
            let expected = Calendar.current.date(byAdding: component, value: Int(amount.rounded()), to: initial)!
            suite.expect(picked.map { Calendar.current.isDate($0, equalTo: expected, toGranularity: component) } == true,
                         "settling picks the central day rather than the leftmost day")
            let distant = Calendar.current.date(byAdding: component, value: 100, to: initial)!
            let destination = NotchCalendarCarousel(date: distant, component: component,
                                                    visibleCount: count, browse: { _ in },
                                                    contentState: contentState) { date in
                Text(date, format: .dateTime.day())
            }
            coordinator.update(destination)
            suite.expect(Calendar.current.isDate(coordinator.centeredDate, equalTo: distant, toGranularity: component),
                         "choosing a distant date recentres it instead of leaving the picked day outside the viewport")
            coordinator.stop()
            scroll.stop()
        }
    }

    private static func calendarLiveScrolling(_ suite: TestSuite) {
        let calendar = Calendar.current
        let initial = calendar.startOfDay(for: Date())
        for (component, sensitivity) in [(Calendar.Component.day, CGFloat(1)), (.month, 1), (.month, 0.75)] {
            var browsed: Date?
            var settled = 0
            func model(_ date: Date) -> NotchCalendarCarousel<Text> {
                NotchCalendarCarousel(date: date, component: component, visibleCount: component == .day ? 7 : 1,
                                      browse: { browsed = $0 }, settled: { _ in settled += 1 },
                                      scrollSensitivity: sensitivity,
                                      contentState: NotchCalendarCarouselContentState(events: [], selectedDay: date, today: initial)) {
                    Text($0, format: .dateTime.day())
                }
            }
            let carousel = model(initial)
            let coordinator = carousel.makeCoordinator()
            let scroll = CalendarCarouselScrollView(frame: CGRect(x: 0, y: 0, width: 448, height: 210))
            let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.contentView = scroll
            coordinator.attach(scroll)
            scroll.layoutSubtreeIfNeeded()
            coordinator.update(carousel)
            func feed(_ points: CGFloat, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [], y: CGFloat = 0) {
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                    wheel1: 0, wheel2: 0, wheel3: 0)!
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(-points / sensitivity))
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(y))
                // CoreGraphics uses different phase bit values than NSEvent.
                let cgPhase: Int64 = phase == .began ? 1 : phase == .changed ? 2 : phase == .ended ? 4 : 0
                let cgMomentum: Int64 = momentum == .began ? 1 : momentum == .changed ? 2 : momentum == .ended ? 3 : 0
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: cgPhase)
                event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: cgMomentum)
                scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
            }
            feed(0, phase: .began, y: 0.5)
            feed(scroll.cellWidth * 2.375, phase: .changed)
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            let expected = calendar.date(byAdding: component, value: 2, to: initial)!
            suite.expect(browsed.map { calendar.isDate($0, equalTo: expected, toGranularity: component) } == true,
                         "live browsing reports the central date before finger lift and ignores touchdown axis noise")
            let offset = scroll.contentView.bounds.minX
            let rendered = coordinator.renderedCellUpdates
            if component == .day, let browsed {
                coordinator.update(model(browsed))
                suite.expect(abs(scroll.contentView.bounds.minX - offset) < 0.001 && !scroll.programmatic
                             && coordinator.renderedCellUpdates == rendered,
                             "feeding the live selected day into the agenda preserves fractional travel and cached day cells")
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            suite.expect(scroll.scrolling && settled == 0 && abs(scroll.contentView.bounds.minX - offset) < 0.001,
                         "holding fingers still never settles or snaps an active trackpad gesture")
            var travel: CGFloat = 2.375
            for amount in [37.25, -80.625, 91.125, -60.75] as [CGFloat] {
                feed(scroll.cellWidth * amount, phase: .changed)
                travel += amount
                let expected = calendar.date(byAdding: component, value: Int(travel.rounded()), to: initial)!
                suite.expect(calendar.isDate(coordinator.centeredDate, equalTo: expected, toGranularity: component),
                             "fast gestures retain all travel even when a single delta exceeds the entire document buffer")
            }
            feed(scroll.cellWidth * 0.125, phase: .ended)
            feed(scroll.cellWidth * 1.375, momentum: .began)
            travel += 1.5
            feed(scroll.cellWidth * 0.375, momentum: .changed)
            travel += 0.375
            feed(0, momentum: .ended)
            let finalOffset = scroll.contentView.bounds.minX
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let finalDate = calendar.date(byAdding: component, value: Int(travel.rounded()), to: initial)!
            suite.expect(settled > 0 && !scroll.scrolling
                         && calendar.isDate(coordinator.centeredDate, equalTo: finalDate, toGranularity: component),
                         "momentum retains its axis and settles on the final date after the stream ends")
            if component == .month {
                suite.expect(abs(scroll.contentView.bounds.minX - finalOffset) < 0.001 && !scroll.programmatic,
                             "month momentum ends at its exact fractional offset without a hard page stop")
            }
            if sensitivity < 1 {
                // Test actual input rather than the normalized travel above.
                // Reversal must remain immediate, without queued motion or a snap.
                let before = scroll.contentView.bounds.minX
                feed(24 * sensitivity, phase: .began)
                suite.expect(abs(scroll.contentView.bounds.minX - before - 24 * sensitivity) < 0.001,
                             "monthly finger travel has a gentler proportional response")
                feed(-24 * sensitivity, phase: .changed)
                suite.expect(abs(scroll.contentView.bounds.minX - before) < 0.001,
                             "reversing a monthly gesture responds immediately without animation lag")
                feed(24 * sensitivity, phase: .ended)
                feed(24 * sensitivity, momentum: .began)
                suite.expect(abs(scroll.contentView.bounds.minX - before - 48 * sensitivity) < 0.001,
                             "monthly momentum uses the same gentle response as finger travel")
                feed(0, momentum: .ended)
                let released = scroll.contentView.bounds.minX
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                suite.expect(abs(scroll.contentView.bounds.minX - released) < 0.001 && !scroll.programmatic,
                             "a gentle monthly gesture stays where momentum ends without locking to a month")
            }
            coordinator.stop()
            scroll.stop()
        }
    }

    private static func calendarMonthAlignment(_ suite: TestSuite) {
        let initial = Calendar.current.dateInterval(of: .month, for: Date())!.start
        let carousel = NotchCalendarCarousel(date: initial, component: .month, visibleCount: 1,
                                            browse: { _ in }, monthAlignmentTolerance: 0.14) { date in
            Text(date, format: .dateTime.month())
        }
        let coordinator = carousel.makeCoordinator()
        let scroll = CalendarCarouselScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 210))
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        coordinator.attach(scroll)
        scroll.layoutSubtreeIfNeeded()
        coordinator.update(carousel)
        for travel in [14, -14, 52, -52, 64, -64] {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: 0, wheel2: Int32(-travel), wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            scroll.setPosition(4 * scroll.cellWidth, animated: false)
            scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
            suite.expect(abs(scroll.contentView.bounds.minX - 4 * scroll.cellWidth - CGFloat(travel)) < 0.001,
                         "month alignment assistance never resists movement during a gesture")
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let expected = 4 * scroll.cellWidth + (abs(travel) < 56 ? 0 : CGFloat(travel))
            suite.expect(abs(scroll.contentView.bounds.minX - expected) < 0.001 && !scroll.programmatic,
                         "months gently align only when released near a boundary, in either direction")
        }
        coordinator.stop()
        scroll.stop()
    }

    private static func calendarMomentum(_ suite: TestSuite) {
        var tracking = NotchCalendarMomentum()
        tracking.record(delta: 0, timestamp: 1)
        for index in 1...5 { tracking.record(delta: 16, timestamp: 1 + Double(index) / 60) }
        suite.expect(abs(tracking.released(at: 1 + 5.0 / 60, limit: 2000) - 960) < 0.001,
                     "a quick swipe retains its release velocity instead of stopping at finger lift")
        suite.expect(tracking.released(at: 1.3, limit: 2000) == 0,
                     "a deliberate finger pause does not create an unwanted fling")
        tracking.record(delta: -16, timestamp: 1.1)
        suite.expect(tracking.released(at: 1.1, limit: 500) == -500,
                     "reversal replaces the old fling direction and release speed remains bounded")
        var distances: [Double] = []
        for fps in [60, 120, 240] {
            var velocity = 960.0, distance = 0.0
            var smooth = true
            for _ in 0..<(fps * 3) {
                let step = NotchCalendarMomentum.step(velocity: velocity, elapsed: 1 / Double(fps))
                smooth = smooth && step.velocity >= 0 && step.velocity < velocity && step.distance > 0
                velocity = step.velocity
                distance += step.distance
            }
            suite.expect(smooth, "coasting slows continuously without reversing or stopping at a month boundary")
            distances.append(distance)
        }
        suite.expect(distances.allSatisfy { abs($0 - distances[0]) < 0.000001 },
                     "deceleration travels the same distance at different display refresh rates")

        let initial = Calendar.current.dateInterval(of: .month, for: Date())!.start
        var settled = 0
        let carousel = NotchCalendarCarousel(date: initial, component: .month, visibleCount: 1,
                                            browse: { _ in }, settled: { _ in settled += 1 }, coastsMonths: true) { date in
            Text(date, format: .dateTime.month())
        }
        let coordinator = carousel.makeCoordinator()
        let scroll = CalendarCarouselScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 210))
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        coordinator.attach(scroll)
        scroll.layoutSubtreeIfNeeded()
        coordinator.update(carousel)
        func feed(_ delta: Int32, phase: Int64, momentum: Int64 = 0, timestamp: Double) {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: 0, wheel2: -delta, wheel3: 0)!
            event.timestamp = UInt64(timestamp * 1_000_000_000)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
        }
        feed(0, phase: 1, timestamp: 1)
        for index in 1...5 { feed(16, phase: 2, timestamp: 1 + Double(index) / 60) }
        feed(0, phase: 4, timestamp: 1 + 5.0 / 60)
        let released = scroll.contentView.bounds.minX
        suite.expect(scroll.isCoasting && scroll.scrolling && settled == 0,
                     "the native month view starts coasting immediately on finger lift without waiting for AppKit momentum")
        feed(200, phase: 0, momentum: 1, timestamp: 1.1)
        suite.expect(abs(scroll.contentView.bounds.minX - released) < 0.001 && scroll.isCoasting,
                     "system momentum cannot double the carousel's custom release movement")
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let coasted = scroll.contentView.bounds.minX
        suite.expect(coasted > released + 50 && scroll.isCoasting && settled == 0,
                     "fast monthly scrolling continues smoothly after the final input event")
        feed(0, phase: 1, timestamp: 2)
        let interrupted = scroll.contentView.bounds.minX
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        suite.expect(!scroll.isCoasting && abs(scroll.contentView.bounds.minX - interrupted) < 0.001,
                     "touching the carousel stops the coast immediately without queued movement")
        feed(0, phase: 4, timestamp: 2.2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        suite.expect(!scroll.scrolling && settled == 1,
                     "a stationary release stays still and settles exactly once")
        feed(0, phase: 1, timestamp: 3)
        for index in 1...5 { feed(16, phase: 2, timestamp: 3 + Double(index) / 60) }
        feed(0, phase: 4, timestamp: 3 + 5.0 / 60)
        RunLoop.main.run(until: Date().addingTimeInterval(1.8))
        suite.expect(!scroll.isCoasting && !scroll.scrolling && settled == 2,
                     "the exponential coast reaches rest and settles without a hard cutoff")
        coordinator.stop()
        scroll.stop()
    }

    private static func calendarColors(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Riga")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let days = NotchCalendarSupport.monthDays(containing: month, calendar: calendar)
        let palette = (0..<5).map { NotchCalendarColor(red: Double($0) / 5, green: 0.5, blue: 1) }
        let events = (0..<512).map { index in
            let day = calendar.date(byAdding: .day, value: index % 60 - 10, to: days[0])!
            let start = calendar.date(byAdding: .hour, value: index % 24, to: day)!
            let end = calendar.date(byAdding: .hour, value: index % 73, to: start)!
            return NotchCalendarEvent(id: "fixture-\(index)", title: "Event", calendar: "Fixture", start: start,
                                      end: end, allDay: index % 7 == 0, location: "", color: palette[index % 5])
        }.reversed()
        let reference = days.map { day in
            NotchCalendarSupport.events(Array(events), on: day, calendar: calendar)
                .reduce(into: [NotchCalendarColor]()) { colors, event in
                    if colors.count < 3 && !colors.contains(event.color) { colors.append(event.color) }
                }
        }
        suite.expect(NotchCalendarSupport.colors(Array(events), on: days, calendar: calendar) == reference,
                     "batched month colors preserve event ordering, duplicate colors, midnight endings and DST crossings")
        suite.expect(NotchCalendarSupport.colors([], on: [], calendar: calendar).isEmpty,
                     "an empty month grid has no event color work")
    }

    private static func monthDrawing(_ suite: TestSuite) {
        let calendar = Calendar.current
        let month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        var chosen: Date?
        let configuration = NotchCalendarMonthCanvas(month: month, selectedDay: month, now: month,
                                                    events: [], text: FeatureStrings.notchCalendar(.enUS),
                                                    rowHeight: 28, weekdayHeight: 16, spacing: 0,
                                                    circle: 24, dotGap: 0, select: { chosen = $0 })
        let canvas = CalendarMonthCanvasView(frame: CGRect(x: 0, y: 0, width: 350, height: 184))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = canvas
        canvas.configure(configuration, locale: Locale(identifier: "en_US"))
        let days = NotchCalendarSupport.monthDays(containing: month)
        suite.expect(canvas.date(at: CGPoint(x: 25, y: 5)) == nil
                     && canvas.date(at: CGPoint(x: 25, y: 30)) == days.first,
                     "native date hit testing distinguishes weekday captions from date cells")
        let children = canvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        suite.expect(children.count == 42 && children[0].accessibilityPerformPress() && chosen == days.first,
                     "all month dates remain individually accessible and activate the correct date")
        let image = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        canvas.cacheDisplay(in: canvas.bounds, to: image)
        let builds = canvas.imageBuildCount
        canvas.configure(configuration, locale: Locale(identifier: "en_US"))
        canvas.cacheDisplay(in: canvas.bounds, to: image)
        suite.expect(builds == 1 && canvas.imageBuildCount == builds,
                     "month drawing reuses its cached image across ordinary display and content updates")
        let outside = calendar.date(byAdding: .month, value: 3, to: month)!
        let unrelated = NotchCalendarEvent(id: "outside", title: "Later", calendar: "Fixture", start: outside,
                                           end: outside.addingTimeInterval(3600), allDay: false, location: "")
        let unchanged = NotchCalendarMonthCanvas(month: month, selectedDay: outside, now: month,
                                                events: [unrelated], text: FeatureStrings.notchCalendar(.enUS),
                                                rowHeight: 28, weekdayHeight: 16, spacing: 0, circle: 24, dotGap: 0,
                                                select: { chosen = $0 })
        // Remove the visible initial selection once, then changes outside the
        // rendered month must leave the image and accessibility objects intact.
        canvas.configure(unchanged, locale: Locale(identifier: "en_US"))
        canvas.cacheDisplay(in: canvas.bounds, to: image)
        let cached = canvas.imageBuildCount
        let accessible = canvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        let later = NotchCalendarMonthCanvas(month: month, selectedDay: outside.addingTimeInterval(86400), now: month,
                                            events: [], text: FeatureStrings.notchCalendar(.enUS),
                                            rowHeight: 28, weekdayHeight: 16, spacing: 0, circle: 24, dotGap: 0,
                                            select: { chosen = $0 })
        canvas.configure(later, locale: Locale(identifier: "en_US"))
        canvas.cacheDisplay(in: canvas.bounds, to: image)
        let retained = canvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        suite.expect(canvas.imageBuildCount == cached && retained.first === accessible.first,
                     "events and selection outside a month do not rebuild its drawing or accessibility dates")
        let separated = NotchCalendarMonthCanvas(month: month, selectedDay: month, now: month,
                                                events: [], text: FeatureStrings.notchCalendar(.enUS),
                                                rowHeight: 25, weekdayHeight: 16, spacing: 0, circle: 22, dotGap: 0,
                                                select: { chosen = $0 }, horizontalPadding: 20)
        canvas.configure(separated, locale: Locale(identifier: "en_US"))
        suite.expect(canvas.date(at: CGPoint(x: 2, y: 45)) == nil
                     && canvas.date(at: CGPoint(x: 348, y: 45)) == nil
                     && canvas.date(at: CGPoint(x: 25, y: 8)) == nil
                     && canvas.date(at: CGPoint(x: 25, y: 30)) == days.first,
                     "month gutters do not select dates, while the inset date grid stays tappable")
    }

    private static func nativeInteractionContracts(_ suite: TestSuite) {
        // Native hit testing only; no windows are shown and no input is sent.
        let surface = NSView(frame: CGRect(x: 0, y: 0, width: 180, height: 32))
        let activation = NotchActivationButton(frame: surface.bounds)
        activation.isTransparent = true
        surface.addSubview(activation)
        let target = surface.hitTest(CGPoint(x: 90, y: 16))
        let interaction = NotchGestureSupport.nativeInteraction(at: target)
        suite.expect(target === activation && !interaction.control && !interaction.scroll,
               "the transparent resting button remains clickable without blocking gestures")
        // With Keyboard navigation on, a click or Tab would focus a plain button,
        // and its focus ring would outline the camera the island hides behind.
        let window = NSWindow(contentRect: surface.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = surface
        suite.expect(!activation.acceptsFirstResponder && !activation.canBecomeKeyView,
               "the transparent resting button never takes keyboard focus")
        var gesture = NotchGestureSupport()
        suite.expect(gesture.handle(x: 0, y: 40, timestamp: 1, began: true, ended: false,
                              momentum: false, precise: true, hasPhase: true,
                              allowVertical: !interaction.control, allowHorizontal: false, expanded: false) == .open,
               "a gesture beginning on the native resting button can open the notch")

        for control in [NSButton(), NSSlider(), NSTextField(), NSTextView()] as [NSView] {
            let child = NSView()
            control.addSubview(child)
            suite.expect(NotchGestureSupport.nativeInteraction(at: child).control,
                   "real controls and their descendants retain their own input")
        }
        let scroll = NSScrollView()
        let content = NSView()
        scroll.documentView = content
        suite.expect(NotchGestureSupport.nativeInteraction(at: content).scroll,
               "scrolling content stays recognized through its native ancestors")
        let empty = NotchGestureSupport.nativeInteraction(at: nil)
        suite.expect(!empty.control && !empty.scroll, "an absent hit target creates no imaginary control")
    }
}
