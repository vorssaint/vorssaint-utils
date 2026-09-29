// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A retained SwiftUI hierarchy does not disappear when its NSWindow closes.
/// Report visibility asynchronously so clients can suspend live previews
/// without changing SwiftUI state during a layout pass.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> WindowVisibilityView { WindowVisibilityView() }
    func updateNSView(_ view: WindowVisibilityView, context: Context) {
        view.onChange = onChange
        view.reportVisibility()
    }
    static func dismantleNSView(_ view: WindowVisibilityView, coordinator: ()) { view.stop() }
}

final class WindowVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var reported: Bool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        pending?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.reportVisibility()
            }
        }
        reportVisibility()
    }
    override func viewDidHide() { super.viewDidHide(); reportVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); reportVisibility() }

    func reportVisibility() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let onChange = self.onChange else { return }
            let visible = !self.isHiddenOrHasHiddenAncestor
                && self.window?.isVisible == true && self.window?.occlusionState.contains(.visible) == true
            guard self.reported != visible else { return }
            self.reported = visible
            onChange(visible)
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        onChange = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
