// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The CLIProxyAPI hubs whose accounts get limits cards on the AI page.
struct AgentHubsSettings: View {
    @ObservedObject private var service = AgentHubLimitsService.shared
    @ObservedObject private var l10n = L10n.shared
    /// Hiding the Limits card stops the checks, so Check hubs greys out with it.
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = ""
    @State private var adding = false
    @State private var address = ""
    @State private var key = ""
    @State private var label = ""
    @State private var problem: String?
    private var text: AgentHubStrings { FeatureStrings.agentHubs(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.subheadline.weight(.medium))
            Text(text.explanation)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(service.hubs) { row($0) }
            if adding {
                form
            } else {
                HStack {
                    // Stays on with every place taken: adding a hub's address
                    // again is how it takes a new key.
                    Button(text.add) {
                        problem = nil
                        adding = true
                    }
                    if !service.hubs.isEmpty {
                        Button(text.check) { service.refresh(force: true) }
                            .disabled(!service.isEnabled || service.hubs.allSatisfy(\.checking))
                    }
                }
            }
        }
        .onAppear { service.synchronize() }
    }

    private func row(_ status: AgentHubStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(status.hub.name).font(.callout)
                Text(status.hub.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle).help(status.hub.url)
                Text(status.checking ? text.checking : text.state(status.state))
                    .font(.caption)
                    .foregroundStyle(refused(status) ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(status.accounts) { account in
                    Text(account.provider.displayName + " · " + account.name)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Button { service.remove(id: status.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).help(text.remove).accessibilityLabel(text.remove + ": " + status.hub.name)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text(text.address)
                    TextField(text.address, text: $address, prompt: Text(verbatim: "https://hub.example.net:8317"))
                        .labelsHidden().accessibilityLabel(text.address)
                }
                GridRow {
                    Text(text.key)
                    SecureField(text.key, text: $key).labelsHidden().accessibilityLabel(text.key)
                }
                GridRow {
                    Text(text.name)
                    TextField(text.name, text: $label).labelsHidden().accessibilityLabel(text.name)
                }
            }
            .textFieldStyle(.roundedBorder)
            Text(text.keyNote)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(l10n.s.uninstallerCancel) { reset() }
                Button(text.save) { save() }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
            }
        }
    }

    private func refused(_ status: AgentHubStatus) -> Bool {
        guard !status.checking, let state = status.state else { return false }
        return text.cardProblem(state) != nil
    }

    private func save() {
        guard let url = AgentHub.normalizedURL(address) else { problem = text.invalidAddress; return }
        guard let key = AgentHub.normalizedKey(key) else { problem = text.invalidKey; return }
        guard service.hubs.count < AgentHub.maximum || service.hubs.contains(where: { $0.id == url }) else {
            problem = text.full
            return
        }
        let name = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard service.add(AgentHub(url: url, label: name, key: key)) else { problem = text.saveFailed; return }
        reset()
    }

    private func reset() {
        adding = false
        address = ""
        key = ""
        label = ""
        problem = nil
    }
}
