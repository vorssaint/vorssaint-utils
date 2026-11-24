// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

/// Passively observes display brightness and keyboard backlight adjustments from hardware keys,
/// Control Center, and the Touch Bar so the island perimeter bars respond smoothly without
/// requiring Accessibility event-tap takeover.
final class NotchBrightnessObserver: ObservableObject {
    static let shared = NotchBrightnessObserver()

    let brightnessChanged = PassthroughSubject<Double, Never>()
    let keyboardLightKeyPressed = PassthroughSubject<Void, Never>()

    private var running = false
    private var screensAsleep = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var brightnessBurstWorks: [DispatchWorkItem] = []

    private var brightnessDetector = NotchBrightnessChangeDetector()
    private var lastBrightnessPollAt: TimeInterval = 0

    private init() {}

    func syncWithPreferences() {
        if NotchSupport.isEnabled() && NotchLightsSupport.isEnabled() {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        screensAsleep = false

        let now = ProcessInfo.processInfo.systemUptime
        if let initialBrightness = readSystemBrightness() {
            _ = brightnessDetector.observe(level: initialBrightness, at: now)
        }
        lastBrightnessPollAt = now

        let mask: NSEvent.EventTypeMask = [.keyDown, .systemDefined]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.screensAsleep = false
                if let level = self.readSystemBrightness() {
                    self.brightnessDetector.noteHandled(level: level, at: ProcessInfo.processInfo.systemUptime)
                }
            }
        ]

        let timer = Timer(timeInterval: 0.24, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        guard running else { return }
        running = false
        pollTimer?.invalidate()
        pollTimer = nil
        cancelBrightnessBursts()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers = []
        screensAsleep = false
        brightnessDetector = NotchBrightnessChangeDetector()
    }

    /// Marks an adjustment already performed by `BrightnessService` so polling does not re-fire it.
    func noteObservedBrightness(_ level: Double) {
        let work = { [weak self] in
            guard let self, self.running else { return }
            self.brightnessDetector.noteHandled(level: level, at: ProcessInfo.processInfo.systemUptime)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func handle(_ event: NSEvent) {
        guard running else { return }
        switch event.type {
        case .keyDown:
            if BrightnessSupport.isBrightnessKeyCode(Int(event.keyCode)),
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                noteBrightnessKeyPressed()
            }
        case .systemDefined:
            if let press = BrightnessSupport.brightnessKeyEvent(subtype: Int(event.subtype.rawValue), data1: event.data1),
               press.isKeyDown {
                noteBrightnessKeyPressed()
            } else if BrightnessSupport.isKeyboardLightPress(subtype: Int(event.subtype.rawValue), data1: event.data1) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, self.running else { return }
                    self.keyboardLightKeyPressed.send()
                }
            }
        default:
            break
        }
    }

    private func timerTick() {
        guard running, !screensAsleep else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastBrightnessPollAt >= 0.22 {
            lastBrightnessPollAt = now
            sampleSystemBrightness(forceBoundaryOnKey: false)
        }
    }

    private func noteBrightnessKeyPressed() {
        let now = ProcessInfo.processInfo.systemUptime
        brightnessDetector.noteKeyPress(at: now)
        cancelBrightnessBursts()
        let offsets: [(TimeInterval, Bool)] = [(0.02, false), (0.08, false), (0.18, true)]
        brightnessBurstWorks = offsets.map { delay, forceBoundary in
            let work = DispatchWorkItem { [weak self] in
                self?.sampleSystemBrightness(forceBoundaryOnKey: forceBoundary)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func cancelBrightnessBursts() {
        for work in brightnessBurstWorks { work.cancel() }
        brightnessBurstWorks.removeAll()
    }

    private func sampleSystemBrightness(forceBoundaryOnKey: Bool) {
        guard running, !screensAsleep, let level = readSystemBrightness() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let detected = brightnessDetector.observe(level: level, at: now, forceBoundaryOnKey: forceBoundaryOnKey) {
            brightnessChanged.send(detected)
        }
    }

    private func readSystemBrightness() -> Double? {
        guard let read = BrightnessBridge.getBrightness else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        let target: CGDirectDisplayID
        if CGGetOnlineDisplayList(8, &ids, &count) == .success, count > 0,
           let builtIn = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            target = builtIn
        } else {
            target = CGMainDisplayID()
        }
        guard target != kCGNullDirectDisplay, CGDisplayIsAsleep(target) == 0 else { return nil }
        var value: Float = -1
        guard read(target, &value) == 0, value.isFinite, value >= 0, value <= 1 else { return nil }
        return Double(value)
    }
}
