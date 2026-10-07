// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct URLCleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.urlCleanerCustomParameters) private var globalNames = ""
    @AppStorage(DefaultsKey.urlCleanerSiteParameters) private var siteNames = ""
    @AppStorage(DefaultsKey.urlCleanerDisabledParameters) private var disabledNames = ""
    @AppStorage(DefaultsKey.urlCleanerImportedParameters) private var importedNames = ""
    /// `file name|ISO 8601 date`, only to say which file the imported rules came from.
    @AppStorage(DefaultsKey.urlCleanerImportedSource) private var importedSource = ""
    @State private var pendingImport: (file: String, rules: URLCleaning.ClearURLsImport)?
    @State private var importError: String?
    @State private var confirmingRemoval = false
    @State private var siteFilter = ""
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
                          disabledNames: disabledNames,
                          importedNames: importedNames)
    }

    private var importText: URLCleanerImportStrings { FeatureStrings.urlCleanerImport(l10n.language) }

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

            rulesSection

            importSection

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
        .alert(importTitle, isPresented: showingImport, presenting: pendingImport) { pending in
            Button(importText.cancel, role: .cancel) {}
            Button(importedNames.isEmpty ? importText.importConfirm : importText.replaceConfirm) {
                importedNames = URLCleaning.storageValue(forTokens: pending.rules.parameters)
                importedSource = pending.file + "|" + Date.now.formatted(.iso8601)
            }
        } message: { pending in
            Text(importSummary(pending.rules))
        }
        .alert(importText.removeTitle, isPresented: $confirmingRemoval) {
            Button(importText.cancel, role: .cancel) {}
            Button(importText.removeConfirm, role: .destructive) {
                importedNames = ""
                importedSource = ""
            }
        } message: {
            Text(String(format: importText.removeMessageFormat, importedSiteCount) + "\n\n" + importText.keepsChoices)
        }
    }

    private var rulesSection: some View {
        Section(l10n.s.urlCleanerRulesTitle) {
            let groups = URLCleaning.ruleGroups(rules: rules)
            // Only an imported table makes the list long enough to search.
            if groups.count > 15 {
                TextField("", text: $siteFilter, prompt: Text(importText.filterPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel(importText.filterPlaceholder)
            }
            ForEach(groups.filter(matchesFilter)) { group in
                DisclosureGroup {
                    parameterGrid(for: group)
                    addParameterRow(site: group.site)
                } label: {
                    HStack {
                        Text(title(for: group.site))
                        if group.entries.allSatisfy({ $0.source == .imported }) {
                            importedTag
                        }
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
    }

    private func matchesFilter(_ group: URLCleaning.RuleGroup) -> Bool {
        siteFilter.isEmpty || title(for: group.site).localizedCaseInsensitiveContains(siteFilter)
    }

    /// The imported layer can be replaced as a whole or removed. Remove sits
    /// on its own row, away from Replace, so one slip cannot take the rules
    /// out when someone meant to update them.
    private var importSection: some View {
        Section(importText.sectionTitle) {
            Text(importedStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(importedNames.isEmpty ? importText.importButton : importText.replaceButton) {
                    chooseRulesFile()
                }
                Spacer()
                Link(importText.openRules, destination: URL(string: "https://github.com/ClearURLs/Rules")!)
            }
            Text(importText.fileCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !importedNames.isEmpty {
                Button(importText.removeButton, role: .destructive) { confirmingRemoval = true }
            }
        }
    }

    private var importedTag: some View {
        Text(importText.importedTag)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var importedSiteCount: Int {
        rules.imported.keys.filter { $0 != URLCleaning.allSites }.count
    }

    private var importedStatus: String {
        guard !importedNames.isEmpty else { return importText.emptyCaption }
        let separator = importedSource.lastIndex(of: "|") ?? importedSource.endIndex
        let date = (try? Date(String(importedSource[separator...].dropFirst()), strategy: .iso8601))
            .map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(l10n.language.formattingLocale())) } ?? ""
        return String(format: importText.summaryFormat, String(importedSource[..<separator]), date,
                      importedSiteCount, rules.imported.values.reduce(0) { $0 + $1.count })
    }

    private var showingImport: Binding<Bool> {
        Binding { pendingImport != nil } set: { if !$0 { pendingImport = nil } }
    }

    private var importTitle: String {
        let file = pendingImport?.file ?? ""
        return String(format: importedNames.isEmpty ? importText.importTitleFormat : importText.replaceTitleFormat, file)
    }

    /// What the file adds, or what it changes about the rules already
    /// imported, then what it leaves out.
    private func importSummary(_ rules: URLCleaning.ClearURLsImport) -> String {
        let before = Set(importedNames.split(separator: ","))
        let after = Set(URLCleaning.storageValue(forTokens: rules.parameters).split(separator: ","))
        var lines = [before.isEmpty
            ? String(format: importText.addsFormat, after.count,
                     rules.parameters.keys.filter { $0 != URLCleaning.allSites }.count)
            : String(format: importText.changesFormat, after.subtracting(before).count,
                     before.subtracting(after).count, after.intersection(before).count)]
        if rules.skipped > 0 { lines.append(String(format: importText.skippedFormat, rules.skipped)) }
        if rules.exceptions > 0 { lines.append(String(format: importText.exceptionsFormat, rules.exceptions)) }
        lines.append(importText.keepsChoices)
        return lines.joined(separator: "\n\n")
    }

    /// Reads at most a little over the limit, like the lyrics import, so a
    /// huge file is refused without being loaded. ClearURLs' file is about
    /// 100 KB.
    private func chooseRulesFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importError = nil
        let limit = 1 << 20
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: limit + 1) else {
            importError = importText.errorUnreadable
            return
        }
        try? handle.close()
        guard data.count <= limit else {
            importError = importText.errorTooLarge
            return
        }
        do {
            pendingImport = (url.lastPathComponent, try URLCleaning.clearURLsImport(from: data))
        } catch URLCleaning.ClearURLsImportError.tooManyNames {
            importError = importText.errorTooMany
        } catch URLCleaning.ClearURLsImportError.nothingUsable {
            importError = importText.errorNothingUsable
        } catch {
            importError = importText.errorNotClearURLs
        }
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
                    if entry.source == .imported {
                        importedTag
                    }
                    if entry.source == .custom {
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
    /// so on can clear the row's record and bring it back as it was.
    private func setSite(_ group: URLCleaning.RuleGroup, enabled: Bool) {
        var disabled = URLCleaning.tokens(from: disabledNames)
        disabled[group.site] = enabled ? nil : Set(group.entries.map(\.name))
        disabledNames = URLCleaning.storageValue(forTokens: disabled)
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
