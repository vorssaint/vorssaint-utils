// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum WindowFocusHistoryTests {
    static func run(expect: (Bool, String) -> Void) {
        checkUnlistedFocus(expect: expect)
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
        expect(history.focusedWindowID(for: 1) == nil && history.focusedWindowID(for: 2) == nil,
               "late focus from the previous app cannot identify the current shortcut's source")
        expect(history.focus(20, for: b) && windows(history) == [20, 11, 30, 10],
               "B resolving its window retains the unresolved activation of A")
        expect(history.focusedWindowID(for: 2) == 20,
               "the current activation reports its focused window before the inventory lists it")
        let againA = history.activate(1)!
        expect(!history.focus(10, for: a), "returning to the same PID does not accept its old request")
        expect(history.focus(11, for: againA) && windows(history) == [11, 20, 30, 10],
               "confirmed focus chooses the actual window instead of the fallback representative")
        expect(history.focus(10, for: againA) && windows(history) == [10, 11, 20, 30],
               "focus changes within one app retain global window recency")

        history.switched(to: 11, pid: 1, previous: 10)
        expect(!history.focus(10, for: againA) && windows(history) == [11, 10, 20, 30],
               "explicit switch rejects a source AX read already in flight")
        let afterSwitch = history.current!
        expect(history.focus(10, for: afterSwitch) && windows(history) == [10, 11, 20, 30],
               "same-app focus observation continues after an explicit switch")
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

    private static func checkUnlistedFocus(expect: (Bool, String) -> Void) {
        let entries = [10, 11, 12].map { WindowUseOrder.Entry(windowID: UInt32($0), pid: 1) }
        var history = WindowFocusHistory()
        let earlierApp = history.activate(2)!
        let request = history.activate(1)!
        history.focus(10, for: request)
        let firstNotice = history.focusRevision
        let beforeLateFocus = history.revision
        expect(history.focus(20, for: earlierApp) && history.revision != beforeLateFocus
               && history.focusRevision == firstNotice && history.focusedWindowID(for: 1) == 10,
               "a late AX result for an earlier app does not confirm the current app's old focus")
        let beforeTermination = history.revision
        history.terminated(2)
        expect(history.revision != beforeTermination && history.focusRevision == firstNotice,
               "terminating a different app does not supersede a pending focus notification")
        guard let afterB = history.focus(11, forPID: 1, ifRevision: firstNotice),
              let afterC = history.focus(12, forPID: 1, ifRevision: afterB) else {
            expect(false, "the owner-confirmed focus notifications for B and C are accepted in order")
            return
        }
        history.reconcile(windows: [10], revision: history.revision)
        expect(history.focusedWindowID(for: 1) == 12
               && history.order(entries, baseline: [0, 1, 2]) == [2, 1, 0],
               "a capture missing B and C preserves C as source and B as the previous window")
        history.reconcile(windows: [10, 11], revision: history.revision)
        expect(history.focusedWindowID(for: 1) == 12,
               "seeing B before C cannot make the older window the current focus")
        history.removeWindow(12)
        expect(history.focusedWindowID(for: 1) == nil
               && history.order(entries, baseline: [0, 1, 2]) == [1, 0, 2],
               "explicit destruction forgets C without naming its predecessor as the current focus")
        expect(history.focus(12, forPID: 1, ifRevision: afterC) == nil,
               "a discovery started before the focused window closed cannot restore it")

        let beforeAX = history.focusRevision
        history.focus(10, for: request)
        expect(history.focus(11, forPID: 1, ifRevision: beforeAX) == nil
               && history.focusedWindowID(for: 1) == 10,
               "a delayed owner lookup cannot overwrite a newer Accessibility focus")
        let beforeRepeat = history.focusRevision
        history.focus(10, for: request)
        expect(history.focusRevision != beforeRepeat && history.focusedWindowID(for: 1) == 10,
               "a fresh focus observation can reconfirm the same front window")
        let beforeActivation = history.focusRevision
        _ = history.activate(2)
        expect(history.focus(11, forPID: 1, ifRevision: beforeActivation) == nil
               && history.focusedWindowID(for: 1) == nil,
               "leaving an app invalidates outstanding focus confirmations")
    }
}
