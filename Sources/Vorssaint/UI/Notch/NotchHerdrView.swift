// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The herdr page: live supervised-agent status with the same row shape as
/// the panel, peer to `NotchAgentsView` but provider-neutral. herdr is not
/// an `AgentProvider` (no tokens, no cost, no limits): this view reads
/// `HerdrStatusService.shared` directly and never touches usage history.
struct NotchHerdrView: View {
    let size: CGSize
    @ObservedObject private var service = HerdrStatusService.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: HerdrFeatureStrings { FeatureStrings.herdr(l10n.language) }

    var body: some View {
        Group {
            if !service.isInstalled {
                NotchEmptyView(symbol: "terminal", message: strings.installHint)
            } else if service.lastError == .serverStopped, service.snapshot == nil {
                NotchEmptyView(symbol: "terminal", message: strings.startHint)
            } else if service.lastError == .unsupportedVersion {
                NotchEmptyView(symbol: "terminal", message: strings.updateRequired)
            } else if let snapshot = service.snapshot, !snapshot.agents.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        if service.isStale {
                            Text(strings.stale).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        ForEach(snapshot.agents) { agent in
                            herdrRow(agent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.automatic)
            } else if service.isRefreshing {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(strings.loading).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotchEmptyView(symbol: "terminal", message: strings.empty)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { service.refresh() }
        .onDisappear { service.surfaceDidChange(visibleSurfaces: 0) }
    }

    private func herdrRow(_ agent: HerdrAgent) -> some View {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.displayName ?? agent.paneID), \(strings.statusLabel(agent.status))")
    }
}

/// The island badge for a blocked agent: count text beside the herdr mark.
/// A herdr-local view on purpose — `NotchCapsuleAgentMarks` is typed on
/// `AgentProvider`, which herdr must never join.
struct NotchHerdrBadgeMarks: View {
    let blockedCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(String(blockedCount))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.orange)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(blockedCount)")
    }
}

/// When the closed island carries the herdr needs-attention count: the
/// feature is available, the binary is installed, the server answered, and
/// at least one supervised agent is blocked. Every clause blocks a false
/// positive: no badge for a missing binary, a stopped server, or an empty
/// room.
enum NotchHerdrBadge {
    static func shouldShow(isAvailable: Bool, isInstalled: Bool,
                           snapshot: HerdrStatusSnapshot?) -> Bool {
        guard isAvailable, isInstalled, let snapshot else { return false }
        return HerdrStatusSupport.showsBadge(snapshot)
    }

    static var shouldShow: Bool {
        shouldShow(isAvailable: AppFeature.herdrStatus.isAvailable,
                   isInstalled: HerdrStatusService.shared.isInstalled,
                   snapshot: HerdrStatusService.shared.snapshot)
    }

    static var blockedCount: Int {
        HerdrStatusService.shared.snapshot?.agents.filter { $0.status == .blocked }.count ?? 0
    }
}
