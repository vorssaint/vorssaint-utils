// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Displays Antigravity configuration, detected logs, and active tracking state.
struct AntigravityAccountSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var conversationCount: Int = 0
    @State private var activeModel: String = ""
    @State private var logsFolder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NotchAgentMark(provider: .antigravity, size: 13)
                    .foregroundStyle(AgentProvider.antigravity.tint)
                    .font(.system(size: 11, weight: .semibold))
                Text("Antigravity")
                    .font(.caption.weight(.medium))
                if !activeModel.isEmpty {
                    NotchAgentChip(text: activeModel, tint: AgentProvider.antigravity.tint)
                }
                Spacer()
                if conversationCount > 0 {
                    Text(FeatureStrings.notchAgents(l10n.language).session + " · " + String(conversationCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    if let logsFolder { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsFolder.path) }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help(FeatureStrings.antigravityAccount(l10n.language).openLogs)
                .accessibilityLabel(FeatureStrings.antigravityAccount(l10n.language).openLogs)
                .disabled(logsFolder == nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .task {
            let info = await Task.detached(priority: .utility) { AntigravityLogInfo.read() }.value
            guard !Task.isCancelled else { return }
            conversationCount = info.conversations
            activeModel = info.model
            logsFolder = info.folder
        }
    }
}
