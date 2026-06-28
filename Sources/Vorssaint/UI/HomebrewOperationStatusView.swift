// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct HomebrewOperationStatusView: View {
    @ObservedObject private var l10n = L10n.shared

    let status: HomebrewOperationStatus
    let log: String
    let terminalFallbackCommand: String?
    let compact: Bool
    @Binding var showDetails: Bool
    var onCancel: () -> Void
    var onClear: () -> Void
    var onOpenTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            header
            progressArea
            if let activity = status.lastActivity, !activity.isEmpty {
                Text(activity)
                    .font(.system(size: compact ? 9.5 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status.result == .needsTerminal {
                terminalFallback
            }
            if !log.isEmpty {
                detailsToggle
            }
            if showDetails && !log.isEmpty {
                technicalLog
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.14))
                Image(systemName: iconName)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if status.isActive {
                        Text(phaseText)
                        Text("|")
                    }
                    TimelineView(.periodic(from: status.startedAt, by: 1)) { context in
                        Text(String(format: l10n.s.homebrewOperationElapsedFormat,
                                    elapsedText(now: context.date)))
                    }
                }
                .font(.system(size: compact ? 9.5 : 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if status.isActive {
                Button(l10n.s.homebrewCancelOperation) {
                    onCancel()
                }
                .controlSize(.mini)
            } else {
                Button(l10n.s.homebrewClearLog) {
                    onClear()
                }
                .controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        if status.isActive {
            if let fraction = status.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                HomebrewIndeterminateProgressBar()
                Text(l10n.s.homebrewOperationProgressUnknown)
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        } else if status.result == .succeeded {
            ProgressView(value: 1)
                .progressViewStyle(.linear)
        }
    }

    private var terminalFallback: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(l10n.s.homebrewTerminalFallback, systemImage: "terminal")
                .font(.system(size: compact ? 9.5 : 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if terminalFallbackCommand != nil {
                HStack(spacing: 8) {
                    Button(l10n.s.homebrewOpenTerminal) {
                        onOpenTerminal()
                    }
                    Button {
                        copy(terminalFallbackCommand)
                    } label: {
                        Label(l10n.s.menuCopy, systemImage: "doc.on.doc")
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var detailsToggle: some View {
        Button {
            showDetails.toggle()
        } label: {
            Label(showDetails ? l10n.s.homebrewOperationHideDetails : l10n.s.homebrewOperationShowDetails,
                  systemImage: showDetails ? "chevron.up" : "chevron.down")
                .font(.system(size: compact ? 10 : 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(log.isEmpty)
    }

    private var technicalLog: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(l10n.s.homebrewOperationTechnicalLog)
                    .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button {
                    copy(log)
                } label: {
                    Label(l10n.s.menuCopy, systemImage: "doc.on.doc")
                }
                .controlSize(.mini)
                .disabled(log.isEmpty)
            }
            ScrollView {
                Text(log.isEmpty ? " " : log)
                    .font(.system(size: compact ? 9 : 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: compact ? 58 : 96)
        }
    }

    private var title: String {
        switch status.result {
        case .running:
            if status.action == .updateHomebrew {
                return l10n.s.homebrewOperationUpdateHomebrew
            }
            if status.action == .upgradeAll {
                return l10n.s.homebrewOperationUpgradeAll
            }
            return String(format: runningTitleFormat, packageDisplayName)
        case .succeeded:
            if status.action == .updateHomebrew {
                return l10n.s.homebrewOperationUpdatedHomebrew
            }
            if status.action == .upgradeAll {
                return l10n.s.homebrewOperationUpgradedAll
            }
            return String(format: succeededTitleFormat, packageDisplayName)
        case .failed:
            return String(format: l10n.s.homebrewOperationFailedFormat, packageDisplayName)
        case .cancelled:
            return l10n.s.homebrewOperationCancelled
        case .needsTerminal:
            return l10n.s.homebrewOperationTerminal
        }
    }

    private var phaseText: String {
        switch status.result {
        case .cancelled:
            return l10n.s.homebrewOperationCancelled
        case .failed:
            return String(format: l10n.s.homebrewOperationFailedFormat, packageDisplayName)
        case .needsTerminal:
            return l10n.s.homebrewOperationTerminal
        case .running, .succeeded:
            switch status.phase {
            case .preparing: return l10n.s.homebrewOperationPreparing
            case .downloading: return l10n.s.homebrewOperationDownloading
            case .installing: return l10n.s.homebrewOperationInstalling
            case .uninstalling: return l10n.s.homebrewOperationUninstalling
            case .upgrading: return l10n.s.homebrewOperationUpgrading
            case .finalizing: return l10n.s.homebrewOperationFinalizing
            case .refreshing: return l10n.s.homebrewOperationRefreshing
            }
        }
    }

    private var runningTitleFormat: String {
        switch status.action {
        case .install: return l10n.s.homebrewOperationInstallFormat
        case .uninstall: return l10n.s.homebrewOperationUninstallFormat
        case .upgrade: return l10n.s.homebrewOperationUpgradeFormat
        case .upgradeAll: return l10n.s.homebrewOperationUpgradeAll
        case .updateHomebrew: return l10n.s.homebrewOperationUpdateHomebrew
        }
    }

    private var succeededTitleFormat: String {
        switch status.action {
        case .install: return l10n.s.homebrewOperationInstalledFormat
        case .uninstall: return l10n.s.homebrewOperationUninstalledFormat
        case .upgrade: return l10n.s.homebrewOperationUpgradedFormat
        case .upgradeAll: return l10n.s.homebrewOperationUpgradedAll
        case .updateHomebrew: return l10n.s.homebrewOperationUpdatedHomebrew
        }
    }

    private var packageDisplayName: String {
        status.package?.displayName ?? l10n.s.homebrewAllPackages
    }

    private var iconName: String {
        switch status.result {
        case .running: return status.action.runningSystemImage
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .needsTerminal: return "terminal.fill"
        }
    }

    private var iconColor: Color {
        switch status.result {
        case .running: return .accentColor
        case .succeeded: return .green
        case .failed, .needsTerminal: return .orange
        case .cancelled: return .secondary
        }
    }

    private func elapsedText(now: Date) -> String {
        let end = status.finishedAt ?? now
        let seconds = max(Int(end.timeIntervalSince(status.startedAt)), 0)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)min"
        }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)min"
    }

    private func copy(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct HomebrewIndeterminateProgressBar: View {
    @State private var offset: CGFloat = -0.35

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(width: max(geometry.size.width * 0.34, 36))
                    .offset(x: offset * geometry.size.width)
            }
            .clipped()
        }
        .frame(height: 5)
        .onAppear {
            offset = -0.35
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                offset = 1.05
            }
        }
    }
}
