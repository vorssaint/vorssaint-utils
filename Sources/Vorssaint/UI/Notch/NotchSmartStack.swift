// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One card holding several faces, a swipe up or down apart, as a stack of
/// widgets does on the phone. A native paging scroll keeps the trackpad's own
/// momentum and interruption, and the island's swipe to close leaves a scroll
/// view alone, so swiping a card never closes the island.
struct NotchSmartStack<Face: Hashable, Content: View>: View {
    let faces: [Face]
    let height: CGFloat
    @ViewBuilder let content: (Face) -> Content
    /// The order the stack opened with. A face that becomes the most
    /// relevant while the island is open never moves the card under the
    /// pointer; only a face appearing or leaving rebuilds the order.
    @State private var order: [Face]
    @State private var shown: Face?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(faces: [Face], height: CGFloat, @ViewBuilder content: @escaping (Face) -> Content) {
        self.faces = faces
        self.height = height
        self.content = content
        _order = State(initialValue: faces)
    }

    var body: some View {
        stack.onChange(of: Set(faces)) { _, _ in order = faces }
    }

    @ViewBuilder private var stack: some View {
        let faces = Set(order) == Set(self.faces) ? order : self.faces
        if faces.count < 2, let only = faces.first {
            content(only).frame(height: height)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(faces, id: \.self) { face in
                        content(face).frame(height: height).id(face)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.never)
            .scrollPosition(id: $shown)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .trailing) { dots(faces) }
        }
    }

    /// Where the stack rests, as the phone's stack shows it: a dot per face,
    /// the current one lit. A click on a dot shows its face.
    private func dots(_ faces: [Face]) -> some View {
        let current = shown ?? faces.first
        return VStack(spacing: 4) {
            ForEach(faces, id: \.self) { face in
                Circle()
                    .fill(.white.opacity(face == current ? 0.9 : 0.3))
                    .frame(width: 4, height: 4)
                    .frame(width: 10, height: 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0)) { shown = face }
                    }
            }
        }
        .padding(.trailing, 3)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: current)
        .accessibilityHidden(true)
    }
}
