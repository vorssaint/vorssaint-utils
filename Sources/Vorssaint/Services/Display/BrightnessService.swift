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
    let method: Method
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

    private struct Route {
        var method: BrightnessDisplay.Method
        var service: CFTypeRef?
        var maximum: UInt16
    }

    private var screenObserver: NSObjectProtocol?
    private var rebuildDebounce: DispatchWorkItem?
    /// Media-key tap, alive only while the brightness keys option is on and
    /// Accessibility is granted. Its mask covers system-defined events only,
    /// so ordinary typing never touches it.
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    /// Serializes every I2C transaction and rebuild; DDC displays drop
    /// commands that interleave.
    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.brightness", qos: .userInitiated)
    private let stateLock = NSLock()
    private var routes: [CGDirectDisplayID: Route] = [:]
    private var pendingLevels: [CGDirectDisplayID: Double] = [:]
    private var drainScheduled = false
    /// Session memory for write-only monitors, so their slider does not jump
    /// back to a placeholder between panel openings.
    private var lastApplied: [CGDirectDisplayID: Double] = [:]
    /// The unmodified gamma curve of each software-dimmed display, captured
    /// before the first change so restoring is exact. Touched only on the
    /// work queue.
    private var gammaBaselines: [CGDirectDisplayID: GammaTable] = [:]

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var count: UInt32
    }
    private var knownTopology = Set<CGDirectDisplayID>()
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
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        rebuildDebounce?.cancel()
        rebuildDebounce = nil
        stateLock.lock()
        rebuildGeneration += 1
        routes = [:]
        pendingLevels = [:]
        lastApplied = [:]
        knownTopology = []
        stateLock.unlock()
        if !displays.isEmpty { displays = [] }
        // Undo any gamma dimming on the work queue, AFTER an apply that may
        // already be in flight there; quitting outright needs nothing (the
        // window server drops a dead process's gamma on its own).
        workQueue.async { [weak self] in
            guard let self else { return }
            for (id, baseline) in self.gammaBaselines {
                CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                            baseline.green, baseline.blue)
            }
            self.gammaBaselines = [:]
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
    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let clamped = min(max(value, 0), 1)
        if let index = displays.firstIndex(where: { $0.id == id }),
           displays[index].brightness != clamped {
            displays[index].brightness = clamped
        }
        stateLock.lock()
        pendingLevels[id] = clamped
        lastApplied[id] = clamped
        let schedule = !drainScheduled
        if schedule { drainScheduled = true }
        stateLock.unlock()
        guard schedule else { return }
        workQueue.async { [weak self] in
            self?.drainPendingLevels()
        }
    }

    // MARK: - Brightness keys (follow the pointer)

    private func syncKeyTap() {
        let wanted = running
            && UserDefaults.standard.bool(forKey: DefaultsKey.brightnessKeysEnabled)
            && Permissions.shared.accessibility
        if wanted { installKeyTap() } else { removeKeyTap() }
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

    /// Routes a brightness key press to the display under the pointer. Both
    /// halves of a handled press (down and up) are swallowed so the system
    /// never also moves its own target; anything this service does not steer
    /// (other keys, pointer on a system-managed display) passes through and
    /// keeps its native behavior, OSD included.
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

        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                               as? NSNumber)?.uint32Value
        else { return Unmanaged.passUnretained(event) }

        stateLock.lock()
        let route = routes[displayID]
        stateLock.unlock()
        guard let route, route.method != .system else {
            // The system's own pipeline handles this display; keep the native
            // keys, animation and OSD.
            return Unmanaged.passUnretained(event)
        }
        if press.isKeyDown, let current = displays.first(where: { $0.id == displayID })?.brightness {
            setBrightness(BrightnessSupport.steppedBrightness(current, delta: press.delta),
                          for: displayID)
        }
        return nil
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
            self.stateLock.lock()
            let changed = topology != self.knownTopology
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

            var level: Float = -1
            if let read = BrightnessBridge.getBrightness, read(id, &level) == 0, level >= 0, level <= 1 {
                // The system pipeline answers for this display (built-in
                // panel or an Apple external display).
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: .system, brightness: Double(level),
                                               readable: true))
                newRoutes[id] = Route(method: .system, service: nil, maximum: 100)
                continue
            }
            guard !isBuiltIn else { continue }
            ddcCandidates.append((built.count, Self.displayIdentity(id, info: info)))
            // Placeholder; the DDC pass below fills brightness and route.
            built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: false,
                                           method: .ddc, brightness: 0.5, readable: false))
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
                        method: .ddc,
                        brightness: BrightnessSupport.normalized(current: current,
                                                                 maximum: ceiling),
                        readable: true)
                    newRoutes[id] = Route(method: .ddc, service: matched.service, maximum: ceiling)
                    softwareIndices.remove(candidate.index)
                case .writeOnly:
                    // Reads fail on some monitors whose writes still work:
                    // keep the slider, seeded from this session's last value.
                    stateLock.lock()
                    let seed = lastApplied[id] ?? 0.5
                    stateLock.unlock()
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, brightness: seed, readable: false)
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
        gammaBaselines = gammaBaselines.filter { seenTopology.contains($0.key) }
        for index in softwareIndices.sorted() {
            let id = built[index].id
            stateLock.lock()
            let value = lastApplied[id] ?? 1.0
            stateLock.unlock()
            captureGammaBaselineIfNeeded(id, currentValue: value)
            guard gammaBaselines[id] != nil else { continue }
            built[index] = BrightnessDisplay(
                id: id, name: built[index].name, isBuiltIn: false,
                method: .software, brightness: value, readable: true)
            newRoutes[id] = Route(method: .software, service: nil, maximum: 100)
            if value < 0.999 { applySoftwareDim(id, value: value) }
        }
        let resolved = built.filter { newRoutes[$0.id] != nil }

        stateLock.lock()
        let stale = generation != rebuildGeneration
        if !stale {
            routes = newRoutes
            knownTopology = seenTopology
        }
        stateLock.unlock()
        guard !stale else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, generation == self.rebuildGeneration else { return }
            if self.displays != resolved { self.displays = resolved }
        }
    }

    // MARK: - Writes (work queue)

    private func drainPendingLevels() {
        while true {
            stateLock.lock()
            guard let (id, value) = pendingLevels.first else {
                drainScheduled = false
                stateLock.unlock()
                return
            }
            pendingLevels.removeValue(forKey: id)
            let route = routes[id]
            stateLock.unlock()
            guard let route else { continue }
            switch route.method {
            case .system:
                _ = BrightnessBridge.setBrightness?(id, Float(value))
            case .ddc:
                guard let service = route.service else { continue }
                let packet = BrightnessSupport.writePacket(
                    code: BrightnessSupport.luminanceCode,
                    value: BrightnessSupport.deviceValue(for: value, maximum: route.maximum))
                _ = ddcSend(service: service, packet: packet)
            case .software:
                applySoftwareDim(id, value: value)
            }
        }
    }

    // MARK: - Software dimming (work queue)

    /// Remembers the display's untouched curve. While our own dim is applied
    /// the live table is a scaled copy, so it must never be recaptured as a
    /// baseline; a clean display refreshes it to follow system curve changes.
    private func captureGammaBaselineIfNeeded(_ id: CGDirectDisplayID, currentValue: Double) {
        if gammaBaselines[id] != nil, currentValue < 0.999 { return }
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
                                        count: UInt32(count))
    }

    private func applySoftwareDim(_ id: CGDirectDisplayID, value: Double) {
        guard let baseline = gammaBaselines[id] else { return }
        if value >= 0.999 {
            CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                        baseline.green, baseline.blue)
            return
        }
        let factor = BrightnessSupport.softwareDimFactor(for: value)
        let red = BrightnessSupport.scaledGammaTable(baseline.red, factor: factor)
        let green = BrightnessSupport.scaledGammaTable(baseline.green, factor: factor)
        let blue = BrightnessSupport.scaledGammaTable(baseline.blue, factor: factor)
        CGSetDisplayTransferByTable(id, baseline.count, red, green, blue)
    }

    // MARK: - DDC transactions (work queue)

    private func ddcSend(service: CFTypeRef, packet: [UInt8]) -> Bool {
        guard let write = BrightnessBridge.writeI2C else { return false }
        var bytes = packet
        var success = false
        for attempt in 0...BrightnessSupport.retryAttempts {
            for _ in 0..<BrightnessSupport.writeCycles {
                usleep(BrightnessSupport.writePauseMicroseconds)
                success = write(service, BrightnessSupport.chipAddress,
                                BrightnessSupport.dataAddress,
                                &bytes, UInt32(bytes.count)) == KERN_SUCCESS
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
