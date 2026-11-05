// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum FixturePreferences {
    final class Store {
        var values: [String: Int] = [:]
        func integer(forKey key: String) -> Int { values[key] ?? 0 }
    }
    static let defaults = Store()
}

@main struct TMobileGatewayAppearanceHarness {
    private static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    static func main() {
        typealias Components = TMobileGatewayMenuBarComponents
        check(Components.all.rawValue == 7 && Components.current == .all,
              "A missing preference preserves the existing all-three appearance")
        for invalid in [Int.min, -1, 0, 8, 15, Int.max] {
            FixturePreferences.defaults.values[Components.defaultsKey] = invalid
            check(Components.current == .all, "Invalid stored components recover to all three")
        }
        let choices: [Components] = [.technology, .bars, .bands]
        for raw in 1...7 {
            FixturePreferences.defaults.values[Components.defaultsKey] = raw
            let components = Components.current
            check(components.rawValue == raw && !components.summary(TMobileGatewayStrings.localized(.enUS)).isEmpty,
                  "Every nonempty combination has a stable preference and summary")
            for choice in choices {
                let removed = components.setting(choice, enabled: false)
                check(!removed.isEmpty && (components == choice ? removed == components : !removed.contains(choice)),
                      "Clearing the last checkbox is blocked; other choices toggle independently")
                check(components.setting(choice, enabled: true).contains(choice), "Any missing piece can be re-enabled")
            }
        }
        check(Components.bars.summary(TMobileGatewayStrings.localized(.enUS)) == "Signal bars only" && Components.bands.summary(TMobileGatewayStrings.localized(.enUS)) == "Bands only"
              && Components.technology.summary(TMobileGatewayStrings.localized(.enUS)) == "Technology only", "Single-piece options explain their visual result")

        let uc = connection(bands: ["n41"], bars: 2)
        let fiveG = connection(bands: ["n71"], bars: 5)
        let lte = connection(bands: [], bars: 4, fiveG: false)
        let unavailable = TMobileGatewayMenuBarSupport.connection(snapshot: nil, strings: TMobileGatewayStrings.localized(.enUS))
        check(uc.badge == "5G UC" && fiveG.badge == "5G" && lte.badge == "LTE",
              "Technology still follows the actual selected radio and existing UC band inference")
        for display in [uc, fiveG, lte, unavailable] {
            for style in [MenuBarBlockStyle.readable, .dense] {
                let all = TMobileGatewayIndicatorDrawing.layout(display, style: style, components: .all)
                let band = display.bands.isEmpty ? "—" : display.bands
                let bandWidth = max(18, ceil((band as NSString).size(withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)]).width))
                check(all.technologyX == 0 && all.barsX == all.badgeWidth + 4
                      && all.bandsX == all.badgeWidth + 26
                      && all.size.width == all.badgeWidth + 18 + bandWidth + 12,
                      "Default geometry remains exactly the previous technology, bars and bands geometry")
                for raw in 1...7 {
                    let components = Components(rawValue: raw)
                    let layout = TMobileGatewayIndicatorDrawing.layout(display, style: style, components: components)
                    check((layout.technologyX != nil) == components.contains(.technology)
                          && (layout.barsX != nil) == components.contains(.bars)
                          && (layout.bandsX != nil) == components.contains(.bands),
                          "Only selected pieces receive drawing coordinates")
                    check(layout.size.height == (style == .readable ? 23 : 21)
                          && layout.size.width > 4 && (raw == 7 || layout.size.width < all.size.width),
                          "Hidden pieces leave no reserved width in either menu bar style")
                    let image = TMobileGatewayIndicatorDrawing.image(display, style: style, components: components)
                    check(image.size == layout.size && pixels(image).contains { $0 != 0 },
                          "Each combination renders nonempty native offscreen artwork")
                }
            }
        }

        let bars = TMobileGatewayIndicatorDrawing.image(uc, style: .dense, components: .bars)
        let changedText = TMobileGatewayMenuBarSupport.ConnectionDisplay(
            badge: "LTE", bands: "b2+b66+b12", bars: uc.bars, accessibilityValue: "synthetic")
        check(bars === TMobileGatewayIndicatorDrawing.image(changedText, style: .dense, components: .bars),
              "Bars-only drawing and its cache ignore hidden technology and bands")
        check(bars.size.width == 22, "Bars only occupies the five bars plus existing trailing padding")
        let zero = connection(bands: ["n41"], bars: 0)
        let full = connection(bands: ["n41"], bars: 5)
        check(pixels(TMobileGatewayIndicatorDrawing.image(zero, style: .dense, components: .bars))
              != pixels(TMobileGatewayIndicatorDrawing.image(full, style: .dense, components: .bars)),
              "Bars-only artwork distinguishes actual zero and full signal")
        let bandOnly = TMobileGatewayIndicatorDrawing.image(uc, style: .dense, components: .bands)
        let changedSignal = TMobileGatewayMenuBarSupport.ConnectionDisplay(
            badge: "LTE", bands: uc.bands, bars: 5, accessibilityValue: "synthetic")
        check(bandOnly === TMobileGatewayIndicatorDrawing.image(changedSignal, style: .dense, components: .bands),
              "Bands-only drawing and its cache ignore hidden technology and signal")
        let technologyOnly = TMobileGatewayIndicatorDrawing.image(uc, style: .dense, components: .technology)
        check(technologyOnly !== bandOnly && technologyOnly !== bars,
              "Changing selected components cannot reuse an incompatible cached image")
        for raw in 1...7 {
            FixturePreferences.defaults.values[Components.defaultsKey] = raw
            let current = connection(bands: ["n41"], bars: 2)
            check(current == uc && current.accessibilityValue.contains("2 of 5 signal bars")
                  && current.accessibilityValue.contains("n41") && current.accessibilityValue.contains("UC inferred"),
                  "Every visual choice retains the complete truthful spoken connection description")
        }
        check(unavailable.badge == "—" && unavailable.bars == nil && unavailable.bands.isEmpty,
              "Unavailable readings never acquire an invented technology, band or zero signal")
        print("PASS: \(checks) T-Mobile appearance checks; in-memory preferences and offscreen drawing only")
    }

    static func connection(bands: [String], bars: Int, fiveG: Bool = true) -> TMobileGatewayMenuBarSupport.ConnectionDisplay {
        let radio = TMobileRadioSignal(bars: bars, bands: bands, rsrp: -95, rsrq: nil, rssi: nil, sinr: nil)
        let snapshot = TMobileGatewaySnapshot(model: nil, firmware: nil, uptime: nil,
            registration: "registered", roaming: false, lte: fiveG ? nil : radio, fiveG: fiveG ? radio : nil)
        return TMobileGatewayMenuBarSupport.connection(snapshot: snapshot, strings: TMobileGatewayStrings.localized(.enUS))
    }

    /// Draw into a private bitmap without creating NSApplication or a window.
    static func pixels(_ image: NSImage) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(image.size.width)),
            pixelsHigh: Int(ceil(image.size.height)), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let count = bitmap.bytesPerRow * bitmap.pixelsHigh
        bitmap.bitmapData!.initialize(repeating: 0, count: count)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bitmap.bitmapData!, count: count)
    }
}
