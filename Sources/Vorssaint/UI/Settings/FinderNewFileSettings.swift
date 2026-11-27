// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// A section of the existing Finder settings page, not a separate utility UI.
struct FinderNewFileSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.finderNewFileEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderNewFileKinds) private var selection = FinderNewFileKind.defaultSelection

    private var strings: FinderNewFileStrings {
        FinderNewFileStrings.localized(l10n.language.rawValue)
    }

    var body: some View {
        Section {
            Toggle(strings.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in FinderNewFileService.syncWithPreferences() }
            Text(strings.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            FinderNewFileExtensionStatus()
            if enabled {
                ForEach(FinderNewFileKind.allCases, id: \.self) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.title(strings), systemImage: kind.symbol)
                    }
                }
            }
        } header: {
            Text(strings.title)
        }
        .settingsFormSectionAnchor(.finderNewFile)
        .onChange(of: selection) { _, _ in FinderNewFileService.syncWithPreferences() }
    }

    private func binding(for kind: FinderNewFileKind) -> Binding<Bool> {
        Binding(get: { FinderNewFileKind.selection(selection).contains(kind) },
                set: { value in
                    var kinds = Set(FinderNewFileKind.selection(selection))
                    if value { kinds.insert(kind) } else { kinds.remove(kind) }
                    selection = FinderNewFileKind.allCases.filter { kinds.contains($0) }
                        .map(\.rawValue).joined(separator: ",")
                })
    }
}


/// Mirrors PermissionRow's status and actions without treating a Finder
/// extension as a TCC permission. The management entry stays available even
/// when the feature switch is off, so the user can disable the extension.
struct FinderNewFileExtensionStatus: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var observation = FinderNewFileExtensionObservation.shared
    @State private var demandID = UUID()

    private var strings: FinderNewFileStrings {
        FinderNewFileStrings.localized(l10n.language.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let enabled = observation.extensionEnabled {
                    Image(systemName: enabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(enabled ? .green : .orange)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(strings.extensionName)
                Spacer()
                if let enabled = observation.extensionEnabled {
                    Text(enabled ? strings.extensionEnabled : strings.extensionDisabled)
                        .font(.caption)
                        .foregroundStyle(enabled ? .green : .orange)
                }
            }
            if observation.extensionEnabled == false {
                Text(strings.extensionHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(strings.manage) {
                FinderNewFileService.openExtensionSettings()
                observation.refresh()
            }
            .controlSize(.small)
        }
        .onAppear { observation.setVisible(demandID, true) }
        .onDisappear { observation.setVisible(demandID, false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            observation.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            observation.refresh()
        }
    }
}

/// Like the existing permission observation, use one shared timer only while
/// a status surface is visible. Poll even while System Settings is frontmost
/// so toggling the extension can update the status before returning. The
/// synchronous system query is serialized off the UI thread.
private final class FinderNewFileExtensionObservation: ObservableObject {
    static let shared = FinderNewFileExtensionObservation()

    @Published private(set) var extensionEnabled: Bool?
    private var demands: Set<UUID> = []
    private var timer: Timer?
    private var inFlight = false

    func setVisible(_ id: UUID, _ visible: Bool) {
        if visible {
            demands.insert(id)
            refresh()
            if timer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    self?.refresh()
                }
                timer.tolerance = 0.15
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        } else {
            demands.remove(id)
            if demands.isEmpty {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    func refresh() {
        guard !demands.isEmpty, !inFlight else { return }
        inFlight = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let enabled = FinderNewFileService.extensionEnabled
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if self.extensionEnabled != enabled {
                    self.extensionEnabled = enabled
                }
            }
        }
    }
}
