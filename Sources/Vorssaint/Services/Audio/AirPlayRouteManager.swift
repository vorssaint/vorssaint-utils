// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import AVKit
import Combine
import CoreMedia
import Foundation
import ObjectiveC

/// Bridges macOS native AirPlay output routing into Vorssaint.
///
/// Discovers and connects AirPlay devices using the system's trusted routing
/// stack (`AVOutputContext` / `AVRoutePickerView`), bypassing Core Audio HAL's
/// inability to enumerate offline AirPlay endpoints.
final class AirPlayRouteManager: NSObject, ObservableObject {
    static let shared = AirPlayRouteManager()

    /// Virtual UID used by Vorssaint to represent an AirPlay output route.
    static let airPlaySentinelUID = "vorssaint.output.airplay"

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var activeSpeakerName: String?
    @Published private(set) var isPresentingPicker: Bool = false

    /// What the mixer's device refresh needs, readable from its HAL queue
    /// without creating the manager (which must happen on the main thread).
    private static let snapshotLock = NSLock()
    private static var snapshotIsListed = false
    private static var snapshotSpeakerName: String?
    private static var snapshotIsConnected = false

    /// True while the mixer is running and AirPlay can actually be streamed to.
    static var isListed: Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotIsListed
    }

    /// True while a speaker is picked, so the AirPlay entry can carry audio.
    static var isSpeakerConnected: Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotIsConnected
    }

    /// The speaker chosen in the picker, if any.
    static var currentSpeakerName: String? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotSpeakerName
    }

    private var cachedIsConnected: Bool = false
    private var cachedSpeakerName: String?

    private var routingContext: NSObject?
    private weak var activePickerView: NSView?
    private var pollTimer: Timer?
    /// Called on the main thread when the connection or speaker changes.
    private var onChange: (() -> Void)?

    private typealias MsgSendClass = @convention(c) (AnyClass, Selector) -> AnyObject?
    private typealias MsgSendObj = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias MsgSendObjReturn = @convention(c) (AnyObject, Selector) -> AnyObject?

    private let msgSendSym = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")

    private override init() {
        assert(Thread.isMainThread, "AirPlayRouteManager must be created on the main thread")
        super.init()
        dlopen("/System/Library/Frameworks/AVKit.framework/AVKit", RTLD_NOW)
        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW)
        setupContext()
        // Streaming needs both the shared context and a renderer that can be
        // bound to it; without either, AirPlay is never offered.
        self.isAvailable = routingContext != nil
            && AVSampleBufferAudioRenderer.instancesRespond(to: sel_registerName("setOutputContext:"))
    }

    deinit {
        pollTimer?.invalidate()
    }

    /// Starts tracking the picked speaker while the mixer runs. Main thread.
    func activate(onChange: @escaping () -> Void) {
        assert(Thread.isMainThread)
        self.onChange = onChange
        Self.snapshotLock.lock()
        Self.snapshotIsListed = isAvailable
        Self.snapshotLock.unlock()
        refreshActiveDevice()
        guard isAvailable, pollTimer == nil else { return }
        // Poll the speaker name every 1.5 seconds on the main run loop.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshActiveDevice()
        }
    }

    /// Stops tracking; the mixer no longer lists AirPlay. Main thread.
    func deactivate() {
        assert(Thread.isMainThread)
        pollTimer?.invalidate()
        pollTimer = nil
        onChange = nil
        Self.snapshotLock.lock()
        Self.snapshotIsListed = false
        Self.snapshotIsConnected = false
        Self.snapshotLock.unlock()
    }

    private func setupContext() {
        guard let cls = NSClassFromString("AVOutputContext"), let sym = msgSendSym else { return }
        let msgClass = unsafeBitCast(sym, to: MsgSendClass.self)
        let sharedSys = sel_registerName("sharedSystemAudioContext")
        let defaultShared = sel_registerName("defaultSharedOutputContext")

        if let ctx = (msgClass(cls, sharedSys) ?? msgClass(cls, defaultShared)) as? NSObject {
            self.routingContext = ctx
        }
    }

    /// Creates and binds an `AVRoutePickerView` to the routing context.
    func makeRoutePickerView(isActive: Bool = true) -> NSView? {
        guard let context = routingContext, let sym = msgSendSym else { return nil }
        let picker = AVRoutePickerView()
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        let setCtxSel = sel_registerName("setOutputContextID:")

        if let ctxID = context.value(forKey: "ID") as? String, picker.responds(to: setCtxSel) {
            msgObj(picker, setCtxSel, ctxID as AnyObject)
        }
        picker.delegate = self
        if isActive {
            self.activePickerView = picker
        }
        return picker
    }

    /// Returns true if an active picker view exists to anchor `presentPicker`.
    var canPresentPicker: Bool {
        activePickerView != nil
    }

    private var fallbackWindow: NSWindow?
    /// The picker hosted in `fallbackWindow`; its delegate callback closes the window.
    private weak var fallbackPicker: AVRoutePickerView?

    /// Programmatically opens the system route picker anchored to the active picker view,
    /// or anchors an invisible transient popup at the mouse cursor if no UI picker is currently mounted.
    func presentPicker() {
        if let picker = activePickerView, picker.window != nil, let button = findButton(in: picker) {
            button.performClick(nil)
            return
        }

        fallbackWindow?.orderOut(nil)
        fallbackWindow = nil

        let mouseLoc = NSEvent.mouseLocation
        let win = NSWindow(
            contentRect: NSRect(x: mouseLoc.x - 10, y: mouseLoc.y - 10, width: 20, height: 20),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.alphaValue = 0.01 // Invisible so no icon shows on screen
        win.level = .popUpMenu // Appears on top of all panels and notch, never underneath
        win.hasShadow = false
        win.isReleasedWhenClosed = false

        if let picker = makeRoutePickerView(isActive: false) {
            picker.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            win.contentView?.addSubview(picker)
            win.orderFront(nil)
            self.fallbackWindow = win
            self.fallbackPicker = picker as? AVRoutePickerView

            // Watchdog to ensure temporary window is cleaned up eventually
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self, weak win] in
                if self?.fallbackWindow === win {
                    win?.orderOut(nil)
                    self?.fallbackWindow = nil
                }
            }

            if let button = findButton(in: picker) {
                button.performClick(nil)
            }
        }
    }

    private func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let found = findButton(in: subview) { return found }
        }
        return nil
    }

    /// Refreshes the currently connected AirPlay device name and status.
    func refreshActiveDevice() {
        assert(Thread.isMainThread)
        guard let context = routingContext, let sym = msgSendSym else { return }
        let msgObjReturn = unsafeBitCast(sym, to: MsgSendObjReturn.self)

        var name: String? = nil
        let outputDevicesSel = sel_registerName("outputDevices")
        if context.responds(to: outputDevicesSel),
           let devices = msgObjReturn(context, outputDevicesSel) as? [NSObject] {
            let names = devices.compactMap { dev -> String? in
                guard let n = dev.value(forKey: "name") as? String, !n.isEmpty, !n.hasPrefix("APEndpoint") else {
                    return nil
                }
                return n
            }
            if !names.isEmpty {
                name = names.joined(separator: " + ")
            }
        }

        if name == nil {
            let outputDevSel = sel_registerName("outputDevice")
            if context.responds(to: outputDevSel),
               let dev = msgObjReturn(context, outputDevSel) as? NSObject,
               let n = dev.value(forKey: "name") as? String,
               !n.isEmpty, !n.hasPrefix("APEndpoint") {
                name = n
            }
        }

        let outputDevSel = sel_registerName("outputDevice")
        let hasDevice = context.responds(to: outputDevSel) && msgObjReturn(context, outputDevSel) != nil
        let connected = hasDevice && name != nil

        let connectedChanged = cachedIsConnected != connected
        let nameChanged = cachedSpeakerName != name
        cachedIsConnected = connected
        cachedSpeakerName = name
        Self.snapshotLock.lock()
        Self.snapshotSpeakerName = name
        Self.snapshotIsConnected = connected
        Self.snapshotLock.unlock()

        if connectedChanged {
            self.isConnected = connected
        }
        if nameChanged {
            self.activeSpeakerName = name
        }
        if connectedChanged || nameChanged {
            onChange?()
        }
    }

    /// Binds an audio object (such as AVSampleBufferAudioRenderer) to the routing context.
    func bindOutputContext(to audioObject: AnyObject) -> Bool {
        guard let context = routingContext, let sym = msgSendSym else { return false }
        let setCtxSel = sel_registerName("setOutputContext:")
        guard audioObject.responds(to: setCtxSel) else { return false }
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        msgObj(audioObject, setCtxSel, context)
        return true
    }

    // MARK: - Per-App AirPlay Streaming

    private var airPlayRenderer: AirPlayRenderer?
    private let mixerSource = MixingAudioSource()
    private let streamLock = NSLock()

    /// Adds an app's stream; false when no renderer could be started for it.
    func addAudioStream(key: String, buffer: AudioRingBuffer) -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        startRendererIfNeeded()
        guard airPlayRenderer != nil else { return false }
        mixerSource.setBuffer(buffer, forKey: key)
        return true
    }

    func removeAudioStream(key: String) {
        streamLock.lock()
        mixerSource.removeBuffer(forKey: key)
        if mixerSource.isEmpty {
            stopRenderer()
        }
        streamLock.unlock()
    }

    private func startRendererIfNeeded() {
        guard airPlayRenderer == nil else { return }
        guard let renderer = AirPlayRenderer(source: mixerSource, manager: self) else { return }
        renderer.start()
        self.airPlayRenderer = renderer
    }

    private func stopRenderer() {
        airPlayRenderer?.stop()
        airPlayRenderer = nil
    }
}

