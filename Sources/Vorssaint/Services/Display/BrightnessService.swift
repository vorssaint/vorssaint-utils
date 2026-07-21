// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.graphics

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
/// While the feature is off nothing exists here: no observers, no services,
/// no I2C traffic. While it is on, the only standing resource is one screen
/// change observer; everything else happens when a slider moves or a panel
/// opens. All I2C work runs on a serial queue with the pacing displays need,
/// and slider drags coalesce to the newest value per display.
final class BrightnessService: ObservableObject {
    static let shared = BrightnessService()

    @Published private(set) var displays: [BrightnessDisplay] = []
    @Published private(set) var pendingDisplayIDs = Set<CGDirectDisplayID>()
    @Published private(set) var displayControlFailure: DisplayControlFailure?
    @Published private(set) var brightnessOSDSupported = false

    enum DisplayControlFailure: Equatable {
        case unavailable
        case lastActive
        case failed
    }

    private struct Route {
        var method: BrightnessDisplay.Method
        var service: CFTypeRef?
        var maximum: UInt16
    }

    private var screenObserver: NSObjectProtocol?
    private var rebuildDebounce: DispatchWorkItem?
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
    private var drainScheduled = false
    /// Session memory for write-only monitors, so their slider does not jump
    /// back to a placeholder between panel openings.
    private var lastApplied: [CGDirectDisplayID: Double] = [:]
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
    /// Stale rebuilds (an unplug mid-scan) must not overwrite fresh state.
    private var rebuildGeneration = 0

