// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KeepAwakeAutomationCondition: String, CaseIterable, Hashable {
    case externalDisplay
    case power
    case runningApps
}

enum KeepAwakeAutomationAction: Equatable {
    case none
    case activate
    case deactivate
}

enum KeepAwakeAutomationSupport {
    private static let screenLockedKey = "CGSSessionScreenIsLocked"

    static func hasExternalDisplay(builtInFlags: [Bool]) -> Bool {
        builtInFlags.contains(false)
    }

    static func isScreenLocked(sessionDictionary: [String: Any]?) -> Bool {
        guard let value = sessionDictionary?[screenLockedKey] else { return false }
        if let locked = value as? Bool { return locked }
        return (value as? NSNumber)?.boolValue ?? false
    }

    static func selectedAppsAreRunning(selectedBundleIDs: [String],
                                       runningBundleIDs: [String]) -> Bool {
        guard !selectedBundleIDs.isEmpty else { return false }
        let selected = Set(selectedBundleIDs)
        return runningBundleIDs.contains(where: selected.contains)
    }

    static func matchingConditions(externalDisplayEnabled: Bool,
                                   externalDisplayConnected: Bool,
                                   powerEnabled: Bool,
                                   connectedToPower: Bool,
                                   runningAppsEnabled: Bool,
                                   selectedAppsRunning: Bool) -> Set<KeepAwakeAutomationCondition> {
        var matches = Set<KeepAwakeAutomationCondition>()
        if externalDisplayEnabled, externalDisplayConnected {
            matches.insert(.externalDisplay)
        }
        if powerEnabled, connectedToPower {
            matches.insert(.power)
        }
        if runningAppsEnabled, selectedAppsRunning {
            matches.insert(.runningApps)
        }
        return matches
    }

    static func action(featureAvailable: Bool,
                       matchingConditions: Set<KeepAwakeAutomationCondition>,
                       sessionActive: Bool,
                       automaticSessionActive: Bool) -> KeepAwakeAutomationAction {
        guard featureAvailable, !matchingConditions.isEmpty else {
            return automaticSessionActive ? .deactivate : .none
        }
        return sessionActive ? .none : .activate
    }

    /// Conditions that can gate closed-lid mode independently of Keep Awake automation.
    enum ClamshellGateCondition: String, CaseIterable, Hashable {
        case externalDisplay
        case power
        case network
    }

    /// How selected closed-lid gate conditions combine.
    enum ClamshellGateMode: String, CaseIterable {
        case any
        case all
    }

    static func selectedClamshellGateConditions(externalDisplay: Bool,
                                                power: Bool,
                                                network: Bool) -> Set<ClamshellGateCondition> {
        var selected = Set<ClamshellGateCondition>()
        if externalDisplay { selected.insert(.externalDisplay) }
        if power { selected.insert(.power) }
        if network { selected.insert(.network) }
        return selected
    }

    /// Empty selection means no gate (always passes). Otherwise Any needs one
    /// currently-true selected condition; All needs every selected condition true.
    static func clamshellGatePasses(selected: Set<ClamshellGateCondition>,
                                    mode: ClamshellGateMode,
                                    externalDisplayConnected: Bool,
                                    connectedToPower: Bool,
                                    networkAvailable: Bool) -> Bool {
        guard !selected.isEmpty else { return true }
        var satisfied = Set<ClamshellGateCondition>()
        if selected.contains(.externalDisplay), externalDisplayConnected {
            satisfied.insert(.externalDisplay)
        }
        if selected.contains(.power), connectedToPower {
            satisfied.insert(.power)
        }
        if selected.contains(.network), networkAvailable {
            satisfied.insert(.network)
        }
        switch mode {
        case .any: return !satisfied.isEmpty
        case .all: return selected.isSubset(of: satisfied)
        }
    }

    /// Whether closed-lid mode should be active right now. Keep Awake itself is
    /// left alone either way; `gatePasses` is the result of `clamshellGatePasses`.
    static func shouldApplyClamshell(preferred: Bool,
                                     keepAwakeActive: Bool,
                                     sessionPaused: Bool,
                                     gatePasses: Bool) -> Bool {
        preferred && keepAwakeActive && !sessionPaused && gatePasses
    }
}
