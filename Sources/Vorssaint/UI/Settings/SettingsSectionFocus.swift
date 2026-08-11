// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

private struct FocusedSettingsSectionAnchorKey: EnvironmentKey {
    static let defaultValue: SettingsSectionAnchor? = nil
}

private extension EnvironmentValues {
    var focusedSettingsSectionAnchor: SettingsSectionAnchor? {
        get { self[FocusedSettingsSectionAnchorKey.self] }
        set { self[FocusedSettingsSectionAnchorKey.self] = newValue }
    }
}

private struct SettingsSectionAnchorModifier: ViewModifier {
    let anchor: SettingsSectionAnchor
    @Environment(\.focusedSettingsSectionAnchor) private var focusedAnchor

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(focusedAnchor == anchor ? 0.10 : 0))
                    .allowsHitTesting(false)
            }
    }
}

private struct SettingsSectionFocusModifier: ViewModifier {
    let page: SettingsPage

    @ObservedObject private var router = SettingsRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedAnchor: SettingsSectionAnchor?
    @State private var highlightID = UUID()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.focusedSettingsSectionAnchor, focusedAnchor)
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

        // A page-changing request publishes before the replacement Form has
        // completed layout. Retry once after the first run-loop turn because
        // grouped Forms can register their section IDs on the following pass.
        DispatchQueue.main.async {
            guard self.highlightID == request.id else { return }
            focus(anchor, using: proxy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard self.highlightID == request.id else { return }
                focus(anchor, using: proxy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard self.highlightID == request.id else { return }
                    if reduceMotion {
                        focusedAnchor = nil
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) {
                            focusedAnchor = nil
                        }
                    }
                }
            }
        }
    }

    private func focus(_ anchor: SettingsSectionAnchor, using proxy: ScrollViewProxy) {
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
    /// Marks a stable destination inside a Settings page.
    func settingsSectionAnchor(_ anchor: SettingsSectionAnchor) -> some View {
        modifier(SettingsSectionAnchorModifier(anchor: anchor))
    }

    /// Handles one-shot destination requests for one Settings page.
    func settingsSectionFocus(for page: SettingsPage) -> some View {
        modifier(SettingsSectionFocusModifier(page: page))
    }
}
