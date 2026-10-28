// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DockSpacerCard: View {
    let language: AppLanguage
    var service: DockSpacerService = .live
    @AppStorage(DefaultsKey.dockSpacerRestartAfterAdding) private var restartAfterAdding = false
    @State private var busy = false
    @State private var result: (action: DockSpacerService.Action, outcome: DockSpacerService.Result)?

    private var text: DockSpacerStrings { FeatureStrings.dockSpacer(language) }

    var body: some View {
        SettingsCard(title: text.title) {
            Text(text.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { addButtons }
                VStack(alignment: .trailing, spacing: 10) { addButtons }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Divider()
            HStack(spacing: 12) {
                Text(text.restartAfterAdding)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Toggle(text.restartAfterAdding, isOn: $restartAfterAdding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Text(text.restartCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if busy {
                    ProgressView().controlSize(.small)
                }
                Button(text.restart) { perform(.restart) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            if let result {
                Label(message(for: result.action, outcome: result.outcome),
                      systemImage: result.outcome.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .buttonStyle(.bordered)
        .disabled(busy)
    }

    private var addButtons: some View {
        Group {
            Button(text.addLarge) { perform(.addLarge) }
            Button(text.addSmall) { perform(.addSmall) }
        }
    }

    private func perform(_ action: DockSpacerService.Action) {
        guard !busy, AppFeature.dockSpacer.isAvailable else { return }
        busy = true
        result = nil
        let shouldRestart = restartAfterAdding
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                service.perform(action, restartAfterAdding: shouldRestart)
            }.value
            result = (action, outcome)
            busy = false
        }
    }

    private func message(for action: DockSpacerService.Action, outcome: DockSpacerService.Result) -> String {
        switch outcome {
        case .added:
            return action == .addLarge ? text.largeAdded : text.smallAdded
        case .restarted:
            switch action {
            case .addLarge: return text.largeAddedAndRestarted
            case .addSmall: return text.smallAddedAndRestarted
            case .restart: return text.restarted
            }
        case .addFailed: return text.addFailed
        case .restartFailed: return text.restartFailed
        case .addedButRestartFailed: return text.addedButRestartFailed
        }
    }
}
