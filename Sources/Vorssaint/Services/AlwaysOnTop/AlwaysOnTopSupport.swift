// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// What brings a pinned window forward when the user reaches for its mirror.
enum AlwaysOnTopReveal: String, CaseIterable {
    case click, hover

    static var saved: AlwaysOnTopReveal {
        UserDefaults.standard.string(forKey: DefaultsKey.alwaysOnTopReveal)
            .flatMap(AlwaysOnTopReveal.init(rawValue:)) ?? .click
    }
}

/// How thick a line the mirror draws around itself, or none.
enum AlwaysOnTopBorder: String, CaseIterable {
    case none, thin, medium, thick

    var width: CGFloat {
        switch self {
        case .none: return 0
        case .thin: return 1
        case .medium: return 2
        case .thick: return 4
        }
    }

    static var saved: AlwaysOnTopBorder {
        UserDefaults.standard.string(forKey: DefaultsKey.alwaysOnTopBorder)
            .flatMap(AlwaysOnTopBorder.init(rawValue:)) ?? .medium
    }

    /// The chosen border colour as `#RRGGBB`, or nil to follow the system
    /// accent colour, which is also what an empty or unreadable value means.
    static func colorHex(_ raw: String?) -> String? {
        raw.flatMap(MenuBarUsageBarSupport.normalizedColorHex)
    }

    static var savedColorHex: String? {
        colorHex(UserDefaults.standard.string(forKey: DefaultsKey.alwaysOnTopBorderColor))
    }
}

/// One on-screen window as the window server lists it, front to back.
struct AlwaysOnTopWindowEntry: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    /// Window-server coordinates, top-left origin.
    let bounds: CGRect
    let alpha: Double
}

/// Whether a pinned window can be seen without help.
enum AlwaysOnTopCoverage: Equatable {
    /// Nothing sits over it on the Space being viewed: no mirror is needed.
    case clear
    /// Another window overlaps it.
    case covered
    /// It lives on a Space that is not showing.
    case offSpace
    /// Minimized, or its app is hidden: the user put it away, so the pin
    /// waits instead of mirroring it.
    case parked
}

/// Where a pin is in its life. Mirroring, waiting for a hover and handing
/// over all show the mirror; the others leave the real window to be seen.
enum AlwaysOnTopPhase: Equatable {
    case uncovered
    case mirroring
    case waitingForHover
    /// A reveal asked the real window forward; the mirror stays until that
    /// is confirmed. A peek is a hover reveal that hands focus back when the
    /// pointer leaves without a click or a keypress.
    case handingOver(peek: Bool)
    case revealed(peek: Bool)
    case parked
}

enum AlwaysOnTopEvent: Equatable {
    case coverage(AlwaysOnTopCoverage)
    case click
    case pointerEntered(onViewedSpace: Bool)
    case pointerExited
    case hoverDelayElapsed
    case handOverConfirmed
    case handOverTimedOut
    /// A click or a keypress in the real window during a peek.
    case peekInput
    case peekPointerLeft
}

enum AlwaysOnTopEffect: Equatable {
    /// Shown as soon as the capture has a frame to put in it.
    case showMirror
    case hideMirror(fade: Bool)
    case startCapture
    /// Keeps the stream running briefly, so switching straight back after a
    /// reveal does not wait for a restart, then stops it.
    case coolCapture
    case stopCapture
    case startHoverDelay
    case cancelHoverDelay
    case beginHandOver
    /// Stops waiting for the real window and gives focus back if the
    /// activation already moved it.
    case cancelHandOver
    case showNotForward
    case watchPeek
    case stopWatchingPeek
    case returnFocus
}

enum AlwaysOnTopSupport {
    /// How long a hover rests before it reveals, so a pointer crossing the
    /// pin on its way to the menu bar or the Dock does nothing.
    static let hoverDelay: TimeInterval = 0.3
    /// How long a reveal on the current Space may take before it gives up.
    static let handOverTimeout: TimeInterval = 1
    /// A reveal that first travels to another Space waits out the switch
    /// animation as well.
    static let spaceHandOverTimeout: TimeInterval = 3
    static let coolDown: TimeInterval = 2
    /// A stream that started but has not delivered a frame by now is stuck
    /// (measured: the capture service can stop delivering without an error).
    static let stallTimeout: TimeInterval = 1.5
    static let framesPerSecond = 30
    static let pollInterval: TimeInterval = 0.1
    /// A window counts as closed only after it has been missing from the
    /// window list this many checks in a row: the window server can drop a
    /// window for a moment while it is being resized.
    static let missingChecksBeforeClosed = 3

