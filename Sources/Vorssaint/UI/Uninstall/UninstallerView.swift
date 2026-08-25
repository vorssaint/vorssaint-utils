// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The uninstaller, embedded as a Settings page: drop an app (or pick one),
/// review the leftover files it found with their sizes, then move the selected
/// ones to the Trash and see the space recovered.
struct UninstallerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var uninstaller = AppUninstaller.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var dropTargeted = false
    @State private var showingAppPicker = false
    @State private var pendingHomebrewRemoval: HomebrewPackage?
    @State private var showHomebrewDetails = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert(l10n.s.homebrewConfirmUninstallTitle,
                   isPresented: Binding(get: { pendingHomebrewRemoval != nil },
                                        set: { if !$0 { pendingHomebrewRemoval = nil } }),
                   presenting: pendingHomebrewRemoval) { package in
                Button(l10n.s.uninstallerCancel, role: .cancel) {}
                Button(l10n.s.homebrewUninstall, role: .destructive) {
                    pendingHomebrewRemoval = nil
                    uninstaller.removeSelectedWithHomebrew()
                }
            } message: { package in
                Text(String(format: l10n.s.homebrewConfirmUninstallBodyFormat, package.displayName))
            }
    }

    @ViewBuilder
    private var content: some View {
        switch uninstaller.phase {
        case .empty: emptyState
        case .scanning: busyState(l10n.s.uninstallerScanning)
        case .results: resultsState
        case .removing: busyState(l10n.s.uninstallerRemoving)
        case let .done(freed, failed): doneState(freed: freed, failed: failed)
        }
    }

    // MARK: Empty / drop

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(dropTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                )
                .frame(width: 360, height: 200)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "trash.square")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                        Text(l10n.s.uninstallerDropTitle)
                            .font(.system(size: 16, weight: .semibold))
                        Text(l10n.s.uninstallerDropSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                )
                .animation(.easeOut(duration: 0.15), value: dropTargeted)

            Button(l10n.s.uninstallerChoose) { choose() }
                .controlSize(.large)

            Text(l10n.s.uninstallerEmptyNote)
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !permissions.fullDiskAccess {
                FullDiskAccessNote().frame(width: 360)
            }
            Spacer()
        }
        .padding(28)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView {
                showingAppPicker = false
            } onSelect: { url in
                showingAppPicker = false
                uninstaller.select(appURL: url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let app = urls.first(where: { $0.pathExtension == "app" }) ?? urls.first else { return false }
            uninstaller.select(appURL: app)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: Busy

    private func busyState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(message).foregroundStyle(.secondary)
            if let target = uninstaller.target {
                HStack(spacing: 8) {
                    Image(nsImage: target.icon).resizable().frame(width: 18, height: 18)
                    Text(target.name).font(.callout)
                }
            }
            Spacer()
        }
    }

    // MARK: Results

    private var resultsState: some View {
        VStack(spacing: 0) {
            targetHeader
            Divider()
            List {
                ForEach(AppUninstaller.Category.allCases, id: \.self) { category in
                    let group = uninstaller.items.filter { $0.category == category }
                    if !group.isEmpty {
                        Section(label(for: category)) {
                            ForEach(group) { item in row(item) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            homebrewStatus
            footer
        }
    }

    private var targetHeader: some View {
        HStack(spacing: 12) {
            if let target = uninstaller.target {
                Image(nsImage: target.icon).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name).font(.system(size: 16, weight: .semibold))
                    Text(target.bundleID ?? target.url.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.byteString(uninstaller.totalSize))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(l10n.s.uninstallerFoundTitle).font(.caption2).foregroundStyle(.secondary)
            }
            Button { uninstaller.reset() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(uninstaller.isRemovingWithHomebrew)
        }
        .padding(16)
    }

    private func row(_ item: AppUninstaller.Leftover) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: includeBinding(item)).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text(prettyPath(item.url))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(Self.byteString(item.size))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: l10n.s.uninstallerSelectedFormat,
                            uninstaller.items.filter(\.include).count, uninstaller.items.count))
                    .font(.system(size: 12, weight: .medium))
                Text(Self.byteString(uninstaller.selectedSize))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.s.uninstallerCancel) { uninstaller.reset() }
                .disabled(uninstaller.isRemovingWithHomebrew)
            Button(removeButtonTitle) {
                if let package = uninstaller.selectedHomebrewPackage {
                    pendingHomebrewRemoval = package
                } else {
                    uninstaller.removeSelected()
                }
            }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!uninstaller.items.contains(where: \.include)
                          || (uninstaller.selectedHomebrewPackage != nil && homebrew.isBusy))
        }
        .padding(16)
    }

    private var removeButtonTitle: String {
        uninstaller.selectedHomebrewPackage == nil ? l10n.s.uninstallerRemove : l10n.s.homebrewUninstall
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
                                            compact: false,
                                            showDetails: $showHomebrewDetails,
                                            onCancel: homebrew.cancelOperation,
                                            onClear: homebrew.clearLog,
                                            onOpenTerminal: homebrew.openTerminalFallback)
                    .padding(12)
                if let tap = homebrew.untrustedTap {
                    HomebrewTrustCard(tap: tap)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
                if let error = homebrew.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            } else {
                Label(String(format: l10n.s.uninstallerHomebrewPackageFormat, package.displayName),
                      systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider()
        }
    }

    // MARK: Done

    private func doneState(freed: Int64, failed: [AppUninstaller.Leftover]) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: UninstallerSupport.doneSymbol(hasLeftovers: !failed.isEmpty))
                .font(.system(size: 54))
                .foregroundStyle(failed.isEmpty ? .green : .orange)
            Text(l10n.s.uninstallerDoneTitle).font(.system(size: 20, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.byteString(freed)))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if !failed.isEmpty {
                UninstallFailureNote(items: failed).frame(width: 360)
            }
            Button(l10n.s.uninstallerAnother) { uninstaller.reset() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            Spacer()
        }
        .padding(28)
    }

    // MARK: Helpers

    private func includeBinding(_ item: AppUninstaller.Leftover) -> Binding<Bool> {
        Binding(
            get: { uninstaller.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { uninstaller.setInclude($0, for: item.id) }
        )
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
