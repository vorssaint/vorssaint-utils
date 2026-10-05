// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The companion's model: its preferences, faces, outlines and strolls, and
/// the drop that carries the Command Bar out of the island.
enum NotchMascotTests {
    static func run(_ suite: TestSuite) {
        preferenceContracts(suite)
        faceContracts(suite)
        outlineContracts(suite)
        trackContracts(suite)
        strollContracts(suite)
        homecomingContracts(suite)
        cameoContracts(suite)
        farewellContracts(suite)
        crossContracts(suite)
        arriveContracts(suite)
        lingerContracts(suite)
        previewContracts(suite)
        countdownContracts(suite)
        activityTrackContracts(suite)
        reactionContracts(suite)
        sideContracts(suite)
        commandBarContracts(suite)
        dropletContracts(suite)
        calendarContracts(suite)
    }

    private static func calendarContracts(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, _ offset: TimeInterval) -> NotchCalendarEvent {
            NotchCalendarEvent(id: id, title: id, calendar: "Personal", start: start.addingTimeInterval(offset),
                               end: start.addingTimeInterval(offset + 1800), allDay: false, location: "")
        }
        let meeting = event("meeting", 0), next = event("next", 900)
        let counting = NotchCalendarCountdown(event: meeting, ongoing: false)
        let began = { NotchMascotSupport.eventBegan(from: counting, to: $0, at: start.addingTimeInterval($1)) }
        suite.expect(began(NotchCalendarCountdown(event: meeting, ongoing: true), 0.5) && began(nil, 1)
                     && began(NotchCalendarCountdown(event: next, ongoing: false), -0.8),
                     "the companion bounces as the event it counted down to begins, whatever the island shows next")
        suite.expect(NotchMascotSupport.timerReaction(finishing: .timer) == .surprised
                     && NotchMascotSupport.timerReaction(finishing: .focus) == .celebrate
                     && NotchMascotSupport.timerReaction(finishing: .shortBreak) == .ready
                     && NotchMascotSupport.timerReaction(finishing: .longBreak) == .ready,
                     "a timer's ring startles it, a finished focus session makes it glad and a break's end gets it ready")
        suite.expect(NotchMascotSupport.powerReaction(pluggedIn: true, charged: false, low: false) == .love
                     && NotchMascotSupport.powerReaction(pluggedIn: false, charged: true, low: false) == .celebrate
                     && NotchMascotSupport.powerReaction(pluggedIn: false, charged: false, low: true) == .yawn
                     && NotchMascotSupport.powerReaction(pluggedIn: false, charged: false, low: false) == nil,
                     "the charger going in makes it glad, a full battery makes it cheer, a low one tires it, and unplugging is no news")
        suite.expect(!began(nil, -120) && !began(NotchCalendarCountdown(event: next, ongoing: false), -300)
                     && !began(nil, 600) && !began(NotchCalendarCountdown(event: meeting, ongoing: false), 1)
                     && !NotchMascotSupport.eventBegan(from: NotchCalendarCountdown(event: meeting, ongoing: true), to: nil,
                                                       at: start.addingTimeInterval(1800)),
                     "an event moved or removed before it starts, a start slept through or an event ending is no news")
    }

    private static func preferenceContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-mascot"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults.set(true, forKey: AppFeature.commandBar.availabilityKey)

        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchMascotSupport.isEnabled(in: defaults) && !NotchMascotSupport.visits(in: defaults)
                     && NotchMascotSupport.commandBarStyle(in: defaults) == nil,
                     "the companion is opt-in, and the Command Bar keeps its own window until it is on")
        defaults.set(true, forKey: DefaultsKey.notchMascotEnabled)
        suite.expect(!NotchMascotSupport.isEnabled(in: defaults) && !NotchMascotSupport.reacts(in: defaults),
                     "switched on but not installed on the Features page, it stays away")
        defaults.set(false, forKey: DefaultsKey.notchMascotEnabled)
        defaults.set(true, forKey: AppFeature.notchMascot.availabilityKey)
        suite.expect(!NotchMascotSupport.isEnabled(in: defaults),
                     "installed, it still waits for its switch")
        suite.expect(NotchMascotSupport.look(in: defaults) == .standard
                     && NotchMascotLook.standard == NotchMascotLook(style: .minimal, shape: .ball, palette: .pearl),
                     "it starts as a pearl ball with two ink eyes")
        defaults.set(true, forKey: DefaultsKey.notchMascotEnabled)
        suite.expect(NotchMascotSupport.isEnabled(in: defaults) && NotchMascotSupport.visits(in: defaults)
                     && NotchMascotSupport.reacts(in: defaults)
                     && NotchMascotSupport.commandBarStyle(in: defaults) == .droplet,
                     "turned on, it visits now and then, reacts, and the Command Bar falls from the island as a drop")
        defaults.set(false, forKey: DefaultsKey.notchMascotReactions)
        suite.expect(NotchMascotSupport.isEnabled(in: defaults) && !NotchMascotSupport.reacts(in: defaults)
                     && NotchMascotSupport.visits(in: defaults),
                     "its reactions can be turned off while it still rests and visits")
        defaults.set(true, forKey: DefaultsKey.notchMascotReactions)
        defaults.set(false, forKey: AppFeature.notchMascot.availabilityKey)
        suite.expect(!NotchMascotSupport.isEnabled(in: defaults) && !NotchMascotSupport.visits(in: defaults)
                     && !NotchMascotSupport.reacts(in: defaults) && NotchMascotSupport.commandBarStyle(in: defaults) == nil,
                     "uninstalled, it leaves the island and the Command Bar keeps its own window")
        defaults.set(true, forKey: AppFeature.notchMascot.availabilityKey)
        defaults.set(NotchCommandBarStyle.island.rawValue, forKey: DefaultsKey.notchCommandBarStyle)
        suite.expect(NotchMascotSupport.commandBarStyle(in: defaults) == .island, "the bar can open inside the island instead")
        defaults.set("puddle", forKey: DefaultsKey.notchCommandBarStyle)
        suite.expect(NotchMascotSupport.commandBarStyle(in: defaults) == .droplet, "an unknown style falls back to the drop")
        defaults.set(false, forKey: DefaultsKey.notchCommandBar)
        suite.expect(NotchMascotSupport.commandBarStyle(in: defaults) == nil, "turned off, the bar keeps its own window")
        defaults.set(true, forKey: DefaultsKey.notchCommandBar)
        defaults.set(false, forKey: AppFeature.commandBar.availabilityKey)
        suite.expect(NotchMascotSupport.commandBarStyle(in: defaults) == nil,
                     "a Command Bar taken off the Features page never comes out of the island")
        defaults.set(true, forKey: AppFeature.commandBar.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchMascotVisits)
        suite.expect(NotchMascotSupport.isEnabled(in: defaults) && !NotchMascotSupport.visits(in: defaults),
                     "visits can be turned off while it still rests")
        defaults.set(true, forKey: DefaultsKey.notchMascotVisits)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchMascotSupport.isEnabled(in: defaults) && !NotchMascotSupport.visits(in: defaults)
                     && NotchMascotSupport.commandBarStyle(in: defaults) == nil,
                     "without the island there is no companion and no bar from it")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(NotchMascotStyle.robot.rawValue, forKey: DefaultsKey.notchMascotStyle)
        defaults.set(NotchMascotShape.pill.rawValue, forKey: DefaultsKey.notchMascotShape)
        defaults.set(NotchMascotPalette.lilac.rawValue, forKey: DefaultsKey.notchMascotPalette)
        suite.expect(NotchMascotSupport.look(in: defaults) == NotchMascotLook(style: .robot, shape: .pill, palette: .lilac),
                     "style, shape and color are read as chosen")
        defaults.set("cube", forKey: DefaultsKey.notchMascotShape)
        defaults.set("neon", forKey: DefaultsKey.notchMascotPalette)
        defaults.set("dragon", forKey: DefaultsKey.notchMascotStyle)
        suite.expect(NotchMascotSupport.look(in: defaults) == .standard, "unknown values from a newer backup fall back")

        let keys = [DefaultsKey.notchMascotEnabled, DefaultsKey.notchMascotVisits, DefaultsKey.notchMascotReactions,
                    DefaultsKey.notchMascotStyle,
                    DefaultsKey.notchMascotShape, DefaultsKey.notchMascotPalette, DefaultsKey.notchCommandBar,
                    DefaultsKey.notchCommandBarStyle, DefaultsKey.notchMascotSide, DefaultsKey.notchMascotVisitFrequency]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] != nil && $0.hasPrefix("notch") }
                     && SettingsBackupSupport.exportKeys().isSuperset(of: keys),
                     "every companion preference travels in a settings backup with the island's")
        suite.expect(Set(NotchMascotShape.allCases.map(\.rawValue)).count == 4
                     && Set(NotchMascotPalette.allCases.map(\.rawValue)).count == 7
                     && Set(NotchMascotPalette.allCases.map { "\($0.light)" }).count == 7
                     && Set(NotchMascotPalette.allCases.map { "\($0.shade)" }).count == 7,
                     "four shapes and seven distinct colors")
        suite.expect(NotchMascotPalette.allCases.first == .pearl
                     && ["pearl", "mint", "peach", "lilac", "lemon", "rose"].allSatisfy { NotchMascotPalette(rawValue: $0) != nil },
                     "every color saved before keeps its name, white first")
        let normal = NotchMascotVisitFrequency.normal.delay
        suite.expect(NotchMascotSupport.nextVisitDelay(.normal, random: 0) == normal.lowerBound
                     && NotchMascotSupport.nextVisitDelay(.normal, random: 1) == normal.upperBound
                     && NotchMascotSupport.nextVisitDelay(.normal, random: 7) == normal.upperBound
                     && NotchMascotVisitFrequency.allCases.allSatisfy { $0.delay.lowerBound >= 60 },
                     "visits come minutes apart, never on a fast beat")
        suite.expect(NotchMascotVisitFrequency.rare.delay.lowerBound > normal.upperBound
                     && NotchMascotVisitFrequency.frequent.delay.upperBound < normal.lowerBound,
                     "rare visits come later than normal ones, frequent ones sooner")
        suite.expect(NotchMascotSupport.visitFrequency(in: defaults) == .normal && NotchMascotSupport.side(in: defaults) == .left,
                     "visits come at the normal pace, beside the camera's left, unless chosen otherwise")
        defaults.set(NotchMascotVisitFrequency.rare.rawValue, forKey: DefaultsKey.notchMascotVisitFrequency)
        defaults.set(NotchMascotSide.right.rawValue, forKey: DefaultsKey.notchMascotSide)
        suite.expect(NotchMascotSupport.visitFrequency(in: defaults) == .rare && NotchMascotSupport.side(in: defaults) == .right,
                     "the pace and the side are read as chosen")
        let lowPower = NotchMascotSupport.blinkInterval(lowPower: true), awake = NotchMascotSupport.blinkInterval(lowPower: false)
        suite.expect(lowPower.lowerBound >= awake.lowerBound * 2 && lowPower.upperBound >= awake.upperBound * 2,
                     "in Low Power Mode it blinks half as often")
        suite.expect(NotchMascotSupport.blinksBeforeSleep(hour: 23) < NotchMascotSupport.blinksBeforeSleep(hour: 14)
                     && NotchMascotSupport.blinksBeforeSleep(hour: 3) < NotchMascotSupport.blinksBeforeSleep(hour: 9)
                     && NotchMascotSupport.blinksBeforeSleep(hour: 6) == NotchMascotSupport.blinksBeforeSleep(hour: 21),
                     "late at night it grows sleepy sooner")
        suite.expect(NotchMascotSupport.greeting(random: 0) == .happy && NotchMascotSupport.greeting(random: 0.5) == .wink
                     && NotchMascotSupport.greeting(random: 0.99) == .love && NotchMascotSupport.greeting(random: 3) == .love,
                     "a visit says hello happy, with a wink or in love")
    }

    private static func faceContracts(_ suite: TestSuite) {
        suite.expect(NotchMascotMood.idle.expression.blinks && NotchMascotMood.searching.expression.blinks
                     && !NotchMascotMood.happy.expression.blinks && !NotchMascotMood.love.expression.blinks
                     && !NotchMascotMood.sleepy.expression.blinks && !NotchMascotMood.wink.expression.blinks,
                     "open eyes blink now and then; smiling, heart and sleepy eyes do not")
        suite.expect(NotchMascotMood.wink.expression.left != NotchMascotMood.wink.expression.right
                     && NotchMascotMood.confused.expression.tilt != 0 && NotchMascotMood.thinking.expression.gaze.y < 0,
                     "a wink closes one eye, confusion tilts the head and thinking looks up")
        var expressions: [NotchMascotExpression] = []
        for mood in NotchMascotMood.allCases where !expressions.contains(mood.expression) {
            expressions.append(mood.expression)
        }
        suite.expect(expressions.count == NotchMascotMood.allCases.count, "every face is its own")
    }

    private static func outlineContracts(_ suite: TestSuite) {
        let eyes: [NotchMascotEye] = [.open, .closed, .happy, .heart, .sleepy, .wide, .squint, .determined]
        let size = CGSize(width: 2, height: 4)
        let structure = elements(NotchMascotGeometry.eye(.open, size: size, center: .zero, right: false))
        var shared = true, bounded = true, starts = true
        for eye in eyes {
            for right in [false, true] {
                let path = NotchMascotGeometry.eye(eye, size: size, center: CGPoint(x: 10, y: 10), right: right)
                shared = shared && elements(path) == structure
                let box = path.boundingBoxOfPath
                bounded = bounded && box.minX > 10 - size.width * 1.4 && box.maxX < 10 + size.width * 1.4
                    && box.minY > 10 - size.height && box.maxY < 10 + size.height
                let points = NotchMascotGeometry.eyePoints(eye, size: size, right: right)
                starts = starts && points.count == NotchMascotGeometry.eyeCurveCount && abs(points[0].x) < 0.05
                    && points[0].y <= (points.map(\.y).min() ?? 0) + size.height * 0.35
            }
        }
        suite.expect(structure.count == NotchMascotGeometry.eyeCurveCount + 2 && shared,
                     "every eye is drawn with the same curves, so any face can turn into any other")
        suite.expect(bounded, "every eye stays around its own place on the face")
        suite.expect(starts, "every outline starts at the top of its middle and runs the same way round")
        let open = NotchMascotGeometry.eyePoints(.open, size: size, right: false)
        let mirrored = NotchMascotGeometry.eyePoints(.determined, size: size, right: true)
        let left = NotchMascotGeometry.eyePoints(.determined, size: size, right: false)
        suite.expect(abs((open.map(\.x).max() ?? 0) + (open.map(\.x).min() ?? 0)) < 0.05
                     && abs((left.map(\.x).max() ?? 0) + (mirrored.map(\.x).min() ?? 0)) < 0.05,
                     "the right eye mirrors the left")

        for shape in NotchMascotShape.allCases {
            let box = NotchMascotGeometry.body(shape, size: 20).boundingBoxOfPath
            suite.expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= 20 && box.maxY <= 20 && box.width > 8 && box.height > 8,
                         "the \(shape.rawValue) body fits its square")
            let face = NotchMascotLook(style: .minimal, shape: shape, palette: .pearl).face
            let body = NotchMascotGeometry.body(shape, size: 20)
            suite.expect(body.contains(CGPoint(x: face.leftEye.x * 20, y: face.leftEye.y * 20))
                         && body.contains(CGPoint(x: face.rightEye.x * 20, y: face.rightEye.y * 20))
                         && body.contains(CGPoint(x: face.shineCenter.x * 20, y: face.shineCenter.y * 20)),
                         "the \(shape.rawValue) face and its highlight sit on the body")
        }
        let robot = NotchMascotGeometry.robot(size: 20)
        let face = NotchMascotLook(style: .robot, shape: .ball, palette: .mint).face
        suite.expect(robot.visor.contains(CGPoint(x: face.leftEye.x * 20, y: face.leftEye.y * 20))
                     && robot.visor.contains(CGPoint(x: face.rightEye.x * 20, y: face.rightEye.y * 20))
                     && [robot.head, robot.ears, robot.antenna, robot.bulb].allSatisfy {
                         let box = $0.boundingBoxOfPath
                         return box.minX >= 0 && box.minY >= 0 && box.maxX <= 20 && box.maxY <= 20
                     },
                     "the robot's eyes light its visor, and all of it fits its square")
    }

    private static func trackContracts(_ suite: TestSuite) {
        for height: CGFloat in [24, 32, 38] {
            let track = NotchMascotSupport.track(stripWidth: 180 + 88, stripHeight: height, wing: 44, cameraWidth: 180,
                                                 floats: false, bodyHeight: height)
            suite.expect(track.rest - track.size / 2 >= 0 && track.rest + track.size / 2 <= 44 - 4
                         && track.hidden == 44...224 && abs(track.farSpot - (224 + 44 - track.rest)) < 0.01
                         && track.size <= height - 8,
                         "at \(Int(height)) points it rests whole inside the wing, beside the camera and never under it")
        }
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        suite.expect(capsule.hidden == nil && capsule.rest == 38 && capsule.size <= 16 && capsule.baseline == 12
                     && capsule.farSpot > capsule.rest && capsule.farSpot + capsule.size / 2 <= 76,
                     "in a capsule it rests in the middle, with no camera to hide behind")
    }

    private static func strollContracts(_ suite: TestSuite) {
        let notch = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32)
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        for (name, track) in [("notch", notch), ("capsule", capsule)] {
            for kind in [NotchMascotVisit.Kind.lap, .pass] {
                let path = NotchMascotMotion.path(for: kind, on: track)
                let label = "\(name) \(kind == .lap ? "lap" : "pass")"
                let counts = Set([path.keyTimes.count, path.x.count, path.lift.count, path.squash.count, path.gaze.count])
                suite.expect(counts.count == 1 && path.keyTimes.first == 0 && path.keyTimes.last == 1
                             && zip(path.keyTimes, path.keyTimes.dropFirst()).allSatisfy { $0 <= $1 },
                             "the \(label) is one even run of frames from start to end")
                suite.expect(path.duration == NotchMascotMotion.duration(of: kind) && path.duration <= 4
                             && path.greeting.lowerBound > 0 && path.greeting.upperBound < path.duration,
                             "the \(label) is short, with its hello inside it")
                suite.expect(path.lift.allSatisfy { $0 >= 0 && $0 <= track.size * 0.4 }
                             && path.squash.allSatisfy { abs($0) <= 0.15 },
                             "the \(label) hops stay low and its squashes small")
                suite.expect(path.lift.allSatisfy { track.baseline - $0 - track.size / 2 >= track.ceiling + 1 },
                             "the \(label) never hops into the island's top edge")
                if kind == .lap {
                    suite.expect(abs((path.x.first ?? 0) - track.rest) < 0.01 && abs((path.x.last ?? 0) - track.rest) < 0.01,
                                 "the \(label) leaves its resting place and comes back to it")
                    // Between two frames it never crosses the strip: a frame
                    // drawn in between would show it in the middle.
                    let crossings = zip(zip(path.x, path.x.dropFirst()), zip(path.keyTimes, path.keyTimes.dropFirst()))
                        .filter { abs($0.0.1 - $0.0.0) > track.width / 2 }
                    suite.expect(!crossings.isEmpty && crossings.allSatisfy { $0.1.0 == $0.1.1 },
                                 "the \(label) goes around off stage in no time, never seen on the way")
                } else {
                    suite.expect((path.x.first ?? 0) <= -track.size / 2 && (path.x.last ?? 0) >= track.width + track.size / 2,
                                 "the \(label) comes in at one end and leaves at the other")
                }
                // Wherever it stands still, it stands where it can be seen.
                if let hidden = track.hidden {
                    var stillInCamera = false
                    for index in 1..<path.x.count where path.x[index] == path.x[index - 1] {
                        let x = path.x[index]
                        if x > hidden.lowerBound + 1, x < hidden.upperBound - 1 { stillInCamera = true }
                    }
                    suite.expect(!stillInCamera, "the \(label) never stops behind the camera")
                }
                let hello = path.keyTimes.indices.filter {
                    let time = path.keyTimes[$0] * path.duration
                    return time >= path.greeting.lowerBound + 0.2 && time <= path.greeting.upperBound - 0.2
                }
                suite.expect(!hello.isEmpty && hello.allSatisfy { index in
                    let x = path.x[index]
                    let seen = x - track.size / 2 >= 0 && x + track.size / 2 <= track.width
                    guard let hidden = track.hidden else { return seen }
                    return seen && (x + track.size / 2 <= hidden.lowerBound || x - track.size / 2 >= hidden.upperBound)
                }, "the \(label) says hello where it can be seen")
            }
        }
    }

    private static func homecomingContracts(_ suite: TestSuite) {
        let notch = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32)
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        for (name, track) in [("notch", notch), ("capsule", capsule)] {
            let path = NotchMascotMotion.path(for: .home, on: track)
            let counts = Set([path.keyTimes.count, path.x.count, path.lift.count, path.squash.count, path.gaze.count])
            suite.expect(counts.count == 1 && path.keyTimes.first == 0 && path.keyTimes.last == 1
                         && path.duration == NotchMascotMotion.homeDuration && path.duration < 0.8,
                         "coming home in a \(name) is one short run of frames")
            suite.expect(abs((path.x.last ?? 0) - track.rest) < 0.01 && path.lift.last == 0,
                         "coming home in a \(name) ends standing where it rests")
            suite.expect(path.greeting.lowerBound == 0 && path.greeting.upperBound < path.duration,
                         "it keeps the bar's face only until it lands")
            if let hidden = track.hidden {
                suite.expect((path.x.first ?? 0) - track.size / 2 > hidden.lowerBound
                             && path.x.allSatisfy { $0 >= track.rest - 0.01 },
                             "it comes out from behind the camera, never past its place")
            } else {
                suite.expect(path.x.allSatisfy { abs($0 - track.rest) < 0.01 },
                             "in a capsule it lands where it rests, the drop having risen there")
            }
        }
    }

    private static func farewellContracts(_ suite: TestSuite) {
        let left = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                            floats: false, bodyHeight: 32)
        let right = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        suite.expect(NotchMascotVisit.Kind.cameo(.groove).takesOnlyItsWing && NotchMascotVisit.Kind.countdown(5).takesOnlyItsWing
                     && NotchMascotVisit.Kind.retreat.takesOnlyItsWing && NotchMascotVisit.Kind.linger(.perk).takesOnlyItsWing
                     && NotchMascotVisit.Kind.cameo(.celebrate).takesOnlyItsWing
                     && !NotchMascotVisit.Kind.pass.takesOnlyItsWing,
                     "reacting or watching a countdown it takes only its wing, and only a stroll the whole strip")
        suite.expect(NotchMascotVisit.Kind.farewell.endsOutOfSight && !NotchMascotVisit.Kind.farewell.watchesTimer
                     && NotchMascotMotion.duration(of: .farewell) < 1,
                     "a farewell is over in under a second and ends out of sight")
        for (name, track) in [("left wing", left), ("right wing", right), ("capsule", capsule)] {
            let path = NotchMascotMotion.path(for: .farewell, on: track)
            let counts = Set([path.keyTimes.count, path.x.count, path.lift.count, path.squash.count, path.gaze.count])
            suite.expect(counts.count == 1 && path.keyTimes.first == 0 && path.keyTimes.last == 1
                         && zip(path.keyTimes, path.keyTimes.dropFirst()).allSatisfy { $0 <= $1 }
                         && path.greeting.lowerBound == 0 && path.greeting.upperBound > 0.3,
                         "saying goodbye in a \(name), it smiles at once in one even run of frames")
            suite.expect(abs((path.x.first ?? 0) - track.rest) < 0.01 && (path.lift.first ?? 1) == 0,
                         "in a \(name) it starts where it rests, so nothing jumps as it turns to go")
            suite.expect(path.lift.allSatisfy { track.baseline - $0 - track.size / 2 >= track.ceiling + 1 },
                         "saying goodbye in a \(name), it never hops into the island's top edge")
            if let hidden = track.hidden {
                let end = path.x.last ?? 0
                suite.expect(end - track.size / 2 >= hidden.lowerBound && end + track.size / 2 <= hidden.upperBound,
                             "in a \(name) it ends behind the camera, before the wings fold")
            } else {
                suite.expect((path.x.last ?? 0) >= track.width + track.size / 2,
                             "in a capsule it walks out past the far end")
            }
        }
    }

    private static func lingerContracts(_ suite: TestSuite) {
        let right = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        suite.expect(NotchMascotVisit.Kind.linger(.ready).endsOutOfSight
                     && NotchMascotVisit.Kind.linger(.ready).reaction == .ready
                     && NotchMascotVisit.Kind.cameo(.love).reaction == .love && NotchMascotVisit.Kind.lap.reaction == nil
                     && NotchMascotMotion.duration(of: .linger(.ready))
                        == NotchMascotMotion.duration(of: .cameo(.ready)) - NotchMascotMotion.cameoArrival,
                     "lingering it skips the way out from behind the camera and keeps the rest of a cameo")
        for (name, track) in [("right wing", right), ("capsule", capsule)] {
            let path = NotchMascotMotion.path(for: .linger(.ready), on: track)
            let hold = NotchMascotMotion.cameoHold(.ready)
            let held = path.keyTimes.indices.filter { path.keyTimes[$0] * path.duration <= hold }
            suite.expect(!held.isEmpty && held.allSatisfy { abs(path.x[$0] - track.rest) < 0.01 && path.lift[$0] == 0 },
                         "lingering in a \(name), it stays where it rested for its whole reaction")
            if let hidden = track.hidden {
                let end = path.x.last ?? 0
                suite.expect(end - track.size / 2 >= hidden.lowerBound && end + track.size / 2 <= hidden.upperBound,
                             "lingering in a \(name), it ends behind the camera")
            } else {
                suite.expect((path.x.last ?? 0) >= track.width + track.size / 2, "lingering in a capsule, it leaves at the far end")
            }
        }
        // What a reaction covered comes back as it sets off home beside a
        // camera, which hides it before it is halfway there, and a quarter of
        // the way out of a capsule, which it walks out of past the end.
        for kind in [NotchMascotVisit.Kind.cameo(.love), .linger(.perk), .cameo(.groove), .linger(.groove)] {
            let duration = NotchMascotMotion.duration(of: kind)
            let camera = NotchMascotMotion.handBack(of: kind, floats: false) ?? 0
            let capsule = NotchMascotMotion.handBack(of: kind, floats: true) ?? 0
            suite.expect(abs(camera - (duration - NotchMascotMotion.cameoExit)) < 1e-9
                         && abs(capsule - (duration - NotchMascotMotion.cameoExit * 3 / 4)) < 1e-9,
                         "\(kind) hands back what it covered as it sets off home beside a camera, soon after in a capsule")
            let path = NotchMascotMotion.path(for: kind, on: right)
            let before = path.keyTimes.indices.filter { path.keyTimes[$0] * path.duration <= camera - 0.01 }
            suite.expect(!before.isEmpty && abs(path.x[before.last!] - right.rest) < 0.01,
                         "\(kind) still stands where it reacted when the strip starts back")
        }
        suite.expect(NotchMascotMotion.handBack(of: .lap, floats: false) == nil
                     && NotchMascotMotion.handBack(of: .countdown(5), floats: false) == nil,
                     "a visit that comes out for no reaction hands nothing back on its own")
    }

    private static func arriveContracts(_ suite: TestSuite) {
        let left = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                            floats: false, bodyHeight: 32)
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        suite.expect(NotchMascotMotion.path(for: .arrive, on: left) == NotchMascotMotion.path(for: .home, on: left)
                     && !NotchMascotVisit.Kind.arrive.endsOutOfSight,
                     "switched on beside a camera, it comes out from behind it as it does back from the bar")
        let path = NotchMascotMotion.path(for: .arrive, on: capsule)
        suite.expect((path.x.first ?? 0) <= -capsule.size / 2 && abs((path.x.last ?? 0) - capsule.rest) < 0.01
                     && path.greeting.lowerBound == 0,
                     "switched on in a capsule, it hops in at the near end instead of appearing in its middle")
        suite.expect(path.lift.allSatisfy { capsule.baseline - $0 - capsule.size / 2 >= capsule.ceiling + 1 },
                     "hopping into a capsule, it never touches the capsule's top")
    }

    private static func crossContracts(_ suite: TestSuite) {
        let left = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                            floats: false, bodyHeight: 32)
        let right = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        suite.expect(!NotchMascotVisit.Kind.cross.endsOutOfSight && NotchMascotMotion.duration(of: .cross) < 1.6,
                     "crossing to the camera's other side ends where it rests, in well under two seconds")
        for (name, track, from) in [("to the left", left, right.rest), ("to the right", right, left.rest)] {
            let path = NotchMascotMotion.path(for: .cross, on: track)
            let counts = Set([path.keyTimes.count, path.x.count, path.lift.count, path.squash.count, path.gaze.count])
            suite.expect(counts.count == 1 && path.keyTimes.first == 0 && path.keyTimes.last == 1
                         && zip(path.keyTimes, path.keyTimes.dropFirst()).allSatisfy { $0 <= $1 },
                         "crossing \(name), it is one even run of frames")
            suite.expect(abs((path.x.first ?? 0) - from) < 0.01 && abs((path.x.last ?? 0) - track.rest) < 0.01,
                         "crossing \(name), it leaves from where it rested and lands where it now rests, with no jump")
            if let hidden = track.hidden {
                let behind = path.x.contains { $0 - track.size / 2 >= hidden.lowerBound && $0 + track.size / 2 <= hidden.upperBound }
                suite.expect(behind, "crossing \(name), it passes behind the camera")
            }
            suite.expect(path.lift.allSatisfy { track.baseline - $0 - track.size / 2 >= track.ceiling + 1 },
                         "crossing \(name), it never hops into the island's top edge")
        }
    }

    private static func previewContracts(_ suite: TestSuite) {
        let track = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        let big = track.scaled(by: 1.5)
        suite.expect(big.width == track.width * 1.5 && big.size == track.size * 1.5 && big.rest == track.rest * 1.5
                     && big.baseline == track.baseline * 1.5 && big.mirrored == track.mirrored
                     && big.hidden.map { $0.lowerBound == (track.hidden?.lowerBound ?? 0) * 1.5 } == true
                     && abs(big.hop(0.22) - track.hop(0.22) * 1.5) < 0.001
                     && abs(big.hop(0.9) - track.hop(0.9) * 1.5) < 0.001,
                     "the Settings preview's island is the real one scaled, hops and all")
        let lap = NotchMascotMotion.path(for: .lap, on: track), bigLap = NotchMascotMotion.path(for: .lap, on: big)
        suite.expect(zip(lap.x, bigLap.x).allSatisfy { abs($0 * 1.5 - $1) < 0.001 }
                     && zip(lap.lift, bigLap.lift).allSatisfy { abs($0 * 1.5 - $1) < 0.001 }
                     && lap.keyTimes == bigLap.keyTimes,
                     "a visit in the preview walks the same way as in the island, only bigger")
        let beats = NotchMascotMoment.allCases.dropFirst().map { [$0.reaction, $0.followUp].compactMap { $0?.rawValue } }
        suite.expect(NotchMascotMoment.allCases.first == .visit && NotchMascotMoment.visit.reaction == nil
                     && NotchMascotMoment.allCases.dropFirst().allSatisfy { $0.reaction != nil }
                     && Set(beats).count == beats.count,
                     "the preview acts out a visit and moments that each play something of their own")
        suite.expect(NotchMascotMoment.agents.reaction == .ready && NotchMascotMoment.agents.followUp == .celebrate
                     && NotchMascotMoment.allCases.filter { $0.followUp != nil } == [.agents],
                     "an AI agent's moment gets to work, then celebrates, and only it plays two beats")
        suite.expect(Set(NotchMascotMoment.allCases.compactMap(\.reaction)) == Set(NotchMascotReaction.allCases)
                     && NotchMascotMoment.eventStarts.reaction == .bounce && NotchMascotMoment.lowBattery.reaction == .yawn,
                     "every reaction has a moment to try, an event beginning bounces and a low battery yawns")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchMascot(language)
            let names = NotchMascotMoment.allCases.map { text.moment($0, language: language) }
            suite.expect(names.allSatisfy { !$0.isEmpty } && Set(names).count == names.count
                         && !text.searchKeywords.contains(where: \.isEmpty)
                         && NotchMascotPalette.allCases.allSatisfy { !text.palette($0).isEmpty },
                         "\(language.rawValue) names every moment once, every color, and words for search")
        }
    }

    private static func cameoContracts(_ suite: TestSuite) {
        let left = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                            floats: false, bodyHeight: 32)
        let right = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20)
        suite.expect(NotchMascotVisit.Kind.pass.endsOutOfSight && NotchMascotVisit.Kind.cameo(.love).endsOutOfSight
                     && !NotchMascotVisit.Kind.lap.endsOutOfSight && !NotchMascotVisit.Kind.home.endsOutOfSight,
                     "only a pass and a cameo end out of sight, so only they cross an activity's strip")
        for reaction in NotchMascotReaction.allCases {
            let kind = NotchMascotVisit.Kind.cameo(reaction)
            suite.expect(NotchMascotMotion.cameoHold(reaction) > reaction.length
                         && NotchMascotMotion.duration(of: kind) <= 3,
                         "coming out for \(reaction.rawValue), it stays for all of it and is soon gone")
            for (name, track) in [("left wing", left), ("right wing", right), ("capsule", capsule)] {
                let path = NotchMascotMotion.path(for: kind, on: track)
                let counts = Set([path.keyTimes.count, path.x.count, path.lift.count, path.squash.count, path.gaze.count])
                suite.expect(counts.count == 1 && path.keyTimes.first == 0 && path.keyTimes.last == 1
                             && zip(path.keyTimes, path.keyTimes.dropFirst()).allSatisfy { $0 <= $1 }
                             && path.duration == NotchMascotMotion.duration(of: kind)
                             && path.greeting.upperBound == path.greeting.lowerBound,
                             "out for \(reaction.rawValue) in a \(name), it is one even run of frames with no hello of its own")
                let landed = path.keyTimes.indices.filter {
                    let time = path.keyTimes[$0] * path.duration
                    return time >= NotchMascotMotion.cameoArrival
                        && time <= NotchMascotMotion.cameoArrival + reaction.length
                }
                suite.expect(!landed.isEmpty && landed.allSatisfy { abs(path.x[$0] - track.rest) < 0.01 && path.lift[$0] == 0 },
                             "in a \(name) it plays its \(reaction.rawValue) standing where it would rest")
                suite.expect(path.lift.allSatisfy { track.baseline - $0 - track.size / 2 >= track.ceiling + 1 },
                             "out for \(reaction.rawValue) in a \(name), it never hops into the island's top edge")
                if let hidden = track.hidden {
                    func behind(_ x: CGFloat) -> Bool {
                        x - track.size / 2 >= hidden.lowerBound && x + track.size / 2 <= hidden.upperBound
                    }
                    let start = path.x.first ?? 0
                    suite.expect(behind(start) && behind(path.x.last ?? 0)
                                 && path.x.allSatisfy { $0 >= min(start, track.rest) - 0.01 && $0 <= max(start, track.rest) + 0.01 },
                                 "in a \(name) it comes from behind the camera, goes no further than its place and goes back")
                } else {
                    suite.expect((path.x.first ?? 0) <= -track.size / 2 && (path.x.last ?? 0) >= track.width + track.size / 2,
                                 "in a capsule it comes in at one end for \(reaction.rawValue) and leaves at the other")
                }
            }
        }
    }

    private static func countdownContracts(_ suite: TestSuite) {
        let left = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                            floats: false, bodyHeight: 32)
        let right = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        guard let hidden = left.hidden else { return suite.expect(false, "a notch track has a camera") }
        let behind = { (x: CGFloat) in x - left.size / 2 >= hidden.lowerBound && x + left.size / 2 <= hidden.upperBound }
        suite.expect(NotchMascotVisit.Kind.countdown(5).endsOutOfSight && NotchMascotVisit.Kind.retreat.endsOutOfSight
                     && NotchMascotVisit.Kind.countdown(5).watchesTimer && NotchMascotVisit.Kind.retreat.watchesTimer
                     && !NotchMascotVisit.Kind.cameo(.perk).watchesTimer,
                     "watching a countdown, and going back from it, end out of sight over the timer's mark alone")
        for total in [5.0, 4.6] {
            let kind = NotchMascotVisit.Kind.countdown(total)
            let path = NotchMascotMotion.path(for: kind, on: left)
            let duration = NotchMascotMotion.duration(of: kind)
            let time = { (index: Int) in path.keyTimes[index] * duration }
            suite.expect(path.duration == duration && duration == total + NotchMascotMotion.countdownLinger
                         + NotchMascotMotion.cameoExit
                         && behind(path.x.first ?? 0) && behind(path.x.last ?? 0),
                         "a countdown of \(total) seconds is watched from behind the camera and back, past its end")
            suite.expect(path.x.allSatisfy { $0 >= left.rest - 0.01 && $0 <= (path.x.first ?? 0) + 0.01 },
                         "it watches from the camera's left, over the timer's mark, and goes no further")
            let watching = path.keyTimes.indices.filter {
                time($0) >= NotchMascotMotion.cameoArrival && time($0) <= total
            }
            suite.expect(!watching.isEmpty && watching.allSatisfy { abs(path.x[$0] - left.rest) < 0.01 && path.gaze[$0] > 0.05 },
                         "it stands where it rests, its eyes on the reading, until the countdown runs out")
            let ticks = stride(from: total.rounded(.up) - 1, through: 1, by: -1).map { total - $0 }
                .filter { $0 > NotchMascotMotion.cameoArrival + 0.25 }
            let hopsAtTicks = ticks.allSatisfy { tick in
                path.keyTimes.indices.contains { abs(time($0) - tick) < 0.04 && path.lift[$0] > 0.5 }
            }
            let stillBetween = ticks.dropLast().allSatisfy { tick in
                path.keyTimes.indices.contains { abs(time($0) - (tick + 0.5)) < 0.04 && path.lift[$0] == 0 }
            }
            suite.expect(!ticks.isEmpty && hopsAtTicks && stillBetween,
                         "with \(total) seconds left it hops as each second goes and keeps still between them")
        }
        let mirrored = NotchMascotMotion.path(for: .countdown(5), on: right)
        suite.expect(mirrored.x == NotchMascotMotion.path(for: .countdown(5), on: left).x,
                     "resting on the right, it still watches from the left, where the timer's mark is")
        let retreat = NotchMascotMotion.path(for: .retreat, on: right)
        suite.expect(abs((retreat.x.first ?? 0) - left.rest) < 0.01 && behind(retreat.x.last ?? 0)
                     && retreat.duration == NotchMascotMotion.duration(of: .retreat),
                     "a paused countdown sends it from where it watched back behind the camera")
    }

    private static func activityTrackContracts(_ suite: TestSuite) {
        let roomy = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                  cameraWidth: 185, layout: .spacious, compactSideRoom: 300)
        let agents = roomy.compactAgentGeometry(wing: 57.2)
        let wing = agents.compactActivityWingWidth
        let left = NotchMascotSupport.track(overActivity: agents, size: agents.compactActivitySize)
        let right = NotchMascotSupport.track(overActivity: agents, size: agents.compactActivitySize, side: .right)
        suite.expect(left.map {
            $0.width == agents.compactActivitySize.width && $0.hidden == wing...(wing + 185)
                && $0.rest - $0.size / 2 >= 4 && $0.rest + $0.size / 2 <= wing - 4
        } == true, "over an activity's strip it comes out whole in the wing on its side of the camera")
        suite.expect(right.map { $0.mirrored && abs($0.rest - ($0.width - (left?.rest ?? 0))) < 0.01 } == true,
                     "on the right it comes out in the right wing")
        var crowded = roomy
        crowded.compactSideRoom = 30
        let cutout = crowded.compactAgentGeometry(wing: 57)
        suite.expect(NotchMascotSupport.track(overActivity: cutout, size: cutout.compactActivitySize) == nil,
                     "a strip that keeps to the cutout has no wing for it, so it stays behind the camera")
        let capsule = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
                                    cameraWidth: 0, silhouette: .capsule)
        let through = NotchMascotSupport.track(overActivity: capsule,
                                               size: CGSize(width: 140, height: capsule.stripHeight))
        suite.expect(capsule.floats && through?.hidden == nil && through?.rest == 70 && through?.mirrored == false,
                     "over a capsule's activity it comes out in the middle")
    }

    private static func reactionContracts(_ suite: TestSuite) {
        var gate = NotchMascotReactionGate()
        suite.expect(gate.admits(.celebrate, at: 100), "the first reaction plays")
        suite.expect(!gate.admits(.love, at: 100 + NotchMascotReactionGate.spacing / 2),
                     "a second one right after waits its turn and is let go")
        suite.expect(gate.admits(.love, at: 100 + NotchMascotReactionGate.spacing + 0.1),
                     "a different one plays once a moment has passed")
        let lovedAt = 100 + NotchMascotReactionGate.spacing + 0.1
        suite.expect(!gate.admits(.love, at: lovedAt + NotchMascotReactionGate.spacing + 1),
                     "the same one never plays twice in a row")
        suite.expect(gate.admits(.love, at: lovedAt + NotchMascotReactionGate.repeatInterval + 0.1),
                     "the same one can come back after a while")
        suite.expect(NotchMascotReactionGate.patience <= 10 && NotchMascotReactionGate.spacing >= 1,
                     "a reaction it cannot show soon is dropped, never saved for later")
        suite.expect(NotchMascotMood.alert.expression.left == .wide && NotchMascotMood.alert.expression.blinks
                     && NotchMascotMood.alert.expression.gaze == .zero,
                     "wide awake keeps its eyes open and blinking, looking ahead")
    }

    private static func sideContracts(_ suite: TestSuite) {
        let left = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                            floats: false, bodyHeight: 32)
        let right = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32, side: .right)
        suite.expect(right.mirrored && abs(right.rest - (268 - left.rest)) < 0.01 && right.hidden == left.hidden
                     && right.rest - right.size / 2 >= 224 + 4 && right.rest + right.size / 2 <= 268,
                     "on the right it rests whole inside the right wing, as far from the camera as on the left")
        let capsule = NotchMascotSupport.track(stripWidth: 76, stripHeight: 24, wing: 0, cameraWidth: 0,
                                               floats: true, bodyHeight: 20, side: .right)
        suite.expect(!capsule.mirrored && capsule.rest == 38, "a capsule keeps it in the middle on either side")
        for kind in [NotchMascotVisit.Kind.lap, .pass, .home, .cameo(.love)] {
            let plain = NotchMascotMotion.path(for: kind, on: left)
            let mirrored = NotchMascotMotion.path(for: kind, on: right)
            suite.expect(mirrored.keyTimes == plain.keyTimes && mirrored.lift == plain.lift
                         && zip(mirrored.x, plain.x).allSatisfy { abs($0 + $1 - 268) < 0.01 }
                         && zip(mirrored.gaze, plain.gaze).allSatisfy { abs($0 + $1) < 0.0001 },
                         "on the right every stroll is the left one in a mirror")
        }
        let lap = NotchMascotMotion.path(for: .lap, on: right)
        suite.expect(abs((lap.x.first ?? 0) - right.rest) < 0.01 && abs((lap.x.last ?? 0) - right.rest) < 0.01,
                     "on the right a lap leaves its place and comes back to it")
    }

    private static func commandBarContracts(_ suite: TestSuite) {
        suite.expect(NotchMascotSupport.commandBarMood(query: " ", hasResults: false, searching: true) == .idle,
                     "an empty field leaves the face at rest")
        suite.expect(NotchMascotSupport.commandBarMood(query: "fire", hasResults: false, searching: true) == .thinking,
                     "it thinks while answers load")
        suite.expect(NotchMascotSupport.commandBarMood(query: "fire", hasResults: true, searching: false) == .idle
                     && NotchMascotSupport.commandBarMood(query: "qzx", hasResults: false, searching: false) == .confused,
                     "it looks at the results, and looks lost when nothing matches")
        suite.expect(NotchMascotSupport.celebrates(from: .thinking, to: .idle, query: "fire", hasResults: true)
                     && NotchMascotSupport.celebrates(from: .confused, to: .idle, query: "fire", hasResults: true),
                     "it celebrates results that arrive after waiting, or after nothing matched")
        suite.expect(!NotchMascotSupport.celebrates(from: .idle, to: .idle, query: "f", hasResults: true)
                     && !NotchMascotSupport.celebrates(from: .confused, to: .idle, query: " ", hasResults: false)
                     && !NotchMascotSupport.celebrates(from: .thinking, to: .confused, query: "fire", hasResults: false),
                     "the first letters finding something is no party, nor is clearing the field or finding nothing")
        suite.expect(NotchMascotSupport.readingGaze(for: "") == nil,
                     "an empty field leaves the eyes ahead")
        let short = NotchMascotSupport.readingGaze(for: "f"), long = NotchMascotSupport.readingGaze(for: String(repeating: "f", count: 60))
        suite.expect((short?.x ?? 0) >= 0.06 && (long?.x ?? 0) > (short?.x ?? 0) && (long?.x ?? 1) <= 0.12,
                     "its eyes go along the text beside it, further as it grows, and stay on its face")
        let ahead = NotchMascotSupport.pointerGaze(from: CGPoint(x: 26, y: 16), to: CGPoint(x: 26, y: 16), size: 20)
        let right = NotchMascotSupport.pointerGaze(from: CGPoint(x: 26, y: 16), to: CGPoint(x: 400, y: 16), size: 20)
        let left = NotchMascotSupport.pointerGaze(from: CGPoint(x: 26, y: 16), to: CGPoint(x: 0, y: 30), size: 20)
        suite.expect(ahead == .zero && right.x > 0 && abs(right.x) <= 0.08 && left.x < 0 && left.y > 0 && abs(left.y) <= 0.05,
                     "its eyes turn toward the pointer, within its face")
    }

    private static func dropletContracts(_ suite: TestSuite) {
        let edge = CommandBarDropletMotion.rootDepth
        let field = CGRect(x: 28, y: edge + CommandBarDropletMotion.landingGap, width: 560, height: 50)
        let icon = CGPoint(x: field.minX + 27, y: field.midY)
        let centerX: CGFloat = 308
        let drop = CommandBarDropletMotion.drop(edge: edge, centerX: centerX, field: field, icon: icon)
        let structure = elements(CommandBarDropletMotion.neckPath(drop.frames[0], edge: edge, centerX: centerX))
        suite.expect(drop.frames.count == drop.keyTimes.count && drop.keyTimes.first == 0 && drop.keyTimes.last == 1
                     && zip(drop.keyTimes, drop.keyTimes.dropFirst()).allSatisfy { $0 < $1 }
                     && drop.frames.allSatisfy { elements(CommandBarDropletMotion.neckPath($0, edge: edge, centerX: centerX)) == structure },
                     "the drop is one run of frames whose neck keeps its curves, so each turns into the next")
        let first = drop.frames[0], last = drop.frames[drop.frames.count - 1]
        suite.expect(first.bead.midY < edge + 2 && first.bead.midX == centerX && first.mascotScale < 1,
                     "the drop starts in the island's edge, with the companion small inside")
        suite.expect(last.bead == field && last.mascot == icon && last.mascotScale == 1 && last.neckRoot == 0
                     && last.neckEnd <= edge,
                     "it ends as the bar's field, with the companion in the icon's place and no neck left")
        suite.expect(drop.duration > 0.4 && drop.duration < 0.9 && drop.landing > 0.15 && drop.landing < drop.reveal
                     && drop.reveal <= drop.duration && drop.reveal < 0.7,
                     "it falls and opens quickly, landing first, and the bar takes over before the swing ends")
        let revealed = drop.frames[min(drop.frames.count - 1,
                                       Int((drop.reveal / drop.duration * Double(drop.frames.count - 1)).rounded(.up)))]
        suite.expect(abs(revealed.bead.width - field.width) <= 2.5 && abs(revealed.bead.height - field.height) <= 1.5,
                     "when the bar takes over, the drop already has its size within a couple of points")
        suite.expect(drop.frames.allSatisfy { $0.bead.maxY <= field.maxY + 12 && $0.bead.minX >= field.minX - 12
                                               && $0.bead.maxX <= field.maxX + 12 },
                     "its spring opens it around the field, never far past it")
        let pinched = drop.frames.firstIndex { $0.neckEnd < $0.bead.minY - 0.5 } ?? drop.frames.count
        suite.expect(pinched < drop.frames.count
                     && drop.frames[pinched...].allSatisfy { $0.neckEnd < $0.bead.minY - 0.5 }
                     && zip(drop.frames[pinched...], drop.frames[pinched...].dropFirst()).allSatisfy { $0.neckEnd >= $1.neckEnd },
                     "the neck lets go once and draws back into the island")
        suite.expect(drop.frames[pinched...].allSatisfy { $0.neckEnd - edge < 1 || $0.neckTip > 0.2 },
                     "what is left of the neck ends round, never in a point")

        let bar = CGRect(x: field.minX, y: field.minY, width: field.width, height: 380)
        let back = CommandBarDropletMotion.retract(edge: edge, centerX: centerX, bar: bar, field: field, icon: icon)
        let start = back.frames[0], end = back.frames[back.frames.count - 1]
        suite.expect(back.frames.count == back.keyTimes.count && start.bead == bar && start.mascot == icon
                     && start.mascotScale == 1 && back.duration < 0.8,
                     "the way back starts as the whole bar, its companion in the icon's place")
        suite.expect(end.bead.midY < edge && end.mascotScale == CommandBarDropletMotion.ridingScale
                     && back.frames.allSatisfy { elements(CommandBarDropletMotion.neckPath($0, edge: edge, centerX: centerX)) == structure },
                     "and ends risen into the island, the companion small inside the drop")
        let side = CommandBarDropletMotion.beadSide
        suite.expect(back.frames.allSatisfy { frame in
            let gap = frame.bead.minY - edge
            let length = frame.neckEnd - edge
            // Apart, the island only bulges toward the drop. Joined, the
            // neck is wide where it meets it.
            return length <= side * 0.3 + 0.5 || gap <= side * 0.3 + 2 || frame.neckTip >= 3
        }, "rising, no thin thread ever stretches from the island to a drop still far off")
    }

    private static func elements(_ path: CGPath) -> [Int32] {
        var kinds: [Int32] = []
        path.applyWithBlock { kinds.append($0.pointee.type.rawValue) }
        return kinds
    }
}
