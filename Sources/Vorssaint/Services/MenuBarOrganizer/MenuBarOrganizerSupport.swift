// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum MenuBarOrganizerSection: String, CaseIterable, Codable, Identifiable {
    case visible
    case hidden
    case alwaysHidden

    var id: String { rawValue }
}

enum MenuBarItemIdentityState: String, Codable {
    case stable
    case provisional
}

struct MenuBarItemIdentity: Hashable, Codable {
    let bundleIdentifier: String
    let title: String
    let occurrence: Int

    var storageValue: String {
        [bundleIdentifier, title, String(occurrence)]
            .map { $0.replacingOccurrences(of: "|", with: "||") }
            .joined(separator: "|")
    }
}

struct MenuBarItemSourceIdentity: Equatable {
    let pid: pid_t
    let bundleIdentifier: String
    let name: String
    let axIdentifier: String?
    let axTitle: String?

    var stableTitle: String? {
        let identifier = axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !identifier.isEmpty { return identifier }
        let title = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }
}

struct ResolvedMenuBarItemIdentity {
    let id: MenuBarItemIdentity
    let state: MenuBarItemIdentityState
    let source: MenuBarItemSourceIdentity?
}

struct ManagedMenuBarItem: Identifiable {
    let id: MenuBarItemIdentity
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerBundleIdentifier: String
    let sourcePID: pid_t?
    let ownerName: String
    let sourceName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let section: MenuBarOrganizerSection
    let identityState: MenuBarItemIdentityState
    let isMovable: Bool
    let isProtected: Bool

    var displayName: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = sourceName.isEmpty ? ownerName : sourceName
        if !cleanTitle.isEmpty, cleanTitle.caseInsensitiveCompare(appName) != .orderedSame {
            return appName.isEmpty ? cleanTitle : "\(appName) - \(cleanTitle)"
        }
        return appName.isEmpty ? (cleanTitle.isEmpty ? "Menu bar item" : cleanTitle) : appName
    }
}

struct MenuBarOrganizerWindowRecord: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let ownerBundleIdentifier: String
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let isOnScreen: Bool
}

struct MenuBarOrganizerCapabilities: Equatable {
    let canEnumerate: Bool
    let canMove: Bool
    let hasPrivateWindowList: Bool
    let unresolvedItemCount: Int

    var automaticEditorAvailable: Bool {
        canEnumerate && canMove
    }
}

struct MenuBarItemSnapshot {
    let items: [ManagedMenuBarItem]
    let capabilities: MenuBarOrganizerCapabilities
    let enumerationSucceeded: Bool
}

/// An in-session destination, never an identity that authorizes moving/clicking
/// the anchor itself. Unknown hosted icons can still mark an exact insertion
/// slot without guessing their originating application.
struct MenuBarItemAnchor {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerBundleIdentifier: String

    init(_ item: ManagedMenuBarItem) {
        windowID = item.windowID
        ownerPID = item.ownerPID
        ownerBundleIdentifier = item.ownerBundleIdentifier
    }

    func resolve(in items: [ManagedMenuBarItem]) -> ManagedMenuBarItem? {
        let matches = items.filter {
            $0.windowID == windowID && $0.ownerPID == ownerPID
                && $0.ownerBundleIdentifier == ownerBundleIdentifier
                && MenuBarOrganizerPolicy.validFrame($0.frame)
        }
        return matches.count == 1 ? matches.first : nil
    }
}

enum MenuBarOrganizerSupport {
    /// Hosted items share a process. Identify the individual status window as
    /// well as its host; position and PID alone are insufficient on macOS 26.
    static func routeEvent(_ event: CGEvent, to windowID: CGWindowID, pid: pid_t, command: Bool) {
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        // WindowServer's window-ID field, used only by the version-gated backend.
        if let field = CGEventField(rawValue: 0x33) { event.setIntegerValueField(field, value: Int64(windowID)) }
    }

    static let controlCenterBundleIdentifier = "com.apple.controlcenter"
    static let systemUIServerBundleIdentifier = "com.apple.systemuiserver"

