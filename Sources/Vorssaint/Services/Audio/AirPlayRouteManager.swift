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
    /// Main thread. Static so the panel's dismissal check can read it
    /// without creating the manager, which loads the private routing stack:
    /// a Vorssaint without the mixer must not pay for AirPlay at all.
    private(set) static var isPresentingPicker = false

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
    private var routingContextID: String?
    /// The backup check, scheduled only while a stream is live.
    private var pollTimer: Timer?
    private var contextObservers: [NSObjectProtocol] = []
    /// Called on the main thread when the connection or speaker changes.
    private var onChange: (() -> Void)?

    private typealias MsgSendClass = @convention(c) (AnyClass, Selector) -> AnyObject?
    private typealias MsgSendObj = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias MsgSendObjReturn = @convention(c) (AnyObject, Selector) -> AnyObject?

    private let msgSendSym = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")

    private override init() {
        dispatchPrecondition(condition: .onQueue(.main))
        super.init()
        // The private routing objects exist on older systems too, but only on
        // macOS 27 was the shared context seen to stay apart from the Mac's
        // own route and the renderer seen to reach the speaker.
        let systemSupported: Bool
        if #available(macOS 27, *) { systemSupported = true } else { systemSupported = false }
        if systemSupported {
            dlopen("/System/Library/Frameworks/AVKit.framework/AVKit", RTLD_NOW)
            dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW)
            setupContext()
        }
        self.isAvailable = AirPlayAvailability.isAvailable(
            mixerSupported: systemSupported,
            hasContext: routingContext != nil,
            contextID: routingContextID,
            pickerCanBind: AVRoutePickerView.instancesRespond(to: sel_registerName("setOutputContextID:")),
            rendererCanBind: AVSampleBufferAudioRenderer.instancesRespond(to: sel_registerName("setOutputContext:")))
    }

    deinit {
        pollTimer?.invalidate()
    }

    /// Starts tracking the picked speaker while the mixer runs. Main thread.
    ///
    /// Nothing wakes up on a schedule for someone who never uses AirPlay: the
    /// context announces when its output devices change. Only while a stream
    /// is live does a slow check back that up, so a speaker that disappears
    /// without a notification still hands its apps back to the Mac.
    func activate(onChange: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.onChange = onChange
        Self.snapshotLock.lock()
        Self.snapshotIsListed = isAvailable
        Self.snapshotLock.unlock()
        guard isAvailable, let context = routingContext else { return }
        refreshActiveDevice()
        if contextObservers.isEmpty {
            contextObservers = ["AVOutputContextOutputDeviceDidChangeNotification",
                                "AVOutputContextOutputDevicesDidChangeNotification"].map { name in
                NotificationCenter.default.addObserver(forName: Notification.Name(name), object: context,
                                                       queue: .main) { [weak self] _ in
                    self?.refreshActiveDevice()
                }
            }
        }
        updateStreamCheck()
    }

    /// Stops tracking; the mixer no longer lists AirPlay. Main thread.
    func deactivate() {
        dispatchPrecondition(condition: .onQueue(.main))
        contextObservers.forEach(NotificationCenter.default.removeObserver)
        contextObservers = []
        pollTimer?.invalidate()
        pollTimer = nil
        onChange = nil
        Self.snapshotLock.lock()
        Self.snapshotIsListed = false
        Self.snapshotIsConnected = false
        Self.snapshotLock.unlock()
    }

    /// Only the default shared context: the system audio context is the route
    /// of the whole Mac, which a per-app route must never move.
    private func setupContext() {
        guard let cls = NSClassFromString("AVOutputContext"), let sym = msgSendSym else { return }
        let msgClass = unsafeBitCast(sym, to: MsgSendClass.self)
        let defaultShared = sel_registerName("defaultSharedOutputContext")
        // Only when this macOS still has it: sending a class method that is
        // gone raises instead of returning nil.
        guard class_getClassMethod(cls, defaultShared) != nil,
              let context = msgClass(cls, defaultShared) as? NSObject else { return }
        routingContext = context
        routingContextID = AirPlayPrivateAPI.string(context, "ID")
    }

    /// Creates an `AVRoutePickerView` bound to the routing context, or nil
    /// when it cannot be bound: an unbound picker works on the whole Mac's
    /// audio route, so it is never handed out.
    private func makeRoutePickerView() -> AVRoutePickerView? {
        guard isAvailable, let contextID = routingContextID, let sym = msgSendSym else { return nil }
        let picker = AVRoutePickerView()
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        let setCtxSel = sel_registerName("setOutputContextID:")
        guard picker.responds(to: setCtxSel) else { return nil }
        msgObj(picker, setCtxSel, contextID as AnyObject)
        picker.delegate = self
        return picker
    }

    private var fallbackWindow: NSWindow?
    /// The picker hosted in `fallbackWindow`; its delegate callback closes the window.
    private weak var fallbackPicker: AVRoutePickerView?
    /// Tells a picker that is presenting now from one whose late callbacks
    /// arrive after another took its place.
    private var pickerGeneration = 0

    /// Opens the system's speaker list at the pointer, where the choice that
    /// asked for it was made: an app's output menu in the panel, Settings or
    /// the island. A transparent window anchors it there.
    func presentPicker() {
        // Nothing to pick with, and no reason to create the anchor window.
        guard isAvailable else { return }
        closePickerWindow()

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
        // Over a full-screen app too, like the panel's own anchor.
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        if let picker = makeRoutePickerView() {
            picker.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            win.contentView?.addSubview(picker)
            win.orderFrontRegardless()
            self.fallbackWindow = win
            self.fallbackPicker = picker

            // A list left open this long, or one whose end was never reported,
            // still goes, and the panel stops treating clicks as the picker's.
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self, weak win] in
                guard let self, let win, self.fallbackWindow === win else { return }
                self.closePickerWindow()
            }

            if let button = findButton(in: picker) {
                button.performClick(nil)
            }
        }
    }

    private func closePickerWindow() {
        fallbackWindow?.orderOut(nil)
        fallbackWindow = nil
        fallbackPicker = nil
        pickerGeneration += 1
        Self.isPresentingPicker = false
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
        dispatchPrecondition(condition: .onQueue(.main))
        guard let context = routingContext, let sym = msgSendSym else { return }
        let msgObjReturn = unsafeBitCast(sym, to: MsgSendObjReturn.self)

        var name: String? = nil
        let outputDevicesSel = sel_registerName("outputDevices")
        if context.responds(to: outputDevicesSel),
           let devices = msgObjReturn(context, outputDevicesSel) as? [NSObject] {
            let names = devices.compactMap { dev -> String? in
                guard let n = AirPlayPrivateAPI.string(dev, "name"), !n.isEmpty, !n.hasPrefix("APEndpoint") else {
                    return nil
                }
                return n
            }
            if !names.isEmpty {
                // Sorted, so a group whose members come back in another order
                // is not reported as a new speaker.
                name = names.sorted().joined(separator: " + ")
            }
        }

        if name == nil {
            let outputDevSel = sel_registerName("outputDevice")
            if context.responds(to: outputDevSel),
               let dev = msgObjReturn(context, outputDevSel) as? NSObject,
               let n = AirPlayPrivateAPI.string(dev, "name"),
               !n.isEmpty, !n.hasPrefix("APEndpoint") {
                name = n
            }
        }

        let outputDevSel = sel_registerName("outputDevice")
        let hasDevice = context.responds(to: outputDevSel) && msgObjReturn(context, outputDevSel) != nil
        let connected = AirPlayAvailability.isConnected(hasDevice: hasDevice, speakerName: name,
                                                        failedSpeakerName: streamingFailedFor)

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
    private lazy var streams = AirPlayStreamRegistry(mixer: mixerSource)
    private let streamLock = NSLock()

    /// Adds one engine's stream to the mix. The engine owns the returned
    /// registration and ends it when it stops; nil when no renderer could be
    /// started. Each app is heard once, through its newest live engine, and
    /// an engine can only ever end its own registration.
    func addAudioStream(appID: String, buffer: AudioRingBuffer) -> AirPlayStreamRegistration? {
        streamLock.lock()
        defer { streamLock.unlock() }
        startRendererIfNeeded()
        guard airPlayRenderer != nil else { return nil }
        let registration = streams.register(appID: appID, buffer: buffer) { [weak self] token in
            self?.endAudioStream(token)
        }
        DispatchQueue.main.async { [weak self] in self?.updateStreamCheck() }
        return registration
    }

    /// Runs the backup check exactly while the mixer is active and a stream is
    /// live. Main thread; reads the live state when it runs, so updates that
    /// arrive out of order still settle on the right answer.
    private func updateStreamCheck() {
        dispatchPrecondition(condition: .onQueue(.main))
        streamLock.lock()
        let streaming = !streams.isEmpty
        streamLock.unlock()
        let wanted = streaming && onChange != nil && isAvailable
        if wanted, pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.refreshActiveDevice()
            }
        } else if !wanted, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    /// The speaker a renderer could not be started for. While it is still the
    /// picked one, AirPlay reports no connection: routed apps fall back to the
    /// Mac and show as unavailable instead of claiming AirPlay while playing
    /// locally, and builds stop being retried. Picking again clears it.
    private var streamingFailedFor: String?

    /// Main thread. A renderer already replaced reports nothing about the
    /// speaker the current one plays to.
    private func rendererFailed(_ renderer: AirPlayRenderer) {
        streamLock.lock()
        let current = airPlayRenderer === renderer
        streamLock.unlock()
        if current { reportStreamingFailure() }
    }

    /// Main thread: a build could not get a renderer.
    func reportStreamingFailure() {
        dispatchPrecondition(condition: .onQueue(.main))
        streamingFailedFor = cachedSpeakerName ?? ""
        refreshActiveDevice()
    }

    /// Makes sure a renderer is running before an engine taps its app, so a
    /// failure here never mutes the app or reads as a missing permission.
    func prepareToStream() -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        startRendererIfNeeded()
        return airPlayRenderer != nil
    }

    /// Stops a renderer that a failed build started and nobody uses.
    func stopIfIdle() {
        streamLock.lock()
        defer { streamLock.unlock() }
        if streams.isEmpty {
            stopRenderer()
        }
    }

    private func endAudioStream(_ token: Int) {
        streamLock.lock()
        defer { streamLock.unlock() }
        if streams.remove(token) {
            stopRenderer()
            DispatchQueue.main.async { [weak self] in self?.updateStreamCheck() }
        }
    }

    private func startRendererIfNeeded() {
        guard airPlayRenderer == nil else { return }
        guard let renderer = AirPlayRenderer(source: mixerSource, manager: self) else { return }
        // A renderer that fails or stops taking audio leaves the tapped apps
        // silent everywhere; reported like one that could not start, they
        // fall back to the Mac until the speaker is picked again.
        renderer.onFailure = { [weak self, weak renderer] in
            guard let self, let renderer else { return }
            self.rendererFailed(renderer)
        }
        renderer.start()
        self.airPlayRenderer = renderer
    }

    private func stopRenderer() {
        airPlayRenderer?.stop()
        airPlayRenderer = nil
    }
}