// MARK: - Ring Buffer & Streaming Pipeline

/// Lock-free single-producer / single-consumer ring buffer for interleaved stereo Float32 frames.
/// Realtime-safe for the Core Audio IO proc producer.
///
/// Positions are 64-bit frame counts that only ever grow, so they never wrap
/// in practice (a 32-bit count overflowed after about 12 hours at 48 kHz).
/// Positions and samples live in manually allocated memory: the IO thread
/// never goes through Swift array or property access.
final class AudioRingBuffer: @unchecked Sendable {
    let sampleRate: Double
    private let capacityFrames: Int
    private let storage: UnsafeMutablePointer<Float>
    /// [0] = next frame to read (consumer), [1] = next frame to write (producer).
    private let positions: UnsafeMutablePointer<Int64>

    /// `startingFramePosition` exists for tests that exercise long-running streams.
    init(sampleRate: Double = 44_100, capacityFrames: Int = 1 << 16, startingFramePosition: Int64 = 0) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        var cap = 1
        while cap < capacityFrames { cap <<= 1 }
        self.capacityFrames = cap
        storage = .allocate(capacity: cap * 2)
        storage.initialize(repeating: 0, count: cap * 2)
        positions = .allocate(capacity: 2)
        positions.initialize(repeating: startingFramePosition, count: 2)
    }

    deinit {
        storage.deallocate()
        positions.deallocate()
    }

    private var head: UnsafeMutablePointer<Int64> { positions }
    private var tail: UnsafeMutablePointer<Int64> { positions + 1 }

    /// Producer: Called from Core Audio realtime IO thread. Zero allocations, no locks.
    func write(frames: UnsafePointer<Float>, frameCount: Int, gain: Float) {
        let t = OSAtomicAdd64Barrier(0, tail)
        let h = OSAtomicAdd64Barrier(0, head)
        let available = capacityFrames - Int(t - h)
        let count = min(frameCount, available)
        guard count > 0 else { return }

        let mask = Int64(capacityFrames - 1)
        for i in 0..<count {
            let slot = Int((t + Int64(i)) & mask) * 2
            storage[slot] = frames[i * 2] * gain
            storage[slot + 1] = frames[i * 2 + 1] * gain
        }
        _ = OSAtomicAdd64Barrier(Int64(count), tail)
    }

    /// Consumer: Called from the AirPlay streaming feed queue.
    @discardableResult
    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let h = OSAtomicAdd64Barrier(0, head)
        let t = OSAtomicAdd64Barrier(0, tail)
        let count = min(frameCount, Int(t - h))

        let mask = Int64(capacityFrames - 1)
        for i in 0..<count {
            let slot = Int((h + Int64(i)) & mask) * 2
            destination[i * 2] = storage[slot]
            destination[i * 2 + 1] = storage[slot + 1]
        }
        if count < frameCount {
            (destination + count * 2).update(repeating: 0, count: (frameCount - count) * 2)
        }
        if count > 0 {
            _ = OSAtomicAdd64Barrier(Int64(count), head)
        }
        return count
    }
}

