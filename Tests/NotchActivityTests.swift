// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SwiftUI

enum NotchActivityTests {
    static func run(_ suite: TestSuite) {
        timerContracts(suite)
        alertContracts(suite)
        lowBatteryContracts(suite)
        pomodoroContracts(suite)
        stopwatchContracts(suite)
        modePickerContracts(suite)
        rulerContracts(suite)
        compactTimerContracts(suite)
        compactMarginContracts(suite)
        compactDownloadContracts(suite)
        keepAwakeContracts(suite)
        accessoryContracts(suite)
        NotchAccessoryConnectionTests.run(suite)
        PeripheralBatteryLifecycleTests.run(suite)
        gateContracts(suite)
        menuBarFitContracts(suite)
        menuBarGapContracts(suite)
        menuBarGapAuditContracts(suite)
        menuBarGapPlannerContracts(suite)
    }

    /// Fitting the strip beside the menu bar's icons: on by default, saved
    /// with backups, wings as wide as the free room down to each activity's
    /// minimum, then covering the menus where allowed or giving way.
    private static func menuBarFitContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-menu-bar-fit"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchFitsMenuBarRoom] as? Bool == true
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchFitsMenuBarRoom),
                     "fitting beside the menu bar's icons starts on and travels with settings backups")
        suite.expect(NotchSupport.fitsMenuBarRoom(in: defaults), "a missing choice fits the strip")
        defaults.set(false, forKey: DefaultsKey.notchFitsMenuBarRoom)
        suite.expect(!NotchSupport.fitsMenuBarRoom(in: defaults), "turning fitting off is kept")

        let covering = NotchMenuBarFit(coverRoom: 600)
        let yielding = NotchMenuBarFit(coverRoom: nil)
        suite.expect(covering.room(measured: 50, minimum: 44) == 50 && yielding.room(measured: 50, minimum: 44) == 50,
                     "room enough for the minimum is used as measured")
        suite.expect(covering.room(measured: 30, minimum: 44) == 600,
                     "a strip that does not fit covers the menus when it may")
        suite.expect(yielding.room(measured: 30, minimum: 44) == 30,
                     "a strip that does not fit and may not cover keeps the measured room and gives way")
        suite.expect(covering.room(measured: nil, minimum: 44) == 600 && yielding.room(measured: .nan, minimum: 44) == 0,
                     "an unknown room covers where allowed and otherwise leaves no wings")
        suite.expect(covering.settledRoom(current: 50, measured: 53) == 50
                     && covering.settledRoom(current: 50, measured: 54) == 54
                     && covering.settledRoom(current: 50, measured: 46.5) == 50,
                     "readings within four points keep the wings where they are")
        suite.expect(covering.settledRoom(current: nil, measured: 51) == 51
                     && covering.settledRoom(current: 50, measured: nil) == 600
                     && yielding.settledRoom(current: 50, measured: nil) == nil,
                     "a first reading always applies, and a failed one covers only where allowed")

        // A 14-inch MacBook Pro camera, with the menus leaving `room` free.
        func base(room: CGFloat?, fit: NotchMenuBarFit?) -> NotchGeometry {
            var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                         cameraWidth: 185, menuBarHeight: 32, compactSideRoom: room)
            geometry.menuBarFit = fit
            return geometry
        }
        func timerWing(room: CGFloat?, fit: NotchMenuBarFit?) -> CGFloat {
            base(room: room, fit: fit).compactTimerGeometry(showsDownloads: false, wing: 60).compactActivityWingWidth
        }
        suite.expect(timerWing(room: 500, fit: covering) == 60 && timerWing(room: 500, fit: nil) == 60,
                     "with room to spare the timer keeps the wings its reading wants")
        suite.expect(timerWing(room: 50, fit: covering) == 50 && timerWing(room: 50, fit: yielding) == 50,
                     "fitted, the timer narrows to the free room, keeping its mark and reading")
        suite.expect(timerWing(room: 50, fit: nil) == 0,
                     "measured without fitting, a timer still gives way below its usual wing")
        suite.expect(timerWing(room: 30, fit: covering) == 60,
                     "below its narrowest wing the timer covers the menus when it may")
        suite.expect(timerWing(room: 30, fit: yielding) == 0,
                     "below its narrowest wing the timer gives way when it may not cover")
        let left = base(room: 50, fit: covering).compactTimerGeometry(showsDownloads: false, wing: 60)
        suite.expect(left.compactActivitySize.width == left.cameraWidth + 2 * 50,
                     "both wings take the smaller side's room, so the strip stays centred on the camera")
        let agents = base(room: 50, fit: covering).compactAgentGeometry(wing: 80).compactActivityWingWidth
        let watch = base(room: 60, fit: covering).compactWatchGeometry(wing: 150).compactActivityWingWidth
        let download = base(room: 30, fit: yielding).compactDownloadGeometry()
        suite.expect(agents == 50 && watch == 60 && download.compactActivityUsesFooter,
                     "agents and watches narrow to the room, and a download below its arrow gives way below the camera")
        suite.expect(base(room: 30, fit: covering).restingWingWidth == 44 && base(room: 30, fit: yielding).restingWingWidth == 0,
                     "the resting wings cover the menus or give way like an activity's")
    }

    /// The gap checked against where every status item really is, and how
    /// often it may be placed again.
    private static func menuBarGapAuditContracts(_ suite: TestSuite) {
        let plain = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        func item(_ x: CGFloat, _ width: CGFloat) -> CGRect { CGRect(x: x, y: 1056, width: width, height: 24) }
        // The reading on the user's display: the island at 786...1133, the
        // gap pushed left to 610...993 by Deep Work's item appearing right of it.
        let island: ClosedRange<CGFloat> = 786...1133
        let pushed = [item(610, 383), item(1007, 24), item(1083, 150), item(1209, 24), item(1384, 44)]
        suite.expect(NotchMenuBarGap.audit(island: island, gapLength: 383, frames: pushed, screen: plain)
                     == .replace(NotchMenuBarGap(position: 686, length: 455)),
                     "a gap pushed under the island is placed again right of the items over it")
        suite.expect(NotchMenuBarGap.audit(island: island, gapLength: 383, frames: [item(1007, 24)], screen: plain) == .unknown,
                     "a reading without the gap changes nothing")
        let landed = [item(770, 30), item(800, 434), item(1240, 24), item(1384, 44)]
        suite.expect(NotchMenuBarGap.audit(island: island, gapLength: 434, frames: landed, screen: plain)
                     == .fits(gap: item(800, 434)),
                     "a gap ending past the island with nothing over the island to its right fits, from where it really ends")
        suite.expect(NotchMenuBarGap.length(rightEnd: 1234, island: island, screen: plain) == 452,
                     "its length then runs from its real end, not the one asked for")
        let leftOver = [item(760, 40), item(790, 444), item(1240, 24)]
        suite.expect(NotchMenuBarGap.audit(island: island, gapLength: 444, frames: leftOver, screen: plain)
                     == .fits(gap: item(790, 444)),
                     "an item left of the gap is cleared by its length, without placing it again")
        let short = [item(700, 420), item(1135, 24)]
        if case .replace = NotchMenuBarGap.audit(island: island, gapLength: 420, frames: short, screen: plain) {
            suite.expect(true, "")
        } else {
            suite.expect(false, "a gap ending short of the island and its margin is placed again")
        }
        let notched = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notchItems = [CGRect(x: 849, y: 958, width: 81, height: 24), CGRect(x: 600, y: 958, width: 40, height: 24)]
        suite.expect(NotchMenuBarGap.audit(island: 606...906, gapLength: 81, frames: notchItems, screen: notched,
                                           notchWidth: 185) == .fits(gap: notchItems[0]),
                     "beside a camera, items left of the notch are not over the island")

    }

    /// Drives a planner as the service does, against a menu bar where the
    /// gap lands where it asked and audits read it back, and counts what it
    /// does to the bar.
    private struct GapBar {
        var planner = NotchMenuBarGapPlanner()
        var now: TimeInterval = 0
        var wakes: [TimeInterval] = []
        var audits: [TimeInterval] = []
        var places = 0, lengths = 0, removes = 0, gaveUp = 0
        /// An item that appeared right of the gap, pushing it this far left,
        /// until the gap is placed again right of it.
        var push: CGFloat = 0

        mutating func apply(_ actions: [NotchMenuBarGapPlanner.Action]) {
            for action in actions {
                switch action {
                case .place: places += 1; push = 0
                case .setLength: lengths += 1
                case .remove: removes += 1
                case .gaveUp: gaveUp += 1
                case .audit(let delay): audits.append(now + delay)
                case .wake(let time): wakes.append(time)
                }
            }
        }

        mutating func want(_ target: NotchMenuBarGapPlanner.Target?) { apply(planner.want(target, now: now)) }

        /// Lets time pass to `time`, running every wake and reading due by then.
        mutating func run(until time: TimeInterval) {
            while true {
                let due = (wakes + audits).filter { $0 <= time }.min()
                guard let due else { break }
                now = max(now, due)
                if let index = wakes.firstIndex(of: due) {
                    wakes.remove(at: index)
                    apply(planner.tick(now: now))
                } else if let index = audits.firstIndex(of: due) {
                    audits.remove(at: index)
                    apply(planner.audited(frames: frames(), now: now))
                }
            }
            now = time
        }

        func frames() -> [CGRect] {
            guard let right = planner.rightEnd, let length = planner.length else { return [] }
            let gap = CGRect(x: right - push - length, y: 1056, width: length, height: 24)
            return push > 0 ? [gap, CGRect(x: right - push + 14, y: 1056, width: push - 14, height: 24)] : [gap]
        }
    }

    /// The planner keeps the gap calm: a debounced length, a delayed shrink,
    /// a capped number of places and lengths, and a fixed point with fitting.
    private static func menuBarGapPlannerContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        func target(_ width: CGFloat, _ content: String = "timer") -> NotchMenuBarGapPlanner.Target {
            NotchMenuBarGapPlanner.Target(island: NotchMenuBarGap.island(width: width, screen: screen)!,
                                          screen: screen, notchWidth: nil, content: content)
        }

        // A Deep Work session: the island at rest, the session starting, its
        // reading ticking every second for five minutes, an app launching
        // with an item that pushes the gap, and the session ending.
        var bar = GapBar()
        bar.want(target(300, "rest"))
        bar.run(until: 1)
        suite.expect(bar.places == 1 && bar.lengths == 0, "the island at rest places one gap after the debounce")
        bar.now = 10
        bar.want(target(400))
        bar.run(until: 11)
        suite.expect(bar.places == 2, "a session widening the island past the gap's end places it once more")
        for second in 0..<300 {
            bar.now = 11 + TimeInterval(second)
            // Readings change the strip by a point or two, and once by eight.
            bar.want(target(second >= 200 ? 392 : (second.isMultiple(of: 2) ? 400 : 402)))
            bar.run(until: bar.now + 1)
        }
        suite.expect(bar.places == 2 && bar.lengths <= 2,
                     "five minutes of reading ticks cause at most two length changes and no new place")
        let ticksLengths = bar.lengths
        bar.push = 150
        bar.apply([.audit(after: NotchMenuBarGapPlanner.auditDelay)])
        bar.run(until: bar.now + 3)
        suite.expect(bar.places == 3 && bar.push == 0,
                     "an app's item pushing the gap under the island places it once more, right of that item")
        suite.expect(bar.lengths <= ticksLengths + 1,
                     "a new place costs at most one length change, once a reading finds where it landed")
        let pushedLengths = bar.lengths
        bar.now += 30
        bar.want(target(300, "rest"))
        bar.run(until: bar.now + 2)
        suite.expect(bar.lengths == pushedLengths + 1 && bar.places == 3 && bar.removes == 0 && bar.gaveUp == 0,
                     "the session ending shortens the gap once, after its delay, without a new place")

        // A shrink waits a second, and a strip that grows back meanwhile changes nothing.
        var shrink = GapBar()
        shrink.want(target(400))
        shrink.run(until: 1)
        shrink.want(target(380))
        shrink.run(until: 1.5)
        suite.expect(shrink.lengths == 0, "a narrower strip keeps the gap for a second")
        shrink.want(target(400))
        shrink.run(until: 5)
        suite.expect(shrink.lengths == 0, "a strip back to its width before the second is up changes nothing")
        shrink.want(target(380))
        shrink.run(until: 8)
        suite.expect(shrink.lengths == 1, "a strip narrower for a second shortens the gap once")

        // Places are two seconds apart at least and four a minute at most.
        var places = GapBar()
        var width: CGFloat = 300
        places.want(target(width))
        places.run(until: 1)
        for step in 1...6 {
            places.now = TimeInterval(step) * 3
            width += 60
            places.want(target(width))
            places.run(until: places.now + 2.9)
        }
        suite.expect(places.places == 4 && places.gaveUp == 1 && places.removes == 1,
                     "a fifth place within a minute removes the gap and says so once")
        places.want(target(width + 60))
        places.run(until: places.now + 5)
        suite.expect(places.places == 4, "the gap stays off while the island shows the same thing")
        places.now += 61
        places.want(target(300, "music"))
        places.run(until: places.now + 1)
        suite.expect(places.places == 5, "something new on the island brings the gap back")
        var close = GapBar()
        close.want(target(300))
        close.run(until: 0.5)
        close.want(target(400))
        close.run(until: 1)
        suite.expect(close.places == 1, "a second place waits two seconds after the first")
        close.run(until: 3)
        suite.expect(close.places == 2, "and then follows")

        // Lengths are capped at twenty a minute.
        var lengths = GapBar()
        lengths.want(target(400))
        lengths.run(until: 1)
        for step in 0..<24 {
            lengths.now = 1 + TimeInterval(step) * 2
            lengths.want(target(step.isMultiple(of: 2) ? 380 : 400))
            lengths.run(until: lengths.now + 1.9)
        }
        suite.expect(lengths.lengths == 20 && lengths.gaveUp == 1 && lengths.removes == 1,
                     "a twenty-first length within a minute removes the gap")

        // The gap's width comes from the island over an empty bar, which
        // nothing it moves can change; fitting then measures with the gap
        // left out. Once the gap is read back, neither moves again.
        var fixed = GapBar()
        let wanted = target(400)
        fixed.want(wanted)
        fixed.run(until: 2)
        let settled = (fixed.places, fixed.lengths)
        let frames = fixed.frames() + [CGRect(x: 700, y: 1056, width: 40, height: 24),
                                        CGRect(x: fixed.planner.rightEnd! + 14, y: 1056, width: 30, height: 24)]
        let gapFrame = frames[0]
        let room = NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: 180, barHeight: 24,
                                               occupied: NotchMenuBarGap.removing(gapFrame, from: frames))!
        suite.expect(room >= (400 - 180) / 2,
                     "with the gap left out, fitting leaves the strip all the width the gap was made for")
        fixed.apply(fixed.planner.want(wanted, now: fixed.now))
        fixed.apply(fixed.planner.audited(frames: frames, now: fixed.now))
        fixed.run(until: fixed.now + 5)
        fixed.apply(fixed.planner.audited(frames: frames, now: fixed.now))
        fixed.run(until: fixed.now + 5)
        suite.expect(fixed.places == settled.0 && fixed.lengths == settled.1,
                     "a reading, a refresh with the same strip and another reading change nothing more")
    }

    /// The empty status item under the island: placed once with its right
    /// end a little past the island, then lengthened and shortened live with
    /// the island's left end, and placed again only when its end must move.
    private static func menuBarGapContracts(_ suite: TestSuite) {
        let plain = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let island = NotchMenuBarGap.island(width: 300, screen: plain)
        suite.expect(island == 810...1110, "the island is centred on its display")
        suite.expect(NotchMenuBarGap.island(width: 300, surfaceShift: 20, screen: plain) == 830...1130,
                     "an island reaching toward one side moves with it")
        suite.expect(NotchMenuBarGap.island(width: 0, screen: plain) == nil
                     && NotchMenuBarGap.island(width: .nan, screen: plain) == nil,
                     "an island with no width clears nothing")
        let gap = island.flatMap { NotchMenuBarGap.placed(island: $0, screen: plain) }
        suite.expect(gap == NotchMenuBarGap(position: 806, length: 308),
                     "a new gap spans the island and four points on each side")
        let offset = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        suite.expect(NotchMenuBarGap.island(width: 300, screen: offset)
                        .flatMap { NotchMenuBarGap.placed(island: $0, screen: offset) } == gap,
                     "the position counts from the edge of the island's own display")
        suite.expect(NotchMenuBarGap.island(width: 5000, screen: plain)
                        .flatMap { NotchMenuBarGap.placed(island: $0, screen: plain) }
                     == NotchMenuBarGap(position: 0, length: 1920),
                     "a gap never reaches past the display")
        let notched = CGRect(x: 0, y: 0, width: 1512, height: 982)
        suite.expect(NotchMenuBarGap.island(width: 300, screen: notched)
                        .flatMap { NotchMenuBarGap.placed(island: $0, screen: notched, notchWidth: 185) }
                     == NotchMenuBarGap(position: 602, length: 61),
                     "beside a physical camera the gap starts past the notch, where macOS keeps status items")

        // Placed at 1134, the gap follows the island by its length alone.
        let end: CGFloat = 1134
        suite.expect(!NotchMenuBarGap.needsPlacing(rightEnd: end, island: 810...1110)
                     && !NotchMenuBarGap.needsPlacing(rightEnd: end, island: 850...1070),
                     "an island that stays within the gap's end keeps the gap where it is")
        suite.expect(NotchMenuBarGap.needsPlacing(rightEnd: end, island: 790...1140)
                     && !NotchMenuBarGap.needsPlacing(rightEnd: end, island: 796...1132),
                     "an island reaching past the gap's end moves it; one growing into the margin does not")
        suite.expect(!NotchMenuBarGap.needsPlacing(rightEnd: end, island: 900...1000),
                     "a narrower island keeps the gap's end, so an item it was placed to clear stays clear")
        suite.expect(NotchMenuBarGap.length(rightEnd: end, island: 810...1110, screen: plain) == 328
                     && NotchMenuBarGap.length(rightEnd: end, island: 820...1100, screen: plain) == 318
                     && NotchMenuBarGap.length(rightEnd: end, island: 790...1130, screen: plain) == 348,
                     "the length reaches from where the items begin to the island's left end and margin")
        suite.expect(NotchMenuBarGap.length(rightEnd: 930, island: 606...906, screen: notched, notchWidth: 185) == 81,
                     "beside a camera the length keeps starting at the notch")
        suite.expect(!NotchMenuBarGap.needsLength(current: 334, wanted: 334.8)
                     && NotchMenuBarGap.needsLength(current: 334, wanted: 336),
                     "a length within a point is not worth laying the bar out again")

        func shows(enabled: Bool = true, presenting: Bool = true, hidden: Bool = false, floats: Bool = false,
                   displayHasMenuBar: Bool = true, isNotched: Bool = false, islandWidth: CGFloat = 300) -> Bool {
            NotchMenuBarGap.shows(enabled: enabled, presenting: presenting, hidden: hidden, floats: floats,
                                  displayHasMenuBar: displayHasMenuBar, isNotched: isNotched,
                                  islandWidth: islandWidth, cameraWidth: 185)
        }
        suite.expect(shows() && shows(isNotched: true), "an island in the menu bar keeps its gap")
        suite.expect(!shows(enabled: false) && !shows(presenting: false) && !shows(hidden: true),
                     "the setting off, a stopped island or a hidden one keeps no gap")
        suite.expect(!shows(floats: true) && !shows(displayHasMenuBar: false),
                     "a floating capsule or a display without the menu bar keeps no gap")
        suite.expect(!shows(isNotched: true, islandWidth: 185) && shows(isNotched: true, islandWidth: 290),
                     "an island no wider than the notch leaves the status items where they are")

        // Measured over Accessibility, the gap is one of the island's own status items.
        let placed = NotchMenuBarGap(position: 786, length: 334)
        let gapFrame = placed.frame(on: plain, barHeight: 24)
        suite.expect(gapFrame == CGRect(x: 800, y: 1056, width: 334, height: 24),
                     "the gap's frame follows from its position and length")
        let main = CGRect(x: 1700, y: 1056, width: 28, height: 24)
        let obs = CGRect(x: 1150, y: 1056, width: 30, height: 24)
        let left = CGRect(x: 770, y: 1056, width: 30, height: 24)
        let drawnGap = CGRect(x: 812, y: 1056, width: 322, height: 24)
        suite.expect(NotchMenuBarGap.removing(gapFrame, from: [left, main, drawnGap, obs])
                     == [left.offsetBy(dx: -8, dy: 0), main, obs],
                     "measuring leaves out the gap, even mid-change, and keeps every other item, the island's own icon too")
        // Items right against the gap, as macOS may lay them out, count from
        // the menu clearance past its ends, so fitting keeps the full wings.
        let tight = CGRect(x: 796, y: 1056, width: 328, height: 24)
        let against = [CGRect(x: 760, y: 1056, width: 36, height: 24), tight, CGRect(x: 1124, y: 1056, width: 26, height: 24)]
        let tightRoom = NotchMenuBarLayout.sideRoom(screen: plain, cameraWidth: 180, barHeight: 24,
                                                    occupied: NotchMenuBarGap.removing(tight, from: against))
        suite.expect(tightRoom == 74 && tightRoom.map { $0 >= (320 - 180) / 2 } == true,
                     "a gap four points past the island leaves fitting the island's full wings and its margin")
        suite.expect(NotchMenuBarGap.removing(nil, from: [main, obs]) == [main, obs],
                     "with no gap every status item counts")
        let room = NotchMenuBarLayout.sideRoom(screen: plain, cameraWidth: 180, barHeight: 24,
                                               occupied: NotchMenuBarGap.removing(gapFrame, from: [drawnGap, obs]))
        suite.expect(NotchMenuBarLayout.sideRoom(screen: plain, cameraWidth: 180, barHeight: 24, occupied: [drawnGap]) == nil
                     && room == 1150 - 8 - (960 + 90),
                     "the gap over the camera would leave no room; without it the room runs to the next icon")
    }

    /// Keep Awake as an activity: off until turned on, gated like the others,
    /// last in the automatic order, and read in whole minutes like a timer.
    private static func keepAwakeContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-keep-awake"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)
        suite.expect(!NotchKeepAwakeSupport.showsActivity(in: defaults),
                     "Keep Awake stays out of the closed island until it is turned on")
        defaults.set(true, forKey: DefaultsKey.notchKeepAwakeActivity)
        suite.expect(NotchKeepAwakeSupport.showsActivity(in: defaults), "the activity follows its own switch")
        defaults.set(false, forKey: AppFeature.keepAwake.availabilityKey)
        suite.expect(!NotchKeepAwakeSupport.showsActivity(in: defaults),
                     "removing Keep Awake from the hub removes its activity")
        defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchKeepAwakeSupport.showsActivity(in: defaults), "the island's master switch gates it too")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchKeepAwakeActivity),
                     "the switch travels in settings backup")

        suite.expect(NotchSupport.compactActivity(timer: false, downloads: false, music: true, keepAwake: true) == .music
                     && NotchSupport.compactActivity(timer: false, downloads: false, calendar: true,
                                                     music: false, keepAwake: true) == .calendar
                     && NotchSupport.compactActivity(timer: false, downloads: false, music: false, keepAwake: true) == .keepAwake,
                     "a session that can run all day yields to every other activity")
        suite.expect(NotchCompactActivity.keepAwake.module == .controls
                     && NotchCompactActivity.keepAwake.symbol == NotchControlItem.keepAwake.symbol,
                     "the activity opens Controls, where the Keep Awake tile is, and shows the tile's mark")

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let locale = Locale(identifier: "en_US")
        func text(_ seconds: TimeInterval) -> String {
            NotchKeepAwakeSupport.compactText(until: now.addingTimeInterval(seconds), now: now, locale: locale)
        }
        suite.expect(text(30 * 60) == "30m" && text(30 * 60 - 0.5) == "30m" && text(29 * 60 + 1) == "30m"
                     && text(29 * 60) == "29m",
                     "a new half-hour session reads 30m until a whole minute has passed")
        suite.expect(text(60 * 60) == "1h00" && text(61 * 60) == "1h01" && text(8 * 3600) == "8h00"
                     && text(26 * 3600 + 5 * 60) == "26h05",
                     "hours read as the timer's do, past the timer's three hours")
        suite.expect(text(59 * 60) == "59m" && text(1) == "1m" && text(0) == "1m" && text(-30) == "1m",
                     "the last minute, and an end the session has not reached yet, still read one minute")
        for seconds: TimeInterval in [1, 59.5, 60, 61, 1799.5, 3600, 3601, 28_800] {
            let end = now.addingTimeInterval(seconds)
            let start = NotchKeepAwakeSupport.tickStart(until: end, now: now)
            let next = start.addingTimeInterval(60)
            let minutes = NotchKeepAwakeSupport.minutesLeft(until: end, now: now)
            suite.expect(start <= now && next > now
                         && NotchKeepAwakeSupport.minutesLeft(until: end, now: next.addingTimeInterval(-0.001)) == minutes
                         && NotchKeepAwakeSupport.minutesLeft(until: end, now: next) == max(1, minutes - 1),
                         "the minute clock wakes when the reading changes, \(seconds) seconds before the end")
        }

        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        for barHeight: CGFloat in [22, 24, 32, 40] {
            for notched in [false, true] {
                let original = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                             cameraWidth: notched ? 180 : 0, menuBarHeight: barHeight,
                                             compactSideRoom: 200)
                for end in [nil, now.addingTimeInterval(45 * 60), now.addingTimeInterval(26 * 3600)] {
                    let wing = NotchKeepAwakeSupport.stripWing(until: end, now: now, locale: locale, in: original)
                    let compact = original.compactTimerGeometry(showsDownloads: false, wing: wing)
                    suite.expect(!compact.compactActivityUsesFooter
                                 && compact.compactActivityWingWidth >= min(wing, NotchTimerSupport.stripWingRange.upperBound)
                                 && compact.compactActivityWingWidth >= 42,
                                 "the cup and the time left keep readable wings beside the camera")
                }
            }
        }
    }

    private static func lowBatteryContracts(_ suite: TestSuite) {
        let keys = [DefaultsKey.notchLowBatteryTint, DefaultsKey.notchLowBatteryThreshold, DefaultsKey.notchLowBatteryEarly,
                    DefaultsKey.notchLowBatteryEarlyThreshold, DefaultsKey.notchLowBatteryMenuBar]
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchLowBatteryTint] as? Bool == false
               && Defaults.registeredDefaults[DefaultsKey.notchLowBatteryThreshold] as? Int == 10
               && Defaults.registeredDefaults[DefaultsKey.notchLowBatteryEarly] as? Bool == false
               && Defaults.registeredDefaults[DefaultsKey.notchLowBatteryEarlyThreshold] as? Int == 20
               && Defaults.registeredDefaults[DefaultsKey.notchLowBatteryMenuBar] as? Bool == true
               && SettingsBackupSupport.exportKeys().isSuperset(of: keys),
               "the low battery warning starts off at 10%, amber at 20%, and travels with settings backups")
        func warning(_ percent: Int?, plugged: Bool = false, tint: Bool = true, threshold: Int = 10,
                     early: Bool = false, earlyThreshold: Int = 20) -> BatteryWarning {
            NotchSupport.batteryWarning(percent: percent, externalConnected: plugged, tint: tint, threshold: threshold,
                                        early: early, earlyThreshold: earlyThreshold)
        }
        suite.expect(warning(10) == .low && warning(3) == .low && warning(11) == .none,
                     "the charge turns red at or below the chosen level")
        suite.expect(warning(5, tint: false) == .none && warning(15, tint: false, early: true) == .none,
                     "the charge keeps its color while the setting is off")
        suite.expect(warning(5, plugged: true) == .none && warning(15, plugged: true, early: true) == .none,
                     "a Mac on power never shows a warning")
        suite.expect(warning(nil) == .none, "an unknown charge is never shown as low")
        suite.expect(warning(25, threshold: 25) == .low && warning(26, threshold: 25) == .none, "the red level can be adjusted")
        suite.expect(warning(1, threshold: 0) == .low && warning(2, threshold: 0) == .none
                     && warning(99, threshold: 150) == .low && warning(100, threshold: 150) == .none,
                     "a stored red level outside the offered range is clamped")
        suite.expect(warning(20, early: true) == .early && warning(11, early: true) == .early
                     && warning(10, early: true) == .low && warning(21, early: true) == .none,
                     "the amber warning comes first and gives way to red")
        suite.expect(warning(15) == .none, "the amber warning stays off until it is turned on")
        suite.expect(warning(40, early: true, earlyThreshold: 40) == .early && warning(41, early: true, earlyThreshold: 40) == .none
                     && warning(100, early: true, earlyThreshold: 150) == .early,
                     "the amber level can be adjusted and is clamped")
        suite.expect(NotchSupport.earlyBatteryThreshold(28, above: 26) == 28
                     && NotchSupport.earlyBatteryThreshold(20, above: 26) == 27
                     && NotchSupport.earlyBatteryThreshold(10, above: 5) == 10
                     && NotchSupport.earlyBatteryThreshold(5, above: 99) == 100
                     && NotchSupport.earlyBatteryThreshold(150, above: 10) == 100
                     && NotchSupport.earlyBatteryThreshold(99, above: 150) == 100,
                     "the amber level stays within its range and above the red level")
        let domain = "com.vorssaint.tests.low-battery"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchSupport.batteryWarning(percent: 5, externalConnected: false, in: defaults) == .none,
                     "missing preferences show no warning")
        defaults.set(true, forKey: DefaultsKey.notchLowBatteryTint)
        defaults.set(true, forKey: DefaultsKey.notchLowBatteryEarly)
        suite.expect(NotchSupport.batteryWarning(percent: 10, externalConnected: false, in: defaults) == .low
                     && NotchSupport.batteryWarning(percent: 20, externalConnected: false, in: defaults) == .early
                     && NotchSupport.menuBarBatteryWarning(percent: 10, externalConnected: false, in: defaults) == .low,
                     "stored preferences use the default levels and reach the menu bar")
        defaults.set(false, forKey: DefaultsKey.notchLowBatteryMenuBar)
        suite.expect(NotchSupport.menuBarBatteryWarning(percent: 10, externalConnected: false, in: defaults) == .none
                     && NotchSupport.batteryWarning(percent: 10, externalConnected: false, in: defaults) == .low,
                     "the menu bar can keep its usual color while the island warns")
    }

    private static func alertContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.timer-alert"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchTimerSupport.isSoundEnabled(in: defaults), "timer sound is enabled by default")
        for enabled in [false, true] {
            defaults.set(enabled, forKey: DefaultsKey.notchTimerSoundEnabled)
            suite.expect(NotchTimerSupport.isSoundEnabled(in: defaults) == enabled,
                   "the sound preference survives reload")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchTimerSoundEnabled] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchTimerSoundEnabled),
               "the sound preference is registered and included in settings backup")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchCoversMenus] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchCoversMenus),
               "compact activity stays visible by default and the preference travels with settings backups")
        suite.expect(NotchSupport.coversMenus(in: defaults), "missing menu-cover preferences use the visible default")
        defaults.set(false, forKey: DefaultsKey.notchCoversMenus)
        suite.expect(!NotchSupport.coversMenus(in: defaults), "an explicit choice to leave menus uncovered is preserved")
        suite.expect(NotchTimerAlert.maximumDuration == .seconds(300), "an alarm is limited to five minutes")
        var sounds = 0, stops = 0
        var elapsed: Duration = .zero
        let alert = NotchTimerAlert(interval: .milliseconds(5), now: { .now.advanced(by: elapsed) },
                                   sound: { sounds += 1 }, stopSound: { stops += 1 })
        defer { alert.stop() }
        func wait(until predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(1)
            while !predicate() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
            }
        }
        func settle() {
            let end = Date().addingTimeInterval(0.04)
            wait { Date() >= end }
        }
        alert.start(enabled: false)
        settle()
        suite.expect(sounds == 0, "a timer completed with sound disabled stays silent")
        alert.start(enabled: true)
        suite.expect(sounds == 1, "an enabled sound alarm alerts immediately")
        alert.start(enabled: true)
        suite.expect(sounds == 1, "preference synchronization does not duplicate a pending alarm")
        wait { sounds >= 3 }
        suite.expect(sounds >= 3, "an unacknowledged sound alarm repeats")
        alert.start(enabled: false)
        let mutedSounds = sounds
        settle()
        suite.expect(sounds == mutedSounds && stops > 0, "disabling sound stops current playback and repetition")
        elapsed = .seconds(299)
        alert.start(enabled: true)
        suite.expect(sounds == mutedSounds + 1, "sound can resume within the original alarm budget")
        alert.suspend()
        let suspendedSounds = sounds
        settle()
        suite.expect(sounds == suspendedSounds, "suspension cancels sound playback")
        alert.start(enabled: true)
        elapsed = .seconds(301)
        let expirationStops = stops
        wait { stops > expirationStops }
        let expiredSounds = sounds
        alert.start(enabled: false)
        alert.start(enabled: true)
        alert.suspend()
        alert.start(enabled: true)
        settle()
        suite.expect(stops > expirationStops && sounds == expiredSounds,
               "five minutes stop playback; preference changes and suspension cannot restart an expired alarm")
        alert.stop()
        alert.start(enabled: true)
        suite.expect(sounds == expiredSounds + 1, "a new timer phase gets a fresh alert budget")
        alert.stop()
        let cancelledSounds = sounds
        settle()
        suite.expect(sounds == cancelledSounds, "dismissal prevents delayed playback")
    }

    private static func timerContracts(_ suite: TestSuite) {
        var session = NotchTimerSession()
        suite.expect(!session.hasSession, "an unused timer has no active session")
        session.start(mode: .timer, minutes: 5, now: 100)
        suite.expect(session.reading(at: 101.25) == 298.75, "countdown uses an absolute deadline, including fractional elapsed time")
        session.start(mode: .pomodoro, minutes: 25, now: 105)
        suite.expect(session.mode == .timer && session.deadline == 400, "starting twice cannot replace an active timer")
        session.pause(at: 160)
        suite.expect(session.isPaused && session.reading(at: 10_000) == 240, "paused time stays fixed across sleep")
        session.resume(at: 10_000)
        suite.expect(session.deadline == 10_240 && session.reading(at: 10_100) == 140, "resume preserves only the remaining duration")
        suite.expect(!session.finishIfDue(at: 10_239.999), "fractional time before the deadline is not complete")
        suite.expect(session.finishIfDue(at: 100_000) && session.completed, "returning from sleep finishes an overdue timer once")
        suite.expect(!session.finishIfDue(at: 100_001), "repeated callbacks cannot announce the same completion twice")
        session.cancel()
        suite.expect(!session.hasSession && session.completedFocuses == 0, "cancel discards the entire session")
        session.start(mode: .timer, minutes: 0, now: 0)
        suite.expect(session.duration == 60, "timer input cannot create an immediately expired session")
        session.pause(at: 60)
        suite.expect(session.completed && !session.isPaused, "pausing at the deadline completes instead of preserving a zero timer")
        session.cancel()
        session.start(mode: .timer, minutes: Int.max, now: 0)
        suite.expect(session.duration == 10_800, "corrupt duration input stays within three hours")
        suite.expect(NotchTimerSupport.timerMinutes(60) == 60 && NotchTimerSupport.timerMinutes(Int.max) == 180
               && NotchTimerSupport.timerMinutes(Int.min) == 1,
               "a remembered duration restored from a backup stays between a minute and three hours")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchTimerMinutes] as? Int == 15
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchTimerMinutes),
               "the timer's duration is registered and travels with settings backups")
        suite.expect(NotchTimerSupport.clockText(0.01) == "00:01" && NotchTimerSupport.clockText(-1) == "00:00"
               && NotchTimerSupport.clockText(.nan) == "00:00", "display rounds up and safely handles invalid remaining time")
        let clockCases: [(TimeInterval, String)] = [
            (59, "00:59"), (60, "01:00"), (3599, "59:59"), (3599.01, "1:00:00"),
            (3600, "1:00:00"), (3601, "1:00:01"), (8580, "2:23:00"),
            (10800, "3:00:00"), (.greatestFiniteMagnitude, "3:00:00"), (.infinity, "00:00")
        ]
        for (seconds, expected) in clockCases {
            suite.expect(NotchTimerSupport.clockText(seconds) == expected,
                   "timer clocks show hours at the hour boundary while preserving seconds: \(seconds)")
        }
        suite.expect(NotchTimerSupport.rollingValue("12:04", everySecond: false) == "12"
               && NotchTimerSupport.rollingValue("1:02:03", everySecond: false) == "1:02"
               && NotchTimerSupport.rollingValue("14m", everySecond: false) == "14m"
               && NotchTimerSupport.rollingValue("12:04", everySecond: true) == "12:04",
               "closed island clocks roll only above the seconds, open ones roll every second")
        let locale = Locale(identifier: "en_US")
        suite.expect(NotchTimerSupport.compactText(870, locale: locale) == "14m"
               && NotchTimerSupport.compactText(60, locale: locale) == "1m",
               "compact timers show whole remaining minutes without overstating a partial minute")
        suite.expect(NotchTimerSupport.compactText(59, locale: locale) == "59s"
               && NotchTimerSupport.compactText(0.01, locale: locale) == "1s",
               "compact timers switch to seconds for the final minute and never finish early")
        let compactCases: [(TimeInterval, String)] = [
            (3599, "59m"), (3599.01, "1h"), (3600, "1h"), (3659, "1h"),
            (3660, "1h 1m"), (8580, "2h 23m"), (10800, "3h")
        ]
        for (seconds, expected) in compactCases {
            suite.expect(NotchTimerSupport.compactText(seconds, locale: locale) == expected,
                   "compact timers and focus durations show hours and whole minutes: \(seconds)")
        }
        for invalid in [Double.nan, .infinity, -1, 0] {
            suite.expect(NotchTimerSupport.compactText(invalid, locale: locale) == "0s",
                   "invalid or expired compact times remain safe to display")
        }
        suite.expect(NotchTimerSupport.compactText(.greatestFiniteMagnitude, locale: locale) == "3h",
               "compact duration formatting preserves the timer's upper limit")
        let hourCases: [(TimeInterval, String)] = [
            (3600, "1h00"), (3659.9, "1h00"), (3660, "1h01"), (5700, "1h35"),
            (8580, "2h23"), (10800, "3h00"), (.greatestFiniteMagnitude, "3h00"), (.nan, "0h00")
        ]
        for (seconds, expected) in hourCases {
            suite.expect(NotchTimerSupport.compactHoursText(seconds) == expected,
                   "the compact strip writes hours as 1h35, never as a colon that reads like minutes and seconds: \(seconds)")
        }
        for language in AppLanguage.allCases {
            suite.expect(!NotchTimerSupport.compactText(870, locale: Locale(identifier: language.rawValue)).isEmpty,
                   "remaining time has a compact unit in every supported language")
            suite.expect(!NotchTimerSupport.compactText(8580, locale: Locale(identifier: language.rawValue)).isEmpty,
                   "hour and minute units are available in every supported language")
        }
        for width: CGFloat in [320, 480, 560] {
            for notched in [false, true] {
                let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
                let geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                             cameraWidth: notched ? 180 : 0,
                                             layout: .custom, customWidth: width, customHeight: 400)
                let setup = geometry.expandedSize(module: .timer)
                let active = geometry.expandedSize(module: .timer, timerHasSession: true)
                suite.expect(geometry.contentSize(for: setup).height
                       == NotchLayout.timer(mode: .timer, hasSession: false, height: geometry.contentBudget)
                       && geometry.contentSize(for: setup).height >= NotchLayout.timerMinimumRulerHeight
                       && geometry.contentSize(for: active).height == NotchLayout.timerRulerHeight && active == setup,
                       "timer setup has room for its ruler and clock, the modes and Start being in the top row; starting it keeps the island's size")
                suite.expect(screen.contains(geometry.frame(for: setup)) && screen.contains(geometry.frame(for: active))
                       && geometry.frame(for: setup).maxY == geometry.frame(for: active).maxY,
                       "starting a timer preserves the screen's top edge and keeps both sizes on screen")
            }
        }
        session.cancel()
        session.start(mode: .pomodoro, minutes: 5, now: 0, configuration: NotchPomodoroConfiguration(totalSessions: 5))
        var now: TimeInterval = 0
        for round in 1...4 {
            suite.expect(session.phase == .focus && session.duration == 1500, "each focus phase lasts 25 minutes")
            now += 1500
            suite.expect(session.finishIfDue(at: now), "each focus deadline completes")
            suite.expect(session.completedFocuses == round && !session.isRunning, "focus completion waits for explicit continuation")
            suite.expect(session.nextPhase == (round == 4 ? .longBreak : .shortBreak), "the fourth completed focus schedules a long break")
            session.startNext(at: now)
            let breakDuration: TimeInterval = round == 4 ? 900 : 300
            suite.expect(session.duration == breakDuration, "break durations distinguish the short and long phases")
            now += breakDuration
            _ = session.finishIfDue(at: now)
            suite.expect(session.nextPhase == .focus, "a completed break returns to focus")
            session.startNext(at: now)
        }
        now += 100_000
        suite.expect(session.finishIfDue(at: now) && session.completedFocuses == 5 && session.completed,
               "a long sleep never manufactures unattended pomodoro cycles")
        let request = CameraPreviewRequest()
        suite.expect(!request.isCancelled, "a new camera request can configure the shared capture session")
        request.cancel(); request.cancel()
        suite.expect(request.isCancelled, "closing a mirror cancels queued configuration idempotently")
    }

    private static func pomodoroContracts(_ suite: TestSuite) {
        let config = NotchPomodoroConfiguration(focusMinutes: 10, shortBreakMinutes: 2,
                                              longBreakMinutes: 7, longBreakInterval: 2, totalSessions: 3)
        var session = NotchTimerSession()
        session.start(mode: .pomodoro, minutes: 1, now: 0, configuration: config)
        suite.expect(session.duration == 600 && session.sessionNumber == 1 && !session.canStartNext,
               "custom focus duration starts the first session and cannot be skipped while active")
        session.pause(at: 100)
        session.resume(at: 1_000)
        suite.expect(session.deadline == 1_500 && session.configuration == config,
               "pause and resume preserve the cycle configuration and remaining focus time")
        var now = 1_500.0
        for round in 1...3 {
            suite.expect(session.finishIfDue(at: now) && session.completedFocuses == round,
                   "each configured focus session counts exactly once")
            suite.expect(session.sessionNumber == round && !session.finishIfDue(at: now + 1),
                   "completed phases retain their progress and reject duplicate completion")
            if round == 3 { break }
            suite.expect(session.canStartNext && !session.cycleFinished, "unfinished cycles offer explicit continuation")
            session.startNext(at: now)
            let expectedBreak = round == 1 ? 120.0 : 420.0
            suite.expect(session.duration == expectedBreak && session.phase == (round == 1 ? .shortBreak : .longBreak),
                   "configured interval chooses the correct short or long break duration")
            now += expectedBreak
            _ = session.finishIfDue(at: now)
            suite.expect(session.completedFocuses == round, "breaks do not count toward the focus-session goal")
            session.startNext(at: now)
            suite.expect(session.phase == .focus && session.duration == 600 && session.sessionNumber == round + 1,
                   "each new focus uses the same configuration and advances visible progress")
            now += 600
        }
        suite.expect(session.cycleFinished && !session.canStartNext && !session.isRunning,
               "the final focus ends the cycle without an extra break")
        let finished = session
        session.startNext(at: now + 1)
        suite.expect(session == finished, "continuation cannot restart a finished cycle")
        session.cancel()
        session.start(mode: .pomodoro, minutes: 1, now: 0,
                      configuration: NotchPomodoroConfiguration(longBreakInterval: 1, totalSessions: 1))
        _ = session.finishIfDue(at: 100_000)
        suite.expect(session.cycleFinished && session.completedFocuses == 1 && !session.canStartNext,
               "a one-session goal ends at focus completion even when a long break would otherwise be due")
        let bounded = NotchPomodoroConfiguration(focusMinutes: Int.max, shortBreakMinutes: Int.min,
            longBreakMinutes: Int.max, longBreakInterval: 0, totalSessions: Int.max)
        suite.expect(bounded.focusMinutes == 180 && bounded.shortBreakMinutes == 1 && bounded.longBreakMinutes == 60
               && bounded.longBreakInterval == 1 && bounded.totalSessions == 24,
               "restored out-of-range values cannot overflow deadlines or create invalid cycle intervals")
        let domain = "com.vorssaint.tests.pomodoro"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let keys: Set<String> = [DefaultsKey.notchPomodoroFocusMinutes, DefaultsKey.notchPomodoroShortBreakMinutes,
            DefaultsKey.notchPomodoroLongBreakMinutes, DefaultsKey.notchPomodoroLongBreakInterval,
            DefaultsKey.notchPomodoroTotalSessions, DefaultsKey.notchTimerMode]
        suite.expect(keys.isSubset(of: Set(Defaults.registeredDefaults.keys))
               && keys.isSubset(of: SettingsBackupSupport.exportKeys()),
               "all Pomodoro choices, including the selected mode, are registered and included in settings backup")
        defaults.set(45, forKey: DefaultsKey.notchPomodoroFocusMinutes)
        defaults.set(8, forKey: DefaultsKey.notchPomodoroShortBreakMinutes)
        defaults.set(20, forKey: DefaultsKey.notchPomodoroLongBreakMinutes)
        defaults.set(3, forKey: DefaultsKey.notchPomodoroLongBreakInterval)
        defaults.set(6, forKey: DefaultsKey.notchPomodoroTotalSessions)
        let saved = NotchPomodoroConfiguration.load(in: defaults)
        suite.expect(saved == NotchPomodoroConfiguration(focusMinutes: 45, shortBreakMinutes: 8,
            longBreakMinutes: 20, longBreakInterval: 3, totalSessions: 6), "saved choices restore the whole cycle")
        session.cancel()
        session.start(mode: .pomodoro, minutes: 1, now: 0, configuration: saved)
        defaults.set(1, forKey: DefaultsKey.notchPomodoroFocusMinutes)
        suite.expect(session.configuration == saved && session.duration == 2_700,
               "changes to saved preferences never rewrite an already running cycle")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, cameraWidth: 180)
        let setup = geometry.expandedSize(module: .timer, timerMode: .pomodoro)
        let active = geometry.expandedSize(module: .timer, timerHasSession: true, timerMode: .pomodoro)
        suite.expect(geometry.contentSize(for: setup).height
               == NotchLayout.timer(mode: .pomodoro, hasSession: false, height: geometry.contentBudget)
               && geometry.contentSize(for: setup).height <= geometry.contentBudget
               && geometry.contentSize(for: active).height == NotchLayout.timerRulerHeight && active.height < setup.height,
               "the Pomodoro setup fits the strip with its readouts under the ruler; running, its progress is in the top row and the island shortens")
    }

    private static func stopwatchContracts(_ suite: TestSuite) {
        var session = NotchTimerSession()
        suite.expect(session.reading(at: 5) == 300 && !session.countsUp, "an idle page still previews the countdown it would start")
        session.start(mode: .stopwatch, minutes: 15, now: 100)
        suite.expect(session.countsUp && session.phase == .stopwatch && session.isRunning && session.deadline == nil
               && session.duration == 0, "a stopwatch runs from zero with no deadline or preset duration")
        suite.expect(session.reading(at: 100) == 0 && session.reading(at: 161.25) == 61.25,
               "elapsed time grows from the anchor, including fractional seconds")
        suite.expect(session.reading(at: 99) == 0, "a clock that reads before its anchor never shows negative time")
        suite.expect(!session.finishIfDue(at: 1_000_000) && session.isRunning && !session.completed,
               "a stopwatch never completes on its own, however long it runs")
        session.start(mode: .timer, minutes: 5, now: 200)
        suite.expect(session.countsUp && session.anchor == 100, "starting twice cannot replace a running stopwatch")
        session.pause(at: 160)
        suite.expect(session.isPaused && !session.isRunning && session.reading(at: 10_000) == 60,
               "pausing holds the elapsed reading across sleep")
        session.pause(at: 170)
        suite.expect(session.reading(at: 10_000) == 60, "pausing a paused stopwatch changes nothing")
        session.resume(at: 10_000)
        suite.expect(session.isRunning && session.reading(at: 10_040.5) == 100.5,
               "resuming continues from the held reading, never from the wall clock gap")
        session.resume(at: 20_000)
        suite.expect(session.reading(at: 20_000) == 10_060, "resuming a running stopwatch changes nothing")
        session.pause(at: .nan)
        suite.expect(session.isRunning, "an invalid clock cannot pause a stopwatch")
        session.cancel()
        suite.expect(!session.hasSession && session.reading(at: 0) == 300 && !session.countsUp,
               "cancel discards the stopwatch and returns the page to its countdown preview")

        var countdown = NotchTimerSession()
        countdown.start(mode: .timer, minutes: 1, now: 0)
        for (elapsed, expected) in [(0.0, 1.0), (0.25, 0.75), (0.999, 0.001)] {
            let offset = NotchTimerSupport.secondBoundaryOffset(for: countdown, at: elapsed)
            suite.expect(abs(offset - expected) < 1e-9, "countdown ticks align to whole remaining seconds: \(elapsed)")
        }
        var stopwatch = NotchTimerSession()
        stopwatch.start(mode: .stopwatch, minutes: 1, now: 0)
        for (elapsed, expected) in [(0.0, 1.0), (0.25, 0.75), (61.999, 0.001)] {
            let offset = NotchTimerSupport.secondBoundaryOffset(for: stopwatch, at: elapsed)
            suite.expect(abs(offset - expected) < 1e-9, "stopwatch ticks align to whole elapsed seconds: \(elapsed)")
        }
        for (session, name) in [(countdown, "countdown"), (stopwatch, "stopwatch")] {
            for now in stride(from: 0.0, through: 59.0, by: 0.37) {
                let offset = NotchTimerSupport.secondBoundaryOffset(for: session, at: now)
                let before = NotchTimerSupport.clockText(for: session, at: now + offset - 0.001)
                let after = NotchTimerSupport.clockText(for: session, at: now + offset + 0.001)
                suite.expect(offset > 0 && offset <= 1 && before != after,
                       "the next tick lands just after the \(name) reading changes: \(now)")
            }
        }
        suite.expect(NotchTimerSupport.secondBoundaryOffset(for: countdown, at: -.infinity) == 0,
               "an unreadable clock schedules an immediate tick instead of an invalid date")
        // A timeline renders the first entry of its schedule at once and wakes
        // only at the next one, so the boundary ahead has to be the second
        // entry, with the first already behind now.
        let reference = Date()
        for (session, name) in [(countdown, "countdown"), (stopwatch, "stopwatch")] {
            for now in stride(from: 0.0, through: 3.0, by: 0.23) {
                let boundary = NotchTimerSupport.secondBoundaryOffset(for: session, at: now)
                let start = reference.addingTimeInterval(NotchTimerSupport.tickScheduleOffset(for: session, at: now))
                var entries = PeriodicTimelineSchedule(from: start, by: 1).entries(from: reference, mode: .normal).makeIterator()
                let first = entries.next()?.timeIntervalSince(reference) ?? .nan
                let second = entries.next()?.timeIntervalSince(reference) ?? .nan
                let third = entries.next()?.timeIntervalSince(reference) ?? .nan
                suite.expect(first <= 0 && first > -1 && abs(second - boundary) < 1e-6 && abs(third - boundary - 1) < 1e-6,
                       "the clock's schedule starts behind now, so its first wake lands on the \(name) boundary "
                       + "instead of skipping it: \(now)")
            }
        }

        let stopwatchCases: [(TimeInterval, String)] = [
            (0, "00:00"), (0.999, "00:00"), (1, "00:01"), (59.9, "00:59"), (60, "01:00"),
            (3599.99, "59:59"), (3600, "1:00:00"), (3661, "1:01:01"), (10_800, "3:00:00"),
            (86_399, "23:59:59"), (359_999, "99:59:59"), (400_000, "99:59:59"),
            (.greatestFiniteMagnitude, "99:59:59"), (-1, "00:00"), (.nan, "00:00"), (.infinity, "00:00")
        ]
        for (seconds, expected) in stopwatchCases {
            suite.expect(NotchTimerSupport.stopwatchText(seconds) == expected,
                   "elapsed clocks round down, grow past the timer's three hours and saturate safely: \(seconds)")
        }
        let compactStopwatchCases: [(TimeInterval, String)] = [
            (0, "00:00"), (42.7, "00:42"), (599, "09:59"), (754, "12:34"), (3599.9, "59:59"),
            (3600, "1h00"), (3720, "1h02"), (5700, "1h35"), (36_000, "10h00"),
            (.greatestFiniteMagnitude, "99h59"), (-1, "00:00"), (.nan, "00:00")
        ]
        for (seconds, expected) in compactStopwatchCases {
            suite.expect(NotchTimerSupport.compactStopwatchText(seconds) == expected,
                   "the compact strip keeps a stopwatch's seconds until hours take their place: \(seconds)")
        }
        let locale = Locale(identifier: "en_US")
        suite.expect(NotchTimerSupport.clockText(for: stopwatch, at: 61.9) == "01:01"
               && NotchTimerSupport.clockText(for: countdown, at: 0.1) == "01:00",
               "session clocks read elapsed time up and remaining time down")
        suite.expect(NotchTimerSupport.compactText(for: stopwatch, at: 61.9, locale: locale) == "01:01"
               && NotchTimerSupport.compactText(for: countdown, at: 0.1, locale: locale) == "1m",
               "compact session readings keep each mode's own notation")
        var hours = NotchTimerSession()
        hours.start(mode: .timer, minutes: 120, now: 0)
        suite.expect(NotchTimerSupport.compactText(for: hours, at: 1, locale: locale) == "1h59"
               && NotchTimerSupport.compactText(for: hours, at: 3600, locale: locale) == "1h00"
               && NotchTimerSupport.compactText(for: hours, at: 3601, locale: locale) == "59m",
               "compact countdowns still switch from hours to minutes at the hour boundary")

        let domain = "com.vorssaint.tests.timer-mode"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchTimerSupport.savedMode(in: defaults) == .timer, "a fresh install opens the countdown")
        for mode in NotchTimerMode.allCases {
            defaults.set(mode.rawValue, forKey: DefaultsKey.notchTimerMode)
            suite.expect(NotchTimerSupport.savedMode(in: defaults) == mode, "the chosen mode survives reload: \(mode)")
        }
        defaults.set("countdown", forKey: DefaultsKey.notchTimerMode)
        suite.expect(NotchTimerSupport.savedMode(in: defaults) == .timer, "an unknown saved mode falls back to the countdown")
        suite.expect(NotchTimerMode.allCases.last == .stopwatch && NotchTimerMode.allCases.first == .timer,
               "the stopwatch joins the mode row after the existing modes, keeping their positions")

        for width: CGFloat in [360, 480, 560] {
            let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32,
                                         cameraWidth: 180, layout: .custom, customWidth: width, customHeight: 400)
            let setup = geometry.expandedSize(module: .timer, timerMode: .stopwatch)
            let active = geometry.expandedSize(module: .timer, timerHasSession: true, timerMode: .stopwatch)
            suite.expect(geometry.contentSize(for: setup).height
                   == NotchLayout.timer(mode: .stopwatch, hasSession: false, height: geometry.contentBudget)
                   && setup.height == geometry.expandedSize(module: .timer).height,
                   "the stopwatch keeps its clock in the countdown's ruler row, so switching between them never resizes the island")
            suite.expect(active == geometry.expandedSize(module: .timer, timerHasSession: true),
                   "a running stopwatch shares the countdown's control row")
        }
    }

    /// The modes and Start sit in the island's top row, on a page no wider
    /// than its ruler and clock need. Beside the camera the modes' menu
    /// takes one side and Start the other; the menu's name may narrow, never
    /// lose letters, and where the sections button leaves its side too
    /// little for a name the menu shows the mode's glyph. A full row of the
    /// page's own width holds the sections button, the whole name and
    /// Start, in every language.
    private static func modePickerContracts(_ suite: TestSuite) {
        let layout = NotchTimerSupport.ModePicker.self
        let font = NSFont.systemFont(ofSize: layout.labelSize, weight: .medium)
        let button = NotchBand.sectionsButtonRoom
        let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))?.size.width ?? 0
        let glyph = ["timer", "stopwatch"].compactMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: layout.labelSize, weight: .medium))?.size.width
        }.max() ?? 0
        let glyphMenu = glyph + layout.menuSpacing + chevron + layout.labelPadding * 2
        // The timer's page as the island opens it, in a display's own size
        // or a capsule without a camera.
        func page(camera: CGFloat, _ size: NotchSize, custom: Double = NotchSize.defaultWidth,
                  sectionsButton: Bool) -> NotchGeometry {
            NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: camera > 0 ? 32 : 0,
                          cameraWidth: camera, layout: size, customWidth: custom, silhouette: camera > 0 ? .notch : .capsule)
                .page(.timer, controls: [], sectionsButton: sectionsButton)
        }
        func band(_ geometry: NotchGeometry) -> NotchBand { NotchBand(geometry: geometry, contentWidth: geometry.contentWidth) }
        let compact = page(camera: 180, .compact, sectionsButton: false)
        let wrapped: CGFloat = max(NotchLayout.timerContentWidth, 180 + compact.pageBandSide * 2)
        suite.expect(band(compact).besideCamera && compact.pageContentWidth == NotchLayout.timerContentWidth
               && compact.contentWidth == wrapped
               && band(compact).side == compact.pageBandSide - NotchBand.cameraClearance
               && chevron > 0 && glyph > 0,
               "the timer's row wraps a 180-point camera on a page no wider than its own: \(band(compact).side)")
        suite.expect(layout.height > layout.labelSize + 2 && layout.labelPadding > 0
               && NotchLayout.timerStartHeight == 28,
               "every mode label keeps room for its underline and around its text, and Start is as tall as the row's buttons")
        var sizes: [(NotchSize, Double)] = [(.compact, NotchSize.defaultWidth), (.spacious, NotchSize.defaultWidth)]
        sizes += stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 20).map { (.custom, $0) }
        let cameras: [CGFloat] = [0, 156, 170, 180, 185, 190, 200, 208, 210, 224]
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchActivities(language)
            let labels = [text.timer, text.pomodoro, text.stopwatch]
            suite.expect(Set(labels).count == 3 && labels.allSatisfy { !$0.isEmpty },
                   "each mode has its own name: \(language)")
            let widths = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            let named = (widths.max() ?? 0) + layout.menuSpacing + chevron + layout.labelPadding * 2
            let narrowed = (widths.max() ?? 0) * layout.menuMinimumScale + layout.menuSpacing + chevron + layout.labelPadding * 2
            let startFont = NSFont.systemFont(ofSize: NotchTimerSupport.StartButton.labelSize, weight: .semibold)
            let start = (text.start as NSString).size(withAttributes: [.font: startFont]).width + NotchTimerSupport.StartButton.padding * 2
            var floating = true, spacious = true, shown = true, starts = true, rows = true
            var narrowest = CGFloat.infinity
            for camera in cameras {
                for (size, custom) in sizes {
                    for sectionsButton in [false, true] {
                        let geometry = page(camera: camera, size, custom: custom, sectionsButton: sectionsButton)
                        let row = band(geometry)
                        guard row.besideCamera else {
                            // Across the top the marks give way before the name narrows.
                            rows = rows && (sectionsButton ? button : 0) + named + 12 + start <= row.side
                            continue
                        }
                        // What the menu's side keeps past the button, as the row draws it.
                        let room = row.side - (sectionsButton ? button : 0)
                        let fits = layout.menuNamesFit(labels, in: row.leadingRoom)
                        shown = shown && (fits ? narrowed <= room : glyphMenu <= room)
                        starts = starts && start <= row.side
                        if !sectionsButton {
                            // With the floating button the menu always names the mode.
                            floating = floating && fits
                            narrowest = min(narrowest, room)
                        } else if size == .spacious {
                            // The preset most islands use keeps the name's room past the button.
                            spacious = spacious && fits
                                && room == band(page(camera: camera, size, sectionsButton: false)).side
                        }
                    }
                }
            }
            suite.expect(floating,
                   "every mode's name names the menu beside the camera in \(language), down to \(Int(narrowest)) points")
            suite.expect(spacious,
                   "past the sections button the spacious island keeps the name's room beside every camera in \(language)")
            suite.expect(shown,
                   "the menu's name never narrows past its minimum, and where it would the mode's glyph fits instead, in \(language): \(Int(narrowed))")
            suite.expect(starts, "Start fits its side beside every camera in \(language): \(Int(start))")
            suite.expect(rows,
                   "a full top row holds the sections button, the whole name and Start in \(language): \(Int(button + named + 12 + start))")
        }
        suite.expect(NotchPomodoroOption.focus.range == 1...180
                     && NotchPomodoroOption.shortBreak.range == 1...60
                     && NotchPomodoroOption.longBreak.range == 1...60
                     && NotchPomodoroOption.longBreakInterval.range == 1...24
                     && NotchPomodoroOption.totalSessions.range == 1...24,
                     "Pomodoro menus preserve every minute and session count accepted by the saved configuration")
        let defaults = NotchPomodoroConfiguration()
        suite.expect(NotchPomodoroOption.focus.range.contains(defaults.focusMinutes)
               && NotchPomodoroOption.shortBreak.range.contains(defaults.shortBreakMinutes)
               && NotchPomodoroOption.longBreak.range.contains(defaults.longBreakMinutes)
               && NotchPomodoroOption.longBreakInterval.range.contains(defaults.longBreakInterval)
               && NotchPomodoroOption.totalSessions.range.contains(defaults.totalSessions),
               "the default cycle is always on the menus")
    }

    private static func rulerContracts(_ suite: TestSuite) {
        for (minute, expected) in [(1, "1"), (55, "55"), (60, "1h00"), (65, "1h05"),
                                   (140, "2h20"), (143, "2h23"), (180, "3h00")] {
            suite.expect(NotchTimerRulerScale.label(for: minute) == expected,
                   "ruler labels write hours with an h, so an hour mark never reads like the minute clock")
        }
        for minute in [1, 15, 90, 180] {
            suite.expect(NotchTimerRulerScale.offset(of: minute, selected: minute) == 0,
                   "the chosen minute stays under the pointer, including the initial value and both endpoints")
        }
        for width in [96.0, 180, 300, 560] {
            var filled = true
            var selectedVisible = true
            var clicksMatch = true
            for selected in 1...180 {
                let pointer = NotchTimerRulerScale.selectionX(selected: selected, width: width)
                let first = pointer + NotchTimerRulerScale.offset(of: 1, selected: selected)
                let last = pointer + NotchTimerRulerScale.offset(of: 180, selected: selected)
                filled = filled && first <= 24 && last >= width - 24
                selectedVisible = selectedVisible && pointer >= 24 && pointer <= width - 24
                for minute in 1...180 {
                    let x = pointer + NotchTimerRulerScale.offset(of: minute, selected: selected)
                    guard (0...width).contains(x) else { continue }
                    let clicked = NotchTimerRulerScale.moving(Double(selected), by: -(x - pointer))
                    clicksMatch = clicksMatch && NotchTimerRulerScale.minute(clicked) == minute
                }
            }
            suite.expect(filled, "the timer ruler fills its width near both limits without an empty half at \(width) points")
            suite.expect(selectedVisible, "every selected minute stays visible with room for its label at \(width) points")
            suite.expect(clicksMatch, "visible ruler ticks select their own minute even when the pointer leaves the center at \(width) points")
        }
        suite.expect(NotchTimerRulerScale.selectionX(selected: 5, width: 300) == 80
               && NotchTimerRulerScale.selectionX(selected: 90, width: 300) == 150
               && NotchTimerRulerScale.selectionX(selected: 180, width: 300) == 276,
               "short durations start near the leading edge, middle durations stay centered and the maximum reaches the trailing edge")
        suite.expect(NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: 14)) == 14
               && NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: -14)) == 16,
               "dragging the ruler by one tick changes one minute in the matching direction")
        for minute in [1, 5, 15, 30, 180] {
            let offset = NotchTimerRulerScale.offset(of: minute, selected: 15)
            suite.expect(NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: -offset)) == minute,
                   "clicking a drawn tick selects its own minute, with the same spacing used by dragging")
        }
        var value = 15.0
        for _ in 0..<3 { value = NotchTimerRulerScale.moving(value, by: 2) }
        suite.expect(NotchTimerRulerScale.minute(value) == 15, "small movements do not repeatedly change the selected tick")
        value = NotchTimerRulerScale.moving(value, by: 2)
        suite.expect(NotchTimerRulerScale.minute(value) == 14, "fine scroll and drag deltas accumulate until crossing a tick")
        value = NotchTimerRulerScale.moving(1, by: 10_000)
        suite.expect(value == 1 && NotchTimerRulerScale.moving(value, by: -14) == 2,
               "dragging beyond the minimum does not leave a dead zone when reversing")
        value = NotchTimerRulerScale.moving(180, by: -10_000)
        suite.expect(value == 180 && NotchTimerRulerScale.moving(value, by: 14) == 179,
               "dragging beyond the maximum allows an immediate reversal")
        suite.expect(NotchTimerRulerScale.minute(.nan) == 1 && NotchTimerRulerScale.minute(.infinity) == 1
               && NotchTimerRulerScale.minute(.greatestFiniteMagnitude) == 180,
               "invalid or excessive ruler values cannot escape the supported duration range")
    }

    private static func compactTimerContracts(_ suite: TestSuite) {
        func companions(of primary: NotchCompactActivity, timer: Bool = true, running: Bool = true,
                        calendar: Bool = true) -> [NotchCompactActivity] {
            NotchSupport.compactCompanions(of: primary, timer: timer, running: running, downloads: true, agents: true,
                                           calendar: calendar, music: true)
        }
        suite.expect(companions(of: .timer) == [.downloads, .agents, .calendar, .music],
                     "a running timer offers every supported pair instead of silently choosing one")
        suite.expect(companions(of: .timer, running: false) == [.downloads],
                     "a paused or finished timer keeps its status mark beside agents, an event or music")
        suite.expect(companions(of: .timer, timer: false).isEmpty && companions(of: .calendar, calendar: false).isEmpty,
                     "an activity that is not showing offers no pair")
        suite.expect(companions(of: .calendar, running: false) == [.downloads, .agents, .music],
                     "an event's clock keeps its side beside a download, agents or music, whatever the timer does")
        suite.expect([NotchCompactActivity.downloads, .agents, .music].allSatisfy { companions(of: $0).isEmpty },
                     "downloads, agents and music need both wings and cannot lead a pair")
        suite.expect(NotchActivityCombination(primary: .calendar, companion: .music).title(.enUS) == "Music + Calendar"
                     && NotchActivityCombination(primary: .timer, companion: .calendar).title(.enUS) == "Calendar + Timer",
                     "a pair is named in the order the island shows it, the companion left of the camera first")
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        for barHeight: CGFloat in [16, 22, 24, 32, 40, 64] {
            for notched in [false, true] {
                for layout in NotchSize.allCases {
                    for room: CGFloat in [-1, 0, 27, 36, 43, 44, 52, 64, 71, 72, 72.9, 79, 80, 100, 200, .nan, .infinity] {
                        let original = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                                     cameraWidth: notched ? 180 : 0, layout: layout,
                                                     menuBarHeight: barHeight, compactSideRoom: room)
                        for downloads in [false, true] {
                            let compact = original.compactTimerGeometry(showsDownloads: downloads)
                            if room.isFinite && room >= 64 {
                                suite.expect(!compact.compactActivityUsesFooter
                                       && compact.compactActivityWingWidth == min(room, downloads ? 80 : 64).rounded(.down),
                                       "timer wings keep their readable width around larger cameras, including simultaneous downloads")
                                suite.expect(compact.compactActivityCameraGap == original.cameraWidth
                                       && compact.compactActivityContentHeight == original.stripHeight,
                                       "narrower timer wings still clear the camera and keep the cutout's height")
                                let cover = compact.compactMusicArtworkSide
                                suite.expect(compact.compactActivityEdgeInset(boxHeight: cover, radius: compact.compactMusicArtworkRadius)
                                                + cover <= compact.compactActivityWingWidth,
                                       "the playing track's cover fits the timer's left wing without touching its curve")
                            } else if notched {
                                suite.expect(!compact.compactActivityUsesFooter && compact.compactActivityWingWidth == 0,
                                       "unavailable menu space retracts timer wings without drawing over adjacent menus")
                                suite.expect(compact.activationArea(in: compact.compactActivitySize, hasHeader: false,
                                                             compactActivity: true).size == compact.compactActivitySize,
                                       "a retracted timer keeps the whole camera region available to open its controls")
                            } else {
                                suite.expect(!compact.compactActivityUsesFooter,
                                       "a simulated timer never falls back below the menu bar")
                                suite.expect(compact.compactActivityWingWidth == 0
                                       && compact.compactActivitySize.height == original.menuBarHeight,
                                       "a simulated timer with no side room keeps only the camera profile within the menu bar")
                            }
                            let positioned = compact.frame(for: compact.compactActivitySize)
                            suite.expect(screen.contains(positioned), "compact timer placement stays within the screen")
                            if notched {
                                suite.expect(positioned.maxY == screen.maxY && positioned.height == original.cameraHeight
                                       && compact.compactActivityTopPadding == 0,
                                       "timer and simultaneous downloads stay beside the camera through menu-space changes")
                            }
                        }
                    }
                }
            }
        }
        let roomy = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 185, layout: .spacious,
                                  compactSideRoom: 300)
        suite.expect(roomy.compactTimerGeometry(showsDownloads: false, wing: 30).compactActivityWingWidth == 44
                        && roomy.compactTimerGeometry(showsDownloads: false, wing: 30).compactActivitySize.width == 185 + 88,
                     "a short reading beside the cover narrows the timer's wings, leaving no empty band at the ends")
        suite.expect(roomy.compactTimerGeometry(showsDownloads: false, wing: 51.2).compactActivityWingWidth == 52
                        && roomy.compactTimerGeometry(showsDownloads: false, wing: 300).compactActivityWingWidth == 64
                        && roomy.compactTimerGeometry(showsDownloads: true, wing: 30).compactActivityWingWidth == 80,
                     "timer wings take what the reading needs up to their old width; a download keeps its own")
    }

    /// Compact strips measure their margins from the silhouette rather than
    /// from a flat padding, so the promise is geometric: whatever a wing draws
    /// keeps the shared gap from the curve, and the download reading still
    /// fits the narrowest wing in every language.
    private static func compactMarginContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let gap = NotchLayout.compactEdgeGap
        /// Distance from a centred box, anchored at `inset`, to the silhouette.
        func clearance(_ geometry: NotchGeometry, inset: CGFloat, boxHeight: CGFloat, radius: CGFloat) -> CGFloat {
            let surface = geometry.compactActivitySize
            let shoulder = geometry.compactActivityShoulder
            let corner = min(NotchLayout.surfaceRadius(height: surface.height),
                             (surface.width - shoulder * 2) / 2)
            let centre = CGPoint(x: shoulder + corner, y: surface.height - corner)
            let x = inset + geometry.compactActivityHorizontalPadding + radius
            let y = surface.height - (geometry.compactActivityContentHeight - boxHeight) / 2 - radius
            if y <= centre.y { return x - radius - shoulder }
            if x >= centre.x { return surface.height - y - radius }
            return corner - hypot(x - centre.x, y - centre.y) - radius
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NotchDownloadSupport.percentSize, weight: .medium)
        for barHeight: CGFloat in [24, 32, 37, 40, 44, 64] {
            for room: CGFloat in [44, 52, 56, 72, 100, 200] {
                for notched in [true, false] {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                                 cameraWidth: notched ? 180 : 160, layout: .compact,
                                                 menuBarHeight: barHeight, compactSideRoom: room)
                    let wing = geometry.compactActivityWingWidth
                    suite.expect(wing == 0 || wing >= 44,
                           "a compact strip either retracts its wings or keeps them wide enough to fill")
                    // Cover, equalizer bar, timer icon, download arrow and the
                    // ink of a percentage. A box too tall for the strip has no
                    // inset that can clear the curve, and keeps the flat margin.
                    for (box, radius) in [(26.0, 26.0 * 0.28), (16.0, 0.9), (20.0, 10.0), (17.0, 8.5),
                                          (NotchDownloadSupport.percentSize * 0.72, 0.0)] {
                        let side = min(box, geometry.compactActivityContentHeight - gap * 2)
                        guard side > 0 else { continue }
                        let corner = min(radius, side / 2)
                        let inset = geometry.compactActivityEdgeInset(boxHeight: side, radius: corner)
                        suite.expect(clearance(geometry, inset: inset, boxHeight: side, radius: corner) >= gap - 0.01,
                               "compact strip content keeps its breathing room from the curved edge")
                    }
                    guard wing >= 44 else { continue }
                    let inset = NotchDownloadSupport.percentInset(in: geometry)
                    for language in AppLanguage.allCases {
                        let reading = (1.0).formatted(NotchDownloadSupport.percentFormat(language)) as NSString
                        let width = reading.size(withAttributes: [.font: font]).width
                        suite.expect(wing - inset >= width * NotchDownloadSupport.percentMinimumScale,
                               "a download reading its last percent keeps one whole line in every language")
                    }
                }
            }
        }
    }

    /// A crowded menu keeps the short arrow and progress; a wider wing names
    /// the file again without reserving the same width for every filename.
    private static func compactDownloadContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NotchDownloadSupport.percentSize, weight: .medium)
        for layout in NotchSize.allCases {
            for barHeight: CGFloat in [24, 32, 37, 44] {
                for room: CGFloat in [0, 30, 44, 50, 56, 72, 200, 600] {
                    for notched in [true, false] {
                        let geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                                     cameraWidth: notched ? 180 : 160, layout: layout,
                                                     menuBarHeight: barHeight, compactSideRoom: room)
                        let download = geometry.compactDownloadGeometry()
                        let size = download.compactActivitySize
                        if download.compactActivityUsesFooter {
                            suite.expect(notched && room < 44 && size.width == geometry.cameraWidth,
                                   "only a crowded physical camera still moves a download below it")
                            continue
                        }
                        let wing = download.compactActivityWingWidth
                        suite.expect(wing == (room >= 44 ? min(56, room) : 0)
                               && size.width == download.cameraWidth + wing * 2 && size.height == geometry.stripHeight,
                               "a download's wings hold its arrow and progress beside the camera, never the wide strip")
                        guard wing > 0 else { continue }
                        let iconSize = min(17, download.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2)
                        suite.expect(download.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2) + iconSize <= wing,
                               "the download arrow fits its wing past the curved edge")
                        let inset = NotchDownloadSupport.percentInset(in: download)
                        for language in AppLanguage.allCases {
                            let reading = (1.0).formatted(NotchDownloadSupport.percentFormat(language)) as NSString
                            suite.expect(wing - inset >= reading.size(withAttributes: [.font: font]).width
                                            * NotchDownloadSupport.percentMinimumScale,
                                   "a download reading its last percent keeps one whole line in every language")
                        }
                    }
                }
            }
        }
        let narrow = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180,
                                   menuBarHeight: 32, compactSideRoom: 80)
        suite.expect(NotchDownloadSupport.compactWing(for: "a.zip", in: narrow) == 56
                     && !NotchDownloadSupport.showsCompactName(in: narrow.compactDownloadGeometry()),
                     "crowded menus keep the short download indicator without a clipped file name")
        let roomy = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180,
                                  menuBarHeight: 32, compactSideRoom: 200)
        let short = NotchDownloadSupport.compactWing(for: "a.zip", in: roomy)
        let long = NotchDownloadSupport.compactWing(for: "a much longer download filename.zip", in: roomy)
        suite.expect(short >= 64 && short < NotchDownloadSupport.compactNameWingThreshold
                     && short < long && long <= 160
                     && NotchDownloadSupport.compactWing(for: nil, in: roomy) == 56,
                     "short filenames do not reserve an empty 94-point wing; long names have a cap")
        for name in ["a.zip", "installer.dmg", "unknown-size.bin"] {
            let wing = NotchDownloadSupport.compactWing(for: name, in: roomy)
            let strip = roomy.compactDownloadGeometry(wing: wing)
            let icon = min(17, strip.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2)
            let content = NSHostingView(rootView: HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: icon))
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }).fittingSize.width
            suite.expect(strip.compactActivityEdgeInset(boxHeight: icon, radius: icon / 2) + content + 4 <= wing + 0.5,
                         "the measured download wing holds the whole name \(name) beside its arrow")
        }
        for layout in [NotchSize.compact, .spacious] {
            let wideMenu = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180,
                                         layout: layout, menuBarHeight: 32, compactSideRoom: 200)
            suite.expect(wideMenu.compactDownloadGeometry(wing: short).compactActivityWingWidth == short
                         && wideMenu.compactDownloadGeometry(wing: long).compactActivityWingWidth == long,
                         "the 440/520-point music preference does not stretch a download beyond its measured name")
        }
        for room in [CGFloat(94), 110, 160, 200] {
            var constrained = roomy
            constrained.compactSideRoom = room
            let download = constrained.compactDownloadGeometry(wing: long)
            suite.expect(download.compactActivityWingWidth == min(room, long)
                         && NotchDownloadSupport.showsCompactName(in: download),
                         "a download name fits within measured menu room once 94 points are available")
        }
    }

    private static func accessoryContracts(_ suite: TestSuite) {
        for (name, symbol) in [("airpods", "airpods"), ("AIRPODS PRO", "airpodspro"),
                               ("My airpods pro 2", "airpodspro"), ("airpods max", "airpodsmax"),
                               ("Max's airpods", "airpods"), ("Wireless Headphones", "headphones")] {
            suite.expect(NotchAccessorySupport.symbol(for: .audio, name: name) == symbol,
                   "recognized headset families use their native symbol, with generic audio as fallback")
        }
        suite.expect(NotchAccessorySupport.symbol(for: .keyboard, name: "Keyboard") == "keyboard"
               && NotchAccessorySupport.symbol(for: .device, name: "Device") == "dot.radiowaves.left.and.right"
               && NotchAccessorySupport.symbol(for: .device, name: "Alex’s Magic Trackpad") == "rectangle.and.hand.point.up.left",
               "model-specific audio symbols preserve other accessory types")
        for kind: PeripheralBatteryKind in [.audio, .keyboard, .mouse, .trackpad, .device] {
            let symbol = NotchAccessorySupport.symbol(for: kind, name: "Device")
            suite.expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                         "accessory indicators use symbols available on this macOS version")
        }
        // A renamed accessory still announces its Bluetooth class of device.
        for (major, minor, symbol) in [(UInt32(0x05), UInt32(0x25), "rectangle.and.hand.point.up.left"),
                                       (0x05, 0x20, "computermouse"), (0x05, 0x10, "keyboard"),
                                       (0x05, 0x30, "keyboard"), (0x05, 0x02, "gamecontroller"),
                                       (0x05, 0x03, "av.remote"), (0x04, 0x06, "headphones"),
                                       (0x04, 0x01, "headphones"), (0x04, 0x05, "hifispeaker"),
                                       (0x04, 0x08, "car"), (0x07, 0x01, "applewatch"),
                                       (0x06, 0x20, "printer"), (0x08, 0x04, "gamecontroller"),
                                       (0x00, 0x00, "dot.radiowaves.left.and.right"),
                                       (0x1F, 0x00, "dot.radiowaves.left.and.right")] {
            let resolved = NotchAccessorySupport.symbol(name: "Kitchen", majorClass: major, minorClass: minor)
            suite.expect(resolved == symbol && NSImage(systemSymbolName: resolved, accessibilityDescription: nil) != nil,
                         "a renamed accessory takes its icon from its class of device (\(major), \(minor))")
        }
        suite.expect(NotchAccessorySupport.symbol(name: "Alex’s Magic Keyboard", majorClass: 0x05, minorClass: 0x25) == "keyboard"
               && NotchAccessorySupport.symbol(name: "AirPods Pro", majorClass: 0x04, minorClass: 0x05) == "airpodspro",
               "a name that says what the accessory is outranks its announced class")
        func device(_ percent: Int, id: String = "HID:1", name: String = "Keyboard") -> PeripheralBatteryDevice {
            PeripheralBatteryDevice(id: id, name: name, percent: percent, kind: .keyboard)
        }
        var battery = NotchAccessoryBatteryState()
        suite.expect(battery.consume([device(19)]).isEmpty, "enabling accessory alerts establishes a silent baseline even when already low")
        suite.expect(battery.consume([device(18)]).isEmpty && battery.consume([]).isEmpty,
               "the same low episode and missing readings do not create another warning")
        suite.expect(battery.consume([device(25)]).isEmpty, "a measured recharge rearms the low battery warning")
        suite.expect(battery.consume([device(20)]).count == 1, "dropping to 20 percent warns once")
        suite.expect(battery.consume([device(21)]).isEmpty && battery.consume([device(20)]).isEmpty,
               "threshold noise cannot repeatedly alert")
        suite.expect(battery.consume([device(18, id: "Bluetooth:1")]).isEmpty,
               "switching telemetry sources for the same accessory preserves its low episode")
        suite.expect(battery.consume([device(101)]).isEmpty && battery.consume([device(20)]).isEmpty,
               "invalid telemetry cannot masquerade as a recharge")
        _ = battery.consume([device(30)])
        suite.expect(battery.consume([device(10)]).count == 1, "a new discharge after actual recharge can warn again")
        for major in [UInt32(0x01), 0x02, 0x03] {
            suite.expect(!NotchAccessorySupport.announcesConnection(majorClass: major),
                         "a phone, tablet, computer or access point linking up on its own is not announced (\(major))")
        }
        for major in [UInt32(0x00), 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x1F] {
            suite.expect(NotchAccessorySupport.announcesConnection(majorClass: major),
                         "accessories and devices without a declared class announce their connection (\(major))")
        }
        var connections = NotchAccessoryConnectionState()
        connections.establishBaseline(["AA:01"])
        suite.expect(!connections.connected("AA:01"), "initially connected accessories do not replay connection banners")
        suite.expect(connections.connected("AA:02") && !connections.connected("AA:02"),
               "duplicate system callbacks produce one connection event")
        suite.expect(!connections.connected(""), "an unidentified connection cannot enter shared state")
        connections.disconnected("AA:01")
        suite.expect(connections.connected("AA:01"), "only a real disconnection rearms a connection banner")
    }

    private static func gateContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-activities"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchTimerSupport.isEnabled(in: defaults) && NotchCameraSupport.isEnabled(in: defaults)
               && NotchAccessorySupport.isEnabled(in: defaults), "installed timer, camera and accessory activity start enabled")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHideTimerCountdown] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHideTimerCountdown),
               "timer countdown visibility keeps its existing default and travels in settings backups")
        var session = NotchTimerSession()
        suite.expect(!NotchTimerSupport.showsActivity(session, in: defaults),
               "only an active session contributes a visible timer activity")
        session.start(mode: .pomodoro, minutes: 25, now: 0)
        suite.expect(NotchTimerSupport.showsActivity(session, in: defaults), "a running countdown shows by default")
        defaults.set(true, forKey: DefaultsKey.notchHideTimerCountdown)
        suite.expect(!NotchTimerSupport.showsActivity(session, in: defaults)
               && NotchTimerSupport.isEnabled(in: defaults),
               "hiding the countdown leaves the timer enabled for session controls and completion")
        let visible = NotchSupport.compactActivities(
            timer: NotchTimerSupport.showsActivity(session, in: defaults),
            downloads: false, agents: false, calendar: false, music: true)
        var selection = NotchActivitySelection()
        selection.select(.timer, available: [.timer, .music])
        suite.expect(visible == [.music] && selection.current(available: visible) == .music,
               "hiding a selected Pomodoro countdown lets music take the closed island")
        suite.expect(NotchNotificationSupport.isEnabled(in: defaults),
               "hiding the timer leaves notifications enabled")
        session.pause(at: 60)
        suite.expect(!NotchTimerSupport.showsActivity(session, in: defaults), "a paused countdown stays hidden")
        session.resume(at: 60)
        suite.expect(session.isRunning && session.finishIfDue(at: 25 * 60) && session.canStartNext,
               "a hidden Pomodoro still completes and offers its next phase")
        suite.expect(NotchSupport.compactActivities(
            timer: NotchTimerSupport.showsActivity(session, in: defaults),
            downloads: false, agents: false, calendar: false, music: true) == [.timer, .music],
               "a finished timer shows in the closed island while its countdown is hidden")
        session.startNext(at: 25 * 60)
        suite.expect(!NotchTimerSupport.showsActivity(session, in: defaults), "the next phase counts down hidden again")
        defaults.set(false, forKey: DefaultsKey.notchHideTimerCountdown)
        suite.expect(NotchTimerSupport.showsActivity(session, in: defaults),
               "showing the countdown again restores the existing session's activity")
        let preferenceKeys = [DefaultsKey.notchTimerEnabled, DefaultsKey.notchCameraEnabled, DefaultsKey.notchAccessoriesEnabled]
        for key in preferenceKeys { defaults.set(false, forKey: key) }
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "timer, camera and accessory activity can be turned off")
        for key in preferenceKeys { defaults.set(true, forKey: key) }
        suite.expect(NotchTimerSupport.isEnabled(in: defaults) && NotchCameraSupport.isEnabled(in: defaults)
               && NotchAccessorySupport.isEnabled(in: defaults), "turning them back on restores their activity")
        suite.expect(NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: false,
            captureControls: false, in: defaults), "the mirror can start only on its selected, expanded surface")
        suite.expect(!NotchCameraSupport.canPresent(expanded: false, selected: .camera, appPanel: false,
            captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .music, appPanel: false,
                captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: true,
                captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: false,
                captureControls: true, in: defaults), "collapse, section changes and replacement surfaces all stop embedded capture")
        defaults.set("timer,camera", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults),
               "hidden activity modules release their resources")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        for feature in [AppFeature.notchTimer, .cameraPreview, .notchAccessories, .monitorPower] {
            defaults.set(false, forKey: feature.availabilityKey)
        }
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "the feature hub gates the owner of each activity")
        for feature in [AppFeature.notchTimer, .cameraPreview, .notchAccessories, .monitorPower] {
            defaults.set(true, forKey: feature.availabilityKey)
        }
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "the notch master switch gates all activities")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: Set(preferenceKeys + [
            AppFeature.notchTimer.availabilityKey, AppFeature.notchAccessories.availabilityKey])),
               "activity preferences and feature availability round-trip through settings backup")
        suite.expect(!Defaults.registeredDefaults.keys.contains(where: { $0 == "notchTimerSession" || $0 == "notchCameraSession" }),
               "live countdown and capture sessions are not persisted as settings")
        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.notchActivities(language)).children {
                if let value = child.value as? String {
                    suite.expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !value.contains("—"),
                           "activity copy is present and human-readable for \(language.rawValue) \(child.label ?? "")")
                }
            }
        }
    }
}
