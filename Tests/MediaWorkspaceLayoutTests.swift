// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Measures production layout and native drop registration without displaying
/// a window, capturing pixels, or sending any input to the user's session.
enum MediaWorkspaceLayoutTests {
    final class Fixture: ObservableObject {
        @Published var height: CGFloat = 180
    }

    final class Selection {
        var events: [String] = []
        var tool = MediaTool.videoCompressor {
            didSet { events.append("content:\(tool.rawValue)") }
        }
    }

    final class Presentation {
        let archives: ShelfDropRoutingContract.NotchFileToolsService
        var heights: [CGFloat] = []
        init(_ archives: ShelfDropRoutingContract.NotchFileToolsService) { self.archives = archives }
        func refreshPresentation() {
            if let height = archives.mediaContentHeight { heights.append(height) }
        }
    }

    class HeightState {
        let archives = ShelfDropRoutingContract.NotchFileToolsService()
        lazy var service = Presentation(archives)
    }

    static func run(expect: (Bool, String) -> Void) {
        func settle(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(2)
            while !condition(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            return condition()
        }
        let fixture = Fixture()
        let fileView = FileView()
        _ = fileView.archives.openMedia(.videoCompressor, inputs: [])
        let sessionID = fileView.archives.mediaSession!.id
        var measured: CGFloat = 0
        let host = NSHostingView(rootView: Workspace(fixture: fixture, onContentHeightChange: {
            measured = $0
            fileView.mediaHeightChanged($0, id: sessionID)
        }))
        host.frame = CGRect(x: 0, y: 0, width: 380, height: 700)
        host.layoutSubtreeIfNeeded()
        expect(settle { measured == 246 },
               "embedded media reports the intrinsic height of header, picker, spacing and content instead of the viewport")
        for height: CGFloat in [80, 550, 180] {
            fixture.height = height
            host.layoutSubtreeIfNeeded()
            expect(settle { measured == height + 66 },
                   "media's reported height follows options and results as they grow or shrink")
            expect(fileView.service.heights.last == measured,
                   "the native window receives its new size in the measurement callback, before a later preferences refresh")
        }
        let frames = fileView.service.heights
        fileView.mediaHeightChanged(measured, id: sessionID)
        fileView.mediaHeightChanged(999, id: UUID())
        fileView.mediaHeightChanged(.nan, id: sessionID)
        expect(fileView.service.heights == frames,
               "duplicate, invalid and stale measurements never restart the resize")

        let selection = Selection()
        let picker = ToolPicker(fixture: selection, onToolChange: {
            selection.events.append("transition:\(selection.tool.rawValue)")
        })
        for tool in [MediaTool.gifMaker, .textExtractor, .imageCompressor, .videoCompressor] {
            let previous = selection.tool
            selection.events = []
            picker.selectedToolBinding.wrappedValue = tool
            expect(selection.events == ["transition:\(previous.rawValue)", "content:\(tool.rawValue)"],
                   "each tool change captures the old content for its transition before replacing the controls")
            selection.events = []
            picker.selectedToolBinding.wrappedValue = tool
            expect(selection.events.isEmpty, "reselecting the current tool does not reset work or restart its animation")
        }

        func types(in view: NSView) -> Set<NSPasteboard.PasteboardType> {
            view.subviews.reduce(into: Set(view.registeredDraggedTypes)) { $0.formUnion(types(in: $1)) }
        }
        for embedded in [false, true] {
            let input = NSHostingView(rootView: Input(inNotch: embedded))
            input.frame = CGRect(x: 0, y: 0, width: 300, height: 70)
            input.layoutSubtreeIfNeeded()
            _ = input.fittingSize
            if embedded {
                expect(types(in: input).isEmpty,
                       "embedded media leaves file drops to the island's destination chooser")
            } else {
                // SwiftUI registers broad transport types and filters the
                // requested file URL type in its own drop coordinator.
                expect(settle { !types(in: input).isEmpty },
                       "standalone media retains its native direct file drop target")
            }
        }
    }
}
