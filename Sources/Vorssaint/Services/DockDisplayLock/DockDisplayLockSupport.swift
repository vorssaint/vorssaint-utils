// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The display the Dock is held to, as stored. A display is remembered by the
/// UUID macOS derives from the monitor itself, so the choice follows it from
/// port to port; the main and built-in choices follow the role instead.
enum DockDisplayLockTarget: Equatable, Hashable {
    case main
    case builtIn
    case display(uuid: String)

    static let mainStorage = "main"
    static let builtInStorage = "builtIn"

    init(storage: String?) {
        switch storage {
        case Self.builtInStorage?: self = .builtIn
        case let uuid? where !uuid.isEmpty && uuid != Self.mainStorage: self = .display(uuid: uuid)
        default: self = .main
        }
    }

    var storageValue: String {
        switch self {
        case .main: return Self.mainStorage
        case .builtIn: return Self.builtInStorage
        case let .display(uuid): return uuid
        }
    }
}

/// One connected display, read once per change of the arrangement. Frames
/// are in global display coordinates, the ones event locations use: the
/// origin at the main display's top left corner, y growing downward.
struct DockDisplayLockDisplay: Equatable, Identifiable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: CGRect
    let isMain: Bool
    let isBuiltIn: Bool
}

/// A screen corner that has a Hot Corner action, as the Dock's
/// `wvous-*-corner` preferences read.
enum DockDisplayLockCorner: String, CaseIterable {
    case topLeft = "tl", topRight = "tr", bottomLeft = "bl", bottomRight = "br"

    var preferenceKey: String { "wvous-\(rawValue)-corner" }

    /// 0 and 1 are the two ways the preference says "no action".
    static func actions(in dockDomain: [String: Any]) -> Set<DockDisplayLockCorner> {
        Set(allCases.filter { ((dockDomain[$0.preferenceKey] as? NSNumber)?.intValue ?? 0) > 1 })
    }
}

/// The decisions behind keeping the Dock on one display, kept apart from the
/// event tap so every arrangement can be walked without real displays.
///
/// With "Displays have separate Spaces" on, macOS moves the Dock to another
/// display when the pointer pushes against that display's Dock edge. There is
/// no setting for it, so the approach is the one DockAnchor by Bradley Wyatt
/// (MIT) takes: pointer moves are held back from the Dock while they press on
/// a display the Dock should not move to. Here only the last rows along the
/// hard part of that edge are held back, a soft edge the pointer simply
/// crosses to a neighbouring display is left alone, drags are held back as
/// well as moves, and a Hot Corner keeps working.
enum DockDisplayLockSupport {
    /// How far from a Dock edge a move is held back, in points. The pointer
    /// stops at a hard edge, on its last row, so a press against the edge
    /// always reads inside this band; a pointer a little higher still reaches
    /// every app.
    static let edgeDepth: CGFloat = 2
    /// The corner square kept for Hot Corners, in points.
    static let cornerSize: CGFloat = 2
    /// Displays closer than this along an edge count as touching.
    static let adjacencyTolerance: CGFloat = 1

    // MARK: - Where the Dock belongs

    /// The display the Dock should stay on now. A chosen display that is not
    /// connected falls back to the main one for as long as it is away; the
    /// choice itself is kept, so it applies again when the display returns.
    static func anchor(for target: DockDisplayLockTarget,
                       in displays: [DockDisplayLockDisplay]) -> DockDisplayLockDisplay? {
        let main = displays.first(where: \.isMain) ?? displays.first
        switch target {
        case .main: return main
        case .builtIn: return displays.first(where: \.isBuiltIn) ?? main
        case let .display(uuid): return displays.first { $0.uuid == uuid } ?? main
        }
    }

    // MARK: - What the tap holds back

    struct Zones: Equatable {
        /// Bands along the hard Dock edges of every other display.
        var strips: [CGRect]
        /// Corner squares of those edges whose Hot Corner has an action.
        var corners: [CGRect]

        static let none = Zones(strips: [], corners: [])
        var isEmpty: Bool { strips.isEmpty }
    }

