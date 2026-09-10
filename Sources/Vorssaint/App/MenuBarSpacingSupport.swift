// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// How tightly the menu bar metric blocks pack together. The standard reserve
/// keeps every number rock-steady by sizing blocks for their largest possible
/// value, which reads as wide gaps on short values (user feedback); compact
/// hugs the current number instead.
enum MenuBarMetricSpacing: String, CaseIterable {
    case standard, compact

    static var current: MenuBarMetricSpacing {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarMetricSpacing) ?? ""
        return MenuBarMetricSpacing(rawValue: Defaults.sanitizedMenuBarMetricSpacing(raw)) ?? .standard
    }
}
/// How a percentage-based monitor reading appears in the menu bar. Values keep
/// the numeric block; bars replace it with a compact vertical gauge. CPU, GPU,
/// memory, disk usage, battery and accessory batteries each pick independently,
/// falling back to the global setting until the user sets one. Readings without
/// a fixed 0...100 scale stay numeric.
enum MenuBarMetricAppearance: String, CaseIterable {
    case values, bars

    var allowsCombinedTemperatures: Bool { self == .values }

    static let barCapableAppearanceKeys = [
        DefaultsKey.menuBarCPUAppearance,
        DefaultsKey.menuBarGPUAppearance,
        DefaultsKey.menuBarMemoryAppearance,
        DefaultsKey.menuBarDiskUsageAppearance,
        DefaultsKey.menuBarBatteryAppearance,
        DefaultsKey.menuBarPeripheralBatteryAppearance,
    ]

    static var current: MenuBarMetricAppearance { current(in: .standard) }

    static func current(in defaults: UserDefaults = .standard) -> MenuBarMetricAppearance {
        let raw = defaults.string(forKey: DefaultsKey.menuBarMetricAppearance) ?? ""
        return MenuBarMetricAppearance(rawValue: Defaults.sanitizedMenuBarMetricAppearance(raw)) ?? .values
    }

    /// Resolves one metric's display. An empty per-item value inherits the
    /// global setting so existing "all bars" or "all values" choices survive.
    static func current(appearanceKey: String?,
                        in defaults: UserDefaults = .standard) -> MenuBarMetricAppearance {
        guard let appearanceKey else { return .values }
        let raw = defaults.string(forKey: appearanceKey) ?? ""
        if raw.isEmpty { return current(in: defaults) }
        return MenuBarMetricAppearance(rawValue: Defaults.sanitizedMenuBarMetricAppearance(raw)) ?? .values
    }

    static func usesBars(appearanceKey: String?,
                         in defaults: UserDefaults = .standard) -> Bool {
        current(appearanceKey: appearanceKey, in: defaults) == .bars
    }

    static func anyUsesBars(in defaults: UserDefaults = .standard) -> Bool {
        barCapableAppearanceKeys.contains { usesBars(appearanceKey: $0, in: defaults) }
    }
}

/// Native menu-bar battery: the system outline with a live fill and charging
/// cutout, yellow while Low Power Mode is on.
enum MenuBarBatterySupport {
    /// Optical size of the macOS menu bar / Control Center battery.
    static let symbolPointSize: CGFloat = 18

