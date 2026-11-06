// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreMedia
import Darwin
import ScreenCaptureKit

/// ScreenCaptureKit buffers are never mutated here; retaining them prevents
/// surface reuse until the consumer/GPU completes. Only ownership crosses queues.
struct RetainedFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    var texture: CVMetalTexture? = nil
}

@MainActor func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}

func residentMiB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
}

@MainActor final class ProbeSession: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    let options: ProbeOptions
    let metrics = ProbeMetrics()
    let captureQueue = DispatchQueue(label: "display-mirror-probe.capture", qos: .userInteractive)
    // Bound both queued main-thread work and retained capture surfaces. Drop
    // incoming frames when the GPU is busy instead of building latency.
    let slots = DispatchSemaphore(value: 2)
    var renderer: ProbeRenderer?
    var window: NSPanel?
    var metalLayer: CAMetalLayer?
    var stream: SCStream?
    var statusItem: NSStatusItem?
    var sampleTimer: Timer?
    var stopTimer: Timer?
    var signals: [DispatchSourceSignal] = []
    var observers: [NSObjectProtocol] = []
    var stopping = false
    var startedAt = 0.0
    var lastTime = 0.0
    var lastCPU = 0.0
    var lastSnapshot = ProbeMetrics.Snapshot()
    var hasFrame = false
    var exitStatus: Int32 = 0

    init(options: ProbeOptions) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await start() }
    }

    func start() async {
        do {
            guard let id = options.displayID,
                  let screen = NSScreen.screens.first(where: { displayID($0) == id }),
                  CGDisplayIsBuiltin(id) == 0, id != CGMainDisplayID(),
                  CGDisplayIsInMirrorSet(id) == 0,
                  let displayMode = CGDisplayCopyDisplayMode(id) else {
                throw ProbeError.message("Select a connected, non-primary external display in extended-desktop mode")
            }
            guard CGPreflightScreenCaptureAccess() else {
                CGRequestScreenCaptureAccess()
                throw ProbeError.message("Grant Screen Recording to Display Mirror Probe (or its Terminal host), then run again")
            }
            let width = options.width ?? displayMode.pixelWidth
            guard width <= displayMode.pixelWidth, width <= 4096 else {
                throw ProbeError.message("Capture width exceeds the source resolution or the probe's 4096-pixel limit")
            }
            let height = Int((Double(width) * Double(displayMode.pixelHeight)
                              / Double(displayMode.pixelWidth)).rounded())
            guard height > 0, height <= 4096 else { throw ProbeError.message("Unsupported capture height") }

            let renderer = try ProbeRenderer()
            self.renderer = renderer
            let layer = CAMetalLayer()
            layer.device = renderer.device
            layer.pixelFormat = .bgra8Unorm
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.framebufferOnly = true
            layer.maximumDrawableCount = 2
            layer.allowsNextDrawableTimeout = true
            layer.displaySyncEnabled = true
            layer.drawableSize = CGSize(width: displayMode.pixelWidth, height: displayMode.pixelHeight)
            layer.frame = CGRect(origin: .zero, size: screen.frame.size)
            metalLayer = layer

            // A tiny temporary window makes this application discoverable to
            // ScreenCaptureKit BEFORE the full-size output is made visible.
            let window = NSPanel(contentRect: NSRect(origin: screen.frame.origin, size: CGSize(width: 2, height: 2)),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.backgroundColor = .black
            window.animationBehavior = .none
            window.orderFrontRegardless()
            self.window = window

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == id }),
                  let ownApp = content.applications.first(where: { $0.processID == getpid() }) else {
                throw ProbeError.message("Could not identify our capture exclusion; refusing feedback-prone capture")
            }
            window.orderOut(nil)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer = layer
            window.contentView = view

            let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = width
            configuration.height = height
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
            configuration.queueDepth = 3
            configuration.capturesAudio = false
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.captureResolution = .best
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            self.stream = stream
            installStopControls()
            print("# mode=\(options.mode.rawValue), display=\(id), source=\(displayMode.pixelWidth)x\(displayMode.pixelHeight), capture=\(width)x\(height), requested_fps=\(options.fps), seconds=\(options.seconds)")
            print("# \(ProcessInfo.processInfo.operatingSystemVersionString); GPU=\(renderer.device.name); CPU percent is this process only (100 = one core)")
            print("# GPU time is this render command only. callback_to_submit excludes capture latency and display scanout. No cursor mirroring.")
            startedAt = CACurrentMediaTime()
            lastTime = startedAt
            lastCPU = cpuSeconds()
            print("elapsed_s,complete_fps,submitted_fps,busy_or_drawable_drops,cpu_percent,resident_mib,gpu_ms_per_completed_frame,callback_to_submit_ms")
            try await stream.startCapture()
            guard !stopping else { try? await stream.stopCapture(); return }
            sampleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            stopTimer = Timer.scheduledTimer(withTimeInterval: Double(options.seconds), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: "time limit") }
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: "display configuration changed") }
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: "system sleep") }
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                                                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: "session inactive") }
            })
        } catch {
            stop(reason: String(describing: error), failure: true)
        }
    }

    func installStopControls() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Mirror Probe"
        let menu = NSMenu()
        let stopItem = NSMenuItem(title: "Stop experiment", action: #selector(stopFromMenu), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        item.menu = menu
        statusItem = item
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in self?.stop(reason: "signal") }
            source.resume()
            signals.append(source)
        }
    }

    @objc func stopFromMenu() { stop(reason: "menu") }

    func sample() {
        let now = CACurrentMediaTime()
        let cpu = cpuSeconds()
        let value = metrics.snapshot()
        let duration = max(0.001, now - lastTime)
        let completed = value.finished - lastSnapshot.finished
        let submitted = value.submitted - lastSnapshot.submitted
        // Missing measurements are empty CSV fields, never a false zero.
        let gpu = completed > 0 ? String(format: "%.3f", (value.gpuMilliseconds - lastSnapshot.gpuMilliseconds) / Double(completed)) : ""
        let delay = submitted > 0 ? String(format: "%.3f", (value.callbackToSubmitMilliseconds - lastSnapshot.callbackToSubmitMilliseconds) / Double(submitted)) : ""
        print(String(format: "%.2f,%.2f,%.2f,%d,%.2f,%.2f,%@,%@", now - startedAt,
                     Double(value.complete - lastSnapshot.complete) / duration,
                     Double(submitted) / duration, value.skipped - lastSnapshot.skipped,
                     100 * (cpu - lastCPU) / duration, residentMiB(), gpu, delay))
        lastTime = now; lastCPU = cpu; lastSnapshot = value
        if now - startedAt > 10, value.complete == 0 { stop(reason: "no complete frames received", failure: true) }
    }

    func stop(reason: String, failure: Bool = false) {
        guard !stopping else { return }
        stopping = true
        exitStatus = failure ? 1 : 0
        window?.orderOut(nil)
        sampleTimer?.invalidate()
        stopTimer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        print("# stopped: \(reason)")
        guard stream != nil else { exit(exitStatus) }
        // A wedged capture service must not keep the overlay/process around.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in exit(exitStatus) }
        Task {
            if let stream { try? await stream.stopCapture() }
            exit(exitStatus)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.stop(reason: error.localizedDescription, failure: true) }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        metrics.complete()
        guard options.mode != .capture else { return }
        guard slots.wait(timeout: .now()) == .success else { metrics.skip(); return }
        let arrival = CACurrentMediaTime()
        let frame = RetainedFrame(buffer: buffer)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.render(frame.buffer, arrival: arrival)
        }
    }

    func render(_ buffer: CVPixelBuffer, arrival: Double) {
        var committed = false
        defer { if !committed { slots.signal() } }
        guard !stopping, let renderer, let layer = metalLayer else { return }
        do {
            let (wrapper, source) = try renderer.texture(for: buffer)
            guard let drawable = layer.nextDrawable() else { metrics.skip(); return }
            let command = try renderer.encode(source: source, destination: drawable.texture,
                                               flipped: options.mode == .flipped)
            command.present(drawable)
            let frame = RetainedFrame(buffer: buffer, texture: wrapper)
            command.addCompletedHandler { [self, frame] completed in
                withExtendedLifetime(frame) {
                    if completed.status == .completed {
                        metrics.finish(gpuSeconds: completed.gpuEndTime - completed.gpuStartTime)
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.stopping, !self.hasFrame else { return }
                            self.hasFrame = true
                            self.window?.orderFrontRegardless()
                        }
                    } else {
                        DispatchQueue.main.async { [weak self] in self?.stop(reason: "GPU command failed", failure: true) }
                    }
                    slots.signal()
                }
            }
            metrics.submit(delay: CACurrentMediaTime() - arrival)
            committed = true
            command.commit()
        } catch {
            stop(reason: String(describing: error), failure: true)
        }
    }
}