/// Resamples one provider's interleaved stereo Float32 frames to 44.1 kHz using linear interpolation.
final class LinearResampler: @unchecked Sendable {
    private let buffer: AudioRingBuffer
    private var phase: Double = 0
    private var carry: [Float] = []
    private var scratch = [Float](repeating: 0, count: 8192 * 2)

    init(buffer: AudioRingBuffer) {
        self.buffer = buffer
    }

    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let sourceRate = buffer.sampleRate > 0 ? buffer.sampleRate : 44_100
        let ratio = sourceRate / 44_100.0

        if abs(ratio - 1.0) < 0.0001 {
            buffer.read(into: destination, frameCount: frameCount)
            carry.removeAll(keepingCapacity: true)
            phase = 0
            return
        }

        let totalNeeded = Int(phase + Double(frameCount - 1) * ratio) + 2
        let carryFrames = carry.count / 2
        let freshNeeded = max(0, totalNeeded - carryFrames)

        if scratch.count < totalNeeded * 2 {
            scratch = [Float](repeating: 0, count: totalNeeded * 2)
        }

        scratch.withUnsafeMutableBufferPointer { sourceBuffer in
            guard let source = sourceBuffer.baseAddress else { return }
            for (index, sample) in carry.enumerated() { source[index] = sample }
            if freshNeeded > 0 {
                buffer.read(into: source + carry.count, frameCount: freshNeeded)
            }

            for frame in 0..<frameCount {
                let position = phase + Double(frame) * ratio
                let index = min(Int(position), totalNeeded - 2)
                let fraction = Float(position - Double(index))

                let left0 = source[index * 2]
                let right0 = source[index * 2 + 1]
                let left1 = source[(index + 1) * 2]
                let right1 = source[(index + 1) * 2 + 1]

                destination[frame * 2] = left0 + (left1 - left0) * fraction
                destination[frame * 2 + 1] = right0 + (right1 - right0) * fraction
            }

            let endPosition = phase + Double(frameCount) * ratio
            let consumed = min(Int(endPosition), totalNeeded)
            phase = endPosition - Double(consumed)

            carry.removeAll(keepingCapacity: true)
            for index in (consumed * 2)..<(totalNeeded * 2) {
                carry.append(source[index])
            }
        }
    }
}

