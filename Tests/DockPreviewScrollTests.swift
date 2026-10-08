// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The production panel is hosted offscreen with empty, same-sized cards.
/// Button doubles expose its real actions without sending input to the desktop.
enum DockPreviewScrollTests {
    struct SwitcherItem: Identifiable {
        let id: CGWindowID
        var windowID: CGWindowID? { id }
        var previewWindowID: CGWindowID? { nil }
        var appIcon: NSImage? { nil }
    }

    final class Model: ObservableObject {
        let windows = (1...12).map { SwitcherItem(id: CGWindowID($0)) }
        @Published var selectedWindowID: CGWindowID?
        func preview(_ item: SwitcherItem) { selectedWindowID = item.windowID }
        func select(_ offset: Int) -> CGWindowID? {
            selectedWindowID = DockPreviewSupport.adjacentWindowID(
                selectedWindowID: selectedWindowID, windowIDs: windows.map(\.id), offset: offset)
            return selectedWindowID
        }
    }

    struct Host: View {
        @ObservedObject var model: Model
        let orientation: DockPreviewOrientation
        let isPinned: Bool
        var body: some View {
            DockPreviewPanelContent(
                windows: model.windows, previews: [:], selectedWindowID: model.selectedWindowID,
                currentAppName: "Test", isPinned: isPinned, orientation: orientation,
                onPreview: model.preview,
                onEndPreview: { _ in if !isPinned { model.selectedWindowID = nil } },
                onCommit: { _ in }, onCloseWindow: { _ in }, onMiddleClick: { _ in },
                onToggleMinimized: { _ in }, onTogglePinned: {}, onClosePanel: {},
                onSelectPrevious: { model.select(-1) }, onSelectNext: { model.select(1) },
                onBeginDrag: { _ in }, onUpdateDrag: {}, onEndDrag: { _ in })
        }
    }

    struct DockPreviewCard: View {
        let window: SwitcherItem
        let preview: CGImage?
        let isSelected: Bool
        let isPanelPinned: Bool
        let onTogglePinned: () -> Void
        let closeActionTitle: String
        let onCommit: () -> Void
        let onClose: () -> Void
        let onMiddleClick: () -> Void
        let onToggleMinimized: () -> Void
        var body: some View {
            Color.clear.frame(width: DockPreviewSupport.cardWidth, height: DockPreviewSupport.cardHeight)
        }
    }

    struct HUDBackdrop: View {
        let cornerRadius: CGFloat
        let opacity: Double
        var body: some View { Color.clear }
    }
    struct NativeWindowDragHandle: View {
        var body: some View { Color.clear }
    }
    final class L10n: ObservableObject {
        static let shared = L10n()
        var s: L10n { self }
        let panelQuit = "Quit"
        let dockPreviewCloseWindow = "Close window"
        let dockPreviewUnpinPanel = "Unpin"
        let dockPreviewClosePanel = "Close panel"
        let dockPreviewPinned = "Pinned"
        let dockPreviewPreviousWindow = "Previous window"
        let dockPreviewNextWindow = "Next window"
    }
    static var buttonActions: [String: () -> Void] = [:]
    struct Button<Label: View>: View {
        let action: () -> Void
        let label: Label
        init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
            self.action = action
            self.label = label()
        }
        var body: some View { label }
        func help(_ title: String) -> Self {
            buttonActions[title] = action
            return self
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.prohibited)
            defer { NSApp.setActivationPolicy(previousPolicy) }
            for (orientation, pinned): (DockPreviewOrientation, Bool) in [
                (.bottom, false), (.left, false), (.right, false), (.bottom, true)
            ] {
                check(suite, orientation: orientation, pinned: pinned)
            }
        }
    }

    @MainActor private static func check(_ suite: TestSuite, orientation: DockPreviewOrientation, pinned: Bool) {
        let model = Model()
        let vertical = DockPreviewSupport.stacksVertically(orientation: orientation, isPinned: pinned)
        let size = CGSize(width: vertical ? DockPreviewSupport.cardWidth + 2 * DockPreviewSupport.panelPadding : 760,
                          height: vertical ? 560 : DockPreviewSupport.cardHeight + 2 * DockPreviewSupport.panelPadding
                            + (pinned ? DockPreviewSupport.panelHeaderHeight : 0))
        let hosting = NSHostingView(rootView: Host(model: model, orientation: orientation, isPinned: pinned))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            buttonActions.removeAll()
            window.close()
        }
        func settle() {
            let deadline = Date().addingTimeInterval(0.25)
            repeat {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
            } while Date() < deadline
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll($0) }.first
        }
        settle()
        guard let scroll = findScroll(hosting) else {
            suite.expect(false, "Dock preview must contain a native scroll view")
            return
        }
        let name = "Dock preview \(orientation), pinned=\(pinned)"
        let extent = vertical ? DockPreviewSupport.cardHeight : DockPreviewSupport.cardWidth
        for index in [2, 3, 4, 3, 2] {
            let offset = CGFloat(index - 1) * (extent + DockPreviewSupport.cardSpacing) + 35
            scroll.contentView.scroll(to: vertical ? NSPoint(x: 0, y: offset) : NSPoint(x: offset, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
            let before = scroll.contentView.bounds.origin
            model.preview(model.windows[index])
            settle()
            let after = scroll.contentView.bounds.origin
            suite.expect(model.selectedWindowID == model.windows[index].windowID,
                         "\(name): hover still highlights the window")
            suite.expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5,
                         "\(name): hover during scrolling must not move content from \(before) to \(after)")
        }
        if pinned {
            func navigate(_ title: String, expectedIndex: Int) {
                guard let action = buttonActions[title] else {
                    suite.expect(false, "\(name): missing navigation action \(title)")
                    return
                }
                action()
                settle()
                let clip = scroll.contentView.bounds
                let start = DockPreviewSupport.panelPadding
                    + CGFloat(expectedIndex) * (extent + DockPreviewSupport.cardSpacing)
                suite.expect(model.selectedWindowID == model.windows[expectedIndex].windowID,
                             "\(name): navigation selects window \(expectedIndex + 1)")
                suite.expect(start >= clip.minX - 0.5 && start + extent <= clip.maxX + 0.5,
                             "\(name): navigation reveals window \(expectedIndex + 1), including wraparound")
            }
            model.preview(model.windows[0])
            settle()
            navigate(L10n.shared.dockPreviewPreviousWindow, expectedIndex: 11)
            navigate(L10n.shared.dockPreviewNextWindow, expectedIndex: 0)
            navigate(L10n.shared.dockPreviewNextWindow, expectedIndex: 1)
            model.preview(model.windows[10])
            settle()
            navigate(L10n.shared.dockPreviewNextWindow, expectedIndex: 11)
        }
        suite.expect(!window.isVisible, "\(name): tests never show a window")
    }
}
