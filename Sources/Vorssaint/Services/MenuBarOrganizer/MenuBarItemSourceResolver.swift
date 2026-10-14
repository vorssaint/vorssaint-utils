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
    private var cachedRecords: [CGWindowID: MenuBarOrganizerWindowRecord] = [:]
    private var scanTask: Task<[CGWindowID: MenuBarItemSourceIdentity], Never>?
    private var scanID: UUID?
    private var scanRecords: [MenuBarOrganizerWindowRecord] = []
    private let scanner: @Sendable ([MenuBarOrganizerWindowRecord]) async -> [CGWindowID: MenuBarItemSourceIdentity]
    private let isTrusted: @Sendable () -> Bool

    init(isTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
         scanner: @escaping @Sendable ([MenuBarOrganizerWindowRecord]) async -> [CGWindowID: MenuBarItemSourceIdentity] = { await MenuBarItemSourceResolver.scanHosted(records: $0) }) {
        self.isTrusted = isTrusted
        self.scanner = scanner
    }

    func resolve(
        records: [MenuBarOrganizerWindowRecord], refresh: Bool = false
    ) async -> [CGWindowID: MenuBarItemSourceIdentity] {
        if refresh { invalidate() }
        guard !Task.isCancelled else { return [:] }
        // Geometry changes during our own drag do not change a window's owner.
        // Reused IDs or changed titles must be resolved again. App lifecycle,
        // permission and display changes also invalidate the whole inventory.
        let reusableIDs = Set(records.filter { record in
            guard let old = cachedRecords[record.windowID] else { return false }
            return old.ownerPID == record.ownerPID && old.ownerBundleIdentifier == record.ownerBundleIdentifier
                && old.title == record.title
        }.map(\.windowID))
        cache = cache.filter { reusableIDs.contains($0.key) }
        cachedRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.windowID, $0) })

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

        if scanTask != nil, scanRecords != unresolvedHosted {
            scanTask?.cancel()
            scanTask = nil
            scanID = nil
            scanRecords = []
        }
        guard !unresolvedHosted.isEmpty, isTrusted() else { return result }
        if scanTask == nil {
            scanID = UUID()
            scanRecords = unresolvedHosted
            let scanner = self.scanner
            scanTask = Task { await scanner(unresolvedHosted) }
        }
        guard let scanTask, let activeScanID = scanID else { return result }
        let matches = await scanTask.value
        // invalidate() can run while this actor awaits the scanner. Neither a
        // cancelled caller nor an obsolete scan may return or cache identities.
        guard scanID == activeScanID else { return [:] }
        self.scanTask = nil
        scanID = nil
        scanRecords = []
        guard !Task.isCancelled, !scanTask.isCancelled, isTrusted() else { return [:] }
        let requestedIDs = Set(unresolvedHosted.map(\.windowID))
        for (windowID, source) in matches where requestedIDs.contains(windowID) {
            result[windowID] = source
            cache[windowID] = source
        }
        return result
    }

    private static func scanHosted(records: [MenuBarOrganizerWindowRecord]) async -> [CGWindowID: MenuBarItemSourceIdentity] {
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
        let task = Task.detached(priority: .utility) {
            Self.match(records: records, applications: applications)
        }
        return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    func invalidate() {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        scanRecords = []
        cache.removeAll()
        cachedRecords.removeAll()
    }

    private static func match(
        records: [MenuBarOrganizerWindowRecord],
        applications: [ApplicationRecord]
    ) -> [CGWindowID: MenuBarItemSourceIdentity] {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var axItems: [AXItemRecord] = []
        for application in applications {
            guard !Task.isCancelled else { return [:] }
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            axItems.append(contentsOf: scanExtrasMenuBar(application, deadline: deadline))
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

    private static func scanExtrasMenuBar(_ app: ApplicationRecord, deadline: TimeInterval) -> [AXItemRecord] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let extras: AXUIElement = attribute("AXExtrasMenuBar", from: application),
              let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: extras)
        else { return [] }

        return children.prefix(256).compactMap { child in
            guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(child, 0.2)
            guard let frame = frame(of: child) else { return nil }
            var pid = app.pid
            AXUIElementGetPid(child, &pid)
            let source = MenuBarItemSourceIdentity(
                pid: pid,
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                axIdentifier: MenuBarOrganizerSupport.sourceIdentifier(
                    attribute(kAXIdentifierAttribute, from: child), siblingCount: children.count),
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
        var frame = CGRect.zero
        if let value: AXValue = attribute("AXFrame", from: element),
           AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &frame),
           MenuBarOrganizerPolicy.validFrame(frame) { return frame }
        guard let position: AXValue = attribute(kAXPositionAttribute, from: element),
              let size: AXValue = attribute(kAXSizeAttribute, from: element),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        frame = CGRect(origin: point, size: dimensions)
        return MenuBarOrganizerPolicy.validFrame(frame) ? frame : nil
    }
}
