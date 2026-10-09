// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The agents' face of Home's player card: the AI page's own live card,
/// showing who is working now. A click opens the AI page.
struct NotchHomeAgentsFace: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        let providers = NotchAgentSupport.providers().filter(usage.snapshot.seen.contains)
        Button { service.select(.agents) } label: {
            if providers.isEmpty {
                NotchAgentCardChrome {
                    Label(text.empty, systemImage: NotchModule.agents.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                NotchAgentLiveCard(snapshot: usage.snapshot, providers: providers, text: text)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.title)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// The calendar's face of Home's levels card: the next events of the week,
/// as the Controls tile names the first. A click opens the Calendar page.
struct NotchHomeCalendarFace: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let strings = FeatureStrings.notchCalendar(l10n.language)
        let now = Date()
        let week = NotchCalendarSupport.readInterval(month: nil, now: now)
        let next = NotchCalendarSupport.upcoming(calendar.events, now: now)
            .filter { !$0.allDay && $0.start < week.end }
        Button { service.select(.calendar) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(strings.title, systemImage: NotchModule.calendar.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if next.isEmpty {
                    Text(strings.empty)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    ForEach(next.prefix(2)) { event in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title.isEmpty ? strings.untitled : event.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(event.start <= now ? strings.ongoing
                                 : NotchCalendarSupport.tileStartText(event.start, now: now,
                                                                      locale: l10n.language.formattingLocale()))
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings.title)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// The files' face of Home's levels card, there only while the shelf holds
/// something: the latest items as the shelf draws them. A click opens Files.
struct NotchHomeFilesFace: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let title = FeatureStrings.notch(l10n.language).files
        let items = shelf.visibleItems
        Button { service.select(.files) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Label(title, systemImage: NotchModule.files.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(items.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(items.prefix(3)) { item in
                        Image(nsImage: item.icon)
                            .resizable()
                            .aspectRatio(contentMode: item.hasContentThumbnail ? .fill : .fit)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .help(item.title)
                    }
                }
                if let latest = items.first {
                    Text(latest.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(items.count)")
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// Home's tile for the last tool opened from the Tools page, drawn as that
/// page draws it. A click runs it from Tools, so a tool that needs the screen
/// closes the island and one that lives in the page opens there.
struct NotchHomeToolTile: View {
    let item: QuickLauncherItem
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared

    var body: some View {
        NotchActionTile(symbol: item.symbol(keepAwake: keepAwake.isActive, muted: micMute.isMuted,
                                            recording: recorder.isRecording),
                        title: item.title(l10n, muted: micMute.isMuted, recording: recorder.isRecording)) {
            service.select(.tools)
            QuickLauncherService.shared.run(item)
        }
        .accessibilityIdentifier("notch.home.tool.\(item.rawValue)")
    }
}
