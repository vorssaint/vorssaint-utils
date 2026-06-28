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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            if homebrew.installed.isEmpty {
                homebrew.refreshInstalled()
            }
        }
        .onChange(of: query) { _, _ in resetContextSelection() }
        .onChange(of: searchKind) { _, _ in resetContextSelection() }
        .onChange(of: installedFilter) { _, _ in clearSelectionIfHidden() }
        .onChange(of: homebrew.operationStatus?.targetID) { _, _ in
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
            Label(l10n.s.homebrewName, systemImage: "shippingbox")
                .font(.system(size: 14, weight: .semibold))
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
                    .frame(maxHeight: .infinity)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                Button {
                    pendingAction = HomebrewPendingAction(action: .updateHomebrew)
                } label: {
                    Label(l10n.s.homebrewUpdateHomebrew, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(homebrew.isBusy)
            }

            HStack(spacing: 8) {
                Picker("", selection: $installedFilter) {
                    Text("\(l10n.s.homebrewAll) \(homebrew.installed.count)").tag(HomebrewInstalledFilter.all)
                    Text("\(l10n.s.homebrewCasks) \(installedCaskCount)").tag(HomebrewInstalledFilter.cask)
                    Text("\(l10n.s.homebrewFormulas) \(installedFormulaCount)").tag(HomebrewInstalledFilter.formula)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                outdatedSummary
            }
        }
    }

    @ViewBuilder
    private var outdatedSummary: some View {
        if homebrew.isLoadingOutdated {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(l10n.s.homebrewUpdates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if homebrew.outdatedCount > 0 {
            HStack(spacing: 8) {
                Label("\(l10n.s.homebrewUpdates) \(homebrew.outdatedCount)", systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button {
                    pendingAction = HomebrewPendingAction(action: .upgradeAll)
                } label: {
                    Label(l10n.s.homebrewUpgradeAll, systemImage: "arrow.up.circle")
                }
                .controlSize(.small)
                .disabled(homebrew.isBusy)
            }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                searchResultsSection
                installedPackagesSection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if homebrew.isSearching {
            packageSection(l10n.s.homebrewSearchResults) {
                loadingRow(l10n.s.homebrewLoading)
            }
        } else if !homebrew.searchResults.isEmpty {
            packageSection(l10n.s.homebrewSearchResults, count: homebrew.searchResults.count) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(homebrew.searchResults) { package in
                        packageRow(package)
                    }
                }
            }
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            packageSection(l10n.s.homebrewSearchResults, count: 0) {
                packageMessage(l10n.s.homebrewSearchEmpty)
            }
        }
    }

    private var installedPackagesSection: some View {
        packageSection(l10n.s.homebrewInstalled, count: filteredInstalled.count) {
            if homebrew.isLoadingInstalled {
                loadingRow(l10n.s.homebrewLoading)
            } else if filteredInstalled.isEmpty {
                packageMessage(l10n.s.homebrewNoPackages)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredInstalled) { package in
                        packageRow(package)
                    }
                }
            }
        }
    }

    private func packageSection<Content: View>(_ title: String,
                                               count: Int? = nil,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let count {
                    countBadge(count)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func packageMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func packageRow(_ package: HomebrewPackage) -> some View {
        HStack(spacing: 8) {
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
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            if activeStatus(for: package) != nil {
                ProgressView()
                    .controlSize(.mini)
            } else if let update = package.update {
                updateButton(package, update: update)
            } else if package.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(homebrew.selectedPackage?.id == package.id ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            packageContextMenu(package)
        }
    }

    private func updateButton(_ package: HomebrewPackage, update: HomebrewPackageUpdate) -> some View {
        Button {
            pendingAction = HomebrewPendingAction(action: .upgrade, package: package)
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(homebrew.isBusy)
        .help("\(l10n.s.homebrewUpgrade): \(update.versionSummary)")
        .accessibilityLabel(l10n.s.homebrewUpgrade)
    }

    @ViewBuilder
    private func packageContextMenu(_ package: HomebrewPackage) -> some View {
        let isBusy = homebrew.isBusy || activeStatus(for: package) != nil
        Button {
            homebrew.select(package)
        } label: {
            Label(l10n.s.homebrewDetailsTitle, systemImage: "info.circle")
        }
        if package.update != nil {
            Button {
                pendingAction = HomebrewPendingAction(action: .upgrade, package: package)
            } label: {
                Label(l10n.s.homebrewUpgrade, systemImage: "arrow.up.circle")
            }
            .disabled(isBusy)
        }
        if package.isInstalled {
            Button(role: .destructive) {
                pendingAction = HomebrewPendingAction(action: .uninstall, package: package)
            } label: {
                Label(l10n.s.homebrewUninstall, systemImage: "trash")
            }
            .disabled(isBusy)
        } else {
            Button {
                pendingAction = HomebrewPendingAction(action: .install, package: package)
            } label: {
                Label(l10n.s.homebrewInstall, systemImage: "arrow.down.circle")
            }
            .disabled(isBusy)
        }
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
                detailRow(l10n.s.homebrewVersion,
                          package.update?.installedText.isEmpty == false
                            ? package.update?.installedText ?? "-"
                            : package.versionText ?? "-")
                if let update = package.update {
                    detailRow(l10n.s.homebrewLatestVersion, update.currentVersion)
                }
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
                    if package.update != nil {
                        Button {
                            pendingAction = HomebrewPendingAction(action: .upgrade, package: package)
                        } label: {
                            Label(l10n.s.homebrewUpgrade, systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
            .disabled(homebrew.isBusy)
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
            ?? (package.update != nil
                ? l10n.s.homebrewUpdateAvailableBadge
                : (package.isInstalled ? l10n.s.homebrewInstalledBadge : l10n.s.homebrewNotInstalledBadge))
        let color: Color = active != nil ? .accentColor : (package.update != nil ? .orange : (package.isInstalled ? .green : .secondary))
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

    private func updateHelp(_ update: HomebrewPackageUpdate) -> String {
        "\(l10n.s.homebrewUpdateAvailableBadge): \(update.versionSummary)"
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

    private var installedCaskCount: Int {
        homebrew.installed.filter { $0.kind == .cask }.count
    }

    private var installedFormulaCount: Int {
        homebrew.installed.filter { $0.kind == .formula }.count
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
        case .upgrade: return l10n.s.homebrewConfirmUpgradeTitle
        case .upgradeAll: return l10n.s.homebrewConfirmUpgradeAllTitle
        case .updateHomebrew: return l10n.s.homebrewConfirmUpdateHomebrewTitle
        }
    }

    private func confirmationBody(for action: HomebrewPendingAction) -> String {
        if action.action == .updateHomebrew {
            return l10n.s.homebrewConfirmUpdateHomebrewBody
        }
        if action.action == .upgradeAll {
            return l10n.s.homebrewConfirmUpgradeAllBody
        }
        guard let package = action.package else { return "" }
        let format: String
        switch action.action {
        case .install:
            format = l10n.s.homebrewConfirmInstallBodyFormat
        case .uninstall:
            format = l10n.s.homebrewConfirmUninstallBodyFormat
        case .upgrade:
            format = l10n.s.homebrewConfirmUpgradeBodyFormat
        case .upgradeAll:
            return l10n.s.homebrewConfirmUpgradeAllBody
        case .updateHomebrew:
            return l10n.s.homebrewConfirmUpdateHomebrewBody
        }
        return String(format: format, package.displayName)
    }

    private func actionTitle(for action: HomebrewPendingAction) -> String {
        switch action.action {
        case .install: return l10n.s.homebrewInstall
        case .uninstall: return l10n.s.homebrewUninstall
        case .upgrade: return l10n.s.homebrewUpgrade
        case .upgradeAll: return l10n.s.homebrewUpgradeAll
        case .updateHomebrew: return l10n.s.homebrewUpdateHomebrew
        }
    }

    private func run(_ action: HomebrewPendingAction) {
        pendingAction = nil
        switch action.action {
        case .install:
            if let package = action.package { homebrew.install(package) }
        case .uninstall:
            if let package = action.package { homebrew.uninstall(package) }
        case .upgrade:
            if let package = action.package { homebrew.upgrade(package) }
        case .upgradeAll:
            homebrew.upgradeAll()
        case .updateHomebrew:
            homebrew.updateHomebrew()
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

    private func clearSelectionIfHidden() {
        pendingAction = nil
        showOperationDetails = false
        guard let selected = homebrew.selectedPackage else { return }
        let isVisible = (homebrew.searchResults + filteredInstalled).contains { $0.id == selected.id }
        if !isVisible {
            homebrew.clearSelection()
        }
    }

    private func activeStatus(for package: HomebrewPackage) -> HomebrewOperationStatus? {
        guard let status = homebrew.operationStatus,
              status.isActive,
              status.package?.id == package.id else { return nil }
        return status
    }

    private func activeActionTitle(for status: HomebrewOperationStatus) -> String {
        switch status.action {
        case .install: return l10n.s.homebrewOperationInstalling
        case .uninstall: return l10n.s.homebrewOperationUninstalling
        case .upgrade: return l10n.s.homebrewOperationUpgrading
        case .upgradeAll: return l10n.s.homebrewOperationUpgrading
        case .updateHomebrew: return l10n.s.homebrewOperationRefreshing
        }
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
