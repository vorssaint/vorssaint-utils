// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

public struct CGSDisplayModeDescription {
    public var modeNumber: UInt32 = 0
    public var flags: UInt32 = 0
    public var width: UInt32 = 0
    public var height: UInt32 = 0
    public var depth: UInt32 = 0
    public var dc2: (
        UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
        UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
        UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
        UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
        UInt32, UInt32
    ) = (0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0)
    public var dc3: UInt16 = 0
    public var freq: UInt16 = 0
    public var dc4: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
    public var density: Float = 1.0

    public init() {}
}

public struct CGSDisplayModeRecord: Sendable, Equatable {
    /// Index in SkyLight's display-mode array. This is the value expected by
    /// CGSConfigureDisplayMode; it is not CGDisplayMode.ioDisplayModeID.
    public let modeNumber: Int32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let density: Float
    public let flags: UInt32
    public let isHiDPI: Bool
    public let isUsable: Bool

    public init(
        modeNumber: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        density: Float,
        flags: UInt32,
        isHiDPI: Bool,
        isUsable: Bool
    ) {
        self.modeNumber = modeNumber
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.density = density
        self.flags = flags
        self.isHiDPI = isHiDPI
        self.isUsable = isUsable
    }

    public init(from desc: CGSDisplayModeDescription, modeIndex: Int32) {
        modeNumber = modeIndex
        width = Int(desc.width)
        height = Int(desc.height)
        density = desc.density
        flags = desc.flags
        refreshRate = Double(desc.freq)
        pixelWidth = Int((Float(desc.width) * desc.density).rounded())
        pixelHeight = Int((Float(desc.height) * desc.density).rounded())
        isHiDPI = desc.density >= 1.5
        isUsable = (desc.flags & 0x40000000) == 0
    }
}

public enum SkyLightBridge {
    // The long-standing private CGS ABI exposes these as void functions.
    // Treating the undefined return register as a CGError made behavior
    // architecture-dependent and could randomly discard otherwise valid modes.
    private typealias CGSGetCurrentDisplayModeFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias CGSGetNumberOfDisplayModesFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias CGSGetDisplayModeDescriptionOfLengthFn =
        @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Void
    private typealias CGSConfigureDisplayModeFn =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> Void

    private static let skyLightHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
               RTLD_LAZY | RTLD_LOCAL)

    private static func lookup<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = skyLightHandle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    public static func currentDisplayModeIndex(for displayID: CGDirectDisplayID) -> Int32? {
        guard let getCurrent = lookup("CGSGetCurrentDisplayMode",
                                      as: CGSGetCurrentDisplayModeFn.self) else { return nil }
        var index: Int32 = -1
        getCurrent(displayID, &index)
        return index >= 0 ? index : nil
    }

    public static func queryCGSModes(for displayID: CGDirectDisplayID) -> [CGSDisplayModeRecord] {
        guard let getCount = lookup("CGSGetNumberOfDisplayModes",
                                    as: CGSGetNumberOfDisplayModesFn.self),
              let getDesc = lookup("CGSGetDisplayModeDescriptionOfLength",
                                   as: CGSGetDisplayModeDescriptionOfLengthFn.self)
        else { return [] }

        var count: Int32 = 0
        getCount(displayID, &count)
        guard count > 0, count < 1024 else { return [] }

        let length = Int32(MemoryLayout<CGSDisplayModeDescription>.size)
        var records: [CGSDisplayModeRecord] = []
        records.reserveCapacity(Int(count))
        for index in 0..<count {
            var desc = CGSDisplayModeDescription()
            getDesc(displayID, index, &desc, length)
            guard desc.width > 0, desc.height > 0, desc.density.isFinite, desc.density > 0 else {
                continue
            }
            records.append(CGSDisplayModeRecord(from: desc, modeIndex: index))
        }
        return records
    }

    /// The private function itself does not return a status code. The public
    /// CGCompleteDisplayConfiguration call remains the transaction boundary.
    @discardableResult
    public static func configureDisplayMode(
        config: CGDisplayConfigRef?,
        displayID: CGDirectDisplayID,
        modeNumber: Int32
    ) -> Bool {
        guard let configure = lookup("CGSConfigureDisplayMode",
                                     as: CGSConfigureDisplayModeFn.self) else { return false }
        configure(config, displayID, modeNumber)
        return true
    }
}
