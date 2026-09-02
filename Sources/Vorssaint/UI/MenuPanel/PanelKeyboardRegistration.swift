// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

// The SwiftUI half of panel keyboard navigation: the environment that scopes
// it to the popover, and the modifiers rows and chrome register themselves
// through. Kept apart from the navigator itself so the navigator can compile
// into the standalone test harness, which has no view layer.

// MARK: - Panel host scoping

/// True only within the popover panel's own view tree. Several components
/// instrumented for keyboard navigation (`KeepAwakeIconPicker`,
/// `AppPickerView`, `AppUpdatesListView`, `HomebrewOperationStatusView`, and
/// others) are also hosted in Settings or a standalone window, which can be
/// open at the same time as the panel — `AppDelegate.shouldDismissPopover`
/// deliberately allows that. `PanelKeyboardRowModifier` and
/// `PanelKeyboardChromeModifier` read this to become no-ops outside the
/// panel, so a Settings/standalone instance of a shared view never
/// registers into (or draws the focus ring for) the panel's navigator —
/// gating per view tree rather than on `popover.isShown`, which can't tell
/// the two hosts apart when both are on screen.
private struct IsMenuPanelHostKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isMenuPanelHost: Bool {
        get { self[IsMenuPanelHostKey.self] }
        set { self[IsMenuPanelHostKey.self] = newValue }
    }
}

extension View {
    /// Marks the root of the popover panel's own content so the keyboard-nav
    /// row/chrome modifiers know they're inside it. Set once, in
    /// `MenuPanelView`.
    func markMenuPanelHost() -> some View {
        environment(\.isMenuPanelHost, true)
    }
}

// MARK: - Row registration

/// One entry in the layout-derived row order: either a single measured row,
/// or a whole lazy list contributing its rows in data order at the position
/// its container occupies. A `LazyVStack` only builds the rows it can show, so
/// it reports the order itself instead of leaving the collector to infer one
/// from frames the rows currently off screen do not have.
private struct PanelRowGeometry: Equatable {
    let ids: [PanelRowID]
    let frame: CGRect
}

private struct PanelRowGeometryPreferenceKey: PreferenceKey {
    static var defaultValue: [PanelRowGeometry] = []

    static func reduce(value: inout [PanelRowGeometry], nextValue: () -> [PanelRowGeometry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct PanelKeyboardRowModifier: ViewModifier {
    @ObservedObject private var navigator = PanelKeyboardNavigator.shared
    @Environment(\.isMenuPanelHost) private var isMenuPanelHost
    @Environment(\.isInPanelKeyboardRowList) private var isInRowList
    let id: PanelRowID
    let actions: PanelRowActions
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isMenuPanelHost {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PanelRowGeometryPreferenceKey.self,
                                               value: registeredGeometry(proxy))
                    }
                )
                .panelFocusRing(navigator.focus == .row(id), cornerRadius: cornerRadius)
                .accessibilityAddTraits(navigator.focus == .row(id) ? .isSelected : [])
                .onDisappear { navigator.unregisterRow(id) }
        } else {
            content
        }
    }

    /// Re-registers the row on every layout pass and hands back its geometry.
    /// `onAppear` fires once, so registering there would freeze the actions a
    /// row was built with — anything they gate on live state (a slider while
    /// its display is pending, a button that becomes enabled later) would keep
    /// answering for the first render forever.
    ///
    /// Inside a lazy list the row contributes no frame of its own: the list
    /// reports the whole order at its container's position, and a row scrolled
    /// out of the inner scroll view has no meaningful place in the panel's
    /// coordinate space anyway.
    private func registeredGeometry(_ proxy: GeometryProxy) -> [PanelRowGeometry] {
        navigator.registerRow(id, actions: actions)
        guard !isInRowList else { return [] }
        return [PanelRowGeometry(
            ids: [id],
            frame: proxy.frame(in: .named(PanelKeyboardNavigator.rowCoordinateSpace)))]
    }
}

/// Set on the rows inside a `panelKeyboardRowList` so they leave the ordering
/// to their container.
private struct IsInPanelKeyboardRowListKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var isInPanelKeyboardRowList: Bool {
        get { self[IsInPanelKeyboardRowListKey.self] }
        set { self[IsInPanelKeyboardRowListKey.self] = newValue }
    }
}