    static func zones(displays: [DockDisplayLockDisplay],
                      anchorID: CGDirectDisplayID?,
                      orientation: DockPreviewOrientation,
                      hotCorners: Set<DockDisplayLockCorner>) -> Zones {
        // One display has nowhere to move the Dock to.
        guard displays.count > 1, let anchorID, displays.contains(where: { $0.id == anchorID }) else {
            return .none
        }
        var zones = Zones.none
        for display in displays where display.id != anchorID {
            let others = displays.filter { $0.id != display.id }
            for segment in hardSegments(of: display, orientation: orientation, others: others) {
                zones.strips.append(strip(along: segment, of: display.frame, orientation: orientation))
            }
            zones.corners += cornerSquares(of: display, orientation: orientation, others: others,
                                           hotCorners: hotCorners)
        }
        return zones
    }

    /// Whether a pointer at `point` is held back from the Dock. The first move
    /// into a Hot Corner square goes through so the corner fires; the moves
    /// after it, which would press on the edge, are held back until the
    /// pointer leaves the square. `inCorner` carries that between moves.
    static func blocks(_ point: CGPoint, zones: Zones, inCorner: inout Bool) -> Bool {
        if zones.corners.contains(where: { $0.contains(point) }) {
            defer { inCorner = true }
            return inCorner
        }
        inCorner = false
        return zones.strips.contains { $0.contains(point) }
    }

    /// The parts of a display's Dock edge with no display beyond them, as
    /// ranges along the edge. Where another display touches that edge the
    /// pointer crosses over instead of pressing, so the Dock cannot be called
    /// there and nothing needs holding back.
    static func hardSegments(of display: DockDisplayLockDisplay,
                             orientation: DockPreviewOrientation,
                             others: [DockDisplayLockDisplay]) -> [ClosedRange<CGFloat>] {
        let frame = display.frame
        let edge: ClosedRange<CGFloat>
        let neighbours: [ClosedRange<CGFloat>]
        switch orientation {
        case .bottom:
            edge = frame.minX...frame.maxX
            neighbours = others.filter { abs($0.frame.minY - frame.maxY) <= adjacencyTolerance }
                .map { $0.frame.minX...$0.frame.maxX }
        case .left:
            edge = frame.minY...frame.maxY
            neighbours = others.filter { abs($0.frame.maxX - frame.minX) <= adjacencyTolerance }
                .map { $0.frame.minY...$0.frame.maxY }
        case .right:
            edge = frame.minY...frame.maxY
            neighbours = others.filter { abs($0.frame.minX - frame.maxX) <= adjacencyTolerance }
                .map { $0.frame.minY...$0.frame.maxY }
        }
        return subtract(neighbours, from: edge)
    }

    static func subtract(_ ranges: [ClosedRange<CGFloat>],
                         from whole: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        var remaining = [whole]
        for cut in ranges {
            remaining = remaining.flatMap { piece -> [ClosedRange<CGFloat>] in
                guard cut.lowerBound < piece.upperBound, cut.upperBound > piece.lowerBound else { return [piece] }
                var kept: [ClosedRange<CGFloat>] = []
                if cut.lowerBound > piece.lowerBound { kept.append(piece.lowerBound...cut.lowerBound) }
                if cut.upperBound < piece.upperBound { kept.append(cut.upperBound...piece.upperBound) }
                return kept
            }
        }
        return remaining.filter { $0.upperBound > $0.lowerBound }
    }

    /// The band along one hard segment. It reaches one point past the edge,
    /// where no display lies, so a pointer reported exactly on the edge line
    /// still falls inside.
    static func strip(along segment: ClosedRange<CGFloat>, of frame: CGRect,
                      orientation: DockPreviewOrientation) -> CGRect {
        let length = segment.upperBound - segment.lowerBound
        switch orientation {
        case .bottom:
            return CGRect(x: segment.lowerBound, y: frame.maxY - edgeDepth, width: length, height: edgeDepth + 1)
        case .left:
            return CGRect(x: frame.minX - 1, y: segment.lowerBound, width: edgeDepth + 1, height: length)
        case .right:
            return CGRect(x: frame.maxX - edgeDepth, y: segment.lowerBound, width: edgeDepth + 1, height: length)
        }
    }

