// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics
import VirtualDisplayBridge

/// Represents a display mode entry (width, height, refreshRate) for virtual displays.
public struct VirtualDisplayModeEntry: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, refreshRate: Double = 60.0) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
    }

    public var label: String {
        "\(width) × \(height) @ \(Int(refreshRate))Hz"
    }
}

/// Represents a collection of modes and default dimensions for a virtual display.
public struct VirtualDisplayProfile: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var aspectRatioLabel: String
    public var modes: [VirtualDisplayModeEntry]
    public var defaultWidth: Int
    public var defaultHeight: Int

    public static let standard16x9 = for16x9()
    public static let mac16x10 = for16x10()

    public static func for16x9() -> VirtualDisplayProfile {
        VirtualDisplayProfile(
            name: "16:9 HiDPI (5K / 4K)",
            aspectRatioLabel: "16:9",
            modes: [
                VirtualDisplayModeEntry(width: 5120, height: 2880, refreshRate: 60),
                VirtualDisplayModeEntry(width: 4608, height: 2592, refreshRate: 60),
                VirtualDisplayModeEntry(width: 4096, height: 2304, refreshRate: 60),
                VirtualDisplayModeEntry(width: 3840, height: 2160, refreshRate: 60),
                VirtualDisplayModeEntry(width: 3200, height: 1800, refreshRate: 60),
                VirtualDisplayModeEntry(width: 2560, height: 1440, refreshRate: 60)
            ],
            defaultWidth: 5120,
            defaultHeight: 2880
        )
    }

    public static func for16x10() -> VirtualDisplayProfile {
        VirtualDisplayProfile(
            name: "16:10 HiDPI",
            aspectRatioLabel: "16:10",
            modes: [
                VirtualDisplayModeEntry(width: 5120, height: 3200, refreshRate: 60),
                VirtualDisplayModeEntry(width: 3840, height: 2400, refreshRate: 60),
                VirtualDisplayModeEntry(width: 2560, height: 1600, refreshRate: 60),
                VirtualDisplayModeEntry(width: 1920, height: 1200, refreshRate: 60)
            ],
            defaultWidth: 3840,
            defaultHeight: 2400
        )
    }

    /// Helper to pick or generate a profile matching a target display's aspect ratio and dimensions.
    public static func profile(matchingWidth width: Int, height: Int) -> VirtualDisplayProfile {
        guard width > 0, height > 0 else { return standard16x9 }
        let ratio = Double(width) / Double(height)

        if abs(ratio - 16.0 / 9.0) < 0.05 {
            return standard16x9
        }
        if abs(ratio - 16.0 / 10.0) < 0.05 {
            return mac16x10
        }

        // Ultrawide (21:9, 32:9) or legacy (4:3, 3:2, etc.) dynamic ladder
        let baseW = width * 2
        let baseH = height * 2
        let factors = [1.0, 0.9, 0.8, 0.75, 0.625, 0.5]
        var modes: [VirtualDisplayModeEntry] = []
        var seen = Set<String>()
        for factor in factors {
            let mw = Int(max(1, (Double(baseW) * factor).rounded()))
            let mh = Int(max(1, (Double(baseH) * factor).rounded()))
            if seen.insert("\(mw)x\(mh)").inserted {
                modes.append(VirtualDisplayModeEntry(width: mw, height: mh, refreshRate: 60))
            }
        }
        return VirtualDisplayProfile(
            name: "HiDPI · \(width) × \(height)",
            aspectRatioLabel: "\(width):\(height)",
            modes: modes.isEmpty ? [VirtualDisplayModeEntry(width: baseW, height: baseH, refreshRate: 60)] : modes,
            defaultWidth: baseW,
            defaultHeight: baseH
        )
    }

    /// Helper to pick or generate a profile matching a target display's current display mode.
    public static func profile(for displayID: CGDirectDisplayID) -> VirtualDisplayProfile {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return standard16x9
        }
        return profile(matchingWidth: mode.width, height: mode.height)
    }
}