private struct PanelKeyboardRowListModifier: ViewModifier {
    @Environment(\.isMenuPanelHost) private var isMenuPanelHost
    let ids: [PanelRowID]

    func body(content: Content) -> some View {
        if isMenuPanelHost {
            content
                .environment(\.isInPanelKeyboardRowList, true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PanelRowGeometryPreferenceKey.self,
                            value: [PanelRowGeometry(
                                ids: ids,
                                frame: proxy.frame(in: .named(PanelKeyboardNavigator.rowCoordinateSpace)))])
                    }
                )
        } else {
            content
        }
    }
}

private struct PanelKeyboardRowOrderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: PanelKeyboardNavigator.rowCoordinateSpace)
            .onPreferenceChange(PanelRowGeometryPreferenceKey.self) { entries in
                // A list's rows all take their container's frame: the panel's
                // own scroll view only ever needs to bring the list into view,
                // and the list scrolls to the focused row from the inside.
                let ordered = entries
                    .sorted { $0.frame.minY < $1.frame.minY }
                    .flatMap { entry in entry.ids.map { ($0, entry.frame) } }
                PanelKeyboardNavigator.shared.configureRowOrder(ordered)
            }
    }
}

private struct PanelKeyboardChromeModifier: ViewModifier {
    @ObservedObject private var navigator = PanelKeyboardNavigator.shared
    @Environment(\.isMenuPanelHost) private var isMenuPanelHost
    let id: PanelChromeID
    let activate: () -> Void
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isMenuPanelHost {
            content
                .panelFocusRing(navigator.focus == .chrome(id), cornerRadius: cornerRadius)
                .accessibilityAddTraits(navigator.focus == .chrome(id) ? .isSelected : [])
                .onAppear { navigator.registerChromeAction(id, activate: activate) }
                .onDisappear { navigator.unregisterChromeAction(id) }
        } else {
            content
        }
    }
}

extension View {
    /// Registers this view as a fixed-position piece of panel chrome (not a
    /// row — no runtime order to track). `MenuPanelView` lists chrome ids in
    /// `configureChrome` in the order they actually appear on screen.
    func panelKeyboardChrome(_ id: PanelChromeID, activate: @escaping () -> Void, cornerRadius: CGFloat = 8) -> some View {
        modifier(PanelKeyboardChromeModifier(id: id, activate: activate, cornerRadius: cornerRadius))
    }

    /// Registers this view as a keyboard-navigable row. `id` must be stable
    /// and unique within its section; `actions` says what Return/Space and
    /// the arrow keys do to it.
    func panelKeyboardRow(_ id: PanelRowID, actions: PanelRowActions, cornerRadius: CGFloat = 8) -> some View {
        modifier(PanelKeyboardRowModifier(id: id, actions: actions, cornerRadius: cornerRadius))
    }

    /// Same as above, for a shared component (a picker tile, a toggle row...)
    /// that is also hosted somewhere outside the panel — Settings, typically
    /// — and should only register when it actually has a row identity to use.
    @ViewBuilder
    func panelKeyboardRow(_ id: PanelRowID?, actions: PanelRowActions, cornerRadius: CGFloat = 8) -> some View {
        if let id {
            modifier(PanelKeyboardRowModifier(id: id, actions: actions, cornerRadius: cornerRadius))
        } else {
            self
        }
    }

    /// Marks a lazy list of keyboard rows, in the order its data is in. A
    /// `LazyVStack` builds only the rows it can show, so the order cannot come
    /// from measured frames the way a hand-laid section's does — the list
    /// states it once here and its rows stop reporting positions of their own.
    /// Pair it with a `ScrollViewReader` that scrolls the focused row into
    /// view, which is also what builds a row the keyboard reaches before the
    /// list has.
    func panelKeyboardRowList(_ ids: [PanelRowID]) -> some View {
        modifier(PanelKeyboardRowListModifier(ids: ids))
    }

    /// Marks the root of a section's scrollable content: establishes the
    /// coordinate space rows measure their position in, and reports the
    /// resulting top-to-bottom order to the navigator.
    func trackPanelKeyboardRowOrder() -> some View {
        modifier(PanelKeyboardRowOrderModifier())
    }
}
