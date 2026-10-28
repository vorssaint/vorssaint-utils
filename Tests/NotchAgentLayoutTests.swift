// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Render the production grid, card chrome and Now card without starting agents.
enum NotchAgentLayoutTests {
    // Icons and surfaces have no effect on sizing. Keep their allocated frames
    // while avoiding app discovery, native animation and glass in the fixture.
    struct NotchControlSurface: ViewModifier {
        let cornerRadius: CGFloat
        let interactive: Bool
        func body(content: Content) -> some View { content.background(.gray.opacity(0.1)) }
    }
    struct NotchAgentMark: View {
        let provider: AgentProvider
        let size: CGFloat
        let tint: Color?
        var body: some View { Color.clear.frame(width: size, height: size) }
    }
    struct NotchAgentGlyphBridge: View {
        let provider: AgentProvider
        let size: CGFloat
        let animates: Bool
        var body: some View { Color.clear }
    }
    struct NotchAgentPulse: View {
        let tint: Color
        let size: CGFloat
        var body: some View { Color.clear.frame(width: size * 2, height: size * 2) }
    }
    final class MarkerView: NSView { var id = "" }
    struct Marker: NSViewRepresentable {
        let id: String
        func makeNSView(context: Context) -> MarkerView { MarkerView() }
        func updateNSView(_ view: MarkerView, context: Context) { view.id = id }
    }
    struct Grid: View {
        let providers: [AgentProvider]
        let width: CGFloat
        var rows: [[NotchAgentTile]] {
            NotchAgentSupport.rows(NotchAgentSupport.tiles(cards: [.limits, .spend, .live, .trend], providers: providers), width: width)
        }
        var body: some View { grid(rows, now: Date()).environment(\.locale, Locale(identifier: "en_US")) }
        @ViewBuilder func card(_ tile: NotchAgentTile, now: Date) -> some View {
            Group {
                if tile.card == .live {
                    NotchAgentLiveCard(snapshot: AgentUsageSnapshot(), providers: providers, text: .enUS)
                } else {
                    NotchAgentCardChrome { Text(tile.id).font(.system(size: 10.5)) }
                }
            }
            .background(Marker(id: tile.id))
        }
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        for providers in [[AgentProvider.claude, .codex, .opencode], [.claude, .codex, .opencode, .cursor], AgentProvider.allCases] {
            for width: CGFloat in [330, 454] {
                let grid = Grid(providers: providers, width: width)
                let host = NSHostingView(rootView: grid)
                host.frame = CGRect(x: 0, y: 0, width: width, height: NotchAgentSupport.contentHeight(grid.rows))
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.close() }
                let deadline = Date().addingTimeInterval(0.15)
                while Date() < deadline {
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                var frames: [String: CGRect] = [:]
                func walk(_ view: NSView) {
                    if let marker = view as? MarkerView { frames[marker.id] = marker.convert(marker.bounds, to: host) }
                    view.subviews.forEach(walk)
                }
                walk(host)
                guard let live = frames[NotchAgentCard.live.rawValue], let trend = frames[NotchAgentCard.trend.rawValue],
                      let row = grid.rows.first(where: { $0.contains(where: { $0.card == .live }) }) else {
                    suite.expect(false, "agent grid renders the Now and Trend cards")
                    continue
                }
                suite.expect(live.height <= NotchAgentSupport.height(of: row) + 0.5,
                             "Now fits its grid row with \(providers.count) idle providers at width \(width): \(live.height)")
                let gap = max(live.minY - trend.maxY, trend.minY - live.maxY)
                suite.expect(gap >= NotchAgentSupport.spacing - 0.5,
                             "Now preserves the gap before Trend with \(providers.count) idle providers at width \(width): \(gap)")
            }
        }
    }
}
