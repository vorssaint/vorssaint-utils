// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Experimental macOS 27 inventory backend.
///
/// MenuBarAgent no longer exposes one WindowServer window per status item, so
/// the safe public observation path is each running application's
/// `AXExtrasMenuBar`. This provider is intentionally read-only: visibility is
/// left disabled until Vorssaint has a transparent, auditable implementation.
/// The architecture is informed by Thaw's macOS 27 research in issue #687 and
/// is independently implemented against Vorssaint's existing AX primitives.
final class MenuBarAccessibilityProvider {
    private struct ApplicationRecord: Sendable {
        let pid: pid_t
        let bundleIdentifier: String
        let name: String
        let bundlePath: String?
    }

    private struct RawRecord: Sendable {
        let pid: pid_t
        let bundleIdentifier: String
        let name: String
        let bundlePath: String?
        let identityTitle: String
        let displayTitle: String
        let frame: CGRect
        let identityState: MenuBarItemIdentityState
    }

    private let queue = DispatchQueue(
        label: "com.vorssaint.menu-bar-ax-enumeration",
        qos: .utility)

    func snapshot(hiddenDividerMidX: CGFloat?,
                  alwaysHiddenDividerMidX: CGFloat?) async -> MenuBarItemSnapshot {
        guard AXIsProcessTrusted() else {
            return MenuBarItemSnapshot(
                items: [],
                capabilities: MenuBarOrganizerCapabilities(
                    canEnumerate: false,
                    canMove: false,
                    canHide: false,
                    hasPrivateWindowList: false,
                    unresolvedItemCount: 0),
                enumerationSucceeded: false)
        }

        let applications = await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationRecord? in
                guard !app.isTerminated else { return nil }
                let pid = app.processIdentifier
                let bundleID = app.bundleIdentifier?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
                return ApplicationRecord(
                    pid: pid,
                    bundleIdentifier: bundleID.isEmpty ? "pid:\(pid)" : bundleID,
                    name: app.localizedName ?? bundleID,
                    bundlePath: app.bundleURL?.path)
            }
        }
        let displayBounds = Self.activeDisplayBounds()
        let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.vorssaint.Vorssaint"
        let records = await enumerate(
            applications: applications,
            displayBounds: displayBounds)

        let items = await MainActor.run {
            var occurrences: [String: Int] = [:]
            return records.map { record -> ManagedMenuBarItem in
                let key = "\(record.bundleIdentifier)\u{0}\(record.identityTitle)"
                let occurrence = occurrences[key, default: 0]
                occurrences[key] = occurrence + 1
                let identity = MenuBarItemIdentity(
                    bundleIdentifier: record.bundleIdentifier,
                    title: record.identityTitle,
                    occurrence: occurrence)
                let protected = record.bundleIdentifier == ownBundleIdentifier
                    || MenuBarOrganizerSupport.isSystemImmovable(
                        bundleIdentifier: record.bundleIdentifier,
                        title: record.identityTitle)
                let icon = record.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
                return ManagedMenuBarItem(
                    id: identity,
                    windowID: MenuBarOrganizerSupport.syntheticWindowID(
                        bundleIdentifier: record.bundleIdentifier,
                        title: record.identityTitle,
                        occurrence: occurrence),
                    ownerPID: record.pid,
                    ownerBundleIdentifier: record.bundleIdentifier,
                    sourcePID: record.pid,
                    ownerName: record.name,
                    sourceName: record.name,
                    bundleIdentifier: record.bundleIdentifier,
                    title: record.displayTitle,
                    frame: record.frame,
                    section: MenuBarOrganizerSupport.section(
                        itemMidX: record.frame.midX,
                        hiddenDividerMidX: hiddenDividerMidX,
                        alwaysHiddenDividerMidX: alwaysHiddenDividerMidX),
                    identityState: record.identityState,
                    isMovable: record.identityState == .stable && !protected,
                    isProtected: protected,
                    image: icon,
                    backend: .accessibility)
            }
        }

        return MenuBarItemSnapshot(
            items: items,
            capabilities: MenuBarOrganizerCapabilities(
                canEnumerate: true,
                canMove: true,
                canHide: false,
                hasPrivateWindowList: false,
                unresolvedItemCount: items.count { $0.identityState == .provisional }),
            enumerationSucceeded: true)
    }

    private func enumerate(applications: [ApplicationRecord],
                           displayBounds: [CGRect]) async -> [RawRecord] {
        await withCheckedContinuation { continuation in
            queue.async {
                let scanned = Self.scan(
                    applications: applications,
                    displayBounds: displayBounds)
                continuation.resume(returning: scanned)
            }
        }
    }

    private static func scan(applications: [ApplicationRecord],
                             displayBounds: [CGRect]) -> [RawRecord] {
        var raw: [RawRecord] = []
        for application in applications {
            let app = AXUIElementCreateApplication(application.pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            guard let extras: AXUIElement = attribute("AXExtrasMenuBar", from: app),
                  let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: extras)
            else { continue }

            for (index, child) in children.enumerated() {
                guard let frame = frame(of: child),
                      MenuBarOrganizerSupport.isAXMenuBarItemFrame(
                        frame, displayBounds: displayBounds)
                else { continue }

                let descendants: [AXUIElement] = attribute(kAXChildrenAttribute, from: child) ?? []
                let identifier: String? = firstString(
                    kAXIdentifierAttribute, in: [child] + descendants)
                let accessibilityDescription: String? = firstString(
                    kAXDescriptionAttribute, in: [child] + descendants)
                let title: String? = firstString(kAXTitleAttribute, in: [child])
                let identity = MenuBarOrganizerSupport.axIdentityTitle(
                    identifier: identifier,
                    accessibilityDescription: accessibilityDescription,
                    title: title,
                    fallbackIndex: index)
                if MenuBarOrganizerSupport.isOrganizerControlIdentity(identity.title) {
                    continue
                }
                let displayTitle = [title, accessibilityDescription, identifier]
                    .compactMap { value -> String? in
                        let normalized = value?.trimmingCharacters(
                            in: .whitespacesAndNewlines) ?? ""
                        return normalized.isEmpty ? nil : normalized
                    }
                    .first ?? identity.title
                var ownerPID = application.pid
                _ = AXUIElementGetPid(child, &ownerPID)
                raw.append(RawRecord(
                    pid: ownerPID,
                    bundleIdentifier: application.bundleIdentifier,
                    name: application.name,
                    bundlePath: application.bundlePath,
                    identityTitle: identity.title,
                    displayTitle: displayTitle,
                    frame: frame,
                    identityState: identity.stable
                        && !application.bundleIdentifier.hasPrefix("pid:")
                        ? .stable : .provisional))
            }
        }

        let directFrames = raw.filter {
            $0.bundleIdentifier != MenuBarOrganizerSupport.menuBarAgentBundleIdentifier
        }.map(\.frame)
        return raw.filter { record in
            record.bundleIdentifier != MenuBarOrganizerSupport.menuBarAgentBundleIdentifier
                || !MenuBarOrganizerSupport.isDuplicateMenuBarAgentRevend(
                    frame: record.frame,
                    directFrames: directFrames)
        }.sorted {
            if $0.frame.minX == $1.frame.minX {
                if $0.bundleIdentifier == $1.bundleIdentifier {
                    return $0.identityTitle < $1.identityTitle
                }
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    private static func firstString(_ name: String,
                                    in elements: [AXUIElement]) -> String? {
        for element in elements {
            if let value: String = attribute(name, from: element),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func attribute<T>(_ name: String,
                                     from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let value: AXValue = attribute("AXFrame", from: element),
              AXValueGetType(value) == .cgRect
        else { return nil }
        var frame = CGRect.zero
        return AXValueGetValue(value, .cgRect, &frame) ? frame : nil
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }
}
