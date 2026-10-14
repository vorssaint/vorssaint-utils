// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

final class MenuBarWindowProvider {
    private struct EnumerationResult {
        let records: [MenuBarOrganizerWindowRecord]
        let succeeded: Bool
        let usedPrivateWindowList: Bool
    }

    private let bridge = MenuBarWindowServerBridge.self
    private let resolver = MenuBarItemSourceResolver()
    private let queue = DispatchQueue(label: "com.vorssaint.menu-bar-enumeration",
                                      qos: .utility)

    func snapshot(hiddenDivider: CGRect,
                  alwaysHiddenDividerMidX: CGFloat?,
                  excludedWindowIDs: Set<CGWindowID>, refreshIdentities: Bool = false) async -> MenuBarItemSnapshot {
        guard MenuBarOrganizerPolicy.supportsAdvancedBackend else {
            return MenuBarItemSnapshot(items: [], capabilities: .unavailable, enumerationSucceeded: false)
        }
        let enumeration = await enumerate()
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount) == .success,
              let scoped = MenuBarOrganizerPolicy.recordsOnDividerDisplay(
                enumeration.records, divider: hiddenDivider,
                displays: displays.prefix(Int(displayCount)).map { CGDisplayBounds($0) }) else {
            return MenuBarItemSnapshot(items: [], capabilities: .unavailable, enumerationSucceeded: false)
        }
        let records = scoped.filter { !excludedWindowIDs.contains($0.windowID) }
        let sources = await resolver.resolve(records: records, refresh: refreshIdentities)
        let identities = MenuBarOrganizerSupport.identities(for: records, sources: sources)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundleIdentifier = Bundle.main.bundleIdentifier

        let items = await MainActor.run {
            records.compactMap { record -> ManagedMenuBarItem? in
                guard let resolved = identities[record.windowID] else { return nil }
                let source = resolved.source
                let bundleIdentifier = source?.bundleIdentifier
                    ?? record.ownerBundleIdentifier
                let identityTitle = source?.stableTitle ?? record.title
                let title = source?.axTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyForDisplay
                    ?? (identityTitle == MenuBarOrganizerSupport.singleItemIdentifier ? "" : identityTitle)
                let protected = MenuBarOrganizerPolicy.isOwnItem(
                    ownerPID: record.ownerPID, sourcePID: source?.pid, bundleIdentifier: bundleIdentifier,
                    currentPID: currentPID, currentBundleIdentifier: currentBundleIdentifier)
                    || MenuBarOrganizerSupport.isSystemImmovable(
                        bundleIdentifier: bundleIdentifier,
                        title: title)
                let movable = resolved.state == .stable && !protected
                return ManagedMenuBarItem(
                    id: resolved.id,
                    windowID: record.windowID,
                    ownerPID: record.ownerPID,
                    ownerBundleIdentifier: record.ownerBundleIdentifier,
                    sourcePID: source?.pid,
                    ownerName: record.ownerName,
                    sourceName: source?.name ?? record.ownerName,
                    bundleIdentifier: bundleIdentifier,
                    title: title,
                    frame: record.frame,
                    section: MenuBarOrganizerSupport.section(
                        itemMidX: record.frame.midX,
                        hiddenDividerMidX: hiddenDivider.midX,
                        alwaysHiddenDividerMidX: alwaysHiddenDividerMidX),
                    identityState: resolved.state,
                    isMovable: movable,
                    isProtected: protected)
            }
            .sorted {
                if $0.frame.minX == $1.frame.minX {
                    return $0.id.storageValue < $1.id.storageValue
                }
                return $0.frame.minX < $1.frame.minX
            }
        }

        return MenuBarItemSnapshot(
            items: items,
            capabilities: MenuBarOrganizerCapabilities(
                canEnumerate: enumeration.succeeded,
                canMove: AXIsProcessTrusted(),
                hasPrivateWindowList: enumeration.usedPrivateWindowList,
                unresolvedItemCount: items.count {
                    $0.identityState == .provisional
                }),
            enumerationSucceeded: enumeration.succeeded)
    }

    private func enumerate() async -> EnumerationResult {
        await withCheckedContinuation { continuation in
            queue.async { [bridge] in
                continuation.resume(returning: Self.enumerate(using: bridge))
            }
        }
    }

    private static func enumerate(
        using bridge: MenuBarWindowServerBridge.Type
    ) -> EnumerationResult {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(
            options, kCGNullWindowID) as? [[String: Any]]
        else {
            return EnumerationResult(records: [],
                                     succeeded: false,
                                     usedPrivateWindowList: false)
        }

        let privateIDs = bridge.menuBarWindowIDs()
        let privateIDSet = privateIDs.map(Set.init)
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount)
        let topEdges = displays.prefix(Int(displayCount)).flatMap {
            let bounds = CGDisplayBounds($0)
            return [bounds.minY, bounds.maxY]
        }

        var records = raw.compactMap {
            record(from: $0, bridge: bridge)
        }
        records = records.filter {
            MenuBarOrganizerSupport.isMenuBarItemCandidate(
                $0, mainMenuLevel: mainMenuLevel)
        }
        if let privateIDSet {
            records = records.filter { privateIDSet.contains($0.windowID) }
        } else {
            records = records.filter {
                MenuBarOrganizerSupport.isLikelyMenuBarWindow(
                    $0, statusLevel: statusLevel, screenTopEdges: topEdges)
            }
        }

        return EnumerationResult(
            records: records,
            succeeded: privateIDs != nil || !records.isEmpty,
            usedPrivateWindowList: privateIDs != nil)
    }

    private static func record(
        from dictionary: [String: Any],
        bridge: MenuBarWindowServerBridge.Type
    ) -> MenuBarOrganizerWindowRecord? {
        guard let idNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
              let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let fallbackFrame = CGRect(dictionaryRepresentation: bounds)
        else { return nil }

        guard idNumber.int64Value > 0, idNumber.int64Value <= Int64(UInt32.max),
              pidNumber.int64Value > 0, pidNumber.int64Value <= Int64(Int32.max) else { return nil }
        let windowID = CGWindowID(idNumber.uint32Value)
        let pid = pid_t(pidNumber.int32Value)
        let frame = bridge.frame(of: windowID) ?? fallbackFrame
        guard MenuBarOrganizerPolicy.validFrame(frame) else { return nil }
        let application = NSRunningApplication(processIdentifier: pid)
        let ownerName = (dictionary[kCGWindowOwnerName as String] as? String)
            ?? application?.localizedName
            ?? ""
        let level = bridge.level(of: windowID)
            ?? CGWindowLevel((dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0)
        return MenuBarOrganizerWindowRecord(
            windowID: windowID,
            ownerPID: pid,
            ownerName: ownerName,
            ownerBundleIdentifier: application?.bundleIdentifier ?? "",
            title: dictionary[kCGWindowName as String] as? String ?? "",
            frame: frame,
            layer: Int(level),
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
    }
}

private extension String {
    var nonEmptyForDisplay: String? { isEmpty ? nil : self }
}
