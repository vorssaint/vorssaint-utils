// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowStickyEdgeTests {
    static func run(expect: (Bool, String) -> Void) {
        typealias S = WindowStickyEdgeSupport
        let left = CGRect(x: 0, y: 0, width: 500, height: 800)
        let right = CGRect(x: 500, y: 0, width: 500, height: 800)
        expect(S.sharedEdge(of: left, with: right) == .right, "left half touches the right half on its right edge")
        expect(S.sharedEdge(of: right, with: left) == .left, "right half touches the left half on its left edge")
        expect(S.sharedEdge(of: CGRect(x: 0, y: 0, width: 1000, height: 400),
                            with: CGRect(x: 0, y: 400, width: 1000, height: 400)) == .bottom,
               "top half touches the bottom half on its bottom edge")
        expect(S.sharedEdge(of: CGRect(x: 0, y: 400, width: 1000, height: 400),
                            with: CGRect(x: 0, y: 0, width: 1000, height: 400)) == .top,
               "bottom half touches the top half on its top edge")
        expect(S.sharedEdge(of: left, with: CGRect(x: 503, y: 0, width: 497, height: 800)) == .right,
               "a gap within the tolerance still counts")
        expect(S.sharedEdge(of: left, with: CGRect(x: 497, y: 0, width: 503, height: 800)) == .right,
               "an overlap within the tolerance still counts")
        expect(S.sharedEdge(of: left, with: CGRect(x: 510, y: 0, width: 490, height: 800)) == nil,
               "a gap beyond the tolerance does not count")
        expect(S.sharedEdge(of: left, with: CGRect(x: 508, y: 0, width: 492, height: 800), tolerance: 12) == .right,
               "the layout window gap widens the tolerance so gapped windows still pair")
        expect(S.sharedEdge(of: left, with: CGRect(x: 500, y: 790, width: 500, height: 400)) == nil,
               "corner contact without real overlap does not count")
        expect(S.sharedEdge(of: left, with: CGRect(x: 500, y: 200, width: 500, height: 300)) == .right,
               "a shorter neighbour on the same edge counts")
        expect(S.sharedEdge(of: left, with: .zero) == nil, "an empty frame never counts")
        expect(S.sharedEdge(of: left, with: left) == nil, "identical frames share no edge")

        let dragged = CGRect(x: 0, y: 0, width: 600, height: 800)
        expect(S.followerFrame(edge: .right, old: left, new: dragged, follower: right)
               == .follow(CGRect(x: 600, y: 0, width: 400, height: 800)),
               "dragging the right edge outward shrinks the right neighbour")
        expect(S.followerFrame(edge: .right, old: left, new: CGRect(x: 0, y: 0, width: 300, height: 800), follower: right)
               == .follow(CGRect(x: 300, y: 0, width: 700, height: 800)),
               "dragging the right edge inward grows the right neighbour")
        expect(S.followerFrame(edge: .left, old: right, new: CGRect(x: 400, y: 0, width: 600, height: 800), follower: left)
               == .follow(CGRect(x: 0, y: 0, width: 400, height: 800)),
               "dragging the left edge shrinks the left neighbour")
        expect(S.followerFrame(edge: .bottom, old: CGRect(x: 0, y: 0, width: 1000, height: 400),
                               new: CGRect(x: 0, y: 0, width: 1000, height: 500),
                               follower: CGRect(x: 0, y: 400, width: 1000, height: 400))
               == .follow(CGRect(x: 0, y: 500, width: 1000, height: 300)),
               "dragging the bottom edge shrinks the lower neighbour")
        expect(S.followerFrame(edge: .top, old: CGRect(x: 0, y: 400, width: 1000, height: 400),
                               new: CGRect(x: 0, y: 300, width: 1000, height: 500),
                               follower: CGRect(x: 0, y: 0, width: 1000, height: 400))
               == .follow(CGRect(x: 0, y: 0, width: 1000, height: 300)),
               "dragging the top edge up shrinks the upper neighbour")
        expect(S.followerFrame(edge: .right, old: left, new: left.offsetBy(dx: 50, dy: 0), follower: right) == .unaffected,
               "moving the whole window leaves the neighbour alone")
        expect(S.followerFrame(edge: .right, old: left, new: CGRect(x: 0, y: 0, width: 500, height: 700), follower: right) == .unaffected,
               "resizing another edge leaves the neighbour alone")
        expect(S.followerFrame(edge: .right, old: left, new: CGRect(x: 100, y: 0, width: 400, height: 800), follower: right) == .unaffected,
               "resizing the opposite edge leaves the neighbour alone")
        expect(S.followerFrame(edge: .right, old: left, new: left, follower: right) == .unaffected,
               "no movement of the shared edge gives no follower frame")
        expect(S.followerFrame(edge: .right, old: left, new: CGRect(x: 0, y: 0, width: 950, height: 800), follower: right)
               == .tooSmall,
               "a follower that would drop below the minimum size stays untouched")
        expect(S.followerFrame(edge: .right, old: left, new: CGRect(x: 0, y: 0, width: 920, height: 800), follower: right)
               == .follow(CGRect(x: 920, y: 0, width: 80, height: 800)),
               "a follower exactly at the minimum size is still allowed")
        // A gap between the two stays what it was.
        let gapped = CGRect(x: 508, y: 0, width: 492, height: 800)
        expect(S.followerFrame(edge: .right, old: left, new: dragged, follower: gapped)
               == .follow(CGRect(x: 608, y: 0, width: 392, height: 800)),
               "the gap between neighbours is preserved while following")

        // Three windows in a row: only the facing neighbour is coupled.
        let a = CGRect(x: 0, y: 0, width: 400, height: 800)
        let b = CGRect(x: 400, y: 0, width: 300, height: 800)
        let c = CGRect(x: 700, y: 0, width: 300, height: 800)
        expect(S.sharedEdge(of: a, with: c) == nil, "the far window of a row of three is not a neighbour")
        expect(S.sharedEdge(of: b, with: c) == .right && S.sharedEdge(of: b, with: a) == .left,
               "the middle window touches both outer windows")
        if case .follow(let moved) = S.followerFrame(edge: .right, old: a, new: CGRect(x: 0, y: 0, width: 450, height: 800), follower: b) {
            expect(moved == CGRect(x: 450, y: 0, width: 250, height: 800) && moved.maxX == b.maxX,
                   "the middle follower keeps its far edge, so the third window stays untouched")
        } else {
            expect(false, "the middle follower keeps its far edge, so the third window stays untouched")
        }
        // Resizing the middle window at its right edge leaves its left neighbour alone.
        let middleGrown = CGRect(x: 400, y: 0, width: 350, height: 800)
        expect(S.followerFrame(edge: .left, old: b, new: middleGrown, follower: a) == .unaffected,
               "the left neighbour ignores a change of the middle window's right edge")
        expect(S.sharedEdge(of: left, with: CGRect(x: 500, y: -100, width: 500, height: 600)) == .right,
               "a neighbour offset vertically but overlapping couples")

        // A drag is a move, a resize is not; a moved window leaves the layout.
        expect(S.isPureMove(old: left, new: left.offsetBy(dx: 30, dy: 0)), "a drag is a pure move")
        expect(!S.isPureMove(old: left, new: dragged), "a resize at one edge is not a move")
        expect(!S.isPureMove(old: left, new: CGRect(x: 100, y: 0, width: 400, height: 800)),
               "a resize at the leading edge changes the size, so it is not a move")
        expect(!S.isPureMove(old: left, new: left), "an unchanged frame is not a move")

        // Displays: windows on different displays never pair.
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        expect(S.shareDisplay(left, right, displays: displays), "two windows on one display share it")
        expect(!S.shareDisplay(CGRect(x: 600, y: 0, width: 400, height: 800),
                               CGRect(x: 1000, y: 0, width: 400, height: 800), displays: displays),
               "windows on two displays do not share one")
        expect(S.shareDisplay(left, right, displays: []), "without display information coupling is not disabled")

        // Setting: off by default, part of the registered defaults (and so the backup).
        expect(Defaults.registeredDefaults[DefaultsKey.windowStickySnapEnabled] as? Bool == false,
               "sticky snapping is off by default")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.windowStickySnapEnabled),
               "sticky snapping takes part in the settings backup")
    }
}