    private init() {}

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
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        removeKeyTap()
        removeFunctionKeyTap()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        rebuildDebounce?.cancel()
        rebuildDebounce = nil
        stateLock.lock()
        rebuildGeneration += 1
        routes = [:]
        pendingLevels = [:]
        writeSequence = 0
        systemWritesInFlight = []
        lastApplied = [:]
        knownTopology = []
        knownActiveTopology = []
        stateLock.unlock()
        pendingDisplayIDs = []
        displayControlFailure = nil
        brightnessOSDSupported = false
        BrightnessOSD.teardown()
        if !displays.isEmpty { displays = [] }
        // Restore displays and gamma on the work queue, AFTER any operation
        // already in flight. Normal app termination uses the synchronous
        // restoration below; gamma also reverts with the process.
        workQueue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let displaysToRestore = self.managedDisabledIDs
            self.managedDisabledIDs = []
            self.managedDisabledDisplays = [:]
            self.stateLock.unlock()
            for id in displaysToRestore {
                _ = Self.configureDisplay(id, enabled: true)
            }
            Self.forgetDisplaysSwitchedOff()
            self.restoreAllGamma()
        }
    }

    /// Re-reads every display. Called when the panel section or the Settings
    /// page appears, so the sliders match changes made elsewhere (brightness
    /// keys, System Settings, the monitor's own buttons).
    func refresh() {
        guard running else { return }
        stateLock.lock()
        rebuildGeneration += 1
        let generation = rebuildGeneration
        stateLock.unlock()
        workQueue.async { [weak self] in
            self?.rebuild(generation: generation)
        }
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
        lastApplied[id] = clamped
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
        stateLock.lock()
        let active = knownActiveTopology
        stateLock.unlock()
        return BrightnessSupport.canDisableDisplay(activeDisplayIDs: active, target: display.id)
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
            let active = knownActiveTopology
            stateLock.unlock()
            guard BrightnessSupport.canDisableDisplay(activeDisplayIDs: active,
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
                let active = Self.activeDisplayIDs()
                guard BrightnessSupport.canDisableDisplay(activeDisplayIDs: active,
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

            guard Self.configureDisplay(display.id, enabled: targetEnabled) else {
                self.finishDisplayToggle(id: display.id, enabled: targetEnabled,
                                         failure: .failed)
                return
            }

            self.stateLock.lock()
            self.pendingLevels.removeValue(forKey: display.id)
            if targetEnabled {
                self.managedDisabledIDs.remove(display.id)
                self.managedDisabledDisplays.removeValue(forKey: display.id)
                self.knownActiveTopology.insert(display.id)
                Self.forgetDisplaySwitchedOff(display.id)
            } else {
                self.managedDisabledIDs.insert(display.id)
                Self.rememberDisplaySwitchedOff(display.id)
                var disabled = display
                disabled.method = nil
                disabled.isActive = false
                self.managedDisabledDisplays[display.id] = disabled
                self.knownActiveTopology.remove(display.id)
            }
            self.stateLock.unlock()
            self.finishDisplayToggle(id: display.id, enabled: targetEnabled, failure: nil)
        }
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

    private static func configureDisplay(_ id: CGDirectDisplayID, enabled: Bool) -> Bool {
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

    /// AppKit gives termination hooks only a brief synchronous window. Queue
    /// behind any toggle already in flight, then restore every display this
    /// process disabled before the process exits.
    func restoreDisplaysBeforeTermination() {
        workQueue.sync {
            // Put every dimmed picture back before anything else: leaving one
            // behind is the difference between quitting the app and a screen
            // that stays dark with nothing left running to explain it.
            restoreAllGamma()
            stateLock.lock()
            let ids = managedDisabledIDs
            managedDisabledIDs = []
            managedDisabledDisplays = [:]
            stateLock.unlock()
            for id in ids {
                _ = Self.configureDisplay(id, enabled: true)
            }
            Self.forgetDisplaysSwitchedOff()
        }
    }

    /// Writes every remembered curve back, skipping any display number that
    /// now belongs to a different monitor. Runs on the work queue.
    private func restoreAllGamma() {
        for (id, baseline) in gammaBaselines
        where Self.displayFingerprint(id) == baseline.fingerprint {
            CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                        baseline.green, baseline.blue)
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

    private static func forgetDisplaysSwitchedOff() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.displaysSwitchedOff)
    }

    /// Switches back on anything a previous run left off. Called at startup,
    /// before any display work, so a screen is never stranded between runs.
    func restoreDisplaysLeftOff() {
        let stored = UserDefaults.standard.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        guard !stored.isEmpty else { return }
        Self.forgetDisplaysSwitchedOff()
        guard DisplayConfigurationBridge.configureEnabled != nil else { return }
        workQueue.async {
            for id in stored {
                // The list is plain numbers on disk and can arrive edited or
                // imported, so anything that is not a display number is
                // skipped rather than converted.
                guard let displayID = CGDirectDisplayID(exactly: id) else { continue }
                _ = Self.configureDisplay(displayID, enabled: true)
            }
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
        let current: Double?
        if method == .system {
            current = currentSystemBrightness(
                for: displayID,
                fallback: displays.first(where: { $0.id == displayID })?.brightness)
        } else {
            current = displays.first(where: { $0.id == displayID })?.brightness
        }
        guard let current else { return }
        setBrightness(BrightnessSupport.steppedBrightness(current, delta: press.delta),
                      for: displayID,
                      showOSD: showOSD)
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
                setBrightness(BrightnessSupport.steppedBrightness(current, delta: press.delta),
                              for: displayID, showOSD: wantsBrightnessOSD)
            }
            // Both halves are replaced so the system never draws a second OSD.
            return nil
        }
        guard followsPointer else {
            return Unmanaged.passUnretained(event)
        }
        if press.isKeyDown, let current = displays.first(where: { $0.id == displayID })?.brightness {
            setBrightness(BrightnessSupport.steppedBrightness(current, delta: press.delta),
                          for: displayID,
                          showOSD: wantsBrightnessOSD)
        }
        return nil
    }

    private func currentSystemBrightness(for id: CGDirectDisplayID,
                                         fallback: Double?) -> Double? {
        stateLock.lock()
        let queued = pendingLevels[id]?.value
        let requested = systemWritesInFlight.contains(id) ? lastApplied[id] : nil
        stateLock.unlock()
        if let queued { return queued }
        if let requested { return requested }
        var live: Float = -1
        if let read = BrightnessBridge.getBrightness,
           read(id, &live) == 0, live >= 0, live <= 1 {
            return Double(live)
        }
        return fallback
    }

    // MARK: - Screen changes

    /// EDR ramps fire this notification in storms with no topology change
    /// (over a hundred times in two seconds, measured); nothing may rebuild
    /// unless the set of displays actually changed, and even then only after
    /// the storm settles.
    private func screensChanged() {
        guard running else { return }
        rebuildDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            CGGetOnlineDisplayList(16, &ids, &count)
            let topology = Set(ids.prefix(Int(count)))
            let activeTopology = Self.activeDisplayIDs()
            self.stateLock.lock()
            let changed = topology != self.knownTopology
                || activeTopology != self.knownActiveTopology
            self.stateLock.unlock()
            if changed { self.refresh() }
        }
        rebuildDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Rebuild (work queue)

    private func rebuild(generation: Int) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let onlineIDs = Array(ids.prefix(Int(count)))

        let seenTopology = Set(onlineIDs)
        let activeTopology = Self.activeDisplayIDs()
        var built: [BrightnessDisplay] = []
        var newRoutes: [CGDirectDisplayID: Route] = [:]
        var ddcCandidates: [(index: Int, identity: BrightnessSupport.DisplayIdentity)] = []

        for id in onlineIDs {
            // A mirroring display follows its source; the source's slider is
            // the real control.
            guard CGDisplayMirrorsDisplay(id) == 0 else { continue }
            let info = Self.displayInfoDictionary(id)
            if let info,
               (info["kCGDisplayIsVirtualDevice"] as? Bool ?? false)
                || (info["kCGDisplayIsAirPlay"] as? Bool ?? false) {
                continue
            }
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = Self.displayName(id, info: info)
            let isActive = activeTopology.contains(id)

            if !isActive {
                stateLock.lock()
                let level = lastApplied[id] ?? 1.0
                stateLock.unlock()
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: nil, isActive: false,
                                               brightness: level, readable: false))
                continue
            }

            var level: Float = -1
            if let read = BrightnessBridge.getBrightness, read(id, &level) == 0, level >= 0, level <= 1 {
                // The system pipeline answers for this display (built-in
                // panel or an Apple external display).
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: .system, isActive: true,
                                               brightness: Double(level), readable: true))
                newRoutes[id] = Route(method: .system, service: nil, maximum: 100)
                continue
            }
            guard !isBuiltIn else { continue }
            ddcCandidates.append((built.count, Self.displayIdentity(id, info: info)))
            // Placeholder; the DDC pass below fills brightness and route.
            built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: false,
                                           method: .ddc, isActive: true,
                                           brightness: 0.5, readable: false))
        }

        stateLock.lock()
        let disabledSnapshots = managedDisabledDisplays
        stateLock.unlock()
        for (id, display) in disabledSnapshots where !seenTopology.contains(id) {
            built.append(display)
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
                switch ddcProbeLuminance(service: matched.service) {
                case .replied(let current, let maximum):
                    let ceiling = BrightnessSupport.sanitizedMaximum(maximum)
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, isActive: true,
                        brightness: BrightnessSupport.normalized(current: current,
                                                                 maximum: ceiling),
                        readable: true)
                    newRoutes[id] = Route(method: .ddc, service: matched.service,
                                          maximum: ceiling)
                    softwareIndices.remove(candidate.index)
                case .writeOnly:
                    // Reads fail on some monitors whose writes still work:
                    // keep the slider, seeded from this session's last value.
                    stateLock.lock()
                    let seed = lastApplied[id] ?? 0.5
                    stateLock.unlock()
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, isActive: true, brightness: seed, readable: false)
                    newRoutes[id] = Route(method: .ddc, service: matched.service, maximum: 100)
                    softwareIndices.remove(candidate.index)
                case .dead:
                    // The channel rejects every write (typically an HDMI
                    // conversion in the path): dim in the video pipeline
                    // instead, which works on any connection.
                    break
                }
            }
        }

        // Software route for everything left over: capture the display's
        // clean gamma curve, restore this session's dim level and reapply it
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
            let value = lastApplied[id] ?? 1.0
            stateLock.unlock()
            captureGammaBaselineIfNeeded(id)
            guard gammaBaselines[id] != nil else { continue }
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
            managedDisabledIDs.subtract(activeTopology)
            for id in activeTopology {
                managedDisabledDisplays.removeValue(forKey: id)
            }
            for display in resolved where display.method != nil {
                lastApplied[display.id] = display.brightness
            }
        }
        stateLock.unlock()
        guard !stale else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, generation == self.rebuildGeneration else { return }
            if self.displays != resolved { self.displays = resolved }
            if self.brightnessOSDSupported != supportsBrightnessOSD {
                self.brightnessOSDSupported = supportsBrightnessOSD
            }
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
                writeSucceeded = ddcSend(service: service, packet: packet)
            case .software:
                writeSucceeded = applySoftwareDim(id, value: value)
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

    private func ddcSend(service: CFTypeRef, packet: [UInt8]) -> Bool {
        guard let write = BrightnessBridge.writeI2C else { return false }
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

    /// Reads the monitor's luminance while also judging the channel itself:
    /// the request write's own return value is the only reliable signal of a
    /// path that cannot carry DDC at all (HDMI conversions reject every
    /// write, while their reads "succeed" with cached EDID bytes).
    private func ddcProbeLuminance(service: CFTypeRef) -> DDCProbe {
        guard let write = BrightnessBridge.writeI2C,
              let read = BrightnessBridge.readI2C else { return .dead }
        var request = BrightnessSupport.readRequestPacket(code: BrightnessSupport.luminanceCode)
        var writeAccepted = false
        for attempt in 0...BrightnessSupport.retryAttempts {
            for _ in 0..<BrightnessSupport.writeCycles {
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
            if attempt < BrightnessSupport.retryAttempts {
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

    private static func displayName(_ id: CGDirectDisplayID, info: NSDictionary?) -> String {
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) {
            return screen.localizedName
        }
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
