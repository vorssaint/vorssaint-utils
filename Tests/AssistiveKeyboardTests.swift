// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

func assistiveKeyboardChecks(_ expect: (Bool, String) -> Void) {
    let point = CGPoint(x: 100, y: 200)
    func window(_ owner: pid_t, alpha: CGFloat = 1,
                bounds: CGRect = CGRect(x: 0, y: 100, width: 400, height: 300)) -> [String: Any] {
        [kCGWindowOwnerPID as String: owner,
         kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: ["X": bounds.minX, "Y": bounds.minY,
                                    "Width": bounds.width, "Height": bounds.height]]
    }
    var pid: pid_t?
    var windows = [window(200)]
    var processReads = 0
    var windowReads = 0
    func click(_ at: CGPoint = CGPoint(x: 100, y: 200)) -> Bool {
        AssistiveKeyboard.ownsPoint(at, keyboardPID: {
            processReads += 1
            return pid
        }, windows: {
            windowReads += 1
            return windows
        })
    }

    expect(!click() && windowReads == 0, "an absent keyboard does not enumerate windows")
    pid = 200
    expect(click(), "the first key works immediately after an absent lookup, without a warm-up or retry")
    expect(processReads == 2 && windowReads == 1, "each click uses current process identity before reading windows")
    expect(!click(CGPoint(x: 800, y: 200)), "an ordinary outside click still dismisses")

    // A restart can happen between two clicks. Neither a cached absence nor a
    // cached positive identity may decide what the later click belongs to.
    pid = nil
    let scansBeforeExit = windowReads
    expect(!click() && windowReads == scansBeforeExit, "keyboard exit is recognized on the next click")
    pid = 201
    expect(!click(), "a window from the previous keyboard process cannot keep a panel open")
    windows = [window(201)]
    expect(click(), "the first key after a keyboard restart needs no second attempt")
    pid = 200
    windows = [window(300), window(200)]
    expect(!click(), "another app above the keyboard still receives an outside click")
    windows = [window(300, alpha: 0), window(200)]
    expect(click(), "a transparent overlay does not hide keyboard input")
    windows = [window(ProcessInfo.processInfo.processIdentifier), window(200)]
    expect(click(), "existing own-process click-through overlays remain transparent to keyboard recognition")
    windows = [window(300, bounds: CGRect(x: 900, y: 800, width: 20, height: 20)), window(200)]
    expect(click(), "unrelated windows away from the click do not block the keyboard")
    windows = []
    expect(!click(), "an empty window list does not claim a keyboard click")
    expect(!AssistiveKeyboard.ownsPoint(point, keyboardPID: { 200 }, windows: { nil }),
           "an unavailable window list does not claim a keyboard click")
    windows = [[kCGWindowOwnerPID as String: pid_t(200)]]
    expect(!click(), "missing bounds cannot identify the clicked keyboard")
    windows = [window(200, bounds: CGRect(x: -500, y: -600, width: 400, height: 300))]
    expect(click(CGPoint(x: -400, y: -500)), "keyboard coordinates can be negative on another display")
}
