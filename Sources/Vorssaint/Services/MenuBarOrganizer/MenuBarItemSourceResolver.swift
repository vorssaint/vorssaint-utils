// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Foundation

/// Resolves the app that created each status item. On macOS 26 the WindowServer
/// owner is commonly Control Center, so owner PID alone is not a stable item
/// identity. AX work runs away from the main actor and is bounded by the app's
/// process-wide AX timeout.
actor MenuBarItemSourceResolver {
    private struct ApplicationRecord: Sendable {
        let pid: pid_t
        let bundleIdentifier: String
        let name: String
    }

    private struct AXItemRecord: Sendable {
        let source: MenuBarItemSourceIdentity
        let frame: CGRect
    }

    private var cache: [CGWindowID: MenuBarItemSourceIdentity] = [:]
    private var scanTask: Task<[CGWindowID: MenuBarItemSourceIdentity], Never>?
    private var scanID: UUID?

    func resolve(
        records: [MenuBarOrganizerWindowRecord]
    ) async -> [CGWindowID: MenuBarItemSourceIdentity] {
        let liveWindowIDs = Set(records.map(\.windowID))
        cache = cache.filter { liveWindowIDs.contains($0.key) }

        var result = cache
        let unresolvedHosted = records.filter {
            $0.ownerBundleIdentifier == MenuBarOrganizerSupport.controlCenterBundleIdentifier
                && result[$0.windowID] == nil
        }

        for record in records
        where record.ownerBundleIdentifier != MenuBarOrganizerSupport.controlCenterBundleIdentifier {
            let source = MenuBarItemSourceIdentity(
                pid: record.ownerPID,
                bundleIdentifier: record.ownerBundleIdentifier.isEmpty
                    ? "pid:\(record.ownerPID)"
                    : record.ownerBundleIdentifier,
                name: record.ownerName,
                axIdentifier: nil,
                axTitle: record.title)
            result[record.windowID] = source
            cache[record.windowID] = source
        }

        guard !unresolvedHosted.isEmpty, AXIsProcessTrusted() else { return result }
        let applications = await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationRecord? in
                guard !app.isTerminated else { return nil }
                let bundleID = app.bundleIdentifier ?? ""
                return ApplicationRecord(
                    pid: app.processIdentifier,
                    bundleIdentifier: bundleID.isEmpty
                        ? "pid:\(app.processIdentifier)"
                        : bundleID,
                    name: app.localizedName ?? bundleID)
            }
        }
        if scanTask == nil {
            scanID = UUID()
            scanTask = Task.detached(priority: .utility) {
                Self.match(records: unresolvedHosted, applications: applications)
            }
        }
        guard let scanTask, let activeScanID = scanID else { return result }
        let matches = await scanTask.value
        if scanID == activeScanID {
            self.scanTask = nil
            scanID = nil
        }
        for (windowID, source) in matches {
            result[windowID] = source
            cache[windowID] = source
        }
        return result
    }

    func invalidate() {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        cache.removeAll()
    }

    private static func match(
        records: [MenuBarOrganizerWindowRecord],
        applications: [ApplicationRecord]
    ) -> [CGWindowID: MenuBarItemSourceIdentity] {
        var axItems: [AXItemRecord] = []
        for application in applications {
            guard !Task.isCancelled else { return [:] }
            axItems.append(contentsOf: scanExtrasMenuBar(application))
        }
        struct Candidate {
            let windowID: CGWindowID
            let source: MenuBarItemSourceIdentity
            let score: CGFloat
            let sourceSlot: String
            let usesOwnerFallback: Bool
        }

        var candidates: [Candidate] = []
        for record in records {
            guard !Task.isCancelled else { return [:] }
            for axItem in axItems {
                // A generic hosted slot can overlap Control Center's own AX
                // child exactly. That match identifies the host, not the app
                // that supplied the item, and must remain provisional.
                if MenuBarOrganizerSupport.isGenericControlCenterHostedTitle(record.title),
                   axItem.source.bundleIdentifier
                    == MenuBarOrganizerSupport.controlCenterBundleIdentifier {
                    continue
                }
                guard let score = MenuBarOrganizerSupport.frameMatchScore(
                    record.frame, axItem.frame)
                else { continue }
                candidates.append(Candidate(
                    windowID: record.windowID,
                    source: axItem.source,
                    score: score,
                    sourceSlot: "\(axItem.source.pid):"
                        + (axItem.source.axIdentifier ?? axItem.source.axTitle ?? "")
                        + ":\(Int(axItem.frame.minX)):\(Int(axItem.frame.minY))",
                    usesOwnerFallback:
                        axItem.source.bundleIdentifier
                            == MenuBarOrganizerSupport.controlCenterBundleIdentifier))
            }
        }

        var usedWindows = Set<CGWindowID>()
        var usedSources = Set<String>()
        var result: [CGWindowID: MenuBarItemSourceIdentity] = [:]
        for candidate in candidates.sorted(by: {
            if $0.score != $1.score { return $0.score < $1.score }
            return !$0.usesOwnerFallback && $1.usesOwnerFallback
        }) {
            guard !usedWindows.contains(candidate.windowID),
                  !usedSources.contains(candidate.sourceSlot)
            else { continue }
            usedWindows.insert(candidate.windowID)
            usedSources.insert(candidate.sourceSlot)
            result[candidate.windowID] = candidate.source
        }
        return result
    }

    private static func scanExtrasMenuBar(_ app: ApplicationRecord) -> [AXItemRecord] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let extras: AXUIElement = attribute("AXExtrasMenuBar", from: application),
              let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: extras)
        else { return [] }

        return children.compactMap { child in
            guard let frame = frame(of: child) else { return nil }
            var pid = app.pid
            AXUIElementGetPid(child, &pid)
            let source = MenuBarItemSourceIdentity(
                pid: pid,
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                axIdentifier: attribute(kAXIdentifierAttribute, from: child),
                axTitle: attribute(kAXTitleAttribute, from: child))
            return AXItemRecord(source: source, frame: frame)
        }
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
        guard AXValueGetValue(value, .cgRect, &frame),
              frame.width > 0,
              frame.height > 0
        else { return nil }
        return frame
    }
}
