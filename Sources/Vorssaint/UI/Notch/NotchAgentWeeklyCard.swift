// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One full-width card per default CLI source. Real samples are dots: gaps,
/// offline periods and allowance refills never become invented history lines.
struct NotchAgentWeeklyCard: View {
    let provider: AgentProvider
    let cycle: AgentWeeklyUsage.Cycle?
    let now: Date
    let historyFailed: Bool
    let strings: AgentWeeklyStrings
    let text: NotchAgentStrings
    var status: String? = nil
    /// False while a chosen Claude profile, not the CLI's default login, is read.
    var namesDefaultAccount = true
    @Environment(\.locale) private var locale

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 7) {
                NotchAgentCardHeader(title: provider.displayName + " · " + strings.title,
                                     symbol: NotchAgentCard.weekly.symbol, tint: provider.tint, provider: provider) { EmptyView() }
                if namesDefaultAccount {
                    Text(strings.defaultAccount).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if let cycle, let sample = cycle.latest {
                    reading(sample, cycle: cycle)
                } else {
                    Text(strings.noData).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if historyFailed {
                    Text(strings.failure).foregroundStyle(.orange).font(.system(size: 9))
                }
                if let status { Text(status).font(.system(size: 9)).foregroundStyle(.orange) }
                Spacer(minLength: 0)
                Text(strings.collection).font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reading(_ sample: AgentWeeklyUsage.Sample, cycle: AgentWeeklyUsage.Cycle) -> some View {
        let plan = AgentWeeklyPlan(sample: sample, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(percent(sample.usedPercent) + " " + text.used).foregroundStyle(provider.tint)
                Text(percent(100 - sample.usedPercent) + " " + text.remaining).foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text(text.updated(date(sample.observedAt)) + " · " + source(sample))
                .font(.system(size: 9)).foregroundStyle(.secondary)
            if let reset = sample.resetsAt {
                Label(date(reset), systemImage: "arrow.clockwise").font(.system(size: 10))
            } else {
                Text(strings.unknownReset).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            chart(cycle, plan: plan)
                .frame(height: 94)
            HStack(spacing: 8) {
                legend(strings.real, color: provider.tint, dashed: false)
                if cycle.inferredStart != nil { legend(strings.ideal, color: .secondary, dashed: true) }
                if plan != nil { legend(strings.recalibrated, color: .green, dashed: true) }
            }
            if cycle.inferredStart != nil {
                Text(strings.inferred).font(.system(size: 8)).foregroundStyle(.secondary)
            }
            if let plan {
                targets(plan)
            } else if sample.isStale(at: now) {
                Text(strings.stale).font(.system(size: 9)).foregroundStyle(.orange)
            }
        }
    }

    private func targets(_ plan: AgentWeeklyPlan) -> some View {
        let goals = plan.targets()
        return VStack(alignment: .leading, spacing: 7) {
            Text(strings.goals).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(strings.targetDay).frame(maxWidth: .infinity, alignment: .leading)
                Text(strings.targetLimit)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(strings.targetAllowance)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 9)).foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 9)
            Group {
                if goals.count <= 7 {
                    targetRows(goals, plan: plan)
                } else {
                    // An unusually long source deadline stays bounded. A
                    // normal weekly table shows its reset without scrolling.
                    ScrollView { targetRows(goals, plan: plan) }.frame(height: 252)
                }
            }
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.top, 4)
    }

    private func targetRows(_ goals: [AgentWeeklyPlan.Target], plan: AgentWeeklyPlan) -> some View {
        VStack(spacing: 0) {
            ForEach(goals) { goal in
                targetRow(goal, plan: plan)
            }
        }
    }

    private func targetRow(_ goal: AgentWeeklyPlan.Target, plan: AgentWeeklyPlan) -> some View {
        let isReset = goal.isActualReset
        let tint: Color = provider.tint
        let allowance = additional(goal.actualPercent, plan: plan)
        let day = goal.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        let resetTime = strings.targetReset
            + " · " + goal.date.formatted(.dateTime.hour().minute().locale(locale))
        let marker = goal.isActualReset ? strings.targetReset : strings.targetDay
        let descriptions = [marker, date(goal.date),
                            strings.targetLimit + " " + percent(goal.actualPercent),
                            strings.targetAllowance + " " + allowance]
        let accessible = descriptions.joined(separator: ", ")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(day).font(.system(size: 10, weight: .medium))
                if isReset { Text(resetTime).font(.system(size: 8)).foregroundStyle(tint) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            budgetCell(goal.actualPercent, plan: plan, tint: .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(allowance).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, 9).frame(height: 32)
        .background(isReset ? tint.opacity(0.09) : Color.clear)
        .overlay(alignment: .bottom) {
            if !isReset { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 9) }
        }
        .help(date(goal.date))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessible)
    }

    private func additional(_ percent: Double, plan: AgentWeeklyPlan) -> String {
        "+" + (percent - plan.initialPercent).formatted(
            .number.precision(.fractionLength(0)).locale(locale)) + " " + strings.points
    }

    private func budgetCell(_ value: Double?, plan: AgentWeeklyPlan, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let value {
                Text("≤ " + percent(value)).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            } else {
                Text("—").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func chart(_ cycle: AgentWeeklyUsage.Cycle, plan: AgentWeeklyPlan?) -> some View {
        let samples = cycle.samples.filter { $0.observedAt <= now }
        let start = min(cycle.inferredStart ?? samples.first?.observedAt ?? now, samples.first?.observedAt ?? now)
        let end = max(cycle.originalReset ?? now, cycle.latest?.resetsAt ?? now, now)
        return HStack(spacing: 4) {
            VStack { Text("100"); Spacer(); Text("50"); Spacer(); Text("0") }
                .font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 19)
            VStack(spacing: 2) {
                Canvas { context, size in
                    func position(_ date: Date, _ used: Double) -> CGPoint {
                        CGPoint(x: size.width * date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start)),
                                y: size.height * (1 - used / 100))
                    }
                    for value in [0.0, 50, 100] {
                        var grid = Path()
                        grid.move(to: CGPoint(x: 0, y: size.height * (1 - value / 100)))
                        grid.addLine(to: CGPoint(x: size.width, y: size.height * (1 - value / 100)))
                        context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                    }
                    func line(from date: Date, used: Double, to reset: Date, color: Color, dash: [CGFloat] = [4, 3]) {
                        var path = Path()
                        path.move(to: position(date, used))
                        path.addLine(to: position(reset, 100))
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: dash))
                    }
                    if let inferred = cycle.inferredStart, let reset = cycle.originalReset {
                        line(from: inferred, used: 0, to: reset, color: .gray)
                    }
                    if let plan { line(from: plan.start, used: plan.initialPercent, to: plan.reset, color: .green) }
                    for sample in samples {
                        let point = position(sample.observedAt, sample.usedPercent)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                                     with: .color(provider.tint))
                    }
                }
                .accessibilityLabel(strings.real + ": " + percent(cycle.latest?.usedPercent ?? 0))
                HStack {
                    Text(shortDate(start))
                    Spacer()
                    Text(shortDate(end))
                }.font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 3) {
            if dashed {
                Rectangle().fill(color).frame(width: 9, height: 1)
            } else {
                Circle().fill(color).frame(width: 4, height: 4)
            }
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: value) + " " + (formatter.timeZone.abbreviation(for: value) ?? "")
    }

    private func shortDate(_ value: Date) -> String {
        value.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    private func source(_ sample: AgentWeeklyUsage.Sample) -> String {
        switch sample.source {
        case "account": return strings.account
        case "sessionLog": return strings.log
        default: return strings.desktop
        }
    }
}
