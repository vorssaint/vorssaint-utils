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

        // Both previews arrive through presentCapture, as the screenshot
        // preview sends them, so whether one stays until dismissed comes
        // from what it was presented with.
        let persistent = Service()
        var persistentCloseCount = 0
        var persistentClosedAfterTakeover = false
        let persistentShown = persistent.presentCapture(
            id: UUID(), content: true, height: 120, takeFocus: false, closeOnCollapse: true,
            fallback: {}, close: {
                persistentCloseCount += 1
                persistentClosedAfterTakeover = persistent.captureControls != nil
                    && persistent.captureID == nil && persistent.captureContent == nil
                    && persistent.captureClose == nil
            }, hover: { _ in })
        suite.expect(persistentShown && persistent.openedPages.map(\.module) == [.captures]
                     && persistent.openedPages.last?.takeFocus == false,
                     "a preview that stays until dismissed opens the captures page without the keyboard")
        persistent.presentCaptureControls(CaptureOptions(), cancel: {})
        suite.expect(persistentCloseCount == 1 && persistentClosedAfterTakeover,
                     "capture controls detach a persistent preview before closing it after island takeover")
        persistent.endCaptureControls()

        let timed = Service()
        var timedCloseCount = 0
        _ = timed.presentCapture(
            id: UUID(), content: true, height: 120, takeFocus: true, closeOnCollapse: false,
            fallback: {}, close: { timedCloseCount += 1 }, hover: { _ in })
        suite.expect(timed.openedPages.last?.takeFocus == true,
                     "a timed preview that prefers the keyboard asks the island for it")
        timed.presentCaptureControls(CaptureOptions(), cancel: {})
        suite.expect(timedCloseCount == 0 && timed.captureID != nil && timed.captureContent == true,
                     "capture controls leave a timed preview owned by its existing dismissal timer")
        timed.endCaptureControls()
        NSEvent.monitorRemovals = 0

        let idle = begin()
        var surfaceUpdates: [(CGRect, CGFloat)] = []
        idle.captureControls?.onCaptureControlsSurfaceChange = { surfaceUpdates.append(($0, $1)) }
        idle.refreshPresentation(animated: false)
        let compactSurfaceBottom = idle.geometry.floatingDrop + idle.surfaceSize.height
        suite.expect(surfaceUpdates.last?.0 == idle.geometry.screen
               && surfaceUpdates.last?.1 == compactSurfaceBottom,
               "compact capture controls publish their bottom edge to the selection overlay")
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
        let openSurfaceBottom = idle.geometry.floatingDrop + idle.surfaceSize.height
        suite.expect(surfaceUpdates.last?.1 == openSurfaceBottom
               && openSurfaceBottom > compactSurfaceBottom,
               "opening capture controls republishes their larger bottom edge")

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
        suite.expect(surfaceUpdates.last?.1 == compactSurfaceBottom,
               "leaving capture controls republishes their compact bottom edge")

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

        let dropped = begin()
        dropped.geometry = NotchGeometry(
            screen: dropped.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
            silhouette: .capsule, capsuleFit: NotchCapsuleFit(width: 0, height: 0, drop: 12))
        var droppedSurface: (CGRect, CGFloat)?
        dropped.captureControls?.onCaptureControlsSurfaceChange = { droppedSurface = ($0, $1) }
        dropped.refreshPresentation(animated: false)
        suite.expect(dropped.geometry.floatingDrop > 0
               && droppedSurface?.0 == dropped.geometry.screen
               && droppedSurface?.1 == dropped.geometry.floatingDrop + dropped.surfaceSize.height,
               "a lowered capsule publishes its drop plus height so it cannot cover the full-screen action")
        dropped.endCaptureControls()

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
