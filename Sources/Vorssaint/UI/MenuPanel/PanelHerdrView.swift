// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The herdr status section: one row per supervised agent with its status,
/// peer to `PanelPortManagerView`. Status only, no actions. Polls while the
/// popover is open and releases on disappear; a stopped server shows its own
/// start hint, a missing binary a single disabled install line.
struct PanelHerdrView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = HerdrStatusService.shared

    var onClose: () -> Void

    private var strings: HerdrFeatureStrings { FeatureStrings.herdr(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.refresh()
        }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
            service.surfaceDidChange(visibleSurfaces: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text(strings.title).font(.headline)
            Spacer()
            Button {
                service.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(service.isRefreshing)
            .help(strings.refresh)
            Button {
                PanelInteractionState.shared.viewKeepsPopoverOpen = false
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !service.isInstalled {
            VStack(alignment: .leading, spacing: 4) {
                Text(strings.notInstalled).font(.system(size: 12, weight: .semibold))
                Text(strings.installHint).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else if service.lastError == .serverStopped, service.snapshot == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(strings.noServer).font(.system(size: 12, weight: .semibold))
                Text(strings.startHint).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else if service.lastError == .unsupportedVersion {
            Text(strings.updateRequired).font(.system(size: 11)).foregroundStyle(.secondary)
        } else if let snapshot = service.snapshot, !snapshot.agents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if service.isStale {
                    Text(strings.stale).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(snapshot.agents) { agent in
                    agentRow(agent)
                }
                if let fetchedAt = Optional(snapshot.fetchedAt) {
                    Text(String(format: strings.lastUpdatedFormat,
                                HerdrPanelTime.label(fetchedAt)))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        } else if service.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(strings.loading).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            Text(strings.empty).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func agentRow(_ agent: HerdrAgent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: HerdrPanelTime.symbol(agent.status))
                .foregroundStyle(HerdrPanelTime.color(agent.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.displayName ?? agent.title ?? agent.paneID)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let detail = agent.title, detail != agent.displayName {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                } else if let cwd = agent.cwd {
                    Text(cwd).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(strings.statusLabel(agent.status))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HerdrPanelTime.color(agent.status))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.displayName ?? agent.paneID), \(strings.statusLabel(agent.status))")
    }
}

/// Presentation helpers with no service coupling: glyph, tint and a short
/// updated-at label. Kept beside the view so tests never import SwiftUI.
enum HerdrPanelTime {
    static func symbol(_ status: HerdrAgent.Status) -> String {
        switch status {
        case .idle: return "moon.zzz"
        case .working: return "ellipsis.curlybraces"
        case .blocked: return "exclamationmark.triangle"
        case .done: return "checkmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    static func label(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func color(_ status: HerdrAgent.Status) -> Color {
        switch status {
        case .idle: return .secondary
        case .working: return .blue
        case .blocked: return .orange
        case .done: return .green
        case .unknown: return .secondary
        }
    }
}
