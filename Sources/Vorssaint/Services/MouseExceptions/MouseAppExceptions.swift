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
/// window server, so the answer is cached until the pointer leaves that
/// window (or `resolveLifetime` expires); a miss is filled synchronously so every
/// event gets a correct answer. With every list empty, which is the normal
/// case, nothing is resolved at all.
///
/// List mutations stay on the main thread; tap lookups read an immutable
/// snapshot under a lock so a dedicated scroll thread stays race-free. When
/// the pointer answer is unknown, features with a non-empty list stand down
/// rather than guess.
final class MouseAppExceptions: ObservableObject {
    static let shared = MouseAppExceptions()

    /// The stored app identities (bundle identifiers or executable paths).
    @Published private(set) var lists: [MouseExceptionScope: [String]] = [:]
    /// Scopes whose excepted apps are currently running (for UI / SuperKey).
    @Published private(set) var runningScopes = Set<MouseExceptionScope>()

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

    /// The last resolved answer: what the app answers to, the window it came
    /// from (nil when the pointer was over nothing), where the pointer was and
    /// when.
    private var cachedIdentity: String?
    private var cachedRegion: CGRect?
    private var cachedPoint: CGPoint = .zero
    private var cachedAt: TimeInterval = -1

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

    /// AppKit answers on the main thread, since the taps that ask no longer
    /// run there.
    private static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    /// Sanitized here the same way `reload` sanitizes what it reads, so an
    /// entry cannot be stored in one spelling and looked for in another.
    func add(_ identity: String, to scope: MouseExceptionScope) {
        let updated = Defaults.sanitizedBundleIdentifierList(list(scope) + [identity])
        guard updated != list(scope) else { return }
        UserDefaults.standard.set(updated, forKey: scope.defaultsKey)
        reload()
    }

    func remove(_ bundleID: String, from scope: MouseExceptionScope) {
        guard list(scope).contains(bundleID) else { return }
        UserDefaults.standard.set(list(scope).filter { $0 != bundleID }, forKey: scope.defaultsKey)
        reload()
    }

    // MARK: - The question the taps ask

    /// True when the app under the pointer, the event target, or the app that
    /// posted the event is on this feature's list. Process-id sets are cheap
    /// and cover known excepted apps; a cache miss fills the pointer answer
    /// synchronously so the first tick is never guessed. While the pointer
    /// app is unknown, hands stay off.
    func excludesPointerTarget(_ scope: MouseExceptionScope,
                               at point: CGPoint,
                               sourceProcessID: Int64 = 0,
                               targetProcessID: Int64 = 0) -> Bool {
        let snapshot = makeSnapshot()
        guard let exceptions = snapshot.lookups[scope], !exceptions.isEmpty else {
            return false
        }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           snapshot.sourceProcessIDs[scope]?.contains(pid) == true {
            return true
        }
        if let pid = MouseAppExceptionSupport.sourceProcessID(targetProcessID),
           snapshot.sourceProcessIDs[scope]?.contains(pid) == true {
            return true
        }
        let answer = pointerIdentity(at: point)
        // An app cannot be told apart from a listed one while it is unknown,
        // and a list exists to keep hands off, so hands stay off.
        guard answer.known else { return true }
        return MouseAppExceptionSupport.isExcepted(answer.identity, exceptions: exceptions)
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
        let frontmost = Self.onMain { Self.identity(for: NSWorkspace.shared.frontmostApplication) }
        return MouseAppExceptionSupport.isExcepted(frontmost, exceptions: exceptions)
    }

    /// Services that intercept wheel events call this with their tap lifecycle.
    /// With every such feature off, unavailable or carrying an empty list, no
    /// workspace observer or source cache remains alive.
    func setSourceTracking(_ active: Bool, for scope: MouseExceptionScope) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setSourceTracking(active, for: scope)
            }
            return
        }
        if active {
            trackedSourceScopes.insert(scope)
        } else {
            trackedSourceScopes.remove(scope)
        }
        refreshSourceTracking()
    }

    private func refreshSourceTracking() {
        let shouldTrack = lock.withLock {
            trackedSourceScopes.contains { lookups[$0]?.isEmpty == false }
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
        if !runningScopes.isEmpty { runningScopes.removeAll() }
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
        let updatedScopes = Set(next.keys)
        Self.onMain {
            if runningScopes != updatedScopes { runningScopes = updatedScopes }
        }
    }

    /// Helpers bundled inside a selected app inherit its exception. This uses
    /// only public bundle URLs and runs on launch or preference changes, never
    /// in the wheel callback.
    private func sourceBundleIdentifiers(for app: NSRunningApplication) -> [String] {
        var identifiers: [String] = []
        if let identity = Self.identity(for: app) {
            identifiers.append(identity)
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
                sourceProcessIDs: sourceProcessIDs)
        }
    }

    /// What the app that owns the window under the pointer answers to, falling
    /// back to the app in front when the pointer is over none. A miss asks the
    /// window server on the caller thread (~190 µs) and caches the answer.
    /// `known` is false when a list is active but no window owns this point:
    /// inventing the frontmost app there would act inside a listed one by
    /// mistake, so the feature stands down until a window can be named.
    private func pointerIdentity(at point: CGPoint) -> (known: Bool, identity: String?) {
        let now = ProcessInfo.processInfo.systemUptime
        let cached = lock.withLock { () -> (known: Bool, identity: String?)? in
            guard !allEmpty else { return (true, nil) }
            if MouseAppExceptionSupport.cacheHolds(region: cachedRegion,
                                                   resolvedPoint: cachedPoint,
                                                   resolvedAt: cachedAt,
                                                   point: point,
                                                   now: now) {
                return (true, cachedIdentity)
            }
            return nil
        }
        if let cached { return cached }

        let window = MouseAppExceptionSupport.pointerWindow(
            in: WindowServerSupport.onScreenWindows(),
            at: point,
            ownProcessID: Self.ownProcessID)
        // No window under the pointer: do not borrow the frontmost app as if it
        // owned this spot. Standing down is the side the exception list exists
        // to protect (issue #1071 / unknown-pointer hands-off).
        guard let window else {
            return (false, nil)
        }
        // LaunchServices / workspace work stays outside `lock` so other taps
        // can still copy their snapshot while this event resolves.
        let resolvedIdentity = Self.identity(
            for: NSRunningApplication(processIdentifier: window.processID))
        let resolvedAt = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            guard !allEmpty else { return }
            cachedIdentity = resolvedIdentity
            cachedRegion = window.frame
            cachedPoint = point
            cachedAt = resolvedAt
        }
        return (true, resolvedIdentity)
    }

    /// A program with no bundle identifier answers to the file being run
    /// instead, so a game started from a launcher can be named at all
    /// (issue #1009).
    private static func identity(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        return MouseAppExceptionSupport.identity(bundleID: app.bundleIdentifier,
                                                 executablePath: app.executableURL?.path)
    }

    private func invalidateCacheLocked() {
        cachedIdentity = nil
        cachedRegion = nil
        cachedAt = -1
    }
}