func runSelftest() throws {
    let valid = try ProbeOptions.parse(["--display", "42", "--fps", "30", "--width", "3840", "--seconds", "10", "--mode", "plain"])
    guard valid.displayID == 42, valid.fps == 30, valid.width == 3840,
          valid.seconds == 10, valid.mode == .plain else { throw ProbeError.message("Option parsing failed") }
    for invalid in [[], ["--display"], ["--display", "0"], ["--display", "-1"],
                    ["--display", "42", "--fps", "0"], ["--display", "42", "--seconds", "601"],
                    ["--display", "42", "--width", "99999"], ["--display", "42", "--mode", "other"],
                    ["--display", "42", "--fps", "30", "--fps", "60"]] {
        var rejected = false
        do { _ = try ProbeOptions.parse(invalid) } catch { rejected = true }
        guard rejected else { throw ProbeError.message("Unsafe options accepted: \(invalid)") }
    }
    let metrics = ProbeMetrics()
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in metrics.complete(); metrics.skip() }
    guard metrics.snapshot().complete == 1000, metrics.snapshot().skipped == 1000 else {
        throw ProbeError.message("Concurrent metrics lost updates")
    }
    try ProbeRenderer.selftest()
    print("SELFTEST OK: options, concurrent counters, CoreVideo texture mapping, actual Metal identity and horizontal flip pixels")
}

setbuf(stdout, nil)
MainActor.assumeIsolated {
do {
    let options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
    if options.help { print(ProbeOptions.usage) }
    else if options.selftest { try runSelftest() }
    else if options.list {
        for screen in NSScreen.screens {
            let id = displayID(screen)
            let mode = CGDisplayCopyDisplayMode(id)
            print("\(id): \(screen.localizedName), \(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0), built_in=\(CGDisplayIsBuiltin(id)), primary=\(id == CGMainDisplayID()), mirrored=\(CGDisplayIsInMirrorSet(id))")
        }
        if NSScreen.screens.isEmpty { print("No displays visible in this session") }
    } else {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let session = ProbeSession(options: options)
        app.delegate = session
        withExtendedLifetime(session) { app.run() }
        exit(session.exitStatus)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n\(ProbeOptions.usage)\n".utf8))
    exit(1)
}
}
