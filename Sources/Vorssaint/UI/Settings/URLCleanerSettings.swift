// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct URLCleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.urlCleanerCustomParameters) private var globalNames = ""
    @AppStorage(DefaultsKey.urlCleanerSiteParameters) private var siteNames = ""
    @AppStorage(DefaultsKey.urlCleanerDisabledParameters) private var disabledNames = ""
    @State private var parameterDrafts: [String: String] = [:]
    @State private var siteDraft = ""
    @State private var siteParameterDraft = ""
    @State private var input = ""
    @State private var copied: String?
    @State private var showingAddSite = false
    /// Worked out from the field on every render, so Copy always takes the
    /// link that is in the field now under the rules in force now.
    private var result: URLCleaning.Result? {
        cleaner.clean(input)
    }
    private var rules: URLCleaning.Rules {
        URLCleaning.rules(globalNames: globalNames,
                          siteNames: siteNames,
                          disabledNames: disabledNames)
    }

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.urlCleanerEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        URLCleanerService.shared.syncWithPreferences()
                    }
                Text(l10n.s.urlCleanerEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(l10n.s.urlCleanerLocalNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if enabled, cleaner.isRunning {
                    Label(l10n.s.urlCleanerActiveNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    // The automatic rewrite is silent by design. Naming what it
                    // took out is the only place someone can see that the
                    // rules did anything to a link they copied.
                    if !cleaner.lastRemoved.isEmpty {
                        Text(removedSummary(cleaner.lastRemoved))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(l10n.s.urlCleanerRulesTitle) {
                ForEach(URLCleaning.ruleGroups(rules: rules)) { group in
                    DisclosureGroup {
                        parameterGrid(for: group)
                        addParameterRow(site: group.site)
                    } label: {
                        HStack {
                            Text(title(for: group.site))
                            Spacer()
                            Text(countLabel(group.enabledCount))
                                .foregroundStyle(.secondary)
                            siteSwitch(for: group)
                        }
                    }
                }
                DisclosureHeaderRow(isExpanded: $showingAddSite) {
                    Text(l10n.s.urlCleanerRulesAddSite)
                    Spacer()
                }
                if showingAddSite {
                    addSiteRow
                        .disclosureIndent()
                }
                Text(l10n.s.urlCleanerRulesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Why the list is as long as it is. Without this the length
                // reads as "we delete a lot from your links", when a real link
                // only ever carries a handful of these.
                Text(l10n.s.urlCleanerRulesCoverageCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.s.urlCleanerManualTitle) {
                HStack(spacing: 8) {
                    TextField("", text: $input, prompt: Text(l10n.s.urlCleanerInputPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel(l10n.s.urlCleanerInputPlaceholder)
                    Button {
                        clearInput()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary.opacity(input.isEmpty ? 0.35 : 1))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.urlCleanerClearButton)
                    .disabled(input.isEmpty)
                }
                HStack {
                    Button(l10n.s.urlCleanerPasteButton) { paste() }
                    Spacer()
                    Button(l10n.s.urlCleanerCopyButton) { copy() }
                        .buttonStyle(.borderedProminent)
                        .disabled(result == nil)
                }
                if let output = result?.url {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(input.isEmpty ? l10n.s.urlCleanerOutputPlaceholder : message)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Two dozen names for one site is a lot of clicking to say "not this
    /// site", or to take it back.
    private func siteSwitch(for group: URLCleaning.RuleGroup) -> some View {
        let isOff = group.enabledCount == 0
        let label = isOff ? l10n.s.urlCleanerRulesRestoreSiteButton : l10n.s.urlCleanerRulesRemoveSiteButton
        return Button {
            setSite(group, enabled: isOff)
        } label: {
            Image(systemName: isOff ? "plus.circle" : "minus.circle")
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Two columns keep a long site list (Bilibili has two dozen names) inside
    /// a row someone can still scroll past.
    private func parameterGrid(for group: URLCleaning.RuleGroup) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 4) {
            ForEach(group.entries) { entry in
                HStack(spacing: 4) {
                    Toggle(entry.name, isOn: enabledBinding(site: group.site, name: entry.name))
                        .toggleStyle(.checkbox)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !entry.isBuiltIn {
                        Button {
                            remove(entry.name, from: group.site)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.s.urlCleanerRulesRemoveButton)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The caption belongs beside the field rather than in the section's own,
    /// which is where someone is when they need to know what a rule matches:
    /// a name, not a position, and one parameter at a time.
    private func addParameterRow(site: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("", text: parameterDraftBinding(for: site),
                          prompt: Text(l10n.s.urlCleanerRulesParameterPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel(l10n.s.urlCleanerRulesParameterPlaceholder)
                    .onSubmit { addParameter(to: site) }
                Button(l10n.s.urlCleanerRulesAddButton) { addParameter(to: site) }
                    .disabled(URLCleaning.parameterName(from: parameterDrafts[site] ?? "") == nil)
            }
            Text(l10n.s.urlCleanerRulesMatchCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// A site arrives with its first name. An empty site is not a rule, so
    /// there is nothing to store or to list until one is typed.
    private var addSiteRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $siteDraft, prompt: Text(verbatim: "example.com"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel(l10n.s.urlCleanerRulesAddSite)
                .onSubmit { addSite() }
            TextField("", text: $siteParameterDraft,
                      prompt: Text(l10n.s.urlCleanerRulesParameterPlaceholder))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel(l10n.s.urlCleanerRulesParameterPlaceholder)
                .onSubmit { addSite() }
            Button(l10n.s.urlCleanerRulesAddButton) { addSite() }
                .disabled(URLCleaning.siteKey(from: siteDraft) == nil
                            || URLCleaning.parameterName(from: siteParameterDraft) == nil)
        }
    }

    private func countLabel(_ count: Int) -> String {
        count == 1
            ? l10n.s.urlCleanerRulesCountSingular
            : String(format: l10n.s.urlCleanerRulesCountPluralFormat, count)
    }

    private func title(for site: String) -> String {
        site == URLCleaning.allSites ? l10n.s.urlCleanerRulesAllSites : site
    }

    private func removedSummary(_ names: [String]) -> String {
        String(format: l10n.s.urlCleanerRemovedFormat, names.joined(separator: ", "))
    }

    private func parameterDraftBinding(for site: String) -> Binding<String> {
        Binding { parameterDrafts[site] ?? "" } set: { parameterDrafts[site] = $0 }
    }

    private func enabledBinding(site: String, name: String) -> Binding<Bool> {
        Binding {
            !(URLCleaning.tokens(from: disabledNames)[site] ?? []).contains(name)
        } set: { isOn in
            var disabled = URLCleaning.tokens(from: disabledNames)
            if isOn {
                disabled[site]?.remove(name)
            } else {
                disabled[site, default: []].insert(name)
            }
            disabledNames = URLCleaning.storageValue(forTokens: disabled)
        }
    }

    private func addSite() {
        guard let site = URLCleaning.siteKey(from: siteDraft),
              let name = URLCleaning.parameterName(from: siteParameterDraft) else { return }
        siteDraft = ""
        siteParameterDraft = ""
        var added = URLCleaning.tokens(from: siteNames)
        added[site, default: []].insert(name)
        siteNames = URLCleaning.storageValue(forTokens: added)
    }

    private func addParameter(to site: String) {
        guard let name = URLCleaning.parameterName(from: parameterDrafts[site] ?? "") else { return }
        parameterDrafts[site] = ""
        // A name switched off earlier and then typed back in is the same
        // request as switching it on again.
        var disabled = URLCleaning.tokens(from: disabledNames)
        disabled[site]?.remove(name)
        disabledNames = URLCleaning.storageValue(forTokens: disabled)
        if site == URLCleaning.allSites {
            var names = URLCleaning.customParameters(from: globalNames)
            names.insert(name)
            globalNames = URLCleaning.storageValue(forNames: names)
        } else {
            var added = URLCleaning.tokens(from: siteNames)
            added[site, default: []].insert(name)
            siteNames = URLCleaning.storageValue(forTokens: added)
        }
    }

    /// Off switches off every name the row lists, the user's own included,
    /// so on can clear the row's record and turn every name it lists on
    /// again, one switched off by hand before included.
    private func setSite(_ group: URLCleaning.RuleGroup, enabled: Bool) {
        var disabled = URLCleaning.tokens(from: disabledNames)
        disabled[group.site] = enabled ? nil : Set(group.entries.map(\.name))
        disabledNames = URLCleaning.storageValue(forTokens: disabled)
    }

    private func remove(_ name: String, from site: String) {
        // A deleted name takes its switched off record with it, so adding it
        // again later brings it back on, as typing it back in already does.
        var disabled = URLCleaning.tokens(from: disabledNames)
        disabled[site]?.remove(name)
        disabledNames = URLCleaning.storageValue(forTokens: disabled)
        if site == URLCleaning.allSites {
            var names = URLCleaning.customParameters(from: globalNames)
            names.remove(name)
            globalNames = URLCleaning.storageValue(forNames: names)
        } else {
            var added = URLCleaning.tokens(from: siteNames)
            added[site]?.remove(name)
            siteNames = URLCleaning.storageValue(forTokens: added)
        }
    }

    /// Through the shared lane: a direct read here would both race the
    /// clipboard services on AppKit's pasteboard cache and hang the button
    /// (and with it the app) on a promised flavour nobody renders any more.
    private func paste() {
        GeneralPasteboardAccess.shared.async({
            NSPasteboard.general.string(forType: .string) ?? ""
        }, then: { pasted in
            self.input = pasted
        })
    }

    private var message: String {
        if let copied, copied == result?.url { return l10n.s.urlCleanerCopied }
        switch URLCleaning.outcome(for: result, input: input) {
        case .notAURL: return l10n.s.urlCleanerNoURL
        case .unchanged: return l10n.s.urlCleanerNoChange
        case .rewritten: return l10n.s.urlCleanerCleaned
        case .removed(let names): return removedSummary(names)
        }
    }

    private func copy() {
        guard let url = result?.url else { return }
        cleaner.copy(url)
        copied = url
    }

    private func clearInput() {
        input = ""
        copied = nil
    }
}
