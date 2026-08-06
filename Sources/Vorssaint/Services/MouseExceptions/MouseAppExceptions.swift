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
/// Main thread only, like the taps that ask.
final class MouseAppExceptions: ObservableObject {
    static let shared = MouseAppExceptions()

    /// The stored lists, as bundle identifiers per feature.
    @Published private(set) var lists: [MouseExceptionScope: [String]] = [:]

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
            lookups[scope] = Set(sanitized)
        }
        allEmpty = lookups.values.allSatisfy(\.isEmpty)
        invalidateCache()
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

    /// True when the app under the pointer or the app that posted the event is
    /// on this feature's list. Source ids are used only by the two scroll taps;
    /// hardware wheel events have no app source and keep the original path.
    func excludesPointerTarget(_ scope: MouseExceptionScope,
                               at point: CGPoint,
                               sourceProcessID: Int64 = 0) -> Bool {
        guard let exceptions = lookups[scope], !exceptions.isEmpty else { return false }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           sourceProcessIDs[scope]?.contains(pid) == true {
            return true
        }
        return MouseAppExceptionSupport.isExcepted(pointerBundleID(at: point), exceptions: exceptions)
    }

    /// True when the app under the pointer or the app in front is on this
    /// feature's list. The side buttons and the button shortcuts send their
    /// command to the app in front, while the click they swallow belonged to
    /// the app under the pointer, so an exception on either side means hands
    /// off.
    func excludesActionTarget(_ scope: MouseExceptionScope,
                              at point: CGPoint,
                              sourceProcessID: Int64 = 0) -> Bool {
        guard let exceptions = lookups[scope], !exceptions.isEmpty else { return false }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           sourceProcessIDs[scope]?.contains(pid) == true {
            return true
        }
        if MouseAppExceptionSupport.isExcepted(pointerBundleID(at: point), exceptions: exceptions) {
            return true
        }
        return MouseAppExceptionSupport.isExcepted(NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
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
        let shouldTrack = trackedSourceScopes.contains {
            lookups[$0]?.isEmpty == false
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
        sourceProcessIDs.removeAll(keepingCapacity: false)
    }

    private func rebuildSourceProcesses(_ applications: [NSRunningApplication]) {
        sourceProcessIDs.removeAll(keepingCapacity: true)
        for app in applications {
            let bundleIDs = sourceBundleIdentifiers(for: app)
            guard !bundleIDs.isEmpty else { continue }
            for scope in trackedSourceScopes {
                guard let exceptions = lookups[scope],
                      MouseAppExceptionSupport.isExcepted(bundleIDs,
                                                          exceptions: exceptions) else { continue }
                sourceProcessIDs[scope, default: []].insert(app.processIdentifier)
            }
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

    /// The app that owns the window under the pointer, falling back to the
    /// app in front when the pointer is over none.
    private func pointerBundleID(at point: CGPoint) -> String? {
        guard !allEmpty else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if MouseAppExceptionSupport.cacheHolds(region: cachedRegion,
                                               resolvedPoint: cachedPoint,
                                               resolvedAt: cachedAt,
                                               point: point,
                                               now: now) {
            return cachedBundleID
        }

        let window = MouseAppExceptionSupport.pointerWindow(in: Self.onScreenWindows(),
                                                            at: point,
                                                            ownProcessID: Self.ownProcessID)
        let bundleID: String?
        if let window {
            bundleID = NSRunningApplication(processIdentifier: window.processID)?.bundleIdentifier
        } else {
            bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        cachedBundleID = bundleID
        cachedRegion = window?.frame
        cachedPoint = point
        cachedAt = now
        return bundleID
    }

    private func invalidateCache() {
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