// MARK: - Private API access

/// Reads from the private routing objects without trusting that this macOS
/// still has the property: key-value coding raises for an unknown key, which
/// would take the app down on the next poll instead of hiding AirPlay.
enum AirPlayPrivateAPI {
    static func string(_ object: NSObject, _ key: String) -> String? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key) as? String
    }
}

// MARK: - Availability

/// AirPlay is offered only when every private piece it depends on is there.
/// Each one matters on its own: without the context id or the picker's
/// context setter the picker falls back to the whole Mac's route, and without
/// the renderer binding the stream would play on the Mac.
enum AirPlayAvailability {
    /// A speaker counts as connected when the context has one with a name,
    /// unless streaming to that very speaker just failed.
    static func isConnected(hasDevice: Bool, speakerName: String?, failedSpeakerName: String?) -> Bool {
        guard hasDevice, let speakerName else { return false }
        return speakerName != failedSpeakerName
    }

    static func isAvailable(mixerSupported: Bool, hasContext: Bool, contextID: String?,
                            pickerCanBind: Bool, rendererCanBind: Bool) -> Bool {
        mixerSupported && hasContext && !(contextID?.isEmpty ?? true) && pickerCanBind && rendererCanBind
    }
}

// MARK: - Stream registrations

/// Which engines currently feed the AirPlay mix. An app is heard once: its
/// lane plays the newest live registration for that app. A replacement engine
/// registers while it is still being built, before the old one is stopped, so
/// it takes the lane over at once instead of adding a second copy; ending a
/// registration removes only that registration, and if it was the one being
/// heard (a discarded build) the lane falls back to the previous live one.
final class AirPlayStreamRegistry: @unchecked Sendable {
    private struct Entry {
        let token: Int
        let buffer: AudioRingBuffer
    }

