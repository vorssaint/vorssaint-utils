// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The next timed event, or the one under way, stays readable beside the
/// camera and moves below a physical notch when the menu bar cannot spare
/// two useful wings. Paired with another activity, that activity's mark
/// takes the title's side and the event keeps its dot and clock. A Join
/// control sits with the clock when Settings asks for one and the event
/// carries a Teams, Zoom or Google Meet link.
struct NotchCalendarStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchCalendarJoinButton) private var joinButton = false

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var usesFullRow: Bool { geometry.compactActivityUsesFooter || geometry.compactActivityWingWidth == 0 }

    var body: some View {
        // An event ending moves the countdown on, or clears it, before the
        // strip has left.
        NotchStripHold(calendar.countdown, shows: service.compactActivity == .calendar) { content($0) }
    }

    @ViewBuilder private func content(_ countdown: NotchCalendarCountdown?) -> some View {
        if let countdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let displayTitle = Self.displayTitle(countdown.event, untitled: text.untitled)
                let remaining = NotchCalendarSupport.countdownText(until: countdown.target, now: context.date)
                let showsJoin = joinButton && countdown.event.meetingURL != nil
                Group {
                    if let companion = service.compactCompanion, geometry.compactActivityWingWidth > 0 {
                        paired(countdown, companion: companion, title: displayTitle, remaining: remaining,
                               now: context.date, showsJoin: showsJoin)
                    } else if usesFullRow {
                        soloFullRow(countdown, title: displayTitle, remaining: remaining, now: context.date,
                                    showsJoin: showsJoin)
                    } else {
                        soloWings(countdown, title: displayTitle, remaining: remaining, now: context.date,
                                  showsJoin: showsJoin)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, geometry.compactActivityHorizontalPadding)
                .padding(.top, geometry.compactActivityTopPadding)
            }
            .accessibilityIdentifier("notch.calendarCountdown")
        }
    }

    private func countdownAccessibility(_ countdown: NotchCalendarCountdown, title: String,
                                        now: Date, showsJoin: Bool) -> NotchCountdownAccessibility {
        NotchCountdownAccessibility(label: "\(countdown.ongoing ? text.ongoing : text.next): \(title)",
                                    value: NotchCalendarSupport.countdownAccessibilityText(
                                        until: countdown.target, now: now, locale: l10n.language.formattingLocale()),
                                    hint: FeatureStrings.notch(l10n.language).open, help: title,
                                    join: showsJoin ? text.joinMeeting : nil,
                                    onJoin: showsJoin ? { service.joinCountdownMeeting() } : nil)
    }

    private var rowInset: CGFloat { max(10, geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)) }

    /// One row below the camera: title opens Calendar, Join opens the meeting.
    @ViewBuilder private func soloFullRow(_ countdown: NotchCalendarCountdown, title: String, remaining: String,
                                          now: Date, showsJoin: Bool) -> some View {
        Group {
            if showsJoin {
                HStack(spacing: 6) {
                    Button { service.openCountdownEvent() } label: {
                        HStack(spacing: 6) {
                            Self.dot(countdown.event)
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .modifier(countdownAccessibility(countdown, title: title, now: now, showsJoin: false))
                    joinControl
                    Button { service.openCountdownEvent() } label: {
                        Self.clock(remaining, ongoing: countdown.ongoing)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .modifier(countdownAccessibility(countdown, title: title, now: now, showsJoin: true))
                }
            } else {
                Button { service.openCountdownEvent() } label: {
                    HStack(spacing: 6) {
                        Self.dot(countdown.event)
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Self.clock(remaining, ongoing: countdown.ongoing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .modifier(countdownAccessibility(countdown, title: title, now: now, showsJoin: false))
            }
        }
        .padding(.horizontal, rowInset)
        .frame(width: geometry.compactActivitySize.width - geometry.compactActivityHorizontalPadding * 2,
               height: geometry.compactActivityContentHeight)
    }

    /// Title left of the camera, clock (and Join) on the right as siblings so
    /// neither click steals the other.
    private func soloWings(_ countdown: NotchCalendarCountdown, title: String, remaining: String,
                           now: Date, showsJoin: Bool) -> some View {
        let inset = geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        return HStack(spacing: 0) {
            Button { service.openCountdownEvent() } label: {
                HStack(spacing: NotchCalendarSupport.stripTitleSpacing) {
                    Self.dot(countdown.event)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                }
                .padding(.leading, inset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .trailing)
                .clipped()
                .contentShape(Rectangle())
            }
            .modifier(countdownAccessibility(countdown, title: title, now: now, showsJoin: false))
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            HStack(spacing: NotchCalendarSupport.stripJoinSpacing) {
                if showsJoin { joinControl }
                Button { service.openCountdownEvent() } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: NotchCalendarSupport.stripClockSpacing) {
                            Self.clock(remaining, ongoing: countdown.ongoing)
                            Text(NotchCalendarSupport.timeText(countdown, locale: l10n.language.formattingLocale()))
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.55))
                                .fixedSize()
                        }
                        Self.clock(remaining, ongoing: countdown.ongoing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .modifier(countdownAccessibility(countdown, title: title, now: now, showsJoin: showsJoin))
            }
            .padding(.trailing, inset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .leading)
        }
        .frame(width: geometry.compactActivitySize.width - geometry.compactActivityHorizontalPadding * 2,
               height: geometry.compactActivityContentHeight)
    }

    /// Both sides sit at the ends, as a timer's pair does, and each opens
    /// its own page. Below a crowded notch the row splits the same way.
    private func paired(_ countdown: NotchCalendarCountdown, companion: NotchCompactActivity, title: String,
                        remaining: String, now: Date, showsJoin: Bool) -> some View {
        let footer = geometry.compactActivityUsesFooter
        let markInset = NotchCompanionMark.inset(companion, geometry: geometry)
        return HStack(spacing: 0) {
            Button { service.openActivity(companion.module) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        NotchCompanionMark(companion: companion, geometry: geometry)
                    }
                }
                .padding(.leading, footer ? max(rowInset, markInset) : markInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(NotchCompanionMark.label(companion, language: l10n.language))
            .accessibilityHint(FeatureStrings.notch(l10n.language).open)
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            HStack(spacing: NotchCalendarSupport.stripJoinSpacing) {
                if showsJoin { joinControl }
                Button { service.openCountdownEvent() } label: {
                    Self.clockMark(countdown, remaining: remaining)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .modifier(countdownAccessibility(countdown, title: title, now: now, showsJoin: showsJoin))
            }
            .padding(.trailing, footer ? rowInset : geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0))
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .trailing)
        }
    }

    /// Opens the meeting without expanding the island.
    private var joinControl: some View {
        NotchCalendarJoinControl(accessibilityTitle: text.joinMeeting) {
            service.joinCountdownMeeting()
        }
    }

    static func displayTitle(_ event: NotchCalendarEvent, untitled: String) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? untitled : title
    }

    /// The event's dot and its clock, as the island draws them beside another activity.
    static func clockMark(_ countdown: NotchCalendarCountdown, remaining: String) -> some View {
        HStack(spacing: NotchCalendarSupport.stripClockSpacing) {
            dot(countdown.event)
            clock(remaining, ongoing: countdown.ongoing)
        }
    }

    private static func dot(_ event: NotchCalendarEvent) -> some View {
        Circle().fill(event.color.color).frame(width: NotchCalendarSupport.stripDotWidth,
                                               height: NotchCalendarSupport.stripDotWidth)
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }

    /// Time left in an event under way takes the agenda's "happening now"
    /// color, so it never reads as a wait for the next one.
    private static func clock(_ remaining: String, ongoing: Bool) -> some View {
        Text(remaining)
            .font(.system(size: 13, weight: .medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(ongoing ? Color.mint : Color.white)
            .modifier(NotchRollingDigits(value: remaining, countsDown: true, everySecond: false))
    }
}

/// Video icon that joins the meeting without opening the island.
struct NotchCalendarJoinControl: View {
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "video.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: NotchCalendarSupport.stripJoinWidth,
                       height: NotchCalendarSupport.stripJoinWidth)
                .background(.white.opacity(0.16), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .layoutPriority(2)
        .help(accessibilityTitle)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityIdentifier("notch.calendarJoin")
    }
}

/// One control for the event: what it is, the time left and where it leads.
private struct NotchCountdownAccessibility: ViewModifier {
    let label: String
    let value: String
    let hint: String
    let help: String
    var join: String? = nil
    var onJoin: (() -> Void)? = nil

    func body(content: Content) -> some View {
        Group {
            if let join, let onJoin {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                    .accessibilityHint(hint)
                    .help(help)
                    .accessibilityAction(named: Text(join), onJoin)
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                    .accessibilityHint(hint)
                    .help(help)
            }
        }
    }
}
