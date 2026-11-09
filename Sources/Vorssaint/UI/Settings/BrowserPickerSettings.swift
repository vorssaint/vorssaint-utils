// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BrowserPickerSettings: View {
    @ObservedObject private var service = BrowserPickerService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.browserPickerShowNumbers) private var showNumbers = true
    @State private var dragging: BrowserPickerOrderID?
    @AppStorage(DefaultsKey.browserPickerPlacement) private var placement = "center"
    private var options: BrowserPickerOptionsStrings { FeatureStrings.browserPickerOptions(l10n.language) }
    private var text: BrowserPickerStrings { FeatureStrings.browserPicker(l10n.language) }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Text(text.description).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(text.openPicker) { service.show() }
                }
                SettingsCard {
                    Toggle(options.showNumbers, isOn: $showNumbers)
                    Divider()
                    Picker(options.position, selection: $placement) {
                        Text(options.center).tag("center")
                        Text(options.cursor).tag("cursor")
                    }
                    .onChange(of: placement) { _, _ in service.updateVisiblePanelFrame() }
                }
                browserOrder
                SettingsCard {
                    if service.isDefaultBrowser {
                        Label(text.defaultActive, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(text.makeDefault) { service.makeDefault() }
                            .disabled(service.isSettingDefault)
                    }
                    Text(text.defaultHint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = service.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .toggleStyle(.switch)
        } header: { Text(text.title) }
        .settingsFormSectionAnchor(.browserPicker)
        .onAppear { service.refresh() }
        .onDisappear { dragging = nil }
    }

    private var orderBinding: Binding<[BrowserPickerOrderID]> {
        Binding(get: { service.browsers.map { BrowserPickerOrderID(rawValue: $0.id) } },
                set: { service.setBrowserOrder($0.map(\.rawValue)) })
    }

    private var browserOrder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text.order).font(.headline)
                Spacer()
                Button(text.scanBrowsers) { service.refresh() }
                    .buttonStyle(.borderless)
            }
            Text(text.orderHint).font(.caption).foregroundStyle(.secondary)
            if service.browsers.isEmpty {
                Text(text.empty).font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(service.browsers.enumerated()), id: \.element.id) { index, browser in
                        PanelReorderableItem(item: BrowserPickerOrderID(rawValue: browser.id),
                                             previewsAsCard: true, order: orderBinding, dragging: $dragging) {
                            BrowserPickerOrderRow(browser: browser, index: index, service: service)
                        }
                        .opacity(dragging?.rawValue == browser.id ? 0.45 : 1)
                        if index < service.browsers.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }
}

private struct BrowserPickerOrderID: RawRepresentable, Hashable {
    let rawValue: String
}

private struct BrowserPickerOrderRow: View {
    let browser: PickerBrowser
    let index: Int
    @ObservedObject var service: BrowserPickerService
    @ObservedObject private var l10n = L10n.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                PanelDragHandle().accessibilityHidden(true)
                Text(service.visibleBrowsers.firstIndex(where: { $0.id == browser.id }).map { String($0 + 1) } ?? "–")
                    .font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 18)
                Image(nsImage: browser.icon).resizable().frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(browser.name).font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(service.hiddenBrowserIDs.contains(browser.id) ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text(FeatureStrings.clipboard(l10n.language).moveUp)) { move(by: -1) }
            .accessibilityAction(named: Text(FeatureStrings.clipboard(l10n.language).moveDown)) { move(by: 1) }
            Toggle(browser.name, isOn: Binding(
                get: { !service.hiddenBrowserIDs.contains(browser.id) },
                set: { service.setBrowserEnabled(browser, enabled: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(isHovered ? Color.primary.opacity(0.045) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func move(by offset: Int) {
        guard service.browsers.indices.contains(index + offset) else { return }
        service.moveBrowser(browser.id, onto: service.browsers[index + offset].id)
    }
}
