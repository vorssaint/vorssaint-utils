// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Apps each mouse feature leaves alone (issue #358). Some apps drive
/// themselves with the wheel and the extra buttons, so a glide or a swallowed
/// click lands as a wrong command inside them; while one of those apps is the
/// one being scrolled or clicked, the relevant behavior stands down and the
/// events reach the app exactly as the system produced them. Smooth scrolling
/// and direction inversion share one wheel list; unrelated mouse actions keep
/// independent lists.
///
/// The app is resolved from the window under the pointer, which is where
/// macOS delivers both the wheel and the click, and falls back to the app in
/// front when the pointer is over no window of its own. Resolving asks the
/// window server on a private queue, then caches the answer until the pointer
/// leaves that window. Event taps never wait for that round-trip: they first
/// consult the event's target process id (synchronously available) and only
/// then the cached pointer answer / frontmost fallback.
///
/// List mutations stay on the main thread; tap lookups read an immutable
/// snapshot under a lock so a dedicated scroll thread stays race-free.
final class MouseAppExceptions: ObservableObject {
    static let shared = MouseAppExceptions()

    /// The stored lists, as bundle identifiers per feature.
    @Published private(set) var lists: [MouseExceptionScope: [String]] = [:]

    private let lock = NSLock()
    /// The same lists as sets, for the lookups the taps make.
    private var lookups: [MouseExceptionScope: Set<String>] = [:]
    /// True while every list is empty, the fast path out of every question.
    private var allEmpty = true

    /// Source process ids are resolved outside the event tap. The scroll taps
    /// only ask these sets, never AppKit or the workspace, for each wheel event.
    private var sourceProcessIDs: [MouseExceptionScope: Set<Int32>] = [:]
    private var trackedSourceScopes: Set<MouseExceptionScope> = []
    private var runningApplicationsObservation: NSKeyValueObservation?

    /// The last resolved answer: the app, the window it came from (nil when
    /// the pointer was over nothing), where the pointer was and when.
    private var cachedBundleID: String?
    private var cachedRegion: CGRect?
    private var cachedPoint: CGPoint = .zero
    private var cachedAt: TimeInterval = -1
    private let pointerResolutionQueue = DispatchQueue(
        label: "com.vorssaint.utils.mouse-exceptions.pointer",
        qos: .userInteractive
    )
    private var latestRequestedPoint: CGPoint?
    private var activeResolution: UInt64?
    private var resolutionGeneration: UInt64 = 0

    private static let ownProcessID = Int32(getpid())

    private init() {
        reload()
    }

    // MARK: - The lists

    func reload() {
        let defaults = UserDefaults.standard
        Defaults.migrateMouseScrollingExceptions(in: defaults)
        var nextLists: [MouseExceptionScope: [String]] = [:]
        var nextLookups: [MouseExceptionScope: Set<String>] = [:]
        for scope in MouseExceptionScope.allCases {
            let raw = defaults.stringArray(forKey: scope.defaultsKey) ?? []
            let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
            if raw != sanitized {
                defaults.set(sanitized, forKey: scope.defaultsKey)
            }
            nextLists[scope] = sanitized
            nextLookups[scope] = Set(sanitized)
        }
        let nextAllEmpty = nextLookups.values.allSatisfy(\.isEmpty)
        lock.withLock {
            lookups = nextLookups
            allEmpty = nextAllEmpty
            invalidateCacheLocked()
        }
        lists = nextLists
        refreshSourceTracking()
    }

    func list(_ scope: MouseExceptionScope) -> [String] { lists[scope] ?? [] }

