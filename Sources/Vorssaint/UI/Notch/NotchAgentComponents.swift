// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension AgentProvider {
    /// Each agent keeps one color across the page, the strip and notices.
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.49, green: 0.60, blue: 1.0)
        case .opencode: return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .copilot: return Color(red: 0.30, green: 0.78, blue: 0.68)
        case .agy: return Color(red: 0.10, green: 0.66, blue: 0.74)
        }
    }
}

/// Green reads as fine and red as trouble only when it earns it: the agent's
/// own color while there is room, orange once a window runs low.
func agentLimitTint(_ provider: AgentProvider, usedFraction: Double) -> Color {
    if usedFraction >= 0.95 { return .red }
    if usedFraction >= 0.8 { return .orange }
    return provider.tint
}

/// A card on the AI page: the same surface as the island's system cards.
struct NotchAgentCardChrome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
    }
}

struct NotchAgentCardHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    /// A card about one agent wears its mark instead of the symbol.
    var provider: AgentProvider? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            if let provider {
                // A mark is finer than a symbol and needs more room to read.
                NotchAgentMark(provider: provider, size: 13, tint: tint)
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 13)
            }
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            accessory
        }
        .frame(height: 17)
    }
}

extension NotchAgentCardHeader where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color = .secondary) {
        self.init(title: title, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// A capsule meter with a tick where spending would be if it were spread
/// evenly across the window: a fill past the tick is ahead of pace.
struct NotchAgentMeter: View {
    let value: Double
    var pace: Double?
    var tint: Color = .white
    var height: CGFloat = 5
    var dimmed = false

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.13))
                Capsule(style: .continuous)
                    .fill(tint.opacity(dimmed ? 0.45 : 0.92))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
                if let pace, pace.isFinite, pace > 0.02, pace < 0.98 {
                    RoundedRectangle(cornerRadius: 0.75)
                        .fill(.white.opacity(0.85))
                        .frame(width: 1.5, height: height + 5)
                        .offset(x: proxy.size.width * pace - 0.75)
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height + 5)
        .accessibilityHidden(true)
    }
}

/// A small ring for the closed island, filled by what is left.
struct NotchAgentRing: View {
    let value: Double
    var tint: Color = .white
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A calm pulse that says an agent is working; still under Reduce Motion.
/// Native layer motion avoids driving the surrounding SwiftUI graph at the
/// display refresh rate, including Settings previews retained after closing.
struct NotchAgentPulse: View {
    var tint: Color
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchAgentPulseBridge(tint: NSColor(tint), size: size, animates: !reduceMotion)
            .frame(width: size * 2, height: size * 2)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// The agent's mark breathing while it works. A turn would read as a
/// cross halfway round, so the mark keeps its angle.
struct NotchAgentGlyph: View {
    let provider: AgentProvider
    var size: CGFloat = 13
    var working = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchAgentGlyphBridge(provider: provider, size: size, animates: working && !reduceMotion)
            // Room for the widest mark, the Claude one, drawn past its size.
            .frame(width: size * 1.45 + 1, height: size * 1.45 + 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct NotchAgentPulseBridge: NSViewRepresentable {
    let tint: NSColor
    let size: CGFloat
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        view.configurePulse(size: size, tint: tint, animates: animates)
    }
    static func dismantleNSView(_ view: NotchAgentAnimationView, coordinator: ()) { view.stop() }
}

/// The Antigravity arch glyph, scaled and centred in its box.
struct AntigravityMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var base = Path()
        base.move(to: CGPoint(x: 144.248, y: 149.062))
        base.addCurve(to: CGPoint(x: 152.685, y: 140.625),
                      control1: CGPoint(x: 151.748, y: 154.688),
                      control2: CGPoint(x: 162.998, y: 150.938))
        base.addCurve(to: CGPoint(x: 89.8727, y: 28.125),
                      control1: CGPoint(x: 121.748, y: 110.625),
                      control2: CGPoint(x: 128.31, y: 28.125))
        base.addCurve(to: CGPoint(x: 27.0602, y: 140.625),
                      control1: CGPoint(x: 51.4352, y: 28.125),
                      control2: CGPoint(x: 57.9977, y: 110.625))
        base.addCurve(to: CGPoint(x: 35.4977, y: 149.062),
                      control1: CGPoint(x: 15.8102, y: 151.875),
                      control2: CGPoint(x: 27.9977, y: 154.688))
        base.addCurve(to: CGPoint(x: 89.8727, y: 94.6875),
                      control1: CGPoint(x: 64.5602, y: 129.375),
                      control2: CGPoint(x: 62.6852, y: 94.6875))
        base.addCurve(to: CGPoint(x: 144.248, y: 149.062),
                      control1: CGPoint(x: 117.06, y: 94.6875),
                      control2: CGPoint(x: 115.185, y: 129.375))
        base.closeSubpath()