/// Sums audio from any number of active per-app ring buffers into a single 44.1 kHz Int16 stream.
final class MixingAudioSource: @unchecked Sendable {
    private let lock = NSLock()
    private var resamplers: [String: LinearResampler] = [:]
    private var mixBus = [Float](repeating: 0, count: 4096 * 2)
    private var laneBus = [Float](repeating: 0, count: 4096 * 2)
    /// A boosted app, or several loud ones together, can sum past full scale.
    /// The same limiter the device path uses turns the mix down for just those
    /// peaks instead of clipping them into crackle (issue #326).
    private let limiter = BoostLookaheadLimiter(channels: 2)
    private let limiterRelease = BoostLimiter.release(sampleRate: 44_100)

    func setBuffer(_ buffer: AudioRingBuffer, forKey key: String) {
        lock.lock()
        resamplers[key] = LinearResampler(buffer: buffer)
        lock.unlock()
    }

    func removeBuffer(forKey key: String) {
        lock.lock()
        resamplers.removeValue(forKey: key)
        lock.unlock()
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resamplers.isEmpty
    }

    func readFrames(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int) {
        lock.lock()
        let lanes = Array(resamplers.values)
        lock.unlock()

        let samples = frameCount * 2
        if mixBus.count < samples {
            mixBus = [Float](repeating: 0, count: samples)
            laneBus = [Float](repeating: 0, count: samples)
        }

        mixBus.withUnsafeMutableBufferPointer { mix in
            guard let mixBase = mix.baseAddress else { return }
            for index in 0..<samples { mixBase[index] = 0 }

            laneBus.withUnsafeMutableBufferPointer { lane in
                guard let laneBase = lane.baseAddress else { return }
                for resampler in lanes {
                    resampler.read(into: laneBase, frameCount: frameCount)
                    for index in 0..<samples { mixBase[index] += laneBase[index] }
                }
            }
            limiter.process(mixBase, frames: frameCount, channels: 2, release: limiterRelease)

            for index in 0..<samples {
                let scaled = mixBase[index] * 32_767
                buffer[index] = Int16(max(-32_768, min(32_767, scaled)))
            }
        }
    }
}

