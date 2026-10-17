// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The mouse and keyboard features that can be told to leave an app alone
/// (issues #358, #741).
/// Each one keeps its OWN list, right under its switch in Settings: excepting
/// an app from the wheel's glide must not also silence the side buttons there.
enum MouseExceptionScope: String, CaseIterable {
    case smoothScroll
    case linearScroll
    case scrollDirection
    case focusFollowsMouse
    case navigation
    case buttonShortcuts
    case middleClick
    case superKey
    case selectionBar

    var defaultsKey: String {
        switch self {
        case .smoothScroll: return DefaultsKey.smoothScrollExceptions
        case .linearScroll: return DefaultsKey.linearScrollExceptions
        case .scrollDirection: return DefaultsKey.scrollInverterExceptions
        case .focusFollowsMouse: return DefaultsKey.focusFollowsMouseExceptions
        case .navigation: return DefaultsKey.mouseNavigationExceptions
        case .buttonShortcuts: return DefaultsKey.mouseButtonExceptions
        case .middleClick: return DefaultsKey.middleClickExceptions
        case .superKey: return DefaultsKey.superKeyExceptions
        case .selectionBar: return DefaultsKey.selectionBarExceptions
        }
    }

    /// The feature the list belongs to, so a list is only ever consulted (and
    /// only ever shown) while its feature is installed and on.
    var feature: AppFeature {
        switch self {
        case .smoothScroll: return .smoothScroll
        case .linearScroll: return .linearScroll
        case .scrollDirection: return .scrollInverter
        case .focusFollowsMouse: return .focusFollowsMouse
        case .navigation: return .mouseNavigation
        case .buttonShortcuts: return .mouseButtonShortcuts
        case .middleClick: return .middleClick
        case .superKey: return .superKey
        case .selectionBar: return .selectionBar
        }
    }
}

/// The pure half of the mouse exceptions: which window answers for the app
/// being used, and how long an answer may be reused before the window server
/// is asked again.
enum MouseAppExceptionSupport {
    /// One on-screen window, reduced to what the decision needs.
    struct Window: Equatable {
        let frame: CGRect
        let layer: Int
        let alpha: Double
        let processID: Int32
        let number: CGWindowID

        init(frame: CGRect, layer: Int, alpha: Double = 1, processID: Int32, number: CGWindowID = 0) {
            self.frame = frame
            self.layer = layer
            self.alpha = alpha
            self.processID = processID
            self.number = number
        }
    }

