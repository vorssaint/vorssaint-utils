// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Whether macOS lets this app's status items into the menu bar at all.
///
/// macOS 26 added a per-app switch under System Settings > Menu Bar
/// ("Allow in the Menu Bar"). Control Center remembers it in its group
/// container, in a `trackedApplications` list whose per-app entry carries
/// `isAllowed`. With it off, AppKit still creates the status item and its
/// window, but Control Center never assigns the window a slot: it stays at
/// the display's bottom-left origin, no preferred position is ever saved, and
/// nothing the app does (recreating the item, resetting its autosave identity)
/// changes that. Recovery has to recognise the state and point at the switch
/// instead of blaming a full bar (#1394).
enum MenuBarAllowanceSupport {
    enum Allowance: Equatable {
        case allowed
        case disallowed
        /// No entry for the app, no flag on it, or a store this build cannot
        /// read. Never treated as a verdict either way.
        case unknown
    }

    static let groupContainerPlistPath = "Library/Group Containers/group.com.apple.controlcenter"
        + "/Library/Preferences/group.com.apple.controlcenter.plist"

    /// The verdict for one bundle id inside a decoded `trackedApplications`
    /// list. Entries come in two shapes: a bare `{bundle: {_0: id}}` marker
    /// and the record `{location: {bundle: {_0: id}}, isAllowed: Bool, ...}`;
    /// only the record carries the flag.
    static func allowance(forBundleID bundleID: String, trackedApplications: [Any]) -> Allowance {
        for case let entry as [String: Any] in trackedApplications {
            guard let location = entry["location"] as? [String: Any],
                  let bundle = location["bundle"] as? [String: Any],
                  bundle["_0"] as? String == bundleID else { continue }
            guard let allowed = entry["isAllowed"] as? Bool else { return .unknown }
            return allowed ? .allowed : .disallowed
        }
        return .unknown
    }

    /// The verdict read out of Control Center's group container plist: an
    /// outer property list whose `trackedApplications` value is a second,
    /// binary property list stored as data.
    static func allowance(forBundleID bundleID: String, groupContainerPlist data: Data) -> Allowance {
        guard let outer = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let innerData = outer["trackedApplications"] as? Data,
              let inner = try? PropertyListSerialization.propertyList(from: innerData, format: nil) as? [Any]
        else { return .unknown }
        return allowance(forBundleID: bundleID, trackedApplications: inner)
    }

    /// The live verdict for this app. Read straight from the file: the domain
    /// belongs to Control Center's app group, which a plain `UserDefaults`
    /// suite lookup from here would not resolve to.
    static func currentAllowance(bundleID: String? = Bundle.main.bundleIdentifier,
                                 home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Allowance {
        guard let bundleID,
              let data = try? Data(contentsOf: home.appendingPathComponent(groupContainerPlistPath))
        else { return .unknown }
        return allowance(forBundleID: bundleID, groupContainerPlist: data)
    }
}
