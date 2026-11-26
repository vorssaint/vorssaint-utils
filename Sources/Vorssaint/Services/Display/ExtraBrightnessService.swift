// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Metal
import QuartzCore

/// Pushes the built-in XDR display past its regular maximum brightness by
/// using the panel's HDR headroom for everything on screen.
///
/// Mechanism: a one-pixel extended-range Metal trigger window in the bottom
/// right corner engages and sustains macOS's EDR headroom, while the display's
/// hardware transfer (gamma) table is scaled above 1.0 via
/// `CGSetDisplayTransferByTable`. Because the transfer table runs in the
/// display pipeline after WindowServer compositing, window switches, Space
/// transitions, and Mission Control never drop the boost (#2883), and there
/// are no full-screen overlay windows to intercept screenshots or cover
/// Mission Control thumbnails.
///
/// Rendering and gamma table calls use public APIs; trigger placement uses the
/// island's runtime-resolved private Space helper, with regular all-Space
/// placement as a fallback. macOS controls the panel: thermal or power
/// pressure can shrink the headroom at any time and the poll adapts.
/// CoreGraphics automatically reverts a process's transfer tables on exit, and
/// `stop()` restores only the built-in display's captured baseline so external
/// display gamma dimming in `BrightnessService` is never disturbed.
/// No windows, timers or observers exist while the feature is off (except
/// briefly while retrying a failed baseline restore until the display becomes
/// writable again).
final class ExtraBrightnessService: ObservableObject {
    static let shared = ExtraBrightnessService()

    /// A built-in display with EDR headroom exists (feature can work here).
    @Published private(set) var supported = false
    /// The boost is currently confirmed active on the panel.
    @Published private(set) var boosting = false

    private struct GammaBaseline {
        let displayID: CGDirectDisplayID
        let table: ExtraBrightnessSupport.GammaTable
    }

    private struct PendingGammaRestore {
        let baseline: GammaBaseline
        let appliedFactor: Double
    }

    /// A one-pixel corner window that presents an extended-range Metal pixel
    /// on every poll tick so macOS engages and sustains the panel's EDR
    /// headroom. Without continuous extended-range presents, macOS revokes the
    /// headroom about a second after the last present and clamps the transfer
    /// table back to SDR.
    private var triggerWindow: NSWindow?
    private var triggerLayer: CAMetalLayer?
    /// A Space of the trigger's own (the island's helper). Keeping the trigger
    /// in its own Space lets it persist across desktop and fullscreen Space
    /// switches without rebuilding. Nil when the symbols are missing: the
    /// trigger then stays on every desktop via `collectionBehavior`.
    private var overlaySpace: NotchOverlaySpace?
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var colorSpaceObserver: NSObjectProtocol?
    private var windowProfileObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Cancellable backoff retry used when a baseline restore failed and the
    /// feature is currently off (`pollTimer == nil`) while the display is
    /// awake.
    private var pendingRestoreRetryWorkItem: DispatchWorkItem?
    private var pendingRestoreRetryAttempt = 0
    /// While the screens sleep the compositor stops recycling drawables and
    /// nextDrawable would stall the main thread, so presents pause and a
    /// fresh render happens on wake.
    private var screensAsleep = false
    /// The factor targeted on screen, moved one smoothing step per tick
    /// toward the instantaneous target (see the ramp constants in
    /// ExtraBrightnessSupport): the grant wobbles while HDR video plays and
    /// applying it raw flashed the whole screen in visible steps.
    private var renderedFactor = 1.0
    /// The factor last written to the built-in display's transfer table.
    private var appliedGammaFactor = 1.0
    /// Whether the live transfer table is currently confirmed boosted above
    /// baseline. Tracked separately from `appliedGammaFactor` so a confirmed
    /// reset updates `boosting` immediately even if a repair write fails.
    private var observedBoosting = false
    /// Untouched native-capacity SDR gamma baseline captured before applying
    /// any boost to the built-in display. Restored directly for this display
    /// only (never via `CGDisplayRestoreColorSyncSettings`, which would wipe
    /// external-display software dimming managed by `BrightnessService`).
    private var gammaBaseline: GammaBaseline?
    /// Retained whenever a baseline restore fails (for example during display
    /// sleep or clamshell). Retried as soon as the original display becomes
    /// writable again—even while Extra Brightness is off—and blocks baseline
    /// recapture until restoration succeeds or readback proves the old boost
    /// is gone.
    private var pendingGammaRestore: PendingGammaRestore?
    /// Set when the built-in display's ColorSync profile changes so the next
    /// clean readback adopts the new profile's baseline instead of overwriting
    /// it with the old curve.
    private var profileChangePending = false
    private var lastScreenColorSpace: NSColorSpace?
    /// The display the trigger was built for. Fullscreen video makes the same
    /// panel re-announce itself (refresh rate and EDR mode changes); those
    /// must reuse the live trigger, not rebuild it.
    private var triggerDisplayID: UInt32?

