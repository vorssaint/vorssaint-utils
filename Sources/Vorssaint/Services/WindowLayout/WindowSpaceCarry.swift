// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Takes a window that is still held by its title bar to another desktop.
///
/// macOS no longer lets one app move another app's window between Spaces,
/// but a window held under the pointer travels with the desktop when the
/// desktop changes. So a pause over a desktop in the picker presses the
/// person's own "Move left/right a space" shortcut, one step at a time,
/// waiting for each switch to land before the next, and the window comes along.
final class WindowSpaceCarry {
    static let shared = WindowSpaceCarry()

    /// How long the pointer rests on a desktop before the trip starts.
    static let dwell: TimeInterval = 0.35
    private static let arrivalPoll: TimeInterval = 0.05
    private static let arrivalTimeout: TimeInterval = 1.2

    private var generation = 0
    private(set) var traveling = false
    /// Called after each desktop change, so the picker can mark the new one.
    var onArrival: (() -> Void)?

    private init() {}

    /// Whether the shortcuts a trip needs are switched on in System Settings.
    static var canCarry: Bool {
        SpaceWindowBridge.spaceShortcut(.left) != nil && SpaceWindowBridge.spaceShortcut(.right) != nil
    }

    /// The pointer came to rest over `space`. `pointer` is an AppKit point.
    func hover(_ space: UInt64, pointer: CGPoint, buttonHeld: @escaping () -> Bool) {
        generation += 1
        let trip = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell) { [weak self] in
            guard let self, trip == self.generation, buttonHeld() else { return }
            self.travel(to: space, pointer: pointer, trip: trip, buttonHeld: buttonHeld)
        }
    }

    /// The pointer left the desktop, or the drag ended.
    func cancel() {
        generation += 1
        traveling = false
    }

    private func travel(to space: UInt64, pointer: CGPoint, trip: Int, buttonHeld: @escaping () -> Bool) {
        guard trip == generation, buttonHeld(),
              let steps = WindowSnapLayoutsSupport.steps(to: space, topology: Self.row(near: pointer)) else {
            traveling = false
            return
        }
        guard steps != 0 else {
            traveling = false
            return
        }
        guard let shortcut = SpaceWindowBridge.spaceShortcut(steps > 0 ? .right : .left) else {
            traveling = false
            return
        }
        traveling = true
        let before = Self.row(near: pointer)?.current
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
        waitForArrival(from: before, pointer: pointer, trip: trip, deadline: Date().addingTimeInterval(Self.arrivalTimeout)) { [weak self] arrived in
            guard let self, trip == self.generation else { return }
            self.onArrival?()
            if arrived { self.travel(to: space, pointer: pointer, trip: trip, buttonHeld: buttonHeld) }
            else { self.traveling = false }
        }
    }

    private func waitForArrival(from before: UInt64?, pointer: CGPoint, trip: Int, deadline: Date,
                                done: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.arrivalPoll) { [weak self] in
            guard let self, trip == self.generation else { return }
            if let now = Self.row(near: pointer)?.current, now != before { return done(true) }
            if Date() >= deadline { return done(false) }
            self.waitForArrival(from: before, pointer: pointer, trip: trip, deadline: deadline, done: done)
        }
    }

    /// The desktops of the display under `pointer`, left to right, and the one showing.
    static func row(near pointer: CGPoint) -> (spaces: [UInt64], current: UInt64?)? {
        guard let topology = SpaceWindowBridge.topology() else { return nil }
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let number = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let display = topology.displays.first { $0.displayID == number } ?? topology.displays.first
        return display.map { ($0.spaces, $0.currentSpace) }
    }
}
