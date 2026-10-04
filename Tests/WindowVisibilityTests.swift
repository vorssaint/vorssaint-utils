// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum WindowVisibilityTests {
    private final class Window: NSWindow {
        var shown = true
        var exposed = true
        override var isVisible: Bool { shown }
        override var occlusionState: NSWindow.OcclusionState { exposed ? [.visible] : [] }
        func notifyVisibility() {
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        let window = Window(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.frame)
        window.contentView = container
        let view = WindowVisibilityView(frame: container.bounds)
        var changes: [Bool] = []
        view.onChange = { changes.append($0) }
        // A fixed 10 ms delay can expire before the main queue runs on a busy
        // CI runner. Drain the work queued by the visibility change instead.
        func flush() {
            var drained = false
            DispatchQueue.main.async { drained = true }
            let deadline = Date().addingTimeInterval(1)
            while !drained && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            expect(drained, "visibility callbacks finish on the main queue")
        }
        view.reportVisibility()
        flush()
        expect(changes == [false], "unattached previews are suspended")
        container.addSubview(view)
        expect(changes == [false], "visibility never changes SwiftUI state during attachment")
        flush()
        expect(changes == [false, true], "visible windows activate their live preview")
        view.reportVisibility()
        window.notifyVisibility()
        flush()
        expect(changes.count == 2, "unchanged visibility does not rebuild the preview")
        window.shown = false
        window.notifyVisibility()
        flush()
        expect(changes.last == false, "closing a retained Settings window suspends its preview")
        window.shown = true
        window.notifyVisibility()
        flush()
        expect(changes.last == true, "reopening Settings restores its preview")
        window.exposed = false
        window.notifyVisibility()
        flush()
        expect(changes.last == false, "fully covered windows suspend live previews")
        window.exposed = true
        window.notifyVisibility()
        flush()
        expect(changes.last == true, "uncovering a window restores its preview")
        container.isHidden = true
        flush()
        expect(changes.last == false, "hidden ancestor views suspend live previews")
        container.isHidden = false
        flush()
        expect(changes.last == true, "unhidden ancestor views restore live previews")
        view.removeFromSuperview()
        flush()
        expect(changes.last == false, "removed previews stop their live work")
        let count = changes.count
        container.addSubview(view)
        view.stop()
        window.notifyVisibility()
        flush()
        expect(changes.count == count, "dismantling cancels queued visibility callbacks")
        view.removeFromSuperview()
        weak var released: WindowVisibilityView?
        autoreleasepool {
            let transient = WindowVisibilityView(frame: .zero)
            released = transient
            container.addSubview(transient)
            transient.removeFromSuperview()
        }
        expect(released == nil, "visibility observers and queued work do not retain removed previews")
    }
}
