// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.graphics
import ObjectiveC.runtime
import os

/// One display the brightness feature can talk to.
struct BrightnessDisplay: Identifiable, Equatable {
    enum Method: Equatable {
        /// The system brightness pipeline: the built-in panel and Apple
        /// external displays.
        case system
        /// DDC/CI over the display's own I2C channel (regular external
        /// monitors).
        case ddc
        /// Gamma-curve dimming for displays whose connection carries no DDC
        /// (HDMI conversions, TVs): the slider darkens the picture itself.
        case software
    }

    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    /// Nil while the display is off, or when it can be switched but does not
    /// expose a brightness route of its own.
    var method: Method?
    var isActive: Bool
    /// 0...1 for the UI slider.
    var brightness: Double
    /// False when the monitor never answered a brightness read: the slider
    /// still works (writes go through), it just starts from the last value
    /// applied here instead of the monitor's own.
    let readable: Bool
}

/// Brightness sliders for every display, built-in and external. The built-in
/// panel and Apple displays go through the system brightness pipeline; other
/// external monitors are driven over DDC/CI, the same protocol their own
/// buttons use, addressed per display through its I2C service.
///
/// While display control is off there are no display observers, services or
/// I2C traffic. Keyboard light state is read only when Quick toggles opens.
/// While display control is on, the standing resources are one screen change
/// observer and a pair of wake observers, and no timers; everything else
/// happens when a slider moves, a panel opens or the Mac wakes. All I2C work
/// runs on a serial queue with the pacing displays need, and slider drags
/// coalesce to the newest value per display.
final class BrightnessService: ObservableObject {
    static let shared = BrightnessService()

    /// Field diagnosis channel: external display trouble is invisible from
    /// here (issue #301 kind of reports), so the display pipeline narrates
    /// its decisions to the unified log, where a user can collect them with
    /// one `log show` command after something goes wrong.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display")

    @Published private(set) var displays: [BrightnessDisplay] = []
    /// The displays that currently put a picture in front of a person, as the
    /// last rebuild found them. The panel decides from this snapshot instead
    /// of asking the display server itself: `canToggleDisplay` is read from a
    /// SwiftUI body, and a body is laid out again from inside the display
    /// reconfiguration this app drives on the main thread, where a question
    /// for the display server is one the same thread is already busy
    /// answering (issue #969).
    @Published private(set) var drawableDisplays = Set<CGDirectDisplayID>()
    @Published private(set) var pendingDisplayIDs = Set<CGDirectDisplayID>()
    @Published private(set) var displayControlFailure: DisplayControlFailure?
    @Published private(set) var brightnessOSDSupported = false
    @Published private(set) var keyboardLightEnabled: Bool?

    enum DisplayControlFailure: Equatable {
        case unavailable
        case lastActive
        case failed
    }

    private struct Route {
        var method: BrightnessDisplay.Method
        var service: CFTypeRef?
        var maximum: UInt16
        var ddcReadable = false
        var ddcPathKey: String?
    }

