// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The open island's bar of pages, as the menu bar panel's icon strip is:
/// each page keeps its own colour, and its icon shows what the page holds
/// at a glance. Settings ends the bar and opens the Settings window.
struct NotchTopBarView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var mic = MicMuteService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var agents = AgentUsageService.shared
    @ObservedObject private var clipboard = ClipboardHistoryService.shared
    @AppStorage(DefaultsKey.notchTopBarSecondaryClickToggles) private var secondaryClickToggles = true
    // Read so the companion in the bar changes as soon as its look does.
    @AppStorage(DefaultsKey.notchMascotStyle) private var mascotStyle = NotchMascotStyle.minimal.rawValue
    @AppStorage(DefaultsKey.notchMascotShape) private var mascotShape = NotchMascotShape.ball.rawValue
    @AppStorage(DefaultsKey.notchMascotPalette) private var mascotPalette = NotchMascotPalette.pearl.rawValue

    var body: some View {
        let items = NotchTopBarConfiguration.current()
        // A narrow island drops the chosen page's name before any icon.
        ViewThatFits(in: .horizontal) {
            row(items, labels: true)
            row(items, labels: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: NotchLayout.topBarHeight)
        .onAppear(perform: noteClipboardSeen)
        .onChange(of: service.selected) { noteClipboardSeen() }
    }

    private func row(_ items: [NotchTopBarItem], labels: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                if item == .settings { Spacer(minLength: 4) }
                button(item, label: labels)
            }
        }
    }

    private func button(_ item: NotchTopBarItem, label: Bool) -> some View {
        let selected = item.module == service.selected && !service.showingSections
            && !service.showingAppPanel && service.selectedMetric == nil
        let toggles = secondaryClickToggles && item.togglesOnSecondaryClick
        return NotchTopBarButton(item: item, tint: tint(item), selected: selected, showsLabel: label, title: title(item),
                                 badge: badge(item), dot: item == .keepAwake && awake.isActive,
                                 dimmed: item == .keepAwake && !awake.isActive,
                                 glyph: { glyph(item, selected: selected) },
                                 action: { activate(item) },
                                 secondary: toggles ? { toggle(item) } : nil)
    }

    private func toggle(_ item: NotchTopBarItem) {
        if item == .keepAwake { KeepAwakeManager.shared.toggle() } else { MicMuteService.shared.toggle() }
    }

    private func activate(_ item: NotchTopBarItem) {
        guard let module = item.module else { service.openSettings(); return }
        service.select(module)
    }

    private func title(_ item: NotchTopBarItem) -> String {
        item.module?.title(l10n.language) ?? l10n.s.menuSettings
    }

    private func noteClipboardSeen() {
        if service.selected == .clipboard { service.clipboardSeenAt = Date() }
    }

    // MARK: Live state

    private var charge: Int? {
        guard let power = monitor.snapshot.power, power.hasBattery else { return nil }
        return power.chargePercent
    }

    private var charging: Bool { monitor.snapshot.power?.externalConnected == true }

    private func tint(_ item: NotchTopBarItem) -> Color {
        switch item {
        case .keepAwake: return awake.isActive ? NotchTopBarPalette.awake : NotchTopBarPalette.amber
        case .microphone: return mic.isMuted ? NotchTopBarPalette.red : NotchTopBarPalette.green
        case .system: return (monitor.snapshot.cpuUsage ?? 0) > 0.8 ? NotchTopBarPalette.orange : NotchTopBarPalette.blue
        case .battery: return NotchTopBarPalette.battery(charge: charge, charging: charging)
        default: return NotchTopBarPalette.tint(item)
        }
    }

    private func badge(_ item: NotchTopBarItem) -> String? {
        switch item {
        case .agents:
            let working = Set(agents.snapshot.live.map(\.provider)).count
            return working > 0 ? "\(working)" : nil
        case .clipboard:
            guard service.selected != .clipboard || !service.expanded else { return nil }
            let fresh = clipboard.entries.lazy.filter { $0.copiedAt > service.clipboardSeenAt }.prefix(10).count
            return fresh == 0 ? nil : fresh > 9 ? "9+" : "\(fresh)"
        default: return nil
        }
    }

    @ViewBuilder private func glyph(_ item: NotchTopBarItem, selected: Bool) -> some View {
        switch item {
        case .agents:
            // The companion, in the style and colour chosen for it.
            NotchMascotView(look: NotchMascotLook(style: NotchMascotStyle(rawValue: mascotStyle) ?? .minimal,
                                                  shape: NotchMascotShape(rawValue: mascotShape) ?? .ball,
                                                  palette: NotchMascotPalette(rawValue: mascotPalette) ?? .pearl),
                            size: 18, idles: false)
                .frame(width: 18, height: 18)
                // Its own view would otherwise take the button's clicks.
                .allowsHitTesting(false)
        case .keepAwake:
            // Awake, the Mac keeps an eye open, as Keep Awake's own eye icon does.
            Image(systemName: awake.isActive ? "eye.fill" : "cup.and.saucer")
        case .music where music.playback?.isPlaying == true && !selected:
            NotchTopBarEqualizer()
        case .microphone:
            Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
        case .calendar:
            NotchTopBarCalendar(day: Calendar.current.component(.day, from: Date()))
        case .battery:
            NotchTopBarBattery(charge: charge, charging: charging)
        default:
            Image(systemName: item.symbol)
        }
    }
}

