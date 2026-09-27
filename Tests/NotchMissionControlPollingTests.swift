// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production timer and refresh methods with a clock and overview
/// double. It neither opens windows nor queries the window server.
enum NotchMissionControlPollingTests {
    enum ProcessInfo {
        static var processInfo = Clock()
        struct Clock { var systemUptime: TimeInterval = 100 }
    }
    enum NotchFrameProbe {
        static var visible = false
        static var reads = 0
        static func overviewIsVisible(on screen: CGRect) -> Bool { reads += 1; return visible }
    }
    class State {
        final class Panel { var isVisible = true }
        let panel = Panel()
        var missionControlTimer: Timer?
        var concealedForMissionControl = false
        var overviewWasVisible = false
        var lastMissionControlCheck: TimeInterval = -.infinity
        var lastMissionControlProbe: TimeInterval = -.infinity
        var currentGeometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                            safeAreaTop: 32, cameraWidth: 210)
        var frameReads = 0
        func sampleMissionControl() { frameReads += 1 }
        deinit { missionControlTimer?.invalidate() }
    }

    static func run(_ suite: TestSuite) {
        ProcessInfo.processInfo.systemUptime = 100
        NotchFrameProbe.visible = false
        NotchFrameProbe.reads = 0
        let host = Host()
        defer { host.missionControlTimer?.invalidate() }
        host.syncMissionControlMonitoring()
        suite.expect(host.missionControlTimer?.timeInterval == 0.25 && host.frameReads == 0,
                     "resting islands use four window-list checks per second and no frame probe")
        let idleTimer = host.missionControlTimer!
        host.syncMissionControlMonitoring()
        suite.expect(host.missionControlTimer === idleTimer, "presentation updates reuse the idle timer")
        let before = NotchFrameProbe.reads
        ProcessInfo.processInfo.systemUptime += 0.1
        host.refreshMissionControlState()
        suite.expect(NotchFrameProbe.reads == before, "incidental idle checks respect the reduced cadence")
        NotchFrameProbe.visible = true
        host.refreshMissionControlState(now: true)
        suite.expect(host.missionControlTimer?.timeInterval == 0.08 && !idleTimer.isValid && host.frameReads == 1,
                     "an immediate reveal check detects overview and replaces the idle timer with the fast timer")
        let activeTimer = host.missionControlTimer!
        ProcessInfo.processInfo.systemUptime += 0.1
        host.refreshMissionControlState()
        suite.expect(host.missionControlTimer === activeTimer && host.frameReads == 1,
                     "an open overview keeps fast detection but throttles expensive frame probes")
        host.concealedForMissionControl = true
        host.panel.isVisible = false
        NotchFrameProbe.visible = false
        ProcessInfo.processInfo.systemUptime += 0.1
        host.refreshMissionControlState()
        suite.expect(host.missionControlTimer === activeTimer && host.frameReads == 2,
                     "a concealed island retains fast restoration after the overview disappears")
        host.concealedForMissionControl = false
        host.panel.isVisible = true
        host.syncMissionControlMonitoring()
        suite.expect(host.missionControlTimer?.timeInterval == 0.25 && !activeTimer.isValid,
                     "a restored island returns to the idle cadence")
        let restoredTimer = host.missionControlTimer!
        host.panel.isVisible = false
        host.syncMissionControlMonitoring()
        suite.expect(host.missionControlTimer == nil && !restoredTimer.isValid,
                     "an ordinary hidden island stops polling completely")
    }
}