    private let mixer: MixingAudioSource
    private let lock = NSLock()
    private var nextToken = 0
    /// Per app, oldest first; the last entry is the audible one.
    private var lanes: [String: [Entry]] = [:]

    init(mixer: MixingAudioSource) {
        self.mixer = mixer
    }

    func register(appID: String, buffer: AudioRingBuffer,
                  onEnd: @escaping (Int) -> Void) -> AirPlayStreamRegistration {
        lock.lock()
        defer { lock.unlock() }
        nextToken += 1
        let token = nextToken
        lanes[appID, default: []].append(Entry(token: token, buffer: buffer))
        // The mixer is updated under the same lock, so its lanes always match
        // this bookkeeping even when registrations race. A buffer that becomes
        // audible starts at its newest audio, never at a backlog; the feed
        // queue skips there on the lane's first read, since only it reads rings.
        mixer.setBuffer(buffer, forKey: appID, startingAt: buffer.writePosition)
        return AirPlayStreamRegistration(token: token, onEnd: onEnd)
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lanes.isEmpty
    }

    /// Removes one registration; true when the mix has no lanes left.
    /// Removing a registration that is already gone changes nothing and
    /// reports false.
    func remove(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let appID = lanes.first(where: { $0.value.contains { $0.token == token } })?.key,
              var entries = lanes[appID],
              let index = entries.firstIndex(where: { $0.token == token }) else { return false }
        let wasAudible = index == entries.count - 1
        entries.remove(at: index)
        if let fallback = entries.last {
            lanes[appID] = entries
            if wasAudible {
                // Nobody read the fallback while it was hidden, so it is full
                // of old audio; playing that would delay the app for good. A
                // feed step may still be reading it right now, so the skip is
                // left to the lane's next read on the feed queue.
                mixer.setBuffer(fallback.buffer, forKey: appID, startingAt: fallback.buffer.writePosition)
            }
        } else {
            lanes.removeValue(forKey: appID)
            mixer.removeBuffer(forKey: appID)
        }
        return lanes.isEmpty
    }
}

