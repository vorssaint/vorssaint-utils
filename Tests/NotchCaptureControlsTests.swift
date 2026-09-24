// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension NotchPresentationRefreshContract {
    /// Production presentation and timer bodies, with an inert window and clock.
    /// Pointer locations are values only; no events or windows reach the desktop.
    static func captureControlsChecks(_ suite: TestSuite) {
        DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
        NSEvent.mouseLocation = .zero
        NSEvent.monitorRemovals = 0
        defer {
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            NSEvent.mouseLocation = .zero
            NSEvent.monitorRemovals = 0
        }
        func begin() -> Service {
            let service = Service()
            service.windowHost?.missionControlDidRestore = { [weak service] in service?.missionControlDidRestore() }
            service.expanded = false
            service.captureControls = CaptureOptions()
            service.captureControlsMonitors = [1]
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
        suite.expect(!idle.captureControlsCollapsed, "capture controls remain available during the initial three seconds")
        DispatchQueue.main.advance(0.5)
        suite.expect(idle.captureControlsCollapsed && idle.captureControls != nil,
               "pointer movement outside controls does not postpone collapse or cancel capture")
        suite.expect(idle.panel?.isVisible == true && idle.windowHost?.activationRect.isEmpty == false,
               "collapsed capture retains a clickable reopening target")
        idle.windowHost?.activate?()
        suite.expect(!idle.captureControlsCollapsed, "the compact activation target reopens capture controls")

        move(idle, inside: true)
        suite.expect(idle.panel?.acceptsMouseMovedEvents == true && idle.panel?.ignoresMouseEvents == false,
               "expanded controls retain movement delivery so their transparent edges cannot swallow the next selection")
        DispatchQueue.main.advance(6)
        suite.expect(!idle.captureControlsCollapsed, "controls stay open while the pointer uses them")
        let expandedFrame = idle.windowHost!.frame
        idle.collapseCaptureControls()
        move(idle, inside: true)
        suite.expect(idle.panel?.acceptsMouseMovedEvents == true && idle.panel?.ignoresMouseEvents == false,
               "the compact target still reports the movement that exits its controls")
        DispatchQueue.main.advance(1)
        suite.expect(idle.captureControlsCollapsed, "manual collapse cannot immediately reopen under a stationary pointer")
        idle.windowHost?.animatingFrame = expandedFrame
        NSEvent.mouseLocation = CGPoint(x: expandedFrame.midX, y: expandedFrame.minY + 1)
        idle.updateCaptureControlsClickThrough()
        suite.expect(idle.panel?.ignoresMouseEvents == true && idle.panel?.acceptsMouseMovedEvents == false,
               "the disappearing part of a collapsing window cannot swallow a selection click")
        idle.windowHost?.animatingFrame = nil
        move(idle, inside: false)
        suite.expect(idle.panel?.acceptsMouseMovedEvents == false && idle.panel?.ignoresMouseEvents == true,
               "leaving the compact target returns pointer delivery to the selection surface")
        move(idle, inside: true)
        DispatchQueue.main.advance(0.2)
        suite.expect(idle.captureControlsCollapsed, "a brief pass over the compact target does not reopen controls")
        DispatchQueue.main.advance(0.05)
        suite.expect(!idle.captureControlsCollapsed, "a deliberate hover reopens the same capture")

        move(idle, inside: false)
        idle.captureControls?.hasFocusedControl = true
        idle.scheduleCaptureControlsCollapse()
        DispatchQueue.main.advance(6)
        suite.expect(!idle.captureControlsCollapsed, "keyboard editing prevents automatic collapse")
        idle.captureControls?.hasFocusedControl = false
        idle.scheduleCaptureControlsCollapse()
        DispatchQueue.main.advance(3)
        suite.expect(idle.captureControlsCollapsed, "leaving keyboard controls restores the idle deadline")

        idle.expandCaptureControls()
        idle.setCaptureSelectionInProgress(true)
        suite.expect(idle.captureControlsCollapsed && idle.panel?.isVisible == false
               && idle.panel?.ignoresMouseEvents == true && idle.panel?.acceptsMouseMovedEvents == false,
               "starting selection immediately removes the entire capture window and its hit target")
        move(idle, inside: true)
        idle.expandCaptureControls()
        DispatchQueue.main.advance(4)
        idle.refreshPresentation()
        suite.expect(idle.panel?.isVisible == false && idle.captureControlsCollapsed,
               "hover, reopening actions and presentation refresh cannot obscure a live drag")
        move(idle, inside: false)
        idle.setCaptureSelectionInProgress(false)
        suite.expect(idle.panel?.isVisible == true && idle.captureControlsCollapsed,
               "an empty selection restores only the compact target for another attempt")
        move(idle, inside: true)
        idle.endCaptureControls()
        let keyRequests = idle.panel?.keyRequests
        DispatchQueue.main.advance(5)
        suite.expect(idle.captureControls == nil && idle.panel?.keyRequests == keyRequests,
               "ending capture cancels a pending hover without reopening anything")
        suite.expect(DispatchQueue.main.pending == 0 && NSEvent.monitorRemovals == 1,
               "capture teardown leaves no scheduled work or capture monitors")

        NSEvent.mouseLocation = .zero
        let replaced = begin()
        let oldOptions = replaced.captureControls
        let oldDeadline = replaced.captureControlsWork
        replaced.endCaptureControls()
        replaced.captureControls = CaptureOptions()
        replaced.refreshPresentation()
        withExtendedLifetime(oldOptions) { oldDeadline?.perform() }
        suite.expect(!replaced.captureControlsCollapsed,
               "even a delivered stale callback cannot collapse a replacement session")
        replaced.endCaptureControls()

        let missionControl = begin()
        let host = missionControl.windowHost!
        host.missionControlMouseEvents = missionControl.panel!.ignoresMouseEvents
        host.concealedForMissionControl = true
        missionControl.endCaptureControls()
        suite.expect(host.missionControlMouseEvents == false && missionControl.panel?.ignoresMouseEvents == true,
                     "ending capture updates the saved input policy while Mission Control keeps the panel click-through")
        host.restoreFromMissionControl()
        suite.expect(missionControl.panel?.ignoresMouseEvents == false,
                     "the resting island accepts clicks again after Mission Control")

        let moving = begin()
        move(moving, inside: true)
        let movingHost = moving.windowHost!
        movingHost.concealedForMissionControl = true
        movingHost.missionControlMouseEvents = false
        moving.panel?.ignoresMouseEvents = true
        move(moving, inside: true)
        suite.expect(movingHost.missionControlMouseEvents && moving.panel?.ignoresMouseEvents == true,
                     "a concealed hit test cannot determine the saved capture input policy")
        movingHost.restoreFromMissionControl()
        suite.expect(moving.panel?.ignoresMouseEvents == false && moving.panel?.acceptsMouseMovedEvents == true,
                     "restoring Mission Control recomputes the capture policy for a pointer over the controls")
        movingHost.concealedForMissionControl = true
        movingHost.missionControlMouseEvents = false
        moving.panel?.ignoresMouseEvents = true
        NSEvent.mouseLocation = .zero
        movingHost.restoreFromMissionControl()
        suite.expect(moving.panel?.ignoresMouseEvents == true && moving.panel?.acceptsMouseMovedEvents == false,
                     "restoring Mission Control also handles a pointer that moved away without a local event")
        moving.endCaptureControls()

        let hidden = Host()
        hidden.hidesWhenSettled = true
        hidden.mouseEventsBeforeHide = true
        hidden.setMouseEventsIgnored(false)
        suite.expect(hidden.panel.ignoresMouseEvents && hidden.mouseEventsBeforeHide == false,
                     "a hidden island retains its new input policy for the next reveal")
    }
}