/// Streams 44.1 kHz Int16 stereo audio to the selected AirPlay device via AVSampleBufferAudioRenderer.
final class AirPlayRenderer: @unchecked Sendable {
    private let source: MixingAudioSource
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let feedQueue = DispatchQueue(label: "com.vorssaint.utils.airplay.render", qos: .userInitiated)

    private let formatDescription: CMAudioFormatDescription
    private let sampleRate: Double = 44_100
    private let framesPerChunk = 2_048
    private var started = false
    private var nextPTS = CMTime.zero

    init?(source: MixingAudioSource, manager: AirPlayRouteManager) {
        self.source = source

        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        ) == noErr, let format else { return nil }
        self.formatDescription = format

        // Unbound, the renderer would play on the local default output while
        // the app is muted by its tap and the UI claims AirPlay.
        guard manager.bindOutputContext(to: renderer) else { return nil }
        synchronizer.addRenderer(renderer)
    }

    private var feedTimer: DispatchSourceTimer?

    func start() {
        guard !started else { return }
        started = true
        nextPTS = CMTime.zero

        synchronizer.setRate(1.0, time: .zero)

        let timer = DispatchSource.makeTimerSource(queue: feedQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            self?.provide()
        }
        timer.resume()
        self.feedTimer = timer
    }

    func stop() {
        guard started else { return }
        started = false
        feedTimer?.cancel()
        feedTimer = nil
        renderer.flush()
        synchronizer.rate = 0
    }

    private let targetLookahead = 0.75

    private func provide() {
        while renderer.isReadyForMoreMediaData {
            let lookahead = CMTimeGetSeconds(CMTimeSubtract(nextPTS, synchronizer.currentTime()))
            if lookahead > targetLookahead { break }

            guard let buffer = makeSampleBuffer() else { break }
            renderer.enqueue(buffer)
        }
    }

    private func makeSampleBuffer() -> CMSampleBuffer? {
        let format = formatDescription
        let frames = framesPerChunk
        let byteCount = frames * 4 // 2ch * Int16

        var pcm = [Int16](repeating: 0, count: frames * 2)
        pcm.withUnsafeMutableBufferPointer { source.readFrames(into: $0.baseAddress!, frameCount: frames) }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let block = blockBuffer else { return nil }

        let copied = pcm.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: nextPTS, decodeTimeStamp: .invalid
        )
        var sampleSize = 4
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer
        ) == noErr, let buffer = sampleBuffer else { return nil }

        nextPTS = CMTimeAdd(nextPTS, CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(sampleRate)))
        return buffer
    }
}

extension AirPlayRouteManager: AVRoutePickerViewDelegate {
    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        self.isPresentingPicker = true
    }

    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        if routePickerView === fallbackPicker {
            // Asynchronously, so AppKit finishes tearing the picker down first.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fallbackPicker === routePickerView else { return }
                self.fallbackWindow?.orderOut(nil)
                self.fallbackWindow = nil
                self.fallbackPicker = nil
            }
        }
        refreshActiveDevice()
        // Keep flag briefly active so any click that dismissed the picker does not simultaneously drop the panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isPresentingPicker = false
        }
    }
}
