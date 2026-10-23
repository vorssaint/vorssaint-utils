// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import IOKit.graphics

/// Flexible scaling: installs a display override that makes macOS offer every
/// native-aspect HiDPI size of an external monitor, so the user can pick any
/// "looks like" size in System Settings › Displays (or any mode picker) and keep
/// text sharp. The override lives in /Library and is written through one
/// administrator prompt per change; nothing here runs in the background.
final class DisplayScalingService: ObservableObject {
    struct Display: Identifiable, Equatable {
        /// Overrides apply per model, so two identical monitors share one row.
        var id: String { "\(vendorID):\(productID)" }
        let displayID: CGDirectDisplayID
        let name: String
        let vendorID: UInt32
        let productID: UInt32
        let nativeWidth: Int
        let nativeHeight: Int
        let state: DisplayScalingOverrideState
        /// HiDPI sizes with the panel's shape, smallest first, then the native
        /// size at 1:1: the stops of the resolution slider. macOS caps how wide
        /// a HiDPI backing store may be, so on large panels the HiDPI stops end
        /// well before native and native is the only sharp size past them.
        let scaleSizes: [ScaledResolution]
        /// What the display shows now, in points, and the pixels it renders.
        let current: ScaledResolution?
        let currentPixelWidth: Int
        let currentPixelHeight: Int

        var currentIsHiDPI: Bool { current.map { currentPixelWidth > $0.width } ?? false }
        var currentIsNative: Bool {
            current == ScaledResolution(width: nativeWidth, height: nativeHeight)
                && currentPixelWidth == nativeWidth
        }
    }

    enum Outcome: Equatable {
        /// `reconnected` is false when the display could not be cycled, so the
        /// user still has to reconnect it for macOS to read the change.
        case installed(reconnected: Bool)
        case removed(reconnected: Bool)
        case failed
    }

    static let shared = DisplayScalingService()

    @Published private(set) var displays: [Display] = []
    @Published private(set) var workingModelID: String?
    @Published private(set) var lastOutcome: Outcome?

    private var screenObserver: NSObjectProtocol?

    private init() {}

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func syncWithPreferences() {
        if AppFeature.displayScaling.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.displayScalingEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    /// Turning the feature off hides the controls and stops listening. Installed
    /// overrides stay: they are system configuration the user chose, and
    /// removing them needs the password, which a switch must not ask for.
    private func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        displays = []
        lastOutcome = nil
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        displays = Self.externalDisplays()
    }

    /// Installs (or updates) Vorssaint's sizes for this model. A foreign
    /// override is moved aside and comes back when Vorssaint's is removed.
    func install(_ display: Display) {
        let minimumPercent = Defaults.sanitizedDisplayScalingMinimumPercent(
            UserDefaults.standard.integer(forKey: DefaultsKey.displayScalingMinimumPercent))
        let sizes = DisplayScalingSupport.flexibleResolutions(nativeWidth: display.nativeWidth,
                                                              nativeHeight: display.nativeHeight,
                                                              minimumPercent: minimumPercent)
        guard let plist = DisplayScalingSupport.overrideData(vendorID: display.vendorID,
                                                            productID: display.productID,
                                                            sizes: sizes),
              let command = DisplayScalingSupport.installCommand(vendorID: display.vendorID,
                                                                productID: display.productID,
                                                                plist: plist) else {
            lastOutcome = .failed
            return
        }
        run(command, for: display, prompt: strings.installPrompt(display.name)) { .installed(reconnected: $0) }
    }

