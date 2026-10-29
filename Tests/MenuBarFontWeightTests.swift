// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Exercise the production drawing methods with isolated preferences, including
/// cached images whose readings have not changed when the font weight changes.
enum MenuBarFontWeightTests {
    typealias Renderer = MenuBarBatteryWarningTests.Renderer

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.menu-bar-font-weight"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        MenuBarBatteryWarningTests.ReviewDefaults.current = defaults
        defer {
            defaults.removePersistentDomain(forName: domain)
            MenuBarBatteryWarningTests.ReviewDefaults.current = nil
            Renderer.blockImageCache.removeAllObjects()
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.menuBarFontWeight] as? String == "automatic",
                     "existing installations retain the original menu bar weights")
        suite.expect(MenuBarFontWeight.current(in: defaults) == .automatic,
                     "an absent font weight preserves the original appearance")
        defaults.set("unknown", forKey: DefaultsKey.menuBarFontWeight)
        suite.expect(MenuBarFontWeight.current(in: defaults) == .automatic,
                     "an unrecognized font weight safely uses the original appearance")
        for weight in MenuBarFontWeight.allCases {
            defaults.set(weight.rawValue, forKey: DefaultsKey.menuBarFontWeight)
            suite.expect(MenuBarFontWeight.current(in: defaults) == weight,
                         "every offered font weight survives preference storage")
            let payload = SettingsBackupSupport.payload(appVersion: "test") { defaults.object(forKey: $0) }
            let restored = SettingsBackupSupport.sanitizedSettings(from: payload)
            suite.expect(restored?[DefaultsKey.menuBarFontWeight] as? String == weight.rawValue,
                         "every offered font weight survives settings export and import")
        }
        let explicitWeights: [(MenuBarFontWeight, NSFont.Weight)] = [
            (.regular, .regular), (.medium, .medium), (.semibold, .semibold), (.bold, .bold),
        ]
        for (choice, expected) in explicitWeights {
            for original: NSFont.Weight in [.medium, .semibold] {
                suite.expect(choice.resolve(original) == expected,
                             "an explicit weight overrides both label and value defaults")
                suite.expect(MenuBarFontWeight.automatic.resolve(original) == original,
                             "Default retains each label and value's original weight")
            }
        }
        for style in [MenuBarBatteryWarningTests.MenuBarBlockStyle.dense, .readable] {
            defaults.set("automatic", forKey: DefaultsKey.menuBarFontWeight)
            suite.expect(Renderer.metricLabelFont(style: style).isEqual(
                NSFont.systemFont(ofSize: style == .readable ? 7.2 : 6.6, weight: .medium)),
                         "Default retains the original metric label font")
            suite.expect(Renderer.metricValueFont(style: style).isEqual(
                NSFont.monospacedDigitSystemFont(ofSize: style == .readable ? 13 : 12, weight: .semibold)),
                         "Default retains the original metric value font")
            suite.expect(Renderer.rateFont(style: style).isEqual(
                NSFont.monospacedSystemFont(ofSize: style == .readable ? 9.8 : 9.2, weight: .semibold)),
                         "Default retains the original network and disk rate font")
            let drawings: [(String, () -> NSImage)] = [
                ("numeric", { Renderer.metricBlockImage(label: "CPU", value: "42%", minimumValue: "100%",
                                                       style: style, pressure: nil, warning: .none) }),
                ("usage bar", { Renderer.usageBarBlockImage(label: "CPU", fraction: 0.42,
                                                          style: style, pressure: nil) }),
                ("network", { Renderer.networkBlockImage(down: "350K", up: "65K", style: style) }),
                ("disk activity", { Renderer.diskActivityBlockImage(read: "350K", write: "65K", style: style) }),
                ("battery", { Renderer.batteryBlockImage(percent: 42, isCharging: false,
                                                        externalConnected: false, warning: .none, style: style) }),
            ]
            for (name, draw) in drawings {
                defaults.set("regular", forKey: DefaultsKey.menuBarFontWeight)
                let regular = draw()
                let regularPixels = regular.tiffRepresentation
                defaults.set("bold", forKey: DefaultsKey.menuBarFontWeight)
                let bold = draw()
                suite.expect(regular !== bold, "\(name) does not reuse an image from another font weight")
                suite.expect(regularPixels != nil && bold.tiffRepresentation != nil
                             && regularPixels != bold.tiffRepresentation,
                             "\(name) actually draws different text at another font weight")
                suite.expect(regular.size.height == bold.size.height,
                             "\(name) keeps its menu bar height at another weight")
                defaults.set("regular", forKey: DefaultsKey.menuBarFontWeight)
                suite.expect(draw() === regular, "\(name) can reuse the correct cached image after switching back")
            }
        }
        for stacked in [false, true] {
            let original = Renderer.statusFont(stacked: stacked)
            let regular = Renderer.statusFont(stacked: stacked, fontWeight: .regular)
            suite.expect(!original.isEqual(regular) && original.pointSize == regular.pointSize,
                         "classic text changes weight without changing its size")
        }
    }
}
