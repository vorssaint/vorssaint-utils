// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct HomebrewSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @State private var query = ""
    @State private var searchKind: HomebrewPackageKind = .cask
    @State private var installedFilter = HomebrewInstalledFilter.all
    @State private var pendingAction: HomebrewPendingAction?
    @State private var showOperationDetails = false

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            Group {
                if homebrew.brewPath == nil {
                    missingState
                } else {
                    content
                }
            }
        }
        .onAppear {
            if homebrew.installed.isEmpty {
                homebrew.refreshInstalled()
            }
        }
        .onChange(of: query) { _, _ in resetContextSelection() }
        .onChange(of: searchKind) { _, _ in resetContextSelection() }
        .onChange(of: installedFilter) { _, _ in resetContextSelection() }
        .onChange(of: homebrew.operationStatus?.package.id) { _, _ in
            showOperationDetails = false
        }
        .confirmationDialog(confirmationTitle,
                            isPresented: confirmationPresented,
                            titleVisibility: .visible) {
            if let pendingAction {
                Button(actionTitle(for: pendingAction), role: pendingAction.action == .uninstall ? .destructive : nil) {
                    run(pendingAction)
                }
            }
            Button(l10n.s.uninstallerCancel, role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(confirmationBody(for: pendingAction))
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Label(l10n.s.homebrewName, systemImage: "shippingbox")
                    .font(.system(size: 14, weight: .semibold))
                PanelBetaBadge(text: l10n.s.betaBadge)
            }
            Text(l10n.s.betaFeatureWarning)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 12)
            if !homebrew.isShellConfigured {
                Divider()
                shellSetupBanner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider()
            HStack(spacing: 0) {
                packageList
                    .frame(width: 232)
                Divider()
                detailPane
            }
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TextField(l10n.s.homebrewSearchPlaceholder, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Picker("", selection: $searchKind) {
                    Text(l10n.s.homebrewCasks).tag(HomebrewPackageKind.cask)
                    Text(l10n.s.homebrewFormulas).tag(HomebrewPackageKind.formula)
                }
                .labelsHidden()
                .frame(width: 116)
                Button {
                    search()
                } label: {
                    Label(l10n.s.homebrewSearchButton, systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || homebrew.isBusy)
                Button {
                    homebrew.refreshInstalled()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(l10n.s.homebrewRefresh)
                .disabled(homebrew.isBusy)
            }

            Picker("", selection: $installedFilter) {
                Text(l10n.s.homebrewAll).tag(HomebrewInstalledFilter.all)
                Text(l10n.s.homebrewCasks).tag(HomebrewInstalledFilter.cask)
                Text(l10n.s.homebrewFormulas).tag(HomebrewInstalledFilter.formula)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    private var shellSetupBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.s.homebrewShellSetupTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(homebrew.didOpenShellConfig ? l10n.s.homebrewShellSetupOpened : l10n.s.homebrewShellSetupBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                homebrew.openShellConfiguration()
            } label: {
                Label(l10n.s.homebrewShellSetupButton, systemImage: "wrench.and.screwdriver")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            Button {
                homebrew.refreshShellConfigurationStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help(l10n.s.homebrewRefresh)
        }
    }

    private var packageList: some View {
        List {
            if homebrew.isSearching {
                ProgressView(l10n.s.homebrewLoading)
            } else if !homebrew.searchResults.isEmpty {
                Section(l10n.s.homebrewSearchResults) {
                    ForEach(homebrew.searchResults) { package in
                        packageRow(package)
                    }
                }
            } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(l10n.s.homebrewSearchResults) {
                    Text(l10n.s.homebrewSearchEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(l10n.s.homebrewInstalled) {
                if homebrew.isLoadingInstalled {
                    ProgressView(l10n.s.homebrewLoading)
                } else if filteredInstalled.isEmpty {
                    Text(l10n.s.homebrewNoPackages)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredInstalled) { package in
                        packageRow(package)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func packageRow(_ package: HomebrewPackage) -> some View {
        Button {
            homebrew.select(package)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: package.kind == .formula ? "terminal" : "app")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.displayName)
                        .font(.system(size: 12, weight: homebrew.selectedPackage?.id == package.id ? .semibold : .regular))
                        .lineLimit(1)
                    Text(package.versionText ?? package.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let popularity = package.popularity {
                    popularityBadge(popularity)
                }
                if activeStatus(for: package) != nil {
                    ProgressView()
                        .controlSize(.mini)
                } else if package.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if homebrew.isLoadingDetails {
                        ProgressView(l10n.s.homebrewLoading)
                    }
                    if let package = homebrew.selectedPackage {
                        packageDetail(package)
                    } else {
                        emptyDetail
                    }
                    if let error = homebrew.errorMessage, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if homebrew.operationStatus != nil {
                Divider()
                operationLog
                    .padding(12)
            }
        }
    }

    private func packageDetail(_ package: HomebrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(package.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                statusBadge(package)
            }
            Text(package.name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let desc = package.desc, !desc.isEmpty {
                Text(desc)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                detailRow(l10n.s.homebrewVersion, package.versionText ?? "-")
                detailRow(l10n.s.homebrewDescription, packageKindLabel(package.kind))
                if let popularity = package.popularity {
                    detailRow(l10n.s.homebrewPopularity, popularityDescription(popularity))
                }
                if let homepage = package.homepage,
                   let url = URL(string: homepage) {
                    Link(l10n.s.homebrewHomepage, destination: url)
                }
            }
            .font(.caption)

            HStack(spacing: 8) {
                if let status = activeStatus(for: package) {
                    Label(activeActionTitle(for: status), systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                } else if package.isInstalled {
                    Button(role: .destructive) {
                        pendingAction = HomebrewPendingAction(action: .uninstall, package: package)
                    } label: {
                        Label(l10n.s.homebrewUninstall, systemImage: "trash")
                    }
                } else {
                    Button {
                        pendingAction = HomebrewPendingAction(action: .install, package: package)
                    } label: {
                        Label(l10n.s.homebrewInstall, systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .disabled(homebrew.operation != nil)
        }
    }

    @ViewBuilder
    private var operationLog: some View {
        if let status = homebrew.operationStatus {
            HomebrewOperationStatusView(status: status,
                                        log: homebrew.log,
                                        terminalFallbackCommand: homebrew.terminalFallbackCommand,
                                        compact: false,
                                        showDetails: $showOperationDetails,
                                        onCancel: homebrew.cancelOperation,
                                        onClear: homebrew.clearLog,
                                        onOpenTerminal: homebrew.openTerminalFallback)
        }
    }

    private var missingState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(l10n.s.homebrewMissingTitle)
                .font(.system(size: 16, weight: .semibold))
            Text(l10n.s.homebrewMissingBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                homebrew.openHomebrewInstaller()
            } label: {
                Label(l10n.s.homebrewInstallHomebrew, systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
            Text(homebrew.didOpenInstaller ? l10n.s.homebrewInstallHomebrewOpened : l10n.s.homebrewInstallHomebrewCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let error = homebrew.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Button {
                homebrew.refreshInstalled()
            } label: {
                Label(l10n.s.homebrewRefresh, systemImage: "arrow.clockwise")
            }
            Spacer()
        }
        .padding(28)
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.s.homebrewDetailsTitle, systemImage: "shippingbox")
                .font(.system(size: 18, weight: .semibold))
            Text(l10n.s.homebrewNoSelection)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBadge(_ package: HomebrewPackage) -> some View {
        let active = activeStatus(for: package)
        let title = active.map { activeActionTitle(for: $0) }
            ?? (package.isInstalled ? l10n.s.homebrewInstalledBadge : l10n.s.homebrewNotInstalledBadge)
        let color: Color = active != nil ? .accentColor : (package.isInstalled ? .green : .secondary)
        return Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func popularityBadge(_ popularity: HomebrewPopularity) -> some View {
        Text(popularity.compactCount)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .help(popularityDescription(popularity))
    }

    private func popularityDescription(_ popularity: HomebrewPopularity) -> String {
        String(format: l10n.s.homebrewPopularityFormat,
               popularity.decimalCount,
               "\(popularity.days)")
    }

    private var filteredInstalled: [HomebrewPackage] {
        switch installedFilter {
        case .all:
            return homebrew.installed
        case .formula:
            return homebrew.installed.filter { $0.kind == .formula }
        case .cask:
            return homebrew.installed.filter { $0.kind == .cask }
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding {
            pendingAction != nil
        } set: { isPresented in
            if !isPresented { pendingAction = nil }
        }
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "" }
        switch pendingAction.action {
        case .install: return l10n.s.homebrewConfirmInstallTitle
        case .uninstall: return l10n.s.homebrewConfirmUninstallTitle
        }
    }

    private func confirmationBody(for action: HomebrewPendingAction) -> String {
        let format = action.action == .install
            ? l10n.s.homebrewConfirmInstallBodyFormat
            : l10n.s.homebrewConfirmUninstallBodyFormat
        return String(format: format, action.package.displayName)
    }

    private func actionTitle(for action: HomebrewPendingAction) -> String {
        action.action == .install ? l10n.s.homebrewInstall : l10n.s.homebrewUninstall
    }

    private func run(_ action: HomebrewPendingAction) {
        pendingAction = nil
        switch action.action {
        case .install: homebrew.install(action.package)
        case .uninstall: homebrew.uninstall(action.package)
        }
    }

    private func search() {
        resetContextSelection()
        homebrew.search(query: query, kind: searchKind)
    }

    private func resetContextSelection() {
        pendingAction = nil
        showOperationDetails = false
        homebrew.clearSelection()
    }

    private func activeStatus(for package: HomebrewPackage) -> HomebrewOperationStatus? {
        guard let status = homebrew.operationStatus,
              status.isActive,
              status.package.id == package.id else { return nil }
        return status
    }

    private func activeActionTitle(for status: HomebrewOperationStatus) -> String {
        status.action == .install ? l10n.s.homebrewOperationInstalling : l10n.s.homebrewOperationUninstalling
    }

    private func packageKindLabel(_ kind: HomebrewPackageKind) -> String {
        kind == .formula ? l10n.s.homebrewFormulas : l10n.s.homebrewCasks
    }
}

private enum HomebrewInstalledFilter: String, CaseIterable, Identifiable {
    case all
    case cask
    case formula

    var id: String { rawValue }
}
