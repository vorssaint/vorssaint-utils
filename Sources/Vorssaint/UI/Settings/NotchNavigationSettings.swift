// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

extension NotchTopBarItem: PanelOrderItem {}

/// The Dynamic Island's Navigation tab: the bar of pages along the open
/// island's top, or the circles floating beside it, and what the bar holds.
struct NotchNavigationSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchNavigationStyle) private var style = NotchNavigationStyle.sideButtons.rawValue
    @AppStorage(DefaultsKey.notchTopBarOrder) private var order = ""
    @AppStorage(DefaultsKey.notchTopBarHidden) private var hidden = ""
    @AppStorage(DefaultsKey.notchTopBarSecondaryClickToggles) private var secondaryClickToggles = true
    @State private var dragging: NotchTopBarItem?
    /// Leads to the Layout tab, where the side buttons are arranged.
    let showLayout: () -> Void
    private var text: NotchNavigationStrings { NotchNavigationStrings.localized(l10n.language) }
    private var chosen: NotchNavigationStyle { NotchNavigationStyle(rawValue: style) ?? .sideButtons }

    private var configuration: NotchTopBarConfiguration {
        NotchTopBarConfiguration(order: order.split(separator: ",").compactMap { NotchTopBarItem(rawValue: String($0)) },
                                 hidden: Set(hidden.split(separator: ",").compactMap { NotchTopBarItem(rawValue: String($0)) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: text.styleTitle) {
                Text(text.styleCaption).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    styleChoice(.topBar, title: text.topBar)
                    styleChoice(.sideButtons, title: text.sideButtons)
                }
                if chosen == .sideButtons {
                    Button(text.sideButtonsHint, action: showLayout).buttonStyle(.link)
                }
            }
            if chosen == .topBar {
                SettingsCard(title: text.itemsTitle) {
                    Text(text.itemsCaption).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 2) {
                        ForEach(configuration.order) { item in row(item) }
                    }
                    Divider()
                    SettingsRow(symbol: "cursorarrow.click.2", title: text.secondaryClick, caption: text.secondaryClickCaption) {
                        Toggle(text.secondaryClick, isOn: $secondaryClickToggles).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
        }
        .onChange(of: [style, order, hidden, String(secondaryClickToggles)]) { _, _ in
            NotchService.shared.syncWithPreferences()
        }
    }

    /// A small island showing where the way between pages sits.
    private func styleChoice(_ item: NotchNavigationStyle, title: String) -> some View {
        let selected = chosen == item
        return Button { style = item.rawValue } label: {
            VStack(spacing: 10) {
                NotchNavigationSample(style: item)
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 92).padding(8)
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func row(_ item: NotchTopBarItem) -> some View {
        let title = item.module?.title(l10n.language) ?? l10n.s.menuSettings
        let available = item.isAvailable()
        let content = HStack(spacing: 8) {
            if item == .settings {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 14)
            } else {
                Toggle(title, isOn: included(item)).labelsHidden().toggleStyle(.checkbox).disabled(!available)
            }
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(NotchTopBarPalette.tint(item), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(available ? .primary : .secondary)
            Spacer(minLength: 4)
            if item != .settings {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
        .opacity(dragging == item ? 0.45 : 1)
        if item == .settings {
            content
        } else {
            PanelReorderableItem(item: item, order: orderBinding, dragging: $dragging) { content }
        }
    }

    private func included(_ item: NotchTopBarItem) -> Binding<Bool> {
        Binding(get: { !configuration.hidden.contains(item) }, set: { shown in
            var updated = configuration
            if shown { updated.hidden.remove(item) } else { updated.hidden.insert(item) }
            save(updated)
        })
    }

    /// Settings keeps its place at the end however the rest are dragged.
    private var orderBinding: Binding<[NotchTopBarItem]> {
        Binding(get: { configuration.order }, set: { save(NotchTopBarConfiguration(order: $0, hidden: configuration.hidden)) })
    }

    private func save(_ updated: NotchTopBarConfiguration) {
        order = updated.order.map(\.rawValue).joined(separator: ",")
        hidden = updated.order.filter(updated.hidden.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// The open island in miniature: a row of coloured icons along its top, or
/// circles beside it.
private struct NotchNavigationSample: View {
    let style: NotchNavigationStyle

    var body: some View {
        switch style {
        case .topBar:
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    ForEach([NotchTopBarItem.agents, .keepAwake, .music, .mixer, .calendar, .scratchpad]) { item in
                        Image(systemName: item.symbol).font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(NotchTopBarPalette.tint(item))
                    }
                }
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.12)).frame(width: 96, height: 22)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        case .sideButtons:
            HStack(spacing: 5) {
                circles
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                    .fill(.black).frame(width: 78, height: 42)
                circles
            }
        }
    }

    private var circles: some View {
        VStack(spacing: 4) {
            ForEach(0..<2) { _ in Circle().fill(.black).frame(width: 13, height: 13) }
        }
    }
}
