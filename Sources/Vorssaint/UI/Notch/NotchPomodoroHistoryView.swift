// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchPomodoroHistoryView: View {
    private enum Scope: Equatable { case all, day(Date), month(Date) }

    let snapshot: NotchPomodoroHistory.Snapshot?
    let now: Date
    let language: AppLanguage
    let onExport: () -> Void
    let onClose: () -> Void
    @State private var scope: Scope = .all
    @State private var archiveNavigation = UUID()

    private var text: NotchPomodoroHistoryStrings { FeatureStrings.notchPomodoroHistory(language) }
    private var activities: NotchActivityStrings { FeatureStrings.notchActivities(language) }
    private var locale: Locale { Locale(identifier: language.rawValue) }
    private var monthStyle: Date.FormatStyle { .dateTime.month(.wide).year().locale(locale) }

    var body: some View {
        history
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .notchBand {
                archiveTitle
            } trailing: {
                HStack(spacing: 2) {
                    NotchIconButton(symbol: "square.and.arrow.up", title: text.export, action: onExport)
                        .disabled(snapshot?.days.isEmpty != false)
                    NotchIconButton(symbol: "xmark", title: Strings.localized(language).supportIntroDoneButton, action: onClose)
                }
            }
            .onChange(of: snapshot?.calendar.timeZone) { _, _ in
                if scope != .all { openArchive(.all) }
            }
    }

    @ViewBuilder private var archiveTitle: some View {
        if let snapshot, !snapshot.months.isEmpty {
            NotchMenuButton(title: text.archive, items: archiveItems(snapshot)) {
                NotchBandMenuLabel(title: text.title)
            }
            .help(text.archive)
        } else {
            Text(text.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func archiveItems(_ snapshot: NotchPomodoroHistory.Snapshot) -> [NotchMenuItem] {
        let months = snapshot.months.map { month in
            NotchMenuItem(title: month.formatted(monthStyle), checked: scope == .month(month)) {
                openArchive(.month(month))
            }
        }
        return [NotchMenuItem(title: text.backToTop) { openArchive(.all) }, .separator] + months
    }

    private func openArchive(_ destination: Scope) {
        scope = destination
        archiveNavigation = UUID()
    }

    @ViewBuilder private var history: some View {
        if let snapshot {
            if snapshot.days.isEmpty {
                NotchEmptyView(symbol: snapshot.storageUnavailable ? "exclamationmark.triangle" : "clock.arrow.circlepath",
                               message: snapshot.storageUnavailable ? text.unavailable : text.empty)
            } else {
                historyList(snapshot)
            }
        } else {
            ProgressView(text.title)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func historyList(_ snapshot: NotchPomodoroHistory.Snapshot) -> some View {
        ScrollView { historyRows(snapshot) }
            .scrollIndicators(.automatic)
            .notchScrollEdgeFade(length: 8)
            .accessibilityIdentifier("notch.pomodoro.history.scroll")
            .id(archiveNavigation)
    }

    private func historyRows(_ snapshot: NotchPomodoroHistory.Snapshot) -> some View {
        let today = snapshot.calendar.startOfDay(for: now)
        let dateStyle = Date.FormatStyle.dateTime.year().month(.abbreviated).day().locale(locale)
        let selection: NotchPomodoroHistory.Day?
        let month: Date?
        switch scope {
        case .all:
            selection = nil
            month = nil
        case .day(let date):
            selection = snapshot.day(containing: date)
            month = nil
        case .month(let date):
            selection = nil
            month = date
        }
        let shownDays = month.map { snapshot.days(inMonth: $0) }
            ?? selection.map { ArraySlice([$0]) } ?? snapshot.days[...]
        return LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
            if let month {
                summary(title: month.formatted(monthStyle),
                        focus: shownDays.reduce(0) { $0 + $1.focusSeconds },
                        breaks: shownDays.reduce(0) { $0 + $1.breakSeconds })
            } else {
                let week = snapshot.recentDays(through: now)
                let day = selection ?? week.last
                summary(title: selection.map { dayLabel($0.date) } ?? text.today,
                        focus: day?.focusSeconds ?? 0, breaks: day?.breakSeconds ?? 0)
                    .padding(.bottom, 2)
                weekOverview(week, selected: selection?.date)
                    .padding(.bottom, 4)
            }
            if snapshot.storageUnavailable {
                Label(text.unavailable, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let selection, selection.entries.isEmpty {
                Text(text.emptyDay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(shownDays) { day in
                Section {
                    ForEach(day.entries, content: row)
                } header: {
                    if selection == nil, month != nil || day.date != today {
                        Text(verbatim: day.date.formatted(dateStyle))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .background(.black)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .padding(.trailing, 4)
    }

    private func weekOverview(_ week: [NotchPomodoroHistory.Day], selected: Date?) -> some View {
        let largest = max(1, week.map { $0.focusSeconds + $0.breakSeconds }.max() ?? 0)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(text.week)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if selected != nil {
                    Button { scope = .all } label: {
                        Text(text.allDays)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false))
                    .accessibilityIdentifier("notch.pomodoro.allDays")
                }
            }
            .lineLimit(1)
            HStack(spacing: 5) {
                ForEach(week) { day in
                    weekDay(day, scale: 26 / CGFloat(largest), selected: selected == day.date)
                }
            }
        }
        .padding(8)
        .modifier(NotchControlSurface(cornerRadius: 9, interactive: false))
    }

    private func weekDay(_ day: NotchPomodoroHistory.Day, scale: CGFloat, selected: Bool) -> some View {
        let date = dayLabel(day.date)
        let values = "\(activities.focus) \(duration(day.focusSeconds)), \(text.breaks) \(duration(day.breakSeconds))"
        return Button {
            scope = selected ? .all : .day(day.date)
        } label: {
            VStack(spacing: 3) {
                Group {
                    if day.entries.isEmpty {
                        Capsule().fill(.white.opacity(0.1)).frame(height: 2)
                    } else {
                        VStack(spacing: 0) {
                            Rectangle().fill(.white.opacity(0.35)).frame(height: CGFloat(day.breakSeconds) * scale)
                            Rectangle().fill(.orange).frame(height: CGFloat(day.focusSeconds) * scale)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                .frame(maxWidth: 18)
                .frame(height: 26, alignment: .bottom)
                Text(verbatim: day.date.formatted(.dateTime.weekday(.short).locale(locale)))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(selected ? .primary : .tertiary)
                    .lineLimit(1)
                    .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .background(.white.opacity(selected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false))
        .help(date + " · " + values)
        .accessibilityLabel(date)
        .accessibilityValue(values)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(locale))
    }

    private func summary(title: String, focus: Int, breaks: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                total(activities.focus, seconds: focus, color: .orange)
                total(text.breaks, seconds: breaks, color: .white.opacity(0.85))
            }
        }
    }

    private func total(_ label: String, seconds: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 2)
            Text(duration(seconds))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .modifier(NotchControlSurface(cornerRadius: 9, interactive: false))
        .accessibilityElement(children: .combine)
    }

    private func row(_ entry: NotchPomodoroHistory.Entry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.phase == .focus ? "timer" : "cup.and.saucer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.phase == .focus ? .orange : .white.opacity(0.55))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(activities.phase(entry.phase))
                .foregroundStyle(.white.opacity(0.9))
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(verbatim: entry.completedAt.formatted(.dateTime.hour().minute().locale(locale)))
                .foregroundStyle(.white.opacity(0.55))
            Text(duration(entry.durationSeconds))
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 48, alignment: .trailing)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .modifier(NotchControlSurface(cornerRadius: 9, interactive: false))
        .accessibilityElement(children: .combine)
    }

    private func duration(_ seconds: Int) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: units, width: .abbreviated).locale(locale))
    }
}