    // An AX-proven app with exactly one status item has an unambiguous slot even
    // when AppKit supplies neither a title nor an identifier. Multiple untitled
    // slots must remain provisional; window-number ordering cannot identify them.
    static let singleItemIdentifier = "vorssaint.single-status-item"
    static func sourceIdentifier(_ identifier: String?, siblingCount: Int) -> String? {
        if let identifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return identifier
        }
        return siblingCount == 1 ? singleItemIdentifier : nil
    }


    static func section(itemMidX: CGFloat,
                        hiddenDividerMidX: CGFloat?,
                        alwaysHiddenDividerMidX: CGFloat?) -> MenuBarOrganizerSection {
        guard let hiddenX = hiddenDividerMidX else { return .visible }
        if let alwaysX = alwaysHiddenDividerMidX, itemMidX < alwaysX {
            return .alwaysHidden
        }
        if itemMidX < hiddenX {
            return .hidden
        }
        return .visible
    }

    static func identities(
        for records: [MenuBarOrganizerWindowRecord],
        sources: [CGWindowID: MenuBarItemSourceIdentity]
    ) -> [CGWindowID: ResolvedMenuBarItemIdentity] {
        struct Seed {
            let record: MenuBarOrganizerWindowRecord
            let source: MenuBarItemSourceIdentity?
            let namespace: String
            let title: String
            let state: MenuBarItemIdentityState
        }

        let seeds = records.map { record -> Seed in
            let source = sources[record.windowID]
            let isHosted = record.ownerBundleIdentifier == controlCenterBundleIdentifier
            // A generic Control Center AX child proves only which process hosts
            // the window. It does not prove which third-party app created the
            // status item, so never promote that host fallback to a stable
            // persisted identity.
            let sourceIsOnlyHost = isHosted
                && source?.bundleIdentifier == controlCenterBundleIdentifier
                && isGenericControlCenterHostedTitle(record.title)
            let resolvedSource = sourceIsOnlyHost ? nil : source
            let state: MenuBarItemIdentityState = isHosted
                && (resolvedSource == nil || resolvedSource?.stableTitle == nil)
                ? .provisional
                : .stable
            let namespace = resolvedSource?.bundleIdentifier.nonEmpty
                ?? record.ownerBundleIdentifier.nonEmpty
                ?? "pid:\(record.ownerPID)"
            let title = resolvedSource?.stableTitle?.nonEmpty
                ?? record.title.nonEmpty
                ?? record.ownerName.nonEmpty
                ?? "window:\(record.windowID)"
            return Seed(record: record,
                        source: resolvedSource,
                        namespace: namespace,
                        title: title,
                        state: state)
        }

        let counts = Dictionary(grouping: seeds, by: { "\($0.namespace)\u{0}\($0.title)" }).mapValues(\.count)
        var occurrences: [String: Int] = [:]
        var result: [CGWindowID: ResolvedMenuBarItemIdentity] = [:]
        for seed in seeds.sorted(by: {
            if $0.namespace != $1.namespace { return $0.namespace < $1.namespace }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.record.windowID < $1.record.windowID
        }) {
            let key = "\(seed.namespace)\u{0}\(seed.title)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            result[seed.record.windowID] = ResolvedMenuBarItemIdentity(
                id: MenuBarItemIdentity(bundleIdentifier: seed.namespace,
                                        title: seed.title,
                                        occurrence: occurrence),
                state: counts[key] == 1 ? seed.state : .provisional,
                source: seed.source)
        }
        return result
    }

    static func isLikelyMenuBarWindow(_ record: MenuBarOrganizerWindowRecord,
                                      statusLevel: Int,
                                      screenTopEdges: [CGFloat]) -> Bool {
        guard record.layer == statusLevel,
              record.alpha > 0,
              record.frame.width > 0,
              record.frame.height > 0,
              record.frame.height <= 64
        else { return false }
        return screenTopEdges.contains {
            abs(record.frame.maxY - $0) <= 8 || abs(record.frame.minY - $0) <= 8
        } || record.frame.minY <= 8
    }

    static func isMenuBarItemCandidate(_ record: MenuBarOrganizerWindowRecord,
                                       mainMenuLevel: Int) -> Bool {
        record.layer != mainMenuLevel
            && !(record.ownerName == "Window Server"
                && record.title.caseInsensitiveCompare("Menubar") == .orderedSame)
    }

    static func frameMatchScore(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat? {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return nil }
        let centerDistance = hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
        let sizeDistance = abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
        let intersection = lhs.intersection(rhs)
        let overlap = intersection.isNull
            ? 0
            : (intersection.width * intersection.height) / max(lhs.width * lhs.height, 1)
        guard centerDistance <= 5 || overlap >= 0.72 else { return nil }
        return centerDistance + sizeDistance * 0.25 - overlap
    }

    static func isGenericControlCenterHostedTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
            || normalized.range(of: #"^Item-\d+$"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Synthetic events must go to the process that owns the window under the
    /// pointer. On macOS 26 that is commonly Control Center, not the app that
    /// logically created the status item.
    static func eventTargetPID(ownerPID: pid_t,
                               ownerBundleIdentifier: String,
                               sourcePID: pid_t?) -> pid_t {
        if ownerBundleIdentifier == controlCenterBundleIdentifier {
            return ownerPID
        }
        return sourcePID ?? ownerPID
    }

    static func isSystemImmovable(bundleIdentifier: String, title _: String) -> Bool {
        // A resolved third-party source has its own bundle identifier. Keep
        // system-host controls protected regardless of locale or display title.
        bundleIdentifier == controlCenterBundleIdentifier || bundleIdentifier == systemUIServerBundleIdentifier
    }



    static func orderedItems(_ items: [ManagedMenuBarItem],
                             in section: MenuBarOrganizerSection) -> [ManagedMenuBarItem] {
        items.filter { $0.section == section }.sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.id.storageValue < $1.id.storageValue
            }
            return $0.frame.minX < $1.frame.minX
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
