// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production battery segments, attributed attachments and image drawing with
/// isolated preferences and readings. No status item or hardware is opened.
enum MenuBarBatteryWarningTests {
    enum ReviewDefaults { static var current: UserDefaults! }
    enum MenuBarMetric { case battery, batteryTemperature }
    struct SystemSnapshot {
        var power: PowerReading?
        var batteryTemperature: Double?
    }
    enum Renderer {
        typealias MenuBarSegment = MenuBarBatteryWarningTests.MenuBarSegment
        typealias MenuBarBlockStyle = MenuBarBatteryWarningTests.MenuBarBlockStyle
        typealias SystemSnapshot = MenuBarBatteryWarningTests.SystemSnapshot
        typealias MenuBarMetric = MenuBarBatteryWarningTests.MenuBarMetric
        typealias MemoryPressure = MenuBarBatteryWarningTests.MemoryPressure
        typealias PowerReading = MenuBarBatteryWarningTests.PowerReading
        typealias ReviewDefaults = MenuBarBatteryWarningTests.ReviewDefaults
        typealias MenuBarMetricSpacing = MenuBarBatteryWarningTests.MenuBarMetricSpacing
        typealias MenuBarMetricAppearance = MenuBarBatteryWarningTests.MenuBarMetricAppearance
        static let blockImageCache = NSCache<NSString, NSImage>()
        static let legacyBlockAttachmentNudge: CGFloat = 0
        static var style = MenuBarBlockStyle.dense
        static var overrideSegments: [MenuBarSegment]?
        static func blockJoined(_ groups: [[MenuBarSegment]], style: MenuBarBlockStyle) -> [MenuBarSegment] {
            groups.flatMap { $0 }
        }
        static func segments(for snapshot: SystemSnapshot, metrics: [MenuBarMetric], allowStacked: Bool) -> [MenuBarSegment] {
            overrideSegments ?? blockSegments(for: snapshot, metrics: metrics, style: style)
        }
        static func usesStackedLayout(for snapshot: SystemSnapshot, metrics: [MenuBarMetric], allowStacked: Bool) -> Bool { false }
        // Unrelated branches of the production attributed-string renderer
        // must not be reached by this battery-only fixture.
        static func symbolAttachment(named: String, stacked: Bool, enlarged: Bool = false) -> NSAttributedString { preconditionFailure() }
        static func usageBarBlockAttachment(label: String, fraction: Double?, style: MenuBarBlockStyle,
                                            pressure: MemoryPressure?) -> NSAttributedString { preconditionFailure() }
        static func networkBlockAttachment(down: String, up: String, style: MenuBarBlockStyle) -> NSAttributedString { preconditionFailure() }
        static func diskActivityBlockAttachment(read: String, write: String, style: MenuBarBlockStyle) -> NSAttributedString { preconditionFailure() }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.menu-bar-battery-warning"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        ReviewDefaults.current = defaults
        defer {
            defaults.removePersistentDomain(forName: domain)
            ReviewDefaults.current = nil
            Renderer.overrideSegments = nil
            Renderer.blockImageCache.removeAllObjects()
        }
        defaults.set(true, forKey: DefaultsKey.notchLowBatteryTint)
        defaults.set(true, forKey: DefaultsKey.notchLowBatteryEarly)
        defaults.set(true, forKey: DefaultsKey.notchLowBatteryMenuBar)
        defaults.set(10, forKey: DefaultsKey.notchLowBatteryThreshold)
        defaults.set(20, forKey: DefaultsKey.notchLowBatteryEarlyThreshold)
        defaults.set(true, forKey: DefaultsKey.menuBarCombineTemperatures)
        segmentContracts(suite, defaults: defaults)
        imageContracts(suite, defaults: defaults)
    }

    private static func snapshot(_ percent: Int? = 10, temperature: Double? = 35, plugged: Bool = false) -> SystemSnapshot {
        var power = PowerReading()
        power.chargePercent = percent
        power.externalConnected = plugged
        return SystemSnapshot(power: power, batteryTemperature: temperature)
    }

    private static func warnings(_ segments: [MenuBarSegment]) -> [BatteryWarning] {
        segments.compactMap {
            switch $0 {
            case let .metricBlock(_, _, _, _, _, warning), let .batteryBlock(_, _, _, warning, _): return warning
            default: return nil
            }
        }
    }

