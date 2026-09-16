// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
@preconcurrency import CoreGraphics
import Foundation
import os

/// Represents a display resolution mode with logical size, physical pixel size, refresh rate, and HiDPI capability.
public struct DisplayResolutionMode: Identifiable, Hashable, Sendable {
    public let id: String
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let modeNumber: Int32?

    public init(
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        modeNumber: Int32? = nil,
        isHiDPI: Bool? = nil,
        id: String? = nil
    ) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.modeNumber = modeNumber
        let hidpi = isHiDPI ?? (pixelWidth > width)
        self.isHiDPI = hidpi
        self.id = id ?? "\(width)x\(height)@\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), refreshRate))-\(pixelWidth)x\(pixelHeight)-\(hidpi ? "hidpi" : "std")-\(modeNumber ?? -1)"
    }

    public init(cgMode: CGDisplayMode) {
        self.init(
            width: cgMode.width,
            height: cgMode.height,
            pixelWidth: cgMode.pixelWidth,
            pixelHeight: cgMode.pixelHeight,
            refreshRate: cgMode.refreshRate,
            modeNumber: cgMode.ioDisplayModeID,
            isHiDPI: cgMode.pixelWidth > cgMode.width
        )
    }

    public init(cgsRecord: CGSDisplayModeRecord) {
        self.init(
            width: cgsRecord.width,
            height: cgsRecord.height,
            pixelWidth: cgsRecord.pixelWidth,
            pixelHeight: cgsRecord.pixelHeight,
            refreshRate: cgsRecord.refreshRate,
            modeNumber: cgsRecord.modeNumber,
            isHiDPI: cgsRecord.isHiDPI || (cgsRecord.pixelWidth > cgsRecord.width) || (cgsRecord.density >= 1.5)
        )
    }

    public var refreshLabel: String {
        if refreshRate > 0 {
            let rounded = (refreshRate * 100).rounded() / 100
            return String(format: "%g Hz", locale: Locale(identifier: "en_US_POSIX"), rounded)
        } else {
            return "动态"
        }
    }

    public var label: String {
        "\(width) × \(height) · \(refreshLabel)\(isHiDPI ? " · HiDPI" : "")"
    }

    public func matches(_ other: DisplayResolutionMode) -> Bool {
        width == other.width &&
        height == other.height &&
        pixelWidth == other.pixelWidth &&
        pixelHeight == other.pixelHeight &&
        abs(refreshRate - other.refreshRate) < 0.05
    }
}

/// Represents the HiDPI operational state of a display.
public enum HiDPIStatus: String, Sendable, CaseIterable, Equatable, Hashable {
    case none
    case native
    case virtualMirror
}

