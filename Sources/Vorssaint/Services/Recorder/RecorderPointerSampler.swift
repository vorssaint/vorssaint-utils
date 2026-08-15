// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Records where the pointer went while a recording runs.
///
/// A fixed-cadence sampler on its own thread rather than an event tap, for
/// three reasons: it needs no permission at all, it costs about a hundred
/// nanoseconds per sample, and a filter that runs offline wants its input on
/// an even grid anyway. The presses come from a mouse-only global monitor,
/// which is exact and, unlike key events, ungated.
///
/// Nothing here exists between recordings: the thread, the monitor and the
/// buffer are all created in `start()` and gone after `stop()`.
final class RecorderPointerSampler {

    private let region: RecorderSupport.Region
    private let displayBounds: CGRect
    private let pauseClock: RecorderPauseClock

    private var thread: Thread?
    private var clickMonitor: Any?
    private let lock = NSLock()
    private var samples: [RecorderMotion.Sample] = []
    /// The pointer shape in effect for each sample, kept alongside rather than
    /// inside it: the seed only becomes an index once the recording is over
    /// and every shape that appeared is known.
    private var identities: [UInt64] = []
    private var clicks: [RecorderMotion.Click] = []
    private let cursors = RecorderCursorCatalog()
    private var startedAt: CFTimeInterval = 0
    private var running = false
    private var generation = 0
    private var lastSeed: Int32?
    private var currentIdentity: UInt64 = 0
    private let displayScale: Double

    /// 125 Hz: comfortably above any mouse report rate we care about, and
    /// still around fourteen microseconds of work per second of recording.
    private static let sampleRate: Double = 125

    init(region: RecorderSupport.Region, pauseClock: RecorderPauseClock) {
        self.region = region
        self.pauseClock = pauseClock
        displayBounds = CGDisplayBounds(region.displayID)
        displayScale = region.scale > 0 ? region.scale : 2
    }

    // MARK: - Lifecycle

    func start() {
        guard thread == nil else { return }
        let startedAt = CACurrentMediaTime()
        let generation = lock.withLock { () -> Int in
            self.startedAt = startedAt
            self.generation += 1
            running = true
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(Int(Self.sampleRate) * 60)
            identities.removeAll(keepingCapacity: true)
            identities.reserveCapacity(Int(Self.sampleRate) * 60)
            lastSeed = nil
            currentIdentity = 0
            clicks.removeAll(keepingCapacity: true)
            return self.generation
        }

        // Mouse-only monitors need no Accessibility grant, and a press is
        // never coalesced the way a move is, so these timestamps are exact.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            self?.record(event, generation: generation)
        }

        let thread = Thread { [weak self] in
            self?.loop(generation: generation, startedAt: startedAt)
        }
        thread.qualityOfService = .userInteractive
        thread.name = "com.vorssaint.recorder.pointer"
        self.thread = thread
        thread.start()
    }

    /// Stops sampling and hands over what was collected.
    func stop() -> RecorderPointerTrack {
        thread = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        return lock.withLock {
            running = false
            let track = RecorderPointerTrack.packing(samples: samples,
                                                     identities: identities,
                                                     clicks: clicks,
                                                     catalog: cursors.collected(),
                                                     systemScale: cursors.systemScale,
                                                     displayScale: displayScale)
            samples.removeAll()
            identities.removeAll()
            clicks.removeAll()
            return track
        }
    }

    // MARK: - Sampling

    private func loop(generation: Int, startedAt: CFTimeInterval) {
        let interval = 1.0 / Self.sampleRate
        while lock.withLock({ running && self.generation == generation }) {
            let now = CACurrentMediaTime()
            if let time = pauseClock.eventTime(now, since: startedAt),
               let point = normalizedPointerLocation() {
                // Two nanoseconds to ask whether the pointer changed, twenty
                // two microseconds to read the new one. So the question rides
                // every sample and the answer is fetched only on a change.
                lock.withLock {
                    guard running, self.generation == generation else { return }
                    let seed = cursors.currentSeed()
                    if seed != lastSeed {
                        lastSeed = seed
                        let identity = cursors.captureCurrentShape()
                        if identity != 0 { currentIdentity = identity }
                    }
                    let sample = RecorderMotion.Sample(
                        time: time,
                        point: point,
                        isPointerVisible: cursors.isPointerVisible()
                    )
                    samples.append(sample)
                    identities.append(currentIdentity)
                }
            }
            let elapsed = CACurrentMediaTime() - now
            if elapsed < interval {
                Thread.sleep(forTimeInterval: interval - elapsed)
            }
        }
    }

    /// The pointer inside the recorded area, 0...1 with a top-left origin.
    /// `CGEvent(source: nil)?.location` is already in the window server's
    /// top-left global space, which is the same space the recorded rectangle
    /// is expressed in, so there is no flipping to get wrong.
    private func normalizedPointerLocation() -> CGPoint? {
        guard let location = CGEvent(source: nil)?.location,
              location.x.isFinite, location.y.isFinite
        else { return nil }
        let scale = region.scale > 0 ? region.scale : 1
        let originX = displayBounds.origin.x + region.pixelRect.origin.x / scale
        let originY = displayBounds.origin.y + region.pixelRect.origin.y / scale
        let width = region.pixelRect.width / scale
        let height = region.pixelRect.height / scale
        guard width > 0, height > 0 else { return nil }
        return CGPoint(x: (location.x - originX) / width,
                       y: (location.y - originY) / height)
    }

    private func record(_ event: NSEvent, generation: Int) {
        lock.withLock {
            guard running, self.generation == generation else { return }
            guard let time = pauseClock.eventTime(CACurrentMediaTime(), since: startedAt)
            else { return }
            let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown
            let click = RecorderMotion.Click(time: time, isDown: isDown)
            clicks.append(click)
        }
    }

}