    private static func segmentContracts(_ suite: TestSuite, defaults: UserDefaults) {
        for style in [MenuBarBlockStyle.readable, .dense] {
            for metrics: [MenuBarMetric] in [[.battery, .batteryTemperature], [.batteryTemperature, .battery]] {
                for (percent, warning): (Int, BatteryWarning) in [(10, .low), (15, .early), (25, .none)] {
                    let segments = Renderer.blockSegments(for: snapshot(percent), metrics: metrics, style: style)
                    suite.expect(segments.count == 1 && warnings(segments) == [warning],
                                 "a combined battery reading carries its warning in either order and block style")
                    if case let .metricBlock(label, value, minimum, _, pressure, _)? = segments.first {
                        suite.expect(label == "BAT" && value == "\(percent)% 35°" && minimum == "100% 999°" && pressure == nil,
                                     "the combined warning preserves the reading, reserved width and absence of a pressure dot")
                    } else { suite.expect(false, "charge and temperature remain one metric block") }
                }
            }
            for input in [snapshot(10, temperature: nil), snapshot(10)] {
                let metrics: [MenuBarMetric] = input.batteryTemperature == nil ? [.battery, .batteryTemperature] : [.battery]
                let segments = Renderer.blockSegments(for: input, metrics: metrics, style: style)
                if case let .batteryBlock(_, _, _, warning, _)? = segments.first {
                    suite.expect(warning == .low, "an isolated battery or missing temperature keeps its warning")
                } else { suite.expect(false, "charge without a combined temperature keeps the battery block") }
            }
            suite.expect(warnings(Renderer.blockSegments(for: snapshot(), metrics: [.batteryTemperature], style: style)) == [.none]
                         && warnings(Renderer.blockSegments(for: snapshot(nil), metrics: [.battery, .batteryTemperature], style: style)) == [.none],
                         "temperature alone never inherits a low-charge warning")
            defaults.set(false, forKey: DefaultsKey.menuBarCombineTemperatures)
            suite.expect(warnings(Renderer.blockSegments(for: snapshot(), metrics: [.battery, .batteryTemperature], style: style)) == [.low, .none],
                         "separate charge and temperature readings tint only the charge")
            defaults.set(true, forKey: DefaultsKey.menuBarCombineTemperatures)
        }
        for key in [DefaultsKey.notchLowBatteryTint, DefaultsKey.notchLowBatteryMenuBar] {
            defaults.set(false, forKey: key)
            suite.expect(warnings(Renderer.blockSegments(for: snapshot(), metrics: [.battery, .batteryTemperature], style: .dense)) == [.none],
                         "either disabled warning switch leaves combined readings untinted")
            defaults.set(true, forKey: key)
        }
        suite.expect(warnings(Renderer.blockSegments(for: snapshot(10, plugged: true), metrics: [.battery, .batteryTemperature], style: .dense)) == [.none],
                     "external power clears a combined battery warning")
    }

    private static func imageContracts(_ suite: TestSuite, defaults: UserDefaults) {
        func image(metrics: [MenuBarMetric] = [.battery, .batteryTemperature]) -> NSImage? {
            let attributed = Renderer.attributed(for: snapshot(), metrics: metrics)
            return attributed.length > 0 ? (attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.image : nil
        }
        for spacing in ["standard", "compact"] {
            defaults.set(spacing, forKey: DefaultsKey.menuBarMetricSpacing)
            for style in [MenuBarBlockStyle.readable, .dense] {
                Renderer.style = style
                for metrics: [MenuBarMetric] in [[.battery, .batteryTemperature], [.battery]] {
                    defaults.set(false, forKey: DefaultsKey.notchLowBatteryTint)
                    let plain = image(metrics: metrics)
                    defaults.set(true, forKey: DefaultsKey.notchLowBatteryTint)
                    defaults.set(10, forKey: DefaultsKey.notchLowBatteryThreshold)
                    let red = image(metrics: metrics)
                    defaults.set(5, forKey: DefaultsKey.notchLowBatteryThreshold)
                    let amber = image(metrics: metrics)
                    defaults.set(false, forKey: DefaultsKey.notchLowBatteryTint)
                    let recovered = image(metrics: metrics)
                    defaults.set(true, forKey: DefaultsKey.notchLowBatteryTint)
                    defaults.set(10, forKey: DefaultsKey.notchLowBatteryThreshold)
                    guard let plain, let red, let amber, let recovered else {
                        suite.expect(false, "battery readings produce image attachments")
                        continue
                    }
                    suite.expect(plain !== red && red !== amber && amber !== plain && recovered === plain,
                                 "warning colors have distinct cache entries and turning the warning off restores the untinted image")
                    suite.expect(plain.size == red.size && red.size == amber.size,
                                 "battery warning colors preserve block dimensions in both spacing modes")
                    suite.expect(matchingPixels(red, color: .systemRed) > 0 && matchingPixels(amber, color: .systemOrange) > 0
                                 && matchingPixels(plain, color: .systemRed) == 0 && matchingPixels(plain, color: .systemOrange) == 0,
                                 "the real attributed-image path draws red and amber, then returns to the normal text color")
                }
            }
        }
        Renderer.overrideSegments = [.metricBlock(label: "RAM", value: "42%", minimumValue: "100%", style: .dense, pressure: .warning)]
        let memory = image()
        suite.expect(warnings(Renderer.overrideSegments!) == [.none]
                     && memory.map { matchingPixels($0, color: .systemYellow) > 0 && matchingPixels($0, color: .systemRed) == 0 } == true,
                     "other metric blocks retain the default warning and their existing pressure color")
        Renderer.overrideSegments = nil
    }

    /// Force the actual NSImage drawing closure into a bitmap and inspect its
    /// pixels. This proves image color, not the appearance of a live status item.
    private static func matchingPixels(_ image: NSImage, color: NSColor) -> Int {
        var matches = 0
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: Int(ceil(image.size.width * 2)), pixelsHigh: Int(ceil(image.size.height * 2)),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            guard let target = color.usingColorSpace(.deviceRGB) else { return }
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), pixel.alphaComponent > 0.5 else { continue }
                    if abs(pixel.redComponent - target.redComponent) < 0.08
                        && abs(pixel.greenComponent - target.greenComponent) < 0.08
                        && abs(pixel.blueComponent - target.blueComponent) < 0.08 { matches += 1 }
                }
            }
        }
        return matches
    }
}
