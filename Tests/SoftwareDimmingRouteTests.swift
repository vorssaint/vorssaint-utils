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
    struct Route {
        var ddcPathKey: String?
        var maximum: UInt16 = 100
        var extendedDimming = true
        var lastDDCValue: UInt16?
    }

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
        var canChooseDimming = true
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
        Context.reset()
        let colorUpdates = Context.Service()
        colorUpdates.requestWarmthUpdate()
        colorUpdates.requestWarmthUpdate()
        expect(colorUpdates.workQueue.jobs.count == 1,
               "rapid color changes share one queued application")
        colorUpdates.routes[display] = Context.Route()
        colorUpdates.workQueue.drain()
        Context.DispatchQueue.main.drain()
        expect(colorUpdates.events == ["warmth:[7]"] && colorUpdates.refreshes == 0,
               "color updates use routes discovered before execution without rescanning displays")
        colorUpdates.running = false
        colorUpdates.requestWarmthUpdate()
        expect(colorUpdates.workQueue.jobs.isEmpty,
               "disabled display and filter features do not enqueue color work")
        for nightShift in [Optional(true), Optional(false), nil] {
            expect(BrightnessSupport.effectiveWarmth(enabled: true, intensity: 0.7,
                       followsNightShift: true, nightShiftEnabled: nightShift) == (nightShift == true ? 0.7 : 0),
                   "scheduled warmth follows the effective system state, remaining neutral if unavailable")
            expect(BrightnessSupport.effectiveWarmth(enabled: true, intensity: 0.7,
                       followsNightShift: false, nightShiftEnabled: nightShift) == 0.7,
                   "manual warmth is independent of Night Shift")
            expect(BrightnessSupport.effectiveWarmth(enabled: false, intensity: 0.7,
                       followsNightShift: true, nightShiftEnabled: nightShift) == 0,
                   "disabling the filter always wins over Night Shift")
        }
        expect(BrightnessSupport.effectiveWarmth(enabled: true, intensity: .nan,
                   followsNightShift: true, nightShiftEnabled: true) == 0,
               "a corrupt scheduled intensity cannot tint the display unpredictably")
        let baseline: [Float] = [0, 0.1, 0.5, 1]
        let neutral = BrightnessSupport.warmthGains(0)
        expect(neutral.red == 1 && neutral.green == 1 && neutral.blue == 1,
               "zero warmth preserves every color channel exactly")
        let amber = BrightnessSupport.warmthGains(1)
        expect(amber.red == 1 && abs(amber.green - 0.4) < 0.0001
                && abs(amber.blue - 0.02) < 0.0001,
               "maximum warmth keeps red while strongly suppressing blue")
        for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let gains = BrightnessSupport.warmthGains(level)
            expect(gains.blue > 0 && gains.blue <= gains.green && gains.green <= gains.red,
                   "warmth keeps all channels bounded and readable")
            for brightness in [Float(0), 0.2, 1] {
                let filtered = BrightnessSupport.scaledGammaTable(baseline, factor: brightness * gains.blue)
                expect(filtered.first == 0 && abs((filtered.last ?? -1) - brightness * gains.blue) < 0.0001,
                       "warmth composes with dimming without lifting black pixels")
            }
        }
        expect(BrightnessSupport.warmthGains(-1).blue == 1
                && BrightnessSupport.warmthGains(.nan).blue == 1
                && BrightnessSupport.warmthGains(.infinity).blue == 1
                && BrightnessSupport.warmthGains(2).blue == amber.blue,
               "invalid warmth preferences stay neutral or within the supported range")
        expect(BrightnessSupport.scaledGammaTable(baseline, factor: neutral.blue) == baseline,
               "disabling warmth restores the original curve rather than filtering a filtered curve")
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

        Context.reset()
        let extended = Context.Service()
        extended.routes[display] = Context.Route(ddcPathKey: path)
        extended.lastApplied[display] = 0.1
        extended.levelKnownAt[display] = Date()
        extended.pendingLevels[display] = 0.05
        extended.setExtendedDimmingPreferred(true, for: display)
        expect(Context.UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessExtendedDimmingPaths) == [path]
                && extended.refreshes == 1
                && extended.pendingLevels[display] == nil,
               "extended dimming is saved for this monitor and drops a write in the old slider scale")
        extended.setExtendedDimmingPreferred(false, for: display)
        expect(Context.UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessExtendedDimmingPaths) == []
                && extended.lastApplied[display] == nil
                && extended.levelKnownAt[display] == nil,
               "turning extended dimming off clears its remembered slider level")
        extended.workQueue.drain()
        Context.DispatchQueue.main.drain()
        expect(extended.softwareDims.isEmpty && extended.refreshes == 2,
               "turning extended dimming off leaves an unchanged gamma curve alone")

        Context.reset()
        let dimmedExtended = Context.Service()
        dimmedExtended.routes[display] = Context.Route(ddcPathKey: path)
        dimmedExtended.dimmedDisplays.insert(display)
        dimmedExtended.setExtendedDimmingPreferred(false, for: display)
        dimmedExtended.workQueue.drain()
        Context.DispatchQueue.main.drain()
        expect(dimmedExtended.softwareDims.map(\.value) == [1]
                && dimmedExtended.refreshes == 1,
               "turning extended dimming off restores a curve the app actually dimmed")

        let restoration = Context.Service()
        restoration.gammaBaselines = [
            display: Context.Service.GammaTable(fingerprint: "display-7"),
            8: Context.Service.GammaTable(fingerprint: "display-8"),
            9: Context.Service.GammaTable(fingerprint: "another-monitor"),
        ]
        restoration.dimmedDisplays = [display, 9]
        restoration.adjustedGammaDisplays = [display, 9]
        restoration.restoreAllGamma()
        expect(restoration.events == ["restore:7"]
                && restoration.gammaBaselines.isEmpty && restoration.dimmedDisplays.isEmpty,
               "stopping restores only curves this app dimmed on the same monitor")

        let tinted = Context.Service()
        tinted.gammaBaselines = [display: Context.Service.GammaTable(fingerprint: "display-7")]
        tinted.adjustedGammaDisplays = [display]
        tinted.gammaPictureLevels[display] = 1
        tinted.restoreAllGamma()
        expect(tinted.events == ["restore:7"] && tinted.adjustedGammaDisplays.isEmpty
                && tinted.gammaPictureLevels.isEmpty && tinted.dimmedDisplays.isEmpty,
               "stopping restores a warmth-only display even when brightness was never dimmed")

        Context.reset()
        let combined = Context.Service()
        combined.routes[display] = Context.Route(ddcPathKey: path, lastDDCValue: 50)
        let monitor = "monitor" as CFString
        expect(combined.writeExtendedBrightness(0.125, to: display,
                                                route: combined.routes[display]!, service: monitor),
               "the lower slider range can dim a readable DDC monitor")
        expect(combined.events == ["ddc:0", "picture:0.5"]
                && combined.routes[display]?.lastDDCValue == 0,
               "the monitor reaches its hardware minimum before the picture dims")
        combined.events = []
        expect(combined.writeExtendedBrightness(0.0625, to: display,
                                                route: combined.routes[display]!, service: monitor)
                && combined.events == ["picture:0.25"],
               "dragging within the software range does not repeat a slow DDC write")
        combined.events = []
        expect(combined.writeExtendedBrightness(0.625, to: display,
                                                route: combined.routes[display]!, service: monitor)
                && combined.events == ["picture:1.0", "ddc:50"],
               "the unmodified picture returns before hardware brightness rises")
        combined.dimmedDisplays.insert(display)
        combined.softwareSucceeds = false
        combined.events = []
        expect(!combined.writeExtendedBrightness(1, to: display,
                                                 route: combined.routes[display]!, service: monitor)
                && combined.events == ["picture:1.0"],
               "a failed picture restore never raises the hardware brightness")

        // Which rows offer the choice at all. The rule is the same on both
        // surfaces, since they share the control.
        let row = Context.Row()
        expect(row.offered, "a monitor whose channel takes writes and answers no reads is offered the choice")
        row.display.readable = true
        expect(row.offered, "a readable DDC monitor offers optional dimming below its hardware minimum")
        row.compact = true
        expect(!row.offered, "the compact panel leaves the extra dimming choice to Settings")
        row.chosen = true
        expect(row.offered, "extra dimming stays in the compact panel once it is on, so it can be turned off")
        row.chosen = false
        row.display.readable = false
        expect(row.offered, "the compact panel keeps the write-only way out")
        row.display.readable = true
        row.compact = false
        row.display.canChooseDimming = false
        expect(!row.offered, "a display with no stable connection path cannot save a dimming choice")
        row.display.canChooseDimming = true
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
