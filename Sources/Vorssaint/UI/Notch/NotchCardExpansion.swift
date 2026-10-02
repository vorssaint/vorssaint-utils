// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchExpansionActions {
    let selectedID: String?
    let open: (String) -> Void
    let close: () -> Void
}

private struct NotchExpansionActionsKey: EnvironmentKey {
    static let defaultValue: NotchExpansionActions? = nil
}

extension EnvironmentValues {
    var notchExpansionActions: NotchExpansionActions? {
        get { self[NotchExpansionActionsKey.self] }
        set { self[NotchExpansionActionsKey.self] = newValue }
    }
}

private struct NotchExpansionSource {
    let anchor: Anchor<CGRect>
    let title: String
    let preferredSize: CGSize
    let surface: NotchControlSurface
    let header: AnyView?
    let content: AnyView
}

private struct NotchExpansionSourcesKey: PreferenceKey {
    static let defaultValue: [String: NotchExpansionSource] = [:]
    static func reduce(value: inout [String: NotchExpansionSource],
                       nextValue: () -> [String: NotchExpansionSource]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct NotchExpandableModifier<Expanded: View>: ViewModifier {
    let id: String
    let title: String
    let preferredSize: CGSize
    let surface: NotchControlSurface
    let header: AnyView?
    let expanded: Expanded
    @Environment(\.notchExpansionActions) private var actions

    func body(content: Content) -> some View {
        content.opacity(actions?.selectedID == id ? 0 : 1)
            .anchorPreference(key: NotchExpansionSourcesKey.self, value: .bounds) { anchor in
                guard actions != nil else { return [:] }
                return [id: NotchExpansionSource(anchor: anchor, title: title,
                                                 preferredSize: preferredSize, surface: surface,
                                                 header: header, content: AnyView(expanded))]
            }
    }
}

extension View {
    func notchExpandable<Expanded: View>(id: String, title: String,
                                         preferredSize: CGSize = CGSize(width: 360, height: 240),
                                         surface: NotchControlSurface = NotchControlSurface(cornerRadius: 18),
                                         header: AnyView? = nil,
                                         @ViewBuilder expanded: () -> Expanded) -> some View {
        modifier(NotchExpandableModifier(id: id, title: title, preferredSize: preferredSize,
                                         surface: surface, header: header, expanded: expanded()))
    }

    /// Expand an information card; nested buttons keep their own actions.
    func notchExpansionTap(id: String, enabled: Bool = true) -> some View {
        modifier(NotchExpansionTap(id: id, enabled: enabled))
    }

    func notchCardHover(enabled: Bool = true) -> some View { modifier(NotchCardHover(applies: enabled)) }
}

private struct NotchExpansionTap: ViewModifier {
    let id: String
    var enabled = true
    @Environment(\.notchExpansionActions) private var actions

    @ViewBuilder func body(content: Content) -> some View {
        if let actions, enabled {
            content.contentShape(Rectangle())
                .onTapGesture { actions.open(id) }
                .accessibilityAction(named: Text(L10n.shared.s.menuShowAll)) { actions.open(id) }
        } else {
            content
        }
    }
}

/// An explicit action keeps previewing separate from pasting, opening or deleting.
struct NotchExpandButton: View {
    let id: String
    let title: String
    var hiddenCount: Int? = nil
    var onOpen: (() -> Void)? = nil
    @Environment(\.notchExpansionActions) private var actions
    @FocusState private var focused: Bool

    var body: some View {
        if let actions {
            Button {
                actions.open(id)
                onOpen?()
            } label: {
                Group {
                    if let hiddenCount {
                        Text("+\(hiddenCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .background(.white.opacity(0.1), in: Capsule())
                    } else {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(lifts: false))
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier("notch.expand.\(id)")
            .focused($focused)
            .onChange(of: actions.selectedID) { old, new in
                if old == id, new == nil { focused = true }
            }
        }
    }
}

/// One presenter per page; sources publish their current content rather than a
/// snapshot captured when the button was pressed.
struct NotchCardExpansionHost<Content: View>: View {
    let module: NotchModule
    let size: CGSize
    @ViewBuilder let content: Content
    @State private var selectedID: String?
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var closeFocused: Bool

    var body: some View {
        content
            .disabled(selectedID != nil)
            .accessibilityHidden(selectedID != nil)
            .frame(width: size.width, height: size.height, alignment: .top)
            .overlayPreferenceValue(NotchExpansionSourcesKey.self) { sources in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        if let selectedID, let source = sources[selectedID] {
                            let card = geometry[source.anchor]
                            let frame = NotchCardExpansionSupport.frame(card: card, page: size,
                                                                      preferred: source.preferredSize)
                            Color.black.opacity(0.3)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: close)
                                .accessibilityHidden(true)
                                .transition(.opacity)
                                .zIndex(0)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    if let header = source.header {
                                        header
                                    } else {
                                        Text(source.title).font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    NotchIconButton(symbol: "xmark", title: l10n.s.menuClose, action: close)
                                        .focused($closeFocused)
                                }
                                .frame(height: 24)
                                source.content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .padding(12)
                            .frame(width: frame.width, height: frame.height)
                            .modifier(source.surface.elevated())
                            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                            .position(x: frame.midX, y: frame.midY)
                            .transition(reduceMotion ? .opacity : .modifier(
                                active: NotchBubbleOrigin(card: card, expanded: frame, progress: 0),
                                identity: NotchBubbleOrigin(card: card, expanded: frame, progress: 1))
                                .combined(with: .opacity))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("notch.expanded.\(selectedID)")
                            .focusSection()
                            .onExitCommand(perform: close)
                            .onAppear { closeFocused = true }
                            .onChange(of: card.intersects(CGRect(origin: .zero, size: size)), initial: true) { _, visible in
                                if !visible { close() }
                            }
                            .id(selectedID)
                            .zIndex(1)
                        }
                        Color.clear.allowsHitTesting(false)
                            .onChange(of: sources.keys.sorted()) { _, ids in
                                if let selectedID, !ids.contains(selectedID) { close() }
                            }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
                .clipped()
                // The idle presenter must pass pointer events through to its cards.
                .allowsHitTesting(selectedID != nil)
            }
            .environment(\.notchExpansionActions,
                         NotchExpansionActions(selectedID: selectedID, open: open, close: close))
            .onChange(of: selectedID) { _, selected in
                if !preview { NotchService.shared.setPageLayer(module, close: selected == nil ? nil : close) }
            }
            .onDisappear {
                if !preview, selectedID != nil { NotchService.shared.setPageLayer(module, close: nil) }
                selectedID = nil
            }
    }

    private func open(_ id: String) {
        let spring = NotchMotion.growingWidth
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: spring.duration, bounce: spring.bounce)) {
            selectedID = id
        }
    }

    private func close() {
        guard selectedID != nil else { return }
        let spring = NotchMotion.shrinkingWidth
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: spring.duration, bounce: spring.bounce)) {
            selectedID = nil
        }
    }
}

/// The positioned reader occupies a page-sized layout box. Map its actual
/// bubble frame rather than scaling around the centre of that layout box.
private struct NotchBubbleOrigin: GeometryEffect {
    let card: CGRect
    let expanded: CGRect
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(NotchCardExpansionSupport.transitionTransform(card: card, expanded: expanded,
                                                                          progress: progress))
    }
}

private struct NotchCardHover: ViewModifier {
    var applies = true
    @AppStorage(DefaultsKey.notchCardHoverEnabled) private var enabled = true
    @Environment(\.notchPresentation) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchExpansionActions) private var expansion
    @State private var hovered = false

    func body(content: Content) -> some View {
        let active = applies && presentation && enabled && hovered && expansion?.selectedID == nil
        content
            .scaleEffect(NotchCardExpansionSupport.hoverScale(enabled: active, hovered: hovered, reduceMotion: reduceMotion))
            .shadow(color: .black.opacity(active ? 0.22 : 0), radius: active ? 7 : 0, y: active ? 3 : 0)
            .zIndex(active ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(duration: NotchMotion.growingWidth.duration,
                                                   bounce: NotchMotion.growingWidth.bounce), value: active)
            .onHover { hovered = $0 }
    }
}