/// Errors related to virtual display operations.
public enum VirtualDisplayError: LocalizedError, Equatable {
    case failedToCreateDescriptor
    case failedToApplySettings
    case displayNotFound(CGDirectDisplayID)
    case configurationFailed(CGError)
    case virtualDisplayCreationFailed

    public var errorDescription: String? {
        switch self {
        case .failedToCreateDescriptor:
            return "Failed to create virtual display descriptor."
        case .failedToApplySettings:
            return "Failed to apply settings to virtual display."
        case .displayNotFound(let id):
            return "Target display ID \(id) not found."
        case .configurationFailed(let error):
            return "Display configuration transaction failed with error: \(error.rawValue)."
        case .virtualDisplayCreationFailed:
            return "Virtual display creation failed or did not yield a valid display ID."
        }
    }
}

/// Manages the lifecycle of an individual virtual display created via CoreGraphics private API.
public final class VirtualDisplayInstance: Identifiable {
    public let id = UUID()
    public let serialNum: UInt32
    public let name: String
    public let profile: VirtualDisplayProfile
    public private(set) var displayID: CGDirectDisplayID?

    private var virtualDisplay: CGVirtualDisplay?

    public init(
        profile: VirtualDisplayProfile,
        customName: String? = nil,
        serialNum: UInt32 = UInt32.random(in: 1000...99999)
    ) {
        self.profile = profile
        self.serialNum = serialNum
        self.name = customName ?? "HiDPI 源 · \(profile.aspectRatioLabel)"
    }

    public func start() throws {
        guard virtualDisplay == nil else { return }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = self.name
        descriptor.maxPixelsWide = UInt32(profile.modes.map(\.width).max() ?? profile.defaultWidth)
        descriptor.maxPixelsHigh = UInt32(profile.modes.map(\.height).max() ?? profile.defaultHeight)

        let diagMm: Double = 27.0 * 25.4
        let w = Double(profile.defaultWidth)
        let h = Double(profile.defaultHeight)
        let ratio = diagMm / max(1.0, sqrt(w * w + h * h))
        descriptor.sizeInMillimeters = CGSize(width: w * ratio, height: h * ratio)

        descriptor.vendorID = 0xF0F0
        descriptor.productID = UInt32(min(profile.defaultWidth, 65535))
        descriptor.serialNum = self.serialNum

        let display = CGVirtualDisplay(descriptor: descriptor)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = profile.modes.map { mode in
            CGVirtualDisplayMode(width: mode.width, height: mode.height, refreshRate: mode.refreshRate)
        }

        guard display.apply(settings) else {
            throw VirtualDisplayError.failedToApplySettings
        }

        self.virtualDisplay = display
        self.displayID = display.displayID
    }

    public func stop() {
        virtualDisplay = nil
        displayID = nil
    }

    deinit {
        stop()
    }
}

/// Singleton service managing virtual displays and mirror relationships for HiDPI rendering.
public final class VirtualDisplayService: @unchecked Sendable {
    public static let shared = VirtualDisplayService()

    private let lock = NSLock()
    /// Map of target physical display ID -> associated virtual display dummy instance
    private var associatedDummies: [CGDirectDisplayID: VirtualDisplayInstance] = [:]

    private init() {}

    /// Checks if a virtual mirror is currently active for the given display ID
    /// (either as target physical display or as the virtual source display).
    public func isVirtualMirrorActive(for displayID: CGDirectDisplayID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if associatedDummies[displayID] != nil {
            return true
        }
        return associatedDummies.values.contains { $0.displayID == displayID }
    }

    /// Returns the virtual display ID mirroring the target physical display, if active.
    public func virtualDisplayID(for targetDisplayID: CGDirectDisplayID) -> CGDirectDisplayID? {
        lock.lock()
        defer { lock.unlock() }
        return associatedDummies[targetDisplayID]?.displayID
    }

    /// Returns the active dummy instance for the target physical display, if any.
    public func dummyInstance(for targetDisplayID: CGDirectDisplayID) -> VirtualDisplayInstance? {
        lock.lock()
        defer { lock.unlock() }
        return associatedDummies[targetDisplayID]
    }

