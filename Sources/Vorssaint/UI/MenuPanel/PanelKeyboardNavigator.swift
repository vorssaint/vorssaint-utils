// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Where keyboard focus currently rests in the menu panel. `nil` until the
/// first navigation key press, so mouse-only use never shows a focus ring.
enum PanelFocusTarget: Equatable {
    /// Panel chrome outside the tab bar and the scrollable content — the
    /// update banner, the back button in metric detail, the footer — which
    /// has a fixed position instead of a runtime-tracked one.
    case chrome(PanelChromeID)
    case tab(PanelSectionID)
    case row(PanelRowID)
}

/// Identity for one piece of panel chrome. Unlike rows, chrome is never
/// reordered or hidden by the user, so its position is just the order
/// `MenuPanelView` lists it in, not something measured at runtime.
enum PanelChromeID: Hashable {
    case updateBanner
    case headerFeedback
    case metricBack
    case footerSettings
    case footerQuit
}

/// Stable identity for a keyboard-navigable row, scoped by section so two
/// sections can reuse the same local id (an enum case, an index...) without
/// colliding.
struct PanelRowID: Hashable {
    let section: PanelSectionID
    let local: AnyHashable

    init(_ section: PanelSectionID, _ local: AnyHashable) {
        self.section = section
        self.local = local
    }
}

/// Which way an arrow-key press adjusts a row's value.
enum PanelAdjustDirection {
    case decrease, increase
}

/// What a row does in response to a key, wired up through `.panelKeyboardRow`.
/// Everything but `activate` is optional — a plain action or toggle row only
/// needs that one. `adjust`/`enter`/`exit` return whether they actually did
/// something, so a row at its limit (or with nowhere to go) hands the key
/// back instead of silently swallowing it.
struct PanelRowActions {
    var activate: (() -> Void)?
    var adjust: ((PanelAdjustDirection, _ fine: Bool) -> Bool)?
    var enter: (() -> Bool)?
    var exit: (() -> Bool)?

    init(activate: (() -> Void)? = nil,
         adjust: ((PanelAdjustDirection, _ fine: Bool) -> Bool)? = nil,
         enter: (() -> Bool)? = nil,
         exit: (() -> Bool)? = nil) {
        self.activate = activate
        self.adjust = adjust
        self.enter = enter
        self.exit = exit
    }
}

/// A level pushed onto the panel's keyboard navigation stack: metric detail
/// or a hosted utility sub-panel. Escape pops the top one before it ever
/// reaches the popover itself.
enum PanelLevelID: Hashable {
    case metricDetail
    case hostedUtility
}

/// Drives keyboard navigation of the menu panel: the section tabs and the
/// rows inside the active section's content. An `NSEvent` local key monitor
/// in `AppDelegate` feeds it every key press (the house pattern for keyboard
/// navigation in this app — see `CommandBarService`, `QuickLauncherService`);
/// SwiftUI only reads `focus` back to render the highlight.
///
/// Row order and on-screen position are never hand-maintained: sections and
/// items are both user-reorderable and hideable, so `configureRowOrder` is
/// fed from real layout (see `panelKeyboardRow` and the row-order collector
/// in `MenuPanelView`).
final class PanelKeyboardNavigator: ObservableObject {
    static let shared = PanelKeyboardNavigator()

    /// The named coordinate space rows measure their on-screen position in,
    /// shared between `panelKeyboardRow` and the collector that sorts them.
    static let rowCoordinateSpace = "panelKeyboardRows"

    @Published private(set) var focus: PanelFocusTarget?

    // Kept current by MenuPanelView every time the visible tabs or the
    // active section change.
    private var tabs: [PanelSectionID] = []
    private var activeTab: PanelSectionID?
    private var onSelectTab: ((PanelSectionID) -> Void)?

    // Kept current by the row registration modifier and its order collector.
    private var rowOrder: [PanelRowID] = []
    private var rowFrames: [PanelRowID: CGRect] = [:]
    private var rowActions: [PanelRowID: PanelRowActions] = [:]

    // Kept current by MenuPanelView: chrome before and after the tab-bar/row
    // content, in the fixed order it actually appears on screen.
    private var leadingChrome: [PanelChromeID] = []
    private var trailingChrome: [PanelChromeID] = []
    private var chromeActivate: [PanelChromeID: () -> Void] = [:]

    private var levels: [(id: PanelLevelID, dismiss: () -> Void)] = []

    private init() {}

    // MARK: - Tabs

