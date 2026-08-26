// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact uninstaller flow for the menu panel. It reuses AppUninstaller so the
/// scan and removal rules stay identical to the larger Settings page.
struct PanelUninstallerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var uninstaller = AppUninstaller.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @State private var dropTargeted = false
    @State private var showingAppPicker = false
    @State private var pendingHomebrewRemoval: HomebrewPackage?
    @State private var showHomebrewDetails = false

    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .dropDestination(for: URL.self) { urls, _ in
            let selected = selectFirstApp(from: urls)
            if selected {
                showingAppPicker = false
            }
            return selected
        } isTargeted: { dropTargeted = $0 }
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
            dismissHomebrewRemovalConfirmation()
        }
        .alert(l10n.s.homebrewConfirmUninstallTitle,
               isPresented: homebrewRemovalConfirmationPresented,
               presenting: pendingHomebrewRemoval) { package in
            Button(l10n.s.uninstallerCancel, role: .cancel) {
                dismissHomebrewRemovalConfirmation()
            }
            Button(l10n.s.homebrewUninstall, role: .destructive) {
                uninstaller.removeSelectedWithHomebrew()
                dismissHomebrewRemovalConfirmation()
            }
        } message: { package in
            Text(String(format: l10n.s.homebrewConfirmUninstallBodyFormat, package.displayName))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch uninstaller.phase {
        case .empty:
            if showingAppPicker {
                appPickerState
            } else {
                emptyState
            }
        case .scanning: busyState(l10n.s.uninstallerScanning)
        case .results: resultsState
        case .removing: busyState(l10n.s.uninstallerRemoving)
        case let .done(freed, failed): doneState(freed: freed, failed: failed)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(l10n.s.uninstallerName, systemImage: "trash")
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            dropZone

            Button {
                choose()
            } label: {
                Label(l10n.s.uninstallerChoose, systemImage: "plus.app")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(l10n.s.uninstallerEmptyNote)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: true)
            }
        }
        .panelCard()
    }

    private var appPickerState: some View {
        AppPickerView(compact: true) {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            uninstaller.select(appURL: url)
        }
        .panelCard()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .frame(height: 108)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.app")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                    Text(l10n.s.uninstallerDropTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.uninstallerDropSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
            )
            .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    private func busyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let target = uninstaller.target {
                HStack(spacing: 7) {
                    Image(nsImage: target.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(target.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .panelCard()
    }

    private var resultsState: some View {
        VStack(alignment: .leading, spacing: 10) {
            targetHeader
            Divider()
            leftoverList
            Divider()
            homebrewStatus
            footer
        }
        .panelCard()
    }

    private var targetHeader: some View {
        HStack(spacing: 9) {
            if let target = uninstaller.target {
                Image(nsImage: target.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(target.bundleID ?? target.url.path)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.byteString(uninstaller.totalSize))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(l10n.s.uninstallerFoundTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Button { uninstaller.reset() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(uninstaller.isRemovingWithHomebrew)
        }
    }

    private var leftoverList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppUninstaller.Category.allCases, id: \.self) { category in
                let group = uninstaller.items.filter { $0.category == category }
                if !group.isEmpty {
                    categoryGroup(group, category: category)
                }
            }
        }
    }

    private func categoryGroup(_ group: [AppUninstaller.Leftover],
                               category: AppUninstaller.Category) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label(for: category).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            ForEach(group) { item in
                row(item)
            }
        }
    }

    private func row(_ item: AppUninstaller.Leftover) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: includeBinding(item))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(prettyPath(item.url))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Text(Self.byteString(item.size))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 24)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: l10n.s.uninstallerSelectedFormat,
                            uninstaller.items.filter(\.include).count, uninstaller.items.count))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(Self.byteString(uninstaller.selectedSize))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(l10n.s.uninstallerCancel) {
                    uninstaller.reset()
                }
                .controlSize(.small)
                .disabled(uninstaller.isRemovingWithHomebrew)
                Spacer()
                Button {
                    if let package = uninstaller.selectedHomebrewPackage {
                        presentHomebrewRemovalConfirmation(for: package)
                    } else {
                        uninstaller.removeSelected()
                    }
                } label: {
                    Label(removeButtonTitle, systemImage: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(!uninstaller.items.contains(where: \.include)
                          || (uninstaller.selectedHomebrewPackage != nil && homebrew.isBusy))
            }
        }
    }

    private var removeButtonTitle: String {
        uninstaller.selectedHomebrewPackage == nil ? l10n.s.uninstallerRemove : l10n.s.homebrewUninstall
    }

    private var homebrewRemovalConfirmationPresented: Binding<Bool> {
        Binding {
            pendingHomebrewRemoval != nil
        } set: { isPresented in
            if !isPresented { dismissHomebrewRemovalConfirmation() }
        }
    }

    private func presentHomebrewRemovalConfirmation(for package: HomebrewPackage) {
        PanelInteractionState.shared.isPresentingPopoverModal = true
        pendingHomebrewRemoval = package
    }

    private func dismissHomebrewRemovalConfirmation() {
        pendingHomebrewRemoval = nil
        PanelInteractionState.shared.isPresentingPopoverModal = false
    }

    @ViewBuilder
    private var homebrewStatus: some View {
        if let package = uninstaller.selectedHomebrewPackage {
            if let status = homebrew.operationStatus,
               status.action == .uninstall,
               status.package?.id == package.id {
                HomebrewOperationStatusView(status: status,
                                            log: homebrew.log,
                                            terminalFallbackCommand: homebrew.terminalFallbackCommand,
                                            compact: true,
                                            showDetails: $showHomebrewDetails,
                                            onCancel: homebrew.cancelOperation,
                                            onClear: homebrew.clearLog,
                                            onOpenTerminal: homebrew.openTerminalFallback)
                if let tap = homebrew.untrustedTap {
                    HomebrewTrustCard(tap: tap, compact: true)
                }
                if let error = homebrew.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label(String(format: l10n.s.uninstallerHomebrewPackageFormat, package.displayName),
                      systemImage: "shippingbox")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
        }
    }

    private func doneState(freed: Int64, failed: [AppUninstaller.Leftover]) -> some View {
        VStack(spacing: 10) {
            Image(systemName: UninstallerSupport.doneSymbol(hasLeftovers: !failed.isEmpty))
                .font(.system(size: 32))
                .foregroundStyle(failed.isEmpty ? .green : .orange)
            Text(l10n.s.uninstallerDoneTitle)
                .font(.system(size: 14, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.byteString(freed)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !failed.isEmpty {
                UninstallFailureNote(items: failed, compact: true)
            }
            Button(l10n.s.uninstallerAnother) {
                uninstaller.reset()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .panelCard()
    }

    private func includeBinding(_ item: AppUninstaller.Leftover) -> Binding<Bool> {
        Binding(
            get: { uninstaller.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { uninstaller.setInclude($0, for: item.id) }
        )
    }

    private func selectFirstApp(from urls: [URL]) -> Bool {
        guard let app = urls.first(where: { $0.pathExtension == "app" }) ?? urls.first else {
            return false
        }
        uninstaller.select(appURL: app)
        return true
    }

    private func choose() {
        showingAppPicker = true
    }

    private func prettyPath(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func label(for category: AppUninstaller.Category) -> String {
        switch category {
        case .app: return l10n.s.uninstallerCatApp
        case .support: return l10n.s.uninstallerCatSupport
        case .caches: return l10n.s.uninstallerCatCaches
        case .preferences: return l10n.s.uninstallerCatPreferences
        case .containers: return l10n.s.uninstallerCatContainers
        case .logs: return l10n.s.uninstallerCatLogs
        case .state: return l10n.s.uninstallerCatState
        case .other: return l10n.s.uninstallerCatOther
        }
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