/// One engine's place in the AirPlay mix. Ending it is idempotent, so a stop
/// followed by the stop in `deinit` cannot touch anyone else's stream.
final class AirPlayStreamRegistration: @unchecked Sendable {
    let token: Int
    private let lock = NSLock()
    private var onEnd: ((Int) -> Void)?

    init(token: Int, onEnd: @escaping (Int) -> Void) {
        self.token = token
        self.onEnd = onEnd
    }

    func end() {
        lock.lock()
        let pending = onEnd
        onEnd = nil
        lock.unlock()
        pending?(token)
    }
}

// MARK: - Feed scheduling

/// Runs a renderer's feed steps. All renderers share one serial queue, so two
/// of them never read the mixing source at once. `stop()` returns only after a
/// step that is already running has finished, and no step starts afterwards.
final class AirPlayFeedDriver: @unchecked Sendable {
    static let sharedQueue = DispatchQueue(label: "com.vorssaint.utils.airplay.render", qos: .userInitiated)
    private static let queueKey = DispatchSpecificKey<Void>()

    private let queue: DispatchQueue
    private let interval: DispatchTimeInterval
    private let timerLock = NSLock()
    private var timer: DispatchSourceTimer?
    /// Read and written on `queue` only.
    private var isActive = false

    init(queue: DispatchQueue = AirPlayFeedDriver.sharedQueue, interval: DispatchTimeInterval = .milliseconds(25)) {
        self.queue = queue
        self.interval = interval
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    func start(_ step: @escaping () -> Void) {
        queue.sync { isActive = true }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in
            guard let self, self.isActive else { return }
            step()
        }
        timerLock.lock()
        timer?.cancel()
        timer = source
        timerLock.unlock()
        source.resume()
    }

    func stop() {
        timerLock.lock()
        let source = timer
        timer = nil
        timerLock.unlock()
        source?.cancel()
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            // Called from a step itself: it finishes on return.
            isActive = false
        } else {
            // Waits for a running step; any step queued behind it sees the flag.
            queue.sync { isActive = false }
        }
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
    private let capacityFrames: Int
    private let storage: UnsafeMutablePointer<Float>
    /// [0] = next frame to read (consumer), [1] = next frame to write
    /// (producer), [2] = the bits of the current sample rate.
    private let positions: UnsafeMutablePointer<Int64>

    /// `startingFramePosition` exists for tests that exercise long-running streams.
    init(sampleRate: Double = 44_100, capacityFrames: Int = 1 << 16, startingFramePosition: Int64 = 0) {
        var cap = 1
        while cap < capacityFrames { cap <<= 1 }
        self.capacityFrames = cap
        storage = .allocate(capacity: cap * 2)
        storage.initialize(repeating: 0, count: cap * 2)
        positions = .allocate(capacity: 3)
        positions.initialize(repeating: startingFramePosition, count: 2)
        (positions + 2).initialize(to: Int64(bitPattern: (sampleRate > 0 ? sampleRate : 44_100).bitPattern))
    }

