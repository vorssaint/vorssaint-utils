// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct CommandBarSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var secureInput = SecureInputMonitor.shared
    @AppStorage(DefaultsKey.commandBarShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.commandBarCompactMode) private var compactMode = false
    @AppStorage(DefaultsKey.commandBarDisabledSources) private var disabledSources = ""
    @AppStorage(DefaultsKey.commandBarAliases) private var aliasesRaw = ""
    @AppStorage(DefaultsKey.commandBarPins) private var pinsRaw = ""
    @AppStorage(DefaultsKey.commandBarHidden) private var hiddenRaw = ""
    @AppStorage(DefaultsKey.commandBarLinks) private var linksData = Data()
    @AppStorage(DefaultsKey.commandBarRowShortcuts) private var rowShortcutsRaw = ""
    @AppStorage(DefaultsKey.commandBarFileScopes) private var fileScopesRaw = ""
    @AppStorage(DefaultsKey.commandBarFileIgnores) private var fileIgnoresRaw = ""
    @State private var editing: CommandBarLink?
    @State private var ignoreDraft = ""
    @State private var showsFileOptions = false

    private var text: CommandBarFeatureStrings { FeatureStrings.commandBar(l10n.language) }
    /// The snippet library already says "save", "delete" and "name" in every
    /// language; saying them twice would only mean two things to keep.
    private var common: SnippetFeatureStrings { FeatureStrings.snippets(l10n.language) }
    private var editLabel: String { FeatureStrings.screenshot(l10n.language).editButton }

    /// The examples do double duty: they say what the bar can do, which no
    /// list of toggles ever manages to.
    private var examples: [String] {
        ["100 km to mi", "2+2*3", "brightness 40", "fire", "battery"].filter {
            $0 != "battery" || PowerSampler.hasInternalBattery
        }
    }

    var body: some View {
        Form {
            Section {
                // One choice, open it or recenter it, so one row. Neither
                // carries an icon: a ⌘ glyph in front of "Open the bar now"
                // reads as the shortcut that opens it, which it is not.
                HStack(spacing: 10) {
                    Button(text.openButton) {
                        CommandBarService.shared.show()
                    }
                    Button(text.resetPositionButton) {
                        CommandBarService.shared.resetPanelPosition()
                    }
                    .disabled(!service.hasCustomPosition)
                }
                // One row for the whole explanation. As separate rows the form
                // drew a divider between every sentence, cutting one paragraph
                // about one feature into four cards that looked like settings.
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.positionCaption)
                    Text(text.settingsCaption)
                    Label(text.privacyNote, systemImage: "lock.laptopcomputer")
                    HStack(spacing: 6) {
                        Text(text.tryTheseLabel)
                            .foregroundStyle(.tertiary)
                        ForEach(examples, id: \.self) { example in
                            Text(example)
                                .font(.system(size: 10.5, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                    .padding(.top, 2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // No callback: the bar reads this on every open, and opening
                // Settings has already hidden it, so the two can never be on
                // screen with a stale value between them.
                Toggle(text.compactModeToggle, isOn: $compactMode)
                Text(text.compactModeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Not the shared "Global shortcut" label the other feature
                // pages use: this page already has an "open the bar" button at
                // the top, so the toggle has to say which of the two it arms.
                Toggle(text.shortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        CommandBarService.shared.syncWithPreferences()
                    }
                ShortcutPreferenceRow(role: .commandBar, isEnabled: shortcutEnabled) {
                    CommandBarService.shared.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if secureInput.holder != .off {
                    SecureInputRow()
                }
            } header: {
                Text(text.pageTitle)
            }

            Section {
                ForEach(CommandBarSource.allCases) { source in
                    Toggle(isOn: binding(for: source)) {
                        Label(title(for: source), systemImage: source.symbolName)
                    }
                    .disabled(source.isAlwaysOn)
                }
            } header: {
                Text(text.sourcesTitle)
            } footer: {
                Text(text.sourcesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(text.filesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if fileScopes.isEmpty {
                    Text(text.filesEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(fileScopes, id: \.self) { scope in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16)
                        Text(scope)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(text.removeButton) { removeFileScope(scope) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
                Button {
                    addFileScope()
                } label: {
                    Label(text.filesAddFolder, systemImage: "plus")
                }
                DisclosureHeaderRow(isExpanded: $showsFileOptions) {
                    Text(FeatureStrings.recorder(l10n.language).moreOptions)
                    Spacer()
                }
                if showsFileOptions {
                    Group {
                        Text(text.filesIgnoreCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(fileIgnores, id: \.self) { pattern in
                            HStack(spacing: 8) {
                                Image(systemName: "eye.slash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(pattern)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Button(text.removeButton) { removeFileIgnore(pattern) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField(text.filesIgnorePlaceholder, text: $ignoreDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addFileIgnore() }
                            Button(text.filesIgnoreAdd) { addFileIgnore() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(ignoreDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .disclosureIndent()
                }
            } header: {
                Text(text.filesTitle)
            }

            Section {
                if links.isEmpty {
                    Text(text.linksEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(links) { link in
                    HStack(spacing: 8) {
                        Image(systemName: link.kind.symbolName)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16)
                        Text(link.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text(link.destination)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(editLabel) { editing = link }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        Button(text.removeButton) { removeLink(link) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
                Button {
                    editing = CommandBarLink()
                } label: {
                    Label(text.linkAddButton, systemImage: "plus")
                }
            } header: {
                Text(text.linksTitle)
            }

            Section {
                if boundRows.isEmpty {
                    Text(text.rowShortcutsEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(boundRows, id: \.key) { entry in
                    HStack {
                        Text(entry.alias)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                        Text(entry.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        // A combination another app already holds never fires,
                        // and a row showing a dead key is worse than no key.
                        if service.refusedRowShortcutKeys.contains(entry.key) {
                            Text(l10n.s.shortcutUnavailable)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button(text.removeButton) { removeRowShortcut(entry.key) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            } header: {
                Text(text.rowShortcutsTitle)
            }

            Section {
                if named.isEmpty {
                    Text(text.namedEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(named, id: \.key) { entry in
                    HStack {
                        Text(entry.alias)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                        Text(entry.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(text.removeButton) { removeAlias(entry.key) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            } header: {
                Text(text.namedTitle)
            }

            Section {
                if pinned.isEmpty {
                    Text(text.pinnedEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(pinned, id: \.key) { entry in
                    HStack {
                        Text(entry.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Button(text.removeButton) { removePin(entry.key) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            } header: {
                Text(text.pinnedTitle)
            }

            Section {
                if hidden.isEmpty {
                    Text(text.hiddenEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(hidden, id: \.key) { entry in
                    HStack {
                        Text(entry.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Button(text.removeButton) { unhide(entry.key) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
                Button(text.forgetAllButton) {
                    CommandBarService.shared.forgetLearnedRanking()
                }
            } header: {
                Text(text.hiddenTitle)
            }
        }
        .formStyle(.grouped)
        .observesSecureInput()
        .sheet(item: $editing) { link in
            CommandBarLinkEditor(draft: link, text: text, common: common) { saved in
                save(saved)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
    }

    // MARK: - The places the person saved

    private var links: [CommandBarLink] { CommandBarLinks.decode(linksData) }

    private var boundRows: [NamedRow] {
        CommandBarRowShortcuts.decode(rowShortcutsRaw)
            .map { NamedRow(key: $0.key, title: title(forKey: $0.key), alias: $0.value.displayString) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func removeRowShortcut(_ key: String) {
        var next = CommandBarRowShortcuts.decode(rowShortcutsRaw)
        next.removeValue(forKey: key)
        rowShortcutsRaw = CommandBarRowShortcuts.encode(next) ?? ""
        CommandBarService.shared.syncWithPreferences()
    }

    private func save(_ link: CommandBarLink) {
        var next = links
        if let index = next.firstIndex(where: { $0.id == link.id }) {
            next[index] = link
        } else {
            next.append(link)
        }
        linksData = CommandBarLinks.encode(next) ?? Data()
    }

    private func removeLink(_ link: CommandBarLink) {
        linksData = CommandBarLinks.encode(links.filter { $0.id != link.id }) ?? Data()
    }

    // MARK: - The lists, resolved to something readable

    private struct NamedRow {
        let key: String
        let title: String
        let alias: String
    }

    /// A key whose row is not in the catalog right now (an app that was
    /// removed) still shows, by its key, so nothing the person set can become
    /// invisible and unremovable. An uninstalled hub feature is dropped
    /// instead: its pin is not a leftover id.
    private func title(forKey key: String) -> String {
        service.entryTitle(forStableKey: key) ?? key
    }

    private var named: [NamedRow] {
        CommandBarPreferences.decodeAliases(aliasesRaw)
            .map { NamedRow(key: $0.key, title: title(forKey: $0.key), alias: $0.value) }
            .sorted { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }
    }

    private var pinned: [NamedRow] {
        CommandBarPreferences.listedPins(
            CommandBarPreferences.decodePins(pinsRaw),
            present: service.presentStableKeys)
            .map { NamedRow(key: $0, title: title(forKey: $0), alias: "") }
    }

    private var hidden: [NamedRow] {
        CommandBarPreferences.decodeHidden(hiddenRaw)
            .sorted()
            .map { NamedRow(key: $0, title: title(forKey: $0), alias: "") }
    }

    private func binding(for source: CommandBarSource) -> Binding<Bool> {
        Binding {
            CommandBarPreferences.isEnabled(source, disabledRaw: disabledSources)
        } set: { isOn in
            var current = CommandBarPreferences.disabledSources(from: disabledSources)
            if isOn { current.remove(source) } else { current.insert(source) }
            disabledSources = CommandBarPreferences.storageValue(for: current)
        }
    }

    private func title(for source: CommandBarSource) -> String {
        switch source {
        case .actions: return text.sourceActions
        case .apps: return text.sourceApps
        case .menus: return text.sourceMenus
        case .windows: return text.sourceWindows
        case .quitApps: return text.sourceQuitApps
        case .settingsPages: return text.sourceSettingsPages
        case .macSettings: return text.sourceMacSettings
        case .snippets: return text.sourceSnippets
        case .clipboard: return text.sourceClipboard
        case .emoji: return text.sourceEmoji
        case .folders: return text.sourceFolders
        case .answers: return text.sourceAnswers
        case .calculator: return text.sourceCalculator
        case .selection: return text.sourceSelection
        case .links: return text.linksTitle
        case .files: return text.sourceFiles
        case .killProcess: return FeatureStrings.killProcess(l10n.language).pageTitle
        }
    }

    // MARK: - The folders a file search looks in

    private var fileScopes: [String] {
        CommandBarFileSearchSupport.decodeList(fileScopesRaw)
    }

    private var fileIgnores: [String] {
        CommandBarFileSearchSupport.decodeList(fileIgnoresRaw)
    }

    /// Stored with a tilde, so a list made on one Mac still points somewhere
    /// on another and a settings export stays portable.
    private func addFileScope() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map { ($0.path as NSString).abbreviatingWithTildeInPath }
        writeFileScopes(fileScopes + added)
    }

    private func removeFileScope(_ scope: String) {
        writeFileScopes(fileScopes.filter { $0 != scope })
    }

    private func addFileIgnore() {
        let pattern = ignoreDraft.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        ignoreDraft = ""
        writeFileIgnores(fileIgnores + [pattern])
    }

    private func removeFileIgnore(_ pattern: String) {
        writeFileIgnores(fileIgnores.filter { $0 != pattern })
    }

    /// Both lists are resolved once and kept, so typing never pays for
    /// reading them; the service is told the moment they change.
    private func writeFileScopes(_ scopes: [String]) {
        fileScopesRaw = CommandBarFileSearchSupport.encodeList(scopes)
        CommandBarService.shared.syncWithPreferences()
    }

    private func writeFileIgnores(_ patterns: [String]) {
        fileIgnoresRaw = CommandBarFileSearchSupport.encodeList(patterns)
        CommandBarService.shared.syncWithPreferences()
    }

    private func removeAlias(_ key: String) {
        var aliases = CommandBarPreferences.decodeAliases(aliasesRaw)
        aliases.removeValue(forKey: key)
        aliasesRaw = CommandBarPreferences.encodeAliases(aliases) ?? ""
    }

    private func removePin(_ key: String) {
        pinsRaw = CommandBarPreferences.encodePins(
            CommandBarPreferences.decodePins(pinsRaw).filter { $0 != key })
    }

    private func unhide(_ key: String) {
        var keys = CommandBarPreferences.decodeHidden(hiddenRaw)
        keys.remove(key)
        hiddenRaw = CommandBarPreferences.encodeHidden(keys)
    }
}

/// Saving a place: a name to call it by, where it goes, and the words that
/// get filled in when it opens. Deliberately three fields and a picker — the
/// person has to look at it once and know what to do.
private struct CommandBarLinkEditor: View {
    @State var draft: CommandBarLink
    let text: CommandBarFeatureStrings
    let common: SnippetFeatureStrings
    let save: (CommandBarLink) -> Void
    let cancel: () -> Void

    @ObservedObject private var l10n = L10n.shared

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.destination.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.linksTitle)
                .font(.system(size: 15, weight: .semibold))

            Picker("", selection: $draft.kind) {
                Text(text.linkKindLink).tag(CommandBarLink.Kind.link)
                Text(text.linkKindPlace).tag(CommandBarLink.Kind.place)
                Text(text.linkKindScript).tag(CommandBarLink.Kind.script)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 5) {
                Text(common.nameLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(text.linkDestinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("", text: $draft.destination)
                        .textFieldStyle(.roundedBorder)
                    if draft.kind == .place || draft.kind == .script {
                        // Typing a path by hand is how people get it wrong.
                        Button(FeatureStrings.radialMenu(l10n.language).chooseButton) {
                            chooseDestination()
                        }
                    }
                }
            }

            if draft.kind != .script {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.linkPlaceholdersHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(CommandBarLinkPlaceholder.allCases) { placeholder in
                            Button {
                                draft.destination += placeholder.token
                            } label: {
                                VStack(spacing: 1) {
                                    Text(placeholder.token)
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    Text(meaning(of: placeholder))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .help(meaning(of: placeholder))
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.scriptHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(text.scriptRunsWithoutArgument, isOn: $draft.runsWithoutArgument)
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button(l10n.s.uninstallerCancel, action: cancel)
                Button(common.saveButton) {
                    var clean = draft
                    clean.name = clean.name.trimmingCharacters(in: .whitespaces)
                    clean.destination = clean.destination.trimmingCharacters(in: .whitespaces)
                    save(clean)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func meaning(of placeholder: CommandBarLinkPlaceholder) -> String {
        switch placeholder {
        case .query: return text.placeholderQuery
        case .clipboard: return text.placeholderClipboard
        case .selection: return text.placeholderSelection
        case .date: return text.placeholderDate
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        // A script is a file, never a folder; a place can be either.
        panel.canChooseDirectories = draft.kind == .place
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.destination = url.path
        if draft.name.isEmpty { draft.name = url.lastPathComponent }
    }
}