    static func windows(from descriptions: [[String: Any]]) -> [Window] {
        descriptions.compactMap { info in
            guard let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (raw["X"] as? NSNumber)?.doubleValue,
                  let y = (raw["Y"] as? NSNumber)?.doubleValue,
                  let width = (raw["Width"] as? NSNumber)?.doubleValue,
                  let height = (raw["Height"] as? NSNumber)?.doubleValue,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            else { return nil }
            return Window(frame: CGRect(x: x, y: y, width: width, height: height),
                          layer: layer,
                          alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                          processID: pid,
                          number: (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    /// Ordinary windows sit at layer 0 and an app's floating panels at 3;
    /// both belong to the app the user is working in. Below that are windows
    /// that live under every real one, so they never get the wheel while an
    /// app window is there to take it. Above it sit the system's furniture
    /// (Dock, menu bar, notifications) and overlays such as menus, whose
    /// windows can span more than they take, so a rectangle alone cannot tell
    /// where they take events: such a window answers only where the window
    /// server hands it the event (`pointerSurface`).
    static let appWindowLayers = 0...3

    /// How long a resolved window keeps answering without asking the window
    /// server again. Measured on this Mac: the window list costs about 190 us
    /// and each hit test about 0.1 ms, while re-checking the rectangle a
    /// lookup produced costs about 2 ns, so a wheel spinning inside a single
    /// window pays the lookup twice a second instead of on every event.
    static let resolveLifetime: TimeInterval = 0.5

    /// The window a click or a wheel would reach at `point`. The list arrives
    /// front to back, so the first window containing the point wins; the
    /// app's own windows are skipped because its panels sit above whatever
    /// the pointer is really over.
    static func pointerWindow(in windows: [Window],
                              at point: CGPoint,
                              ownProcessID: Int32) -> Window? {
        windows.first { window in
            window.alpha > 0
                && appWindowLayers.contains(window.layer)
                && window.processID != ownProcessID
                && window.frame.contains(point)
        }
    }

    /// The surface that takes the event at the pointer, when one does:
    /// another process's window above the app band that the window server
    /// hands the click or the wheel to, such as a menu, a banner or
    /// Launchpad. It answers instead of the app window it covers, which gets
    /// nothing. Launchpad is the case people meet: the Dock draws it over
    /// every app window, and the layer rule in `pointerWindow` named the app
    /// hidden behind it (issue #3135). The window server's own hit test
    /// decides which window that is, not a rectangle, since the Dock's window
    /// spans the whole screen and lets everything outside the Dock through. A
    /// window of this app is never a surface, as above.
    static func pointerSurface(in windows: [Window],
                               receivingWindowID: CGWindowID?,
                               ownProcessID: Int32) -> Window? {
        guard let receivingWindowID, receivingWindowID != 0 else { return nil }
        return windows.first { window in
            window.number == receivingWindowID
                && window.layer > appWindowLayers.upperBound
                && window.processID != ownProcessID
        }
    }

    static let dockBundleID = "com.apple.dock"
    /// Launchpad.app only asks the Dock to show the grid, which the Dock
    /// draws itself, so a listed Launchpad stands for every Dock surface: the
    /// grid, and also the Dock's bar, its stacks and anything else it draws.
    /// The grid's layer could tell it apart, but that layer has been measured
    /// on one macOS version only.
    static let launchpadBundleID = "com.apple.launchpad.launcher"

    /// What a surface answers to: its owner, plus Launchpad for the Dock.
    static func surfaceIdentities(_ ownerIdentities: [String]) -> [String] {
        ownerIdentities.contains(dockBundleID) ? ownerIdentities + [launchpadBundleID] : ownerIdentities
    }

    /// Whether the previous answer still applies. A window answers while the
    /// pointer stays inside it; "no window here" only applies while the
    /// pointer has not moved at all, so a wheel over the desktop cannot pin a
    /// stale verdict to the whole screen. Both expire with `resolveLifetime`,
    /// which is what picks up a window that opened, closed or moved under a
    /// resting pointer.
    static func cacheHolds(region: CGRect?,
                           resolvedPoint: CGPoint,
                           resolvedAt: TimeInterval,
                           point: CGPoint,
                           now: TimeInterval) -> Bool {
        guard now >= resolvedAt, now - resolvedAt < resolveLifetime else { return false }
        guard region != nil else { return point == resolvedPoint }
        return cacheNamesWindow(region: region, point: point)
    }

    /// Whether an answer that aged out still names the window under the
    /// pointer. The pointer thread serves that one instead of waiting for the
    /// main thread; over any other window it has nothing to say yet.
    static func cacheNamesWindow(region: CGRect?, point: CGPoint) -> Bool {
        guard let region else { return false }
        return region.contains(point)
    }

    static func isExcepted(_ bundleID: String?, exceptions: Set<String>) -> Bool {
        guard let bundleID, !exceptions.isEmpty else { return false }
        return exceptions.contains(bundleID)
    }

    /// A program that is not packaged as an app can have no bundle identifier
    /// at all — the Java process a game launcher starts is the one people ask
    /// about (issue #1009) — so the path of the file being run stands in as
    /// its identity. A stored path is told apart from a bundle identifier by
    /// its leading slash, which a bundle identifier never has, so one list
    /// carries both kinds and everything already saved keeps its meaning.
    static func isExecutablePathIdentity(_ identity: String) -> Bool {
        identity.hasPrefix("/")
    }

    /// The one spelling a path identity is stored and matched by. The file
    /// sheet hands back the name the user browsed while a running program
    /// reports the name it was started under, and the same file reaches the
    /// two ends under different names whenever anything on the way is a link:
    /// measured on this Mac, the sheet answers /private/tmp/… where the
    /// running program answers /tmp/… for one file. Both ends resolve, so
    /// they meet. A relative path is nothing to resolve against and is no
    /// identity at all.
    static func executablePathIdentity(_ path: String?) -> String? {
        guard let path, isExecutablePathIdentity(path) else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// The one identity a running program is listed by when it is picked from
    /// the programs that are open: its bundle identifier when it has one, and
    /// the file being run when it does not. Matching asks `identities`, which
    /// also counts a listed path.
    static func identity(bundleID: String?, executablePath: @autoclosure () -> String?) -> String? {
        bundleID ?? executablePathIdentity(executablePath())
    }

    /// Everything a running program answers to on a list: its bundle
    /// identifier when it has one, and the file being run while a list names a
    /// program by its path. Java's launcher carries an Info.plist of its own,
    /// and a JVM reports its identifier once AWT registers the app, the same
    /// one for every Java program that runtime runs (measured on this Mac:
    /// net.java.openjdk.java for an AWT program on Temurin 25). A JVM started
    /// with -XstartOnFirstThread, as Minecraft 1.13 and later is on macOS,
    /// skips that registration and reports none. A runtime picked by its path
    /// (issue #1009) is told apart by that path alone. The path is not even
    /// looked at while no list names one: this runs under the event taps.
    static func identities(bundleID: String?,
                           executablePath: @autoclosure () -> String?,
                           readsPath: Bool) -> [String] {
        var identities = bundleID.map { [$0] } ?? []
        if readsPath, let path = executablePathIdentity(executablePath()) {
            identities.append(path)
        }
        return identities
    }

    /// What a picked file will be reported as once it runs, which is what the
    /// picker has to store. A file sheet can be walked into a bundle, and the
    /// binary at Contents/MacOS is reported by its bundle identifier rather
    /// than by its path, so storing the file there would match nothing.
    ///
    /// Only the bundle's OWN executable counts, which is the same rule the
    /// system applies: measured on this Mac, a bundle's main executable run
    /// straight from disk is reported as com.example.withid, while a runtime
    /// shipped deeper in that same bundle — the Java a game launcher starts
    /// (issue #1009) — is reported with no identifier at all and stays a path.
    /// Walking up to any enclosing .app when storing would file that Java
    /// under the launcher and break the case this all exists for — a rule
    /// about the picked identity only: the source scope walks up on purpose
    /// (sourceBundleIdentifiers), so a helper inherits the exception of the
    /// app it shipped inside.
    static func pickedIdentity(for url: URL) -> String? {
        // Pointed at the bundle: its identifier, or the binary it runs when
        // the Info.plist names none, which is what the system reports for it.
        if let bundle = Bundle(url: url) {
            return bundle.bundleIdentifier ?? executablePathIdentity(bundle.executableURL?.path)
        }
        // Walked inside one: only the bundle's own executable is reported by
        // the identifier, so anything deeper keeps its own path.
        let picked = executablePathIdentity(url.path)
        var candidate = url.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let bundle = Bundle(url: candidate),
               executablePathIdentity(bundle.executableURL?.path) == picked {
                return bundle.bundleIdentifier ?? picked
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            candidate = parent
        }
        return picked
    }

    static func sourceProcessID(_ rawValue: Int64) -> Int32? {
        guard rawValue > 0 else { return nil }
        return Int32(exactly: rawValue)
    }

    static func isExcepted(_ bundleIDs: [String], exceptions: Set<String>) -> Bool {
        bundleIDs.contains(where: exceptions.contains)
    }
}
