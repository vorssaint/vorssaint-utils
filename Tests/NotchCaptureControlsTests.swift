// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension NotchPresentationRefreshContract {
    /// Production presentation and timer bodies, with an inert window and clock.
    /// Pointer locations are values only; no events or windows reach the desktop.
    static func captureControlsChecks(expect: (Bool, String) -> Void) {
        DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
        NSEvent.mouseLocation = .zero
        defer {
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            NSEvent.mouseLocation = .zero
        }
        func begin() -> Service {
            let service = Service()
            service.expanded = false
            service.captureControls = CaptureOptions()
            service.refreshPresentation(animated: false)
            service.updateCaptureControlsClickThrough()
            service.scheduleCaptureControlsCollapse()
            return service
        }
        func move(_ service: Service, inside: Bool) {
            NSEvent.mouseLocation = inside
                ? CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY - 1)
                : .zero
            service.updateCaptureControlsClickThrough()
        }

        let idle = begin()
        for _ in 0..<5 {
            DispatchQueue.main.advance(0.5)
            move(idle, inside: false)
        }
        expect(!idle.captureControlsCollapsed, "capture controls remain available during the initial three seconds")
        DispatchQueue.main.advance(0.5)
        expect(idle.captureControlsCollapsed && idle.captureControls != nil,
               "pointer movement outside controls does not postpone collapse or cancel capture")
        expect(idle.panel?.isVisible == true && idle.windowHost?.activationRect.isEmpty == false,
               "collapsed capture retains a clickable reopening target")
        idle.windowHost?.activate?()
        expect(!idle.captureControlsCollapsed, "the compact activation target reopens capture controls")

        move(idle, inside: true)
        expect(idle.panel?.acceptsMouseMovedEvents == true && idle.panel?.ignoresMouseEvents == false,
               "expanded controls retain movement delivery so their transparent edges cannot swallow the next selection")
        DispatchQueue.main.advance(6)
        expect(!idle.captureControlsCollapsed, "controls stay open while the pointer uses them")
        let expandedFrame = idle.windowHost!.frame
        idle.collapseCaptureControls()
        move(idle, inside: true)
        expect(idle.panel?.acceptsMouseMovedEvents == true && idle.panel?.ignoresMouseEvents == false,
               "the compact target still reports the movement that exits its controls")
        DispatchQueue.main.advance(1)
        expect(idle.captureControlsCollapsed, "manual collapse cannot immediately reopen under a stationary pointer")
        idle.windowHost?.animatingFrame = expandedFrame
        NSEvent.mouseLocation = CGPoint(x: expandedFrame.midX, y: expandedFrame.minY + 1)
        idle.updateCaptureControlsClickThrough()
        expect(idle.panel?.ignoresMouseEvents == true && idle.panel?.acceptsMouseMovedEvents == false,
               "the disappearing part of a collapsing window cannot swallow a selection click")
        idle.windowHost?.animatingFrame = nil
        move(idle, inside: false)
        expect(idle.panel?.acceptsMouseMovedEvents == false && idle.panel?.ignoresMouseEvents == true,
               "leaving the compact target returns pointer delivery to the selection surface")
        move(idle, inside: true)
        DispatchQueue.main.advance(0.2)
        expect(idle.captureControlsCollapsed, "a brief pass over the compact target does not reopen controls")
        DispatchQueue.main.advance(0.05)
        expect(!idle.captureControlsCollapsed, "a deliberate hover reopens the same capture")

        move(idle, inside: false)
        idle.captureControls?.hasFocusedControl = true
        idle.scheduleCaptureControlsCollapse()
        DispatchQueue.main.advance(6)
        expect(!idle.captureControlsCollapsed, "keyboard editing prevents automatic collapse")
        idle.captureControls?.hasFocusedControl = false
        idle.scheduleCaptureControlsCollapse()
        DispatchQueue.main.advance(3)
        expect(idle.captureControlsCollapsed, "leaving keyboard controls restores the idle deadline")

        idle.expandCaptureControls()
        idle.setCaptureSelectionInProgress(true)
        expect(idle.captureControlsCollapsed && idle.panel?.isVisible == false
               && idle.panel?.ignoresMouseEvents == true && idle.panel?.acceptsMouseMovedEvents == false,
               "starting selection immediately removes the entire capture window and its hit target")
        move(idle, inside: true)
        idle.expandCaptureControls()
        DispatchQueue.main.advance(4)
        idle.refreshPresentation()
        expect(idle.panel?.isVisible == false && idle.captureControlsCollapsed,
               "hover, reopening actions and presentation refresh cannot obscure a live drag")
        move(idle, inside: false)
        idle.setCaptureSelectionInProgress(false)
        expect(idle.panel?.isVisible == true && idle.captureControlsCollapsed,
               "an empty selection restores only the compact target for another attempt")
        move(idle, inside: true)
        idle.endCaptureControls()
        let keyRequests = idle.panel?.keyRequests
        DispatchQueue.main.advance(5)
        expect(idle.captureControls == nil && idle.panel?.keyRequests == keyRequests,
               "ending capture cancels a pending hover without reopening anything")
        expect(DispatchQueue.main.pending == 0 && idle.monitorRemovals == 1,
               "capture teardown leaves no scheduled work or capture monitors")

        NSEvent.mouseLocation = .zero
        let replaced = begin()
        let oldOptions = replaced.captureControls
        let oldDeadline = replaced.captureControlsWork
        replaced.endCaptureControls()
        replaced.captureControls = CaptureOptions()
        replaced.refreshPresentation()
        withExtendedLifetime(oldOptions) { oldDeadline?.perform() }
        expect(!replaced.captureControlsCollapsed,
               "even a delivered stale callback cannot collapse a replacement session")
        replaced.endCaptureControls()
    }
}