    func add(_ bundleID: String, to scope: MouseExceptionScope) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !list(scope).contains(bundleID) else { return }
        UserDefaults.standard.set(list(scope) + [bundleID], forKey: scope.defaultsKey)
        reload()
    }

    func remove(_ bundleID: String, from scope: MouseExceptionScope) {
        guard list(scope).contains(bundleID) else { return }
        UserDefaults.standard.set(list(scope).filter { $0 != bundleID }, forKey: scope.defaultsKey)
        reload()
    }

    // MARK: - The question the taps ask

    /// True when the app under the pointer, the event target, or the app that
    /// posted the event is on this feature's list. Target ids cover the first
    /// wheel tick before the async pointer cache warms.
    func excludesPointerTarget(_ scope: MouseExceptionScope,
                               at point: CGPoint,
                               sourceProcessID: Int64 = 0,
                               targetProcessID: Int64 = 0) -> Bool {
        let snapshot = makeSnapshot()
        guard let exceptions = snapshot.lookups[scope], !exceptions.isEmpty else {
            return false
        }
        let targetBundleID = bundleID(forProcessID: targetProcessID)
        let pointerBundleID = pointerBundleID(at: point, snapshot: snapshot)
        return MouseAppExceptionSupport.excludes(
            scope: scope,
            snapshot: snapshot,
            sourceProcessID: sourceProcessID,
            targetProcessID: targetProcessID,
            targetBundleID: targetBundleID,
            pointerBundleID: pointerBundleID)
    }

    /// True when the app under the pointer or the app in front is on this
    /// feature's list. The side buttons and the button shortcuts send their
    /// command to the app in front, while the click they swallow belonged to
    /// the app under the pointer, so an exception on either side means hands
    /// off.
    func excludesActionTarget(_ scope: MouseExceptionScope,
                              at point: CGPoint,
                              sourceProcessID: Int64 = 0,
                              targetProcessID: Int64 = 0) -> Bool {
        if excludesPointerTarget(scope,
                                 at: point,
                                 sourceProcessID: sourceProcessID,
                                 targetProcessID: targetProcessID) {
            return true
        }
        let snapshot = makeSnapshot()
        guard let exceptions = snapshot.lookups[scope], !exceptions.isEmpty else {
            return false
        }
        return MouseAppExceptionSupport.isExcepted(
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            exceptions: exceptions)
    }

    /// Services that intercept wheel events call this with their tap lifecycle.
    /// With every such feature off, unavailable or carrying an empty list, no
    /// workspace observer or source cache remains alive.
    func setSourceTracking(_ active: Bool, for scope: MouseExceptionScope) {
        if active {
            trackedSourceScopes.insert(scope)
        } else {
            trackedSourceScopes.remove(scope)
        }
        refreshSourceTracking()
    }

    private func refreshSourceTracking() {
        let shouldTrack = trackedSourceScopes.contains { scope in
            lock.withLock { lookups[scope]?.isEmpty == false }
        }
        guard shouldTrack else {
            stopSourceTracking()
            return
        }

        if runningApplicationsObservation == nil {
            runningApplicationsObservation = NSWorkspace.shared.observe(
                \.runningApplications, options: [.initial, .new]) { [weak self] workspace, _ in
                    self?.rebuildSourceProcesses(workspace.runningApplications)
            }
        } else {
            rebuildSourceProcesses(NSWorkspace.shared.runningApplications)
        }
    }

    private func stopSourceTracking() {
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
        lock.withLock {
            sourceProcessIDs.removeAll(keepingCapacity: false)
        }
    }

    private func rebuildSourceProcesses(_ applications: [NSRunningApplication]) {
        var next: [MouseExceptionScope: Set<Int32>] = [:]
        let tracked = trackedSourceScopes
        let lookupsCopy = lock.withLock { lookups }
        for app in applications {
            let bundleIDs = sourceBundleIdentifiers(for: app)
            guard !bundleIDs.isEmpty else { continue }
            for scope in tracked {
                guard let exceptions = lookupsCopy[scope],
                      MouseAppExceptionSupport.isExcepted(bundleIDs,
                                                          exceptions: exceptions) else { continue }
                next[scope, default: []].insert(app.processIdentifier)
            }
        }
        lock.withLock {
            sourceProcessIDs = next
        }
    }

    /// Helpers bundled inside a selected app inherit its exception. This uses
    /// only public bundle URLs and runs on launch or preference changes, never
    /// in the wheel callback.
    private func sourceBundleIdentifiers(for app: NSRunningApplication) -> [String] {
        var identifiers: [String] = []
        if let bundleID = app.bundleIdentifier {
            identifiers.append(bundleID)
        }

        var url = (app.bundleURL ?? app.executableURL)?.standardizedFileURL
        while let candidate = url, candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let bundleID = Bundle(url: candidate)?.bundleIdentifier,
               !identifiers.contains(bundleID) {
                identifiers.append(bundleID)
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            url = parent
        }
        return identifiers
    }

    // MARK: - Resolving

    private func makeSnapshot() -> MouseAppExceptionSupport.LookupSnapshot {
        lock.withLock {
            MouseAppExceptionSupport.LookupSnapshot(
                lookups: lookups,
                sourceProcessIDs: sourceProcessIDs,
                allEmpty: allEmpty,
                cachedBundleID: cachedBundleID,
                cachedRegion: cachedRegion,
                cachedPoint: cachedPoint,
                cachedAt: cachedAt)
        }
    }

    private func bundleID(forProcessID rawValue: Int64) -> String? {
        guard let pid = MouseAppExceptionSupport.sourceProcessID(rawValue) else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// The app that owns the window under the pointer. A cache miss schedules
    /// the WindowServer query off the event-tap run loop and returns the app in
    /// front for this event; subsequent wheel events use the resolved cache.
    private func pointerBundleID(at point: CGPoint,
                                 snapshot: MouseAppExceptionSupport.LookupSnapshot) -> String? {
        guard !snapshot.allEmpty else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if MouseAppExceptionSupport.cacheHolds(region: snapshot.cachedRegion,
                                               resolvedPoint: snapshot.cachedPoint,
                                               resolvedAt: snapshot.cachedAt,
                                               point: point,
                                               now: now) {
            return snapshot.cachedBundleID
        }

        requestPointerResolution(at: point)
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func requestPointerResolution(at point: CGPoint) {
        lock.withLock {
            latestRequestedPoint = point
            guard activeResolution == nil else { return }

            resolutionGeneration &+= 1
            let token = resolutionGeneration
            activeResolution = token
            latestRequestedPoint = nil

            pointerResolutionQueue.async { [weak self] in
                guard let self else { return }
                let window = MouseAppExceptionSupport.pointerWindow(
                    in: Self.onScreenWindows(),
                    at: point,
                    ownProcessID: Self.ownProcessID
                )
                DispatchQueue.main.async { [weak self] in
                    self?.finishPointerResolution(window, at: point, token: token)
                }
            }
        }
    }

    private func finishPointerResolution(_ window: MouseAppExceptionSupport.Window?,
                                         at point: CGPoint,
                                         token: UInt64) {
        var followUp: CGPoint?
        lock.withLock {
            guard activeResolution == token else { return }
            activeResolution = nil
            guard !allEmpty else { return }

            cachedBundleID = window.flatMap {
                NSRunningApplication(processIdentifier: $0.processID)?.bundleIdentifier
            } ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            cachedRegion = window?.frame
            cachedPoint = point
            cachedAt = ProcessInfo.processInfo.systemUptime

            if let latestRequestedPoint {
                self.latestRequestedPoint = nil
                let cacheStillHolds = MouseAppExceptionSupport.cacheHolds(
                    region: cachedRegion,
                    resolvedPoint: cachedPoint,
                    resolvedAt: cachedAt,
                    point: latestRequestedPoint,
                    now: cachedAt
                )
                if !cacheStillHolds {
                    followUp = latestRequestedPoint
                }
            }
        }
        if let followUp {
            requestPointerResolution(at: followUp)
        }
    }

    private func invalidateCacheLocked() {
        resolutionGeneration &+= 1
        activeResolution = nil
        latestRequestedPoint = nil
        cachedBundleID = nil
        cachedRegion = nil
        cachedAt = -1
    }

    /// The on-screen windows, front to back, without the desktop and its
    /// icons: scrolling the empty desktop must fall through to the app in
    /// front rather than answer with the file manager behind everything.
    private static func onScreenWindows() -> [MouseAppExceptionSupport.Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (raw["X"] as? NSNumber)?.doubleValue,
                  let y = (raw["Y"] as? NSNumber)?.doubleValue,
                  let width = (raw["Width"] as? NSNumber)?.doubleValue,
                  let height = (raw["Height"] as? NSNumber)?.doubleValue,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
                return nil
            }
            return MouseAppExceptionSupport.Window(
                frame: CGRect(x: x, y: y, width: width, height: height),
                layer: layer,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                processID: pid)
        }
    }
}
