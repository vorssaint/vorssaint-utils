// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum AppWindowTravelSupport {
    static let minimumSize = CGSize(width: 80, height: 60)

    struct Candidate: Equatable {
        let windowID: CGWindowID
        let spaces: [UInt64]
        let size: CGSize
        let alpha: Double
        let isOrderedIn: Bool?
        let isHiddenWithApp: Bool?
        let isMinimized: Bool
        let isExcludedFromWindowCycle: Bool
        let hasParent: Bool
    }

    static func isUsable(_ candidate: Candidate, appIsHidden: Bool) -> Bool {
        let confirmedHiddenWindow = SwitcherSupport.isConfirmedHiddenAppWindow(
            appIsHidden: appIsHidden, windowSpaces: candidate.spaces,
            isHiddenWithApp: candidate.isHiddenWithApp)
        let isLive = appIsHidden ? confirmedHiddenWindow : candidate.isOrderedIn != false
        return isLive && !candidate.spaces.isEmpty
            && candidate.size.width >= minimumSize.width
            && candidate.size.height >= minimumSize.height
            && (confirmedHiddenWindow || candidate.alpha > 0)
            && !candidate.isMinimized
            && !candidate.isExcludedFromWindowCycle
            && !candidate.hasParent
    }

    static func recencyOrder(_ windows: [CGWindowID], history: [CGWindowID]) -> [CGWindowID] {
        let rank = Dictionary(history.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return windows.enumerated()
            .sorted { lhs, rhs in
                switch (rank[lhs.element], rank[rhs.element]) {
                case let (left?, right?): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    static func travelTarget(candidates: [Candidate],
                             appIsHidden: Bool,
                             visibleSpaces: Set<UInt64>) -> CGWindowID? {
        guard !visibleSpaces.isEmpty else { return nil }
        let usable = candidates.filter { isUsable($0, appIsHidden: appIsHidden) }
        guard !usable.contains(where: { $0.spaces.contains(where: visibleSpaces.contains) }) else { return nil }
        return usable.first?.windowID
    }

    static func moveDestination(windowSpaces: [UInt64],
                                destination: UInt64?,
                                visibleSpaces: Set<UInt64>,
                                fullscreenSpaces: Set<UInt64>,
                                isMinimized: Bool) -> UInt64? {
        guard let destination, !isMinimized, !windowSpaces.isEmpty, !visibleSpaces.isEmpty,
              !windowSpaces.contains(destination), !windowSpaces.contains(where: visibleSpaces.contains),
              !fullscreenSpaces.contains(destination),
              !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: windowSpaces, fullscreenSpaces: fullscreenSpaces)
        else { return nil }
        return destination
    }

    static func placement(windowFrame: CGRect, destination: CGRect) -> CGPoint? {
        guard !destination.isEmpty, !windowFrame.intersects(destination) else { return nil }
        let x = destination.midX - windowFrame.width / 2
        let y = destination.midY - windowFrame.height / 2
        return CGPoint(x: max(destination.minX, min(x, destination.maxX - windowFrame.width)),
                       y: max(destination.minY, y))
    }
}
