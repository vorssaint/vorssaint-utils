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
        func pointer(_ service: Service, inside: Bool) -> CGPoint {
            inside ? CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY - 1) : .zero
        }
        /// Presents the controls as a capture does: compact, with a pointer
        /// already resting on them held back until it leaves.
        func begin(pointerInside: Bool = false) -> Service {
            let service = Service()
            NSEvent.mouseLocation = pointer(service, inside: pointerInside)
            service.windowHost?.missionControlDidRestore = { [weak service] in service?.missionControlDidRestore() }
            service.expanded = false
            service.captureControls = CaptureOptions()
            service.captureControlsCollapsed = true
            service.captureControlsMonitors = [1]
            service.refreshPresentation(animated: false)
            service.hoverState.close(pointerInside: service.windowHost?.containsHover(NSEvent.mouseLocation) == true)
            service.updateCaptureControlsClickThrough()
            return service
        }
        func move(_ service: Service, inside: Bool) {
            NSEvent.mouseLocation = pointer(service, inside: inside)
            service.updateCaptureControlsClickThrough()
        }

        let idle = begin()
        for _ in 0..<8 {
            DispatchQueue.main.advance(0.5)
            move(idle, inside: false)
        }
        suite.expect(idle.captureControlsCollapsed && idle.captureControls != nil,
               "capture controls start compact and stay so while the pointer selects elsewhere")
        suite.expect(idle.panel?.isVisible == true && idle.windowHost?.activationRect.isEmpty == false,
               "compact capture controls keep a clickable target that opens them")
        move(idle, inside: true)
        DispatchQueue.main.advance(0.2)
        suite.expect(idle.captureControlsCollapsed, "a brief pass over the compact target does not open controls")
        DispatchQueue.main.advance(0.1)
        suite.expect(!idle.captureControlsCollapsed, "a deliberate hover opens the controls")

        move(idle, inside: true)
        suite.expect(idle.panel?.acceptsMouseMovedEvents == true && idle.panel?.ignoresMouseEvents == false,
               "expanded controls retain movement delivery so their transparent edges cannot swallow the next selection")
        DispatchQueue.main.advance(6)
        suite.expect(!idle.captureControlsCollapsed, "controls stay open while the pointer uses them")
        move(idle, inside: false)
        DispatchQueue.main.advance(0.1)
        move(idle, inside: true)
        DispatchQueue.main.advance(1)
        suite.expect(!idle.captureControlsCollapsed, "a pointer that slips off and returns at once keeps the controls open")
        move(idle, inside: false)
        DispatchQueue.main.advance(0.1)
        move(idle, inside: false)
        DispatchQueue.main.advance(0.1)
        suite.expect(idle.captureControlsCollapsed && idle.captureControls != nil,
               "leaving the controls closes them soon, however the pointer moves, without cancelling the capture")

        idle.windowHost?.activate?()
        suite.expect(!idle.captureControlsCollapsed, "the compact activation target opens capture controls")
        DispatchQueue.main.advance(2.5)
        suite.expect(!idle.captureControlsCollapsed,
               "controls opened with the pointer elsewhere wait for a control to take keyboard focus")
        DispatchQueue.main.advance(1)
        suite.expect(idle.captureControlsCollapsed, "controls opened with the pointer elsewhere close when none does")

        move(idle, inside: true)
        DispatchQueue.main.advance(0.3)
        suite.expect(!idle.captureControlsCollapsed, "hovering again after the controls closed opens them")
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
        DispatchQueue.main.advance(0.3)
        suite.expect(!idle.captureControlsCollapsed, "a deliberate hover reopens the same capture")

        idle.captureControls?.hasFocusedControl = true
        idle.scheduleCaptureControlsCollapse()
        move(idle, inside: false)
        DispatchQueue.main.advance(6)
        suite.expect(!idle.captureControlsCollapsed, "keyboard editing keeps the controls open after the pointer leaves")
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

        let replaced = begin()
        replaced.expandCaptureControls()
        let oldOptions = replaced.captureControls
        let oldDeadline = replaced.captureControlsWork
        replaced.endCaptureControls()
        replaced.captureControls = CaptureOptions()
        replaced.refreshPresentation()
        withExtendedLifetime(oldOptions) { oldDeadline?.perform() }
        suite.expect(oldDeadline != nil && !replaced.captureControlsCollapsed,
               "even a delivered stale callback cannot collapse a replacement session")
        replaced.endCaptureControls()

        let resting = begin(pointerInside: true)
        DispatchQueue.main.advance(1)
        suite.expect(resting.captureControlsCollapsed,
                     "a pointer already on the island when capture starts does not open the controls")
        move(resting, inside: false)
        move(resting, inside: true)
        DispatchQueue.main.advance(0.3)
        suite.expect(!resting.captureControlsCollapsed, "once that pointer leaves, hovering opens the controls")
        resting.endCaptureControls()

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
        suite.expect(host.panel.isVisible == host.restoringFromMissionControl,
                     "a visible island stays marked as restoring while it fades back in")
        host.fadeCompletion?()
        suite.expect(!host.restoringFromMissionControl, "the finished fade ends the restore")

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
