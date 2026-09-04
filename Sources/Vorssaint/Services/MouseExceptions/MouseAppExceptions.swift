// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Apps each mouse feature leaves alone (issue #358). Some apps drive
/// themselves with the wheel and the extra buttons, so a glide or a swallowed
/// click lands as a wrong command inside them; while one of those apps is the
/// one being scrolled or clicked, the feature that named it stands down and
/// the events reach the app exactly as the system produced them. Every
/// feature keeps its own list, so leaving an app out of one never changes
/// what the others do there.
///
/// The app is resolved from the window under the pointer, which is where
/// macOS delivers both the wheel and the click, and falls back to the app in
/// front when the pointer is over no window of its own. Resolving asks the
/// window server, so the answer is cached until the pointer leaves that
/// window; with every list empty, which is the normal case, nothing is
/// resolved at all and the taps cost exactly what they always did.
///
/// The lists are written on the main thread; the taps that ask run on the
/// pointer thread (`PointerTapRunLoop`), so everything they read is guarded by
/// `lock` and the AppKit half of resolving is asked on the main thread.
final class MouseAppExceptions: ObservableObject {
    static let shared = MouseAppExceptions()

    /// Guards the lookups, the source ids and the resolved-app cache: written
    /// on the main thread, read from the tap callbacks.
    private let lock = NSLock()

    /// The stored lists, as bundle identifiers per feature.
    @Published private(set) var lists: [MouseExceptionScope: [String]] = [:]

    /// The same lists as sets, for the lookups the taps make. Under `lock`.
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
        for scope in MouseExceptionScope.allCases {
            let raw = defaults.stringArray(forKey: scope.defaultsKey) ?? []
            let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
            if raw != sanitized {
                defaults.set(sanitized, forKey: scope.defaultsKey)
            }
            lists[scope] = sanitized
            lock.withLock { lookups[scope] = Set(sanitized) }
        }
        lock.withLock { allEmpty = lookups.values.allSatisfy(\.isEmpty) }
        invalidateCache()
        refreshSourceTracking()
    }

    func list(_ scope: MouseExceptionScope) -> [String] { lists[scope] ?? [] }

    /// The lists and source ids a tap needs, copied out under the lock.
    private func lookup(_ scope: MouseExceptionScope) -> (exceptions: Set<String>, sources: Set<Int32>) {
        lock.withLock { (lookups[scope] ?? [], sourceProcessIDs[scope] ?? []) }
    }

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

    /// True when the app under the pointer or the app that posted the event is
    /// on this feature's list. Source ids are used only by the two scroll taps;
    /// hardware wheel events have no app source and keep the original path.
    func excludesPointerTarget(_ scope: MouseExceptionScope,
                               at point: CGPoint,
                               sourceProcessID: Int64 = 0) -> Bool {
        let (exceptions, sources) = lookup(scope)
        guard !exceptions.isEmpty else { return false }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           sources.contains(pid) {
            return true
        }
        return MouseAppExceptionSupport.isExcepted(pointerIdentity(at: point), exceptions: exceptions)
    }

    /// True when the app under the pointer or the app in front is on this
    /// feature's list. The side buttons and the button shortcuts send their
    /// command to the app in front, while the click they swallow belonged to
    /// the app under the pointer, so an exception on either side means hands
    /// off.
    func excludesActionTarget(_ scope: MouseExceptionScope,
                              at point: CGPoint,
                              sourceProcessID: Int64 = 0) -> Bool {
        let (exceptions, sources) = lookup(scope)
        guard !exceptions.isEmpty else { return false }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           sources.contains(pid) {
            return true
        }
        if MouseAppExceptionSupport.isExcepted(pointerIdentity(at: point), exceptions: exceptions) {
            return true
        }
        let frontmost = Self.onMain { Self.identity(for: NSWorkspace.shared.frontmostApplication) }
        return MouseAppExceptionSupport.isExcepted(frontmost, exceptions: exceptions)
    }

    /// Services that intercept wheel events call this with their tap lifecycle.
    /// With every such feature off, unavailable or carrying an empty list, no
    /// workspace observer or source cache remains alive.
    func setSourceTracking(_ active: Bool, for scope: MouseExceptionScope) {
        lock.withLock {
            if active {
                trackedSourceScopes.insert(scope)
            } else {
                trackedSourceScopes.remove(scope)
            }
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
        lock.withLock { sourceProcessIDs.removeAll(keepingCapacity: false) }
    }

    private func rebuildSourceProcesses(_ applications: [NSRunningApplication]) {
        var rebuilt: [MouseExceptionScope: Set<Int32>] = [:]
        let (scopes, exceptionsByScope) = lock.withLock { (trackedSourceScopes, lookups) }
        for app in applications {
            let bundleIDs = sourceBundleIdentifiers(for: app)
            guard !bundleIDs.isEmpty else { continue }
            for scope in scopes {
                guard let exceptions = exceptionsByScope[scope],
                      MouseAppExceptionSupport.isExcepted(bundleIDs,
                                                          exceptions: exceptions) else { continue }
                rebuilt[scope, default: []].insert(app.processIdentifier)
            }
        }
        lock.withLock { sourceProcessIDs = rebuilt }
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

    /// What the app that owns the window under the pointer answers to, falling
    /// back to the app in front when the pointer is over none.
    private func pointerIdentity(at point: CGPoint) -> String? {
        let now = ProcessInfo.processInfo.systemUptime
        // The cache answers under the lock; resolving happens outside it,
        // since it ends up on the main thread.
        let answer = lock.withLock { () -> (settled: Bool, identity: String?) in
            guard !allEmpty else { return (true, nil) }
            guard MouseAppExceptionSupport.cacheHolds(region: cachedRegion,
                                                      resolvedPoint: cachedPoint,
                                                      resolvedAt: cachedAt,
                                                      point: point,
                                                      now: now) else { return (false, nil) }
            return (true, cachedIdentity)
        }
        if answer.settled { return answer.identity }

        let window = MouseAppExceptionSupport.pointerWindow(in: WindowServerSupport.onScreenWindows(),
                                                            at: point,
                                                            ownProcessID: Self.ownProcessID)
        let identity = Self.onMain { () -> String? in
            let app = window.map { NSRunningApplication(processIdentifier: $0.processID) }
                ?? NSWorkspace.shared.frontmostApplication
            return Self.identity(for: app)
        }
        lock.withLock {
            cachedIdentity = identity
            cachedRegion = window?.frame
            cachedPoint = point
            cachedAt = now
        }
        return identity
    }

    /// A program with no bundle identifier answers to the file being run
    /// instead, so a game started from a launcher can be named at all
    /// (issue #1009).
    private static func identity(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        return MouseAppExceptionSupport.identity(bundleID: app.bundleIdentifier,
                                                 executablePath: app.executableURL?.path)
    }

    private func invalidateCache() {
        lock.withLock {
            cachedIdentity = nil
            cachedRegion = nil
            cachedAt = -1
        }
    }
}