    /// The rate the producer writes at. The device can renegotiate it under a
    /// running tap (a headset switching to a call), so the reader looks it up
    /// on every read instead of keeping the value from build time.
    var sampleRate: Double {
        get { Double(bitPattern: UInt64(bitPattern: OSAtomicAdd64Barrier(0, positions + 2))) }
        set {
            guard newValue > 0, newValue.isFinite else { return }
            let replacement = Int64(bitPattern: newValue.bitPattern)
            while true {
                let current = OSAtomicAdd64Barrier(0, positions + 2)
                if OSAtomicCompareAndSwap64Barrier(current, replacement, positions + 2) { return }
            }
        }
    }

    deinit {
        storage.deallocate()
        positions.deallocate()
    }

    private var head: UnsafeMutablePointer<Int64> { positions }
    private var tail: UnsafeMutablePointer<Int64> { positions + 1 }

    /// Producer: Called from Core Audio realtime IO thread. Zero allocations, no locks.
    /// `frames` holds `channels` interleaved samples per frame: a mono source
    /// plays on both sides, and only the first two of more channels are kept.
    func write(frames: UnsafePointer<Float>, frameCount: Int, channels: Int = 2, gain: Float) {
        guard channels > 0 else { return }
        let t = OSAtomicAdd64Barrier(0, tail)
        let h = OSAtomicAdd64Barrier(0, head)
        let used = min(capacityFrames, max(0, Int(t - h)))
        let count = min(frameCount, capacityFrames - used)
        guard count > 0 else { return }

        let mask = Int64(capacityFrames - 1)
        let right = min(1, channels - 1)
        for i in 0..<count {
            let slot = Int((t + Int64(i)) & mask) * 2
            let frame = i * channels
            storage[slot] = frames[frame] * gain
            storage[slot + 1] = frames[frame + right] * gain
        }
        _ = OSAtomicAdd64Barrier(Int64(count), tail)
    }

    /// How far the producer has written. Safe to read from any thread: it
    /// only records a position for the consumer to skip to later.
    var writePosition: Int64 { OSAtomicAdd64Barrier(0, tail) }

    /// Consumer (the feed queue) only: frames written and not yet read.
    var availableFrames: Int {
        let h = OSAtomicAdd64Barrier(0, head)
        let t = OSAtomicAdd64Barrier(0, tail)
        return max(0, Int(t - h))
    }

    /// Consumer (the feed queue) only: moves the read position forward to
    /// `position`, never past what has been written, never backwards.
    func skip(to position: Int64) {
        let h = OSAtomicAdd64Barrier(0, head)
        let target = min(position, OSAtomicAdd64Barrier(0, tail))
        if target > h { _ = OSAtomicAdd64Barrier(target - h, head) }
    }

    /// Consumer: Called from the AirPlay streaming feed queue.
    @discardableResult
    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let h = OSAtomicAdd64Barrier(0, head)
        let t = OSAtomicAdd64Barrier(0, tail)
        let count = min(frameCount, max(0, Int(t - h)))

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

    /// Where this lane starts reading, applied by its first read on the feed
    /// queue. Recorded when the lane is (re)assigned: a buffer that was not
    /// heard kept filling, and that backlog must not play.
    private var startPosition: Int64?

    /// Seconds of unread audio a lane may hold before it catches up. Normal
    /// feeding keeps well under this (about one 2048-frame chunk).
    static let maximumBacklog = 0.2
    /// Seconds kept when it catches up, so the next reads do not run dry.
    static let keptBacklog = 0.05

