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
        }
    }
}

/// The resting island's colors: green while a window has room, yellow once
/// it runs low and red when it is almost out, as the system draws them dark.
func agentStatusTint(_ status: NotchAgentRestingStatus) -> Color {
    switch status {
    case .normal: return Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    case .low: return Color(red: 1, green: 0xD6 / 255, blue: 0x0A / 255)
    case .almostOut: return Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)
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

private struct NotchAgentGlyphBridge: NSViewRepresentable {
    let provider: AgentProvider
    let size: CGFloat
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        let image: NSImage?
        let markSize: CGFloat
        let tint: NSColor?
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
        }
    }
}

/// An agent's mark at the size of the symbol it stands in for.
struct NotchAgentMark: View {
    let provider: AgentProvider
    var size: CGFloat = 13
    var tint: Color?
    /// A box the mark must fit, as inside the resting ring. Boxed, an app
    /// icon is never drawn: its own colors and margin read as a smudge.
    var box: CGFloat? = nil

    var body: some View {
        if let box {
            boxed(box)
        } else {
            sized
        }
    }

    @ViewBuilder private func boxed(_ box: CGFloat) -> some View {
        if case .template(let image) = AgentMarks.mark(for: provider) {
            // The menu bar images keep a margin; the knot's fills the box.
            let side = box * provider.markScale / 1.2
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: side, height: side)
                .foregroundStyle(tint ?? provider.tint)
        } else {
            Image(systemName: provider.symbol)
                .font(.system(size: box * 0.72, weight: .semibold))
                .foregroundStyle(tint ?? provider.tint)
        }
    }

    @ViewBuilder private var sized: some View {
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

/// One account at rest: its mark inside the session ring, the weekly bar
/// below. Each window wears its own status color; one switched off keeps
/// its empty track, so the ring always means the session and the bar the week.
struct NotchAgentRestingGauge: View {
    let meter: NotchAgentRestingMeter
    let used: Bool
    static let ring: CGFloat = 14
    static let lineWidth: CGFloat = 1.6
    static let barHeight: CGFloat = 2
    static let barGap: CGFloat = 1.8
    /// How far the ring's middle sits above the wing's.
    static let ringRise: CGFloat = 2.4
    static let track = Color.white.opacity(0.18)

    var body: some View {
        VStack(spacing: Self.barGap) {
            ZStack {
                if let session = meter.session {
                    NotchAgentRing(value: fill(session), tint: tint(session), lineWidth: Self.lineWidth)
                } else {
                    Circle().stroke(Self.track, lineWidth: Self.lineWidth)
                }
                NotchAgentMark(provider: meter.provider, box: 9)
            }
            .frame(width: Self.ring, height: Self.ring)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Self.track.opacity(meter.weekly == nil ? 0.45 : 1))
                if let weekly = meter.weekly, fill(weekly) > 0 {
                    Capsule(style: .continuous)
                        .fill(tint(weekly))
                        .frame(width: max(Self.barHeight, Self.ring * fill(weekly)))
                }
            }
            .frame(width: Self.ring, height: Self.barHeight)
        }
        // The ring's middle sits above the wing's, the bar below.
        .offset(y: -Self.ringRise + (Self.barGap + Self.barHeight) / 2)
        .accessibilityHidden(true)
    }

    private func fill(_ window: AgentLimitWindow) -> Double {
        used ? window.usedFraction : window.remainingFraction
    }

    private func tint(_ window: AgentLimitWindow) -> Color {
        agentStatusTint(NotchAgentSupport.restingStatus(usedFraction: window.usedFraction))
    }
}

/// The number beside a resting meter: with its "%" over "left" or "used"
/// where the wing has room, each line centred on its ink so "1" and "%" do
/// not pull it off the axis, or the bare number set against the gauge it
/// shares the wing with.
struct NotchAgentRestingAmount: View {
    let window: AgentLimitWindow
    let used: Bool
    /// "left" or "used" under the number; nil for the bare number.
    let word: String?
    /// The side the bare number's gauge is on.
    var gauge: HorizontalEdge = .leading
    /// The number's size; the sign and the word follow it.
    var size: CGFloat = 12
    var width: CGFloat = 31

