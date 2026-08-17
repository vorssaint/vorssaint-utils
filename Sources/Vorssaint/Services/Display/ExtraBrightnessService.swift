// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Metal
import QuartzCore

/// Pushes a display past its regular maximum brightness by using the panel's
/// HDR headroom for everything on screen: the built-in XDR panel of a MacBook
/// Pro, and any external monitor that reports headroom of its own.
///
/// Mechanism: a fullscreen, click-through overlay window holds a Metal layer
/// whose compositing filter is "multiply". The layer renders a solid gray
/// above 1.0 in extended linear sRGB, so the window server multiplies every
/// pixel beneath it into the extended range the panel reserves for HDR:
/// whites get brighter, blacks stay black, contrast is preserved. Showing
/// extended range content is also exactly what makes macOS engage the
/// panel's headroom, so the overlay bootstraps itself: it starts with a
/// small boost and ramps up as the reported headroom rises.
///
/// Every capable display gets its own overlay pair and its own smoothing
/// state, because the headroom each one grants moves independently.
///
/// Everything is public API and macOS stays in charge of the panels: thermal
/// or power pressure can shrink the headroom at any time and the poll adapts.
/// The overlays die with the app, so no display state can outlive a crash.
/// No windows, timers or observers exist while the feature is off.
final class ExtraBrightnessService: ObservableObject {
    static let shared = ExtraBrightnessService()

    /// At least one display with EDR headroom exists (feature can work here).
    @Published private(set) var supported = false
    /// The boost is currently visible on at least one display.
    @Published private(set) var boosting = false

    /// One boosted display: its overlay pair, the curve its panel takes and
    /// the smoothing state that belongs to it alone.
    private final class Boost {
        let displayID: UInt32
        let reference: (referenceEDR: Double, bonus: Double)
        var overlayWindow: NSWindow
        var overlayLayer: CAMetalLayer
        /// A one-pixel corner window without the multiply filter. The multiply
        /// layer alone does not reliably make macOS engage the panel's
        /// headroom, but a plain extended range pixel does (verified on this
        /// hardware). Its layer keeps re-presenting on every poll tick: macOS
        /// only sustains the headroom while extended range content keeps being
        /// presented, and revokes it about a second after the last present
        /// (the boost visibly dropped out on XDR hardware when only the first
        /// frame was shown).
        var triggerWindow: NSWindow
        var triggerLayer: CAMetalLayer
        /// The factor currently on screen, moved one smoothing step per tick
        /// toward the instantaneous target (see the ramp constants in
        /// ExtraBrightnessSupport): the grant wobbles while HDR video plays
        /// and rendering it raw flashed the whole screen in visible steps.
        var renderedFactor = 1.0
        /// Consecutive poll ticks that read no engaged headroom.
        var disengagedTicks = 0

        init(displayID: UInt32, reference: (referenceEDR: Double, bonus: Double),
             overlayWindow: NSWindow, overlayLayer: CAMetalLayer,
             triggerWindow: NSWindow, triggerLayer: CAMetalLayer) {
            self.displayID = displayID
            self.reference = reference
            self.overlayWindow = overlayWindow
            self.overlayLayer = overlayLayer
            self.triggerWindow = triggerWindow
            self.triggerLayer = triggerLayer
        }
    }

    private var boosts: [UInt32: Boost] = [:]
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// While the screens sleep the compositor stops recycling drawables and
    /// nextDrawable would stall the main thread, so presents pause and a
    /// fresh render happens on wake.
    private var screensAsleep = false

    private init() {}