    /// Switches the display to one of its HiDPI sizes, keeping the refresh
    /// rate it runs at. Public CoreGraphics only: the same change System
    /// Settings makes when a size is picked there.
    func applyScale(_ size: ScaledResolution, to display: Display) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard size != display.current,
              let mode = Self.scaleModes(display.displayID, native: (display.nativeWidth, display.nativeHeight))[size]
        else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        guard CGConfigureDisplayWithDisplayMode(config, display.displayID, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return
        }
        CGCompleteDisplayConfiguration(config, .permanently)
        refresh()
    }

    func remove(_ display: Display) {
        guard case .vorssaint = display.state,
              let command = DisplayScalingSupport.removeCommand(vendorID: display.vendorID,
                                                               productID: display.productID) else { return }
        run(command, for: display, prompt: strings.removePrompt(display.name)) { .removed(reconnected: $0) }
    }

    /// Runs the administrator command, then reconnects every display of the
    /// model: WindowServer reads an override only when a display connects.
    private func run(_ command: String, for display: Display, prompt: String,
                     success: @escaping (_ reconnected: Bool) -> Outcome) {
        guard workingModelID == nil else { return }
        workingModelID = display.id
        lastOutcome = nil
        AdminShell.run(command, prompt: prompt) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { return }
                guard succeeded else {
                    self.finish(.failed)
                    return
                }
                let ids = Self.onlineDisplayIDs(vendorID: display.vendorID, productID: display.productID)
                guard !ids.isEmpty else {
                    self.finish(success(false))
                    return
                }
                self.cycle(ids) { self.finish(success($0)) }
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        workingModelID = nil
        lastOutcome = outcome
        refresh()
    }

    /// One display at a time, so two identical monitors never go dark together.
    private func cycle(_ ids: [CGDirectDisplayID], allReconnected: Bool = true,
                       completion: @escaping (Bool) -> Void) {
        guard let id = ids.first else {
            completion(allReconnected)
            return
        }
        BrightnessService.cycleDisplay(id) { [weak self] reconnected in
            self?.cycle(Array(ids.dropFirst()), allReconnected: allReconnected && reconnected,
                        completion: completion)
        }
    }

    private static func onlineDisplayIDs(vendorID: UInt32, productID: UInt32) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter {
            CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) == vendorID
                && CGDisplayModelNumber($0) == productID
        }
    }

    private var strings: DisplayScalingStrings {
        FeatureStrings.displayScaling(L10n.shared.language)
    }

    // MARK: - Uninstall

    /// Overrides Vorssaint wrote, found by reading /Library (no password).
    static func managedOverridePaths() -> [(vendorID: UInt32, productID: UInt32)] {
        let root = URL(fileURLWithPath: DisplayScalingSupport.overridesDirectory)
        let manager = FileManager.default
        guard let vendors = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
        var found: [(UInt32, UInt32)] = []
        for vendorDirectory in vendors where vendorDirectory.hasPrefix("DisplayVendorID-") {
            guard let vendorID = UInt32(vendorDirectory.dropFirst("DisplayVendorID-".count), radix: 16),
                  let products = try? manager.contentsOfDirectory(
                      atPath: root.appendingPathComponent(vendorDirectory).path) else { continue }
            for product in products where product.hasPrefix("DisplayProductID-") {
                guard let productID = UInt32(product.dropFirst("DisplayProductID-".count), radix: 16) else { continue }
                let path = DisplayScalingSupport.overridePath(vendorID: vendorID, productID: productID)
                if case .vorssaint = DisplayScalingSupport.state(ofOverride: manager.contents(atPath: path)) {
                    found.append((vendorID, productID))
                }
            }
        }
        return found
    }

    /// Removes every override Vorssaint wrote, restoring what each replaced,
    /// with one password prompt. Succeeds at once when there is nothing to do.
    static func removeAllForUninstall(completion: @escaping (Bool) -> Void) {
        let commands = managedOverridePaths().compactMap {
            DisplayScalingSupport.removeCommand(vendorID: $0.vendorID, productID: $0.productID)
        }
        guard !commands.isEmpty else { completion(true); return }
        let strings = FeatureStrings.displayScaling(L10n.shared.language)
        // Each removal ends in `exit`; a subshell per model keeps one from
        // ending the others.
        let command = commands.map { "( \($0) )" }.joined(separator: " && ")
        AdminShell.run(command, prompt: strings.uninstallPrompt, completion: completion)
    }

    // MARK: - Displays

    private static func externalDisplays() -> [Display] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let names = screenNames()
        var seen = Set<String>()
        var displays: [Display] = []
        for id in ids.prefix(Int(count)) {
            // Built-in panels already offer HiDPI, and an override written for
            // one could leave the only screen unusable.
            guard CGDisplayIsBuiltin(id) == 0, let native = nativePixelSize(id) else { continue }
            let vendorID = CGDisplayVendorNumber(id), productID = CGDisplayModelNumber(id)
            guard vendorID != 0, productID != 0, vendorID != 0xFFFF_FFFF else { continue }
            let path = DisplayScalingSupport.overridePath(vendorID: vendorID, productID: productID)
            let currentMode = CGDisplayCopyDisplayMode(id)
            let display = Display(
                displayID: id,
                name: names[id] ?? FeatureStrings.displayScaling(L10n.shared.language).unnamedDisplay,
                vendorID: vendorID, productID: productID,
                nativeWidth: native.width, nativeHeight: native.height,
                state: DisplayScalingSupport.state(ofOverride: FileManager.default.contents(atPath: path)),
                scaleSizes: scaleModes(id, native: native).keys.sorted(),
                current: currentMode.map { ScaledResolution(width: $0.width, height: $0.height) },
                currentPixelWidth: currentMode?.pixelWidth ?? 0,
                currentPixelHeight: currentMode?.pixelHeight ?? 0)
            guard seen.insert(display.id).inserted else { continue }
            displays.append(display)
        }
        return displays
    }

    /// Every HiDPI mode with the panel's shape, plus the native mode at 1:1,
    /// one per size, at the refresh rate the display runs now (or its fastest
    /// when that one is missing).
    private static func scaleModes(_ id: CGDirectDisplayID,
                                   native: (width: Int, height: Int)) -> [ScaledResolution: CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [:] }
        let currentRate = CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0
        var best: [ScaledResolution: CGDisplayMode] = [:]
        for mode in modes where mode.isUsableForDesktopGUI()
            && (mode.pixelWidth == mode.width * 2 && mode.pixelHeight == mode.height * 2
                || mode.width == native.width && mode.height == native.height
                    && mode.pixelWidth == native.width && mode.pixelHeight == native.height) {
            let size = ScaledResolution(width: mode.width, height: mode.height)
            guard DisplayScalingSupport.matchesNativeAspect(size, nativeWidth: native.width,
                                                            nativeHeight: native.height) else { continue }
            guard let kept = best[size] else { best[size] = mode; continue }
            let keptIsHiDPI = kept.pixelWidth > kept.width, modeIsHiDPI = mode.pixelWidth > mode.width
            if keptIsHiDPI != modeIsHiDPI {
                if modeIsHiDPI { best[size] = mode }
                continue
            }
            let keptMatches = abs(kept.refreshRate - currentRate) < 0.5
            let modeMatches = abs(mode.refreshRate - currentRate) < 0.5
            if modeMatches && !keptMatches || modeMatches == keptMatches && mode.refreshRate > kept.refreshRate {
                best[size] = mode
            }
        }
        return best
    }

    /// The panel's own resolution: the mode macOS flags as native. Taking the
    /// largest mode instead would pick a HiDPI backing store an override added.
    private static func nativePixelSize(_ id: CGDirectDisplayID) -> (width: Int, height: Int)? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return nil }
        let native = modes.filter { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }
            .max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        guard let native, native.pixelWidth >= DisplayScalingSupport.minimumNativeWidth else { return nil }
        return (native.pixelWidth, native.pixelHeight)
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                             as? NSNumber)?.uint32Value else { continue }
            names[id] = screen.localizedName
        }
        return names
    }
}
