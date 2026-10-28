// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// AppKit-created windows don't consistently adopt an NSHostingController's
/// navigation title. Keep the real window title and native toolbar in sync.
struct SettingsWindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.title = title
        }
    }
}

/// SwiftUI exposes column visibility, but not the native pane's collapse
/// policy. Configure that policy without replacing its split-view delegate,
/// toolbar, sidebar search, or platform materials.
struct SettingsSidebarWidthRestorer: NSViewRepresentable {
    let width: CGFloat
    var defaults: UserDefaults = .standard

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.schedule(from: view, width: width)
    }

    func makeCoordinator() -> Coordinator { Coordinator(defaults: defaults) }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        private let defaults: UserDefaults
        private var hasRestored = false
        private var attempts = 0
        private var resizeObserver: NSObjectProtocol?

        init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        func schedule(from view: NSView, width: CGFloat) {
            guard !hasRestored, attempts < 8 else { return }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.restore(from: view, width: width)
            }
        }

        private func restore(from view: NSView, width: CGFloat) {
            guard !hasRestored else { return }
            attempts += 1
            guard let split = Self.enclosingSplitView(of: view),
                  split.bounds.width > 0,
                  let controller = split.delegate as? NSSplitViewController,
                  let sidebar = controller.splitViewItems.first,
                  let pane = split.arrangedSubviews.first else {
                schedule(from: view, width: width)
                return
            }
            sidebar.canCollapse = false
            sidebar.canCollapseFromWindowResize = false
            sidebar.minimumThickness = SettingsShellLayout.sidebarMinWidth
            sidebar.maximumThickness = SettingsShellLayout.sidebarMaxWidth

            split.layoutSubtreeIfNeeded()
            let target = SettingsShellLayout.clampedSidebarWidth(width)
            split.setPosition(target, ofDividerAt: 0)
            // The controller's content view is inset inside the pane on macOS 26.
            guard abs(pane.frame.width - target) < 1 else {
                schedule(from: view, width: width)
                return
            }
            hasRestored = true
            // Persist the native divider's settled width, not an initial
            // SwiftUI geometry proposal. No delayed write is lost on close.
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: split, queue: .main
            ) { [weak self, weak sidebar, weak pane] _ in
                guard let self, let sidebar, let pane, !sidebar.isCollapsed else { return }
                SettingsShellLayout.storeSidebarWidth(pane.frame.width, defaults: self.defaults)
            }
        }

        func stopObserving() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
        }

        private static func enclosingSplitView(of view: NSView) -> NSSplitView? {
            var parent = view.superview
            while let current = parent {
                if let split = current as? NSSplitView { return split }
                parent = current.superview
            }
            return nil
        }
    }
}

private struct SettingsSearchRowStyle: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected
                ? Color(appearsActive ? .alternateSelectedControlTextColor : .unemphasizedSelectedTextColor)
                : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Color(appearsActive ? .selectedContentBackgroundColor
                                             : .unemphasizedSelectedContentBackgroundColor)
                        : .clear)
            }
    }
}

extension View {
    func settingsSearchRowStyle(isSelected: Bool) -> some View {
        modifier(SettingsSearchRowStyle(isSelected: isSelected))
    }
}
