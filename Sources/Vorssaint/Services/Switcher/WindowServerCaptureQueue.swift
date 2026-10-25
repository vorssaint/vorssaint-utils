// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Lets one window capture reach the system at a time, ScreenCaptureKit work
/// included, and keeps the synchronous window-server calls off Swift's
/// cooperative executor. Cancellation releases the caller, but an in-flight
/// system call keeps its place until it actually returns. A cancelled queued
/// request never captures.
///
/// Every capture has the system check Screen Recording for this app, and the
/// window server can wait for that check on its main thread. When the check
/// stalls (tccd took over a minute under heavy load in issue #1863), a
/// window-server capture gives up on ScreenCaptureKit after 30 seconds and
/// asks the window server directly, which then waits on the same check until
/// macOS's 40-second watchdog ends the session. So a capture starts only soon
/// after the check answered promptly, a slow answer or a slow capture pauses
/// captures for longer each time, and nothing waits behind a turn that has
/// not come back.
final class WindowServerCaptureQueue: @unchecked Sendable {
    /// The check usually answers in about ten milliseconds.
    static let slowPermissionCheck: TimeInterval = 0.5
    /// Far above the tens of milliseconds a capture usually takes, far below
    /// the 30 seconds after which the system goes to the window server.
    static let slowCapture: TimeInterval = 2
    /// A prompt answer vouches for the captures that follow it closely.
    static let permissionCheckLifetime: TimeInterval = 5

    /// Doubles with each slow turn in a row, from half a minute up to ten.
    static func pause(afterSlowTurns count: Int) -> TimeInterval {
        let doublings = Double(min(max(count, 1), 6) - 1)
        return min(600, 30 * pow(2, doublings))
    }

    private typealias PermissionPreflight = @convention(c) (CFString, CFDictionary?) -> Int32

    /// `TCCAccessPreflight` puts the Screen Recording check to tccd from this
    /// app itself: it never prompts, and nothing else waits on its answer.
    /// Nil where the symbol is missing; the queue then only has its pauses
    /// to go by.
    static let screenRecordingCheck: (() -> Void)? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(framework, "TCCAccessPreflight")
        else { return nil }
        let preflight = unsafeBitCast(symbol, to: PermissionPreflight.self)
        return { _ = preflight("kTCCServiceScreenCapture" as CFString, nil) }
    }()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "window-capture")

    private let queue = DispatchQueue(label: "com.vorssaint.window-capture", qos: .userInitiated)
    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let checkPermission: () -> Void
    private var pendingCount = 0
    private var turnStartedAt: TimeInterval?
    private var pausedUntil: TimeInterval = 0
    private var slowTurns = 0
    private var promptCheckAt: TimeInterval?

    /// `checkPermission` asks the question every capture makes the system
    /// ask, with nothing else waiting on the answer.
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         checkPermission: @escaping () -> Void = {}) {
        self.now = now
        self.checkPermission = checkPermission
    }

    func capture<Value>(waitingForOtherCaptures: Bool = true,
                        _ operation: @escaping () -> Value?) async -> Value? {
        await submit(waitingForOtherCaptures: waitingForOtherCaptures) { finish in
            finish(autoreleasepool(invoking: operation))
        }
    }

    /// ScreenCaptureKit work takes a turn like a window-server call and holds
    /// it until it returns. It must not capture through this queue itself,
    /// which would wait on its own turn.
    func perform<Value>(waitingForOtherCaptures: Bool = true,
                        _ operation: @escaping () async -> Value?) async -> Value? {
        await submit(waitingForOtherCaptures: waitingForOtherCaptures) { finish in
            // The next turn waits for this one to return, not for this block.
            self.queue.suspend()
            Task.detached(priority: .userInitiated) {
                finish(await operation())
                self.queue.resume()
            }
        }
    }

    private func submit<Value>(waitingForOtherCaptures: Bool,
                               _ run: @escaping (_ finish: @escaping (Value?) -> Void) -> Void) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let request = Request<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.install(continuation) else { return }
                let accepted = lock.withLock {
                    guard acceptsTurns(at: now()), waitingForOtherCaptures || pendingCount == 0 else { return false }
                    pendingCount += 1
                    return true
                }
                guard accepted else {
                    request.finish(nil)
                    return
                }
                queue.async {
                    guard let start = self.beginTurn(unlessCancelled: { request.isFinished }) else {
                        self.lock.withLock { self.pendingCount -= 1 }
                        request.finish(nil)
                        return
                    }
                    run { value in
                        self.endTurn(startedAt: start)
                        request.finish(value)
                    }
                }
            }
        } onCancel: {
            request.finish(nil)
        }
    }

    /// Paused, or a turn that has not come back: the system is stalling, and
    /// a capture waiting behind it would only add another check.
    private func acceptsTurns(at time: TimeInterval) -> Bool {
        guard time >= pausedUntil else { return false }
        guard let turnStartedAt else { return true }
        return time - turnStartedAt < Self.slowCapture
    }

    /// Whether a capture asked for now would get a turn. A caller can keep
    /// what it last saw instead of reading a refusal as a missing window.
    var acceptsCaptures: Bool { lock.withLock { acceptsTurns(at: now()) } }

    /// Starts a turn, asking the check again first when its last prompt
    /// answer is old. Nil leaves the turn without a capture.
    private func beginTurn(unlessCancelled cancelled: () -> Bool) -> TimeInterval? {
        guard !cancelled() else { return nil }
        let checkIsDue = lock.withLock { () -> Bool? in
            let time = now()
            guard time >= pausedUntil else { return nil }
            turnStartedAt = time
            return promptCheckAt.map { time - $0 >= Self.permissionCheckLifetime } ?? true
        }
        guard let checkIsDue else { return nil }
        if checkIsDue {
            let asked = now()
            checkPermission()
            let answered = now()
            let prompt = answered - asked < Self.slowPermissionCheck
            lock.withLock {
                if prompt {
                    promptCheckAt = answered
                } else {
                    turnStartedAt = nil
                    pauseAfterSlowTurn(at: answered, took: answered - asked, reason: "Screen Recording check")
                }
            }
            guard prompt else { return nil }
        }
        // Cancelled while the check was asked: still no capture.
        guard !cancelled() else {
            lock.withLock { turnStartedAt = nil }
            return nil
        }
        return now()
    }

    private func endTurn(startedAt start: TimeInterval) {
        lock.withLock {
            let time = now()
            pendingCount -= 1
            turnStartedAt = nil
            if time - start >= Self.slowCapture {
                pauseAfterSlowTurn(at: time, took: time - start, reason: "capture")
            } else {
                slowTurns = 0
            }
        }
    }

    /// Captures come back only after the check answers promptly again.
    /// Logged, since thumbnails and Watch otherwise just stop for a while.
    private func pauseAfterSlowTurn(at time: TimeInterval, took: TimeInterval, reason: String) {
        slowTurns += 1
        let pause = Self.pause(afterSlowTurns: slowTurns)
        pausedUntil = time + pause
        promptCheckAt = nil
        Self.log.notice("Window captures paused for \(Int(pause), privacy: .public) s: a \(reason, privacy: .public) took \(Int(took * 1000), privacy: .public) ms")
    }

    private final class Request<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?
        private var finished = false

        var isFinished: Bool { lock.withLock { finished } }

        func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
            let installed = lock.withLock {
                guard !finished else { return false }
                self.continuation = continuation
                return true
            }
            if !installed { continuation.resume(returning: nil) }
            return installed
        }

        func finish(_ value: Value?) {
            let continuation = lock.withLock {
                finished = true
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume(returning: value)
        }
    }
}
