// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A tab leaves the panel and the Dynamic Island once none of its gate
/// features is installed, so a row whose feature the gate leaves out is
/// unreachable when that feature is the only one installed. The sections and
/// rows are the production enums, generated from source.
enum MenuPanelSectionGateContract {
    static func run(_ suite: TestSuite) {
        suite.expect(ControlPanelItem.allCases.contains { $0.feature == .smoothScroll },
                     "installed smooth scrolling has a menu bar control")
        suite.expect(PanelSectionID.controls.featureGate.contains(.smoothScroll),
                     "smooth scrolling alone keeps the Controls tab available")
        suite.expect(ControlCategory.category(for: .smoothScroll) == .inputDevices,
                     "smooth scrolling appears in Mouse & keyboard")
        let savedOrder = ControlPanelItem.allCases.filter { $0 != .smoothScroll }.map(\.rawValue)
        let restoredOrder = Defaults.sanitizedPanelItemOrder(savedOrder.joined(separator: ","),
                                                           defaultOrder: ControlPanelItem.allCases.map(\.rawValue))
        suite.expect(restoredOrder == savedOrder + [ControlPanelItem.smoothScroll.rawValue],
                     "existing custom control orders gain smooth scrolling without losing their order")
        func expectGate(_ section: PanelSectionID, keeps features: [AppFeature], _ rows: String) {
            let missing = features.filter { !section.featureGate.contains($0) }.map(\.rawValue)
            suite.expect(missing.isEmpty,
                         "every \(rows) row keeps the \(section.rawValue) tab available, missing \(missing)")
        }
        expectGate(.controls, keeps: ControlPanelItem.allCases.map(\.feature), "control")
        expectGate(.utilities, keeps: UtilityPanelItem.allCases.map(\.feature), "utility")
        expectGate(.toggles, keeps: QuickToggleAction.allCases.map(\.feature), "quick toggle")
        expectGate(.system, keeps: [.connectedDevices], "connected devices")
    }
}