    /// The two ends of the Dock edge that are real screen corners, where the
    /// pointer stops in both directions, and that have a Hot Corner action.
    static func cornerSquares(of display: DockDisplayLockDisplay,
                              orientation: DockPreviewOrientation,
                              others: [DockDisplayLockDisplay],
                              hotCorners: Set<DockDisplayLockCorner>) -> [CGRect] {
        let frame = display.frame
        let ends: [DockDisplayLockCorner]
        switch orientation {
        case .bottom: ends = [.bottomLeft, .bottomRight]
        case .left: ends = [.topLeft, .bottomLeft]
        case .right: ends = [.topRight, .bottomRight]
        }
        return ends.compactMap { corner in
            guard hotCorners.contains(corner) else { return nil }
            let left = corner == .topLeft || corner == .bottomLeft
            let top = corner == .topLeft || corner == .topRight
            let x = left ? frame.minX : frame.maxX - cornerSize
            let y = top ? frame.minY : frame.maxY - cornerSize
            // Just past the corner on each side: another display there means
            // the pointer slides on instead of stopping in the corner.
            let beyondSide = CGPoint(x: left ? frame.minX - 0.5 : frame.maxX + 0.5, y: y + cornerSize / 2)
            let beyondEnd = CGPoint(x: x + cornerSize / 2, y: top ? frame.minY - 0.5 : frame.maxY + 0.5)
            guard !others.contains(where: { $0.frame.contains(beyondSide) || $0.frame.contains(beyondEnd) })
            else { return nil }
            return CGRect(x: left ? x - 1 : x, y: top ? y - 1 : y, width: cornerSize + 1, height: cornerSize + 1)
        }
    }

    // MARK: - Where the Dock is

    /// The display the Dock sits on, from the frame of its icon list. The
    /// list's short-axis position can be reported off by tens of points
    /// (seen on macOS 27), so the display is picked along the long axis and
    /// then by the nearest Dock edge.
    static func display(holdingDockFrame dockFrame: CGRect,
                        orientation: DockPreviewOrientation,
                        displays: [DockDisplayLockDisplay]) -> CGDirectDisplayID? {
        guard !dockFrame.isEmpty else { return nil }
        switch orientation {
        case .bottom:
            return displays.filter { $0.frame.minX <= dockFrame.midX && dockFrame.midX < $0.frame.maxX }
                .min { abs($0.frame.maxY - dockFrame.maxY) < abs($1.frame.maxY - dockFrame.maxY) }?.id
        case .left:
            return displays.filter { $0.frame.minY <= dockFrame.midY && dockFrame.midY < $0.frame.maxY }
                .min { abs($0.frame.minX - dockFrame.minX) < abs($1.frame.minX - dockFrame.minX) }?.id
        case .right:
            return displays.filter { $0.frame.minY <= dockFrame.midY && dockFrame.midY < $0.frame.maxY }
                .min { abs($0.frame.maxX - dockFrame.maxX) < abs($1.frame.maxX - dockFrame.maxX) }?.id
        }
    }

    // MARK: - Calling the Dock over

    /// The pointer path that calls the Dock to `display`: a short approach
    /// toward the middle of its Dock edge, then a few presses against it,
    /// each with the push into the edge macOS reads as a request.
    struct Step: Equatable {
        let point: CGPoint
        let delta: CGVector
    }

    static func summonPath(to display: DockDisplayLockDisplay,
                           orientation: DockPreviewOrientation) -> [Step] {
        let frame = display.frame
        let edge: CGPoint
        let inward: CGVector
        switch orientation {
        case .bottom:
            edge = CGPoint(x: frame.midX, y: frame.maxY - 1)
            inward = CGVector(dx: 0, dy: 1)
        case .left:
            edge = CGPoint(x: frame.minX, y: frame.midY)
            inward = CGVector(dx: -1, dy: 0)
        case .right:
            edge = CGPoint(x: frame.maxX - 1, y: frame.midY)
            inward = CGVector(dx: 1, dy: 0)
        }
        let approachLength: CGFloat = 40
        let approachSteps = 8
        let approach = (0..<approachSteps).map { index -> Step in
            let remaining = approachLength * CGFloat(approachSteps - 1 - index) / CGFloat(approachSteps - 1)
            let point = CGPoint(x: edge.x - inward.dx * remaining, y: edge.y - inward.dy * remaining)
            let step = approachLength / CGFloat(approachSteps - 1)
            return Step(point: point, delta: CGVector(dx: inward.dx * step, dy: inward.dy * step))
        }
        let presses = Array(repeating: Step(point: edge, delta: CGVector(dx: inward.dx * 4, dy: inward.dy * 4)),
                            count: 10)
        return approach + presses
    }
}