/// Aggregated service managing display resolutions, HiDPI modes, and display mutation transactions.
public final class DisplayResolutionService: ObservableObject, @unchecked Sendable {
    public static let shared = DisplayResolutionService()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
        category: "display-resolution"
    )

    @Published public private(set) var modesPerDisplay: [CGDirectDisplayID: [DisplayResolutionMode]] = [:]
    @Published public private(set) var currentModePerDisplay: [CGDirectDisplayID: DisplayResolutionMode] = [:]
    @Published public private(set) var hiDPIStatusPerDisplay: [CGDirectDisplayID: HiDPIStatus] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refresh()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Self.log.info("Screen parameters changed notification received; refreshing display resolution modes.")
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    /// Refreshes all active displays, available modes, current mode, and HiDPI status.
    public func refresh() {
        if Thread.isMainThread {
            _performRefresh()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._performRefresh()
            }
        }
    }

    private func _performRefresh() {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            modesPerDisplay = [:]
            currentModePerDisplay = [:]
            hiDPIStatusPerDisplay = [:]
            return
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return
        }

        let activeIDs = Array(displayIDs.prefix(Int(count)))
        var newModesPerDisplay: [CGDirectDisplayID: [DisplayResolutionMode]] = [:]
        var newCurrentModePerDisplay: [CGDirectDisplayID: DisplayResolutionMode] = [:]
        var newHiDPIStatusPerDisplay: [CGDirectDisplayID: HiDPIStatus] = [:]

        for displayID in activeIDs {
            let availableModes = queryModes(for: displayID)
            newModesPerDisplay[displayID] = availableModes

            // Detect current mode for display
            if let currentCG = CGDisplayCopyDisplayMode(displayID) {
                let currentRaw = DisplayResolutionMode(cgMode: currentCG)
                let currentMode = availableModes.first(where: { $0.matches(currentRaw) }) ?? currentRaw
                newCurrentModePerDisplay[displayID] = currentMode

                // Determine HiDPIStatus
                let status: HiDPIStatus
                if VirtualDisplayService.shared.isVirtualMirrorActive(for: displayID) {
                    status = .virtualMirror
                } else if currentMode.isHiDPI {
                    status = .native
                } else {
                    status = .none
                }
                newHiDPIStatusPerDisplay[displayID] = status
            } else {
                let status: HiDPIStatus = VirtualDisplayService.shared.isVirtualMirrorActive(for: displayID) ? .virtualMirror : .none
                newHiDPIStatusPerDisplay[displayID] = status
            }
        }

        self.modesPerDisplay = newModesPerDisplay
        self.currentModePerDisplay = newCurrentModePerDisplay
        self.hiDPIStatusPerDisplay = newHiDPIStatusPerDisplay
    }

    /// Queries all available display modes for a given display ID, combining CGDisplay modes and CGS private modes.
    public func queryModes(for displayID: CGDirectDisplayID) -> [DisplayResolutionMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let cgModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []).filter {
            $0.isUsableForDesktopGUI()
        }
        let publicModes = cgModes.map { DisplayResolutionMode(cgMode: $0) }
        let cgsRecords = SkyLightBridge.queryCGSModes(for: displayID)

        var result = publicModes
        let maxMode = publicModes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) })
        let nativeAspect = (maxMode != nil && maxMode!.height > 0) ? Double(maxMode!.width) / Double(maxMode!.height) : 0.0

        for r in cgsRecords where r.isUsable {
            if nativeAspect > 0 {
                let aspect = Double(r.width) / Double(r.height)
                if abs(aspect - nativeAspect) / nativeAspect >= 0.03 {
                    continue
                }
            }

            let newMode = DisplayResolutionMode(cgsRecord: r)
            if let idx = result.firstIndex(where: { $0.matches(newMode) }) {
                if result[idx].modeNumber == nil && newMode.modeNumber != nil {
                    result[idx] = newMode
                }
            } else {
                result.append(newMode)
            }
        }

        if let currentCG = CGDisplayCopyDisplayMode(displayID) {
            let currentMode = DisplayResolutionMode(cgMode: currentCG)
            if !result.contains(where: { $0.matches(currentMode) }) {
                result.append(currentMode)
            }
        }

        result.sort { lhs, rhs in
            let lhsArea = lhs.width * lhs.height
            let rhsArea = rhs.width * rhs.height
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.width != rhs.width {
                return lhs.width > rhs.width
            }
            if lhs.isHiDPI != rhs.isHiDPI {
                return lhs.isHiDPI && !rhs.isHiDPI
            }
            return lhs.refreshRate > rhs.refreshRate
        }

        return result
    }

    /// Applies a resolution mode for the target display, optionally protected by the 15-second watchdog timer.
    @discardableResult
    public func applyMode(
        _ mode: DisplayResolutionMode,
        for displayID: CGDirectDisplayID,
        useWatchdog: Bool = true
    ) -> Bool {
        // If a virtual mirror was active for this display, disable it before applying the native mode
        if VirtualDisplayService.shared.isVirtualMirrorActive(for: displayID) {
            do {
                try VirtualDisplayService.shared.disableVirtualMirror(for: displayID)
            } catch {
                Self.log.error("Failed to disable virtual mirror prior to mode switch: \(error.localizedDescription)")
            }
        }

        let currentCGMode = CGDisplayCopyDisplayMode(displayID)
        let mirrorMaster = CGDisplayMirrorsDisplay(displayID)
        let currentMirrorMasterID: CGDirectDisplayID? = (mirrorMaster != kCGNullDirectDisplay) ? mirrorMaster : nil
        let currentCGSModeNumber: Int32? = currentModePerDisplay[displayID]?.modeNumber ?? currentCGMode?.ioDisplayModeID

        if useWatchdog {
            DisplayRecoveryManager.shared.beginAction(
                targetDisplayID: displayID,
                previousMode: currentCGMode,
                previousCGSModeNumber: currentCGSModeNumber,
                previousMirrorMasterID: currentMirrorMasterID,
                virtualDisplayCreated: false,
                confirmationSeconds: 15
            )
        }

        var config: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&config)
        guard beginErr == .success, let cfg = config else {
            Self.log.error("CGBeginDisplayConfiguration failed: \(beginErr.rawValue)")
            if useWatchdog {
                DisplayRecoveryManager.shared.confirm()
            }
            return false
        }

        var applied = false

        if let modeNumber = mode.modeNumber {
            let err = SkyLightBridge.configureDisplayMode(config: cfg, displayID: displayID, modeNumber: modeNumber)
            if err == .success {
                applied = true
            } else {
                Self.log.warning("SkyLightBridge.configureDisplayMode modeNumber \(modeNumber) failed with error \(err.rawValue), falling back to CGConfigureDisplayWithDisplayMode")
            }
        }

        if !applied {
            let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
            let allModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
            if let targetCGMode = allModes.first(where: {
                $0.width == mode.width &&
                $0.height == mode.height &&
                $0.pixelWidth == mode.pixelWidth &&
                $0.pixelHeight == mode.pixelHeight &&
                abs($0.refreshRate - mode.refreshRate) < 0.05
            }) ?? allModes.first(where: {
                $0.width == mode.width &&
                $0.height == mode.height &&
                abs($0.refreshRate - mode.refreshRate) < 0.05
            }) {
                let err = CGConfigureDisplayWithDisplayMode(cfg, displayID, targetCGMode, nil)
                if err == .success {
                    applied = true
                } else {
                    Self.log.error("CGConfigureDisplayWithDisplayMode failed: \(err.rawValue)")
                }
            }
        }

        guard applied else {
            CGCancelDisplayConfiguration(cfg)
            Self.log.error("Unable to find suitable CGDisplayMode for \(mode.label) on display \(displayID)")
            if useWatchdog {
                DisplayRecoveryManager.shared.confirm()
            }
            refresh()
            return false
        }

        let completeErr = CGCompleteDisplayConfiguration(cfg, .forSession)
        if completeErr == .success {
            Self.log.info("Successfully applied display mode \(mode.label) to display \(displayID)")
            refresh()
            return true
        } else {
            Self.log.error("CGCompleteDisplayConfiguration failed: \(completeErr.rawValue)")
            CGCancelDisplayConfiguration(cfg)
            if useWatchdog {
                DisplayRecoveryManager.shared.rollback()
            }
            refresh()
            return false
        }
    }

    /// Intelligently toggles HiDPI mode on the specified display:
    /// - If `.virtualMirror`: disables virtual mirror to revert to native resolution.
    /// - If `.native`: switches to matching standard (1x) mode with identical dimensions.
    /// - If `.none`: switches to matching native HiDPI mode, or creates virtual mirror dummy display if no native HiDPI mode exists.
    public func toggleHiDPI(for displayID: CGDirectDisplayID) {
        let currentStatus = hiDPIStatusPerDisplay[displayID] ?? (
            VirtualDisplayService.shared.isVirtualMirrorActive(for: displayID) ? .virtualMirror :
            ((currentModePerDisplay[displayID]?.isHiDPI ?? false) ? .native : .none)
        )

        guard let current = currentModePerDisplay[displayID] ?? (
            CGDisplayCopyDisplayMode(displayID).map { DisplayResolutionMode(cgMode: $0) }
        ) else {
            Self.log.error("Cannot toggle HiDPI: unable to determine current mode for display \(displayID)")
            return
        }

        switch currentStatus {
        case .virtualMirror:
            Self.log.info("Toggling HiDPI from virtualMirror -> disabling virtual mirror on display \(displayID)")
            do {
                try VirtualDisplayService.shared.disableVirtualMirror(for: displayID)
            } catch {
                Self.log.error("Failed to disable virtual mirror for display \(displayID): \(error.localizedDescription)")
            }
            refresh()

        case .native:
            Self.log.info("Toggling HiDPI from native -> finding standard mode for display \(displayID)")
            let available = modesPerDisplay[displayID] ?? queryModes(for: displayID)
            let candidates = available.filter { !$0.isHiDPI && $0.width == current.width && $0.height == current.height }
            if let target = candidates.min(by: { abs($0.refreshRate - current.refreshRate) < abs($1.refreshRate - current.refreshRate) }) {
                applyMode(target, for: displayID, useWatchdog: true)
            } else {
                Self.log.warning("No matching standard non-HiDPI mode found for \(current.width) × \(current.height) on display \(displayID)")
            }

        case .none:
            Self.log.info("Toggling HiDPI from none -> looking for native HiDPI mode or fallback to virtual mirror on display \(displayID)")
            let available = modesPerDisplay[displayID] ?? queryModes(for: displayID)
            let candidates = available.filter { $0.isHiDPI && $0.width == current.width && $0.height == current.height }
            if let nativeHiDPI = candidates.min(by: { abs($0.refreshRate - current.refreshRate) < abs($1.refreshRate - current.refreshRate) }) {
                Self.log.info("Found native HiDPI mode \(nativeHiDPI.label); applying mode")
                applyMode(nativeHiDPI, for: displayID, useWatchdog: true)
            } else {
                Self.log.info("No native HiDPI mode found for \(current.width) × \(current.height); enabling virtual mirror")
                let currentCGMode = CGDisplayCopyDisplayMode(displayID)
                let mirrorMaster = CGDisplayMirrorsDisplay(displayID)
                let currentMirrorMasterID: CGDirectDisplayID? = (mirrorMaster != kCGNullDirectDisplay) ? mirrorMaster : nil
                let currentCGSModeNumber: Int32? = current.modeNumber ?? currentCGMode?.ioDisplayModeID

                DisplayRecoveryManager.shared.beginAction(
                    targetDisplayID: displayID,
                    previousMode: currentCGMode,
                    previousCGSModeNumber: currentCGSModeNumber,
                    previousMirrorMasterID: currentMirrorMasterID,
                    virtualDisplayCreated: true,
                    confirmationSeconds: 15
                )

                do {
                    try VirtualDisplayService.shared.enableVirtualMirror(
                        for: displayID,
                        width: current.width,
                        height: current.height
                    )
                    Self.log.info("Successfully enabled virtual mirror HiDPI for display \(displayID)")
                } catch {
                    Self.log.error("Failed to enable virtual mirror for display \(displayID): \(error.localizedDescription)")
                    DisplayRecoveryManager.shared.confirm()
                }
                refresh()
            }
        }
    }
}
