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
    struct RunningApplication { let bundleIdentifier: String? }
    enum NSWorkspace {
        static let shared = Workspace()
        final class Workspace { var frontmostApplication: RunningApplication? }
    }
    enum Bundle {
        static let main = RunningApplication(bundleIdentifier: "com.vorssaint.tests.notch")
    }
    enum ClipboardHistoryService {
        static let shared = History()
        final class History {
            var remembered = 0
            func rememberPasteTarget() { remembered += 1 }
        }
    }
    final class Panel {
        var resignations = 0
        func resignKey() { resignations += 1 }
    }
    class State {
        var running = true
        var suspended = false
        var expanded = false
        var hiddenUntilHover = false
        var captureControls: Bool?
        var idleContent = NotchIdleContent.music
        var compactActivity: Bool?
        var accessibilityGranted = true
        var menuSpaceTimer: Timer?
        var menuSpaceGeneration = 0
        var screenRefreshWork: DispatchWorkItem?
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 210, compactSideRoom: 64)
        var panel: Panel? = Panel()
        var modules: [NotchModule] = [.controls]
        var pinned = false
        var keepsWorkingSurface = false
        var preferenceSyncs = 0
        var reads = 0
        var presentations = 0
        var collapses = 0
        func syncWithPreferences() { preferenceSyncs += 1 }
        func readMenuSpace() { reads += 1 }
        func refreshPresentation(animated: Bool) { presentations += 1 }
        func collapse() { collapses += 1 }
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
        var timer = virtual.menuSpaceTimer
        expect(timer != nil && virtual.reads == 1,
               "granting Accessibility starts the existing menu reader without restarting the app")
        virtual.hiddenUntilHover = true
        virtual.syncMenuSpaceMonitoring()
        expect(virtual.menuSpaceTimer == nil && timer?.invalidated == true,
               "hidden mode stops menu polling while no window occupies the menu bar")
        virtual.hiddenUntilHover = false
        virtual.syncMenuSpaceMonitoring()
        timer = virtual.menuSpaceTimer
        virtual.geometry.compactSideRoom = 64
        virtual.accessibilityGranted = false
        virtual.syncMenuSpaceMonitoring()
        expect(virtual.menuSpaceTimer == nil && timer?.invalidated == true
               && virtual.geometry.compactSideRoom == nil && virtual.presentations == 1,
               "revoking Accessibility stops polling and withdraws stale menu-space geometry")
        virtual.accessibilityGranted = true
        virtual.running = false
        virtual.syncMenuSpaceMonitoring()
        expect(virtual.menuSpaceTimer == nil && virtual.reads == 2,
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
        expect(simulated.menuSpaceTimer != nil && simulated.reads == 2,
               "a bare simulated cutout still checks that its center does not cover menus")
        simulated.compactActivity = true
        simulated.syncMenuSpaceMonitoring()
        expect(simulated.menuSpaceTimer != nil && simulated.reads == 2,
               "starting compact activity reuses the simulated notch's existing menu reader")

        simulated.geometry.compactSideRoom = 64
        let beforeChange = simulated.menuSpaceGeneration
        let beforePresentation = simulated.presentations
        let beforeReads = simulated.reads
        NSWorkspace.shared.frontmostApplication = RunningApplication(bundleIdentifier: "com.example.terminal")
        simulated.applicationDidActivate()
        expect(simulated.geometry.compactSideRoom == 64 && simulated.menuSpaceGeneration > beforeChange
               && simulated.presentations == beforePresentation && simulated.reads == beforeReads + 1,
               "switching apps keeps the simulated cutout on screen and starts the read that decides whether it stays")
        expect(simulated.panel?.resignations == 1 && simulated.collapses == 0,
               "another app taking focus releases the island's key status without collapsing a closed island")
        simulated.syncMenuSpaceMonitoring()
        expect(simulated.geometry.compactSideRoom == 64 && simulated.reads == beforeReads + 1,
               "a preference sync during the pending read neither withdraws the cutout nor starts another read")
        simulated.expanded = true
        simulated.modules = [.controls, .clipboard]
        simulated.applicationDidActivate()
        expect(simulated.collapses == 1 && ClipboardHistoryService.shared.remembered == 1
               && simulated.reads == beforeReads + 2,
               "an open island still remembers the paste target and collapses when another app activates")
        NSWorkspace.shared.frontmostApplication = Bundle.main
        simulated.applicationDidActivate()
        expect(simulated.collapses == 1 && simulated.panel?.resignations == 2 && simulated.reads == beforeReads + 3,
               "this app activating re-reads the menus without giving up its own island")
        simulated.suspended = true
        simulated.applicationDidActivate()
        expect(simulated.reads == beforeReads + 3, "a suspended island ignores activations")
        simulated.suspended = false

        let physical = Service()
        physical.idleContent = .none
        physical.syncMenuSpaceMonitoring()
        expect(physical.menuSpaceTimer == nil && physical.reads == 0,
               "an empty physical camera does not need a menu reader")
        NSWorkspace.shared.frontmostApplication = RunningApplication(bundleIdentifier: "com.example.terminal")
        physical.applicationDidActivate()
        expect(physical.geometry.compactSideRoom == 64 && physical.presentations == 0,
               "the physical camera retains its existing presentation during app changes")

        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchService.swift",
                                  encoding: .utf8)) ?? ""
        let code = source.components(separatedBy: "\n")
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
        guard let start = code.range(of: "func readMenuSpace()"),
              let end = code.range(of: "func applyMenuSpace(", range: start.upperBound..<code.endIndex) else {
            expect(false, "the menu reader and the method that applies its result are still found")
            return
        }
        let reader = code[start.lowerBound..<end.lowerBound]
        expect(reader.contains("menuBarOwningApplication") && !reader.contains("frontmostApplication"),
               "the menu read measures the application whose menus are on the bar: an accessory app with focus "
               + "leaves the previous app's menus displayed, and its own menu geometry is never laid out")
    }
}