    /// Enables a virtual mirror for the given physical display: creates a virtual dummy display
    /// with HiDPI capability matching the requested dimensions and mirrors the target display to it.
    @discardableResult
    public func enableVirtualMirror(
        for targetDisplayID: CGDirectDisplayID,
        width: Int,
        height: Int
    ) throws -> CGDirectDisplayID {
        lock.lock()
        // If an existing dummy is active for this display, stop it first to ensure clean state
        if let existing = associatedDummies.removeValue(forKey: targetDisplayID) {
            existing.stop()
        }
        lock.unlock()

        var profile = VirtualDisplayProfile.profile(matchingWidth: width, height: height)
        // Ensure requested target HiDPI pixel size (width * 2, height * 2) is present in modes if within bounds
        let hiDPIW = max(width, width * 2)
        let hiDPIH = max(height, height * 2)
        if !profile.modes.contains(where: { $0.width == hiDPIW && $0.height == hiDPIH }) {
            profile.modes.insert(
                VirtualDisplayModeEntry(width: hiDPIW, height: hiDPIH, refreshRate: 60),
                at: 0
            )
        }

        let instance = VirtualDisplayInstance(
            profile: profile,
            customName: "HiDPI 源 (\(width)×\(height))"
        )
        try instance.start()

        guard let virtualID = instance.displayID, virtualID != kCGNullDirectDisplay else {
            instance.stop()
            throw VirtualDisplayError.virtualDisplayCreationFailed
        }

        var config: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&config)
        guard beginErr == .success, let cfg = config else {
            instance.stop()
            throw VirtualDisplayError.configurationFailed(beginErr)
        }

        let mirrorErr = CGConfigureDisplayMirrorOfDisplay(cfg, targetDisplayID, virtualID)
        if mirrorErr != .success {
            CGCancelDisplayConfiguration(cfg)
            instance.stop()
            throw VirtualDisplayError.configurationFailed(mirrorErr)
        }

        let completeErr = CGCompleteDisplayConfiguration(cfg, .forSession)
        if completeErr != .success {
            CGCancelDisplayConfiguration(cfg)
            instance.stop()
            throw VirtualDisplayError.configurationFailed(completeErr)
        }

        lock.lock()
        associatedDummies[targetDisplayID] = instance
        lock.unlock()

        return virtualID
    }

    /// Disables virtual mirroring for the target physical display and destroys the dummy display.
    public func disableVirtualMirror(for targetDisplayID: CGDirectDisplayID) throws {
        lock.lock()
        let instance = associatedDummies.removeValue(forKey: targetDisplayID)
        lock.unlock()

        var config: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&config)
        guard beginErr == .success, let cfg = config else {
            instance?.stop()
            throw VirtualDisplayError.configurationFailed(beginErr)
        }

        let mirrorErr = CGConfigureDisplayMirrorOfDisplay(cfg, targetDisplayID, kCGNullDirectDisplay)
        if mirrorErr != .success {
            CGCancelDisplayConfiguration(cfg)
            instance?.stop()
            throw VirtualDisplayError.configurationFailed(mirrorErr)
        }

        let completeErr = CGCompleteDisplayConfiguration(cfg, .forSession)
        if completeErr != .success {
            CGCancelDisplayConfiguration(cfg)
            instance?.stop()
            throw VirtualDisplayError.configurationFailed(completeErr)
        }

        instance?.stop()
    }

    /// Restores all display mirrors to native unmirrored state and tears down all active dummy instances.
    public func destroyAll() {
        lock.lock()
        let targets = Array(associatedDummies.keys)
        let instances = Array(associatedDummies.values)
        associatedDummies.removeAll()
        lock.unlock()

        if !targets.isEmpty {
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success, let cfg = config {
                for targetID in targets {
                    _ = CGConfigureDisplayMirrorOfDisplay(cfg, targetID, kCGNullDirectDisplay)
                }
                _ = CGCompleteDisplayConfiguration(cfg, .forSession)
            }
        }

        for instance in instances {
            instance.stop()
        }
    }
}
