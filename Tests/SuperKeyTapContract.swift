// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The real tap thread body runs against a macOS that refuses every event tap.
/// No tap, key mapping or run loop is created.
enum SuperKeyTapContract {
    enum Tap {
        static var requests = 0
        static func create(tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions,
                           eventsOfInterest: CGEventMask, callback: CGEventTapCallBack,
                           userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
            requests += 1
            return nil
        }
    }
    enum Queue {
        static var pending: [() -> Void] = []
        static var main: Queue.Type { Self.self }
        static func async(execute: @escaping () -> Void) { pending.append(execute) }
    }
    class State {
        typealias DispatchQueue = Queue
        static var isEngaged = true
        static let mouseDownTypes: [CGEventType] = [.leftMouseDown]
        let lifecycleLock = NSLock()
        var tapRunLoop: CFRunLoop?
        var tapThread: Thread?
        var shouldStopTapThread = false
        var tap: CFMachPort?
        var mouseTap: CFMachPort?
        var mouseTapRefusals = 0
        var isRunning = true
        var mappingFailure: SuperKeyMappingFailure?
        var clearedMappings = 0
        func clearEventTapThread() -> Bool { false }
        func startOnMain() {}
        func clearLeftoverMapping() { clearedMappings += 1 }
        func tapDidStart(_ tap: CFMachPort) {}
        func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? { nil }
    }

    static func run(_ suite: TestSuite) {
        let service = SuperKeyService()
        service.runEventTap()
        Queue.pending.forEach { $0() }
        Queue.pending = []
        suite.expect(Tap.requests == 1 && !service.isRunning && !State.isEngaged && service.clearedMappings == 1
                     && service.mappingFailure == .keyboardTapRefused,
                     "a refused keyboard tap stops the key and reports why, found \(String(describing: service.mappingFailure))")
    }
}
