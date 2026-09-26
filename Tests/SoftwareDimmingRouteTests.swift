// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Moving one display between the DDC and the gamma route is extracted from
/// production. Turning the choice off is the half that has a screen to put
/// back: the scaled curve is this app's and the level behind it belongs to the
/// gamma route, so both have to go before the monitor takes the slider back
/// (issue #1589).
enum SoftwareDimmingRouteContract {
    struct Route { var ddcPathKey: String? }

    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute action: @escaping () -> Void) { jobs.append(action) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue {
        static let main = Queue()
    }

    enum UserDefaults {
        static var standard = Store()
        final class Store {
            var values: [String: Any] = [:]
            func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
            func set(_ value: Any, forKey key: String) { values[key] = value }
        }
    }

    /// The display as a row sees it. A monitor behind a converter is active,
    /// external, routed over DDC and answers no reads.
    enum Method { case ddc, software }
    struct Display {
        var id: CGDirectDisplayID = 7
        var isActive = true
        var isBuiltIn = false
        var method: Method? = .ddc
        var readable = false
    }

    final class Log {
        var lines: [String] = []
        func log(_ message: String) { lines.append(message) }
    }

    static func reset() {
        UserDefaults.standard = UserDefaults.Store()
        DispatchQueue.main.jobs = []
    }
}

enum SoftwareDimmingRouteTests {
    private typealias Context = SoftwareDimmingRouteContract

    private static let path = "port-1:monitor-a"
    private static let display: CGDirectDisplayID = 7

    private static func dimmedDisplay() -> Context.Service {
        Context.reset()
        let service = Context.Service()
        service.routes[display] = Context.Route(ddcPathKey: path)
        // The display is on the gamma route with a dim applied and its level
        // remembered, which is the state the choice is turned off from.
        service.lastApplied[display] = 0.35
        service.levelKnownAt[display] = Date()
        Context.UserDefaults.standard.set([path], forKey: DefaultsKey.brightnessForcedSoftwarePaths)
        Context.UserDefaults.standard.set([path], forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
        return service
    }

    static func run(expect: (Bool, String) -> Void) {
        let off = dimmedDisplay()
        off.setSoftwareDimmingPreferred(false, for: display)
        expect(Context.UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessForcedSoftwarePaths) == []
                && off.forgottenWriteOnlyPaths == [path],
               "turning the choice off releases the display and lets the channel be probed again")
        expect(off.lastApplied[display] == nil && off.levelKnownAt[display] == nil,
               "the slider starts from the monitor rather than the level the gamma route left behind")
        expect(off.softwareDims.isEmpty && off.refreshes == 0,
               "nothing touches the screen before the work queue runs")
        off.workQueue.drain()
        expect(off.softwareDims.map(\.value) == [1],
               "the picture goes back to its own curve when the choice goes off")
        expect(off.refreshes == 0,
               "the rebuild waits for the restored curve, so the probe reads an undimmed display")
        Context.DispatchQueue.main.drain()
        expect(off.refreshes == 1, "the display is rebuilt onto the DDC route once the picture is back")

        let on = dimmedDisplay()
        on.setSoftwareDimmingPreferred(true, for: display)
        expect(Context.UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessForcedSoftwarePaths) == [path]
                && on.refreshes == 1,
               "choosing software dimming pins the display and rebuilds it straight away")
        expect(on.softwareDims.isEmpty && on.workQueue.jobs.isEmpty,
               "choosing it never restores a curve, which would undo the dim being asked for")
        expect(on.lastApplied[display] == 0.35 && on.levelKnownAt[display] != nil,
               "the level the gamma route is about to use is kept")

        // Which rows offer the choice at all. The rule is the same on both
        // surfaces, since they share the control.
        let row = Context.Row()
        expect(row.offered, "a monitor whose channel takes writes and answers no reads is offered the choice")
        row.display.readable = true
        expect(!row.offered, "a monitor whose channel answers reads is left on DDC without asking")
        row.display.readable = false
        row.display.isBuiltIn = true
        expect(!row.offered, "the built-in display never routes over DDC, so it is never asked about")
        row.display.isBuiltIn = false
        row.display.isActive = false
        expect(!row.offered, "a display that is switched off has nothing to dim")
        row.display.isActive = true
        row.display.method = .software
        expect(!row.offered, "a display already on the gamma route for its own reasons is not a choice")
        row.chosen = true
        expect(row.offered,
               "a display moved here by hand keeps the control, or there would be no way back to DDC")
        row.display.isActive = false
        expect(!row.offered, "not even a chosen display offers the control while it is switched off")

        // A display the rebuild has not routed yet has no path to record the
        // choice against, so nothing is written and no screen is touched.
        Context.reset()
        let unrouted = Context.Service()
        unrouted.setSoftwareDimmingPreferred(false, for: display)
        expect(Context.UserDefaults.standard.values.isEmpty
                && unrouted.refreshes == 0
                && unrouted.softwareDims.isEmpty
                && unrouted.workQueue.jobs.isEmpty,
               "a display with no known DDC path is left alone entirely")
    }
}
