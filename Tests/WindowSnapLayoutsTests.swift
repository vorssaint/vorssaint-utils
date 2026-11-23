// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The island's snap-layout picker: where it sits, what each part of it
/// means, and which desktops it offers.
enum WindowSnapLayoutsTests {
    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = WindowSnapLayoutsSupport.geometry(screen: screen, topInset: 38)

        suite.expect(WindowSnapLayoutsSupport.layouts.map(\.id)
                        == ["halves", "twoThirdsLeft", "twoThirdsRight", "thirds", "halfAndQuarters", "quarters"],
                     "the picker offers the Windows 11 set of layouts")
        suite.expect(geometry.panel.maxY == screen.maxY && abs(geometry.panel.midX - screen.midX) <= 0.5
                        && geometry.cards.allSatisfy { $0.frame.maxY <= screen.maxY - 38 },
                     "the picker hangs from the top of the screen, centred, with its layouts below the camera")
        suite.expect(geometry.cards.allSatisfy { card in
                        card.zones.allSatisfy { card.frame.contains($0.frame) }
                     } && zip(geometry.cards, geometry.cards.dropFirst()).allSatisfy { $0.frame.maxX < $1.frame.minX },
                     "each layout's parts stay inside its card, and the cards never overlap")

        let halves = geometry.cards[0]
        let left = halves.zones[0].frame, right = halves.zones[1].frame
        suite.expect(geometry.hit(at: CGPoint(x: left.midX, y: left.midY)) == .zone(layout: "halves", action: .leftHalf)
                        && geometry.hit(at: CGPoint(x: right.midX, y: right.midY)) == .zone(layout: "halves", action: .rightHalf),
                     "the part under the pointer is the place the window takes")
        suite.expect(geometry.hit(at: CGPoint(x: (left.maxX + right.minX) / 2, y: left.midY)) != nil,
                     "the seam between two parts never drops the highlight")
        suite.expect(geometry.hit(at: CGPoint(x: screen.midX, y: screen.midY)) == nil
                        && geometry.hit(at: CGPoint(x: geometry.panel.minX - 40, y: geometry.panel.midY)) == nil,
                     "away from the picker nothing is chosen")
        let quarters = geometry.cards.first { $0.layout.id == "quarters" }!
        let bottomRight = quarters.zones.first { $0.action == .bottomRight }!.frame
        suite.expect(bottomRight.midX > quarters.frame.midX && bottomRight.midY < quarters.frame.midY,
                     "a part sits where it puts the window: bottom right at the card's bottom right")

        suite.expect(WindowSnapLayoutsSupport.spaces(ordered: [1], fullscreen: [], current: 1).isEmpty
                        && WindowSnapLayoutsSupport.spaces(ordered: [1, 9], fullscreen: [9], current: 1).isEmpty,
                     "with one desktop, full-screen apps aside, no desktops are offered")
        let spaces = WindowSnapLayoutsSupport.spaces(ordered: [4, 7, 9], fullscreen: [], current: 7)
        suite.expect(spaces.map(\.number) == [1, 2, 3] && spaces.map(\.current) == [false, true, false],
                     "desktops are numbered in their order, the one showing marked")
        let withSpaces = WindowSnapLayoutsSupport.geometry(screen: screen, topInset: 38, spaces: spaces)
        let chips = withSpaces.chips
        suite.expect(chips.count == 3 && withSpaces.panel.height > geometry.panel.height
                        && chips.allSatisfy { chip in withSpaces.cards.allSatisfy { $0.frame.minY > chip.frame.maxY } },
                     "desktops sit in a row of their own under the layouts")
        suite.expect(withSpaces.hit(at: CGPoint(x: chips[0].frame.midX, y: chips[0].frame.midY)) == .space(4)
                        && withSpaces.hit(at: CGPoint(x: chips[1].frame.midX, y: chips[1].frame.midY)) == nil,
                     "another desktop takes the window; the one already showing does not")

        let narrow = WindowSnapLayoutsSupport.geometry(screen: CGRect(x: 0, y: 0, width: 520, height: 800), topInset: 24)
        suite.expect(narrow.panel.width <= 520 && narrow.panel.minX >= 0,
                     "on a narrow display the cards shrink rather than run off the screen")
    }
}
