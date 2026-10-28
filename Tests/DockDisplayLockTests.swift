// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockDisplayLockTests {
    static func run(_ suite: TestSuite) {
        targets(suite)
        zones(suite)
        dockLocation(suite)
        catalog(suite)
    }

    private typealias Support = DockDisplayLockSupport

    private static func display(_ id: CGDirectDisplayID, _ frame: CGRect, main: Bool = false,
                                builtIn: Bool = false) -> DockDisplayLockDisplay {
        DockDisplayLockDisplay(id: id, uuid: "UUID-\(id)", name: "Display \(id)", frame: frame,
                               isMain: main, isBuiltIn: builtIn)
    }

    // A 2560×1440 main display with a 1920×1080 one to its right, 78 points
    // lower, as a real desk has them.
    private static let main = display(3, CGRect(x: 0, y: 0, width: 2560, height: 1440), main: true)
    private static let side = display(1, CGRect(x: 2560, y: 78, width: 1920, height: 1080))
    // A laptop under the middle of the main display.
    private static let below = display(5, CGRect(x: 640, y: 1440, width: 1512, height: 982), builtIn: true)

    private static func blocks(_ point: CGPoint, _ zones: Support.Zones) -> Bool {
        var inCorner = false
        return Support.blocks(point, zones: zones, inCorner: &inCorner)
    }

    private static func targets(_ suite: TestSuite) {
        suite.expect(DockDisplayLockTarget(storage: nil) == .main
                && DockDisplayLockTarget(storage: "") == .main
                && DockDisplayLockTarget(storage: "main") == .main
                && DockDisplayLockTarget(storage: "builtIn") == .builtIn
                && DockDisplayLockTarget(storage: "1A39FCE5") == .display(uuid: "1A39FCE5"),
                     "a stored choice reads back as the main display, the built-in one or a display by its UUID")
        suite.expect([DockDisplayLockTarget.main, .builtIn, .display(uuid: "1A39FCE5")].allSatisfy {
            DockDisplayLockTarget(storage: $0.storageValue) == $0
        }, "every choice survives being stored")

        suite.expect(Support.anchor(for: .main, in: [side, main])?.id == main.id
                && Support.anchor(for: .display(uuid: side.uuid), in: [main, side])?.id == side.id
                && Support.anchor(for: .builtIn, in: [main, below])?.id == below.id,
                     "the Dock is held to the display the choice names")
        suite.expect(Support.anchor(for: .display(uuid: "UUID-9"), in: [main, side])?.id == main.id
                && Support.anchor(for: .builtIn, in: [main, side])?.id == main.id,
                     "a chosen display that is not connected falls back to the main display")
    }

    private static func zones(_ suite: TestSuite) {
        let none: Set<DockDisplayLockCorner> = []
        let onMain = Support.zones(displays: [main, side], anchorID: main.id, orientation: .bottom, hotCorners: none)
        suite.expect(blocks(CGPoint(x: 3000, y: 1157), onMain) && blocks(CGPoint(x: 4479.5, y: 1157.9), onMain)
                && blocks(CGPoint(x: 3000, y: 1158), onMain),
                     "a press on the other display's bottom edge is held back, up to the edge line itself")
        suite.expect(!blocks(CGPoint(x: 3000, y: 1150), onMain) && !blocks(CGPoint(x: 1280, y: 1439), onMain)
                && !blocks(CGPoint(x: 3000, y: 500), onMain),
                     "a few points above that edge, and anywhere on the Dock's own display, the pointer passes")

        let onSide = Support.zones(displays: [main, side], anchorID: side.id, orientation: .bottom, hotCorners: none)
        suite.expect(blocks(CGPoint(x: 1280, y: 1439), onSide) && !blocks(CGPoint(x: 3000, y: 1157), onSide),
                     "choosing the other display moves the held edge to the main display")

        let overLaptop = Support.zones(displays: [main, below], anchorID: below.id, orientation: .bottom,
                                       hotCorners: none)
        suite.expect(blocks(CGPoint(x: 100, y: 1439), overLaptop) && blocks(CGPoint(x: 2400, y: 1439), overLaptop)
                && !blocks(CGPoint(x: 1000, y: 1439), overLaptop),
                     "where a display sits below, the pointer crosses over instead of being held back")
        suite.expect(Support.hardSegments(of: main, orientation: .bottom, others: [below]) == [0...640, 2152...2560],
                     "the hard parts of an edge are what no display touches")

        let leftDock = Support.zones(displays: [main, side], anchorID: main.id, orientation: .left, hotCorners: none)
        suite.expect(leftDock.isEmpty,
                     "a display whose left edge is fully shared has nowhere for a left Dock to be called")
        let leftOnSide = Support.zones(displays: [main, side], anchorID: side.id, orientation: .left,
                                       hotCorners: none)
        suite.expect(blocks(CGPoint(x: 0.5, y: 700), leftOnSide) && !blocks(CGPoint(x: 5, y: 700), leftOnSide),
                     "a left Dock is held off the main display's left edge")
        let rightDock = Support.zones(displays: [main, side], anchorID: main.id, orientation: .right,
                                      hotCorners: none)
        suite.expect(blocks(CGPoint(x: 4479, y: 600), rightDock) && !blocks(CGPoint(x: 2559, y: 600), rightDock),
                     "a right Dock is held off the right display's outer edge, not off the edge both share")

        suite.expect(Support.zones(displays: [main], anchorID: main.id, orientation: .bottom, hotCorners: none).isEmpty
                && Support.zones(displays: [main, side], anchorID: nil, orientation: .bottom, hotCorners: none).isEmpty
                && Support.zones(displays: [main, side], anchorID: 42, orientation: .bottom, hotCorners: none).isEmpty,
                     "one display, or no display to hold the Dock to, holds nothing back")

        let corners = Support.zones(displays: [main, side], anchorID: main.id, orientation: .bottom,
                                    hotCorners: [.bottomRight, .bottomLeft])
        var inCorner = false
        let corner = CGPoint(x: 4479.5, y: 1157.5)
        let first = Support.blocks(corner, zones: corners, inCorner: &inCorner)
        let second = Support.blocks(corner, zones: corners, inCorner: &inCorner)
        let along = Support.blocks(CGPoint(x: 4000, y: 1157.5), zones: corners, inCorner: &inCorner)
        let again = Support.blocks(corner, zones: corners, inCorner: &inCorner)
        suite.expect(!first && second && along && !again,
                     "the first move into a Hot Corner fires it; pressing on in the corner is held back")
        suite.expect(corners.corners.count == 1 && blocks(CGPoint(x: 2560.5, y: 1157.5), corners),
                     "a corner the pointer slides past into the next display is no Hot Corner")
        suite.expect(DockDisplayLockCorner.actions(in: ["wvous-br-corner": NSNumber(value: 1),
                                                        "wvous-bl-corner": NSNumber(value: 2),
                                                        "wvous-tl-corner": NSNumber(value: 0)]) == [.bottomLeft],
                     "only a corner with an action counts as a Hot Corner")

        suite.expect(Support.subtract([2...4], from: 0...10) == [0...2, 4...10]
                && Support.subtract([-5...20], from: 0...10).isEmpty
                && Support.subtract([20...30], from: 0...10) == [0...10],
                     "edge ranges subtract like intervals")
    }

    private static func dockLocation(_ suite: TestSuite) {
        let displays = [main, side]
        suite.expect(Support.display(holdingDockFrame: CGRect(x: 679, y: 1370, width: 1202, height: 60),
                                     orientation: .bottom, displays: displays) == main.id
                && Support.display(holdingDockFrame: CGRect(x: 3000, y: 1098, width: 600, height: 60),
                                   orientation: .bottom, displays: displays) == side.id,
                     "the Dock's icon list tells which display holds it")
        suite.expect(Support.display(holdingDockFrame: CGRect(x: 679, y: 1442, width: 1202, height: 60),
                                     orientation: .bottom, displays: displays) == main.id,
                     "a list frame reported off its display on the short axis still finds it")
        suite.expect(Support.display(holdingDockFrame: .zero, orientation: .bottom, displays: displays) == nil,
                     "no frame, no answer")

        let path = Support.summonPath(to: side, orientation: .bottom)
        suite.expect(path.last?.point == CGPoint(x: side.frame.midX, y: side.frame.maxY - 1)
                && path.allSatisfy { side.frame.contains($0.point) && $0.delta.dy > 0 && $0.delta.dx == 0 },
                     "calling the Dock presses down on the chosen display's bottom edge, inside that display")
        let leftPath = Support.summonPath(to: main, orientation: .left)
        suite.expect(leftPath.last?.point == CGPoint(x: 0, y: main.frame.midY)
                && leftPath.allSatisfy { $0.delta.dx < 0 && $0.delta.dy == 0 },
                     "a left Dock is called by pressing left")
    }

    private static func catalog(_ suite: TestSuite) {
        let feature = AppFeature.dockDisplayLock
        suite.expect(feature.group == .windowsDock
                && feature.enabledKeys == [DefaultsKey.dockDisplayLockEnabled]
                && feature.permissions == [.accessibility]
                && !feature.installedByDefault
                && feature.energyProfile == .mouse,
                     "keeping the Dock on one display is an opt-in pointer feature behind Accessibility")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.dockDisplayLockEnabled] as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.dockDisplayLockTarget] as? String == "main"
                && Defaults.registeredDefaults[DefaultsKey.dockDisplayLockReturns] as? Bool == false,
                     "it ships off, held to the main display, and never moves the pointer on its own")
        let exported = SettingsBackupSupport.exportKeys()
        suite.expect([DefaultsKey.dockDisplayLockEnabled, DefaultsKey.dockDisplayLockTarget,
                      DefaultsKey.dockDisplayLockReturns, feature.availabilityKey].allSatisfy(exported.contains),
                     "its choices travel with a settings backup; a display missing there falls back to the main one")
        suite.expect(feature.settingsDestination == FeatureSettingsDestination(.dock, sectionAnchor: .dockDisplayLock)
                && feature.settingsDestination.hasValidSectionAnchor
                && FeatureVisibilitySupport.features(for: .dock).contains(feature),
                     "its settings are a card on the Dock page")
        suite.expect(!FeaturePreset.allCases.contains { $0.features.contains(feature) },
                     "no preset installs it")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.dockDisplayLock(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.count == 14 && values.allSatisfy { !$0.isEmpty }
                    && strings.dockLocationFormat.components(separatedBy: "%@").count == 2,
                         "\(language.rawValue) has every Dock display string, the location with one name in it")
        }
    }
}
