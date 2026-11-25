// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum WindowFocusHistoryTests {
    static func run(expect: (Bool, String) -> Void) {
        typealias Entry = WindowUseOrder.Entry
        let entries = [Entry(windowID: 20, pid: 2), Entry(windowID: 10, pid: 1),
                       Entry(windowID: 30, pid: 3), Entry(windowID: 11, pid: 1)]
        // C was recorded long ago. A then B activate while AX is unavailable.
        // Enumeration appends their new windows behind C before sorting.
        let reconciled = WindowUseOrder.reconciled([30], existing: [10, 11, 20, 30],
                                                  frontToBack: [20, 10, 30, 11])
        let baseline = WindowUseOrder.order(entries, windowHistory: reconciled,
                                             appHistory: [2, 1, 3], frontToBack: [20, 10, 30, 11])
        expect(baseline.map { entries[$0].windowID } == [30, 20, 10, 11],
               "control reproduces stale window ordering before activation evidence")
        var history = WindowFocusHistory()
        let a = history.activate(1)!
        let b = history.activate(2)!
        history.reconcile(windows: [30], revision: history.revision)
        func windows(_ history: WindowFocusHistory) -> [UInt32?] {
            history.order(entries, baseline: baseline).map { entries[$0].windowID }
        }
        expect(windows(history) == [20, 10, 30, 11],
               "rapid A then B activation selects A next even when both AX reads are missing")
        expect(history.focus(11, for: a) && windows(history) == [20, 11, 30, 10],
               "a late AX response resolves A in place without displacing B")
        expect(history.frontAppFocus(for: 1).windowID == nil && history.frontAppFocus(for: 2).windowID == nil,
               "a late result for a previous app supplies no focus hint for the front app")
        expect(history.focus(20, for: b) && windows(history) == [20, 11, 30, 10],
               "B resolving its window retains the unresolved activation of A")
        let focus = history.frontAppFocus(for: 2)
        expect(focus.windowID == 20 && focus.observedWindows == [20, 11],
               "the request sees only observed windows as focus evidence, excluding the window-server seed")
        let againA = history.activate(1)!
        expect(!history.focus(10, for: a), "returning to the same PID does not accept its old request")
        expect(history.focus(11, for: againA) && windows(history) == [11, 20, 30, 10],
               "confirmed focus chooses the actual window instead of the fallback representative")
        expect(history.focus(10, for: againA) && windows(history) == [10, 11, 20, 30],
               "focus changes within one app retain global window recency")

        history.switched(to: 11, pid: 1, previous: 10, now: 1)
        expect(!history.focus(10, for: againA) && windows(history) == [11, 10, 20, 30],
               "explicit switch rejects a source AX read already in flight")
        let handoff = history.frontAppFocus(for: 1, now: 1.01)
        let afterSwitch = history.current!
        _ = history.focus(11, for: afterSwitch)
        let confirmed = history.frontAppFocus(for: 1, now: 1.02)
        let expired = history.frontAppFocus(for: 1, now: 1 + WindowFocusHistory.switchConfirmationInterval)
        expect(handoff.recentSwitch?.windowID == 11 && handoff.recentSwitch?.previousWindowID == 10
                && confirmed.recentSwitch?.windowID == 11 && confirmed.recentSwitch?.previousWindowID == 10
                && confirmed.latest?.confirmation != handoff.latest?.confirmation
                && expired.recentSwitch == nil,
               "AX reconfirming the switch target preserves the pair until its original deadline")
        expect(history.focus(10, for: afterSwitch) && windows(history) == [10, 11, 20, 30],
               "same-app focus observation continues after an explicit switch")
        expect(history.frontAppFocus(for: 1, now: 1.03).recentSwitch == nil,
               "AX observing a different window supersedes the pending switch")

        var omitting = history
        let beforeOmission = omitting.frontAppFocus(for: 1).latest
        omitting.reconcile(windows: [11, 20, 30], revision: omitting.revision)
        let omitted = omitting.frontAppFocus(for: 1)
        expect(omitted.windowID == nil && !omitted.observedWindows.contains(10)
                && omitted.latest?.windowID == 10 && omitted.latest?.confirmation == beforeOmission?.confirmation,
               "a missing focus leaves its observation available for checking an in-flight read")
        _ = omitting.focus(11, for: afterSwitch)
        _ = omitting.focus(11, for: afterSwitch)
        let returned = omitting.frontAppFocus(for: 1).latest
        expect(returned?.windowID == 11 && returned?.previousWindowID == 10
                && returned?.confirmation != omitted.latest?.confirmation,
               "returning to a source remembers its omitted predecessor even after repeated AX confirmation")
        var closing = history
        closing.beginFocusRead(for: afterSwitch)
        closing.reconcile(windows: [10], revision: closing.revision)
        closing.destroyed(10)
        var siblingRead = closing
        expect(siblingRead.finishFocusRead(11, for: afterSwitch)
                && siblingRead.frontAppFocus(for: 1).windowID == 11,
               "AX can confirm the surviving sibling even when the previous scan omitted it")
        _ = closing.focus(11, for: afterSwitch)
        expect(!closing.finishFocusRead(10, for: afterSwitch)
                && closing.frontAppFocus(for: 1).windowID == 11,
               "a late AX reply for the closed window leaves the newly focused sibling in front")

        var reading = history
        let newWindow: UInt32 = 12
        let previousFocus = reading.frontAppFocus(for: 1).latest?.confirmation
        reading.beginFocusRead(for: afterSwitch)
        reading.destroyed(newWindow)
        reading.destroyed(20)
        expect(!reading.finishFocusRead(newWindow, for: afterSwitch)
                && reading.frontAppFocus(for: 1).latest?.confirmation == previousFocus
                && !reading.frontAppFocus(for: 1).observedWindows.contains(newWindow),
               "AX cannot introduce an unknown window destroyed during the read, even after another removal")

        reading.beginFocusRead(for: afterSwitch)
        reading.destroyed(11)
        expect(reading.finishFocusRead(newWindow, for: afterSwitch)
                && reading.frontAppFocus(for: 1).latest?.previousWindowID == 10,
               "a new read can accept a reused ID when only a different window closed during that read")

        reading.beginFocusRead(for: afterSwitch)
        reading.reconcile(windows: [10], revision: reading.revision)
        expect(reading.frontAppFocus(for: 1).windowID == nil
                && reading.finishFocusRead(newWindow, for: afterSwitch)
                && reading.frontAppFocus(for: 1).windowID == newWindow,
               "AX can reconfirm a window omitted from a scan during the read")
        _ = history.activate(99, recording: false)
        expect(!history.focus(11, for: afterSwitch) && windows(history) == [10, 11, 20, 30],
               "the app's own activation handoff invalidates callbacks without changing history")

        var returning = WindowFocusHistory()
        let firstA = returning.activate(1)!
        _ = returning.focus(10, for: firstA)
        let c = returning.activate(3)!
        _ = returning.focus(30, for: c)
        let returnedA = returning.activate(1)!
        _ = returning.activate(2)
        expect(returning.focus(10, for: returnedA) && windows(returning) == [20, 10, 30, 11],
               "late focus moves a previously used window to its new activation rank")
        expect(!returning.focus(11, for: firstA),
               "a resolved older activation cannot overwrite a newer same-app activation")

        var changing = WindowFocusHistory()
        let changingA = changing.activate(1)!
        _ = changing.focus(10, for: changingA)
        _ = changing.activate(2)
        expect(changing.focus(11, for: changingA) && windows(changing) == [20, 11, 10, 30],
               "late intra-app focus uses the last confirmed rank and retains the previous window")
        changing.terminated(1)
        expect(!changing.focus(10, for: changingA),
               "termination invalidates a resolved activation's late focus")

        var explicit = WindowFocusHistory()
        let source = explicit.activate(1)!
        _ = explicit.focus(10, for: source)
        explicit.switched(to: 20, pid: 2, previous: 10)
        expect(!explicit.focus(11, for: source) && windows(explicit) == [20, 10, 30, 11],
               "cross-app explicit switches invalidate resolved source requests")

        var windowless = WindowFocusHistory()
        _ = windowless.activate(4)
        let withWindowless = entries + [Entry(windowID: nil, pid: 4)]
        expect(windowless.order(withWindowless, baseline: baseline + [4]).first == 4,
               "a recently activated windowless app keeps its activation rank")
        windowless.switched(to: nil, pid: 4, previous: 20)
        expect(windowless.order(withWindowless, baseline: baseline + [4]).prefix(2) == [4, 0],
               "switching to a windowless app keeps the source window next")
        windowless.terminated(4)
        expect(windowless.current == nil
                && windowless.order(withWindowless, baseline: baseline + [4]).first == 0,
               "termination removes activation evidence and invalidates its callbacks")

        history.reconcile(windows: [20, 30], revision: history.revision)
        expect(history.order(entries, baseline: baseline) == [0, 2, 1, 3],
               "reconciliation drops closed windows from observed focus history")
        let capturedRevision = history.revision
        let newA = history.activate(1)!
        _ = history.focus(10, for: newA)
        history.reconcile(windows: [20, 30], revision: capturedRevision)
        expect(windows(history) == [10, 20, 30, 11],
               "a snapshot captured before new focus cannot erase that focus")
        let stale = b
        history = WindowFocusHistory()
        _ = history.activate(2)
        expect(!history.focus(20, for: stale), "restart cannot accept a previous lifecycle's request")
        history = WindowFocusHistory()
        for pid in 1...300 { _ = history.activate(Int32(pid)) }
        let many = (1...300).map { Entry(windowID: UInt32($0), pid: Int32($0)) }
        let bounded = history.order(many, baseline: Array(many.indices))
        expect(bounded.count == 300 && Set(bounded).count == 300 && bounded[255] == 44 && bounded[256] == 0,
               "bounded activation history preserves all remaining entries exactly once")
        expect(history.order([], baseline: []).isEmpty, "empty window lists remain empty")
    }
}
