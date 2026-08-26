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
    @State private var output = ""
    @State private var message: String?
    @State private var showingAddSite = false
    private var canClearInput: Bool { !input.isEmpty || !output.isEmpty || message != nil }
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
                            // Two dozen names for one site is a lot of clicking
                            // to say "not this site". The names stay listed and
                            // can be switched back on one at a time.
                            Button {
                                disableEverything(in: group)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(group.enabledCount == 0)
                            .help(l10n.s.urlCleanerRulesRemoveSiteButton)
                            .accessibilityLabel(l10n.s.urlCleanerRulesRemoveSiteButton)
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
                        .onSubmit { clean() }
                    Button {
                        clearInput()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary.opacity(canClearInput ? 1 : 0.35))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.urlCleanerClearButton)
                    .disabled(!canClearInput)
                }
                HStack {
                    Button(l10n.s.urlCleanerPasteButton) { paste() }
                    Button(l10n.s.urlCleanerCleanButton) { clean() }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(l10n.s.urlCleanerCopyButton) { copy() }
                        .disabled(output.isEmpty)
                }
                if output.isEmpty {
                    Text(message ?? l10n.s.urlCleanerOutputPlaceholder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
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

    /// Switches off every built-in name for a site and drops the ones the user
    /// added to it, which is what "not this site" means in a model that stores
    /// edits as a difference from the shipped tables rather than a copy.
    private func disableEverything(in group: URLCleaning.RuleGroup) {
        var disabled = URLCleaning.tokens(from: disabledNames)
        for entry in group.entries where entry.isBuiltIn {
            disabled[group.site, default: []].insert(entry.name)
        }
        disabledNames = URLCleaning.storageValue(forTokens: disabled)

        let added = group.entries.filter { !$0.isBuiltIn }.map(\.name)
        guard !added.isEmpty else { return }
        if group.site == URLCleaning.allSites {
            var names = URLCleaning.customParameters(from: globalNames)
            for name in added { names.remove(name) }
            globalNames = URLCleaning.storageValue(forNames: names)
        } else {
            var siteTokens = URLCleaning.tokens(from: siteNames)
            for name in added { siteTokens[group.site]?.remove(name) }
            siteNames = URLCleaning.storageValue(forTokens: siteTokens)
        }
    }

    private func remove(_ name: String, from site: String) {
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
            self.clean()
        })
    }

    private func clean() {
        let result = cleaner.clean(input)
        output = result?.url ?? ""
        switch URLCleaning.outcome(for: result, input: input) {
        case .notAURL: message = l10n.s.urlCleanerNoURL
        case .unchanged: message = l10n.s.urlCleanerNoChange
        case .rewritten: message = l10n.s.urlCleanerCleaned
        case .removed(let names): message = removedSummary(names)
        }
    }

    private func copy() {
        guard !output.isEmpty else { return }
        cleaner.copy(output)
        message = l10n.s.urlCleanerCopied
    }

    private func clearInput() {
        input = ""
        output = ""
        message = nil
    }
}
