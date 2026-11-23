// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

typealias NotchControlSurface = NotchCompactTests.NotchControlSurface

/// The production reading, without the account service or an open island.
/// Accessibility frames also catch a full label attached to a shorter fallback.
enum NotchAgentLimitReadingTests {
    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { checks(suite) }
    }

    @MainActor private static func checks(_ suite: TestSuite) {
        _ = NSApplication.shared
        // SwiftUI creates accessibility nodes lazily. Enable them only in
        // this process and restore the previous value when the checks end.
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previous, with: attribute) }
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 223, height: 24),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        // Two cards at the pairing threshold, each with 12-point side padding.
        let smallestPairedWidth = (NotchAgentSupport.pairWidth - NotchAgentSupport.spacing) / 2 - 24
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchAgents(language)
            let locale = language.formattingLocale()
            for display in NotchAgentLimitDisplay.allCases {
                let limit = AgentLimitWindow(id: "reading", kind: .weekly, minutes: 10_080, scope: "Sonnet",
                                             usedPercent: display == .remaining ? 0 : 100, resetsAt: nil)
                let share = NotchAgentSupport.limitShare(limit, display: display, text: text)
                let full = NSHostingView(rootView: Text(share)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize())
                let required = full.fittingSize.width
                for width: CGFloat in [smallestPairedWidth, 183, 223] {
                    for title in [text.session, "\(text.weekly) · Sonnet"] {
                        for countdown in [nil, AgentFormat.duration(6 * 86_400 + 23 * 3600, locale: locale),
                                          "≈ " + AgentFormat.duration(4 * 3600 + 59 * 60, locale: locale)] {
                            let host = NSHostingView(rootView: NotchAgentLimitReading(
                                title: title, share: share, countdown: countdown, tint: .white)
                                .environment(\.locale, locale).frame(width: width, height: 24))
                            window.contentView = host
                            window.setContentSize(CGSize(width: width, height: 24))
                            settle(host)
                            let readings = elements(host)
                                .filter { $0.accessibilityIdentifier?() == "notch.agentLimitShare" }
                            let context = "\(language.rawValue), \(width) pt, \(title), \(share), reset \(countdown ?? "none")"
                            suite.expect(readings.count == 1, "one visible limit reading: \(context)")
                            guard let reading = readings.first else { continue }
                            suite.expect(readingText(reading) == share,
                                         "the visible limit names remaining or used: \(context)")
                            let frame = reading.accessibilityFrame?() ?? .zero
                            let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
                            suite.expect(frame.width >= required - 1 && frame.minX >= bounds.minX - 1
                                         && frame.maxX <= bounds.maxX + 1 && frame.height > 0,
                                         "the whole worded limit stays inside its card: \(context)")
                        }
                    }
                }
            }
        }
        for (width, showsCountdown): (CGFloat, Bool) in [(183, false), (320, true)] {
            let host = NSHostingView(rootView: NotchAgentLimitReading(
                title: "Week · Sonnet", share: "100% used", countdown: "≈ 6d 23h", tint: .white)
                .frame(width: width, height: 24))
            window.contentView = host
            window.setContentSize(CGSize(width: width, height: 24))
            settle(host)
            let countdown = elements(host)
                .filter { $0.accessibilityIdentifier?() == "notch.agentLimitCountdown" }
            suite.expect(countdown.isEmpty != showsCountdown,
                         "a reset countdown gives way only when the complete reading needs its room at \(width) pt")
        }
        costReadings(suite, in: window)
    }

    @MainActor private static func costReadings(_ suite: TestSuite, in window: NSWindow) {
        let language = AppLanguage.ptBR
        let text = FeatureStrings.notchAgents(language)
        let locale = language.formattingLocale()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        let yesterday = today.addingTimeInterval(-86_400)
        func reply(_ provider: AgentProvider, _ project: String, _ date: Date, _ cost: Double?) -> AgentUsageRecord {
            AgentUsageRecord(provider: provider, date: date, model: project, project: project, session: "fixture",
                             tokens: AgentTokens(output: 100), cost: cost, savings: 0)
        }
        func snapshot(_ records: [AgentUsageRecord], missing: [CursorTranscriptActivity] = []) -> AgentUsageSnapshot {
            var result = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                                                    providers: Set(records.map(\.provider)), now: now, calendar: calendar)
            result.includeCursorActivity(missing)
            return result
        }
        func nodes<V: View>(_ view: V) -> [AnyObject] {
            let size = CGSize(width: 500, height: 140)
            let host = NSHostingView(rootView: view.environment(\.locale, locale)
                .frame(width: size.width, height: size.height))
            window.contentView = host
            window.setContentSize(size)
            settle(host)
            return elements(host)
        }
        func announces(_ nodes: [AnyObject], _ reading: String) -> Bool {
            nodes.contains { $0.accessibilityLabel?() == reading || readingText($0) == reading }
        }

        let earlier = today.addingTimeInterval(-4 * 86_400)
        let earlierReply = reply(.cursor, "fixture", earlier, 1.25)
        let undated = CursorTranscriptActivity(project: "fixture", undatedThrough: now)
        let baseline = nodes(NotchAgentActivityCard(snapshot: snapshot([earlierReply], missing: [undated]), text: text))
        suite.expect(announces(baseline, "1") && !announces(baseline, text.streak),
                     "an undated reply leaves the activity count at one measured day with no streak")
        let yesterdayMinute = Int(yesterday.timeIntervalSince1970 / 60)
        let dated = CursorTranscriptActivity(project: "fixture", minutes: IndexSet([yesterdayMinute - 1440, yesterdayMinute]))
        let observed = nodes(NotchAgentActivityCard(snapshot: snapshot([earlierReply], missing: [dated, undated]), text: text))
        suite.expect(announces(observed, "3") && announces(observed, text.streak),
                     "two consecutive unmetered Cursor days count toward activity and sustain the streak through yesterday")
        let onlyObserved = nodes(NotchAgentActivityCard(snapshot: snapshot([], missing: [dated]), text: text))
        suite.expect(!announces(onlyObserved, text.busiestDay) && announces(onlyObserved, "— · " + text.partialCostNote),
                     "observed days without measured usage supply neither a busiest day nor a cost")

        let metered = reply(.cursor, "partial", yesterday, 1.25)
        let cursorOnly = nodes(NotchAgentTrendCard(snapshot: snapshot([metered]), providers: [.cursor],
                                                  period: .week, text: text))
        suite.expect(announces(cursorOnly, text.week + " · " + AgentFormat.cost(1.25)),
                     "a fully measured Cursor project announces its exact API value, even with no other provider")
        let records = [metered, reply(.codex, "complete", today, 2)]
        let missing = CursorTranscriptActivity(project: metered.project,
                                               minutes: IndexSet(integer: Int(yesterday.timeIntervalSince1970 / 60) + 1))
        let idleDay = nodes(NotchAgentTrendCard(snapshot: snapshot([metered], missing: [missing]), providers: [.cursor],
                                                period: .today, text: text))
        suite.expect(announces(idleDay, text.today + " · " + AgentFormat.cost(0)),
                     "yesterday's partial Cursor cost leaves today's empty Trend interval exact")
        let history = snapshot(records, missing: [missing])
        let minimum = "≥ " + AgentFormat.cost(3.25) + " · " + text.partialCostNote
        let trend = nodes(NotchAgentTrendCard(snapshot: history, providers: [.cursor, .codex], period: .week, text: text))
        suite.expect(announces(trend, text.week + " · " + minimum),
                     "Trend announces the week's minimum and explains the missing coverage")
        let activity = nodes(NotchAgentActivityCard(snapshot: history, text: text))
        let day = today.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        suite.expect(announces(activity, minimum) && announces(activity, day + " · " + AgentFormat.cost(2)),
                     "Activity announces the map's minimum while keeping its fully priced busiest day exact")
        let tokens = text.tokens(AgentFormat.tokens(100))
        for (date, amount, note) in [(yesterday, "≥ " + AgentFormat.cost(1.25), " · " + text.partialCostNote),
                                     (today, AgentFormat.cost(2), "")] {
            let day = date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            let trend = nodes(NotchAgentTrendCard(snapshot: history, providers: [.cursor, .codex], period: .week,
                                                  text: text, hovered: date))
            suite.expect(announces(trend, day + " · " + amount + " · " + tokens + note),
                         "the selected Trend day announces its own cost coverage beside its tokens")
            let activity = nodes(NotchAgentActivityCard(snapshot: history, text: text, hovered: date))
            suite.expect(announces(activity, day + " · " + amount + note),
                         "the selected Activity day announces its own cost coverage")
        }

        let usage = snapshot(records + [reply(.codex, "unpriced", today, nil)], missing: [missing]).usage(.week)
        let shares = nodes(NotchAgentShareCard(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                               shares: usage.projects, byCost: usage.fullyPriced, text: text))
        let readings = shares.filter { $0.accessibilityRole?() == .staticText }.compactMap { readingText($0) }
        for (project, value) in [("partial", tokens + " · ≥ " + AgentFormat.cost(1.25) + " · " + text.partialCostNote),
                                 ("complete", tokens + " · " + AgentFormat.cost(2)),
                                 ("unpriced", tokens + " · — · " + text.partialCostNote)] {
            let reading = project + " · " + value
            suite.expect(readings.filter { $0 == reading }.count == 1,
                         "a token-ranked project announces its own cost coverage: \(project), got \(readings)")
        }
    }

    @MainActor private static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
    }

    @MainActor private static func readingText(_ element: AnyObject) -> String? {
        // AppKit declares several return types for this selector. Use its
        // object result without selecting a control-specific Swift overload.
        let selector = NSSelectorFromString("accessibilityValue")
        if let object = element as? NSObject, object.responds(to: selector),
           let value = object.perform(selector)?.takeUnretainedValue() as? String {
            return value
        }
        return element.accessibilityLabel?()
    }

    // SwiftUI's nodes expose the selectors without inheriting from
    // NSAccessibilityElement or declaring NSAccessibilityProtocol.
    @MainActor private static func elements(_ element: AnyObject) -> [AnyObject] {
        [element] + (element.accessibilityChildren?() ?? []).flatMap { elements($0 as AnyObject) }
    }
}
