// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ColorSync
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePort(_ display: CGDirectDisplayID) -> io_service_t

private let displayServicesGetBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
          let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
}()

private let coreDisplayGetBrightness: (@convention(c) (CGDirectDisplayID) -> Double)? = {
    guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
          let symbol = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (CGDirectDisplayID) -> Double).self)
}()

struct DisplayResolutionMode: Identifiable, Hashable {
    let id: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool

    var label: String {
        var parts = ["\(width) x \(height)"]
        if isHiDPI { parts.append("HiDPI") }
        if refreshRate > 1 {
            parts.append("\(Int(refreshRate.rounded())) Hz")
        }
        return parts.joined(separator: " - ")
    }
}

enum DisplayScaleChoice: String, CaseIterable, Identifiable {
    case native, hiDPI
    var id: String { rawValue }
}

struct ManagedDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let vendorID: UInt32
    let productID: UInt32
    let pointWidth: Int
    let pointHeight: Int
    let originX: Int
    let originY: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let currentModeID: Int32?
    let currentModeLabel: String
    let modes: [DisplayResolutionMode]
    let hdrSupported: Bool
    let hdrEnabled: Bool
    let hdrMutable: Bool
    let hiDPIOverrideInstalled: Bool

    var nativeMode: DisplayResolutionMode? {
        modes.filter { !$0.isHiDPI }.max {
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth < $1.pixelWidth }
            return $0.pixelHeight < $1.pixelHeight
        }
    }

    var bestHiDPIMode: DisplayResolutionMode? {
        modes.filter(\.isHiDPI).max {
            if $0.width != $1.width { return $0.width < $1.width }
            if $0.height != $1.height { return $0.height < $1.height }
            return $0.refreshRate < $1.refreshRate
        }
    }

    static func == (lhs: ManagedDisplay, rhs: ManagedDisplay) -> Bool {
        lhs.id == rhs.id
            && lhs.currentModeID == rhs.currentModeID
            && lhs.hdrEnabled == rhs.hdrEnabled
            && lhs.isMain == rhs.isMain
            && lhs.originX == rhs.originX
            && lhs.originY == rhs.originY
            && lhs.pointWidth == rhs.pointWidth
            && lhs.pointHeight == rhs.pointHeight
            && lhs.hiDPIOverrideInstalled == rhs.hiDPIOverrideInstalled
            && lhs.modes == rhs.modes
    }
}

struct DisplayImageAdjustment: Codable, Equatable {
    var contrast: Double = 0
    var gamma: Double = 0
    var gain: Double = 0
    var warmth: Double = 0
    var inverted: Bool = false
    var paused: Bool = false

    var isNeutral: Bool {
        contrast == 0 && gamma == 0 && gain == 0 && warmth == 0 && !inverted
    }
}

struct ManagedColorProfile: Identifiable, Equatable {
    let name: String
    let path: URL
    let colorSpace: String

    var id: String { path.path }
}

struct DisplayManagementPreset: Identifiable, Codable, Equatable {
    struct Entry: Codable, Equatable {
        let displayUUID: String
        let modeID: Int32?
        let brightness: Double?
        let colorProfilePath: String?
        let hdrEnabled: Bool?
        let originX: Int?
        let originY: Int?
        let isMain: Bool?
    }

    var id = UUID()
    var name: String
    var createdAt = Date()
    var entries: [Entry]
}

@MainActor
final class DisplayManagementService: ObservableObject {
    static let shared = DisplayManagementService()

    @Published private(set) var displays: [ManagedDisplay] = []
    @Published private(set) var presets: [DisplayManagementPreset] = []
    @Published private(set) var colorProfiles: [ManagedColorProfile] = []
    @Published private(set) var activeProfileByDisplayID: [CGDirectDisplayID: URL] = [:]
    @Published private(set) var nightShiftAvailable = false
    @Published private(set) var trueToneAvailable = false
    @Published private(set) var autoBrightnessAvailable = false
    @Published private(set) var imageAdjustments: [CGDirectDisplayID: DisplayImageAdjustment] = [:]
    @Published var nightShiftEnabled = false
    @Published var trueToneEnabled = false
    @Published var autoBrightnessEnabled = false {
        didSet {
            UserDefaults.standard.set(autoBrightnessEnabled,
                                      forKey: DefaultsKey.displayAutoBrightnessEnabled)
            autoBrightnessEnabled ? startAutoBrightness() : stopAutoBrightness()
        }
    }
    @Published var autoBrightnessSensitivity = 1.0 {
        didSet {
            let sanitized = min(max(autoBrightnessSensitivity, 0.5), 1.5)
            if sanitized != autoBrightnessSensitivity {
                autoBrightnessSensitivity = sanitized
                return
            }
            UserDefaults.standard.set(sanitized,
                                      forKey: DefaultsKey.displayAutoBrightnessSensitivity)
            applyAutoBrightness()
        }
    }
    @Published private(set) var lastError: String?

