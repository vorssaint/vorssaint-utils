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
/// front when the pointer is over no window of its own. A surface, a window
/// above the app band that takes the event there such as Launchpad, a menu or
/// a banner, answers in place of the app window it covers. Resolving asks the
/// window server, so the answer is cached until the pointer leaves that
/// window; with every list empty, which is the normal case, nothing is
/// resolved at all and the taps cost exactly what they always did.
///
/// The lists are written on the main thread; the taps that ask run on the
/// pointer thread (`PointerTapRunLoop`), so everything they read is guarded by
/// `lock`. Pointer callbacks reuse the last answer and schedule a refresh on
/// the main thread without waiting for it.
final class MouseAppExceptions: ObservableObject {
    static let shared = MouseAppExceptions()

    /// Guards the lookups, the source ids and the resolved-app cache: written
    /// on the main thread, read from the tap callbacks.
    private let lock = NSLock()

    /// The stored lists, as bundle identifiers per feature.
    @Published private(set) var lists: [MouseExceptionScope: [String]] = [:]
    @Published private(set) var runningScopes = Set<MouseExceptionScope>()

    /// The same lists as sets, for the lookups the taps make. Under `lock`.
    private var lookups: [MouseExceptionScope: Set<String>] = [:]
    /// True while every list is empty, the fast path out of every question.
    private var allEmpty = true
    /// True while some list names a program by its path, the only time a
    /// program's path is read (issue #1009).
    private var listsNamePath = false

    /// Source process ids are resolved outside the event tap. The scroll taps
    /// only ask these sets, never AppKit or the workspace, for each wheel event.
    private var sourceProcessIDs: [MouseExceptionScope: Set<Int32>] = [:]
    private var trackedSourceScopes: Set<MouseExceptionScope> = []
    private var runningApplicationsObservation: NSKeyValueObservation?

    /// The last resolved answer: what the app answers to, the window it came
    /// from (nil when the pointer was over nothing), where the pointer was and
    /// when.
    private var cachedIdentities: [String] = []
    private var cachedRegion: CGRect?
    private var cachedPoint: CGPoint = .zero
    private var cachedAt: TimeInterval = -1
    private var pointerRefreshScheduled = false

    private static let ownProcessID = Int32(getpid())
    private let uptime: () -> TimeInterval
    private let onScreenWindows: () -> [MouseAppExceptionSupport.Window]
    private let receivingWindow: (CGPoint) -> CGWindowID?
    private let identitiesForProcess: ((Int32) -> [String])?

