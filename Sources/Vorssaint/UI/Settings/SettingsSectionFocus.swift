// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

private struct SettingsSectionBounds {
    let anchor: Anchor<CGRect>
    let cornerRadius: CGFloat
    let padding: CGFloat
}

private struct SettingsSectionBoundsKey: PreferenceKey {
    static var defaultValue: [SettingsSectionAnchor: [SettingsSectionBounds]] = [:]

    static func reduce(value: inout Value, nextValue: () -> Value) {
        for (anchor, bounds) in nextValue() {
            value[anchor, default: []].append(contentsOf: bounds)
        }
    }
}

/// A Form distributes modifiers on a Section to its rows. Collect their
/// bounds so the landing highlight can frame the whole section once.
private struct SettingsSectionAnchorModifier: ViewModifier {
    let anchor: SettingsSectionAnchor
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .anchorPreference(key: SettingsSectionBoundsKey.self, value: .bounds) { bounds in
                [anchor: [SettingsSectionBounds(anchor: bounds, cornerRadius: cornerRadius,
                                                padding: padding)]]
            }
    }
}

private struct SettingsSectionFocusModifier: ViewModifier {
    let page: SettingsPage

    @ObservedObject private var router = SettingsRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedAnchor: SettingsSectionAnchor?
    @State private var lastFocusedAnchor: SettingsSectionAnchor?
    @State private var highlightID = UUID()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .overlayPreferenceValue(SettingsSectionBoundsKey.self) { sections in
                    GeometryReader { geometry in
                        if let anchor = lastFocusedAnchor,
                           let bounds = sections[anchor],
                           let first = bounds.first {
                            let boundsRect = bounds.dropFirst().reduce(geometry[first.anchor]) {
                                $0.union(geometry[$1.anchor])
                            }
                            let rect = boundsRect.insetBy(dx: -first.padding, dy: -first.padding)
                            RoundedRectangle(cornerRadius: first.cornerRadius, style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: first.cornerRadius, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2)
                                        .shadow(color: Color.accentColor.opacity(0.5), radius: 14)
                                }
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(focusedAnchor == anchor ? 1 : 0)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .onAppear {
                    consumePendingRequest(using: proxy)
                }
                .onChange(of: router.requestID) { _, _ in
                    consumePendingRequest(using: proxy)
                }
        }
    }

    private func consumePendingRequest(using proxy: ScrollViewProxy) {
        guard let request = router.pendingDestinationRequest,
              request.destination.page == page else { return }

        router.consumeDestinationRequest(id: request.id)
        highlightID = request.id
        guard let anchor = request.destination.sectionAnchor else {
            focusedAnchor = nil
            return
        }
        lastFocusedAnchor = anchor

        // A page-changing request publishes before the replacement Form has
        // completed layout. Retry once after the first run-loop turn because
        // grouped Forms can register their section IDs on the following pass.
        DispatchQueue.main.async {
            guard self.highlightID == request.id else { return }
            focus(anchor, using: proxy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard self.highlightID == request.id else { return }
                focus(anchor, using: proxy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    guard self.highlightID == request.id else { return }
                    if reduceMotion {
                        focusedAnchor = nil
                    } else {
                        withAnimation(.easeOut(duration: 0.4)) {
                            focusedAnchor = nil
                        }
                    }
                }
            }
        }
    }

    /// Centered, so the section lands in the middle of the eye line rather
    /// than at an edge of the window.
    private func focus(_ anchor: SettingsSectionAnchor, using proxy: ScrollViewProxy) {
        // These destinations render just the selected tool at the top.
        // Scrolling their newly created view twice only delays navigation.
        if page == .general || page == .energy {
            focusedAnchor = anchor
            return
        }
        if reduceMotion {
            proxy.scrollTo(anchor, anchor: .center)
            focusedAnchor = anchor
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(anchor, anchor: .center)
                focusedAnchor = anchor
            }
        }
    }
}

extension View {
    /// Marks a stable destination inside a Settings page. The corner radius
    /// is the destination's own, so the landing outline hugs it.
    func settingsSectionAnchor(_ anchor: SettingsSectionAnchor, cornerRadius: CGFloat = 7) -> some View {
        modifier(SettingsSectionAnchorModifier(anchor: anchor, cornerRadius: cornerRadius, padding: 0))
    }

    /// Grouped Forms inset their headers and rows from the section background.
    func settingsFormSectionAnchor(_ anchor: SettingsSectionAnchor) -> some View {
        modifier(SettingsSectionAnchorModifier(anchor: anchor, cornerRadius: 10, padding: 10))
    }

    /// Handles one-shot destination requests for one Settings page.
    func settingsSectionFocus(for page: SettingsPage) -> some View {
        modifier(SettingsSectionFocusModifier(page: page))
    }
}