    private var screenObserver: NSObjectProtocol?
    private var rebuildDebounce: DispatchWorkItem?
    private var wakeObservers: [NSObjectProtocol] = []
    private var wakeRebuild: DispatchWorkItem?
    /// How long displays are given to finish coming back before they are
    /// spoken to again. A monitor still bringing its connection up answers
    /// nothing, and taking that silence at face value would move it off the
    /// protocol its own buttons use.
    private static let wakeSettleDelay: TimeInterval = 3
    /// Media-key tap, alive while pointer routing or the optional overlay is
    /// on and Accessibility is granted. Its mask covers system-defined events
    /// only, so ordinary typing never touches it.
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    /// Second tap for keyboards that send brightness as an ordinary key
    /// press instead of a media key. Every keystroke in the session passes
    /// through it, so it runs on its own thread: the window server waits for
    /// a tap to answer, and waiting on the main run loop is what made typing
    /// stutter once already.
    private let keyThreadLock = NSLock()
    private var functionKeyTap: CFMachPort?
    private var functionKeyRunLoop: CFRunLoop?
    private var functionKeyThread: Thread?
    private var shouldStopFunctionKeyThread = false
    private var pendingFunctionKeyRestart = false
    /// Whether F14 and F15 still mean brightness for the system. Sampled when
    /// the tap goes up, never from the tap thread.
    private var functionKeysAdjustBrightness = true
    /// Whether the app's own overlay stands in for the system's, sampled with
    /// the tap so the tap thread never reads published state.
    private var overlayReplacesNativeOSD = false
    /// Codes whose press this app consumed, so the matching release is
    /// consumed as well and the system never sees half a key.
    private var swallowedKeyCodes = Set<Int>()
    /// Serializes every I2C transaction and rebuild; DDC displays drop
    /// commands that interleave.
    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.brightness", qos: .userInitiated)
    private let stateLock = NSLock()
    private var routes: [CGDirectDisplayID: Route] = [:]
    private struct PendingWrite {
        let value: Double
        let showOSD: Bool
        let sequence: UInt64
    }
    private var pendingLevels: [CGDirectDisplayID: PendingWrite] = [:]
    private var writeSequence: UInt64 = 0
    /// Keeps fast system-key repeats based on the newest requested value while
    /// DisplayServices is still applying the previous asynchronous write.
    private var systemWritesInFlight = Set<CGDirectDisplayID>()
    /// Steps that arrived while the monitor behind a display was being read,
    /// waiting to be added to the step that read commits. An entry existing at
    /// all means a read is in flight for that display. Main thread only, like
    /// the key presses that fill it (issue #370).
    private var ddcPendingSteps: [CGDirectDisplayID: Double] = [:]
    private var drainScheduled = false
    /// Session memory for write-only monitors, so their slider does not jump
    /// back to a placeholder between panel openings. Each value remembers
    /// which physical monitor it belonged to: display numbers are handed out
    /// again after a reconnection, and a level saved for one monitor must
    /// never dim whatever inherits its number.
    private struct RememberedLevel {
        var value: Double
        var fingerprint: String
    }
    private var lastApplied: [CGDirectDisplayID: RememberedLevel] = [:]
    /// When each display's remembered level was last known to match the
    /// monitor, so a step can tell a value it just wrote from one that has
    /// been sitting around while the monitor moved on without it.
    private var levelKnownAt: [CGDirectDisplayID: Date] = [:]
    /// How long a remembered level is taken at face value. Long enough that
    /// holding a key steps smoothly off the running value, short enough that
    /// the first press after a pause asks the monitor where it actually is.
    private static let levelTrustWindow: TimeInterval = 3
    /// When the previous DDC command to each display finished, so the next
    /// one keeps the standard's spacing. Touched only on the work queue.
    private var ddcCommandEnds: [CGDirectDisplayID: UInt64] = [:]
    /// The unmodified gamma curve of each software-dimmed display, captured
    /// before the first change so restoring is exact. Touched only on the
    /// work queue.
    private var gammaBaselines: [CGDirectDisplayID: GammaTable] = [:]
    /// How many untouched curves are worth keeping for displays that are not
    /// attached right now. A curve is a few kilobytes and keeping it is what
    /// makes a reconnection safe, so the cap only exists so a long session
    /// full of different monitors cannot grow without bound.
    private static let rememberedGammaBaselines = 16
    /// Displays whose picture is currently scaled by this app. While a display
    /// is in here its live curve is ours, not its own, so it is never read
    /// back as a baseline. Touched only on the work queue.
    private var dimmedDisplays = Set<CGDirectDisplayID>()

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var count: UInt32
        /// Which monitor the curve was read from. Display numbers are handed
        /// out again after a reconnection, so this is what stops one
        /// monitor's curve from ever being written to another.
        var fingerprint: String
    }

    /// Identifies the physical monitor behind a display number.
    private static func displayFingerprint(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id))"
    }

    /// A remembered level, only if it was saved for the monitor currently
    /// behind this display number. Callers hold the state lock.
    private func rememberedLevel(for id: CGDirectDisplayID) -> Double? {
        guard let remembered = lastApplied[id],
              remembered.fingerprint == Self.displayFingerprint(id) else { return nil }
        return remembered.value
    }
    private var knownTopology = Set<CGDirectDisplayID>()
    private var knownActiveTopology = Set<CGDirectDisplayID>()
    /// Only displays disabled by this process are restored when the feature
    /// is switched off. A display another app disabled is never changed
    /// without a direct click from the user.
    private var managedDisabledIDs = Set<CGDirectDisplayID>()
    /// A disabled display leaves even CoreGraphics' online list. Keep its
    /// last row so the panel still offers the button that brings it back.
    private var managedDisabledDisplays: [CGDirectDisplayID: BrightnessDisplay] = [:]
    private var running = false
    private var keyboardLightLevel: Float?
    private var lastKeyboardLightLevel: Float = BrightnessSupport.defaultKeyboardLightLevel
    private lazy var keyboardLightBridge = KeyboardLightBridge()
    /// Stale rebuilds (an unplug mid-scan) must not overwrite fresh state.
    private var rebuildGeneration = 0
    /// The topology a queued or running rebuild already covers. Opening the
    /// panel must not put the same slow monitor probe behind itself again.
    private var rebuildingTopology: BrightnessSupport.DisplayTopology?

    private init() {}

    func setKeyboardLightEnabled(_ enabled: Bool) {
        guard keyboardLightEnabled != nil, let keyboardLightBridge else { return }
        if !enabled, let level = keyboardLightLevel, level > 0 {
            lastKeyboardLightLevel = level
        }
        let target = enabled
            ? BrightnessSupport.keyboardLightOnLevel(lastNonzero: lastKeyboardLightLevel)
            : 0
        guard keyboardLightBridge.setBrightness(target) else {
            refreshKeyboardLight()
            return
        }
        keyboardLightLevel = target
        keyboardLightEnabled = target > 0
    }

    /// Reads this Mac's keyboard light only when its Quick toggles surface opens.
    func refreshKeyboardLight() {
        guard let level = keyboardLightBridge?.brightness(), level >= 0, level <= 1 else {
            keyboardLightLevel = nil
            keyboardLightEnabled = nil
            return
        }
        keyboardLightLevel = level
        if level > 0 { lastKeyboardLightLevel = level }
        keyboardLightEnabled = level > 0
    }

    func syncWithPreferences() {
        let wanted = AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled)
        if wanted { start() } else { stop() }
        syncKeyTap()
    }

    private func start() {
        guard !running else { return }
        running = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        installWakeObservers()
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        removeKeyTap()
        removeFunctionKeyTap()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        removeWakeObservers()
        rebuildDebounce?.cancel()
        rebuildDebounce = nil
        stateLock.lock()
        rebuildGeneration += 1
        rebuildingTopology = nil
        routes = [:]
        pendingLevels = [:]
        writeSequence = 0
        systemWritesInFlight = []
        lastApplied = [:]
        knownTopology = []
        knownActiveTopology = []
        stateLock.unlock()
        ddcPendingSteps = [:]
        pendingDisplayIDs = []
        displayControlFailure = nil
        brightnessOSDSupported = false
        BrightnessOSD.teardown()
        if !displays.isEmpty { displays = [] }
        if !drawableDisplays.isEmpty { drawableDisplays = [] }
        // Queue on the work queue first so this lands AFTER any operation
        // already in flight, then hand the reconfigurations to the main
        // thread, which is the only place they may run (see
        // `configureDisplay`), and put the gamma curves back behind them.
        // Normal app termination uses the synchronous restoration below;
        // gamma also reverts with the process.
        workQueue.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreManagedDisplays()
                self.workQueue.async { [weak self] in
                    guard let self else { return }
                    self.restoreAllGamma()
                    self.ddcCommandEnds = [:]
                    Self.log.log("brightness service stopped; displays and gamma restored")
                }
            }
        }
    }

    /// Re-reads every display. Called when the panel section or the Settings
    /// page appears, so the sliders match changes made elsewhere (brightness
    /// keys, System Settings, the monitor's own buttons).
    func refresh(force: Bool = false) {
        guard running else { return }
        let topology = Self.currentTopology()
        let previousDisplays = displays
        stateLock.lock()
        guard BrightnessSupport.shouldQueueRebuild(topology: topology,
                                                   pending: rebuildingTopology,
                                                   force: force) else {
            stateLock.unlock()
            return
        }
        rebuildGeneration += 1
        let generation = rebuildGeneration
        rebuildingTopology = topology
        stateLock.unlock()
        let screenNames = Self.localizedScreenNames()
        workQueue.async { [weak self] in
            self?.rebuild(generation: generation, previousDisplays: previousDisplays,
                          screenNames: screenNames)
        }
    }

    /// The display names a person sees in System Settings, which is what the
    /// sliders are labelled with. `NSScreen` is main thread only while the
    /// rebuild runs on `workQueue`, so the whole set is read here and carried
    /// into the rebuild rather than looked up from it.
    private static func localizedScreenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                             as? NSNumber)?.uint32Value else { continue }
            names[id] = screen.localizedName
        }
        return names
    }

    /// Moves one display's brightness. The published value updates on the
    /// spot for a responsive slider; the hardware write happens on the work
    /// queue, and a drag folds into one write of the newest value.
    func setBrightness(_ value: Double, for id: CGDirectDisplayID,
                       showOSD: Bool = false) {
        let clamped = min(max(value, 0), 1)
        if let index = displays.firstIndex(where: { $0.id == id }),
           displays[index].brightness != clamped {
            displays[index].brightness = clamped
        }
        stateLock.lock()
        writeSequence &+= 1
        pendingLevels[id] = PendingWrite(value: clamped,
                                         showOSD: showOSD,
                                         sequence: writeSequence)
        lastApplied[id] = RememberedLevel(value: clamped,
                                          fingerprint: Self.displayFingerprint(id))
        levelKnownAt[id] = Date()
        let schedule = !drainScheduled
        if schedule { drainScheduled = true }
        stateLock.unlock()
        guard schedule else { return }
        workQueue.async { [weak self] in
            self?.drainPendingLevels()
        }
    }

    // MARK: - Display power

    var displaySwitchingAvailable: Bool { DisplayConfigurationBridge.configureEnabled != nil }

    func isDisplayPending(_ id: CGDirectDisplayID) -> Bool {
        pendingDisplayIDs.contains(id)
    }

    func canToggleDisplay(_ display: BrightnessDisplay) -> Bool {
        guard displaySwitchingAvailable, !isDisplayPending(display.id) else { return false }
        guard display.isActive else { return true }
        return BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawableDisplays,
                                                  target: display.id)
    }

    /// Enables or disables one connected display without changing the saved
    /// system arrangement. The transaction is app-only and never overwrites
    /// the user's saved display configuration.
    func toggleDisplay(_ display: BrightnessDisplay) {
        guard !isDisplayPending(display.id) else { return }
        guard displaySwitchingAvailable else {
            displayControlFailure = .unavailable
            return
        }
        let targetEnabled = !display.isActive
        if !targetEnabled {
            stateLock.lock()
            let online = knownTopology
            let active = knownActiveTopology
            stateLock.unlock()
            let drawable = Self.drawableDisplayIDs(online: online, active: active)
            guard BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawable,
                                                       target: display.id) else {
                displayControlFailure = .lastActive
                return
            }
        }

        displayControlFailure = nil
        pendingDisplayIDs.insert(display.id)
        workQueue.async { [weak self] in
            guard let self else { return }
            if !targetEnabled {
                let topology = Self.currentTopology()
                let drawable = Self.drawableDisplayIDs(online: topology.online,
                                                       active: topology.active)
                guard BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawable,
                                                           target: display.id) else {
                    self.finishDisplayToggle(id: display.id, enabled: targetEnabled,
                                             failure: .lastActive)
                    return
                }
                // A software-dimmed screen should return with its clean gamma
                // before the saved dim level is reapplied by the rebuild.
                if let baseline = self.gammaBaselines[display.id] {
                    CGSetDisplayTransferByTable(display.id, baseline.count, baseline.red,
                                                baseline.green, baseline.blue)
                }
            }

            // The gamma curve above is work-queue state; the reconfiguration
            // itself belongs to the main thread (see `configureDisplay`).
            DispatchQueue.main.async { [weak self] in
                self?.commitDisplayToggle(display, enabled: targetEnabled)
            }
        }
    }

    /// Second half of `toggleDisplay`, on the main thread: the display
    /// reconfiguration and the bookkeeping that follows it.
    private func commitDisplayToggle(_ display: BrightnessDisplay, enabled: Bool) {
        if !enabled { Self.rememberDisplaySwitchedOff(display.id) }
        guard Self.configureDisplay(display.id, enabled: enabled) else {
            if !enabled { Self.forgetDisplaySwitchedOff(display.id) }
            finishDisplayToggle(id: display.id, enabled: enabled, failure: .failed)
            return
        }

        stateLock.lock()
        pendingLevels.removeValue(forKey: display.id)
        if enabled {
            managedDisabledIDs.remove(display.id)
            managedDisabledDisplays.removeValue(forKey: display.id)
            knownActiveTopology.insert(display.id)
        } else {
            managedDisabledIDs.insert(display.id)
            var disabled = display
            disabled.method = nil
            disabled.isActive = false
            managedDisabledDisplays[display.id] = disabled
            knownActiveTopology.remove(display.id)
        }
        stateLock.unlock()
        // The stored list is written with the lock released, like every other
        // place that touches it. A `UserDefaults` write posts
        // `didChangeNotification`, and the observers registered with
        // `queue: .main` make that post wait for the main thread; held under
        // `stateLock` it waits on a main thread that is itself waiting for the
        // same lock inside `canToggleDisplay`, called from a SwiftUI body
        // (issue #647). Running here on the main thread is what keeps that from
        // happening today, and the thread this runs on is not something the
        // lock should have to depend on.
        if enabled { Self.forgetDisplaySwitchedOff(display.id) }
        finishDisplayToggle(id: display.id, enabled: enabled, failure: nil)
    }

    private func finishDisplayToggle(id: CGDirectDisplayID, enabled: Bool,
                                     failure: DisplayControlFailure?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingDisplayIDs.remove(id)
            self.displayControlFailure = failure
            if failure == nil, let index = self.displays.firstIndex(where: { $0.id == id }) {
                self.displays[index].isActive = enabled
                if !enabled { self.displays[index].method = nil }
                self.refresh()
            }
        }
    }

    /// The active list can include virtual devices with no picture a person
    /// can use. Those must not hide a stranded physical display.
    private static func drawableDisplayIDs(online: Set<CGDirectDisplayID>,
                                           active: Set<CGDirectDisplayID>) -> Set<CGDirectDisplayID> {
        let virtual = Set(online.filter {
            displayInfoDictionary($0)?["kCGDisplayIsVirtualDevice"] as? Bool ?? false
        })
        return BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: online, activeDisplayIDs: active, virtualDisplayIDs: virtual)
    }

    /// Switches one display on or off inside a display reconfiguration
    /// transaction. **Main thread only.** CoreGraphics runs a
    /// reconfiguration's callbacks inline on whichever thread drives the
    /// transaction, and in this process those callbacks are AppKit's: they
    /// rebuild `NSScreen` and post the screen-parameters notification, which
    /// is main-thread work. Driven from the work queue they run off the main
    /// thread while the main thread is itself inside CoreGraphics asking for
    /// the display list, and neither side can finish, so the app freezes with
    /// nothing left that can end it (issue #747). A caller on the wrong
    /// thread is refused and logged rather than allowed to hang.
    private static func configureDisplay(_ id: CGDirectDisplayID, enabled: Bool) -> Bool {
        guard Thread.isMainThread else {
            log.error("refused to reconfigure display \(id) off the main thread")
            return false
        }
        guard let configure = DisplayConfigurationBridge.configureEnabled else { return false }
        var reference: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&reference) == .success,
              let configuration = reference else { return false }
        guard configure(configuration, id, enabled) == 0 else {
            CGCancelDisplayConfiguration(configuration)
            return false
        }
        return CGCompleteDisplayConfiguration(configuration, .forAppOnly) == .success
    }

    private static func activeDisplayIDs() -> Set<CGDirectDisplayID> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Set(ids.prefix(Int(count)))
    }

    private static func currentTopology() -> BrightnessSupport.DisplayTopology {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return BrightnessSupport.DisplayTopology(
            online: Set(ids.prefix(Int(count))),
            active: activeDisplayIDs())
    }

    /// AppKit gives termination hooks only a brief synchronous window. Put
    /// every dimmed picture back first, queued behind any operation already in
    /// flight: leaving one behind is the difference between quitting the app
    /// and a screen that stays dark with nothing left running to explain it.
    /// The reconfigurations then run here, on the main thread AppKit calls
    /// this from, which is where they have to run anyway (see
    /// `configureDisplay`).
    func restoreDisplaysBeforeTermination() {
        workQueue.sync { restoreAllGamma() }
        restoreManagedDisplays()
    }

    /// Switches every display this process disabled back on. Main thread only,
    /// like every other reconfiguration here.
    private func restoreManagedDisplays() {
        stateLock.lock()
        let ids = managedDisabledIDs
        stateLock.unlock()
        for id in ids {
            guard Self.configureDisplay(id, enabled: true) else { continue }
            stateLock.lock()
            managedDisabledIDs.remove(id)
            managedDisabledDisplays.removeValue(forKey: id)
            stateLock.unlock()
            Self.forgetDisplaySwitchedOff(id)
        }
    }

    /// Writes every remembered curve back, skipping any display number that
    /// now belongs to a different monitor. Runs on the work queue.
    private func restoreAllGamma() {
        for (id, baseline) in gammaBaselines
        where Self.displayFingerprint(id) == baseline.fingerprint {
            CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                        baseline.green, baseline.blue)
            Self.log.log("restored gamma baseline for display \(id)")
        }
        gammaBaselines = [:]
        dimmedDisplays = []
    }

    // MARK: - Displays switched off by this app

    /// A display switched off here disappears from the system entirely, and
    /// the row offering to switch it back on lived only in memory. If the app
    /// went away without putting it back, whether by a crash or by being
    /// forced to quit, the only way left was to unplug the screen. The
    /// intention is written down instead, and honoured on the next start.
    private static func rememberDisplaySwitchedOff(_ id: CGDirectDisplayID) {
        var stored = UserDefaults.standard.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        guard !stored.contains(Int(id)) else { return }
        stored.append(Int(id))
        UserDefaults.standard.set(stored, forKey: DefaultsKey.displaysSwitchedOff)
    }

    private static func forgetDisplaySwitchedOff(_ id: CGDirectDisplayID) {
        let stored = UserDefaults.standard.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        let remaining = stored.filter { $0 != Int(id) }
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.displaysSwitchedOff)
        } else {
            UserDefaults.standard.set(remaining, forKey: DefaultsKey.displaysSwitchedOff)
        }
    }

    /// Switches back on anything a previous run left off. Called at startup on
    /// the main thread, before any display work, so a screen is never stranded
    /// between runs. Nothing here belongs to the work queue, and the
    /// reconfiguration itself may not run there (see `configureDisplay`).
    func restoreDisplaysLeftOff() {
        let stored = UserDefaults.standard.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        guard !stored.isEmpty else { return }
        guard DisplayConfigurationBridge.configureEnabled != nil else { return }
        for id in stored {
            // The list is plain numbers on disk and can arrive edited or
            // imported, so anything that is not a display number is skipped
            // rather than converted.
            guard let displayID = CGDirectDisplayID(exactly: id) else { continue }
            guard Self.configureDisplay(displayID, enabled: true) else { continue }
            Self.forgetDisplaySwitchedOff(displayID)
        }
    }

    // MARK: - Brightness keys (follow the pointer)

    private func syncKeyTap() {
        let defaults = UserDefaults.standard
        let wantsKeyRouting = defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
        let wantsBrightnessOSD = defaults.bool(
            forKey: DefaultsKey.brightnessOSDEnabled
        ) && brightnessOSDSupported
        let wanted = running
            && (wantsKeyRouting || wantsBrightnessOSD)
            && Permissions.shared.accessibility
        if wanted { installKeyTap() } else { removeKeyTap() }
        // The plain key press path only earns its keystroke tap when the
        // pointer actually decides the target.
        if wanted, wantsKeyRouting {
            let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys")
            let adjusts = BrightnessSupport.functionKeysAdjustBrightness(symbolicHotKeys: hotKeys)
            let overlayReplaces = wantsBrightnessOSD
            keyThreadLock.withLock {
                functionKeysAdjustBrightness = adjusts
                overlayReplacesNativeOSD = overlayReplaces
            }
            installFunctionKeyTap()
        } else {
            removeFunctionKeyTap()
        }
    }

    private func installKeyTap() {
        guard keyTap == nil else { return }
        let systemDefined = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<BrightnessService>.fromOpaque(userInfo).takeUnretainedValue()
            return service.handleKeyEvent(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        keyTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        keyTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeKeyTap() {
        guard let tap = keyTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let keyTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes)
        }
        keyTapSource = nil
        keyTap = nil
    }

    // MARK: - Brightness keys on other keyboards

    private func installFunctionKeyTap() {
        let thread = keyThreadLock.withLock { () -> Thread? in
            if functionKeyThread != nil {
                if shouldStopFunctionKeyThread { pendingFunctionKeyRestart = true }
                return nil
            }
            shouldStopFunctionKeyThread = false
            pendingFunctionKeyRestart = false
            let thread = Thread { [weak self] in self?.runFunctionKeyTap() }
            thread.name = "Vorssaint Brightness Keys"
            thread.qualityOfService = .userInteractive
            functionKeyThread = thread
            return thread
        }
        thread?.start()
    }

    private func removeFunctionKeyTap() {
        let snapshot = keyThreadLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopFunctionKeyThread = true
            pendingFunctionKeyRestart = false
            swallowedKeyCodes.removeAll()
            return (functionKeyRunLoop, functionKeyTap, functionKeyThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            keyThreadLock.withLock {
                shouldStopFunctionKeyThread = false
                functionKeyThread = nil
            }
        }
    }

    private func runFunctionKeyTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            keyThreadLock.withLock { functionKeyRunLoop = runLoop }
            let stopBeforeCreating = keyThreadLock.withLock { shouldStopFunctionKeyThread }
            guard !stopBeforeCreating else {
                if clearFunctionKeyThread() { installFunctionKeyTap() }
                return
            }
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<BrightnessService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.routeFunctionKey(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearFunctionKeyThread()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            keyThreadLock.withLock { functionKeyTap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            if keyThreadLock.withLock({ shouldStopFunctionKeyThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            if clearFunctionKeyThread() { installFunctionKeyTap() }
        }
    }

    private func clearFunctionKeyThread() -> Bool {
        keyThreadLock.withLock {
            let restart = pendingFunctionKeyRestart
            functionKeyTap = nil
            functionKeyRunLoop = nil
            functionKeyThread = nil
            shouldStopFunctionKeyThread = false
            pendingFunctionKeyRestart = false
            swallowedKeyCodes.removeAll()
            return restart
        }
    }

    /// Runs on the tap thread. The window server holds every keystroke in the
    /// session until this returns, so anything that is not one of the four
    /// brightness codes leaves immediately, and nothing here reads state that
    /// belongs to the main thread: the target display comes from the display
    /// server and the route from behind the state lock.
    private func routeFunctionKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tap = keyThreadLock.withLock { shouldStopFunctionKeyThread ? nil : functionKeyTap }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard BrightnessSupport.isBrightnessKeyCode(keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        // A release is consumed only when its press was, so the system never
        // receives half a key.
        guard type == .keyDown else {
            let consumed = keyThreadLock.withLock { swallowedKeyCodes.remove(keyCode) != nil }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        let adjusts = keyThreadLock.withLock { functionKeysAdjustBrightness }
        let modifiers = event.flags.intersection([.maskCommand, .maskControl,
                                                  .maskAlternate, .maskShift])
        guard let press = BrightnessSupport.brightnessFunctionKeyEvent(
            keyCode: keyCode,
            isKeyDown: true,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            hasModifiers: !modifiers.isEmpty,
            functionKeysAdjustBrightness: adjusts)
        else { return Unmanaged.passUnretained(event) }

        var displayID: CGDirectDisplayID = 0
        var matched: UInt32 = 0
        guard CGGetDisplaysWithPoint(event.location, 1, &displayID, &matched) == .success,
              matched > 0
        else { return Unmanaged.passUnretained(event) }

        stateLock.lock()
        let route = routes[displayID]
        stateLock.unlock()
        guard let route else { return Unmanaged.passUnretained(event) }
        if route.method == .system {
            // Same rule the media keys follow, so both kinds of keyboard
            // behave alike: the built-in panel keeps the system's own handling
            // and its animation unless the app's own overlay replaces it, and
            // every other system-routed display has to be stepped here,
            // because the system only ever moves its native target.
            let overlayReplacesNative = keyThreadLock.withLock { overlayReplacesNativeOSD }
            guard BrightnessSupport.stepsSystemRoutedDisplay(
                followsPointer: true,
                displayIsBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                overlayReplacesNative: overlayReplacesNative
            ), BrightnessBridge.setBrightness != nil else {
                return Unmanaged.passUnretained(event)
            }
        }
        keyThreadLock.withLock { _ = swallowedKeyCodes.insert(keyCode) }
        DispatchQueue.main.async { [weak self] in
            self?.applyKeyStep(press, to: displayID, method: route.method)
        }
        return nil
    }

    /// The actual step, always on the main thread, shared by both key paths.
    private func applyKeyStep(_ press: BrightnessSupport.BrightnessKeyEvent,
                              to displayID: CGDirectDisplayID,
                              method: BrightnessDisplay.Method) {
        let showOSD = UserDefaults.standard.bool(forKey: DefaultsKey.brightnessOSDEnabled)
        step(displayID, method: method, delta: press.delta, showOSD: showOSD)
    }

    /// Moves a display one step from where it actually is.
    ///
    /// A step is only as good as the value it starts from, and a remembered
    /// one goes out of date on its own: the monitor has buttons of its own,
    /// and its level is read once when the routes are built, which can be a
    /// moment when the panel answers badly. Starting from a stale value and
    /// writing the result is what threw a monitor sitting at 80% down to one
    /// step above nothing (issue #370). So a step that follows a pause asks
    /// the monitor where it is first, exactly as the system-routed path
    /// already did; steps in a burst keep using the running value, so holding
    /// a key stays smooth and does not put a read between every press.
    private func step(_ displayID: CGDirectDisplayID,
                      method: BrightnessDisplay.Method,
                      delta: Double,
                      showOSD: Bool) {
        let cached = displays.first(where: { $0.id == displayID })?.brightness
        if method == .system {
            guard let current = currentSystemBrightness(for: displayID, fallback: cached) else { return }
            commitStep(from: current, delta: delta, to: displayID, method: method, showOSD: showOSD)
            return
        }
        stateLock.lock()
        let known = levelKnownAt[displayID]
        let route = routes[displayID]
        stateLock.unlock()
        let fresh = BrightnessSupport.trustsRememberedLevel(lastKnownAt: known, now: Date(),
                                                            window: Self.levelTrustWindow)
        // Gamma dimming is this app's own doing, so the remembered value is
        // the truth by construction and there is nothing to ask.
        guard method == .ddc, route?.ddcReadable == true, !fresh,
              let route, let service = route.service else {
            guard let current = cached else { return }
            commitStep(from: current, delta: delta, to: displayID, method: method, showOSD: showOSD)
            return
        }
        // A press that lands while the monitor is being read joins the step
        // that read is about to commit. Starting a second read instead would
        // begin from the same value the first press has not written yet, and
        // two taps would move the monitor a single step.
        if ddcPendingSteps[displayID] != nil {
            ddcPendingSteps[displayID, default: 0] += delta
            return
        }
        ddcPendingSteps[displayID] = 0
        // Reading a monitor takes long enough to be felt, so it happens off
        // the main thread and the step follows the answer.
        workQueue.async { [weak self] in
            guard let self else { return }
            let probe = self.ddcProbeLuminance(for: displayID, service: service)
            if case .replied = probe {
                self.forgetWriteOnlyDDCPath(route.ddcPathKey)
            } else {
                if case .writeOnly = probe {
                    self.rememberWriteOnlyDDCPath(route.ddcPathKey)
                }
                self.stateLock.lock()
                if self.routes[displayID]?.ddcPathKey == route.ddcPathKey {
                    self.routes[displayID]?.ddcReadable = false
                }
                self.stateLock.unlock()
                Self.log.log("ddc reads stopped answering for display \(displayID); future steps will write only")
            }
            DispatchQueue.main.async {
                let queued = self.ddcPendingSteps.removeValue(forKey: displayID) ?? 0
                var current = cached
                if case let .replied(value, maximum) = probe {
                    let level = BrightnessSupport.normalized(
                        current: value, maximum: BrightnessSupport.sanitizedMaximum(maximum))
                    Self.log.log("display \(displayID) reads \(level) before stepping")
                    current = level
                    if let index = self.displays.firstIndex(where: { $0.id == displayID }) {
                        self.displays[index].brightness = level
                    }
                }
                guard let current else { return }
                self.commitStep(from: current, delta: delta + queued, to: displayID,
                                method: method, showOSD: showOSD)
            }
        }
    }

    private func commitStep(from current: Double,
                            delta: Double,
                            to displayID: CGDirectDisplayID,
                            method: BrightnessDisplay.Method,
                            showOSD: Bool) {
        let stepped = BrightnessSupport.steppedBrightness(current, delta: delta)
        Self.log.log("key step display \(displayID) route \(String(describing: method), privacy: .public) \(current) to \(stepped)")
        setBrightness(stepped, for: displayID, showOSD: showOSD)
    }

    /// Routes a handled brightness key press to the pointer display when that
    /// option is on, otherwise replacing only the system target's overlay.
    /// Both halves are swallowed so the system never performs the same step.
    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              let press = BrightnessSupport.brightnessKeyEvent(subtype: Int(nsEvent.subtype.rawValue),
                                                               data1: nsEvent.data1)
        else { return Unmanaged.passUnretained(event) }

        let defaults = UserDefaults.standard
        let followsPointer = defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
        let wantsBrightnessOSD = defaults.bool(
            forKey: DefaultsKey.brightnessOSDEnabled
        )
        let displayID: CGDirectDisplayID
        if followsPointer {
            let pointer = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: {
                NSMouseInRect(pointer, $0.frame, false)
            }), let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                           as? NSNumber)?.uint32Value else {
                return Unmanaged.passUnretained(event)
            }
            displayID = id
        } else if wantsBrightnessOSD,
                  let systemTarget = displays.first(where: {
                      $0.isBuiltIn && $0.isActive && $0.method == .system
                  }) ?? displays.first(where: {
                      $0.isActive && $0.method == .system
                  }) {
            // With pointer routing off, keep the native target. In clamshell
            // mode this can be a system-managed external display.
            displayID = systemTarget.id
        } else {
            return Unmanaged.passUnretained(event)
        }

        stateLock.lock()
        let route = routes[displayID]
        stateLock.unlock()
        guard let route else { return Unmanaged.passUnretained(event) }
        if route.method == .system {
            // The system's own key handling only ever steps its native
            // target, never the display under the pointer, so a pointer
            // routed press on a system-routed external display (Apple
            // pipeline monitors, or any display in clamshell mode) is
            // stepped here instead of passed through (issue #268).
            // The published list can lag a rebuild by a beat; resolve the
            // panel kind from the display server so a press never lands on
            // the wrong side of the built-in check.
            let isBuiltIn = displays.first(where: { $0.id == displayID })?.isBuiltIn
                ?? (CGDisplayIsBuiltin(displayID) != 0)
            guard BrightnessSupport.stepsSystemRoutedDisplay(
                followsPointer: followsPointer,
                displayIsBuiltIn: isBuiltIn,
                overlayReplacesNative: wantsBrightnessOSD && brightnessOSDSupported
            ), BrightnessBridge.setBrightness != nil else {
                // The built-in panel keeps the system's native brightness
                // handling and animation unless the overlay replaces it.
                return Unmanaged.passUnretained(event)
            }
            if press.isKeyDown, let current = currentSystemBrightness(
                for: displayID,
                fallback: displays.first(where: { $0.id == displayID })?.brightness
            ) {
                let stepped = BrightnessSupport.steppedBrightness(current, delta: press.delta)
                Self.log.log("key step display \(displayID) route system \(current) to \(stepped)")
                setBrightness(stepped, for: displayID, showOSD: wantsBrightnessOSD)
            }
            // Both halves are replaced so the system never draws a second OSD.
            return nil
        }
        guard followsPointer else {
            return Unmanaged.passUnretained(event)
        }
        if press.isKeyDown {
            step(displayID, method: route.method, delta: press.delta, showOSD: wantsBrightnessOSD)
        }
        return nil
    }

    private func currentSystemBrightness(for id: CGDirectDisplayID,
                                         fallback: Double?) -> Double? {
        stateLock.lock()
        let queued = pendingLevels[id]?.value
        let requested = systemWritesInFlight.contains(id) ? rememberedLevel(for: id) : nil
        stateLock.unlock()
        if let queued { return queued }
        if let requested { return requested }
        // Same reason as the rebuild: a sleeping panel answers a number it
        // cannot honour, so the last value known good is the better base.
        var live: Float = -1
        if CGDisplayIsAsleep(id) == 0, let read = BrightnessBridge.getBrightness,
           read(id, &live) == 0, live >= 0, live <= 1 {
            return Double(live)
        }
        return fallback
    }

    // MARK: - Screen changes

    /// EDR ramps fire this notification in storms with no topology change
    /// (over a hundred times in two seconds, measured). Use one fixed settle
    /// window from the first event: resetting it for every notification made
    /// a newly connected display wait behind the whole storm.
    private func screensChanged() {
        guard running, rebuildDebounce == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.rebuildDebounce = nil
            let topology = Self.currentTopology()
            self.stateLock.lock()
            let changed = topology.online != self.knownTopology
                || topology.active != self.knownActiveTopology
            self.stateLock.unlock()
            if changed {
                Self.log.log("topology changed to \(topology.online.sorted().map(String.init).joined(separator: ","), privacy: .public); rebuilding")
                let drawable = Self.drawableDisplayIDs(online: topology.online,
                                                       active: topology.active)
                if !self.restoreManagedDisplayIfHeadless(drawableDisplayIDs: drawable) {
                    self.refresh()
                }
            }
        }
        rebuildDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// A user can intentionally turn off the built-in panel while an external
    /// display remains. If that last active display is then unplugged, there
    /// is no UI left to reverse the choice, so restore one display that this
    /// process disabled and leave every unrelated display configuration alone.
    private func restoreManagedDisplayIfHeadless(drawableDisplayIDs: Set<CGDirectDisplayID>) -> Bool {
        stateLock.lock()
        let candidates = BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: drawableDisplayIDs,
            managedDisabledIDs: managedDisabledIDs,
            builtInDisabledIDs: Set(managedDisabledDisplays.values
                .filter(\.isBuiltIn).map(\.id)))
        stateLock.unlock()
        guard !candidates.isEmpty else { return false }

        pendingDisplayIDs.formUnion(candidates)
        // Already on the main thread, which is where the reconfiguration has
        // to run (see `configureDisplay`); the hop only lets the pending state
        // reach the panel before the transaction blocks it.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var restored: CGDirectDisplayID?
            for id in candidates where Self.configureDisplay(id, enabled: true) {
                restored = id
                break
            }
            if let restored {
                self.stateLock.lock()
                self.managedDisabledIDs.remove(restored)
                self.managedDisabledDisplays.removeValue(forKey: restored)
                self.stateLock.unlock()
                Self.forgetDisplaySwitchedOff(restored)
                Self.log.log("restored display \(restored) after the active display set became empty")
            } else {
                Self.log.error("could not restore a display after the active display set became empty")
            }
            self.pendingDisplayIDs.subtract(candidates)
            self.displayControlFailure = restored == nil ? .failed : nil
            self.refresh(force: true)
        }
        return true
    }

    // MARK: - Waking up

    /// Sleep takes the connection to every external monitor down with it, and
    /// the channel this app speaks to each one through is a new one once the
    /// connection returns. The channels held from before the sleep then lead
    /// nowhere: the sliders and the brightness keys go through the motions
    /// and the monitor never hears any of it, until opening the panel looks
    /// everything up again. Nothing else can catch this, because the list of
    /// displays is exactly the same on both sides of the sleep and the check
    /// above has nothing to compare. Waking is the signal (issue #366).
    private func installWakeObservers() {
        guard wakeObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.didWakeNotification,
                         NSWorkspace.screensDidWakeNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.displaysWokeUp()
            }
        }
    }

    private func removeWakeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in wakeObservers { workspace.removeObserver(observer) }
        wakeObservers = []
        wakeRebuild?.cancel()
        wakeRebuild = nil
    }

    /// One wake arrives as both notifications, and the screens usually wake a
    /// moment before the monitors have finished negotiating, so the two fold
    /// into a single pass that waits for the connections to settle.
    private func displaysWokeUp() {
        guard running else { return }
        wakeRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            Self.log.log("woke from sleep; rebuilding display routes")
            self.refresh(force: true)
        }
        wakeRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeSettleDelay, execute: work)
    }

    // MARK: - Rebuild (work queue)

    private func rebuild(generation: Int, previousDisplays: [BrightnessDisplay],
                         screenNames: [CGDirectDisplayID: String]) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let onlineIDs = Array(ids.prefix(Int(count)))

        let seenTopology = Set(onlineIDs)
        let activeTopology = Self.activeDisplayIDs()
        var built: [BrightnessDisplay] = []
        var newRoutes: [CGDirectDisplayID: Route] = [:]
        var ddcCandidates: [(index: Int, identity: BrightnessSupport.DisplayIdentity)] = []
        var virtualIDs = Set<CGDirectDisplayID>()

        for id in onlineIDs {
            let info = Self.displayInfoDictionary(id)
            // Read before the mirroring guard below, so the snapshot the panel
            // decides from covers every online display, exactly like the live
            // reading it replaces.
            if (info?["kCGDisplayIsVirtualDevice"] as? Bool ?? false) { virtualIDs.insert(id) }
            // A mirroring display follows its source; the source's slider is
            // the real control.
            guard CGDisplayMirrorsDisplay(id) == 0 else { continue }
            if let info,
               (info["kCGDisplayIsVirtualDevice"] as? Bool ?? false)
                || (info["kCGDisplayIsAirPlay"] as? Bool ?? false) {
                continue
            }
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = Self.displayName(id, info: info, screenNames: screenNames)
            let isActive = activeTopology.contains(id)

            if !isActive {
                stateLock.lock()
                let level = rememberedLevel(for: id) ?? 1.0
                stateLock.unlock()
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: nil, isActive: false,
                                               brightness: level, readable: false))
                continue
            }

            // A panel that is asleep answers a reading it cannot honour, and
            // it has been measured answering zero for a display sitting at a
            // third of its range. Taking that as the truth is what leaves a
            // later key press stepping up from nothing (issue #370).
            let asleep = CGDisplayIsAsleep(id) != 0
            var level: Float = -1
            if let read = BrightnessBridge.getBrightness,
               read(id, &level) == 0, level >= 0, level <= 1 {
                // The system pipeline answers for this display (built-in
                // panel or an Apple external display). A reading taken while
                // the panel sleeps is kept out of the remembered level: it
                // has been measured answering zero for a display sitting at a
                // third of its range, and a later key press would step up
                // from that nothing (issue #370).
                stateLock.lock()
                let remembered = rememberedLevel(for: id)
                stateLock.unlock()
                let trusted = asleep ? (remembered ?? Double(level)) : Double(level)
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: .system, isActive: true,
                                               brightness: trusted, readable: !asleep))
                newRoutes[id] = Route(method: .system, service: nil, maximum: 100)
                if !asleep {
                    stateLock.lock()
                    levelKnownAt[id] = Date()
                    stateLock.unlock()
                }
                continue
            }
            guard !isBuiltIn else { continue }
            ddcCandidates.append((built.count, Self.displayIdentity(id, info: info)))
            // Placeholder; the DDC pass below fills brightness and route.
            built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: false,
                                           method: .ddc, isActive: true,
                                           brightness: 0.5, readable: false))
        }

        let drawableIDs = BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: seenTopology, activeDisplayIDs: activeTopology,
            virtualDisplayIDs: virtualIDs)

        stateLock.lock()
        let disabledSnapshots = managedDisabledDisplays
        // Still the previous rebuild's set at this point: what was not in it
        // just arrived, or returned from a connection gap.
        let previousTopology = knownTopology
        let topologyChanged = seenTopology != knownTopology
            || activeTopology != knownActiveTopology
        let canPublishDiscovery = generation == rebuildGeneration && topologyChanged
        if canPublishDiscovery {
            // The power control only becomes safe when it sees the new active
            // set. Brightness routes remain untouched until probing finishes.
            knownTopology = seenTopology
            knownActiveTopology = activeTopology
        }
        stateLock.unlock()
        for (id, display) in disabledSnapshots where !seenTopology.contains(id) {
            built.append(display)
        }

        if canPublishDiscovery {
            let previousByID = Dictionary(uniqueKeysWithValues: previousDisplays.map { ($0.id, $0) })
            let discovered = built.map { display -> BrightnessDisplay in
                guard display.isActive,
                      let previous = previousByID[display.id], previous.isActive else {
                    var pending = display
                    if pending.isActive { pending.method = nil }
                    return pending
                }
                return BrightnessDisplay(id: display.id, name: display.name,
                                         isBuiltIn: display.isBuiltIn,
                                         method: previous.method, isActive: true,
                                         brightness: previous.brightness,
                                         readable: previous.readable)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, generation == self.rebuildGeneration else { return }
                if self.displays != discovered { self.displays = discovered }
                if self.drawableDisplays != drawableIDs { self.drawableDisplays = drawableIDs }
            }
        }

        // DDC pass: walk the IORegistry once, score services against the
        // remaining displays and read each matched monitor's brightness.
        // Whatever ends up without a live DDC channel falls back to gamma
        // dimming, so every real display keeps a working slider.
        var softwareIndices = Set(ddcCandidates.map(\.index))
        if !ddcCandidates.isEmpty, BrightnessBridge.ddcAvailable {
            let services = Self.externalServices()
            var scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)] = []
            for candidate in ddcCandidates {
                for service in services {
                    scores.append((candidate.index, service.identity.ordinal,
                                   BrightnessSupport.matchScore(service: service.identity,
                                                                display: candidate.identity)))
                }
            }
            var assignment = BrightnessSupport.assignServices(scores: scores)
            // One display and one service left unmatched can only belong to
            // each other (EDID data is sometimes too sparse to score).
            if assignment.isEmpty, ddcCandidates.count == 1, services.count == 1 {
                assignment = [ddcCandidates[0].index: services[0].identity.ordinal]
            }
            for candidate in ddcCandidates {
                guard let ordinal = assignment[candidate.index],
                      let matched = services.first(where: { $0.identity.ordinal == ordinal }) else {
                    continue
                }
                let id = built[candidate.index].id
                let ioDisplayLocation = candidate.identity.ioDisplayLocation.flatMap {
                    $0.isEmpty ? nil : $0
                } ?? matched.identity.ioDisplayLocation
                let pathKey = BrightnessSupport.ddcPathKey(
                    displayFingerprint: Self.displayFingerprint(id),
                    ioDisplayLocation: ioDisplayLocation)
                let rememberedWriteOnly = !BrightnessSupport.shouldProbeDDC(
                    pathKey: pathKey, writeOnlyPaths: writeOnlyDDCPaths())
                let probe: DDCProbe
                if rememberedWriteOnly {
                    probe = .writeOnly
                    Self.log.log("ddc cached display \(id): writeOnly")
                } else {
                    probe = ddcProbeLuminance(for: id, service: matched.service,
                                              classifyingChannel: true)
                    Self.log.log("ddc probe display \(id): \(String(describing: probe), privacy: .public)")
                }
                switch probe {
                case .replied(let current, let maximum):
                    forgetWriteOnlyDDCPath(pathKey)
                    let ceiling = BrightnessSupport.sanitizedMaximum(maximum)
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, isActive: true,
                        brightness: BrightnessSupport.normalized(current: current,
                                                                 maximum: ceiling),
                        readable: true)
                    newRoutes[id] = Route(method: .ddc, service: matched.service,
                                          maximum: ceiling, ddcReadable: true,
                                          ddcPathKey: pathKey)
                    stateLock.lock()
                    levelKnownAt[id] = Date()
                    stateLock.unlock()
                    softwareIndices.remove(candidate.index)
                case .writeOnly:
                    rememberWriteOnlyDDCPath(pathKey)
                    // Reads fail on some monitors whose writes still work:
                    // keep the slider, seeded from this session's last value.
                    stateLock.lock()
                    let seed = rememberedLevel(for: id) ?? 0.5
                    stateLock.unlock()
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, isActive: true, brightness: seed, readable: false)
                    newRoutes[id] = Route(method: .ddc, service: matched.service,
                                          maximum: 100, ddcPathKey: pathKey)
                    softwareIndices.remove(candidate.index)
                case .dead:
                    forgetWriteOnlyDDCPath(pathKey)
                    // The channel rejects every write (typically an HDMI
                    // conversion in the path): dim in the video pipeline
                    // instead, which works on any connection.
                    break
                }
            }
        }

        // Software route for everything left over: capture the display's
        // clean gamma curve and put back a dim this app applied itself
        // (reconfigurations and wake reset gamma behind our back).
        // A display that drops off for a moment, which is what a hub
        // renegotiating or a cable settling looks like, comes back needing
        // the same untouched curve it had before. Forgetting it here is what
        // would force a fresh reading from a screen that is still dimmed, so
        // curves are kept across the gap and only trimmed once far more have
        // piled up than any desk has monitors.
        if gammaBaselines.count > Self.rememberedGammaBaselines {
            gammaBaselines = gammaBaselines.filter { seenTopology.contains($0.key) }
        }
        for index in softwareIndices.sorted() {
            let id = built[index].id
            stateLock.lock()
            var value = BrightnessSupport.softwareDimToRestore(
                remembered: rememberedLevel(for: id),
                appliedByApp: dimmedDisplays.contains(id))
            stateLock.unlock()
            captureGammaBaselineIfNeeded(id)
            guard gammaBaselines[id] != nil else { continue }
            // A display that was not here a moment ago may have been
            // replugged precisely to recover a black picture, so the saved
            // dim returns floored to a visible level (issue #301).
            if !previousTopology.contains(id) {
                let floored = BrightnessSupport.reconnectedDimLevel(value)
                if floored != value {
                    Self.log.log("display \(id) returned dimmed to \(value); raising to \(floored)")
                    value = floored
                }
            }
            built[index] = BrightnessDisplay(
                id: id, name: built[index].name, isBuiltIn: false,
                method: .software, isActive: true, brightness: value, readable: true)
            newRoutes[id] = Route(method: .software, service: nil, maximum: 100)
            if value < 0.999 { _ = applySoftwareDim(id, value: value) }
        }
        var resolved: [BrightnessDisplay] = []
        var supportsBrightnessOSD = false
        let stale: Bool
        stateLock.lock()
        stale = generation != rebuildGeneration
        if !stale {
            resolved = built.compactMap { display -> BrightnessDisplay? in
                if !display.isActive || newRoutes[display.id] != nil { return display }
                // Even without a brightness route, an active physical display is
                // useful in the generalized Displays surface when it can be
                // switched on or off.
                guard DisplayConfigurationBridge.configureEnabled != nil else { return nil }
                var display = display
                display.method = nil
                return display
            }
            for index in resolved.indices {
                let id = resolved[index].id
                resolved[index].brightness = BrightnessSupport.brightnessAfterRebuild(
                    probed: resolved[index].brightness,
                    pending: pendingLevels[id]?.value)
            }
            supportsBrightnessOSD = resolved.contains { display in
                guard display.isActive, newRoutes[display.id] != nil else { return false }
                switch display.method {
                case .system:
                    return BrightnessBridge.setBrightness != nil
                case .ddc, .software:
                    return true
                case nil:
                    return false
                }
            }
            routes = newRoutes
            knownTopology = seenTopology
            knownActiveTopology = activeTopology
            rebuildingTopology = nil
            managedDisabledIDs.subtract(activeTopology)
            for id in activeTopology {
                managedDisabledDisplays.removeValue(forKey: id)
            }
            for display in resolved where display.method != nil {
                lastApplied[display.id] = RememberedLevel(
                    value: display.brightness,
                    fingerprint: Self.displayFingerprint(display.id))
            }
        }
        stateLock.unlock()
        guard !stale else { return }
        for display in resolved where display.isActive {
            let route = display.method.map { String(describing: $0) } ?? "none"
            Self.log.log("display \(display.id) [\(Self.displayFingerprint(display.id), privacy: .public)] route \(route, privacy: .public) level \(display.brightness)")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, generation == self.rebuildGeneration else { return }
            if self.displays != resolved { self.displays = resolved }
            if self.drawableDisplays != drawableIDs { self.drawableDisplays = drawableIDs }
            if self.brightnessOSDSupported != supportsBrightnessOSD {
                self.brightnessOSDSupported = supportsBrightnessOSD
            }
            self.refreshKeyboardLight()
            self.syncKeyTap()
        }
    }

    // MARK: - Writes (work queue)

    private func drainPendingLevels() {
        while true {
            stateLock.lock()
            guard let (id, pending) = pendingLevels.first else {
                drainScheduled = false
                stateLock.unlock()
                return
            }
            pendingLevels.removeValue(forKey: id)
            let value = pending.value
            let osdLevel = pending.showOSD ? value : nil
            let route = routes[id]
            let writeGeneration = rebuildGeneration
            if route?.method == .system { systemWritesInFlight.insert(id) }
            stateLock.unlock()
            guard let route else { continue }
            var writeSucceeded = false
            switch route.method {
            case .system:
                writeSucceeded = BrightnessBridge.setBrightness?(id, Float(value)) == 0
            case .ddc:
                guard let service = route.service else { continue }
                let deviceValue = BrightnessSupport.deviceValue(for: value,
                                                                maximum: route.maximum)
                let packet = BrightnessSupport.writePacket(
                    code: BrightnessSupport.luminanceCode,
                    value: deviceValue)
                writeSucceeded = ddcSend(to: id, service: service, packet: packet)
            case .software:
                writeSucceeded = applySoftwareDim(id, value: value)
            }
            Self.log.log("wrote display \(id) route \(String(describing: route.method), privacy: .public) level \(value) ok \(writeSucceeded)")
            if route.method == .ddc, !writeSucceeded, route.ddcReadable == false,
               let pathKey = route.ddcPathKey {
                forgetWriteOnlyDDCPath(pathKey)
                DispatchQueue.main.async { [weak self] in
                    self?.refresh(force: true)
                }
            }
            if route.method == .system {
                stateLock.lock()
                if pendingLevels[id] == nil { systemWritesInFlight.remove(id) }
                stateLock.unlock()
            }
            if writeSucceeded, let osdLevel {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running,
                          UserDefaults.standard.bool(
                              forKey: DefaultsKey.brightnessOSDEnabled
                          ) else { return }
                    self.stateLock.lock()
                    let current = self.rebuildGeneration
                    let latestWrite = self.writeSequence
                    self.stateLock.unlock()
                    guard current == writeGeneration,
                          latestWrite == pending.sequence else { return }
                    BrightnessOSD.show(displayID: id,
                                       brightness: osdLevel)
                }
            }
        }
    }

    // MARK: - Software dimming (work queue)

    /// Remembers the display's untouched curve, once. While a dim is applied
    /// the live table is a scaled copy of it, and after a reconnection there
    /// is no way to tell a scaled copy from the real thing.
    private func captureGammaBaselineIfNeeded(_ id: CGDirectDisplayID) {
        let fingerprint = Self.displayFingerprint(id)
        // A curve is only read while the screen is still showing its own. Once
        // a dim is applied the live curve is a scaled copy, and reading that
        // back would take the dim as the new normal and darken the screen
        // again on every reconnection until it is black. A display this app is
        // not dimming is read again, so a colour profile the user changes, or
        // a warm evening tint, becomes what everything else scales from.
        if gammaBaselines[id]?.fingerprint == fingerprint, dimmedDisplays.contains(id) { return }
        let capacity = 256
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, UInt32(capacity), &red, &green, &blue,
                                          &sampleCount) == .success,
              sampleCount > 0 else { return }
        let count = Int(min(sampleCount, UInt32(capacity)))
        gammaBaselines[id] = GammaTable(red: Array(red.prefix(count)),
                                        green: Array(green.prefix(count)),
                                        blue: Array(blue.prefix(count)),
                                        count: UInt32(count),
                                        fingerprint: fingerprint)
        Self.log.log("captured gamma baseline for display \(id) [\(fingerprint, privacy: .public)], peak \(red[count - 1])")
    }

    @discardableResult
    private func applySoftwareDim(_ id: CGDirectDisplayID, value: Double) -> Bool {
        guard let baseline = gammaBaselines[id],
              baseline.fingerprint == Self.displayFingerprint(id) else { return false }
        if value >= 0.999 {
            let restored = CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                                       baseline.green, baseline.blue) == .success
            if restored { dimmedDisplays.remove(id) }
            return restored
        }
        let factor = BrightnessSupport.softwareDimFactor(for: value)
        let red = BrightnessSupport.scaledGammaTable(baseline.red, factor: factor)
        let green = BrightnessSupport.scaledGammaTable(baseline.green, factor: factor)
        let blue = BrightnessSupport.scaledGammaTable(baseline.blue, factor: factor)
        let applied = CGSetDisplayTransferByTable(id, baseline.count, red, green, blue) == .success
        if applied { dimmedDisplays.insert(id) }
        return applied
    }

    // MARK: - DDC transactions (work queue)

    /// Holds the standard's 50ms gap between whole commands to one display.
    /// The pauses inside a command are not enough on their own: without this
    /// gap a slider drag chains commands at the write pause, and monitors
    /// exist that answer a stream that fast by dropping their signal until
    /// they are power cycled (issue #301).
    private func paceDDCCommand(for id: CGDirectDisplayID) {
        let now = DispatchTime.now().uptimeNanoseconds / 1_000
        let delay = BrightnessSupport.ddcCommandDelay(
            nowMicroseconds: now,
            lastCommandEndMicroseconds: ddcCommandEnds[id])
        if delay > 0 { usleep(delay) }
    }

    private func recordDDCCommandEnd(for id: CGDirectDisplayID) {
        ddcCommandEnds[id] = DispatchTime.now().uptimeNanoseconds / 1_000
    }

    private func ddcSend(to id: CGDirectDisplayID, service: CFTypeRef, packet: [UInt8]) -> Bool {
        guard let write = BrightnessBridge.writeI2C else { return false }
        paceDDCCommand(for: id)
        defer { recordDDCCommandEnd(for: id) }
        var bytes = packet
        var success = false
        for attempt in 0...BrightnessSupport.retryAttempts {
            for _ in 0..<BrightnessSupport.writeCycles {
                usleep(BrightnessSupport.writePauseMicroseconds)
                let accepted = write(service, BrightnessSupport.chipAddress,
                                     BrightnessSupport.dataAddress,
                                     &bytes, UInt32(bytes.count)) == KERN_SUCCESS
                success = accepted || success
            }
            if success { return true }
            if attempt < BrightnessSupport.retryAttempts {
                usleep(BrightnessSupport.retryPauseMicroseconds)
            }
        }
        return success
    }

    private enum DDCProbe {
        case replied(current: UInt16, maximum: UInt16)
        case writeOnly
        case dead
    }

    private func writeOnlyDDCPaths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessDDCWriteOnlyPaths
        ) ?? [])
    }

    private func rememberWriteOnlyDDCPath(_ path: String?) {
        guard let path else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) ?? []
        let updated = BrightnessSupport.updatedWriteOnlyDDCPaths(
            stored, path: path, isWriteOnly: true)
        if updated != stored {
            defaults.set(updated, forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
        }
    }

    private func forgetWriteOnlyDDCPath(_ path: String?) {
        guard let path else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) ?? []
        let updated = BrightnessSupport.updatedWriteOnlyDDCPaths(
            stored, path: path, isWriteOnly: false)
        if updated != stored {
            defaults.set(updated, forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
        }
    }

    /// Reads the monitor's luminance while also judging the channel itself:
    /// the request write's own return value is the only reliable signal of a
    /// path that cannot carry DDC at all (HDMI conversions reject every
    /// write, while their reads "succeed" with cached EDID bytes).
    private func ddcProbeLuminance(for id: CGDirectDisplayID,
                                   service: CFTypeRef,
                                   classifyingChannel: Bool = false) -> DDCProbe {
        guard let write = BrightnessBridge.writeI2C,
              let read = BrightnessBridge.readI2C else { return .dead }
        paceDDCCommand(for: id)
        defer { recordDDCCommandEnd(for: id) }
        var request = BrightnessSupport.readRequestPacket(code: BrightnessSupport.luminanceCode)
        var writeAccepted = false
        let attempts = BrightnessSupport.ddcProbeAttempts()
        let writeCycles = BrightnessSupport.ddcProbeWriteCycles(
            classifyingChannel: classifyingChannel)
        for attempt in 0..<attempts {
            for _ in 0..<writeCycles {
                usleep(BrightnessSupport.writePauseMicroseconds)
                if write(service, BrightnessSupport.chipAddress,
                         BrightnessSupport.dataAddress,
                         &request, UInt32(request.count)) == KERN_SUCCESS {
                    writeAccepted = true
                }
            }
            usleep(BrightnessSupport.readPauseMicroseconds)
            var reply = [UInt8](repeating: 0, count: BrightnessSupport.replyLength)
            if read(service, BrightnessSupport.chipAddress, 0,
                    &reply, UInt32(reply.count)) == KERN_SUCCESS,
               let parsed = BrightnessSupport.parseReply(reply) {
                return .replied(current: parsed.current, maximum: parsed.maximum)
            }
            if attempt + 1 < attempts {
                usleep(BrightnessSupport.retryPauseMicroseconds)
            }
        }
        switch BrightnessSupport.channelOutcome(writeAccepted: writeAccepted, replyParsed: false) {
        case .writeOnly: return .writeOnly
        case .live, .dead: return .dead
        }
    }

    // MARK: - Display identity

    private static func displayInfoDictionary(_ id: CGDirectDisplayID) -> NSDictionary? {
        guard let create = BrightnessBridge.createInfoDictionary else { return nil }
        return create(id)?.takeRetainedValue() as NSDictionary?
    }

    private static func displayName(_ id: CGDirectDisplayID, info: NSDictionary?,
                                    screenNames: [CGDirectDisplayID: String]) -> String {
        if let name = screenNames[id] { return name }
        if let names = info?["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value {
            return name
        }
        return "Display"
    }

    private static func displayIdentity(_ id: CGDirectDisplayID,
                                        info: NSDictionary?) -> BrightnessSupport.DisplayIdentity {
        var identity = BrightnessSupport.DisplayIdentity()
        guard let info else { return identity }
        identity.vendorID = (info[kDisplayVendorID] as? NSNumber)?.int64Value
        identity.productID = (info[kDisplayProductID] as? NSNumber)?.int64Value
        identity.weekOfManufacture = (info[kDisplayWeekOfManufacture] as? NSNumber)?.int64Value
        identity.yearOfManufacture = (info[kDisplayYearOfManufacture] as? NSNumber)?.int64Value
        identity.horizontalImageSize = (info[kDisplayHorizontalImageSize] as? NSNumber)?.int64Value
        identity.verticalImageSize = (info[kDisplayVerticalImageSize] as? NSNumber)?.int64Value
        identity.ioDisplayLocation = info[kIODisplayLocationKey] as? String
        if let names = info["DisplayProductName"] as? [String: String] {
            identity.productName = names["en_US"] ?? names.first?.value
        }
        identity.serialNumber = (info[kDisplaySerialNumber] as? NSNumber)?.int64Value
        return identity
    }

    // MARK: - IORegistry walk

    private struct ExternalService {
        var identity: BrightnessSupport.ServiceIdentity
        var service: CFTypeRef
    }

    /// External displays hang off the IORegistry as a framebuffer entry
    /// (identity: EDID UUID, product attributes) followed by its AV service
    /// proxy (the I2C endpoint, tagged with its location). Only proxies
    /// marked External accept DDC; the built-in panel's proxy is Embedded.
    private static func externalServices() -> [ExternalService] {
        guard let createWithService = BrightnessBridge.createWithService else { return [] }
        var results: [ExternalService] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var pending = BrightnessSupport.ServiceIdentity()
        var ordinal = 0
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                ordinal += 1
                pending = BrightnessSupport.ServiceIdentity()
                pending.ordinal = ordinal
                if let uuid = Self.property(entry, "EDID UUID") as? String {
                    pending.edidUUID = uuid
                }
                var path = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
                    pending.ioDisplayLocation = String(cString: path)
                }
                if let attributes = Self.property(entry, "DisplayAttributes") as? NSDictionary,
                   let product = attributes["ProductAttributes"] as? NSDictionary {
                    pending.productName = product["ProductName"] as? String ?? ""
                    pending.serialNumber = (product["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                }
            } else if name == "DCPAVServiceProxy" {
                guard let location = Self.property(entry, "Location") as? String,
                      location == "External",
                      let service = createWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                else { continue }
                results.append(ExternalService(identity: pending, service: service))
            }
        }
        return results
    }

    private static func property(_ entry: io_service_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively))?
            .takeRetainedValue()
    }
}

