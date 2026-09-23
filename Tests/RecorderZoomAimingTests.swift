// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the editor's actual aiming lifecycle, and the undo that can take its
/// zoom away, with a controlled preview player.
enum RecorderZoomAimingTests {
    final class PreviewTask {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    final class Item { var videoComposition: String? = "edited" }
    final class Player {
        var currentItem: Item? = Item()
        var isMuted = true
    }
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
        var undoStack: [RecorderEditDocument] = []
        var redoStack: [RecorderEditDocument] = []
        var suppressUndo = false
        var trim = RecorderSupport.Trim(start: 0, end: 5)
        var focus: CGPoint? {
            guard let segment = document.zoomSegments.first,
                  let x = segment.focusX, let y = segment.focusY else { return nil }
            return CGPoint(x: x, y: y)
        }
        var pauseCount = 0
        var rebuildCount = 0
        func pause() { pauseCount += 1 }
        func rebuildPreview() {
            // Like the editor, nothing is composed while a picker shows the raw source.
            guard !isAimingZoom, !isPickingBlurArea else { return }
            rebuildCount += 1
            player.currentItem?.videoComposition = "edited"
        }
        func beginInteraction() {}
        func commitZoomEdit() {}
        func persist() {}
        func rebuildComposition() {}
        func applyAudioMix() {}
        func seek(to seconds: Double) {}
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
        removedByUndo(suite)
    }

    /// Undo can take away the zoom being aimed. Its selection goes with it,
    /// or the next click on the picture would set the focus of nothing.
    private static func removedByUndo(_ suite: TestSuite) {
        let model = Model()
        let added = model.document.zoomSegments[0].id
        model.undoStack = [RecorderEditDocument()]
        model.selectedZoomID = added
        model.beginAiming()
        model.undo()
        suite.expect(model.zoom(added) == nil && model.selectedZoomID == nil,
                     "undoing a zoom's creation also clears its selection")
        suite.expect(!model.isAimingZoom && model.player.currentItem?.videoComposition == "edited",
                     "undo ends aiming at the removed zoom and restores the edited preview")
        model.beginAiming()
        suite.expect(!model.isAimingZoom, "aiming cannot begin for a zoom that undo removed")
        model.redo()
        suite.expect(model.zoom(added) != nil && model.selectedZoomID == nil,
                     "redo brings the zoom back without reviving the stale selection")
        model.selectedZoomID = added
        model.document = RecorderEditDocument()
        suite.expect(model.selectedZoomID == nil && model.undoStack.count == 2,
                     "an ordinary edit that replaces the zooms drops the selection and stays undoable")

        let blurred = Model()
        let blur = RecorderBlurRegion(start: 0, end: 5)
        blurred.document.blurs = [blur]
        blurred.selectedBlurID = blur.id
        blurred.beginPickingBlurArea()
        let rebuilds = blurred.rebuildCount
        blurred.undo()
        suite.expect(blurred.document.blurs.isEmpty && blurred.selectedBlurID == nil,
                     "undoing a blur's creation also clears its selection")
        suite.expect(!blurred.isPickingBlurArea && blurred.rebuildCount > rebuilds
                     && blurred.player.currentItem?.videoComposition == "edited",
                     "undo ends drawing the removed blur's area and restores the edited preview")
    }
}