        let bounds = CGRect(x: 15, y: 28, width: 148, height: 127)
        guard bounds.width > 0, bounds.height > 0, rect.width > 0, rect.height > 0 else { return base }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let xOffset = rect.minX + (rect.width - bounds.width * scale) / 2 - bounds.minX * scale
        let yOffset = rect.minY + (rect.height - bounds.height * scale) / 2 - bounds.minY * scale
        let transform = CGAffineTransform(translationX: xOffset, y: yOffset)
            .scaledBy(x: scale, y: scale)
        return base.applying(transform)
    }

    static let templateImage: NSImage = {
        let size = NSSize(width: 36, height: 36)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let path = AntigravityMarkShape().path(in: CGRect(origin: .zero, size: rect.size))
            ctx.addPath(path.cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct NotchAgentGlyphBridge: NSViewRepresentable {
    let provider: AgentProvider
    let size: CGFloat
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        let image: NSImage?
        let markSize: CGFloat
        let tint: NSColor?
        if provider == .agy {
            image = AntigravityMarkShape.templateImage
            markSize = size * provider.markScale
            tint = NSColor(provider.tint)
        } else {
            switch AgentMarks.mark(for: provider) {
            case .template(let mark):
                image = mark
                markSize = size * provider.markScale
                tint = NSColor(provider.tint)
            case .icon(let mark):
                image = mark
                markSize = size * 1.35
                tint = nil
            case nil:
                image = NSImage(systemSymbolName: provider.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
                markSize = size
                tint = NSColor(provider.tint)
            }
        }
        view.configureGlyph(image: image, size: markSize, tint: tint, animates: animates)
    }
    static func dismantleNSView(_ view: NotchAgentAnimationView, coordinator: ()) { view.stop() }
}

/// Stacked bars, one per bucket, each split by agent. Hovering a bar reports
/// it so the card can name the day and its value.
struct NotchAgentBars: View {
    let buckets: [AgentBucket]
    let providers: [AgentProvider]
    let byCost: Bool
    @Binding var hovered: Date?

    var body: some View {
        let values = buckets.map { bucket in providers.map { bucket.byProvider[$0]?.weight(byCost: byCost) ?? 0 } }
        let peak = max(values.map { $0.reduce(0, +) }.max() ?? 0, .leastNonzeroMagnitude)
        GeometryReader { proxy in
            let count = CGFloat(max(1, buckets.count))
            let gap: CGFloat = count > 24 ? 2 : 4
            let width = max(1, (proxy.size.width - gap * (count - 1)) / count)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    let parts = values[index]
                    let total = parts.reduce(0, +)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if total <= 0 {
                            Capsule().fill(.white.opacity(0.1)).frame(height: 2)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(providers.indices.reversed(), id: \.self) { slot in
                                    if parts[slot] > 0 {
                                        Rectangle()
                                            .fill(providers[slot].tint.opacity(hovered == nil || hovered == bucket.start ? 0.95 : 0.5))
                                            .frame(height: max(1, proxy.size.height * parts[slot] / peak))
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: min(3, width / 2), style: .continuous))
                        }
                    }
                    .frame(width: width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = bucket.start } else if hovered == bucket.start { hovered = nil }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Thirteen weeks of activity, a column a week, darker cells for quieter days.
struct NotchAgentHeatmap: View {
    let days: [AgentBucket]
    let byCost: Bool
    @Binding var hovered: Date?
    var calendar: Calendar = .autoupdatingCurrent
    static let spacing: CGFloat = 2.5

    /// Square cells as tall as seven rows allow, across every week shown.
    static func width(height: CGFloat, days: [AgentBucket], calendar: Calendar = .autoupdatingCurrent) -> CGFloat {
        let weeks = CGFloat(Self.columns(days, calendar: calendar).count)
        let cell = max(1, (height - spacing * 6) / 7)
        return max(0, weeks * cell + max(0, weeks - 1) * spacing)
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = Self.columns(days, calendar: calendar)
            let spacing = Self.spacing
            let cell = min((proxy.size.height - spacing * 6) / 7,
                           (proxy.size.width - spacing * CGFloat(max(0, columns.count - 1))) / CGFloat(max(1, columns.count)))
            let levels = thresholds
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            if let day = week[row] {
                                let value = day.total.weight(byCost: byCost)
                                RoundedRectangle(cornerRadius: min(2.5, cell / 3), style: .continuous)
                                    .fill(.white.opacity(opacity(value, levels: levels)))
                                    .overlay {
                                        if hovered == day.start || calendar.isDateInToday(day.start) {
                                            RoundedRectangle(cornerRadius: min(2.5, cell / 3), style: .continuous)
                                                .strokeBorder(.white.opacity(hovered == day.start ? 0.9 : 0.45), lineWidth: 1)
                                        }
                                    }
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                    .onHover { inside in
                                        if inside { hovered = day.start } else if hovered == day.start { hovered = nil }
                                    }
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    /// Days laid into weeks that start on the reader's first weekday.
    static func columns(_ days: [AgentBucket], calendar: Calendar) -> [[AgentBucket?]] {
        var weeks: [[AgentBucket?]] = []
        var current = [AgentBucket?](repeating: nil, count: 7)
        for day in days {
            let weekday = (calendar.component(.weekday, from: day.start) - calendar.firstWeekday + 7) % 7
            if weekday == 0, current.contains(where: { $0 != nil }) {
                weeks.append(current)
                current = [AgentBucket?](repeating: nil, count: 7)
            }
            current[weekday] = day
        }
        if current.contains(where: { $0 != nil }) { weeks.append(current) }
        return weeks
    }

    /// Quartiles of the active days, so one heavy day does not wash out the rest.
    private var thresholds: [Double] {
        let values = days.map { $0.total.weight(byCost: byCost) }.filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [] }
        return [0.25, 0.5, 0.75].map { values[min(values.count - 1, Int(Double(values.count) * $0))] }
    }

    private func opacity(_ value: Double, levels: [Double]) -> Double {
        guard value > 0 else { return 0.07 }
        let level = levels.filter { value > $0 }.count
        return [0.28, 0.45, 0.65, 0.9][min(3, level)]
    }
}

/// Each agent's own mark, taken from its maker's app on this Mac: the
/// monochrome image the app shows in the menu bar, or else the app's icon.
/// None of that artwork ships with Vorssaint, so a Mac without the app
/// keeps a symbol. Looked up once; the strip redraws every second.
enum AgentMarks {
    enum Mark {
        /// Drawn in the agent's color, like the symbol it replaces.
        case template(NSImage)
        case icon(NSImage)
    }

    private static var found: [AgentProvider: Mark?] = [:]

    static func mark(for provider: AgentProvider) -> Mark? {
        if let mark = found[provider] { return mark }
        let mark = lookUp(provider)
        found[provider] = .some(mark)
        return mark
    }

    private static func lookUp(_ provider: AgentProvider) -> Mark? {
        guard provider != .agy else { return nil }
        for identifier in provider.appIdentifiers {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { continue }
            if let bundle = Bundle(url: url) {
                for name in provider.menuBarImageNames {
                    if let image = bundle.image(forResource: name) {
                        image.isTemplate = true
                        return .template(image)
                    }
                }
            }
            return .icon(NSWorkspace.shared.icon(forFile: url.path))
        }
        return nil
    }
}

private extension AgentProvider {
    /// The maker's desktop apps, the one that runs the agent first.
    var appIdentifiers: [String] {
        switch self {
        case .claude: return [AgentClaudeAppUsage.bundleIdentifier]
        case .codex: return AgentCodexServer.appIdentifiers
        case .opencode: return ["ai.opencode.desktop", "ai.opencode.desktop.beta", "ai.opencode.desktop.dev"]
        case .copilot: return ["com.github.githubapp"]
        case .agy: return ["com.google.antigravity"]
        }
    }

    /// The menu bar images keep a margin; the spark's thin rays need more
    /// of the box than the knot to look the same size.
    var markScale: CGFloat { self == .claude ? 1.45 : 1.2 }

    /// What those apps name the mark they show in the menu bar.
    var menuBarImageNames: [String] {
        switch self {
        case .claude: return ["TrayIconTemplate"]
        case .codex: return ["chatgptTemplate"]
        // The OpenCode app shows nothing in the menu bar; its icon stands in.
        case .opencode: return []
        case .copilot: return []
        case .agy: return []
        }
    }
}

/// An agent's mark at the size of the symbol it stands in for.
struct NotchAgentMark: View {
    let provider: AgentProvider
    var size: CGFloat = 13
    var tint: Color?

    var body: some View {
        if provider == .agy {
            AntigravityMarkShape()
                .fill(tint ?? provider.tint)
                .frame(width: size * provider.markScale, height: size * provider.markScale)
        } else {
            switch AgentMarks.mark(for: provider) {
            case .template(let image):
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * provider.markScale, height: size * provider.markScale)
                    .foregroundStyle(tint ?? provider.tint)
            case .icon(let image):
                // App icons keep a margin around their artwork.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 1.35, height: size * 1.35)
            case nil:
                Image(systemName: provider.symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(tint ?? provider.tint)
            }
        }
    }
}
