// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum NotchSpacesClickTests {
    static func space(_ id: UInt64, number: Int?, current: Bool = false) -> NotchSpace {
        NotchSpace(id: id, uuid: nil, desktopNumber: number, current: current, name: nil)
    }
    enum SpaceWindowBridge {
        enum Direction { case left, right }
        enum Shortcut: Equatable { case desktop(Int), left, right }
        static var directEnabled = true
        static var arrowsEnabled = true
        static var presses: [Shortcut] = []
        static func desktopShortcut(number: Int?) -> Shortcut? {
            guard directEnabled, let number, SpaceHopSupport.desktopHotKeyID(number: number) != nil else { return nil }
            return .desktop(number)
        }
        static func spaceShortcut(_ direction: Direction) -> Shortcut? {
            arrowsEnabled ? (direction == .right ? .right : .left) : nil
        }
        static func pressSpaceShortcut(_ shortcut: Shortcut) { presses.append(shortcut) }
    }
    enum SpaceHop {
        static var cancellations = 0
        static func cancelPending() { cancellations += 1 }
    }
    enum DispatchQueue {
        static let main = Queue()
        static var jobs: [DispatchWorkItem] = []
        final class Queue {
            func asyncAfter(deadline: DispatchTime, execute: DispatchWorkItem) { jobs.append(execute) }
        }
        static func next() {
            guard !jobs.isEmpty else { return }
            let job = jobs.removeFirst()
            if !job.isCancelled { job.perform() }
        }
    }
    class State {
        var snapshot = Snapshot(displayID: 1, spaces: [space(10, number: 1, current: true), space(20, number: 2), space(30, number: nil)])
        var running = true
        var enabled = true
        var trusted = true
        var switching = false
        var shortcutUnavailable = false
        var generation = UUID()
        var travel: DispatchWorkItem?
        func AXIsProcessTrusted() -> Bool { trusted }
        var focusedDisplay: CGDirectDisplayID?
        var cursorRestored = false
        func focusDisplay(_ id: CGDirectDisplayID) -> Bool { focusedDisplay = id; snapshot.displayID = id; return true }
        func restoreCursorIfNeeded() { cursorRestored = true }
        func refresh() {}
    }
    enum NotchSpacesService { static let shared = Service() }
    enum NotchService { static let shared = Island() }
    class IslandState {
        var acceptsUserInteraction = true
        var modules: [NotchModule] = [.spaces]
        var pending: (() -> Void)?
        var collapsed = false
        func perform(_ action: @escaping () -> Void) {
            collapsed = true
            pending = action
        }
    }
    static func reset() {
        SpaceWindowBridge.presses = []
        SpaceWindowBridge.directEnabled = true
        SpaceWindowBridge.arrowsEnabled = true
        DispatchQueue.jobs = []
    }
    static func run(_ suite: TestSuite) {
        defer { reset() }
        reset()
        let shared = Service()
        var externalCurrent = space(40, number: 4, current: true)
        externalCurrent.displayID = 2
        var externalTarget = space(50, number: 5)
        externalTarget.displayID = 2
        shared.snapshot.spaces = shared.snapshot.spaces.map { value in
            var value = value; value.displayID = 1; return value
        } + [externalCurrent, externalTarget]
        shared.select(50)
        suite.expect(shared.focusedDisplay == 2 && SpaceWindowBridge.presses == [.desktop(5)],
                     "a remote desktop click routes the shortcut to its owning display")
        shared.snapshot.spaces[3] = space(40, number: 4)
        shared.snapshot.spaces[3].displayID = 2
        externalTarget = space(50, number: 5, current: true)
        externalTarget.displayID = 2
        shared.snapshot.spaces[4] = externalTarget
        DispatchQueue.next()
        suite.expect(!shared.switching && shared.cursorRestored,
                     "arrival observes the target display's current Space and restores the cursor")
        reset()
        SpaceWindowBridge.directEnabled = false
        let sharedArrows = Service()
        var builtIn = space(10, number: 1, current: true)
        builtIn.displayID = 1
        sharedArrows.snapshot.spaces = [builtIn, externalCurrent, externalTarget]
        sharedArrows.snapshot.spaces[2] = space(50, number: 5)
        sharedArrows.snapshot.spaces[2].displayID = 2
        sharedArrows.select(50)
        suite.expect(SpaceWindowBridge.presses == [.right],
                     "remote directional fallback counts only the owning display's Spaces")
        sharedArrows.cancelTravel()
        reset()
        NotchSpacesService.shared.step(forward: true)
        suite.expect(NotchService.shared.collapsed && NotchService.shared.pending != nil
                     && SpaceWindowBridge.presses.isEmpty,
                     "arrow and swipe steps use the same focus handoff as a Space click")
        NotchService.shared.pending?()
        suite.expect(SpaceWindowBridge.presses == [.desktop(2)],
                     "a stepped Space sends its shortcut only after the island has settled")
        NotchSpacesService.shared.cancelTravel()
        reset()
        let island = Island()
        island.switchSpace(20)
        suite.expect(island.collapsed && island.pending != nil && SpaceWindowBridge.presses.isEmpty,
                     "a click closes the island and sends no input while it still holds focus")
        island.pending?()
        suite.expect(SpaceWindowBridge.presses == [.desktop(2)],
                     "once the island settles, the click invokes the selected desktop's registered shortcut")
        NotchSpacesService.shared.cancelTravel()
        reset()
        let service = Service()
        service.select(20)
        service.snapshot.spaces = [space(10, number: 1), space(20, number: 2, current: true), space(30, number: nil)]
        DispatchQueue.next()
        suite.expect(!service.switching && SpaceWindowBridge.presses == [.desktop(2)],
                     "verified direct arrival completes without additional arrow presses")
        reset()
        SpaceWindowBridge.directEnabled = false
        let arrows = Service()
        arrows.select(20)
        suite.expect(SpaceWindowBridge.presses == [.right], "a disabled direct binding falls back to the registered arrow")
        reset()
        let fullscreen = Service()
        fullscreen.select(30)
        suite.expect(SpaceWindowBridge.presses == [.right], "full-screen Spaces use directional travel without a desktop binding")
        fullscreen.snapshot.spaces = [space(10, number: 1), space(20, number: 2, current: true), space(30, number: nil)]
        DispatchQueue.next()
        suite.expect(SpaceWindowBridge.presses == [.right, .right], "each intermediate arrival is verified before another step")
        reset()
        let stalled = Service()
        stalled.switching = true
        stalled.waitForArrival(from: 10, to: 20, displayID: 1, remaining: 16,
                               deadline: .now() - 1, generation: stalled.generation, fallbackToArrows: true)
        DispatchQueue.next()
        suite.expect(SpaceWindowBridge.presses == [.right] && stalled.switching,
                     "a direct shortcut that fails to arrive gets one verified directional fallback")
        reset()
        let disabled = Service()
        SpaceWindowBridge.directEnabled = false
        SpaceWindowBridge.arrowsEnabled = false
        disabled.select(20)
        suite.expect(disabled.shortcutUnavailable && !disabled.switching && SpaceWindowBridge.presses.isEmpty,
                     "disabled bindings report unavailability without inventing a shortcut")
        reset()
        let revoked = Service()
        revoked.select(20)
        revoked.trusted = false
        DispatchQueue.next()
        suite.expect(!revoked.switching && SpaceWindowBridge.presses == [.desktop(2)],
                     "permission revocation cancels pending travel")
        reset()
        let movedPointer = Service()
        movedPointer.select(20)
        movedPointer.snapshot.displayID = 2
        DispatchQueue.next()
        suite.expect(!movedPointer.switching && SpaceWindowBridge.presses == [.desktop(2)],
                     "moving to another display cancels travel before it can affect that display")
        reset()
        let replaced = Service()
        replaced.select(20)
        let old = DispatchQueue.jobs.removeFirst()
        replaced.select(30)
        old.perform()
        suite.expect(replaced.switching && SpaceWindowBridge.presses == [.desktop(2), .right],
                     "an obsolete arrival callback cannot cancel a newer selection")
        reset()
        let blocked = Service()
        blocked.trusted = false
        blocked.select(20)
        suite.expect(!blocked.switching && SpaceWindowBridge.presses.isEmpty, "clicks require live Accessibility trust")
        let hidden = Island()
        hidden.modules = []
        hidden.switchSpace(20)
        suite.expect(!hidden.collapsed && hidden.pending == nil, "a hidden Spaces section cannot send input")
    }
}
