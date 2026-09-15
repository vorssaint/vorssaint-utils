// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The notification and permission lifecycle bodies come from production;
/// clock, scheduling, permission and menu reads are controlled boundaries.
enum NotchScreenRefreshContract {
    struct Deadline {
        let seconds: Double
        static func now() -> Self { Self(seconds: DispatchQueue.main.now) }
        static func + (left: Self, right: Double) -> Self { Self(seconds: left.seconds + right) }
    }
    final class Scheduler {
        var now: Double = 0
        var jobs: [(Deadline, DispatchWorkItem)] = []
        var pending: Int { jobs.filter { !$0.1.isCancelled }.count }
        func asyncAfter(deadline: Deadline, execute work: DispatchWorkItem) { jobs.append((deadline, work)) }
        func advance(_ seconds: Double) {
            now += seconds
            while let index = jobs.firstIndex(where: { $0.0.seconds <= now }) {
                let work = jobs.remove(at: index).1
                if !work.isCancelled { work.perform() }
            }
        }
    }
    enum DispatchQueue { static var main = Scheduler() }
    final class Timer {
        var tolerance: Double = 0
        var invalidated = false
        init(timeInterval: Double, repeats: Bool, block: @escaping (Timer) -> Void) {}
        func invalidate() { invalidated = true }
    }
    enum RunLoop {
        static let main = Loop()
        final class Loop {
            enum Mode { case common }
            func add(_ timer: Timer, forMode: Mode) {}
        }
    }
    class State {
        var running = true
        var suspended = false
        var expanded = false
        var captureControls: Bool?
        var idleContent = NotchIdleContent.music
        var compactActivity: Bool?
        var accessibilityGranted = true
        var menuSpaceTimer: Timer?
        var menuSpaceGeneration = 0
        var screenRefreshWork: DispatchWorkItem?
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 210, compactSideRoom: 64)
        var preferenceSyncs = 0
        var reads = 0
        var presentations = 0
        func syncWithPreferences() { preferenceSyncs += 1 }
        func readMenuSpace() { reads += 1 }
        func refreshPresentation(animated: Bool) { presentations += 1 }
    }

    static func run(expect: (Bool, String) -> Void) {
        DispatchQueue.main = Scheduler()
        let service = Service()
        let initialSize = service.geometry.compactMusicGeometry.compactActivitySize
        var pendingPeak = 0
        var geometryChanged = false
        for _ in 0..<120 {
            service.screenParametersDidChange()
            pendingPeak = max(pendingPeak, DispatchQueue.main.pending)
            DispatchQueue.main.advance(1.0 / 60)
            geometryChanged = geometryChanged || service.geometry.compactMusicGeometry.compactActivitySize != initialSize
        }
        expect(service.preferenceSyncs == 0 && pendingPeak == 1,
               "a two-second screen-parameter burst retains one pending refresh instead of resynchronizing each event")
        expect(!geometryChanged && !service.geometry.compactMusicGeometry.compactActivityUsesFooter,
               "brightness-only notifications preserve measured music wings and never move music below the camera")
        DispatchQueue.main.advance(0.11)
        expect(service.preferenceSyncs == 1 && service.reads == 1 && service.screenRefreshWork == nil,
               "the settled screen configuration triggers one synchronization and menu measurement")
        expect(service.geometry.compactSideRoom == 64,
               "refreshing menu space retains the last valid measurement until its replacement arrives")
        service.screenParametersDidChange()
        DispatchQueue.main.advance(0.11)
        expect(service.preferenceSyncs == 2, "a later independent screen change is still processed")

        service.screenParametersDidChange()
        service.suspended = true
        DispatchQueue.main.advance(0.11)
        expect(service.preferenceSyncs == 2 && service.screenRefreshWork == nil,
               "a queued display update cannot resynchronize the island after suspension")
        service.suspended = false
        service.screenParametersDidChange()
        service.running = false
        DispatchQueue.main.advance(0.11)
        service.screenParametersDidChange()
        expect(service.preferenceSyncs == 2 && DispatchQueue.main.pending == 0,
               "stopping the island makes queued and later screen notifications inert")

        let virtual = Service()
        virtual.geometry.compactSideRoom = nil
        virtual.accessibilityGranted = false
        virtual.syncMenuSpaceMonitoring()
        expect(virtual.menuSpaceTimer == nil && virtual.reads == 0,
               "missing Accessibility does not leave a timer polling unavailable menu geometry")
        virtual.accessibilityGranted = true
        virtual.syncMenuSpaceMonitoring()
        let timer = virtual.menuSpaceTimer
        expect(timer != nil && virtual.reads == 1,
               "granting Accessibility starts the existing menu reader without restarting the app")
        virtual.geometry.compactSideRoom = 64
        virtual.accessibilityGranted = false
        virtual.syncMenuSpaceMonitoring()
        expect(virtual.menuSpaceTimer == nil && timer?.invalidated == true
               && virtual.geometry.compactSideRoom == nil && virtual.presentations == 1,
               "revoking Accessibility stops polling and withdraws stale menu-space geometry")
        virtual.accessibilityGranted = true
        virtual.running = false
        virtual.syncMenuSpaceMonitoring()
        expect(virtual.menuSpaceTimer == nil && virtual.reads == 1,
               "permission alone cannot start menu polling for a disabled island")

        let simulated = Service()
        simulated.geometry = NotchGeometry(screen: simulated.geometry.screen, safeAreaTop: 0, cameraWidth: 0)
        simulated.accessibilityGranted = false
        simulated.syncMenuSpaceMonitoring()
        expect(simulated.menuSpaceTimer == nil && simulated.reads == 0,
               "a simulated camera does not poll menus without Accessibility")
        simulated.accessibilityGranted = true
        for _ in 0..<100 { simulated.syncMenuSpaceMonitoring() }
        let simulatedTimer = simulated.menuSpaceTimer
        expect(simulatedTimer != nil && simulated.reads == 1,
               "available menu access starts one reader for a simulated camera's compact indicators")
        simulated.geometry.compactSideRoom = 64
        simulated.accessibilityGranted = false
        simulated.syncMenuSpaceMonitoring()
        expect(simulated.menuSpaceTimer == nil && simulatedTimer?.invalidated == true
               && simulated.geometry.compactSideRoom == nil,
               "revoking access removes measured simulated wings and stops their reader")
        simulated.accessibilityGranted = true
        simulated.idleContent = .none
        simulated.syncMenuSpaceMonitoring()
        expect(simulated.menuSpaceTimer == nil && simulated.reads == 1,
               "a bare simulated cutout needs no recurring menu reads")
        simulated.compactActivity = true
        simulated.syncMenuSpaceMonitoring()
        expect(simulated.menuSpaceTimer != nil && simulated.reads == 2,
               "starting compact activity resumes menu measurements for the simulated notch")
    }
}
