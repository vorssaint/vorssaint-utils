// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.pwr_mgt

/// Quick subsystem check, run with `Vorssaint --selftest`.
/// Core capabilities fail the test; hardware-dependent readings only warn.
enum SelfTest {
    static func runAndExit() -> Never {
        var failures: [String] = []
        var warnings: [String] = []

        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Vorssaint selftest" as CFString,
                                                 &assertionID)
        if result == kIOReturnSuccess {
            IOPMAssertionRelease(assertionID)
        } else {
            failures.append("power assertion (\(result))")
        }

        if let memory = SystemInfo.memoryUsage() {
            if memory.total == 0 || memory.used > memory.total || memory.appUsed > memory.total
                || memory.compressed > memory.total || memory.cached > memory.total {
                failures.append("memory bounds")
            } else if memory.used == 0 {
                // Virtualized hosts can transiently report every page as
                // reclaimable cache; the reading is bounded but not useful.
                warnings.append("memory usage unavailable")
            }
            if memory.swapUsed == nil {
                failures.append("swap memory reading")
            }
        } else {
            failures.append("memory reading")
        }
        _ = SystemInfo.batterySnapshot() // may be nil on desktops

        if SystemInfo.wallClockUptimeSeconds() == nil {
            failures.append("uptime reading")
        }

        if let smc = SMCClient() {
            let keys = smc.keys { $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("Tg") }
            if keys.isEmpty {
                warnings.append("no SMC temperature keys")
            } else if keys.compactMap({ smc.readValue($0) }).isEmpty {
                warnings.append("SMC keys found but unreadable")
            }
        } else {
            warnings.append("AppleSMC unavailable")
        }

        // Network counters should be readable and never run backwards.
        let net1 = NetworkSampler.readCounters()
        let net2 = NetworkSampler.readCounters()
        if net1 == NetworkCounters(), net2 == NetworkCounters() {
            warnings.append("network counters unavailable")
        } else if net2.received < net1.received || net2.sent < net1.sent {
            failures.append("network counters decreased")
        }

        let diskCounters = DiskSampler.readCounters()
        let disks = DiskSampler().sample(now: ProcessInfo.processInfo.systemUptime)
        if diskCounters.isEmpty {
            warnings.append("disk counters unavailable")
        }
        if disks.isEmpty {
            warnings.append("no mounted disk volumes found")
        }

        // Power: laptops report battery/adapter flow; some desktops report nothing.
        if PowerSampler(smc: SMCClient()).sample().isEmpty {
            warnings.append("no power metrics on this Mac")
        }

        UserDefaults.standard.set("ok", forKey: "selftest")
        if UserDefaults.standard.string(forKey: "selftest") != "ok" {
            failures.append("UserDefaults")
        }
        UserDefaults.standard.removeObject(forKey: "selftest")

        for style in KeepAwakeActiveIcon.allCases {
            guard let image = BlackHoleGlyph.activeImage(style: style, tint: .orange) else {
                failures.append("Keep Awake icon \(style.rawValue)")
                continue
            }
            if image.size != BlackHoleGlyph.pointSize {
                failures.append("Keep Awake icon size \(style.rawValue)")
            }
            // image.size stays correct even when the symbol inside it is scaled
            // too large, so an overflow only shows as ink clipped by the canvas.
            if inkTouchesEdge(of: image) {
                failures.append("Keep Awake icon \(style.rawValue) is clipped by its canvas")
            }
        }

        // Tools/MakeIcon.swift writes the glyph PNGs at BlackHoleGlyph.pointSize.
        // Changing the canvas in one and not the other would squash the glyph.
        if Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") == nil {
            warnings.append("menu bar glyph asset not bundled")
        } else if let rep = BlackHoleGlyph.image(active: false)?
            .representations.min(by: { $0.pixelsWide < $1.pixelsWide }) {
            if rep.pixelsWide != Int(BlackHoleGlyph.pointSize.width)
                || rep.pixelsHigh != Int(BlackHoleGlyph.pointSize.height) {
                failures.append("menu bar glyph is \(rep.pixelsWide)×\(rep.pixelsHigh) px at 1x, "
                                + "expected \(Int(BlackHoleGlyph.pointSize.width))×"
                                + "\(Int(BlackHoleGlyph.pointSize.height))")
            }
        } else {
            failures.append("menu bar glyph representations")
        }

        for warning in warnings {
            print("SELFTEST WARNING: \(warning)")
        }
        if failures.isEmpty {
            print("SELFTEST OK")
            exit(0)
        } else {
            print("SELFTEST FAILED: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }

    /// Whether any visible pixel of `image` sits on its outermost row or column.
    /// Every menu bar glyph is drawn with a margin, so touching an edge means
    /// the artwork outgrew its canvas and is being cropped.
    private static func inkTouchesEdge(of image: NSImage) -> Bool {
        let sampling = 2
        let wide = Int(image.size.width) * sampling
        let high = Int(image.size.height) * sampling
        guard wide > 0, high > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The context draws in pixels, so fill the whole bitmap.
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(wide), height: CGFloat(high)))
        NSGraphicsContext.restoreGraphicsState()

        func visible(_ x: Int, _ y: Int) -> Bool {
            (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
        }
        for x in 0..<wide where visible(x, 0) || visible(x, high - 1) { return true }
        for y in 0..<high where visible(0, y) || visible(wide - 1, y) { return true }
        return false
    }
}

/// Prints every temperature sensor the monitor would consider, with its
/// classification. Run with `Vorssaint --sensors`; handy when porting
/// the sensor mapping to a new chip generation.
enum SensorDump {
    static func runAndExit() -> Never {
        guard let smc = SMCClient() else {
            print("AppleSMC unavailable")
            exit(1)
        }
        let keys = smc.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        let cpuPlatform = TemperatureSensorSelector.currentPlatform()
        let hasCPUCoreSet = TemperatureSensorSelector.hasCPUCoreSet(platform: cpuPlatform)
        print("component    key   type   °C")
        for key in keys.sorted(by: { $0.name < $1.name }) {
            guard let value = smc.readValue(key), value > 1, value < 125 else { continue }
            let component: String
            if key.name.hasPrefix("TB") {
                component = "battery"
            } else if key.name.hasPrefix("Tg") {
                component = "gpu"
            } else if hasCPUCoreSet {
                component = TemperatureSensorSelector.isCPUCoreKey(key.name, platform: cpuPlatform) ? "cpu-core" : "cpu-aux"
            } else {
                component = "cpu"
            }
            print(String(format: "%-11@  %@  %@  %6.2f",
                         component as NSString, key.name, key.dataType, value))
        }
        exit(0)
    }
}
