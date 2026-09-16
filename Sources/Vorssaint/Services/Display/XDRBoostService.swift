// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Metal
import QuartzCore

/// Service managing hardware-level Extended Dynamic Range (EDR / XDR) peak brightness
/// boost on Liquid Retina XDR and external HDR/EDR displays.
///
/// Operates by creating an active 1x1 EDR CAMetalLayer that signals WindowServer
/// to unleash full panel headroom (up to 1600 nits), while simultaneously applying
/// hardware-level gamma transfer scaling via CGSetDisplayTransferByTable.
@MainActor
public final class XDRBoostService: ObservableObject {
    public static let shared = XDRBoostService()

    nonisolated public static let minBoost: Double = 1.0
    nonisolated public static let maxBoost: Double = 2.0
    nonisolated public static let defaultBoost: Double = 1.5

    @Published public private(set) var isBoostEnabled: [CGDirectDisplayID: Bool] = [:]
    @Published public private(set) var boostMultiplier: [CGDirectDisplayID: Double] = [:]

    private var activePrimers: [CGDirectDisplayID: EDRPrimer] = [:]
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        installObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
            disableAll()
        }
    }

    // MARK: - Hardware Query

    public func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return num.uint32Value == displayID
            }
            return false
        }
    }

    public func isEDRSupported(for displayID: CGDirectDisplayID) -> Bool {
        guard let s = screen(for: displayID) else { return false }
        return s.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05
    }

    public func maximumHeadroom(for displayID: CGDirectDisplayID) -> Double {
        guard let s = screen(for: displayID) else { return 1.0 }
        return max(1.0, Double(s.maximumPotentialExtendedDynamicRangeColorComponentValue))
    }

    public func currentMultiplier(for displayID: CGDirectDisplayID) -> Double {
        boostMultiplier[displayID] ?? Self.defaultBoost
    }

    public func isEnabled(for displayID: CGDirectDisplayID) -> Bool {
        isBoostEnabled[displayID] ?? false
    }

    // MARK: - Control

    public func toggleBoost(for displayID: CGDirectDisplayID) {
        let current = isEnabled(for: displayID)
        setEDRBoost(displayID: displayID, enabled: !current)
    }

    public func setEDRBoost(displayID: CGDirectDisplayID, enabled: Bool, multiplier: Double? = nil, animated: Bool = true) {
        let mult = multiplier ?? currentMultiplier(for: displayID)
        let clamped = min(Self.maxBoost, max(Self.minBoost, mult))

        if !enabled || clamped <= 1.001 {
            isBoostEnabled[displayID] = false
            if let existing = activePrimers.removeValue(forKey: displayID) {
                existing.stop()
            }
            Self.restoreDefault(for: displayID)
            return
        }

        isBoostEnabled[displayID] = true
        boostMultiplier[displayID] = clamped

        if let existing = activePrimers[displayID] {
            existing.updateMultiplier(clamped, animated: animated)
        } else {
            if let primer = EDRPrimer(displayID: displayID, initialMultiplier: clamped, animated: animated) {
                activePrimers[displayID] = primer
            } else {
                Self.applyGammaRamp(boost: clamped, for: displayID)
            }
        }
    }

    public func setMultiplier(_ multiplier: Double, for displayID: CGDirectDisplayID, animated: Bool = false) {
        let clamped = min(Self.maxBoost, max(Self.minBoost, multiplier))
        boostMultiplier[displayID] = clamped
        if isEnabled(for: displayID) {
            setEDRBoost(displayID: displayID, enabled: true, multiplier: clamped, animated: animated)
        }
    }

    public func disableAll() {
        for primer in activePrimers.values {
            primer.stop()
        }
        activePrimers.removeAll()
        isBoostEnabled.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Hardware Gamma Transfer

    @discardableResult
    nonisolated public static func applyGammaRamp(boost: Double, for displayID: CGDirectDisplayID) -> Bool {
        if boost <= 1.001 {
            return restoreDefault(for: displayID)
        }

        let sampleCount = 256
        let scale = Float(min(maxBoost, max(minBoost, boost)))

        var red = [Float](repeating: 0, count: sampleCount)
        var green = [Float](repeating: 0, count: sampleCount)
        var blue = [Float](repeating: 0, count: sampleCount)

        let maxIdx = Float(sampleCount - 1)
        for i in 0..<sampleCount {
            let normalized = Float(i) / maxIdx
            let val = normalized * scale
            red[i] = val
            green[i] = val
            blue[i] = val
        }

        let err = CGSetDisplayTransferByTable(displayID, UInt32(sampleCount), &red, &green, &blue)
        return err == .success
    }

    @discardableResult
    nonisolated public static func restoreDefault(for displayID: CGDirectDisplayID) -> Bool {
        CGDisplayRestoreColorSyncSettings()
        return true
    }

    // MARK: - Lifecycle Observers

    private func installObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleSleep()
                }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWake()
                }
            },
        ]
    }

    private func removeObservers() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers = []
    }

    private func handleSleep() {
        for primer in activePrimers.values {
            primer.pause()
        }
        CGDisplayRestoreColorSyncSettings()
    }

    private func handleWake() {
        for (displayID, enabled) in isBoostEnabled where enabled {
            let mult = boostMultiplier[displayID] ?? Self.defaultBoost
            if let primer = activePrimers[displayID] {
                primer.resume(multiplier: mult)
            } else {
                setEDRBoost(displayID: displayID, enabled: true, multiplier: mult, animated: true)
            }
        }
    }

    private func handleScreenChange() {
        let activeIDs = Set(NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        })
        for (displayID, primer) in activePrimers where !activeIDs.contains(displayID) {
            primer.stop()
            activePrimers.removeValue(forKey: displayID)
            isBoostEnabled.removeValue(forKey: displayID)
        }
    }

    // MARK: - EDR Primer Window

    @MainActor
    public final class EDRPrimer {
        private var window: NSWindow?
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var metalLayer: CAMetalLayer?
        public private(set) var currentMultiplier: Double = 1.0
        private var fadeTimer: Timer?
        private var heartbeatTimer: Timer?
        public let displayID: CGDirectDisplayID

        public init?(displayID: CGDirectDisplayID, initialMultiplier: Double = 1.0, animated: Bool = true) {
            guard let screen = XDRBoostService.shared.screen(for: displayID),
                  let dev = MTLCreateSystemDefaultDevice(),
                  let queue = dev.makeCommandQueue() else {
                return nil
            }
            self.displayID = displayID
            self.device = dev
            self.commandQueue = queue

            let frame = NSRect(x: screen.frame.maxX - 1, y: screen.frame.minY, width: 1, height: 1)
            let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.isReleasedWhenClosed = false
            win.animationBehavior = .none
            win.sharingType = .none
            win.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .canJoinAllApplications, .canJoinAllSpaces, .stationary]

            let metal = CAMetalLayer()
            metal.device = dev
            metal.pixelFormat = .rgba16Float
            metal.wantsExtendedDynamicRangeContent = true
            metal.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            metal.drawableSize = CGSize(width: 1, height: 1)
            metal.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

            let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            view.wantsLayer = true
            view.layer = metal
            win.contentView = view

            self.window = win
            self.metalLayer = metal
            win.orderFrontRegardless()

            let clamped = min(XDRBoostService.maxBoost, max(XDRBoostService.minBoost, initialMultiplier))
            if animated && clamped > 1.0 {
                self.currentMultiplier = 1.0
                renderPrimer(multiplier: 1.0)
                fadeIn(to: clamped, duration: 0.25)
            } else {
                self.currentMultiplier = clamped
                renderPrimer(multiplier: clamped)
                XDRBoostService.applyGammaRamp(boost: clamped, for: displayID)
            }
            startHeartbeat()
        }

        public func renderPrimer(multiplier: Double = 2.0) {
            guard let metal = metalLayer,
                  let drawable = metal.nextDrawable(),
                  let queue = commandQueue else { return }

            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = drawable.texture
            passDesc.colorAttachments[0].loadAction = .clear
            let val = Float(multiplier)
            passDesc.colorAttachments[0].clearColor = MTLClearColor(red: Double(val), green: Double(val), blue: Double(val), alpha: 1.0)
            passDesc.colorAttachments[0].storeAction = .store

            guard let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
            self.currentMultiplier = multiplier
        }

        private func startHeartbeat() {
            guard heartbeatTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.presentHeartbeat()
                }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            self.heartbeatTimer = timer
        }

        private func stopHeartbeat() {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
        }

        private func presentHeartbeat() {
            guard let metal = metalLayer,
                  let drawable = metal.nextDrawable(),
                  let queue = commandQueue else { return }
            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = drawable.texture
            passDesc.colorAttachments[0].loadAction = .clear
            passDesc.colorAttachments[0].storeAction = .store
            let val = Float(currentMultiplier)
            passDesc.colorAttachments[0].clearColor = MTLClearColor(red: Double(val), green: Double(val), blue: Double(val), alpha: 1.0)
            guard let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }

        public func fadeIn(to targetMultiplier: Double, duration: TimeInterval = 0.25, completion: (() -> Void)? = nil) {
            fadeTimer?.invalidate()
            fadeTimer = nil

            let startMultiplier = currentMultiplier
            let target = min(XDRBoostService.maxBoost, max(XDRBoostService.minBoost, targetMultiplier))
            let startTime = CACurrentMediaTime()

            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
                MainActor.assumeIsolated {
                    guard let self = self else {
                        t.invalidate()
                        return
                    }
                    let elapsed = CACurrentMediaTime() - startTime
                    let progress = min(1.0, elapsed / max(0.01, duration))
                    let eased = sin(progress * .pi / 2.0)
                    let current = startMultiplier + (target - startMultiplier) * eased
                    self.renderPrimer(multiplier: current)
                    XDRBoostService.applyGammaRamp(boost: current, for: self.displayID)

                    if progress >= 1.0 {
                        t.invalidate()
                        self.fadeTimer = nil
                        self.renderPrimer(multiplier: target)
                        XDRBoostService.applyGammaRamp(boost: target, for: self.displayID)
                        completion?()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.fadeTimer = timer
        }

        public func updateMultiplier(_ newMultiplier: Double, animated: Bool = false) {
            let clamped = min(XDRBoostService.maxBoost, max(XDRBoostService.minBoost, newMultiplier))
            if animated {
                fadeIn(to: clamped, duration: 0.15)
            } else {
                fadeTimer?.invalidate()
                fadeTimer = nil
                renderPrimer(multiplier: clamped)
                XDRBoostService.applyGammaRamp(boost: clamped, for: displayID)
            }
        }

        public func pause() {
            stopHeartbeat()
            fadeTimer?.invalidate()
            fadeTimer = nil
        }

        public func resume(multiplier: Double) {
            renderPrimer(multiplier: multiplier)
            XDRBoostService.applyGammaRamp(boost: multiplier, for: displayID)
            startHeartbeat()
        }

        public func stop() {
            stopHeartbeat()
            fadeTimer?.invalidate()
            fadeTimer = nil
            window?.orderOut(nil)
            window = nil
            metalLayer = nil
            commandQueue = nil
            device = nil
        }

        deinit {
            MainActor.assumeIsolated {
                stop()
            }
        }
    }
}