    var body: some View {
        let fraction = used ? window.usedFraction : window.remainingFraction
        let digits = String(Int((fraction * 100).rounded()))
        let status = NotchAgentSupport.restingStatus(usedFraction: window.usedFraction)
        let tint = status == .normal ? Color.white.opacity(0.92) : agentStatusTint(status)
        let face = Font.system(size: size, weight: .semibold, design: .rounded)
        if let word {
            let wordSize = size * 0.625
            ZStack {
                (Text(digits).font(face).monospacedDigit()
                    + Text("%").font(.system(size: size * 0.7, weight: .semibold, design: .rounded)))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .offset(x: NotchAgentRestingInk.offset(number: digits, size: size, percent: true), y: -size * 0.3)
                Text(word)
                    .font(.system(size: wordSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .offset(x: NotchAgentRestingInk.offset(word: word, size: wordSize), y: size * 0.48)
            }
            .frame(width: width)
            .accessibilityHidden(true)
        } else {
            // Level with the ring, not with the ring and bar together: an
            // unfilled bar reads as empty space, and the number would hang
            // below the ring. Digits' ink sits 0.3 points under their line's
            // middle. As far from its ring whatever the digits: the ink, not
            // the advance, starts a gap past the stroke. The slot gives way
            // to a taller strip's wider shoulder, and "100", 24 points in
            // even digits, shrinks to fit 16.
            let bearings = NotchAgentRestingInk.bearings(number: digits, size: size)
            let clearance = NotchAgentRestingGauge.lineWidth / 2
            Text(digits).font(face).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .offset(x: gauge == .trailing ? bearings.trailing - clearance : clearance - bearings.leading,
                        y: 0.3 - NotchAgentRestingGauge.ringRise)
                .frame(maxWidth: width, alignment: gauge == .trailing ? .trailing : .leading)
                .accessibilityHidden(true)
        }
    }
}

/// Where a line's ink lies within its advance, so it can sit on the axis or
/// against a gauge by its glyphs. Measured once per string and size; there
/// are few of either.
enum NotchAgentRestingInk {
    /// The blank before and after a line's glyphs.
    private static var bearings: [String: (leading: CGFloat, trailing: CGFloat)] = [:]

    /// How far a line moves so the middle of its ink, not of its advance,
    /// lies on the axis.
    static func offset(number digits: String, size: CGFloat, percent: Bool) -> CGFloat {
        let blank = numberBearings(digits, size: size, percent: percent)
        return (blank.trailing - blank.leading) / 2
    }

    static func offset(word: String, size: CGFloat) -> CGFloat {
        let blank = cached("w\(size) \(word)") { [(word, font(size, .medium))] }
        return (blank.trailing - blank.leading) / 2
    }

    /// The blank either side of a bare number's digits.
    static func bearings(number digits: String, size: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        numberBearings(digits, size: size, percent: false)
    }

    private static func numberBearings(_ digits: String, size: CGFloat, percent: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        cached("n\(size)\(percent) \(digits)") {
            [(digits, font(size, .semibold, monospacedDigits: true))] + (percent ? [("%", font(size * 0.7, .semibold))] : [])
        }
    }

    private static func cached(_ key: String, _ parts: () -> [(String, NSFont)]) -> (leading: CGFloat, trailing: CGFloat) {
        if let blank = bearings[key] { return blank }
        let blank = measure(parts())
        bearings[key] = blank
        return blank
    }

    static func measure(_ parts: [(String, NSFont)]) -> (leading: CGFloat, trailing: CGFloat) {
        let text = NSMutableAttributedString()
        for (string, font) in parts { text.append(NSAttributedString(string: string, attributes: [.font: font])) }
        let line = CTLineCreateWithAttributedString(text)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard advance > 0, !ink.isNull, ink.width > 0 else { return (0, 0) }
        return (ink.minX, advance - ink.maxX)
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight, monospacedDigits: Bool = false) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor
        if monospacedDigits {
            descriptor = descriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}
