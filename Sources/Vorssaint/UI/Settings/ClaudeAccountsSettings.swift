// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Claude Code profiles found on this Mac, each with a switch for its
/// limits card on the AI page. Shown only once there is more than `~/.claude`.
struct ClaudeAccountsSettings: View {
    @AppStorage(DefaultsKey.notchAgentsHiddenClaudeProfiles) private var hidden = ""
    @ObservedObject private var service = CodexProfileLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    /// Read on each draw, not on appear: with no profiles yet the section has
    /// nothing on screen, so an appear handler would never run.
    private var profiles: [CodexAccountProfile] {
        ClaudeAccountProfile.discover(defaultName: FeatureStrings.codexAccounts(l10n.language).defaultName)
    }
    private var text: ClaudeAccountStrings { FeatureStrings.claudeAccounts(l10n.language) }

    var body: some View {
        let profiles = profiles
        Group {
            if !profiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text.title).font(.subheadline.weight(.medium))
                    Text(text.explanation)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(profiles) { profile in
                        Toggle(isOn: Binding(
                            get: { !hidden.split(separator: ",").contains(Substring(profile.id)) },
                            set: { shown in
                                ClaudeAccountProfile.setHidden(!shown, id: profile.id)
                                service.synchronize()
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                Text(profile.directory).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    .truncationMode(.middle).help(profile.directory)
                            }
                        }
                        .toggleStyle(TrailingSwitchToggleStyle())
                        .accessibilityLabel("Claude · " + profile.name)
                    }
                }
            }
        }
    }
}
