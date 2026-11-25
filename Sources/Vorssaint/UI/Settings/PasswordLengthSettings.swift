// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PasswordLengthSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var service = PasswordLengthService()
    @State private var minimum = 8
    @State private var pending: PasswordLengthPolicy.Action?
    @State private var confirming = false

    var body: some View {
        let strings = FeatureStrings.passwordLength(l10n.language)
        Section {
            Text(strings.caption).font(.caption).foregroundStyle(.secondary)
            if service.busy {
                ProgressView().controlSize(.small).accessibilityLabel(strings.title)
            } else if let snapshot = service.snapshot, let rules = try? snapshot.rules() {
                if rules.contains(where: { $0.scope == .global }) ||
                    ((try? service.saved?.rules().contains { $0.scope == .global }) == true) {
                    Text(strings.shared).font(.caption).foregroundStyle(.orange)
                }
                if service.saved != nil {
                    Button(strings.restore) { ask(.restore) }
                } else if !rules.isEmpty {
                    let count = rules.compactMap { PasswordLengthPolicy.minimum(in: $0.policy) }.max() ?? 0
                    LabeledContent(strings.minimum, value: "\(count)")
                    Button(strings.disable) { ask(.disable) }
                } else {
                    Text(strings.none).foregroundStyle(.secondary)
                    Stepper(value: $minimum, in: 1...64) {
                        LabeledContent(strings.minimum, value: "\(minimum)")
                    }
                    Button(strings.enable) { ask(.enable) }
                }
            }
            if service.failed {
                Text(strings.failed).font(.caption).foregroundStyle(.orange)
            }
            Button(strings.refresh) { service.refresh() }.disabled(service.busy)
        } header: {
            Label(strings.title, systemImage: "key")
        }
        .onAppear { service.refresh() }
        .alert(strings.title, isPresented: $confirming) {
            Button(l10n.s.uninstallerCancel, role: .cancel) { pending = nil }
            Button(strings.continueAction) {
                if let pending {
                    service.perform(pending, minimum: pending == .enable ? minimum : nil, prompt: strings.title)
                }
                pending = nil
            }
        } message: {
            Text(strings.confirm)
        }
    }

    private func ask(_ action: PasswordLengthPolicy.Action) {
        pending = action
        confirming = true
    }
}