// MARK: - Private symbol bridge

/// The brightness pipelines have no public API. Every symbol resolves once
/// through dlopen/dlsym and the feature degrades gracefully wherever one is
/// missing: no system brightness symbol means no built-in slider, no I2C
/// symbols mean no external sliders, never a crash.
private enum BrightnessBridge {
    typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32
    typealias CreateInfoDictionaryFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias WriteI2CFn = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias ReadI2CFn = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let displayServicesHandle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let coreDisplayHandle = dlopen(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

    static let getBrightness: GetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesGetBrightness")
    static let setBrightness: SetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesSetBrightness")
    static let createInfoDictionary: CreateInfoDictionaryFn? =
        symbol(coreDisplayHandle, "CoreDisplay_DisplayCreateInfoDictionary")
    static let createWithService: CreateWithServiceFn? =
        symbol(coreDisplayHandle, "IOAVServiceCreateWithService")
    static let writeI2C: WriteI2CFn? =
        symbol(coreDisplayHandle, "IOAVServiceWriteI2C")
    static let readI2C: ReadI2CFn? =
        symbol(coreDisplayHandle, "IOAVServiceReadI2C")

    static var ddcAvailable: Bool {
        createWithService != nil && writeI2C != nil && readI2C != nil
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/// Keyboard backlighting has no public setter. Resolve the system client and
/// its methods at runtime so unsupported hardware or a future removal simply
/// hides the control instead of affecting launch.
private final class KeyboardLightBridge {
    private typealias CopyIDsFn = @convention(c) (NSObject, Selector) -> Unmanaged<AnyObject>
    private typealias IsBuiltInFn = @convention(c) (NSObject, Selector, UInt64) -> ObjCBool
    private typealias GetBrightnessFn = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetBrightnessFn = @convention(c)
        (NSObject, Selector, Float, Int32, Bool, UInt64) -> ObjCBool
    private typealias SuspendIdleDimmingFn = @convention(c)
        (NSObject, Selector, Bool, UInt64) -> ObjCBool

    private let client: NSObject
    private let keyboardID: UInt64
    private let getBrightness: GetBrightnessFn
    private let setBrightnessValue: SetBrightnessFn
    private let suspendIdleDimming: SuspendIdleDimmingFn
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString(
        "setBrightness:fadeSpeed:commit:forKeyboard:")
    private let suspendSelector = NSSelectorFromString("suspendIdleDimming:forKeyboard:")

    init?() {
        guard let framework = Bundle(
            path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              framework.load(),
              let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }

        let client = clientClass.init()
        let copySelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        guard let copyIDs: CopyIDsFn = Self.implementation(
            client, selector: copySelector, as: CopyIDsFn.self),
              let isBuiltIn: IsBuiltInFn = Self.implementation(
                client, selector: builtInSelector, as: IsBuiltInFn.self),
              let getBrightness: GetBrightnessFn = Self.implementation(
                client, selector: getSelector, as: GetBrightnessFn.self),
              let setBrightness: SetBrightnessFn = Self.implementation(
                client, selector: setSelector, as: SetBrightnessFn.self),
              let suspendIdleDimming: SuspendIdleDimmingFn = Self.implementation(
                client, selector: suspendSelector, as: SuspendIdleDimmingFn.self),
              let ids = copyIDs(client, copySelector).takeRetainedValue() as? [NSNumber],
              let keyboardID = ids.map(\.uint64Value).first(where: {
                  isBuiltIn(client, builtInSelector, $0).boolValue
              })
        else { return nil }

        self.client = client
        self.keyboardID = keyboardID
        self.getBrightness = getBrightness
        self.setBrightnessValue = setBrightness
        self.suspendIdleDimming = suspendIdleDimming
    }

    func brightness() -> Float {
        getBrightness(client, getSelector, keyboardID)
    }

    func setBrightness(_ value: Float) -> Bool {
        _ = suspendIdleDimming(client, suspendSelector, true, keyboardID)
        defer { _ = suspendIdleDimming(client, suspendSelector, false, keyboardID) }
        return setBrightnessValue(client, setSelector, min(max(value, 0), 1), 350,
                                  true, keyboardID).boolValue
    }

    private static func implementation<Function>(
        _ object: NSObject,
        selector: Selector,
        as type: Function.Type
    ) -> Function? {
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: type)
    }
}

/// CoreGraphics exposes display reconfiguration publicly but keeps the one
/// operation that marks a connected display enabled or disabled private. The
/// symbol is resolved dynamically so an OS that removes it simply disables
/// the button instead of preventing the app from launching.
private enum DisplayConfigurationBridge {
    typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef, UInt32, Bool) -> Int32

    private static let coreGraphicsHandle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    static let configureEnabled: ConfigureEnabledFn? = {
        guard let coreGraphicsHandle,
              let pointer = dlsym(coreGraphicsHandle, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(pointer, to: ConfigureEnabledFn.self)
    }()
}
