// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FinderToolsView: View {
    @ObservedObject var service: FinderToolsService
    @ObservedObject private var l10n = L10n.shared
    @State private var confirming = false
    private var text: FinderToolsStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.title).font(.title2.bold())
            Text(text.description).foregroundStyle(.secondary)
            HStack {
                Button(l10n.s.menuSettings) { service.openConfiguration() }
                if !service.configuration.savedActions.isEmpty {
                    Menu(FeatureStrings.radialMenu(l10n.language).actionsHeader) {
                        ForEach(service.configuration.savedActions.filter { $0.group == nil }) { saved in
                            Button(saved.title) { service.pendingSavedAction = saved }
                        }
                        ForEach(savedGroups, id: \.self) { group in
                            Menu(group) {
                                ForEach(service.configuration.savedActions.filter { $0.group == group }) { saved in
                                    Button(saved.title) { service.pendingSavedAction = saved }
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            Menu(l10n.s.quickToolsTab) {
                ForEach(RadialMenuTool.allCases.filter { $0 != .finderTools && $0.isRunnable() }) { tool in
                    Button(tool.feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language))) {
                        AppToolLauncher.run(tool)
                    }
                }
            }.disabled(service.isRunning)
            Form {
                Picker(text.run, selection: $service.action) {
                    ForEach(FinderToolsCategory.allCases) { category in
                        Section(category.title(language: l10n.language.rawValue)) {
                            ForEach(service.configuration.menu.orderedActions.filter { $0.category == category }) { action in
                                Text(service.configuration.menu.title(for: action, language: l10n.language.rawValue)).tag(action)
                            }
                        }
                    }
                }
                if service.action.needsSelection {
                    HStack {
                        Text("\(text.selection): \(service.selection.count)")
                        Spacer()
                        Button(text.chooseFiles) { service.chooseFiles() }
                    }
                    if !service.selection.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading) {
                                ForEach(Array(service.selection.enumerated()), id: \.offset) { index, url in
                                    HStack {
                                        Text(url.path).font(.caption).textSelection(.enabled)
                                        Spacer()
                                        Button("↑") { service.selection.swapAt(index, index - 1) }.disabled(index == 0)
                                        Button("↓") { service.selection.swapAt(index, index + 1) }.disabled(index == service.selection.count - 1)
                                        Button(l10n.s.actionRemove) { service.selection.remove(at: index) }
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }
                }
                if service.action.needsDestination {
                    HStack {
                        Text(text.destination)
                        Text(service.destination?.path ?? "—")
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            .help(service.destination?.path ?? text.chooseFolder)
                        Spacer()
                        Button(text.chooseFolder) { service.chooseDestination() }
                    }
                }
                if service.action == .openTerminal {
                    Picker("Terminal", selection: $service.terminalTarget) {
                        ForEach(FinderTerminalTarget.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if service.terminalTarget != .cmux {
                        Picker(text.open, selection: $service.terminalMode) {
                            ForEach(FinderTerminalMode.allCases) { Text($0.title(l10n.language.rawValue)).tag($0) }
                        }
                    }
                }
                if service.action == .newFile {
                    Picker(l10n.s.mediaFormat, selection: Binding(get: {
                        (service.name as NSString).pathExtension.lowercased()
                    }, set: { fileExtension in
                        service.name = (service.name as NSString).deletingPathExtension + "." + fileExtension
                    })) {
                        ForEach(FinderNewFileTemplates.extensions, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                }
                if service.action == .fileTree || service.action == .directoryTree {
                    Stepper("↳ \(service.treeDepth)", value: $service.treeDepth, in: 1...32)
                }
                if service.action == .encryptedDiskImage {
                    SecureField(FinderToolsStrings.password(l10n.language), text: $service.password)
                }
                if service.action == .watermarkPDF {
                    TextField(MediaImageConverterStrings.localized(l10n.language).watermarkTextPlaceholder,
                              text: $service.watermark)
                }
                if service.action == .recolor {
                    ColorPicker(l10n.s.colorPickerName, selection: $service.imageColor, supportsOpacity: false)
                }
                if service.action == .repairNames {
                    Picker(l10n.s.mediaFormat, selection: $service.filenameEncoding) {
                        Text("Windows-1252 → UTF-8").tag(String.Encoding.windowsCP1252.rawValue)
                        Text("ISO-8859-1 → UTF-8").tag(String.Encoding.isoLatin1.rawValue)
                        Text("Mac Roman → UTF-8").tag(String.Encoding.macOSRoman.rawValue)
                    }
                    if let changes = try? FinderSearchTools.repairedNames(service.selection,
                        encoding: .init(rawValue: service.filenameEncoding)) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            Text("\(change.source.lastPathComponent) → \(change.newName)").font(.caption)
                        }
                    } else { Text(text.failure).foregroundStyle(.red) }
                }
                if service.action.needsName {
                    TextField(text.name, text: $service.name)
                    if service.action == .batchRename {
                        Text("{n} · {name} · {stem} · {ext}").font(.caption.monospaced()).foregroundStyle(.secondary)
                        ForEach(Array(FinderBatchTools.renameChanges(service.selection, pattern: service.name).enumerated()), id: \.offset) { _, change in
                            Text("\(change.source.lastPathComponent) → \(change.newName)")
                                .font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }.disabled(service.isRunning)
            if let result = service.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.failures.isEmpty ? text.success : text.failure)
                        if let output = result.text {
                            Text(output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                        ForEach(result.outputs, id: \.self) { url in
                            Text(url.path).font(.caption).textSelection(.enabled)
                        }
                        ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
                            Text("\(failure.url.lastPathComponent): \(failure.reason)")
                                .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error = service.error {
                Text(text.failure).foregroundStyle(.red)
                Text(error).font(.caption).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack {
                if service.isRunning {
                    ProgressView().controlSize(.small)
                    Button(text.cancel) { service.cancel() }.disabled(!service.canCancel)
                }
                if service.result?.text != nil {
                    Button(l10n.s.menuCopy) { service.copyResult() }
                }
                Spacer()
                Button(service.action.title(languageCode: l10n.language.rawValue)) {
                    if service.action.changesSources { confirming = true }
                    else { service.run() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.isRunning
                          || (service.action.needsSelection && service.selection.isEmpty)
                          || (service.action.needsDestination && service.destination == nil)
                          || (service.action.needsName && service.name.isEmpty))
            }
        }
        .padding(22)
        .confirmationDialog(service.pendingSavedAction?.title ?? "", isPresented: Binding(get: {
            service.pendingSavedAction != nil
        }, set: { if !$0 { service.pendingSavedAction = nil } })) {
            if let saved = service.pendingSavedAction {
                Button(text.run) {
                    service.runSavedAction(saved)
                    service.pendingSavedAction = nil
                }
            }
            Button(text.cancel, role: .cancel) { service.pendingSavedAction = nil }
        } message: {
            if let saved = service.pendingSavedAction {
                Text((saved.kind == .website ? saved.location.absoluteString : saved.location.path) + "\n" + service.selection.map(\.path).joined(separator: "\n"))
            }
        }
        .confirmationDialog(service.action.title(languageCode: l10n.language.rawValue), isPresented: $confirming) {
            Button(service.action.title(languageCode: l10n.language.rawValue),
                   role: service.action == .permanentDelete ? .destructive : nil) { service.run() }
            Button(text.cancel, role: .cancel) { }
        } message: {
            Text(service.selection.map(\.lastPathComponent).joined(separator: "\n"))
        }
    }

    private var savedGroups: [String] {
        var seen = Set<String>()
        return service.configuration.savedActions.compactMap(\.group).filter { seen.insert($0).inserted }
    }
}
