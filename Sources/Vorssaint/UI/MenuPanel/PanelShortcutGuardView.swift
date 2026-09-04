// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct PanelShortcutGuardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = ShortcutGuardService.shared

    @AppStorage(DefaultsKey.shortcutGuardEnabled)
    private var enabled = true

    @State private var showingPicker = false
    @State private var recorderError: String?
    @State private var isRecording = false
    @State private var dropTargeted = false

    var onClose: () -> Void

    private var strings: ShortcutGuardStrings {
        FeatureStrings.shortcutGuard(l10n.language)
    }

    private var needsAccessibility: Bool {
        enabled
            && !service.appIdentities.isEmpty
            && !service.blockedShortcuts.isEmpty
            && !permissions.accessibility
    }

    private var recorderValue: GlobalShortcut? {
        service.blockedShortcuts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if showingPicker {
                appPicker
            } else {
                configurationContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.syncWithPreferences()
        }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
        }
    }

    @ViewBuilder
    private var configurationContent: some View {
        Toggle(strings.enable, isOn: $enabled)
            .toggleStyle(.switch)
            .font(.system(size: 11.5, weight: .medium))
            .onChange(of: enabled) { _, _ in
                service.syncWithPreferences()
            }

        applicationsCard
        shortcutsCard

        if needsAccessibility {
            PermissionRow(kind: .accessibility)
                .panelCard()
        }
    }

    private var appPicker: some View {
        let excluded = Set(service.appIdentities)
        return AppPickerView(
            compact: true,
            canBrowseApplications: true,
            acceptsExecutables: true,
            onCancel: { showingPicker = false },
            onSelect: { url in
                showingPicker = false
                _ = service.addPickedURL(url)
            },
            loadApps: {
                service.selectableApplications(excluding: excluded)
            }
        )
        .panelCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.title, systemImage: AppFeature.shortcutGuard.symbolName)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    private var applicationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.applications)
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button {
                    showingPicker = true
                } label: {
                    Label(strings.add, systemImage: "plus")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            dropZone

            if service.appIdentities.isEmpty {
                Text(strings.noApplications)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 2)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(service.appIdentities, id: \.self) { identity in
                            applicationRow(identity)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(9)
        .panelCard()
    }

    private var dropZone: some View {
        VStack(spacing: 3) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Text(strings.dropFromFinder)
                .font(.system(size: 10.5, weight: .medium))
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(dropTargeted ? 0.12 : 0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(dropTargeted ? 0.65 : 0.38),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            service.addPickedURLs(urls) > 0
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .animation(.easeOut(duration: 0.12), value: dropTargeted)
    }

    private func applicationRow(_ identity: String) -> some View {
        HStack(spacing: 7) {
            Image(nsImage: InstalledApps.icon(for: identity))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(InstalledApps.name(for: identity))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)

                Text(InstalledApps.location(for: identity) ?? identity)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 4)

            Button {
                service.removeAppIdentity(identity)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.s.actionRemove)
            .accessibilityLabel(l10n.s.actionRemove)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        }
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(strings.blockedShortcuts)
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()

                ShortcutRecorderButton(
                    shortcut: recorderValue,
                    isEnabled: enabled,
                    waitingTitle: l10n.s.shortcutPressKeys,
                    emptyTitle: strings.record,
                    notCapturedAction: {
                        recorderError = l10n.s.shortcutNotCaptured
                    },
                    recordingChanged: { recording in
                        isRecording = recording
                        if recording { recorderError = nil }
                    },
                    invalidAction: {
                        recorderError = l10n.s.shortcutInvalid
                    },
                    captureAction: { shortcut in
                        recorderError = nil
                        service.addShortcut(shortcut)
                    }
                )
                .frame(width: 104)
            }

            if service.blockedShortcuts.isEmpty {
                Text(strings.noShortcuts)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.blockedShortcuts, id: \.self) { shortcut in
                    HStack {
                        Text(shortcut.displayString)
                            .font(.system(size: 11, design: .rounded))

                        Spacer()

                        Button {
                            service.removeShortcut(shortcut)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.s.actionRemove)
                        .accessibilityLabel(l10n.s.actionRemove)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.07))
                    }
                }
            }

            if let recorderError {
                Text(recorderError)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Text(strings.activeCaption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .panelCard()
    }
}