    func configureTabs(_ tabs: [PanelSectionID], active: PanelSectionID,
                       select: @escaping (PanelSectionID) -> Void) {
        self.tabs = tabs
        activeTab = active
        onSelectTab = select
        // Any tab focus snaps to wherever the active tab actually is, so a
        // mouse click while keyboard focus is showing moves the ring instead
        // of leaving it stranded on a tab that is no longer selected.
        if case .tab = focus {
            focus = tabs.contains(active) ? .tab(active) : nil
        }
    }

    /// Programmatic focus for callers outside the keyboard-nav loop (e.g. a
    /// menu-bar icon deep-linking into a section). The caller updates the
    /// selection itself; this only moves the ring to match.
    func focusTab(_ id: PanelSectionID) {
        focus = .tab(id)
    }

    func clearFocus() {
        focus = nil
    }

    // MARK: - Rows

    func registerRow(_ id: PanelRowID, actions: PanelRowActions) {
        rowActions[id] = actions
    }

    func unregisterRow(_ id: PanelRowID) {
        rowActions.removeValue(forKey: id)
        if case .row(let focused)? = focus, focused == id {
            focus = fallbackFocus()
        }
    }

    /// The rows in the section currently on screen, sorted top to bottom by
    /// real on-screen position, with the frame each measured in
    /// `rowCoordinateSpace` — the coordinate space of the scroll view's own
    /// document view, so `OverlayScrollView` can scroll a row into view
    /// without knowing anything about the panel's content.
    func configureRowOrder(_ rows: [(id: PanelRowID, frame: CGRect)]) {
        rowOrder = rows.map(\.id)
        rowFrames = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.frame) })
        if case .row(let focused)? = focus, !rowOrder.contains(focused) {
            focus = fallbackFocus()
        }
    }

    func frame(for row: PanelRowID) -> CGRect? {
        rowFrames[row]
    }

    /// Where focus lands when whatever it was on disappears out from under
    /// it: the active tab if there is one to show, otherwise nowhere.
    private func fallbackFocus() -> PanelFocusTarget? {
        guard let activeTab, tabs.contains(activeTab) else { return nil }
        return .tab(activeTab)
    }

    // MARK: - Chrome

    /// The fixed chrome before and after the tab bar/content, in on-screen
    /// order — the update banner and header feedback button lead; the
    /// footer trails; metric detail's back button takes the tab bar's spot
    /// at the front instead.
    func configureChrome(leading: [PanelChromeID], trailing: [PanelChromeID]) {
        leadingChrome = leading
        trailingChrome = trailing
        if case .chrome(let id)? = focus, !leading.contains(id), !trailing.contains(id) {
            focus = fallbackFocus()
        }
    }

    func registerChromeAction(_ id: PanelChromeID, activate: @escaping () -> Void) {
        chromeActivate[id] = activate
    }

    func unregisterChromeAction(_ id: PanelChromeID) {
        chromeActivate.removeValue(forKey: id)
        if case .chrome(let focused)? = focus, focused == id {
            focus = fallbackFocus()
        }
    }

    // MARK: - Levels

    func pushLevel(_ id: PanelLevelID, dismiss: @escaping () -> Void) {
        levels.append((id, dismiss))
    }

    func popLevel(_ id: PanelLevelID) {
        levels.removeAll { $0.id == id }
    }

    /// Escape: pops the top level (if any) and returns true; returns false
    /// once the stack is empty, so the caller closes the popover only then.
    @discardableResult
    func popTopLevel() -> Bool {
        guard let top = levels.last else { return false }
        top.dismiss()
        return true
    }

    // MARK: - Keys

    /// Handles one key-down; returns true if the panel consumed it.
    ///
    /// Tab is the one key that engages keyboard navigation from a standing
    /// start (focus nil): nothing else in the popover has a working native
    /// key-view loop for it to compete with. Arrows and Return/Space defer
    /// instead while focus is nil, so a native control the user just
    /// click-focused (a slider, a stepper) keeps its own arrow keys until
    /// the person actually starts navigating with the keyboard.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let fine = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case kVK_Tab:
            moveTab(backward: fine)
            return true
        case kVK_LeftArrow:
            guard focus != nil else { return false }
            return handleLeft(fine: fine)
        case kVK_RightArrow:
            guard focus != nil else { return false }
            return handleRight(fine: fine)
        case kVK_DownArrow:
            guard focus != nil else { return false }
            return handleDown()
        case kVK_UpArrow:
            guard focus != nil else { return false }
            return handleUp()
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            guard focus != nil else { return false }
            return activateFocused()
        default:
            return false
        }
    }

    /// The whole panel, top to bottom, as one line: leading chrome, the tab
    /// bar (one stop, wherever `activeTab` is — absent in metric detail,
    /// where the back button takes its place in `leadingChrome`), the rows
    /// in their real order, then trailing chrome. Up/Down walk this; Left/
    /// Right only ever act within one stop (cycling tabs, adjusting a row).
    private var sequence: [PanelFocusTarget] {
        var steps = leadingChrome.map { PanelFocusTarget.chrome($0) }
        if !tabs.isEmpty, let activeTab {
            steps.append(.tab(activeTab))
        }
        steps.append(contentsOf: rowOrder.map { .row($0) })
        steps.append(contentsOf: trailingChrome.map { .chrome($0) })
        return steps
    }

    private func handleLeft(fine: Bool) -> Bool {
        switch focus {
        case nil, .tab:
            moveTab(backward: true)
            return true
        case .chrome:
            return true
        case .row(let id):
            guard let actions = rowActions[id] else { return true }
            if let adjust = actions.adjust { return adjust(.decrease, fine) }
            if let exit = actions.exit { return exit() }
            return true
        }
    }

    private func handleRight(fine: Bool) -> Bool {
        switch focus {
        case nil, .tab:
            moveTab(backward: false)
            return true
        case .chrome:
            return true
        case .row(let id):
            guard let actions = rowActions[id] else { return true }
            if let adjust = actions.adjust { return adjust(.increase, fine) }
            if let enter = actions.enter { return enter() }
            return true
        }
    }

    private func handleDown() -> Bool {
        let steps = sequence
        guard !steps.isEmpty else { return false }
        guard let focus, let index = steps.firstIndex(of: focus) else {
            self.focus = steps.first
            return true
        }
        if index + 1 < steps.count {
            self.focus = steps[index + 1]
        }
        return true
    }

    private func handleUp() -> Bool {
        let steps = sequence
        guard !steps.isEmpty else { return false }
        guard let focus, let index = steps.firstIndex(of: focus) else {
            self.focus = steps.first
            return true
        }
        if index > 0 {
            self.focus = steps[index - 1]
        }
        return true
    }

    private func moveTab(backward: Bool) {
        guard !tabs.isEmpty else { return }
        let baseID: PanelSectionID
        switch focus {
        case .tab(let id): baseID = id
        case .row(let row): baseID = row.section
        case .chrome, nil: baseID = activeTab ?? tabs[0]
        }
        guard let index = tabs.firstIndex(of: baseID) else {
            if let activeTab, tabs.contains(activeTab) { selectTab(activeTab) }
            return
        }
        let count = tabs.count
        let nextIndex = ((backward ? index - 1 : index + 1) % count + count) % count
        selectTab(tabs[nextIndex])
    }

    private func selectTab(_ id: PanelSectionID) {
        focus = .tab(id)
        activeTab = id
        onSelectTab?(id)
    }

    private func activateFocused() -> Bool {
        switch focus {
        case .chrome(let id):
            chromeActivate[id]?()
            return true
        case .tab(let id):
            selectTab(id)
            return true
        case .row(let id):
            rowActions[id]?.activate?()
            return true
        case nil:
            return false
        }
    }
}

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

