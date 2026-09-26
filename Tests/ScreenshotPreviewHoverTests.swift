// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production hover handlers and dismissal scheduling run with a controlled
/// clock. Pointer crossings are supplied explicitly; no native UI is exercised.
enum ScreenshotPreviewHoverTests {
    typealias DispatchQueue = NotchScreenRefreshContract.DispatchQueue

    final class Model {
        var sharing = false
        var deletingShare = false
    }

    class State {
        var pointerInside = false
        var systemSharing = false
        var dismissWork: DispatchWorkItem?
        var autoDismissDuration: TimeInterval = 12
        var closed = false
        let model = Model()
        func close() { closed = true }
    }

    static func run(_ suite: TestSuite) {
        defer { DispatchQueue.main = NotchScreenRefreshContract.Scheduler() }
        for duration in [3.0, 12.0] {
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            let controller = Controller()
            controller.autoDismissDuration = duration
            let embedded = Preview(embedded: true, hoverChanged: controller.hoverChanged)
            controller.scheduleAutoDismiss()
            controller.hoverChanged(true) // Enter the island through the header.
            DispatchQueue.main.advance(duration)
            suite.expect(!controller.closed, "entering the capture header cancels automatic dismissal")

            for _ in 0..<2 {
                embedded.previewHoverChanged(true) // Header to image.
                embedded.previewHoverChanged(false) // Image to header, still in the island.
                DispatchQueue.main.advance(duration)
                suite.expect(controller.pointerInside && !controller.closed && DispatchQueue.main.pending == 0,
                             "moving between the image and header actions keeps the embedded preview open")
            }

            controller.hoverChanged(false) // Leave the whole island.
            DispatchQueue.main.advance(duration - 0.5)
            suite.expect(!controller.closed, "leaving the island keeps the configured dismissal delay")
            controller.hoverChanged(true) // Return before the deadline.
            DispatchQueue.main.advance(duration)
            suite.expect(!controller.closed, "returning to the header cancels an outstanding dismissal")
            controller.hoverChanged(false)
            DispatchQueue.main.advance(duration)
            suite.expect(controller.closed, "leaving the island still dismisses an unused capture")

            // Disabling the island rebuilds the preview as a floating view.
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            let floatingController = Controller()
            floatingController.autoDismissDuration = duration
            let floating = Preview(embedded: false, hoverChanged: floatingController.hoverChanged)
            floatingController.scheduleAutoDismiss()
            floating.previewHoverChanged(true)
            DispatchQueue.main.advance(duration)
            suite.expect(floatingController.pointerInside && !floatingController.closed,
                         "the floating preview still cancels dismissal while hovered")
            floating.previewHoverChanged(false)
            DispatchQueue.main.advance(duration - 0.5)
            suite.expect(!floatingController.closed, "the floating preview retains its dismissal delay")
            DispatchQueue.main.advance(0.5)
            suite.expect(floatingController.closed, "leaving the floating preview still dismisses it")

            // The system share sheet opens outside the preview, so the pointer
            // leaves it while a target is being picked.
            DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
            let sharingController = Controller()
            sharingController.autoDismissDuration = duration
            sharingController.systemSharing = true
            sharingController.hoverChanged(true)
            sharingController.hoverChanged(false)
            DispatchQueue.main.advance(duration)
            suite.expect(!sharingController.closed && DispatchQueue.main.pending == 0,
                         "an open share sheet keeps the preview from dismissing")
            sharingController.systemSharing = false
            sharingController.scheduleAutoDismiss()
            DispatchQueue.main.advance(duration)
            suite.expect(sharingController.closed, "a cancelled share sheet resumes the dismissal delay")
        }
    }
}
