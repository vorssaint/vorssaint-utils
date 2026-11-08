// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Folders where another computer's Claude Code logs are synced, whose usage
/// the AI page counts with this Mac's.
struct AgentSyncedFoldersSettings: View {
    @AppStorage(DefaultsKey.notchAgentsSyncedFolders) private var saved = ""
    @ObservedObject private var l10n = L10n.shared
    private var folders: [String] { NotchAgentSupport.parseSyncedFolders(saved) }
    private var text: AgentSyncedLogStrings { FeatureStrings.agentSyncedLogs(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.subheadline.weight(.medium))
            Text(text.explanation)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(folders, id: \.self) { folder in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((folder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).help(folder)
                        if !Self.exists(folder) {
                            Text(text.missing).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button { save(folders.filter { $0 != folder }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help(text.remove).accessibilityLabel(text.remove)
                }
            }
            Button(text.add) { addFolder() }
        }
    }

    private static func exists(_ folder: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder, isDirectory: &directory) && directory.boolValue
    }

    private func save(_ value: [String]) {
        saved = value.joined(separator: "\n")
        AgentUsageService.shared.syncWithPreferences()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Synced folders often sit inside a hidden one.
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = AgentLogRoot.canonical(url).path
        guard path != "/", !folders.contains(path) else { return }
        save(folders + [path])
    }
}
