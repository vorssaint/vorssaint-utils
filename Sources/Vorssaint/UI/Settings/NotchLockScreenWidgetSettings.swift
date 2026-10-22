// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

extension NotchLockScreenWidget: PanelOrderItem {}

/// The Lock Screen's widgets under its options: This Mac's, the stage's and
/// the AI rail's, each shown or hidden and dragged into order within its own
/// place. The rail switches above stay the masters; a place they turn off
/// says so, and its widgets keep their choices for when it returns.
struct NotchLockScreenWidgetSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchLockScreenWidgetOrder) private var order = ""
    @AppStorage(DefaultsKey.notchLockScreenHiddenWidgets) private var hidden = ""
    @AppStorage(DefaultsKey.notchLockScreenMac) private var mac = false
    @AppStorage(DefaultsKey.notchLockScreenAgents) private var agents = false
    @State private var dragging: NotchLockScreenWidget?

    private var text: NotchLockScreenStrings { FeatureStrings.notchLockScreen(l10n.language) }
    private var configuration: NotchLockScreenWidgets { NotchLockScreenWidgets(order: order, hidden: hidden) }

    var body: some View {
        SettingsCard(title: text.widgets) {
            Text(text.widgetsHint).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(NotchLockScreenWidget.Place.allCases) { place in
                if place != .mac { Divider() }
                group(place)
            }
        }
    }

    @ViewBuilder private func group(_ place: NotchLockScreenWidget.Place) -> some View {
        let reason = self.reason(place)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title(place)).font(.subheadline.weight(.medium))
                if let reason {
                    Text("· " + reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(configuration.order(in: place)) { widget in
                row(widget, available: reason == nil && self.reason(widget) == nil)
            }
        }
    }

    private func row(_ widget: NotchLockScreenWidget, available: Bool) -> some View {
        let title = name(widget)
        let reason = self.reason(widget)
        return PanelReorderableItem(item: widget, order: orderBinding(widget.place), dragging: $dragging) {
            HStack(spacing: 8) {
                Toggle(title, isOn: shown(widget)).labelsHidden().toggleStyle(.checkbox)
                Image(systemName: widget.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tint(widget), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(available ? 1 : 0.5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(available ? .primary : .secondary)
                    if let reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
            .opacity(dragging == widget ? 0.45 : 1)
            .accessibilityElement(children: .combine)
            // VoiceOver's way to reorder, which otherwise only drags.
            .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveUp) { move(widget, by: -1) }
            .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveDown) { move(widget, by: 1) }
        }
    }

    // MARK: Words

    private func title(_ place: NotchLockScreenWidget.Place) -> String {
        switch place {
        case .mac: return text.mac
        case .stage: return text.center
        case .ai: return FeatureStrings.notchAgents(l10n.language).title
        }
    }

    /// The names the cards themselves carry, so a row reads as its card.
    private func name(_ widget: NotchLockScreenWidget) -> String {
        let s = l10n.s
        let cards = FeatureStrings.notchLockScreenWidgets(l10n.language)
        switch widget {
        case .cpu: return s.cpuLabel
        case .gpu: return s.gpuLabel
        case .memory: return s.memorySection
        case .network: return s.networkSection
        case .accessories: return text.accessories
        case .battery: return s.powerBattery
        case .calendar: return FeatureStrings.notchCalendar(l10n.language).title
        case .nowPlaying: return FeatureStrings.radialMenu(l10n.language).mediaNowPlaying
        case .claude: return AgentProvider.claude.displayName
        case .codex: return AgentProvider.codex.displayName
        case .lifetime: return text.lifetimeSpending
        case .agents: return cards.agentsAtWork
        case .streak: return cards.streak
        }
    }

    /// Why a whole place stays off, whatever its widgets say.
    private func reason(_ place: NotchLockScreenWidget.Place) -> String? {
        switch place {
        case .mac: return mac ? nil : text.turnedOffAbove
        case .stage: return nil
        case .ai:
            guard NotchAgentSupport.sectionShows() else { return needs(.agents) }
            return agents ? nil : text.turnedOffAbove
        }
    }

    /// Why one widget on the stage stays off: the calendar goes with This
    /// Mac and the Calendar section, the player with the Music section.
    private func reason(_ widget: NotchLockScreenWidget) -> String? {
        switch widget {
        case .calendar:
            guard mac else { return text.turnedOffAbove }
            return NotchCalendarSupport.isEnabled() ? nil : needs(.calendar)
        case .nowPlaying:
            return NotchLockScreenSupport.showsMusic() ? nil : needs(.music)
        default:
            return nil
        }
    }

    private func needs(_ module: NotchModule) -> String {
        String(format: text.needsSectionFormat, module.title(l10n.language))
    }

    /// The island's own colors where a widget has a page there.
    private func tint(_ widget: NotchLockScreenWidget) -> Color {
        switch widget {
        case .battery: return NotchTopBarPalette.green
        case .accessories: return NotchTopBarPalette.tan
        case .calendar: return NotchTopBarPalette.red
        case .nowPlaying: return NotchTopBarPalette.rose
        default: return widget.place == .ai ? NotchTopBarPalette.clay : NotchTopBarPalette.blue
        }
    }

    // MARK: Saving

    private func shown(_ widget: NotchLockScreenWidget) -> Binding<Bool> {
        Binding(get: { !configuration.hidden.contains(widget) },
                set: { save(configuration.showing(widget, $0)) })
    }

    /// A place's widgets as the drag sees them; a drop rewrites that place alone.
    private func orderBinding(_ place: NotchLockScreenWidget.Place) -> Binding<[NotchLockScreenWidget]> {
        Binding(get: { configuration.order(in: place) }, set: { save(configuration.arranging($0)) })
    }

    private func move(_ widget: NotchLockScreenWidget, by offset: Int) {
        save(configuration.moving(widget, by: offset))
    }

    private func save(_ updated: NotchLockScreenWidgets) {
        order = updated.encodedOrder
        hidden = updated.encodedHidden
    }
}
