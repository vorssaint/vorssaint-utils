// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The run loop that serves the event taps standing in the path of ordinary
/// clicks and wheel events.
///
/// An active tap holds each event it asked for until its callback returns, so a
/// tap served by the main run loop makes every click in every app wait for
/// whatever this app happens to be drawing, reading or asking Accessibility at
/// that moment. Under a full-screen game that shows up as clicks arriving late
/// and, when the wait crosses the system's limit, as events the window server
/// drops on its way to disabling the tap.
///
/// This thread does nothing else: no UI, no timers, no Accessibility. A tap
/// served here answers as soon as the event arrives, whatever the rest of the
/// app is doing.
enum PointerTapRunLoop {
    /// Serves `source` on the pointer thread. The tap callback runs there, so
    /// everything it touches has to be safe away from the main thread.
    static func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(runLoop, source, .commonModes)
    }

    /// Gives the source and its port back on the thread that owns them, once
    /// the callback that may be running there has returned.
    ///
    /// Never waits for that thread: a callback in flight may be asking the main
    /// thread for the app under the pointer, and the caller is usually the main
    /// thread itself. The port is only invalidated after the tap has been
    /// switched off, so nothing arrives once the block has run.
    static func remove(_ source: CFRunLoopSource, invalidating port: CFMachPort?) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            if let port {
                CFMachPortInvalidate(port)
            }
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Built on first use: a feature that never runs never starts the thread.
    private static let runLoop: CFRunLoop = {
        var started: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            started = CFRunLoopGetCurrent()
            // A run loop with no source of its own returns immediately; this
            // port is never signalled and exists only to keep it alive.
            RunLoop.current.add(NSMachPort(), forMode: .common)
            ready.signal()
            while true {
                CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
            }
        }
        thread.name = "Vorssaint Pointer Input"
        thread.qualityOfService = .userInteractive
        thread.start()
        // The wait orders the write above against the read below.
        ready.wait()
        return started!
    }()
}