    private let presetsKey = "displayManagementPresets"
    private let queue = DispatchQueue(label: "com.vorssaint.utils.display-management", qos: .userInitiated)
    private var blueLightClient: NSObject?
    private var trueToneClient: NSObject?
    private var autoBrightnessTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    private init() {
        autoBrightnessEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.displayAutoBrightnessEnabled)
        let storedSensitivity = UserDefaults.standard.double(forKey: DefaultsKey.displayAutoBrightnessSensitivity)
        if storedSensitivity > 0 {
            autoBrightnessSensitivity = min(max(storedSensitivity, 0.5), 1.5)
        }
        loadPresets()
        configureSystemEffects()
        autoBrightnessAvailable = Self.builtInBrightness() != nil
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenParametersChanged()
            }
        }
        if autoBrightnessEnabled {
            startAutoBrightness()
        }
    }

    func refresh() {
        refreshDisplays()
        refreshSystemEffects()
        loadColorProfilesIfNeeded()
        autoBrightnessAvailable = Self.builtInBrightness() != nil
    }

    func clearError() {
        lastError = nil
    }

    func setMode(_ mode: DisplayResolutionMode, for display: ManagedDisplay) {
        lastError = nil
        queue.async {
            let success = Self.applyModeID(mode.id, to: display.id)
            DispatchQueue.main.async {
                if success {
                    self.refreshDisplays()
                } else {
                    self.lastError = "Could not change the resolution for \(display.name)."
                }
            }
        }
    }

    func setScale(_ choice: DisplayScaleChoice, for display: ManagedDisplay) {
        let target: DisplayResolutionMode?
        switch choice {
        case .native: target = display.nativeMode
        case .hiDPI: target = display.bestHiDPIMode
        }
        guard let target else {
            lastError = choice == .hiDPI
                ? "No HiDPI mode is available for \(display.name)."
                : "No native mode is available for \(display.name)."
            return
        }
        setMode(target, for: display)
    }

    func setMainDisplay(_ display: ManagedDisplay) {
        guard !display.isMain else { return }
        let snapshot = displays
        queue.async {
            let success = Self.applyMainDisplay(display.id, among: snapshot)
            DispatchQueue.main.async {
                if success {
                    self.refreshDisplays()
                } else {
                    self.lastError = "Could not make \(display.name) the main display."
                }
            }
        }
    }

    func setDisplayPosition(_ display: ManagedDisplay, x: Int, y: Int) {
        let snapshot = displays
        queue.async {
            let success = Self.applyPosition(display.id, x: x, y: y, among: snapshot)
            DispatchQueue.main.async {
                if success {
                    self.refreshDisplays()
                } else {
                    self.lastError = "Could not move \(display.name)."
                }
            }
        }
    }

    func installHiDPIOverride(for display: ManagedDisplay) {
        guard !display.isBuiltIn else {
            lastError = "HiDPI overrides are only for external displays."
            return
        }
        let width = max(display.pixelWidth, display.nativeMode?.pixelWidth ?? display.pixelWidth)
        let height = max(display.pixelHeight, display.nativeMode?.pixelHeight ?? display.pixelHeight)
        queue.async {
            let error = Self.writeHiDPIOverride(vendorID: display.vendorID,
                                                productID: display.productID,
                                                nativeWidth: width,
                                                nativeHeight: height)
            DispatchQueue.main.async {
                if let error {
                    self.lastError = error
                } else {
                    self.refreshDisplays()
                    self.lastError = nil
                }
            }
        }
    }

    func removeHiDPIOverride(for display: ManagedDisplay) {
        queue.async {
            let error = Self.removeHiDPIOverride(vendorID: display.vendorID, productID: display.productID)
            DispatchQueue.main.async {
                if let error {
                    self.lastError = error
                } else {
                    self.refreshDisplays()
                    self.lastError = nil
                }
            }
        }
    }

    func setHDR(_ enabled: Bool, for display: ManagedDisplay) {
        guard display.hdrMutable else {
            lastError = "HDR control is not available for \(display.name)."
            return
        }
        lastError = nil
        let success = displayHDRControl.set(display.id, enabled)
        if success {
            refreshDisplays()
        } else {
            lastError = "Could not change HDR for \(display.name)."
        }
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let brightnessByID = Dictionary(uniqueKeysWithValues:
            BrightnessService.shared.displays.map { ($0.id, $0.brightness) })
        let entries = displays.map { display in
            DisplayManagementPreset.Entry(
                displayUUID: display.uuid,
                modeID: display.currentModeID,
                brightness: brightnessByID[display.id],
                colorProfilePath: activeProfileByDisplayID[display.id]?.path,
                hdrEnabled: display.hdrMutable ? display.hdrEnabled : nil,
                originX: display.originX,
                originY: display.originY,
                isMain: display.isMain
            )
        }
        presets.insert(DisplayManagementPreset(name: trimmed, entries: entries), at: 0)
        savePresets()
    }

    func deletePreset(_ preset: DisplayManagementPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    func renamePreset(_ preset: DisplayManagementPreset, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].name = trimmed
        savePresets()
    }

    func updatePresetFromCurrentDisplays(_ preset: DisplayManagementPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        let name = presets[index].name
        let brightnessByID = Dictionary(uniqueKeysWithValues:
            BrightnessService.shared.displays.map { ($0.id, $0.brightness) })
        presets[index].entries = displays.map { display in
            DisplayManagementPreset.Entry(
                displayUUID: display.uuid,
                modeID: display.currentModeID,
                brightness: brightnessByID[display.id],
                colorProfilePath: activeProfileByDisplayID[display.id]?.path,
                hdrEnabled: display.hdrMutable ? display.hdrEnabled : nil,
                originX: display.originX,
                originY: display.originY,
                isMain: display.isMain
            )
        }
        presets[index].name = name
        savePresets()
    }

    func applyPreset(_ preset: DisplayManagementPreset) {
        lastError = nil
        let displayByUUID = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0) })
        let arrangementEntries = preset.entries.compactMap { entry -> (displayID: CGDirectDisplayID, x: Int, y: Int)? in
            guard let display = displayByUUID[entry.displayUUID],
                  let x = entry.originX,
                  let y = entry.originY else { return nil }
            return (display.id, x, y)
        }
        for entry in preset.entries {
            guard let display = displayByUUID[entry.displayUUID] else { continue }
            if let modeID = entry.modeID, display.currentModeID != modeID {
                _ = Self.applyModeID(modeID, to: display.id)
            }
            if let profilePath = entry.colorProfilePath,
               let profile = colorProfiles.first(where: { $0.path.path == profilePath }) {
                _ = Self.setColorProfile(profile.path, for: display.id)
            }
            if let hdrEnabled = entry.hdrEnabled, display.hdrMutable {
                _ = displayHDRControl.set(display.id, hdrEnabled)
            }
            if let brightness = entry.brightness,
               BrightnessService.shared.displays.contains(where: { $0.id == display.id }) {
                BrightnessService.shared.setBrightness(brightness, for: display.id)
            }
        }
        if !arrangementEntries.isEmpty {
            _ = Self.applyOrigins(arrangementEntries)
        }
        refreshDisplays()
        refreshActiveProfiles()
    }

    func setColorProfile(_ profile: ManagedColorProfile, for display: ManagedDisplay) {
        lastError = nil
        let success = Self.setColorProfile(profile.path, for: display.id)
        if success {
            activeProfileByDisplayID[display.id] = profile.path
        } else {
            lastError = "Could not apply \(profile.name) to \(display.name)."
        }
    }

    func resetColorProfile(for display: ManagedDisplay) {
        lastError = nil
        let success = Self.clearColorProfile(for: display.id)
        if success {
            activeProfileByDisplayID.removeValue(forKey: display.id)
            refreshActiveProfiles()
        } else {
            lastError = "Could not restore the default color profile for \(display.name)."
        }
    }

    func setNightShift(_ enabled: Bool) {
        guard let blueLightClient else { return }
        Self.callSetter(blueLightClient, selectorName: "setEnabled:", value: enabled)
        nightShiftEnabled = enabled
    }

    func setTrueTone(_ enabled: Bool) {
        guard let trueToneClient else { return }
        Self.callSetter(trueToneClient, selectorName: "setEnabled:", value: enabled)
        trueToneEnabled = enabled
    }

    func setImageAdjustment(_ adjustment: DisplayImageAdjustment, for display: ManagedDisplay) {
        imageAdjustments[display.id] = adjustment
        BrightnessService.shared.setImageAdjustment(adjustment.paused ? nil : adjustment,
                                                   for: display.id)
    }

    func resetImageAdjustment(for display: ManagedDisplay) {
        imageAdjustments.removeValue(forKey: display.id)
        BrightnessService.shared.setImageAdjustment(nil, for: display.id)
    }

    private func refreshDisplays() {
        let newDisplays = Self.onlineDisplays()
        displays = newDisplays
        imageAdjustments = imageAdjustments.filter { id, _ in
            newDisplays.contains { $0.id == id }
        }
        refreshActiveProfiles()
    }

    private func screenParametersChanged() {
        refresh()
        if autoBrightnessEnabled {
            applyAutoBrightness()
        }
    }

    nonisolated private static func onlineDisplays() -> [ManagedDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayIsActive(id) != 0 else { return nil }
            let current = CGDisplayCopyDisplayMode(id)
            let modes = displayModes(for: id)
            let currentMode = current.flatMap { mode in
                modes.first { $0.id == mode.ioDisplayModeID }
            }
            let name = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }?.localizedName ?? "Display \(id)"
            let hdr = displayHDRControl.state(id)
            let bounds = CGDisplayBounds(id)
            return ManagedDisplay(
                id: id,
                uuid: displayUUID(id),
                name: name,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                vendorID: CGDisplayVendorNumber(id),
                productID: CGDisplayModelNumber(id),
                pointWidth: Int(bounds.width.rounded()),
                pointHeight: Int(bounds.height.rounded()),
                originX: Int(bounds.origin.x.rounded()),
                originY: Int(bounds.origin.y.rounded()),
                pixelWidth: CGDisplayPixelsWide(id),
                pixelHeight: CGDisplayPixelsHigh(id),
                currentModeID: current?.ioDisplayModeID,
                currentModeLabel: currentMode?.label ?? "\(CGDisplayPixelsWide(id)) x \(CGDisplayPixelsHigh(id))",
                modes: modes,
                hdrSupported: hdr.supported,
                hdrEnabled: hdr.enabled,
                hdrMutable: hdr.mutable,
                hiDPIOverrideInstalled: hiDPIOverrideInstalled(vendorID: CGDisplayVendorNumber(id),
                                                               productID: CGDisplayModelNumber(id))
            )
        }
    }

    nonisolated private static func displayModes(for displayID: CGDirectDisplayID) -> [DisplayResolutionMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }
        var seen = Set<String>()
        return rawModes.compactMap { mode in
            guard mode.width >= 640, mode.height >= 480 else { return nil }
            let refresh = mode.refreshRate
            let hiDPI = mode.pixelWidth > mode.width || mode.pixelHeight > mode.height
            let key = "\(mode.width)x\(mode.height):\(mode.pixelWidth)x\(mode.pixelHeight):\(Int(refresh.rounded())):\(hiDPI)"
            guard seen.insert(key).inserted else { return nil }
            return DisplayResolutionMode(
                id: mode.ioDisplayModeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: refresh,
                isHiDPI: hiDPI
            )
        }
        .sorted {
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
            if $0.pixelHeight != $1.pixelHeight { return $0.pixelHeight > $1.pixelHeight }
            return $0.refreshRate > $1.refreshRate
        }
    }

    nonisolated private static func applyModeID(_ modeID: Int32, to displayID: CGDirectDisplayID) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              let mode = rawModes.first(where: { $0.ioDisplayModeID == modeID }) else {
            return false
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    nonisolated private static func applyOrigins(_ origins: [(displayID: CGDirectDisplayID, x: Int, y: Int)]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for origin in origins {
            CGConfigureDisplayOrigin(config, origin.displayID, Int32(origin.x), Int32(origin.y))
        }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        if complete != .success {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }

    nonisolated private static func applyMainDisplay(_ displayID: CGDirectDisplayID,
                                                     among displays: [ManagedDisplay]) -> Bool {
        guard let target = displays.first(where: { $0.id == displayID }) else { return false }
        let dx = target.originX
        let dy = target.originY
        let shifted = displays.map { display in
            (display.id, display.originX - dx, display.originY - dy)
        }
        return applyOrigins(shifted)
    }

    nonisolated private static func applyPosition(_ displayID: CGDirectDisplayID,
                                                  x: Int,
                                                  y: Int,
                                                  among displays: [ManagedDisplay]) -> Bool {
        var origins = displays.map { display in
            (display.id, display.id == displayID ? x : display.originX,
             display.id == displayID ? y : display.originY)
        }
        if let main = displays.first(where: \.isMain),
           let proposedMain = origins.first(where: { $0.0 == main.id }),
           proposedMain.1 != 0 || proposedMain.2 != 0 {
            let dx = proposedMain.1
            let dy = proposedMain.2
            origins = origins.map { ($0.0, $0.1 - dx, $0.2 - dy) }
        }
        return applyOrigins(origins.map { ($0.0, $0.1, $0.2) })
    }

    nonisolated private static func overrideURL(vendorID: UInt32, productID: UInt32) -> URL {
        URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides", isDirectory: true)
            .appendingPathComponent(String(format: "DisplayVendorID-%x", vendorID), isDirectory: true)
            .appendingPathComponent(String(format: "DisplayProductID-%x", productID))
    }

    nonisolated private static func hiDPIOverrideInstalled(vendorID: UInt32, productID: UInt32) -> Bool {
        FileManager.default.fileExists(atPath: overrideURL(vendorID: vendorID, productID: productID).path)
    }

    nonisolated private static func writeHiDPIOverride(vendorID: UInt32,
                                                       productID: UInt32,
                                                       nativeWidth: Int,
                                                       nativeHeight: Int) -> String? {
        let modes = hiDPIModeData(nativeWidth: nativeWidth, nativeHeight: nativeHeight)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: ["scale-resolutions": modes],
                                                             format: .xml,
                                                             options: 0) else {
            return "Could not build the HiDPI override."
        }
        let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vorssaint-hidpi-\(vendorID)-\(productID).plist")
        do {
            try data.write(to: temporaryURL, options: .atomic)
        } catch {
            return error.localizedDescription
        }
        let destination = overrideURL(vendorID: vendorID, productID: productID)
        let command = "mkdir -p '\(destination.deletingLastPathComponent().path)' && cp '\(temporaryURL.path)' '\(destination.path)'"
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        return runPrivileged(command)
    }

    nonisolated private static func removeHiDPIOverride(vendorID: UInt32, productID: UInt32) -> String? {
        let destination = overrideURL(vendorID: vendorID, productID: productID)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return runPrivileged("rm -f '\(destination.path)'")
    }

    nonisolated private static func hiDPIModeData(nativeWidth: Int, nativeHeight: Int) -> [Data] {
        let scales = [1.0, 0.75, 0.625, 0.5]
        return scales.compactMap { scale in
            let logicalWidth = Int((Double(nativeWidth) * scale).rounded()) & ~1
            let logicalHeight = Int((Double(nativeHeight) * scale).rounded()) & ~1
            guard logicalWidth >= 800, logicalHeight >= 600 else { return nil }
            let backingWidth = logicalWidth * 2
            let backingHeight = logicalHeight * 2
            var bytes = [UInt8](repeating: 0, count: 8)
            bytes[0] = UInt8((backingWidth >> 24) & 0xff)
            bytes[1] = UInt8((backingWidth >> 16) & 0xff)
            bytes[2] = UInt8((backingWidth >> 8) & 0xff)
            bytes[3] = UInt8(backingWidth & 0xff)
            bytes[4] = UInt8((backingHeight >> 24) & 0xff)
            bytes[5] = UInt8((backingHeight >> 16) & 0xff)
            bytes[6] = UInt8((backingHeight >> 8) & 0xff)
            bytes[7] = UInt8(backingHeight & 0xff)
            return Data(bytes)
        }
    }

    nonisolated private static func runPrivileged(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Administrator authorization failed."
            return message
        }
        return nil
    }

    private func startAutoBrightness() {
        stopAutoBrightness()
        autoBrightnessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyAutoBrightness() }
        }
        autoBrightnessTimer?.tolerance = 0.3
        applyAutoBrightness()
    }

    private func stopAutoBrightness() {
        autoBrightnessTimer?.invalidate()
        autoBrightnessTimer = nil
    }

    private func applyAutoBrightness() {
        guard autoBrightnessEnabled,
              let builtIn = Self.builtInBrightness() else { return }
        let target = min(max(builtIn * autoBrightnessSensitivity, 0), 1)
        for display in BrightnessService.shared.displays where !display.isBuiltIn && display.isActive {
            BrightnessService.shared.setBrightness(target, for: display.id)
        }
    }

    nonisolated private static func builtInBrightness() -> Double? {
        guard let id = activeDisplayIDs().first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }
        if let get = displayServicesGetBrightness {
            var value: Float = 0
            if get(id, &value) == 0 { return min(max(Double(value), 0), 1) }
        }
        if let get = coreDisplayGetBrightness {
            let value = get(id)
            if value > 0 { return min(max(value, 0), 1) }
        }
        var value: Float = 0
        let service = CGDisplayIOServicePort(id)
        guard service != 0 else { return nil }
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
        return result == KERN_SUCCESS ? min(max(Double(value), 0), 1) : nil
    }

    nonisolated private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func loadColorProfilesIfNeeded() {
        guard colorProfiles.isEmpty else {
            refreshActiveProfiles()
            return
        }
        queue.async {
            let profiles = Self.enumerateColorProfiles()
            DispatchQueue.main.async {
                self.colorProfiles = profiles
                self.refreshActiveProfiles()
            }
        }
    }

    nonisolated private static func enumerateColorProfiles() -> [ManagedColorProfile] {
        let roots = [
            URL(fileURLWithPath: "/Library/ColorSync/Profiles", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/ColorSync/Profiles", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/ColorSync/Profiles", isDirectory: true),
        ]
        var seen = Set<String>()
        var result: [ManagedColorProfile] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "icc" || ext == "icm", seen.insert(url.path).inserted else { continue }
                result.append(profile(from: url))
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func profile(from url: URL) -> ManagedColorProfile {
        var name = url.deletingPathExtension().lastPathComponent
        var colorSpace = "RGB"
        if let rawProfile = ColorSyncProfileCreateWithURL(url as CFURL, nil) {
            let profile = rawProfile.takeRetainedValue()
            if let rawDescription = ColorSyncProfileCopyDescriptionString(profile) {
                name = rawDescription.takeRetainedValue() as String
            }
            if let header = ColorSyncProfileCopyHeader(profile)?.takeRetainedValue() as Data?,
               header.count >= 20,
               let tag = String(bytes: header[16..<20], encoding: .ascii) {
                colorSpace = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ManagedColorProfile(name: name, path: url, colorSpace: colorSpace.isEmpty ? "RGB" : colorSpace)
    }

    private func refreshActiveProfiles() {
        var active: [CGDirectDisplayID: URL] = [:]
        for display in displays {
            if let url = Self.activeProfileURL(for: display.id) {
                active[display.id] = url
            }
        }
        activeProfileByDisplayID = active
    }

    nonisolated private static func activeProfileURL(for displayID: CGDirectDisplayID) -> URL? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let profileKey = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue(),
              let rawInfo = ColorSyncDeviceCopyDeviceInfo(deviceClass, uuid) else {
            return nil
        }
        let info = rawInfo.takeRetainedValue() as NSDictionary
        guard let factory = info["FactoryProfiles"] as? NSDictionary,
              let activeMode = factory[profileKey] else { return nil }
        if let custom = info["CustomProfiles"] as? NSDictionary,
           let value = custom[activeMode],
           let url = urlValue(value) {
            return url
        }
        if let mode = factory[activeMode] as? NSDictionary,
           let value = mode["DeviceProfileURL"],
           let url = urlValue(value) {
            return url
        }
        return nil
    }

    nonisolated private static func setColorProfile(_ url: URL, for displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let profileKey = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue() else {
            return false
        }
        let info: NSDictionary = [profileKey: url as NSURL]
        return ColorSyncDeviceSetCustomProfiles(deviceClass, uuid, info as CFDictionary)
    }

    nonisolated private static func clearColorProfile(for displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let profileKey = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue() else {
            return false
        }
        let info: NSDictionary = [profileKey: NSNull()]
        return ColorSyncDeviceSetCustomProfiles(deviceClass, uuid, info as CFDictionary)
    }

    nonisolated private static func urlValue(_ value: Any) -> URL? {
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        if let string = value as? String { return URL(string: string) ?? URL(fileURLWithPath: string) }
        return nil
    }

    private func configureSystemEffects() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil else {
            return
        }
        if let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            blueLightClient = type.init()
            nightShiftAvailable = blueLightClient != nil
        }
        if let type = NSClassFromString("CBTrueToneClient") as? NSObject.Type {
            trueToneClient = type.init()
            trueToneAvailable = trueToneClient.map {
                Self.callBool($0, selectorName: "supported") && Self.callBool($0, selectorName: "available")
            } ?? false
        }
        refreshSystemEffects()
    }

    private func refreshSystemEffects() {
        if let blueLightClient {
            var bytes = [UInt8](repeating: 0, count: 64)
            let selector = NSSelectorFromString("getBlueLightStatus:")
            if blueLightClient.responds(to: selector) {
                typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
                let ok = bytes.withUnsafeMutableBytes {
                    unsafeBitCast(blueLightClient.method(for: selector), to: Fn.self)(
                        blueLightClient, selector, $0.baseAddress!)
                }
                if ok { nightShiftEnabled = bytes[1] != 0 }
            }
        }
        if let trueToneClient, trueToneAvailable {
            trueToneEnabled = Self.callBool(trueToneClient, selectorName: "enabled")
        }
    }

    private static func callBool(_ object: NSObject, selectorName: String) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Fn.self)(object, selector)
    }

    private static func callSetter(_ object: NSObject, selectorName: String, value: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Bool) -> Void
        unsafeBitCast(object.method(for: selector), to: Fn.self)(object, selector, value)
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([DisplayManagementPreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }

    nonisolated private static func displayUUID(_ displayID: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return "\(CGDisplayVendorNumber(displayID)):\(CGDisplayModelNumber(displayID)):\(CGDisplaySerialNumber(displayID))"
    }

}

