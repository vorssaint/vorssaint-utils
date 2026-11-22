// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The island's own outline at whatever size it is drawn: its shoulders and
/// bottom corners follow the height as the real island's do, so the corners
/// stay round the whole way as it grows and shrinks.
struct NotchLiveShape: Shape {
    func path(in rect: CGRect) -> Path {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: rect.height)).path(in: rect)
    }
}

/// An island that opens from its resting size, as the real one does: the
/// width and height each follow the island's own springs (a little bounce
/// growing, none shrinking), the outline keeps its true corners throughout,
/// and the content, laid out at its final size, fades in once there is room
/// and out before the island closes. It hangs from the top edge of its
/// window, which is clear, so only the black shape takes clicks.
struct NotchMorphSurface<Content: View>: View {
    let open: Bool
    let collapsed: CGSize
    let expanded: CGSize
    @ViewBuilder let content: () -> Content

    @State private var drawn = false
    @State private var grown = false
    @State private var contentShown = false

    private func spring(_ motion: NotchMotion.Spring) -> Animation {
        .spring(duration: motion.duration, bounce: motion.bounce)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if drawn {
                NotchLiveShape().fill(.black)
                    .overlay(alignment: .top) {
                        content()
                            .frame(width: expanded.width, height: expanded.height, alignment: .top)
                            .opacity(contentShown ? 1 : 0)
                            .animation(.easeOut(duration: contentShown ? 0.2 : 0.12), value: contentShown)
                    }
                    .clipShape(NotchLiveShape())
                    .frame(width: grown ? expanded.width : collapsed.width)
                    .animation(spring(grown ? NotchMotion.growingWidth : NotchMotion.shrinkingWidth), value: grown)
                    .frame(height: grown ? expanded.height : collapsed.height)
                    .animation(spring(grown ? NotchMotion.growingHeight : NotchMotion.shrinkingHeight), value: grown)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if open { drawn = true; grown = true; contentShown = true } }
        .onChange(of: open) { _, wanted in wanted ? present() : dismiss() }
    }

    private func present() {
        drawn = true
        // One turn at the resting size, then the growth, so it springs from the camera.
        DispatchQueue.main.async {
            grown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if open { contentShown = true } }
        }
    }

    private func dismiss() {
        contentShown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard !open else { return }
            grown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.shrinkingWidth.duration + 0.15) {
                if !open { drawn = false }
            }
        }
    }
}
