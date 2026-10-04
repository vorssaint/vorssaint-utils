// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A scrolling page fades where more of it lies beyond an edge, so a card is
/// never sliced by a hard line. At rest at the start there is nothing to fade,
/// and the last row at the end stays clear. Earlier systems keep the hard edge.
struct NotchScrollEdgeFade: ViewModifier {
    var axis: Axis = .vertical
    var length: CGFloat = 16
    @State private var beyondStart = false
    @State private var beyondEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: Edges.self) { geometry in
                    let offset = axis == .vertical ? geometry.contentOffset.y : geometry.contentOffset.x
                    let visible = axis == .vertical ? geometry.containerSize.height : geometry.containerSize.width
                    let total = axis == .vertical ? geometry.contentSize.height : geometry.contentSize.width
                    return Edges(start: offset > 1, end: offset + visible < total - 1)
                } action: { _, edges in
                    beyondStart = edges.start
                    beyondEnd = edges.end
                }
                .mask { fadeMask }
        } else {
            content
        }
    }

    private struct Edges: Equatable { var start: Bool; var end: Bool }

    private var fadeMask: some View {
        let vertical = axis == .vertical
        return Rectangle().fill(.black)
            .overlay(alignment: vertical ? .top : .leading) {
                fade(toStart: true).opacity(beyondStart ? 1 : 0)
            }
            .overlay(alignment: vertical ? .bottom : .trailing) {
                fade(toStart: false).opacity(beyondEnd ? 1 : 0)
            }
            .compositingGroup()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: beyondStart)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: beyondEnd)
    }

    /// Erases the mask toward the edge it sits on.
    private func fade(toStart: Bool) -> some View {
        let vertical = axis == .vertical
        let from: UnitPoint = vertical ? (toStart ? .top : .bottom) : (toStart ? .leading : .trailing)
        let to: UnitPoint = vertical ? (toStart ? .bottom : .top) : (toStart ? .trailing : .leading)
        return LinearGradient(colors: [.black, .clear], startPoint: from, endPoint: to)
            .frame(width: vertical ? nil : length, height: vertical ? length : nil)
            .blendMode(.destinationOut)
    }
}

extension View {
    func notchScrollEdgeFade(_ axis: Axis = .vertical, length: CGFloat = 16) -> some View {
        modifier(NotchScrollEdgeFade(axis: axis, length: length))
    }
}
