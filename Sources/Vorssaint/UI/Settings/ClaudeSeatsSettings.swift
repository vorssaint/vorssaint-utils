// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// What a seat's sign-in command can do: go to the clipboard, or to a
/// Terminal window where the person runs it.
enum ClaudeSeatActions {
    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    static func openTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The Claude seats whose limits show side by side on the AI page, each
/// through a Claude Code profile of its own that the person signs in.
struct ClaudeSeatsSettings: View {
    @AppStorage(DefaultsKey.notchAgentsClaudeSeats) private var saved = ""
    @AppStorage(DefaultsKey.notchAgentsClaudeOrgLabel) private var organization = ""
    @ObservedObject private var service = ClaudeSeatLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var adding = false

    private var profiles: [ClaudeSeatProfile] { ClaudeSeatProfile.decode(saved) }
    private var text: ClaudeSeatStrings { FeatureStrings.claudeSeats(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.subheadline.weight(.medium))
            Text(text.explanation)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                row(profile, index: index)
            }
            HStack {
                Button(text.find) { find() }
                    .disabled(profiles.count >= ClaudeSeatProfile.maximum)
                Button(text.add) { adding.toggle() }
                    .disabled(profiles.count >= ClaudeSeatProfile.maximum)
            }
            if adding { addSheet }
            if !profiles.isEmpty {
                LabeledContent(text.orgLabel) {
                    TextField(text.orgLabel, text: Binding(get: { organization },
                                                           set: { organization = String($0.prefix(40)) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .labelsHidden()
                }
            }
            Text(text.fallback)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { service.synchronize() }
    }

    private func row(_ profile: ClaudeSeatProfile, index: Int) -> some View {
        let state = service.states.first { $0.id == profile.id }
        let identity = state?.identity ?? ClaudeSeatIdentity.read(profile.profileURL)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(identity?.email ?? text.notSignedIn).lineLimit(1).truncationMode(.middle)
                    if let account = identity?.account, account == service.activeAccount {
                        Text(text.inApp)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AgentProvider.claude.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AgentProvider.claude.tint.opacity(0.14), in: Capsule())
                    }
                }
                Text([profile.directory.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path,
                                                             with: "~"),
                      identity?.organizationName, identity?.plan?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            status(state)
            Button { move(profile, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).disabled(index == 0).help(text.moveUp).accessibilityLabel(text.moveUp)
            Button { move(profile, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).disabled(index == profiles.count - 1).help(text.moveDown)
                .accessibilityLabel(text.moveDown)
            Button { save(profiles.filter { $0.id != profile.id }) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).help(text.remove).accessibilityLabel(text.remove)
        }
    }

    @ViewBuilder private func status(_ state: ClaudeSeatState?) -> some View {
        let (label, tint): (String, Color) = {
            guard let state else { return (text.notChecked, .secondary) }
            if state.checking && state.limits == nil { return (text.checking, .secondary) }
            switch state.failure {
            case .needsSignIn?: return (text.signInNeeded, .orange)
            case .missing?: return (text.missing, .orange)
            case .outdated?: return (text.outdated, .orange)
            case .unreachable? where state.limits == nil: return (text.failed, .orange)
            default: break
            }
            guard let checked = state.limits?.observedAt else { return (text.notChecked, .secondary) }
            return (text.checked(checked.formatted(.relative(presentation: .named)
                .locale(l10n.language.formattingLocale()))), .green)
        }()
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// The command for the next free `~/.claude-seatN`, to copy or run.
    private var addSheet: some View {
        let command = ClaudeSeatProfile.signInCommand(existing: profiles)
        return VStack(alignment: .leading, spacing: 6) {
            Text(text.addTitle).font(.callout.weight(.semibold))
            Text(text.addExplanation)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack {
                Spacer()
                Button(text.copyCommand) { ClaudeSeatActions.copy(command) }
                Button(text.openTerminal) { ClaudeSeatActions.openTerminal() }
                Button(text.done) {
                    find()
                    adding = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Adds the signed-in `~/.claude-*` folders not on the list yet.
    private func find() {
        var updated = profiles
        for profile in ClaudeSeatProfile.discover() where !updated.contains(where: {
            $0.canonicalDirectory == profile.canonicalDirectory
        }) { updated.append(profile) }
        save(Array(updated.prefix(ClaudeSeatProfile.maximum)))
    }

    private func move(_ profile: ClaudeSeatProfile, by offset: Int) {
        var updated = profiles
        guard let index = updated.firstIndex(of: profile), updated.indices.contains(index + offset) else { return }
        updated.swapAt(index, index + offset)
        save(updated)
    }

    private func save(_ value: [ClaudeSeatProfile]) {
        saved = ClaudeSeatProfile.encode(value)
        AgentUsageService.shared.syncWithPreferences()
    }
}