    private init() {}

    func syncWithPreferences() {
        refreshSupported()
        let enabled = AppFeature.extraBrightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
        if enabled, supported {
            start()
        } else if enabled {
            installObserver()
            stop(preservingObservers: true)
        } else {
            stop()
        }
    }

    /// Re-applies a level change immediately instead of waiting for the poll.
    /// The slider is user feedback, so it bypasses the smoothing ramp.
    func levelDidChange() {
        guard pollTimer != nil else { return }
        renderIfNeeded(immediate: true)
    }

    // MARK: - Detection

    /// The Mac's model identifier (for example Mac16,1), the primary signal
    /// for a real XDR panel: names and headroom values from NSScreen proved
    /// unreliable across machines and macOS versions.
    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()

    /// Which sustainable boost curve this panel generation takes.
    private static let panelReference = ExtraBrightnessSupport.panelReference(model: modelIdentifier)

    private static func builtInXDRScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
                && ExtraBrightnessSupport.isSupportedPanel(
                    model: modelIdentifier,
                    localizedName: screen.localizedName,
                    potentialEDR: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
        }
    }

    /// The screen the trigger was built for. Which panel qualifies moves only
    /// with the display topology, and `didChangeScreenParametersNotification`
    /// already tracks that into `triggerDisplayID`, so the poll looks the
    /// display up instead of re-deriving it with `builtInXDRScreen()` four
    /// times a second.
    private var triggerScreen: NSScreen? {
        guard let triggerDisplayID else { return nil }
        return NSScreen.screens.first { Self.displayID(of: $0) == triggerDisplayID }
    }

    private func refreshSupported() {
        let now = Self.builtInXDRScreen() != nil
        if supported != now { supported = now }
    }

    private func syncBoostingFlag() {
        if boosting != observedBoosting { boosting = observedBoosting }
    }

    // MARK: - Lifecycle

    private func start() {
        guard pollTimer == nil else { return }
        guard let screen = Self.builtInXDRScreen() else { return }
        cancelPendingRestoreRetry()
        showTrigger(on: screen)
        installObserver()
        // Four presents a second: the headroom grant follows recent extended
        // range presents and macOS revokes it about a second after they stop,
        // so this heartbeat keeps a comfortable margin while costing nothing.
        // The common modes keep it beating while one of the app's menus,
        // sliders or alerts tracks the mouse; the default mode alone pauses
        // there, long enough for the grant to lapse.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.renderIfNeeded()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        renderIfNeeded()
    }

    func stop() {
        stop(preservingObservers: false)
    }

    private func stop(preservingObservers: Bool) {
        let hasActiveGamma = gammaBaseline != nil
            || pendingGammaRestore != nil
            || appliedGammaFactor > 1.0 + ExtraBrightnessSupport.gammaFactorEpsilon
        guard pollTimer != nil || triggerWindow != nil || hasActiveGamma
                || screenObserver != nil || pendingRestoreRetryWorkItem != nil else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        restoreGammaBaseline(clearingBaseline: true)
        _ = resolvePendingGammaRestore()
        if preservingObservers || pendingGammaRestore != nil {
            installObserver()
        } else {
            removeObserver()
        }
        if pendingGammaRestore != nil {
            schedulePendingRestoreRetryIfNeeded()
        } else {
            cancelPendingRestoreRetry()
        }
        triggerDisplayID = nil
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        triggerLayer = nil
        overlaySpace?.close()
        overlaySpace = nil
        commandQueue = nil
        metalDevice = nil
        renderedFactor = 1.0
        profileChangePending = false
        lastScreenColorSpace = nil
        syncBoostingFlag()
    }

    private func installObserver() {
        guard screenObserver == nil else { return }
        let center = NotificationCenter.default
        screenObserver = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenChange()
        }
        colorSpaceObserver = center.addObserver(
            forName: NSScreen.colorSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleProfileChange()
        }
        windowProfileObserver = center.addObserver(
            forName: NSWindow.didChangeScreenProfileNotification,
            object: nil, queue: .main) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow,
                  window === self.triggerWindow else { return }
            self.handleProfileChange()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.handleScreensSleep()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.handleScreensWake()
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.handleActiveSpaceChange()
            },
        ]
    }

    private func removeObserver() {
        let center = NotificationCenter.default
        if let screenObserver { center.removeObserver(screenObserver) }
        screenObserver = nil
        if let colorSpaceObserver { center.removeObserver(colorSpaceObserver) }
        colorSpaceObserver = nil
        if let windowProfileObserver { center.removeObserver(windowProfileObserver) }
        windowProfileObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers = []
        screensAsleep = false
    }

    private func cleanupObserversIfDisabled() {
        let enabled = AppFeature.extraBrightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
        if !enabled, pendingGammaRestore == nil, pollTimer == nil {
            cancelPendingRestoreRetry()
            removeObserver()
        }
    }

    private func cancelPendingRestoreRetry() {
        pendingRestoreRetryWorkItem?.cancel()
        pendingRestoreRetryWorkItem = nil
        pendingRestoreRetryAttempt = 0
    }

    /// Keeps a cancellable, backoff-paced retry running while a baseline
    /// restore is still pending, the feature is off, and the screens are awake.
    /// Pauses on sleep and cancels immediately once restoration succeeds or
    /// the feature starts again.
    private func schedulePendingRestoreRetryIfNeeded() {
        guard pollTimer == nil, pendingGammaRestore != nil, !screensAsleep else {
            if pendingGammaRestore == nil || pollTimer != nil { cancelPendingRestoreRetry() }
            return
        }
        guard pendingRestoreRetryWorkItem == nil else { return }
        let delay = ExtraBrightnessSupport.pendingRestoreRetryDelay(attempt: pendingRestoreRetryAttempt)
        pendingRestoreRetryAttempt += 1
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRestoreRetryWorkItem = nil
            guard self.pollTimer == nil, self.pendingGammaRestore != nil, !self.screensAsleep else {
                if self.pendingGammaRestore == nil || self.pollTimer != nil {
                    self.cancelPendingRestoreRetry()
                }
                return
            }
            if self.resolvePendingGammaRestore() {
                self.cleanupObserversIfDisabled()
            } else {
                self.schedulePendingRestoreRetryIfNeeded()
            }
        }
        pendingRestoreRetryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func handleScreensSleep() {
        screensAsleep = true
        cancelPendingRestoreRetry()
        restoreGammaBaseline(clearingBaseline: true)
        renderedFactor = 1.0
        syncBoostingFlag()
    }

    private func handleScreensWake() {
        screensAsleep = false
        cancelPendingRestoreRetry()
        _ = resolvePendingGammaRestore()
        if pollTimer != nil {
            renderIfNeeded()
        } else if pendingGammaRestore != nil {
            schedulePendingRestoreRetryIfNeeded()
        } else {
            cleanupObserversIfDisabled()
        }
    }

    private func handleProfileChange() {
        if pendingGammaRestore != nil {
            _ = resolvePendingGammaRestore()
            cleanupObserversIfDisabled()
        }
        guard pollTimer != nil, gammaBaseline != nil else { return }
        profileChangePending = true
        renderIfNeeded()
    }

    /// The trigger sits in its own Space (or, without it, on every Space), so
    /// a desktop or fullscreen change normally needs nothing beyond a fresh
    /// present and drift check. Rebuilding stays as the fallback for what can
    /// still move the ground under it: a different built-in display, or AppKit
    /// reporting that a desktop-resident trigger is not on the active Space.
    private func handleActiveSpaceChange() {
        guard pollTimer != nil else { return }
        guard let screen = Self.builtInXDRScreen() else {
            handleScreenChange()
            return
        }
        if let triggerWindow,
           ExtraBrightnessSupport.canReuseTriggerWindow(
               sameDisplay: triggerDisplayID == Self.displayID(of: screen),
               inOwnSpace: overlaySpace != nil,
               triggerOnActiveSpace: triggerWindow.isOnActiveSpace) {
            renderIfNeeded()
            return
        }
        showTrigger(on: screen)
        renderIfNeeded()
    }

    private func handleScreenChange() {
        refreshSupported()
        _ = resolvePendingGammaRestore()
        let enabled = AppFeature.extraBrightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
        guard enabled else {
            stop()
            return
        }
        guard let screen = Self.builtInXDRScreen() else {
            // Built-in display gone (clamshell): release everything; the
            // preference stays on and a later screen change brings it back.
            stop(preservingObservers: true)
            return
        }
        guard pollTimer != nil else {
            start()
            return
        }
        // The same panel re-announces itself in storms: an EDR headroom ramp
        // alone fires this notification over a hundred times in two seconds
        // (measured), and HDR video starting or going fullscreen ramps the
        // headroom every time. Rebuilding or recapturing the baseline for each
        // one would blink the boost; with the panel, profile and frame
        // unchanged nothing happens here at all and the poll keeps its pace.
        if let triggerWindow, triggerDisplayID == Self.displayID(of: screen) {
            var needsRender = false
            if let lastColorSpace = lastScreenColorSpace, screen.colorSpace != lastColorSpace {
                profileChangePending = true
                needsRender = true
            }
            lastScreenColorSpace = screen.colorSpace
            let frame = Self.triggerFrame(on: screen)
            if triggerWindow.frame != frame {
                triggerWindow.setFrame(frame, display: false)
                needsRender = true
            }
            if needsRender {
                renderIfNeeded()
            }
        } else {
            restoreGammaBaseline(clearingBaseline: true)
            showTrigger(on: screen)
            renderIfNeeded()
        }
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func triggerFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.maxX - 1, y: screen.frame.minY, width: 1, height: 1)
    }

    /// Neither window list option works for finding the blocked sheet
    /// directly: `.optionOnScreenOnly` never lists it, and `.optionAll`
    /// carries dozens of stale windows AMSUIPaymentViewService leaves
    /// registered from earlier purchase attempts long after they are
    /// dismissed.
    ///
    /// SecurityAgent owns the Touch ID / password panel for admin prompts
    /// and is a real running application for as long as its panel is up, so
    /// it can be checked directly. For the Mac App Store's purchase sheet,
    /// stepping out of the way while the Store itself is frontmost avoids any
    /// shielding-level window interference.
    private static func systemAuthorizationUIIsActive() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.SecurityAgent").isEmpty {
            return true
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.AppStore"
    }

    /// The trigger belongs to every Space and sits out Exposé so Space
    /// transitions never pause the extended-range presents that keep the
    /// panel's EDR headroom engaged.
    private static let triggerCollectionBehavior: NSWindow.CollectionBehavior = [
        .ignoresCycle, .fullScreenAuxiliary, .canJoinAllApplications,
        .canJoinAllSpaces, .stationary,
    ]

    /// Desktop and window-overview transitions composite above ordinary
    /// screen-saver windows, so the one-pixel headroom trigger stays at the
    /// display-shield level to remain presented throughout transitions.
    private static let triggerWindowLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    // MARK: - Trigger Window

    /// The one-pixel extended-range window that makes macOS engage and sustain
    /// the panel's EDR headroom. It sits in the bottom right corner of the
    /// screen and is kept dim, so at most it reads as a faint dot there while
    /// the boost is on.
    private func showTrigger(on screen: NSScreen) {
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        triggerLayer = nil
        overlaySpace?.close()
        overlaySpace = NotchOverlaySpace()

        guard let device = metalDevice ?? MTLCreateSystemDefaultDevice(),
              let queue = commandQueue ?? device.makeCommandQueue() else { return }

        let newDisplayID = Self.displayID(of: screen)
        if let existingBaseline = gammaBaseline, existingBaseline.displayID != newDisplayID {
            restoreGammaBaseline(clearingBaseline: true)
        }
        lastScreenColorSpace = screen.colorSpace

        let window = NSWindow(contentRect: Self.triggerFrame(on: screen), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = Self.triggerWindowLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.sharingType = .none
        window.collectionBehavior = Self.triggerCollectionBehavior

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view

        triggerDisplayID = newDisplayID
        metalDevice = device
        commandQueue = queue
        triggerWindow = window
        triggerLayer = layer
        presentTrigger(waitUntilScheduled: true)
        overlaySpace?.add(window)
        window.orderFrontRegardless()
    }

    /// One clear pass of the extended range pixel. Called on every poll tick
    /// while the boost is on: the headroom grant follows recent presents, so
    /// a single frame engages it only to lose it a moment later.
    private func presentTrigger(waitUntilScheduled: Bool = false) {
        guard let layer = triggerLayer,
              let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Comfortably in extended range so the headroom engages, but dim
        // enough that the single pixel stays unobtrusive.
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1.8, green: 1.8, blue: 1.8, alpha: 1.0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        if waitUntilScheduled { commands.waitUntilScheduled() }
    }

    // MARK: - Gamma Transfer Table

    /// Reads the full native transfer table using the display's reported
    /// capacity (for example 1,024 entries on Liquid Retina XDR panels).
    /// Rejects partial reads so restoration is always lossless across every
    /// native sample.
    private static func readGammaTable(
        for displayID: CGDirectDisplayID
    ) -> ExtraBrightnessSupport.GammaTable? {
        let capacity = Int(CGDisplayGammaTableCapacity(displayID))
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, UInt32(capacity),
                                          &red, &green, &blue, &sampleCount) == .success,
              Int(sampleCount) == capacity else { return nil }
        return ExtraBrightnessSupport.GammaTable(red: red, green: green, blue: blue)
    }

    @discardableResult
    private func restoreGammaTable(_ baseline: GammaBaseline) -> Bool {
        guard CGDisplayIsBuiltin(baseline.displayID) != 0,
              CGDisplayIsAsleep(baseline.displayID) == 0 else { return false }
        guard CGSetDisplayTransferByTable(baseline.displayID, baseline.table.count,
                                          baseline.table.red, baseline.table.green,
                                          baseline.table.blue) == .success else { return false }
        guard let verified = Self.readGammaTable(for: baseline.displayID) else { return false }
        return ExtraBrightnessSupport.gammaTableMatches(verified, expected: baseline.table)
    }

    /// Inspects the live LUT *before* replaying the saved baseline so a newly
    /// loaded clean ColorSync profile is never overwritten with an older
    /// profile's curve. Only replays the saved baseline when the live LUT is
    /// still carrying this service's boost (or cannot be confirmed clean).
    @discardableResult
    private func resolvePendingGammaRestore(for displayID: CGDirectDisplayID? = nil) -> Bool {
        guard let pending = pendingGammaRestore else { return true }
        let targetID = pending.baseline.displayID
        guard CGDisplayIsBuiltin(targetID) != 0,
              CGDisplayIsAsleep(targetID) == 0 else {
            if let displayID, targetID != displayID { return true }
            return false
        }
        let observed = Self.readGammaTable(for: targetID)
        switch ExtraBrightnessSupport.pendingRestoreAction(
            baseline: pending.baseline.table,
            appliedFactor: pending.appliedFactor,
            observed: observed) {
        case .clearWithoutWrite:
            pendingGammaRestore = nil
            cancelPendingRestoreRetry()
            appliedGammaFactor = 1.0
            observedBoosting = false
            syncBoostingFlag()
            return true
        case .replayBaseline:
            if restoreGammaTable(pending.baseline) {
                pendingGammaRestore = nil
                cancelPendingRestoreRetry()
                appliedGammaFactor = 1.0
                observedBoosting = false
                syncBoostingFlag()
                return true
            }
            if let displayID, targetID != displayID { return true }
            return false
        }
    }

    private func captureGammaBaselineIfNeeded(for displayID: CGDirectDisplayID) -> GammaBaseline? {
        guard resolvePendingGammaRestore(for: displayID) else { return nil }
        if let existing = gammaBaseline, existing.displayID == displayID {
            return existing
        }
        if gammaBaseline != nil {
            restoreGammaBaseline(clearingBaseline: true)
            guard resolvePendingGammaRestore(for: displayID) else { return nil }
        }
        guard CGDisplayIsBuiltin(displayID) != 0,
              CGDisplayIsAsleep(displayID) == 0,
              let live = Self.readGammaTable(for: displayID),
              ExtraBrightnessSupport.isUsableGammaBaseline(live) else { return nil }
        let baseline = GammaBaseline(displayID: displayID, table: live)
        gammaBaseline = baseline
        profileChangePending = false
        return baseline
    }

    private func restoreGammaBaseline(clearingBaseline: Bool) {
        let neutralLimit = 1.0 + ExtraBrightnessSupport.gammaFactorEpsilon
        if let baseline = gammaBaseline, appliedGammaFactor > neutralLimit {
            let liveBeforeWrite = (CGDisplayIsBuiltin(baseline.displayID) != 0
                && CGDisplayIsAsleep(baseline.displayID) == 0)
                ? Self.readGammaTable(for: baseline.displayID)
                : nil
            switch ExtraBrightnessSupport.pendingRestoreAction(
                baseline: baseline.table,
                appliedFactor: appliedGammaFactor,
                observed: liveBeforeWrite) {
            case .clearWithoutWrite:
                appliedGammaFactor = 1.0
                observedBoosting = false
                if pendingGammaRestore?.baseline.displayID == baseline.displayID {
                    pendingGammaRestore = nil
                    cancelPendingRestoreRetry()
                }
            case .replayBaseline:
                if restoreGammaTable(baseline) {
                    appliedGammaFactor = 1.0
                    observedBoosting = false
                    if pendingGammaRestore?.baseline.displayID == baseline.displayID {
                        pendingGammaRestore = nil
                        cancelPendingRestoreRetry()
                    }
                } else {
                    pendingGammaRestore = PendingGammaRestore(
                        baseline: baseline,
                        appliedFactor: appliedGammaFactor)
                    if let liveBeforeWrite {
                        observedBoosting = ExtraBrightnessSupport.observedBoostActive(
                            baseline: baseline.table, observed: liveBeforeWrite)
                    }
                }
            }
        }
        if clearingBaseline {
            gammaBaseline = nil
            if pendingGammaRestore == nil {
                appliedGammaFactor = 1.0
                observedBoosting = false
            }
        }
        syncBoostingFlag()
    }

    /// Sustains the EDR trigger pixel and updates the built-in display's
    /// hardware transfer table for the current level and granted headroom.
    /// The factor moves one smoothing step per tick while headroom is engaged
    /// so a grant wobbling under HDR video reads as a gentle drift instead of
    /// stepped flashes; `immediate` (the level slider) snaps straight to the
    /// target. Whenever headroom is absent or drops to SDR, the transfer table
    /// restores immediately so bright whites are never clipped.
    private func renderIfNeeded(immediate: Bool = false) {
        guard !screensAsleep else { return }
        guard let screen = triggerScreen,
              let displayID = triggerDisplayID,
              triggerLayer != nil else { return }
        guard CGDisplayIsAsleep(displayID) == 0 else { return }
        guard !Self.systemAuthorizationUIIsActive() else {
            triggerWindow?.orderOut(nil)
            restoreGammaBaseline(clearingBaseline: false)
            renderedFactor = 1.0
            syncBoostingFlag()
            return
        }
        if let triggerWindow, !triggerWindow.isVisible { triggerWindow.orderFrontRegardless() }
        presentTrigger()
        guard var baseline = captureGammaBaselineIfNeeded(for: displayID) else {
            renderedFactor = 1.0
            syncBoostingFlag()
            return
        }

        if let lastColorSpace = lastScreenColorSpace, screen.colorSpace != lastColorSpace {
            profileChangePending = true
        }
        lastScreenColorSpace = screen.colorSpace

        var observedTable: ExtraBrightnessSupport.GammaTable?
        if profileChangePending {
            observedTable = Self.readGammaTable(for: displayID)
            if let observed = observedTable,
               ExtraBrightnessSupport.canAdoptProfileBaseline(
                   previousBaseline: baseline.table,
                   appliedFactor: appliedGammaFactor,
                   observed: observed) {
                let adopted = GammaBaseline(displayID: displayID, table: observed)
                gammaBaseline = adopted
                baseline = adopted
                appliedGammaFactor = 1.0
                observedBoosting = false
                profileChangePending = false
            }
        }

        let level = Double(UserDefaults.standard.integer(forKey: DefaultsKey.extraBrightnessLevel)) / 100.0
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        let baselinePeak = Double(ExtraBrightnessSupport.gammaTablePeak(baseline.table))
        let neutralLimit = 1.0 + ExtraBrightnessSupport.gammaFactorEpsilon

        let preview = ExtraBrightnessSupport.effectiveGammaAction(
            level: level,
            currentEDR: headroom,
            potentialEDR: potential,
            reference: Self.panelReference,
            previousFactor: renderedFactor,
            appliedFactor: appliedGammaFactor,
            baselinePeak: baselinePeak,
            immediate: immediate,
            drifted: false)

        var drifted = false
        if preview.action == .noop, preview.nextFactor > neutralLimit {
            let live = observedTable ?? Self.readGammaTable(for: displayID)
            observedTable = live
            if let live {
                drifted = ExtraBrightnessSupport.gammaTableDrifted(
                    baseline: baseline.table,
                    observed: live,
                    factor: preview.nextFactor)
                if drifted {
                    observedBoosting = ExtraBrightnessSupport.observedBoostActive(
                        baseline: baseline.table,
                        observed: live)
                }
            }
        }

        let decision = ExtraBrightnessSupport.effectiveGammaAction(
            level: level,
            currentEDR: headroom,
            potentialEDR: potential,
            reference: Self.panelReference,
            previousFactor: renderedFactor,
            appliedFactor: appliedGammaFactor,
            baselinePeak: baselinePeak,
            immediate: immediate,
            drifted: drifted)
        renderedFactor = decision.nextFactor

        switch decision.action {
        case .noop:
            break
        case .restore:
            let live = observedTable ?? Self.readGammaTable(for: displayID)
            switch ExtraBrightnessSupport.pendingRestoreAction(
                baseline: baseline.table,
                appliedFactor: appliedGammaFactor,
                observed: live) {
            case .clearWithoutWrite:
                appliedGammaFactor = 1.0
                observedBoosting = false
                if pendingGammaRestore?.baseline.displayID == displayID {
                    pendingGammaRestore = nil
                    cancelPendingRestoreRetry()
                }
            case .replayBaseline:
                if restoreGammaTable(baseline) {
                    appliedGammaFactor = 1.0
                    observedBoosting = false
                    if pendingGammaRestore?.baseline.displayID == displayID {
                        pendingGammaRestore = nil
                        cancelPendingRestoreRetry()
                    }
                } else if let live {
                    observedBoosting = ExtraBrightnessSupport.observedBoostActive(
                        baseline: baseline.table,
                        observed: live)
                }
            }
        case .apply(let factor):
            let scaled = ExtraBrightnessSupport.boostTransferTable(from: baseline.table, factor: factor)
            if CGSetDisplayTransferByTable(displayID, scaled.count,
                                           scaled.red, scaled.green, scaled.blue) == .success {
                appliedGammaFactor = factor
                observedBoosting = factor > 1.001
            } else if let live = observedTable ?? Self.readGammaTable(for: displayID) {
                observedBoosting = ExtraBrightnessSupport.observedBoostActive(
                    baseline: baseline.table,
                    observed: live)
                if !observedBoosting,
                   ExtraBrightnessSupport.canClearPendingRestore(
                       baseline: baseline.table,
                       appliedFactor: appliedGammaFactor,
                       observed: live) {
                    appliedGammaFactor = 1.0
                }
            }
        }

        syncBoostingFlag()
    }
}