    static func reduce(_ phase: AlwaysOnTopPhase, _ event: AlwaysOnTopEvent,
                       reveal: AlwaysOnTopReveal) -> (AlwaysOnTopPhase, [AlwaysOnTopEffect]) {
        switch (phase, event) {
        // A hand-over owns the pin until it is confirmed, times out or is
        // cancelled; the activation it asked for changes coverage on the way.
        case (.handingOver, .coverage):
            return (phase, [])

        case (.uncovered, .coverage(.covered)), (.uncovered, .coverage(.offSpace)),
             (.parked, .coverage(.covered)), (.parked, .coverage(.offSpace)):
            return (.mirroring, [.startCapture, .showMirror])
        case (.revealed(let peek), .coverage(.covered)), (.revealed(let peek), .coverage(.offSpace)):
            return (.mirroring, (peek ? [.stopWatchingPeek] : []) + [.startCapture, .showMirror])

        case (.mirroring, .coverage(.clear)):
            return (.uncovered, [.hideMirror(fade: false), .stopCapture])
        case (.waitingForHover, .coverage(.clear)):
            return (.uncovered, [.cancelHoverDelay, .hideMirror(fade: false), .stopCapture])
        case (.parked, .coverage(.clear)):
            return (.uncovered, [])

        case (.parked, .coverage(.parked)):
            return (phase, [])
        case (.waitingForHover, .coverage(.parked)):
            return (.parked, [.cancelHoverDelay, .hideMirror(fade: false), .stopCapture])
        case (.revealed(let peek), .coverage(.parked)):
            return (.parked, (peek ? [.stopWatchingPeek] : []) + [.hideMirror(fade: false), .stopCapture])
        case (_, .coverage(.parked)):
            return (.parked, [.hideMirror(fade: false), .stopCapture])

        case (.mirroring, .click):
            return (.handingOver(peek: false), [.beginHandOver])
        case (.waitingForHover, .click):
            return (.handingOver(peek: false), [.cancelHoverDelay, .beginHandOver])
        // Clicking during a hover hand-over makes it a real reveal.
        case (.handingOver(peek: true), .click):
            return (.handingOver(peek: false), [])

        case (.mirroring, .pointerEntered(let onViewedSpace)):
            // Hover never travels to another Space: that takes a click.
            guard reveal == .hover, onViewedSpace else { return (phase, []) }
            return (.waitingForHover, [.startHoverDelay])
        case (.waitingForHover, .pointerExited):
            return (.mirroring, [.cancelHoverDelay])
        case (.handingOver(peek: true), .pointerExited):
            return (.mirroring, [.cancelHandOver])
        case (.waitingForHover, .hoverDelayElapsed):
            return (.handingOver(peek: true), [.beginHandOver])

        case (.handingOver(let peek), .handOverConfirmed):
            return (.revealed(peek: peek), [.hideMirror(fade: true), .coolCapture] + (peek ? [.watchPeek] : []))
        case (.handingOver, .handOverTimedOut):
            return (.mirroring, [.cancelHandOver, .showNotForward])

        case (.revealed(peek: true), .peekInput):
            return (.revealed(peek: false), [.stopWatchingPeek])
        // Focus goes back to the app the hover came from; that app covers the
        // window again, which brings the mirror back through coverage.
        case (.revealed(peek: true), .peekPointerLeft):
            return (.revealed(peek: false), [.stopWatchingPeek, .returnFocus])

        default:
            return (phase, [])
        }
    }

    /// `onScreen` is front to back. Windows from `ownPID`, from `ignoredPIDs`
    /// (the Dock keeps a transparent, screen-sized window) and at or above
    /// `systemLevel` (Dock, menu bar, alerts) are never counted as covering.
    /// Smaller windows of the pinned window's own process that sit wholly
    /// inside it (tooltips, popovers, sheets, title chips) belong to it.
    static func coverage(of windowID: CGWindowID,
                         onScreen: [AlwaysOnTopWindowEntry],
                         isParked: Bool,
                         ownPID: pid_t,
                         ignoredPIDs: Set<pid_t>,
                         systemLevel: Int) -> AlwaysOnTopCoverage {
        guard let index = onScreen.firstIndex(where: { $0.id == windowID }) else {
            return isParked ? .parked : .offSpace
        }
        let target = onScreen[index]
        for entry in onScreen[..<index] {
            guard entry.pid != ownPID, !ignoredPIDs.contains(entry.pid),
                  entry.alpha > 0.01, entry.layer >= 0, entry.layer < systemLevel else { continue }
            if entry.pid == target.pid, target.bounds.contains(entry.bounds) { continue }
            let overlap = entry.bounds.intersection(target.bounds)
            if !overlap.isNull, overlap.width >= 1, overlap.height >= 1 { return .covered }
        }
        return .clear
    }

    /// The real window is in front once its app is frontmost and either the
    /// app reports it as the focused window or nothing covers it. Either alone
    /// misses cases: a same-app child window can sit over it, and a focus
    /// report can arrive before a Space switch finishes.
    static func handOverConfirmed(frontmostPID: pid_t?,
                                  appPID: pid_t,
                                  ownerPID: pid_t,
                                  focusedWindowID: CGWindowID?,
                                  windowID: CGWindowID,
                                  coverage: AlwaysOnTopCoverage) -> Bool {
        guard let frontmostPID, frontmostPID == appPID || frontmostPID == ownerPID else { return false }
        switch coverage {
        case .clear: return true
        case .covered: return focusedWindowID == windowID
        case .offSpace, .parked: return false
        }
    }

    /// Window-server frames have a top-left origin on the primary display;
    /// AppKit frames a bottom-left one.
    static func appKitFrame(windowServerFrame frame: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    static func streamPixelSize(for frame: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (max(2, Int((frame.width * scale).rounded())), max(2, Int((frame.height * scale).rounded())))
    }
}
