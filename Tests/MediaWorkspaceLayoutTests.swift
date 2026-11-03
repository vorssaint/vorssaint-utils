// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Measures production layout and native drop registration without displaying
/// a window, capturing pixels, or sending any input to the user's session.
enum MediaWorkspaceLayoutTests {
    final class Fixture: ObservableObject {
        @Published var height: CGFloat = 180
        var pickerFrame = CGRect.zero
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

    static func run(_ suite: TestSuite) {
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
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        suite.expect(settle { measured == 246 },
               "embedded media reports the intrinsic height of header, picker, spacing and content instead of the viewport")
        for height: CGFloat in [80, 550, 180] {
            fixture.height = height
            host.layoutSubtreeIfNeeded()
            suite.expect(settle { measured == height + 66 },
                   "media's reported height follows options and results as they grow or shrink")
            suite.expect(fileView.service.heights.last == measured,
                   "the native window receives its new size in the measurement callback, before a later preferences refresh")
        }
        let frames = fileView.service.heights
        fileView.mediaHeightChanged(measured, id: sessionID)
        fileView.mediaHeightChanged(999, id: UUID())
        fileView.mediaHeightChanged(.nan, id: sessionID)
        suite.expect(fileView.service.heights == frames,
               "duplicate, invalid and stale measurements never restart the resize")

        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? [])
                + view.subviews.flatMap { scrollViews(in: $0) }
        }
        func overflows(_ scroll: NSScrollView) -> Bool {
            (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height + 1
        }
        let panelFixture = Fixture()
        panelFixture.height = 900
        let panel = NSScrollView(frame: CGRect(x: 0, y: 0, width: 380, height: 260))
        panel.hasVerticalScroller = true
        panel.scrollerStyle = .overlay
        panel.autohidesScrollers = true
        let document = NSHostingView(rootView: VStack(spacing: 8) {
            Color.clear.frame(height: 24)
            Workspace(fixture: panelFixture, onContentHeightChange: nil)
        })
        document.translatesAutoresizingMaskIntoConstraints = false
        panel.documentView = document
        let panelWindow = NSWindow(contentRect: panel.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panelWindow.isReleasedWhenClosed = false
        panelWindow.contentView = panel
        defer { panelWindow.close() }
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: panel.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor),
            document.widthAnchor.constraint(equalTo: panel.contentView.widthAnchor),
        ])
        for height: CGFloat in [260, 120, 80, 190, 340] {
            panelWindow.setContentSize(CGSize(width: 380, height: height))
            panel.layoutSubtreeIfNeeded()
            suite.expect(settle {
                panel.layoutSubtreeIfNeeded()
                return abs(document.frame.height - panel.contentView.bounds.height) <= 1
                    && scrollViews(in: document).filter(overflows).count == 1
            }, "compact media fits its enclosing viewport and leaves exactly one scrolling region at height \(height)")
            if let scroll = scrollViews(in: document).first(where: overflows), let content = scroll.documentView {
                let bottom = content.frame.height - scroll.contentView.bounds.height
                scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                suite.expect(abs(scroll.contentView.bounds.maxY - content.frame.height) <= 1,
                       "the bottom media settings remain reachable at viewport height \(height)")
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                _ = settle { panelFixture.pickerFrame.minY >= 0 }
            }
        }
        if let scroll = scrollViews(in: document).first(where: overflows), let content = scroll.documentView {
            let picker = panelFixture.pickerFrame
            let wheel = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                               wheelCount: 1, wheel1: -120, wheel2: 0, wheel3: 0)!)!
            scroll.scrollWheel(with: wheel)
            suite.expect(settle { scroll.contentView.bounds.minY > 0 && panelFixture.pickerFrame.minY < picker.minY },
                   "native wheel events scroll the type picker together with media content")
            let bottom = content.isFlipped ? content.frame.height - scroll.contentView.bounds.height : 0
            scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            suite.expect(abs(scroll.contentView.bounds.minY - bottom) <= 1 && panelFixture.pickerFrame.minY < picker.minY,
                   "even a small media workspace can reach its bottom settings by scrolling the whole page")
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            suite.expect(settle { abs(panelFixture.pickerFrame.minY - picker.minY) <= 1 },
                   "scrolling back to the top restores the type picker in the same scroll region")
        } else {
            suite.expect(false, "long media options have a reachable scroll view")
        }
        for height: CGFloat in [80, 1200] {
            panelFixture.height = height
            let expectedScrolls = height == 80 ? 0 : 1
            suite.expect(settle {
                panel.layoutSubtreeIfNeeded()
                return abs(document.frame.height - panel.contentView.bounds.height) <= 1
                    && scrollViews(in: document).filter(overflows).count == expectedScrolls
            }, "changing media content height to \(height) preserves the panel viewport and scrolling ownership")
        }

        fixture.height = 900
        host.frame.size.height = 200
        host.layoutSubtreeIfNeeded()
        suite.expect(settle { measured == 966 }, "a small file-media viewport still reports its full natural height")
        if let scroll = scrollViews(in: host).first(where: overflows), let content = scroll.documentView {
            let picker = fixture.pickerFrame
            scroll.contentView.scroll(to: CGPoint(x: 0, y: content.frame.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            suite.expect(fixture.pickerFrame.minY < picker.minY && measured == 966,
                   "file-media scrolls the type picker with its settings without resizing the island from the scroll offset")
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            suite.expect(settle { abs(fixture.pickerFrame.minY - picker.minY) <= 1 && measured == 966 },
                   "file-media scrolling back to the top restores type selection without changing the natural height")
        } else {
            suite.expect(false, "file media scrolls when its natural height exceeds the available space")
        }

        let selection = Selection()
        let picker = ToolPicker(fixture: selection, onToolChange: {
            selection.events.append("transition:\(selection.tool.rawValue)")
        })
        for tool in [MediaTool.gifMaker, .textExtractor, .imageCompressor, .videoCompressor] {
            let previous = selection.tool
            selection.events = []
            picker.selectedToolBinding.wrappedValue = tool
            suite.expect(selection.events == ["transition:\(previous.rawValue)", "content:\(tool.rawValue)"],
                   "each tool change captures the old content for its transition before replacing the controls")
            selection.events = []
            picker.selectedToolBinding.wrappedValue = tool
            suite.expect(selection.events.isEmpty, "reselecting the current tool does not reset work or restart its animation")
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
                suite.expect(types(in: input).isEmpty,
                       "embedded media leaves file drops to the island's destination chooser")
            } else {
                // SwiftUI registers broad transport types and filters the
                // requested file URL type in its own drop coordinator.
                suite.expect(settle { !types(in: input).isEmpty },
                       "standalone media retains its native direct file drop target")
            }
        }
    }
}