    init(buffer: AudioRingBuffer, startingAt position: Int64? = nil) {
        self.buffer = buffer
        self.startPosition = position
    }

    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) {
        if let position = startPosition {
            startPosition = nil
            buffer.skip(to: position)
        }
        // While the renderer is not taking audio (the speaker connecting,
        // being switched), the tap keeps writing. Played back later at the
        // same rate, that backlog would stay as delay for the rest of the
        // session, so anything past a small margin is skipped.
        let rate = buffer.sampleRate
        if buffer.availableFrames > Int(rate * Self.maximumBacklog) {
            buffer.skip(to: buffer.writePosition - Int64(rate * Self.keptBacklog))
            carry.removeAll(keepingCapacity: true)
            phase = 0
        }
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

    /// `startingAt` is where the lane begins reading (see `LinearResampler`).
    /// Only the feed queue reads a ring, so only it may move the read
    /// position; this just hands it the position to move to.
    func setBuffer(_ buffer: AudioRingBuffer, forKey key: String, startingAt position: Int64? = nil) {
        lock.lock()
        resamplers[key] = LinearResampler(buffer: buffer, startingAt: position)
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

/// Tells when a renderer has stopped taking audio for good: it failed, it
/// never started playing, or, once playback got going, it has not been ready
/// for more far longer than a hiccup lasts. A speaker that is slow to connect
/// gets far longer than one that stops mid-stream. Reports once.
struct AirPlayRendererWatch {
    static let stallLimit: TimeInterval = 10
    static let startLimit: TimeInterval = 60
    private var startedAt: TimeInterval?
    private var lastReady: TimeInterval?
    private var hasPlayed = false
    private var reported = false

    mutating func shouldReport(failed: Bool, ready: Bool, playing: Bool, now: TimeInterval) -> Bool {
        guard !reported else { return false }
        if startedAt == nil { startedAt = now }
        hasPlayed = hasPlayed || playing
        if ready || !playing || lastReady == nil { lastReady = now }
        let stalled = now - (lastReady ?? now) > Self.stallLimit
        let neverStarted = !hasPlayed && now - (startedAt ?? now) > Self.startLimit
        guard failed || stalled || neverStarted else { return false }
        reported = true
        return true
    }
}

/// Streams 44.1 kHz Int16 stereo audio to the selected AirPlay device via AVSampleBufferAudioRenderer.
final class AirPlayRenderer: @unchecked Sendable {
    private let source: MixingAudioSource
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let feed = AirPlayFeedDriver()
    /// Set before `start()`; called on the main thread, once.
    var onFailure: (() -> Void)?
    /// Feed queue only.
    private var watch = AirPlayRendererWatch()

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

    func start() {
        guard !started else { return }
        started = true
        nextPTS = CMTime.zero

        synchronizer.setRate(1.0, time: .zero)
        feed.start { [weak self] in
            self?.provide()
        }
    }

    /// Returns only once no feed step is running or can start again, so a
    /// replacement renderer never reads the shared mix at the same time.
    func stop() {
        guard started else { return }
        started = false
        feed.stop()
        renderer.flush()
        synchronizer.rate = 0
    }

    deinit { feed.stop() }

    private let targetLookahead = 0.75

    private func provide() {
        if watch.shouldReport(failed: renderer.status == .failed, ready: renderer.isReadyForMoreMediaData,
                              playing: CMTimeGetSeconds(synchronizer.currentTime()) > 0.1,
                              now: ProcessInfo.processInfo.systemUptime) {
            let failure = onFailure
            DispatchQueue.main.async { failure?() }
        }
        // A feed that fell behind the playback clock would enqueue late
        // chunks back to back; restart the timeline just ahead of it instead.
        let now = synchronizer.currentTime()
        if CMTimeCompare(nextPTS, now) < 0 {
            nextPTS = CMTimeAdd(now, CMTime(value: CMTimeValue(sampleRate * 0.05), timescale: CMTimeScale(sampleRate)))
        }
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
        // Picking again is a fresh try at streaming.
        streamingFailedFor = nil
        pickerGeneration += 1
        Self.isPresentingPicker = true
    }

    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        let generation = pickerGeneration
        // A picker already replaced, its window gone, leaves the flag to the
        // one presenting now.
        let isCurrent = routePickerView === fallbackPicker
        if isCurrent {
            // Asynchronously, so AppKit finishes tearing the picker down first.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fallbackPicker === routePickerView else { return }
                self.fallbackWindow?.orderOut(nil)
                self.fallbackWindow = nil
                self.fallbackPicker = nil
            }
        }
        refreshActiveDevice()
        // Choosing a speaker completes about a second after the picker closes.
        // The context's notifications normally report it; a few bounded checks
        // cover a connection that finishes without one. Only after the picker
        // was used, so nothing runs while AirPlay sits unused.
        for delay in [1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshActiveDevice()
            }
        }
        // Stays set a moment, so the click that closed the list does not also
        // close the panel. A list opened again meanwhile keeps it set.
        guard isCurrent else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.pickerGeneration == generation else { return }
            Self.isPresentingPicker = false
        }
    }
}
