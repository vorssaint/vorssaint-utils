// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the editor's actual aiming lifecycle with a controlled preview player.
enum RecorderZoomAimingTests {
    final class PreviewTask {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    final class Item { var videoComposition: String? = "edited" }
    final class Player { var currentItem: Item? = Item() }
    class State {
        let player = Player()
        var previewTask: PreviewTask? = PreviewTask()
        var selectedBlurID: UUID?
        var isAimingZoom = false
        var isPickingBlurArea = false
        var sourceSize = CGSize(width: 1000, height: 500)
        var document: RecorderEditDocument = {
            var document = RecorderEditDocument()
            document.zoomSegments = [.init(start: 0, end: 5, amount: 2)]
            return document
        }()
        var focus: CGPoint? {
            guard let segment = document.zoomSegments.first,
                  let x = segment.focusX, let y = segment.focusY else { return nil }
            return CGPoint(x: x, y: y)
        }
        var pauseCount = 0
        var rebuildCount = 0
        func pause() { pauseCount += 1 }
        func rebuildPreview() {
            rebuildCount += 1
            player.currentItem?.videoComposition = "edited"
        }
        func beginInteraction() {}
        func applyDuringInteraction(_ next: RecorderEditDocument) { document = next }
        func commitZoomEdit() {}
    }

    static func run(_ suite: TestSuite) {
        let model = Model()
        model.beginAiming()
        suite.expect(!model.isAimingZoom && model.player.currentItem?.videoComposition == "edited",
                     "aiming requires a selected zoom and otherwise leaves the preview alone")
        model.selectedZoomID = model.document.zoomSegments[0].id
        model.beginAiming()
        suite.expect(model.isAimingZoom && model.previewTask?.cancelled == true
                     && model.player.currentItem?.videoComposition == nil && model.pauseCount == 1,
                     "choosing a zoom focus pauses and removes the composed zoom and backdrop")
        model.aim(at: CGPoint(x: 150, y: 125), in: CGSize(width: 200, height: 200))
        suite.expect(model.focus == CGPoint(x: 0.75, y: 0.75)
                     && !model.isAimingZoom && model.rebuildCount == 1,
                     "a click maps through the full letterboxed source and restores the edited preview")
        model.beginAiming()
        model.endAiming()
        suite.expect(!model.isAimingZoom && model.rebuildCount == 2,
                     "Escape restores the edited preview without changing the selected focus")
        model.endAiming()
        suite.expect(model.rebuildCount == 2, "ending an inactive picker does not rebuild again")
        model.beginAiming()
        model.aim(at: CGPoint(x: 10, y: 10), in: CGSize(width: 200, height: 200))
        suite.expect(model.focus == CGPoint(x: 0.75, y: 0.75) && model.rebuildCount == 3,
                     "a click outside the source keeps the old focus and still restores the preview")
        model.beginAiming()
        model.selectedZoomID = nil
        suite.expect(!model.isAimingZoom && model.rebuildCount == 4,
                     "deselecting or deleting the zoom exits raw-preview mode")
        model.selectedZoomID = model.document.zoomSegments[0].id
        model.beginAiming()
        model.selectedBlurID = UUID()
        model.beginPickingBlurArea()
        suite.expect(!model.isAimingZoom && model.isPickingBlurArea
                     && model.player.currentItem?.videoComposition == nil,
                     "switching to blur selection leaves only one active picker over the full source")
        model.beginAiming()
        suite.expect(model.isAimingZoom && !model.isPickingBlurArea,
                     "switching back to zoom aiming ends blur selection")
        let rebuilds = model.rebuildCount
        model.setSelectedZoomFocus(nil)
        suite.expect(model.focus == nil && !model.isAimingZoom
                     && model.player.currentItem?.videoComposition == "edited"
                     && model.rebuildCount == rebuilds + 1,
                     "following the pointer cancels manual aiming and restores the edited preview")
        model.beginAiming()
        model.setSelectedZoomFocus(nil)
        suite.expect(!model.isAimingZoom && model.player.currentItem?.videoComposition == "edited"
                     && model.rebuildCount == rebuilds + 2,
                     "following the pointer restores the preview even when the focus was already unset")
    }
}