    static let valueColor = NSColor.textColor
    static let outlineColor = NSColor.textColor
    static let lowPowerColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.19, alpha: 0.88)

    static let glyphSize: CGSize =
        makeBatterySymbol(named: "battery.100percent", color: .labelColor)?.size
        ?? CGSize(width: 31, height: 14)

    static func symbolName(for percent: Int,
                           isCharging: Bool,
                           isPluggedIn: Bool = false) -> String {
        if isCharging { return "battery.100percent.bolt" }
        if isPluggedIn { return "powercord.fill" }
        switch max(0, min(100, percent)) {
        case 90...: return "battery.100percent"
        case 65..<90: return "battery.75percent"
        case 40..<65: return "battery.50percent"
        case 15..<40: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    static func symbolColor(lowPowerMode: Bool) -> NSColor {
        lowPowerMode ? lowPowerColor : valueColor
    }

    static func fillFraction(_ percent: Int) -> CGFloat {
        CGFloat(max(0, min(100, percent))) / 100
    }

    static func fillRect(in rect: NSRect, percent: Int) -> NSRect {
        let xScale = rect.width / glyphSize.width
        let yScale = rect.height / glyphSize.height
        return NSRect(x: rect.minX + 4 * xScale,
                      y: rect.minY + 3 * yScale,
                      width: 19 * xScale * fillFraction(percent),
                      height: 8 * yScale)
    }

    static func glyphImage(percent: Int,
                           isCharging: Bool,
                           isPluggedIn: Bool,
                           lowPowerMode: Bool,
                           tint: NSColor? = nil) -> NSImage {
        let outlineColor = tint ?? MenuBarBatterySupport.outlineColor
        let fillColor = lowPowerMode ? lowPowerColor : (tint ?? valueColor)
        let size = glyphSize
        let image = NSImage(size: size, flipped: false) { rect in
            drawGlyph(in: rect,
                      percent: percent,
                      isCharging: isCharging,
                      isPluggedIn: isPluggedIn,
                      outlineColor: outlineColor,
                      fillColor: fillColor)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func drawGlyph(in rect: NSRect,
                          percent: Int,
                          isCharging: Bool,
                          isPluggedIn: Bool,
                          outlineColor: NSColor,
                          fillColor: NSColor) {
        guard let empty = makeBatterySymbol(named: "battery.0percent",
                                            color: outlineColor.withAlphaComponent(0.75)) else { return }

        let fillRect = fillRect(in: rect, percent: percent)
        if fillRect.width > 0 {
            fillColor.setFill()
            let radius = min(fillRect.width, fillRect.height) / 2
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
        }
        empty.draw(in: rect)

        if isCharging,
           let bolt = makeMonochromeSymbol(named: "bolt.fill", pointSize: 11, color: outlineColor) {
            if fillFraction(percent) < 0.75 {
                let centered = rect.offsetBy(dx: -2, dy: 0)
                // Until the fill covers the whole bolt, a cutout erases part
                // of its shape. Use the foreground with clearance from the fill.
                if let cutout = makeMonochromeSymbol(named: "bolt.fill", pointSize: 15, color: .white) {
                    drawCentered(cutout, in: centered, operation: .destinationOut)
                }
                drawCentered(bolt, in: centered)
            } else {
                drawCentered(bolt, in: rect.offsetBy(dx: -2, dy: 0), operation: .destinationOut)
            }
        } else if isPluggedIn {
            drawPlug(in: rect, color: fillColor)
        }
    }

    private static func makeBatterySymbol(named name: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = false
        return image
    }

    private static func makeMonochromeSymbol(named name: String,
                                             pointSize: CGFloat,
                                             color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private static func drawPlug(in rect: NSRect, color: NSColor) {
        guard let cutout = makeMonochromeSymbol(named: "powerplug.portrait.fill",
                                                pointSize: 16.5,
                                                color: .white),
              let plug = makeMonochromeSymbol(named: "powerplug.portrait.fill",
                                              pointSize: 11.5,
                                              color: color) else { return }
        let centered = rect.offsetBy(dx: -2, dy: 0)
        drawCentered(cutout, in: centered, operation: .destinationOut)
        drawCentered(plug, in: centered)
    }

    private static func drawCentered(_ image: NSImage,
                                     in rect: NSRect,
                                     operation: NSCompositingOperation = .sourceOver) {
        image.draw(in: NSRect(x: rect.midX - image.size.width / 2,
                              y: rect.midY - image.size.height / 2,
                              width: image.size.width,
                              height: image.size.height),
                   from: .zero,
                   operation: operation,
                   fraction: 1,
                   respectFlipped: true,
                   hints: nil)
    }
}

enum MenuBarUsageBarSupport {
    static let defaultNormalColor = "#64D2FF"
    static let defaultElevatedColor = "#FFD60A"
    static let defaultCriticalColor = "#FF453A"
    static let defaultMediumThreshold = 70
    static let defaultHighThreshold = 90

    enum Level {
        case normal, elevated, critical
    }

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func memoryFraction(used: UInt64?, total: UInt64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return clampedFraction(Double(used) / Double(total))
    }

    static func percentFraction(_ percent: Int) -> Double {
        clampedFraction(Double(percent) / 100)
    }

    static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    /// Quantizing to the number of drawable pixels keeps the image cache
    /// bounded while retaining every visible fill level.
    static func fillLevel(for fraction: Double, steps: Int) -> Int {
        guard steps > 0 else { return 0 }
        return Int((clampedFraction(fraction) * Double(steps)).rounded())
    }

    static func thresholds(medium: Int, high: Int) -> (medium: Int, high: Int) {
        let medium = min(99, max(1, medium))
        let high = min(100, max(medium + 1, high))
        return (medium, high)
    }

    static func level(for fraction: Double,
                      mediumPercent: Int = defaultMediumThreshold,
                      highPercent: Int = defaultHighThreshold) -> Level {
        let thresholds = thresholds(medium: mediumPercent, high: highPercent)
        let percent = clampedFraction(fraction) * 100
        switch percent {
        case Double(thresholds.high)...: return .critical
        case Double(thresholds.medium)...: return .elevated
        default: return .normal
        }
    }

    static func currentLevel(for fraction: Double,
                             defaults: UserDefaults = .standard) -> Level {
        level(for: fraction,
              mediumPercent: defaults.integer(forKey: DefaultsKey.menuBarUsageBarMediumThreshold),
              highPercent: defaults.integer(forKey: DefaultsKey.menuBarUsageBarHighThreshold))
    }

    static func currentColorHex(for level: Level,
                                defaults: UserDefaults = .standard) -> String {
        switch level {
        case .normal:
            return sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarUsageBarNormalColor),
                                     fallback: defaultNormalColor)
        case .elevated:
            return sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarUsageBarElevatedColor),
                                     fallback: defaultElevatedColor)
        case .critical:
            return sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarUsageBarCriticalColor),
                                     fallback: defaultCriticalColor)
        }
    }

    static func sanitizedColorHex(_ raw: String?, fallback: String) -> String {
        let fallback = normalizedColorHex(fallback) ?? defaultNormalColor
        guard let raw, let normalized = normalizedColorHex(raw) else { return fallback }
        return normalized
    }

    static func rgb(for raw: String?, fallback: String) -> RGB {
        let hex = sanitizedColorHex(raw, fallback: fallback)
        let digits = String(hex.dropFirst())
        let value = UInt64(digits, radix: 16) ?? 0
        return RGB(red: Double((value >> 16) & 0xFF) / 255,
                   green: Double((value >> 8) & 0xFF) / 255,
                   blue: Double(value & 0xFF) / 255)
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        let components = [red, green, blue].map {
            Int((clampedFraction($0) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    private static func normalizedColorHex(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard digits.count == 6,
              digits.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { return nil }
        return "#" + digits
    }

}

enum MenuBarSpacingSupport {
    /// Idle CPU/GPU readings live right at the one-to-two digit boundary
    /// (4% one tick, 10% the next); reserving the bare current digit count
    /// made the whole bar wobble on every crossing. Two digits cover 0-99
    /// without ever moving.
    static let compactMinimumDigits = 2

    /// Highest digit count each block has shown this session, so a spike to
    /// three digits widens that block once and keeps it there instead of
    /// letting the width oscillate while the value hovers at the boundary.
    /// Touched only on the main thread (status item refresh and the settings
    /// preview both render there).
    private static var digitHighWater: [String: Int] = [:]

    /// A finite Keep Awake countdown is the only menu-bar content whose text
    /// changes just because time passed. Everything else refreshes from its
    /// publisher or preference change, so no timer should live at rest.
    static func needsTitleRefreshTimer(keepAwakeActive: Bool,
                                       showsCountdown: Bool,
                                       hasEndDate: Bool) -> Bool {
        keepAwakeActive && showsCountdown && hasEndDate
    }

    /// The reserve compact mode uses for a metric block: the current value's
    /// shape, widened to at least `compactMinimumDigits` digits and to the
    /// block's session high-water mark. Stable by construction; still far
    /// narrower than reserving each metric's absolute maximum.
    static func compactReserve(label: String, value: String) -> String {
        let digits = value.filter(\.isNumber).count
        let floor = compactFloor(currentDigits: digits, highWater: digitHighWater[label])
        digitHighWater[label] = floor
        return digitMatchedReserve(for: value, minimumDigits: floor)
    }

    static func compactFloor(currentDigits: Int, highWater: Int?) -> Int {
        max(currentDigits, compactMinimumDigits, highWater ?? 0)
    }

    /// A same-width stand-in for the value ("14%" gives "88%"), padded with
    /// extra digits in front of the first number until `minimumDigits` is
    /// met ("4%" with a minimum of 2 gives "88%"). Values without digits are
    /// returned shape-for-shape.
    static func digitMatchedReserve(for value: String, minimumDigits: Int = 0) -> String {
        var out = ""
        var digitCount = value.filter(\.isNumber).count
        var padded = false
        for character in value {
            if character.isNumber, !padded {
                while digitCount < minimumDigits {
                    out.append("8")
                    digitCount += 1
                }
                padded = true
            }
            out.append(character.isNumber ? "8" : character)
        }
        return out
    }

    /// The glue string drawn between two metric blocks.
    static func blockGlue(readableStyle: Bool, spacing: MenuBarMetricSpacing) -> String {
        switch spacing {
        case .standard: return readableStyle ? "  " : " "
        case .compact: return readableStyle ? " " : "\u{200A}"
        }
    }

    /// Whether the app glyph may hide so the menu bar shows metrics only
    /// (user request). Every gate protects the same invariant: the status
    /// item must never end up with no image and no text, and hiding must
    /// never swallow a signal the user opted into.
    /// - `metricsEnabled` keeps a countdown-only title from hiding the glyph.
    /// - `renderedTitleLength` covers the launch gap where metrics are on
    ///   but the first sample has not landed yet (empty title).
    /// - `separateMetrics` keeps the glyph when metrics live in their own
    ///   status items and the main one would otherwise be empty.
    /// - `mustShowForSignal` brings the glyph back while it carries a signal
    ///   (update available, mic muted indicator).
    static func shouldHideStatusIcon(optionEnabled: Bool,
                                     separateMetrics: Bool,
                                     metricsEnabled: Bool,
                                     renderedTitleLength: Int,
                                     mustShowForSignal: Bool) -> Bool {
        optionEnabled
            && !separateMetrics
            && metricsEnabled
            && renderedTitleLength > 0
            && !mustShowForSignal
    }

    /// Whether the whole main status item may hide in the separate-items
    /// mode, where each metric is its own clickable item and the main one
    /// carries only the glyph. It may only vanish while at least one metric
    /// item is actually installed (the panel stays reachable through them),
    /// its own title is empty (an active countdown renders there and must
    /// not disappear), and no signal needs the glyph back.
    static func shouldHideMainStatusItem(optionEnabled: Bool,
                                         separateMetrics: Bool,
                                         metricItemsShown: Int,
                                         renderedTitleLength: Int,
                                         mustShowForSignal: Bool) -> Bool {
        optionEnabled
            && separateMetrics
            && metricItemsShown > 0
            && renderedTitleLength == 0
            && !mustShowForSignal
    }

    /// How many refreshes in a row a metric may render nothing before its item
    /// goes. Long enough to ride out a sensor that skips a tick, short enough
    /// that a reading which stops for good does not leave an empty slot behind.
    /// Refreshes come from the monitor tick and from anything else that redraws
    /// the bar, so this is a small number of seconds, not an exact delay.
    static let emptyMetricRendersBeforeRemoval = 5

    /// Whether a pinned metric keeps its own item in the menu bar right now.
    /// A reading that is momentarily unavailable renders nothing for a tick,
    /// and taking the item away and putting it back for that is both a
    /// visible flicker and the churn the menu bar copes with worst. An item
    /// that already exists stays and goes blank, until the reading has been
    /// missing long enough to call it gone.
    static func keepsMetricStatusItem(hasRenderedTitle: Bool,
                                      itemExists: Bool,
                                      consecutiveEmptyRenders: Int = 0) -> Bool {
        if hasRenderedTitle { return true }
        guard itemExists else { return false }
        return consecutiveEmptyRenders < emptyMetricRendersBeforeRemoval
    }
}

enum StatusItemPlacementSupport {
    static let mainAutosaveName = "VorssaintMenuBarItem"
    static let maxPlacementGeneration = 10_000

    static func placementGeneration(in defaults: UserDefaults) -> Int {
        min(max(defaults.integer(forKey: DefaultsKey.statusItemPlacementGeneration), 0),
            maxPlacementGeneration)
    }

    static func mainAutosaveName(in defaults: UserDefaults) -> String {
        let generation = placementGeneration(in: defaults)
        guard generation > 0 else { return mainAutosaveName }
        return "\(mainAutosaveName).\(generation)"
    }

    /// The visibility macOS remembers for one item identity, in both the
    /// spellings it has used. Left behind, either keeps the item marked as
    /// hidden, which is the state the recovery exists to undo.
    private static func clearRememberedVisibility(of name: String, in defaults: UserDefaults) {
        defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
    }

    /// Undoes a remembered hidden state while leaving the arranged position
    /// alone. An item that starts over with no saved position is born at the
    /// left end of the status area, against the notch, which is the first
    /// zone macOS drops from a crowded bar (issue #167) — so the spot the
    /// person already arranged is worth far more than a fresh identity, and
    /// is only given up when keeping it demonstrably fails.
    static func clearRememberedVisibility(in defaults: UserDefaults) {
        clearRememberedVisibility(of: mainAutosaveName(in: defaults), in: defaults)
    }

    static func bumpPlacementGeneration(in defaults: UserDefaults) {
        let previousName = mainAutosaveName(in: defaults)
        defaults.removeObject(forKey: "NSStatusItem Preferred Position \(previousName)")
        clearRememberedVisibility(of: previousName, in: defaults)
        let nextGen = (placementGeneration(in: defaults) % maxPlacementGeneration) + 1
        defaults.set(nextGen, forKey: DefaultsKey.statusItemPlacementGeneration)
        let nextName = mainAutosaveName(in: defaults)
        defaults.removeObject(forKey: "NSStatusItem Preferred Position \(nextName)")
        clearRememberedVisibility(of: nextName, in: defaults)
    }
}