    init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         onScreenWindows: @escaping () -> [MouseAppExceptionSupport.Window] = WindowServerSupport.onScreenWindows,
         receivingWindow: @escaping (CGPoint) -> CGWindowID? = WindowServerSupport.receivingWindow(at:),
         identitiesForProcess: ((Int32) -> [String])? = nil) {
        self.uptime = uptime
        self.onScreenWindows = onScreenWindows
        self.receivingWindow = receivingWindow
        self.identitiesForProcess = identitiesForProcess
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
        lock.withLock {
            allEmpty = lookups.values.allSatisfy(\.isEmpty)
            listsNamePath = lookups.values.contains {
                $0.contains(where: MouseAppExceptionSupport.isExecutablePathIdentity)
            }
        }
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
        let answer = pointerIdentity(at: point)
        // An app cannot be told apart from a listed one while it is unknown,
        // and a list exists to keep hands off, so hands stay off.
        guard answer.known else { return true }
        return MouseAppExceptionSupport.isExcepted(answer.identities, exceptions: exceptions)
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
        let answer = pointerIdentity(at: point)
        guard answer.known else { return true }
        if MouseAppExceptionSupport.isExcepted(answer.identities, exceptions: exceptions) {
            return true
        }
        let frontmost = Self.onMain { identities(for: NSWorkspace.shared.frontmostApplication) }
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
        if !runningScopes.isEmpty { runningScopes.removeAll() }
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
        let updatedScopes = Set(rebuilt.keys)
        Self.onMain {
            if runningScopes != updatedScopes { runningScopes = updatedScopes }
        }
    }

    /// Helpers bundled inside a selected app inherit its exception. This uses
    /// only public bundle URLs and runs on launch or preference changes, never
    /// in the wheel callback.
    private func sourceBundleIdentifiers(for app: NSRunningApplication) -> [String] {
        var identifiers = identities(for: app)

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
    /// back to the app in front when the pointer is over none. A surface that
    /// takes the event there answers in place of both. `known` is false only
    /// on the pointer thread, which never waits for the main one.
    private func pointerIdentity(at point: CGPoint) -> (known: Bool, identities: [String]) {
        let now = uptime()
        // The pointer thread must return even while the main thread is busy.
        // An answer that aged out still names the window it came from, so the
        // pointer resting in that window keeps it; anywhere else the answer
        // belongs to another window and is no answer at all.
        let isMainThread = Thread.isMainThread
        var needsRefresh = false
        let answer = lock.withLock { () -> (settled: Bool, known: Bool, identities: [String]) in
            guard !allEmpty else { return (true, true, []) }
            guard MouseAppExceptionSupport.cacheHolds(region: cachedRegion,
                                                      resolvedPoint: cachedPoint,
                                                      resolvedAt: cachedAt,
                                                      point: point,
                                                      now: now) else {
                if !isMainThread {
                    needsRefresh = !pointerRefreshScheduled
                    if needsRefresh { pointerRefreshScheduled = true }
                    let sameWindow = MouseAppExceptionSupport.cacheNamesWindow(region: cachedRegion,
                                                                              point: point)
                    return (true, sameWindow, sameWindow ? cachedIdentities : [])
                }
                return (false, true, [])
            }
            return (true, true, cachedIdentities)
        }
        if needsRefresh {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.lock.withLock { self.pointerRefreshScheduled = false } }
                _ = self.pointerIdentity(at: point)
            }
        }
        if answer.settled { return (answer.known, answer.identities) }

        let windows = onScreenWindows()
        let surface = MouseAppExceptionSupport.pointerSurface(in: windows,
                                                              receivingWindowID: receivingWindow(point),
                                                              ownProcessID: Self.ownProcessID)
        // A surface no app owns, such as the menu bar the window server draws
        // for the app in front, names nobody, so the usual answer stands.
        let surfaceIdentities = surface.map {
            MouseAppExceptionSupport.surfaceIdentities(identities(forProcess: $0.processID))
        } ?? []
        let resolved: [String]
        let region: CGRect?
        if let surface, !surfaceIdentities.isEmpty {
            // A surface may take less than its rectangle: the Dock's spans the
            // screen and takes events over the Dock only. One that also takes
            // them at its center, as Launchpad and menus do, is taken to fill
            // its rectangle and is cached like a window; any other answers for
            // its exact spot only, like an answer of nothing.
            resolved = surfaceIdentities
            let center = CGPoint(x: surface.frame.midX, y: surface.frame.midY)
            region = receivingWindow(center) == surface.number ? surface.frame : nil
        } else {
            let window = MouseAppExceptionSupport.pointerWindow(in: windows,
                                                                at: point,
                                                                ownProcessID: Self.ownProcessID)
            resolved = window.map { identities(forProcess: $0.processID) }
                ?? identities(for: NSWorkspace.shared.frontmostApplication)
            region = window?.frame
        }
        lock.withLock {
            cachedIdentities = resolved
            cachedRegion = region
            cachedPoint = point
            cachedAt = now
        }
        return (true, resolved)
    }

    /// While a list names a program by its path, a program answers to the
    /// file being run as well as to its bundle identifier, so a Java runtime
    /// picked by its path (issue #1009) is matched even when AWT registered
    /// the JVM under the identifier of Java's launcher.
    private func identities(for app: NSRunningApplication?) -> [String] {
        guard let app else { return [] }
        return MouseAppExceptionSupport.identities(bundleID: app.bundleIdentifier,
                                                   executablePath: app.executableURL?.path,
                                                   readsPath: lock.withLock { listsNamePath })
    }

    private func identities(forProcess processID: Int32) -> [String] {
        if let identitiesForProcess { return identitiesForProcess(processID) }
        return identities(for: NSRunningApplication(processIdentifier: processID))
    }

    private func invalidateCache() {
        lock.withLock {
            cachedIdentities = []
            cachedRegion = nil
            cachedAt = -1
        }
    }
}
