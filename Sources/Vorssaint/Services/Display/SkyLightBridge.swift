// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics
import Darwin

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

    public init(from desc: CGSDisplayModeDescription) {
        self.modeNumber = Int32(bitPattern: desc.modeNumber)
        self.width = Int(desc.width)
        self.height = Int(desc.height)
        self.density = desc.density
        self.flags = desc.flags
        self.refreshRate = Double(desc.freq)
        self.pixelWidth = Int((Float(desc.width) * desc.density).rounded())
        self.pixelHeight = Int((Float(desc.height) * desc.density).rounded())
        self.isHiDPI = desc.density >= 1.5
        self.isUsable = (desc.flags & 0x40000000) == 0
    }
}

public enum SkyLightBridge {
    private typealias CGSGetNumberOfDisplayModesFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias CGSGetDisplayModeDescriptionOfLengthFn = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Int32
    private typealias CGSConfigureDisplayModeFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> Int32

    private static let skyLightHandle: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)

    private static func lookup<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = skyLightHandle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    public static func queryCGSModes(for displayID: CGDirectDisplayID) -> [CGSDisplayModeRecord] {
        guard let getCount = lookup("CGSGetNumberOfDisplayModes", as: CGSGetNumberOfDisplayModesFn.self),
              let getDesc = lookup("CGSGetDisplayModeDescriptionOfLength", as: CGSGetDisplayModeDescriptionOfLengthFn.self)
        else { return [] }

        var count: Int32 = 0
        guard getCount(displayID, &count) == 0, count > 0 else { return [] }

        let length = Int32(MemoryLayout<CGSDisplayModeDescription>.size)
        var records: [CGSDisplayModeRecord] = []
        for i in 0..<count {
            var desc = CGSDisplayModeDescription()
            guard getDesc(displayID, i, &desc, length) == 0 else { continue }
            records.append(CGSDisplayModeRecord(from: desc))
        }
        return records
    }

    public static func configureDisplayMode(config: CGDisplayConfigRef?, displayID: CGDirectDisplayID, modeNumber: Int32) -> CGError {
        guard let configMode = lookup("CGSConfigureDisplayMode", as: CGSConfigureDisplayModeFn.self) else {
            return .failure
        }
        let res = configMode(config, displayID, modeNumber)
        return CGError(rawValue: res) ?? (res == 0 ? .success : .failure)
    }
}