private struct PanelRowGeometry: Equatable {
    let id: PanelRowID
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
    let id: PanelRowID
    let actions: PanelRowActions
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isMenuPanelHost {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PanelRowGeometryPreferenceKey.self,
                            value: [PanelRowGeometry(
                                id: id,
                                frame: proxy.frame(in: .named(PanelKeyboardNavigator.rowCoordinateSpace)))])
                    }
                )
                .panelFocusRing(navigator.focus == .row(id), cornerRadius: cornerRadius)
                .accessibilityAddTraits(navigator.focus == .row(id) ? .isSelected : [])
                .onAppear { navigator.registerRow(id, actions: actions) }
                .onDisappear { navigator.unregisterRow(id) }
        } else {
            content
        }
    }
}

private struct PanelKeyboardRowOrderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: PanelKeyboardNavigator.rowCoordinateSpace)
            .onPreferenceChange(PanelRowGeometryPreferenceKey.self) { rows in
                let ordered = rows.sorted { $0.frame.minY < $1.frame.minY }.map { ($0.id, $0.frame) }
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

    /// Marks the root of a section's scrollable content: establishes the
    /// coordinate space rows measure their position in, and reports the
    /// resulting top-to-bottom order to the navigator.
    func trackPanelKeyboardRowOrder() -> some View {
        modifier(PanelKeyboardRowOrderModifier())
    }
}