private struct NotchTopBarButton<Glyph: View>: View {
    let item: NotchTopBarItem
    let tint: Color
    let selected: Bool
    let showsLabel: Bool
    let title: String
    let badge: String?
    let dot: Bool
    let dimmed: Bool
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void
    /// What a secondary click does instead of opening the island's menu.
    let secondary: (() -> Void)?
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                glyph()
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint.opacity(selected || hovered ? 1 : dimmed ? 0.45 : 0.62))
                    .frame(minWidth: 20)
                    .contentTransition(.symbolEffect(.replace))
                if selected, showsLabel, item != .settings {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(tint.opacity(selected ? 0.24 : hovered ? 0.14 : 0),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3.5)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(tint, in: Capsule())
                        .offset(x: 4, y: -3)
                }
            }
            .overlay(alignment: .bottom) {
                if dot {
                    Circle().fill(tint).frame(width: 4, height: 4).offset(y: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9, highlights: false))
        .overlay { if let secondary { NotchSecondaryClickCatcher(action: secondary) } }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selected)
        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: hovered)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(badge ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Three bars that rise and fall while something plays.
private struct NotchTopBarEqualizer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3) { index in
                    let phase = (time * 4.4 + Double(index) * 1.3).truncatingRemainder(dividingBy: .pi * 2)
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 3, height: reduceMotion ? 8 : 4 + 10 * (0.5 + 0.5 * sin(phase)))
                }
            }
            .frame(width: 13, height: 14, alignment: .bottom)
        }
    }
}

/// A battery drawn to its charge, with a bolt while it charges.
private struct NotchTopBarBattery: View {
    let charge: Int?
    let charging: Bool

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(lineWidth: 1.4)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .frame(width: max(1.5, 16 * CGFloat(min(100, max(0, charge ?? 100))) / 100))
                    .padding(2)
            }
            .frame(width: 21, height: 11)
            RoundedRectangle(cornerRadius: 1).frame(width: 1.6, height: 4)
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).padding(.leading, 1)
            }
        }
    }
}

/// Today's date on a page of a calendar.
private struct NotchTopBarCalendar: View {
    let day: Int

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous).strokeBorder(lineWidth: 1.4)
            UnevenRoundedRectangle(topLeadingRadius: 3.5, topTrailingRadius: 3.5, style: .continuous)
                .frame(height: 4.5)
            Text("\(day)")
                .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                .padding(.top, 4.5)
        }
        .frame(width: 17, height: 16)
    }
}

/// Takes a secondary click over its view, in place of the island's menu,
/// leaving every other click to the view beneath.
private struct NotchSecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp: return super.hitTest(point)
            default: return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) { action?() }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
