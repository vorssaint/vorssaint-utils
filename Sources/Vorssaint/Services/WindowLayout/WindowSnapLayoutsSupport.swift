// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One snap layout: the screen split into the places a window can take.
struct WindowSnapLayout: Equatable, Identifiable {
    let id: String
    let zones: [WindowLayoutAction]
}

/// What the pointer is over while a window is dragged under the open picker.
enum WindowSnapLayoutsHit: Equatable {
    /// One place in one layout.
    case zone(layout: String, action: WindowLayoutAction)
    /// Another desktop on the same display.
    case space(UInt64)
}

/// A desktop the picker offers. The one already showing is drawn but takes no drop.
struct WindowSnapLayoutsSpace: Equatable {
    let id: UInt64
    let number: Int
    let current: Bool
}

/// The picker that grows out of the island while a window is dragged, laid
/// out once in screen points. The panel draws from the same rectangles the
/// drag is tested against, so what lights up is always what the drop does.
struct WindowSnapLayoutsGeometry: Equatable {
    struct Card: Equatable {
        let layout: WindowSnapLayout
        let frame: CGRect
        let zones: [(action: WindowLayoutAction, frame: CGRect)]

        static func == (lhs: Card, rhs: Card) -> Bool {
            lhs.layout == rhs.layout && lhs.frame == rhs.frame
                && lhs.zones.map(\.action) == rhs.zones.map(\.action) && lhs.zones.map(\.frame) == rhs.zones.map(\.frame)
        }
    }

    struct Chip: Equatable {
        let space: WindowSnapLayoutsSpace
        let frame: CGRect
    }

    /// The panel, in AppKit screen points. Its top is the screen's top edge.
    let panel: CGRect
    /// Below the camera housing or the menu bar, where content may go.
    let contentTop: CGFloat
    let cards: [Card]
    let chips: [Chip]

    /// The pointer is tested with a little slack, so the gaps between zones
    /// never drop a highlight while it crosses them.
    func hit(at point: CGPoint) -> WindowSnapLayoutsHit? {
        guard panel.insetBy(dx: -WindowSnapLayoutsSupport.slack, dy: -WindowSnapLayoutsSupport.slack).contains(point)
        else { return nil }
        for card in cards {
            if let zone = card.zones.first(where: { $0.frame.contains(point) }) {
                return .zone(layout: card.layout.id, action: zone.action)
            }
        }
        for card in cards where card.frame.insetBy(dx: -WindowSnapLayoutsSupport.cardGap / 2,
                                                   dy: -WindowSnapLayoutsSupport.cardGap / 2).contains(point) {
            // Between two zones of one card: the nearer zone.
            let nearest = card.zones.min { distance(point, $0.frame) < distance(point, $1.frame) }
            return nearest.map { .zone(layout: card.layout.id, action: $0.action) }
        }
        if let chip = chips.first(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(point) }), !chip.space.current {
            return .space(chip.space.id)
        }
        return nil
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

enum WindowSnapLayoutsSupport {
    /// The Windows 11 set: halves, two thirds and a third each way, thirds,
    /// a half beside two quarters, and quarters.
    static let layouts: [WindowSnapLayout] = [
        WindowSnapLayout(id: "halves", zones: [.leftHalf, .rightHalf]),
        WindowSnapLayout(id: "twoThirdsLeft", zones: [.leftTwoThirds, .rightThird]),
        WindowSnapLayout(id: "twoThirdsRight", zones: [.leftThird, .rightTwoThirds]),
        WindowSnapLayout(id: "thirds", zones: [.leftThird, .centerThird, .rightThird]),
        WindowSnapLayout(id: "halfAndQuarters", zones: [.leftHalf, .topRight, .bottomRight]),
        WindowSnapLayout(id: "quarters", zones: [.topLeft, .topRight, .bottomLeft, .bottomRight]),
    ]

    static let cardSize = CGSize(width: 92, height: 58)
    static let cardGap: CGFloat = 10
    /// Between two zones inside a card.
    static let zoneGap: CGFloat = 3
    static let padding: CGFloat = 16
    static let chipSize = CGSize(width: 74, height: 26)
    static let chipGap: CGFloat = 8
    static let rowGap: CGFloat = 12
    static let slack: CGFloat = 6

