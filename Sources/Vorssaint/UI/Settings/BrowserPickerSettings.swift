// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserPickerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrowserPickerService.shared
    @State private var editing: EditedRule?
    @State private var dragging: UUID?

    private var strings: BrowserPickerStrings { FeatureStrings.browserPicker(l10n.language) }

    /// A sheet needs an identity; a new rule gets one up front.
    private struct EditedRule: Identifiable {
        let id = UUID()
        let draft: BrowserPickerRuleDraft
    }

    var body: some View {
        Form {
            Section {
                defaultBrowserRow
            } footer: {
                Text(strings.defaultBrowserCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if service.rules.isEmpty {
                    Text(strings.noRules)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(service.rules) { rule in
                    BrowserPickerRuleRow(rule: rule, service: service, strings: strings, dragging: $dragging,
                                         edit: { editing = EditedRule(draft: BrowserPickerRuleDraft(rule)) })
                }
                Button(strings.addRule) {
                    editing = EditedRule(draft: BrowserPickerRuleDraft(site: "", path: "", target: nil))
                }
                if !service.withheldProfiles.isEmpty {
                    FullDiskAccessNote(reason: String(format: strings.profilesWithheldFormat,
                                                      service.withheldProfiles.joined(separator: ", ")))
                }
            } header: {
                Text(strings.rulesTitle)
            } footer: {
                Text(strings.rulesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDrop(of: [UTType.text], delegate: BrowserPickerDragCleanup(dragging: $dragging))
        .sheet(item: $editing) { edited in
            BrowserPickerRuleEditor(service: service, draft: edited.draft) { rule in
                if let rule {
                    if edited.draft.id == nil { service.add(rule) } else { service.update(rule) }
                }
                editing = nil
            }
        }
        .onAppear {
            service.refreshDefaultState()
            service.refreshChoices(openingSettings: true)
        }
        // Someone may change the default browser in System Settings meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refreshDefaultState()
        }
    }

    private var defaultBrowserRow: some View {
        HStack(spacing: 10) {
            Image(systemName: service.isDefaultBrowser ? "checkmark.circle.fill" : "link.circle")
                .font(.system(size: 18))
                .foregroundStyle(service.isDefaultBrowser ? Color.green : Color.secondary)
            Text(service.isDefaultBrowser ? strings.statusOn : strings.statusOff)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if service.isChangingDefault {
                ProgressView().controlSize(.small)
            }
            if service.isDefaultBrowser {
                Button(String(format: strings.restoreFormat, service.previousBrowserName ?? "Safari")) {
                    service.setDefaultBrowser(false)
                }
                .disabled(service.isChangingDefault)
            } else {
                Button(strings.makeDefault) { service.setDefaultBrowser(true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isChangingDefault)
            }
        }
    }
}

private struct BrowserPickerRuleRow: View {
    let rule: BrowserPickerRule
    @ObservedObject var service: BrowserPickerService
    let strings: BrowserPickerStrings
    @Binding var dragging: UUID?
    let edit: () -> Void

    var body: some View {
        let installed = service.isInstalled(rule.target)
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Toggle(strings.ruleEnabled, isOn: Binding(
                get: { rule.isEnabled },
                set: { var changed = rule; changed.isEnabled = $0; service.update(changed) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Button(action: edit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.site)
                        if !rule.path.isEmpty {
                            Text(rule.path.removingPercentEncoding ?? rule.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let appURL = BrowserPickerBrowsers.applicationURL(for: rule.target) {
                        Image(nsImage: BrowserPickerIcons.icon(for: appURL))
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(installed ? service.label(for: rule.target)
                                   : String(format: strings.unavailableTargetFormat, service.label(for: rule.target)))
                        .foregroundStyle(installed ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }
                .opacity(rule.isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.editRule)
            Menu {
                Button(strings.editRule, action: edit)
                Button(strings.moveUp) { move(by: -1) }
                    .disabled(service.rules.first?.id == rule.id)
                Button(strings.moveDown) { move(by: 1) }
                    .disabled(service.rules.last?.id == rule.id)
                Divider()
                Button(strings.deleteRule, role: .destructive) { service.delete(rule.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(strings.ruleActions)
        }
        .opacity(dragging == rule.id ? 0.45 : 1)
        .contentShape(Rectangle())
        .onDrag {
            dragging = rule.id
            return NSItemProvider(object: rule.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: BrowserPickerRuleDropDelegate(target: rule.id, service: service,
                                                                          dragging: $dragging))
        .accessibilityAction(named: Text(strings.moveUp)) { move(by: -1) }
        .accessibilityAction(named: Text(strings.moveDown)) { move(by: 1) }
    }

    private func move(by offset: Int) {
        var rules = service.rules
        guard let index = rules.firstIndex(where: { $0.id == rule.id }),
              rules.indices.contains(index + offset) else { return }
        rules.swapAt(index, index + offset)
        service.setRules(rules)
    }
}

/// Order is priority, so the list reorders live as a dragged rule passes
/// over the others, like the Radial menu's actions.
private struct BrowserPickerRuleDropDelegate: DropDelegate {
    let target: UUID
    let service: BrowserPickerService
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        var rules = service.rules
        guard let dragging, dragging != target,
              let from = rules.firstIndex(where: { $0.id == dragging }),
              let to = rules.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            rules.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            service.setRules(rules)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct BrowserPickerDragCleanup: DropDelegate {
    @Binding var dragging: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
