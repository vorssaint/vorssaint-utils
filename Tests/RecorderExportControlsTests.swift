// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum RecorderExportControlsTests {
    static func run(_ suite: TestSuite) {
        let model = RecorderExportControlsFixture()
        model.document.exportFormat = "gif"
        model.document.gifScalePercent = 50
        suite.expect(model.exportSize == CGSize(width: 960, height: 540),
                     "editor dimensions follow selected GIF scale independently of video quality")
        model.document.gifScalePercent = 1
        suite.expect(model.exportSize == CGSize(width: 56, height: 32),
                     "editor GIF dimensions reflect the encoder minimum short side")
        model.setExportFormat(.video)
        suite.expect(model.exportSize == CGSize(width: 1920, height: 1080),
                     "switching back to video restores its independent quality dimensions")
        model.setGIFScalePercent(75)
        model.setGIFFrameRate(20)
        model.setExportFormat(.gif)
        suite.expect(model.document.quality == "balanced"
            && model.document.resolvedGIFScalePercent == 75
            && model.document.resolvedGIFFrameRate == 20,
                     "format, GIF size and FPS edits preserve independent video quality")
        let beforeBusyEdit = model.document
        model.isExporting = true
        model.setExportFormat(.video)
        model.setGIFScalePercent(50)
        model.setGIFFrameRate(10)
        suite.expect(model.document == beforeBusyEdit,
                     "export controls reject edits while export is in progress")

        let actions = RecorderExportActionFixture()
        for format in [RecorderSupport.ExportFormat.video, .gif] {
            actions.model.setExportFormat(format)
            actions.save()
            let ext = format == .gif ? "gif" : "mp4"
            suite.expect(actions.saved?.1.pathExtension == ext,
                         "primary save chooses the selected format extension")
            switch (format, actions.saved?.0) {
            case (.video, .video?), (.gif, .gif?): break
            default: suite.expect(false, "primary save chooses the selected encoder")
            }
            actions.copySelected()
            suite.expect(actions.copied?.0 == format && actions.copied?.1 == false,
                         "primary copy chooses the selected encoder without deleting")
            actions.copyAndDelete()
            suite.expect(actions.copied?.0 == format && actions.copied?.1 == true,
                         "copy and delete chooses the selected encoder")
            let selection = RecorderEditorExportSelection(format: format)
            suite.expect(selection.contentType.identifier == (format == .gif ? "com.compuserve.gif" : "public.mpeg-4"),
                         "Save As uses the selected format content type")
        }
        let pendingCopy = RecorderExportActionFixture()
        var didProduceClipboardFile = false
        pendingCopy.run(.gif, to: URL(fileURLWithPath: "/tmp/copy.gif"),
                        rememberDestination: false) { _ in didProduceClipboardFile = true }
        pendingCopy.model.completion?(nil)
        suite.expect(didProduceClipboardFile && !pendingCopy.exported,
                     "producing a clipboard file does not mark the recording safe before publication")
        pendingCopy.finishClipboardPublication(false, deletesRecording: true)
        suite.expect(!pendingCopy.exported && !pendingCopy.confirmedClose && pendingCopy.window?.closes == 0,
                     "failed publication after a successful GIF export preserves close confirmation")
        let failedSave = RecorderExportActionFixture()
        failedSave.save()
        failedSave.model.completion?(.writeFailed)
        suite.expect(!failedSave.exported,
                     "failed save does not mark the recording safely exported")
        let successfulSave = RecorderExportActionFixture()
        successfulSave.save()
        successfulSave.model.completion?(nil)
        suite.expect(successfulSave.exported,
                     "successful save still marks a recording safely exported")
        let lane = RecorderExportActionFixture.GeneralPasteboardAccess.shared
        let cancelledCopy = RecorderExportActionFixture()
        cancelledCopy.startGIFCopy(true)
        cancelledCopy.model.completion?(nil)
        let cancelledWork = lane.pending.removeFirst()
        suite.expect(cancelledCopy.model.isExporting,
                     "GIF publication remains busy while queued")
        cancelledCopy.model.cancelExport()
        suite.expect(!cancelledCopy.model.isExporting,
                     "cancelling queued GIF publication immediately releases the editor")
        let publicationsBeforeCancel = RecorderExportActionFixture.RecorderGIFClipboard.publications
        let queuedResult = cancelledWork.work()
        suite.expect(RecorderExportActionFixture.RecorderGIFClipboard.publications == publicationsBeforeCancel,
                     "cancelled queued GIF work never touches the clipboard")
        cancelledWork.completion(queuedResult)
        cancelledWork.completion(true)
        suite.expect(!cancelledCopy.exported && !cancelledCopy.confirmedClose && cancelledCopy.window?.closes == 0,
                     "late GIF publication success after cancellation cannot mark safe or close and delete")

        let staleCopy = RecorderExportActionFixture()
        staleCopy.startGIFCopy(true)
        staleCopy.model.completion?(nil)
        let firstWork = lane.pending.removeFirst()
        _ = firstWork.work() // Simulates an AppKit operation already running when cancelled.
        staleCopy.model.cancelExport()
        staleCopy.model.isExporting = true // A later encoder now owns busy state.
        firstWork.completion(true)
        suite.expect(staleCopy.model.isExporting && !staleCopy.exported && staleCopy.window?.closes == 0,
                     "stale publication completion cannot clear a later export's busy state or close it")

        let normalCopy = RecorderExportActionFixture()
        normalCopy.startGIFCopy(true)
        normalCopy.model.completion?(nil)
        let normalWork = lane.pending.removeFirst()
        normalWork.completion(normalWork.work())
        suite.expect(!normalCopy.model.isExporting && normalCopy.exported
            && normalCopy.confirmedClose && normalCopy.window?.closes == 1,
                     "uncancelled GIF publication still completes copy and delete")
        actions.finishClipboardPublication(false, deletesRecording: true)
        suite.expect(!actions.exported && !actions.confirmedClose && actions.window?.closes == 0,
                     "failed clipboard publication never marks a source safe or closes and deletes it")
        actions.finishClipboardPublication(true, deletesRecording: false)
        suite.expect(actions.exported && !actions.confirmedClose && actions.window?.closes == 0,
                     "successful copy keeps the editor open")
        actions.finishClipboardPublication(true, deletesRecording: true)
        suite.expect(actions.confirmedClose && actions.window?.closes == 1,
                     "successful clipboard publication closes only when deletion was requested")
    }
}