private let displayHDRControl = HDRControl()

private struct HDRControl {
    typealias SetFn = @convention(c) (CGDirectDisplayID, Bool) -> Bool
    typealias GetFn = @convention(c) (CGDirectDisplayID) -> Bool

    private let setFn: SetFn?
    private let getEnabledFn: GetFn?
    private let getSupportedFn: GetFn?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
            setFn = nil
            getEnabledFn = nil
            getSupportedFn = nil
            return
        }
        setFn = Self.load(handle, [
            "CoreDisplay_Display_SetHighDynamicRangeEnabled",
            "CoreDisplay_Display_SetHDREnabled",
        ])
        getEnabledFn = Self.load(handle, [
            "CoreDisplay_Display_IsHighDynamicRangeEnabled",
            "CoreDisplay_Display_IsHDREnabled",
        ])
        getSupportedFn = Self.load(handle, [
            "CoreDisplay_Display_SupportsHighDynamicRange",
            "CoreDisplay_Display_SupportsHDR",
        ])
    }

    func state(_ displayID: CGDirectDisplayID) -> (supported: Bool, enabled: Bool, mutable: Bool) {
        let potentialEDR = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        let supported = getSupportedFn?(displayID) ?? (potentialEDR > 1)
        let enabled = getEnabledFn?(displayID) ?? (potentialEDR > 1)
        return (supported, enabled, setFn != nil && supported)
    }

    func set(_ displayID: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        setFn?(displayID, enabled) ?? false
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer, _ names: [String]) -> T? {
        for name in names {
            if let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: T.self)
            }
        }
        return nil
    }
}