    /// Where a placement sits in a card, as fractions from the card's top left.
    static func fractions(for action: WindowLayoutAction) -> CGRect {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let rect = WindowLayoutGeometry.rect(for: action, current: screen, visibleFrame: screen)
        return CGRect(x: rect.minX / screen.width, y: (screen.maxY - rect.maxY) / screen.height,
                      width: rect.width / screen.width, height: rect.height / screen.height)
    }

    /// Desktops worth offering: none at all while there is only the one.
    static func spaces(ordered: [UInt64], fullscreen: Set<UInt64>, current: UInt64?) -> [WindowSnapLayoutsSpace] {
        let desktops = ordered.filter { !fullscreen.contains($0) }
        guard desktops.count > 1 else { return [] }
        return desktops.enumerated().map { WindowSnapLayoutsSpace(id: $1, number: $0 + 1, current: $1 == current) }
    }

    /// `screen` is the display's frame and `topInset` the height of its menu
    /// bar or camera housing, both in AppKit points.
    static func geometry(screen: CGRect, topInset: CGFloat,
                         layouts: [WindowSnapLayout] = layouts,
                         spaces: [WindowSnapLayoutsSpace] = []) -> WindowSnapLayoutsGeometry {
        let count = CGFloat(layouts.count)
        // A narrow display gets smaller cards rather than a picker wider than itself.
        let available = max(200, screen.width - 2 * 24 - 2 * padding)
        let natural = count * cardSize.width + max(0, count - 1) * cardGap
        let scale = min(1, available / max(natural, 1))
        let card = CGSize(width: (cardSize.width * scale).rounded(.down), height: (cardSize.height * scale).rounded(.down))
        let cardsWidth = count * card.width + max(0, count - 1) * cardGap
        let chipsWidth = spaces.isEmpty ? 0
            : CGFloat(spaces.count) * chipSize.width + CGFloat(spaces.count - 1) * chipGap
        let width = max(cardsWidth, min(chipsWidth, available)) + 2 * padding
        let chipsHeight = spaces.isEmpty ? 0 : rowGap + chipSize.height
        let height = topInset + padding * 0.75 + card.height + chipsHeight + padding
        let panel = CGRect(x: (screen.midX - width / 2).rounded(), y: screen.maxY - height, width: width, height: height)
        let contentTop = screen.maxY - topInset - padding * 0.75

        var cards: [WindowSnapLayoutsGeometry.Card] = []
        var x = panel.midX - cardsWidth / 2
        for layout in layouts {
            let frame = CGRect(x: x, y: contentTop - card.height, width: card.width, height: card.height)
            let zones = layout.zones.map { action -> (action: WindowLayoutAction, frame: CGRect) in
                let f = fractions(for: action)
                let rect = CGRect(x: frame.minX + f.minX * frame.width,
                                  y: frame.maxY - (f.minY + f.height) * frame.height,
                                  width: f.width * frame.width, height: f.height * frame.height)
                return (action, rect.insetBy(dx: zoneGap / 2, dy: zoneGap / 2))
            }
            cards.append(.init(layout: layout, frame: frame, zones: zones))
            x += card.width + cardGap
        }

        var chips: [WindowSnapLayoutsGeometry.Chip] = []
        if !spaces.isEmpty {
            let shown = min(chipsWidth, width - 2 * padding)
            let chipWidth = (shown - CGFloat(spaces.count - 1) * chipGap) / CGFloat(spaces.count)
            var chipX = panel.midX - shown / 2
            let chipY = contentTop - card.height - rowGap - chipSize.height
            for space in spaces {
                chips.append(.init(space: space, frame: CGRect(x: chipX, y: chipY, width: chipWidth, height: chipSize.height)))
                chipX += chipWidth + chipGap
            }
        }
        return WindowSnapLayoutsGeometry(panel: panel, contentTop: contentTop, cards: cards, chips: chips)
    }
}