    func syncWithPreferences() {
        refreshSupported()
        let wanted = AppFeature.extraBrightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
            && supported
        if wanted { start() } else { stop() }
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

    /// Which sustainable boost curve this Mac's own panel generation takes.
    private static let panelReference = ExtraBrightnessSupport.panelReference(model: modelIdentifier)

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Every screen worth boosting, each with the curve its panel takes. The
    /// built-in panel is judged by the Mac's model, an external monitor only
    /// by the headroom it reports, since its panel is not knowable from its
    /// name.
    private static func boostableScreens() -> [(screen: NSScreen, id: UInt32,
                                                reference: (referenceEDR: Double, bonus: Double))] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            if CGDisplayIsBuiltin(id) != 0 {
                guard ExtraBrightnessSupport.isSupportedPanel(model: modelIdentifier,
                                                              localizedName: screen.localizedName,
                                                              potentialEDR: potential) else { return nil }
                return (screen, id, panelReference)
            }
            guard ExtraBrightnessSupport.isBoostableExternal(potentialEDR: potential) else { return nil }
            return (screen, id, ExtraBrightnessSupport.externalReference(potentialEDR: potential))
        }
    }

    private func refreshSupported() {
        let now = !Self.boostableScreens().isEmpty
        if supported != now { supported = now }
    }

    // MARK: - Lifecycle

    private func start() {
        guard pollTimer == nil else { return }
        let screens = Self.boostableScreens()
        guard !screens.isEmpty else { return }
        reconcileBoosts(with: screens)
        guard !boosts.isEmpty else { return }
        installObserver()
        // Four presents a second: the headroom grant follows recent extended
        // range presents and macOS revokes it about a second after they stop,
        // so this heartbeat keeps a comfortable margin while costing nothing.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.renderIfNeeded()
        }
        pollTimer?.tolerance = 0.05
        renderIfNeeded()
    }

    func stop() {
        guard pollTimer != nil || !boosts.isEmpty else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        removeObserver()
        for boost in boosts.values { tearDown(boost) }
        boosts = [:]
        commandQueue = nil
        metalDevice = nil
        if boosting { boosting = false }
    }

    private func tearDown(_ boost: Boost) {
        boost.overlayWindow.orderOut(nil)
        boost.triggerWindow.orderOut(nil)
    }

    private func installObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenChange()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.renderIfNeeded()
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.handleActiveSpaceChange()
            },
        ]
    }

    private func removeObserver() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers = []
        screensAsleep = false
    }

    /// Each pair is resident on every Space, so a desktop or fullscreen change
    /// normally needs nothing beyond a fresh present. Rebuilding stays as the
    /// fallback for what can still move the ground under one: a display coming
    /// or going, or AppKit reporting that a window is not there.
    private func handleActiveSpaceChange() {
        guard pollTimer != nil else { return }
        let screens = Self.boostableScreens()
        guard !screens.isEmpty else {
            handleScreenChange()
            return
        }
        let stranded = screens.contains { entry in
            guard let boost = boosts[entry.id] else { return true }
            return !ExtraBrightnessSupport.canReuseSpaceWindows(
                sameDisplay: true,
                overlayOnActiveSpace: boost.overlayWindow.isOnActiveSpace,
                triggerOnActiveSpace: boost.triggerWindow.isOnActiveSpace)
        }
        if stranded { reconcileBoosts(with: screens, rebuildAll: true) }
        renderIfNeeded()
    }

    private func handleScreenChange() {
        refreshSupported()
        guard pollTimer != nil else { return }
        let screens = Self.boostableScreens()
        guard !screens.isEmpty else {
            // Nothing left to boost (clamshell, the HDR monitor unplugged):
            // release everything. The preference stays on and a later screen
            // change brings it back.
            stop()
            syncWithPreferences()
            return
        }
        reconcileBoosts(with: screens)
        renderIfNeeded()
    }

    /// Brings the live overlays in line with the boostable screens: new
    /// displays get a pair, departed ones give theirs up, and a display whose
    /// frame moved has its windows resized.
    ///
    /// The same panel re-announces itself in storms: an EDR headroom ramp
    /// alone fires the screen notification over a hundred times in two
    /// seconds (measured), and HDR video starting or going fullscreen ramps
    /// the headroom every time. Rebuilding for each one blinked the boost off
    /// and on, so a display already covered at the same frame is left
    /// completely alone and the poll keeps its own pace.
    private func reconcileBoosts(with screens: [(screen: NSScreen, id: UInt32,
                                                 reference: (referenceEDR: Double, bonus: Double))],
                                 rebuildAll: Bool = false) {
        let wanted = Set(screens.map(\.id))
        for (id, boost) in boosts where !wanted.contains(id) {
            tearDown(boost)
            boosts.removeValue(forKey: id)
        }
        guard let device = metalDevice ?? MTLCreateSystemDefaultDevice(),
              let queue = commandQueue ?? device.makeCommandQueue() else { return }
        metalDevice = device
        commandQueue = queue
        for entry in screens {
            if let boost = boosts[entry.id], !rebuildAll {
                if boost.overlayWindow.frame != entry.screen.frame {
                    boost.overlayWindow.setFrame(entry.screen.frame, display: false)
                    boost.overlayLayer.frame = CGRect(origin: .zero, size: entry.screen.frame.size)
                    boost.triggerWindow.setFrame(Self.triggerFrame(on: entry.screen), display: false)
                }
                continue
            }
            // A pair replaced mid-boost hands its factor to the new one, so
            // the display never blinks back through neutral on the way.
            let carried = boosts.removeValue(forKey: entry.id)
            if let carried { tearDown(carried) }
            boosts[entry.id] = makeBoost(on: entry.screen, id: entry.id,
                                         reference: entry.reference,
                                         device: device, queue: queue,
                                         startingFactor: carried?.renderedFactor ?? 1.0)
        }
    }

    private static func triggerFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.maxX - 1, y: screen.frame.minY, width: 1, height: 1)
    }

    /// The pair belongs to every Space and sits out Exposé. Bound to a single
    /// Space it travelled with that Space: swiping to another desktop slid the
    /// overlay off screen for the whole animation, taking the boost with it
    /// until the transition ended and a rebuild brought it back (measured).
    /// Resident everywhere there is no handoff at all, and the presents that
    /// hold the panel's headroom never pause.
    private static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .ignoresCycle, .fullScreenAuxiliary, .canJoinAllApplications,
        .canJoinAllSpaces, .stationary,
    ]

    /// Desktop and window-overview transitions composite above ordinary
    /// screen-saver windows. Keep the multiplier and its headroom trigger at
    /// the display-shield level so both remain in the final picture.
    private static let overlayWindowLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    // MARK: - Overlay

    private func makeBoost(on screen: NSScreen, id: UInt32,
                           reference: (referenceEDR: Double, bonus: Double),
                           device: MTLDevice, queue: MTLCommandQueue,
                           startingFactor: Double) -> Boost {
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        // Above regular windows and the menu bar so the whole picture is
        // boosted evenly; it ignores clicks, so it is never in the way.
        Self.configureOverlayWindow(window)

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.isOpaque = false
        // The window server multiplies everything beneath by this layer's
        // pixels. A uniform color needs no resolution: two by two is plenty.
        layer.compositingFilter = "multiply"
        layer.drawableSize = CGSize(width: 2, height: 2)
        layer.frame = CGRect(origin: .zero, size: screen.frame.size)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view

        let triggerWindow = NSWindow(contentRect: Self.triggerFrame(on: screen),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        Self.configureOverlayWindow(triggerWindow)
        let triggerLayer = CAMetalLayer()
        triggerLayer.device = device
        triggerLayer.pixelFormat = .rgba16Float
        triggerLayer.wantsExtendedDynamicRangeContent = true
        triggerLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        triggerLayer.drawableSize = CGSize(width: 1, height: 1)
        triggerLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let triggerView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        triggerView.wantsLayer = true
        triggerView.layer = triggerLayer
        triggerWindow.contentView = triggerView

        let boost = Boost(displayID: id, reference: reference,
                          overlayWindow: window, overlayLayer: layer,
                          triggerWindow: triggerWindow, triggerLayer: triggerLayer)
        boost.renderedFactor = startingFactor
        // First frame before the windows show: a rebuild mid-boost must come
        // up already multiplying, never with an empty (neutral) layer.
        render(boost, factor: boost.renderedFactor, waitUntilScheduled: true)
        window.orderFrontRegardless()
        presentTrigger(boost, waitUntilScheduled: true)
        triggerWindow.orderFrontRegardless()
        return boost
    }

    private static func configureOverlayWindow(_ window: NSWindow) {
        window.level = overlayWindowLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        // Screenshots and recordings must show the real content, not the
        // boosted composite (the overlay would wash captures out).
        window.sharingType = .none
        window.collectionBehavior = overlayCollectionBehavior
    }

    /// One clear pass of the extended range pixel. Called on every poll tick
    /// while the boost is on: the headroom grant follows recent presents, so
    /// a single frame engages it only to lose it a moment later.
    private func presentTrigger(_ boost: Boost, waitUntilScheduled: Bool = false) {
        guard let queue = commandQueue,
              let drawable = boost.triggerLayer.nextDrawable(),
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

    /// Renders the multiply color for the current level and headroom, every
    /// poll tick, for every boosted display. Both layers of each pair keep
    /// presenting for as long as the boost is on: macOS grants a panel's
    /// headroom in response to presented extended range content and revokes
    /// it moments after presents stop, which visibly dropped the boost after
    /// a second on XDR hardware. Two tiny clear passes per display per tick
    /// cost nothing measurable. Each display's rendered factor moves one
    /// smoothing step per tick (with a grace window over transient dropouts),
    /// so a grant wobbling under HDR video reads as a gentle drift instead of
    /// stepped flashes; `immediate` (the level slider) snaps to the target.
    private func renderIfNeeded(immediate: Bool = false) {
        guard !screensAsleep, !boosts.isEmpty else { return }
        let level = Double(UserDefaults.standard.integer(forKey: DefaultsKey.extraBrightnessLevel)) / 100.0
        var screensByID: [UInt32: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = Self.displayID(of: screen) { screensByID[id] = screen }
        }
        var anyVisible = false
        for boost in boosts.values {
            guard let screen = screensByID[boost.displayID] else { continue }
            presentTrigger(boost)
            let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            let engaged = headroom > ExtraBrightnessSupport.headroomThreshold
            boost.disengagedTicks = engaged ? 0 : boost.disengagedTicks + 1
            let instantaneous = ExtraBrightnessSupport.renderFactor(level: level,
                                                                    currentEDR: headroom,
                                                                    potentialEDR: potential,
                                                                    reference: boost.reference)
            if immediate {
                boost.renderedFactor = instantaneous
            } else {
                let target = ExtraBrightnessSupport.gracedTarget(instantaneous: instantaneous,
                                                                 previous: boost.renderedFactor,
                                                                 engaged: engaged,
                                                                 disengagedTicks: boost.disengagedTicks)
                boost.renderedFactor = ExtraBrightnessSupport.rampedFactor(previous: boost.renderedFactor,
                                                                           target: target)
            }
            render(boost, factor: boost.renderedFactor)
            if boost.renderedFactor > 1.001 { anyVisible = true }
        }
        if boosting != anyVisible { boosting = anyVisible }
    }

    /// One clear-only render pass, no shaders: the drawable is a uniform gray
    /// at `factor`, which the compositing filter multiplies with the screen.
    private func render(_ boost: Boost, factor: Double, waitUntilScheduled: Bool = false) {
        guard let queue = commandQueue,
              let drawable = boost.overlayLayer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor,
                                                            blue: factor, alpha: 1.0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        if waitUntilScheduled { commands.waitUntilScheduled() }
    }
}
