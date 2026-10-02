// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

// A floating capsule has no camera inside it, so what the closed island shows
// runs in one row from one round end to the other, and the capsule is as
// wide as that row. The service measures each row with NotchCapsuleLayout,
// and these views draw it with the same measures. A click anywhere on the
// capsule opens the island, on the activity's page when it shows one.

private typealias CapsuleLayout = NotchCapsuleLayout

/// One row between the capsule's round ends, centred in the menu bar.
private struct NotchCapsuleRow<Content: View>: View {
    let size: CGSize
    let geometry: NotchGeometry
    var leading = CapsuleLayout.endPadding
    var trailing = CapsuleLayout.endPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        let side = CapsuleLayout.side(geometry)
        content()
            .padding(.leading, side + leading)
            .padding(.trailing, side + trailing)
            .frame(width: size.width, height: geometry.stripHeight)
            .foregroundStyle(.white)
    }
}

private extension Text {
    func capsuleTitle() -> some View {
        font(Font(CapsuleLayout.titleFont as CTFont)).lineLimit(1)
    }

    func capsuleDetail() -> some View {
        font(Font(CapsuleLayout.detailFont as CTFont)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
    }
}

private struct NotchCapsuleSymbol: View {
    let name: String
    var tint: Color = .white

    var body: some View {
        Image(systemName: name)
            .font(.system(size: CapsuleLayout.symbolSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: CapsuleLayout.symbolWidth)
            .capsuleCentred(name)
            .accessibilityHidden(true)
    }
}

private extension View {
    /// A symbol's ink, not its frame, meets the row's middle line, where the
    /// text beside it has its capitals.
    func capsuleCentred(_ symbol: String, size: CGFloat = CapsuleLayout.symbolSize,
                        weight: NSFont.Weight = .medium) -> some View {
        alignmentGuide(VerticalAlignment.center) {
            $0[VerticalAlignment.center] + CapsuleLayout.symbolDrop(symbol, size: size, weight: weight)
        }
    }
}

/// Feedback, a message or a mirrored banner, read from one end to the other.
struct NotchCapsuleNoticeView: View {
    let notice: NotchNotice
    let geometry: NotchGeometry
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch notice.event {
        // A warning reads as one in any agent's color; other AI notices wear it.
        case .agents: return notice.symbol.hasPrefix("exclamationmark") ? .orange : notice.agent?.tint ?? .white
        default: return .white
        }
    }

    var body: some View {
        NotchCapsuleRow(size: size, geometry: geometry) {
            if let content = notice.notification {
                banner(content)
            } else if let level = notice.level {
                levelRow(level)
            } else {
                messageRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }

    private func banner(_ content: NotchNotificationContent) -> some View {
        HStack(spacing: CapsuleLayout.spacing) {
            NotchNotificationAppIcon(app: content.app, size: CapsuleLayout.notificationIconSide(geometry))
            Text(content.compactTitle).capsuleTitle().layoutPriority(1)
            if !content.compactDetail.isEmpty {
                Text(content.compactDetail).capsuleDetail()
                    .padding(.leading, CapsuleLayout.groupSpacing - CapsuleLayout.spacing)
            }
        }
    }

    /// The meter keeps its place while the reading changes: the reading
    /// always has the room of its widest value.
    private func levelRow(_ level: Double) -> some View {
        HStack(spacing: CapsuleLayout.spacing) {
            NotchCapsuleSymbol(name: notice.symbol, tint: tint)
            NotchMeter(value: level, height: CapsuleLayout.meterHeight, tint: tint)
                .frame(width: CapsuleLayout.meterWidth)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: level)
            Text(notice.detail)
                .font(Font(CapsuleLayout.levelFont as CTFont))
                .lineLimit(1)
                .contentTransition(.numericText())
                .frame(width: CapsuleLayout.levelReadingWidth(notice.detail), alignment: .trailing)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: notice.detail)
        .transaction { $0.disablesAnimations = false }
    }

    private var messageRow: some View {
        HStack(spacing: CapsuleLayout.spacing) {
            mark
            Text(notice.title).capsuleTitle().layoutPriority(1)
            if !notice.detail.isEmpty {
                Text(notice.detail).capsuleDetail()
                    .truncationMode(notice.event == .accessory ? .middle : .tail)
                    .padding(.leading, CapsuleLayout.groupSpacing - CapsuleLayout.spacing)
            }
        }
    }

    @ViewBuilder private var mark: some View {
        // A notice about the agent itself wears its mark; warnings and
        // renewals keep a symbol that says what happened.
        if notice.event == .agents, let agent = notice.agent, notice.symbol == agent.symbol {
            NotchAgentMark(provider: agent, size: CapsuleLayout.symbolSize).frame(width: CapsuleLayout.symbolWidth)
        } else if notice.event == .track {
            NotchCapsuleTrackArtwork(side: min(CapsuleLayout.symbolWidth, CapsuleLayout.artworkSide(geometry)))
                .frame(width: CapsuleLayout.symbolWidth)
        } else {
            NotchCapsuleSymbol(name: notice.symbol, tint: tint)
        }
    }
}

/// The new song's cover, read as it arrives: it often lands after the title.
private struct NotchCapsuleTrackArtwork: View {
    @ObservedObject private var music = NotchMusicService.shared
    let side: CGFloat

    var body: some View { NotchMusicCover(artwork: music.artwork, side: side, radius: side * 0.24) }
}

/// The closed capsule at rest: bare, or with the charge or the AI allowance
/// the person chose, in its middle.
struct NotchCapsuleRestingView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    var body: some View {
        NotchCapsuleRow(size: size, geometry: geometry) {
            HStack(spacing: 5) {
                switch service.idleContent {
                case .battery:
                    Image(systemName: "battery.100percent").font(.system(size: CapsuleLayout.symbolSize))
                        .capsuleCentred("battery.100percent", weight: .regular)
                    if let percent = service.power.chargePercent {
                        Text("\(percent)%").font(Font(CapsuleLayout.smallFont as CTFont)).lineLimit(1)
                    }
                case .agents:
                    NotchAgentRestingWing(leading: true)
                    NotchAgentRestingWing(leading: false)
                case .music:
                    if let artwork = music.artwork {
                        NotchMusicCover(artwork: artwork, side: CapsuleLayout.artworkSide(geometry),
                                        radius: CapsuleLayout.artworkSide(geometry) / 2)
                    }
                    if music.playback?.isPlaying == true {
                        NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 10, tint: music.artworkTint?.color ?? .white)
                    }
                case .none:
                    EmptyView()
                }
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityHidden(true)
    }
}

/// Playing music: the cover in the round end, concentric with it, the title
/// in the middle and the bars at the other end.
struct NotchCapsuleMusicStrip: View {
    @ObservedObject var service: NotchService
    var snapshot: NotchCompactMusicSnapshot? = nil
    /// The surface the strip fills; a departing strip keeps its own.
    var size: CGSize? = nil
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { snapshot?.geometry ?? displayGeometry ?? service.geometry }
    /// A new song stays off the strip until its notice has shown it.
    private var shown: NotchCompactMusicSnapshot? { snapshot ?? service.heldMusic }
    private var playback: NotchPlayback? { shown?.playback ?? music.playback }
    private var artwork: NSImage? { shown == nil ? music.artwork : shown?.artwork }
    private var tint: NotchArtworkTint? { shown == nil ? music.artworkTint : shown?.tint }
    private var title: String { playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }

    var body: some View {
        let side = CapsuleLayout.artworkSide(geometry)
        let named = service.capsuleMusicTitleShown
        NotchCapsuleRow(size: size ?? CapsuleLayout.musicSurface(title: named ? title : nil, geometry: geometry),
                        geometry: geometry, leading: CapsuleLayout.artworkInset(geometry)) {
            HStack(spacing: 0) {
                NotchMusicCover(artwork: artwork, side: side, radius: side / 2)
                // A song is named only as it starts; then the cover and bars say enough.
                Group {
                    if named { Text(title).capsuleTitle().truncationMode(.tail).transition(.opacity) }
                    else { Color.clear }
                }
                .padding(.horizontal, CapsuleLayout.endPadding)
                .frame(maxWidth: .infinity)
                NotchLiveEqualizerBars(isPlaying: playback?.isPlaying == true,
                                       bars: NotchLayout.compactMusicBarCount,
                                       barWidth: NotchLayout.compactMusicBarWidth,
                                       height: CapsuleLayout.barsHeight(geometry),
                                       tint: tint?.color ?? .white)
            }
            .modifier(NotchMusicSwipeFeedback(enabled: snapshot == nil))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
        .help(title)
    }
}

/// A running timer: its mark, or the activity it shares the capsule with,
/// and its reading.
struct NotchCapsuleTimerStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }
    private var companion: NotchCompactActivity? { service.compactCompanion }

    var body: some View {
        NotchCapsuleRow(size: size, geometry: geometry,
                        leading: companion == .music ? CapsuleLayout.artworkInset(geometry) : CapsuleLayout.endPadding) {
            HStack(spacing: CapsuleLayout.markGap(companion)) {
                mark
                if timer.session.isRunning {
                    TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                        for: timer.session, at: timer.now)), by: 1)) { _ in reading }
                } else {
                    reading
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
        .accessibilityValue(NotchTimerSupport.clockText(for: timer.session, at: timer.now))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    @ViewBuilder private var mark: some View {
        if let companion {
            NotchCapsuleCompanionMark(companion: companion, geometry: geometry)
        } else {
            NotchCapsuleSymbol(name: timer.session.completed ? "checkmark.circle" : timer.session.isPaused ? "pause.circle"
                               : timer.session.countsUp ? "stopwatch" : "timer", tint: .orange)
        }
    }

    private var reading: some View {
        let text = NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                 locale: Locale(identifier: l10n.language.rawValue))
        return Text(text)
            .font(Font(CapsuleLayout.readingFont as CTFont))
            .foregroundStyle(.orange)
            .lineLimit(1).fixedSize()
            .modifier(NotchRollingDigits(value: text, countsDown: !timer.session.countsUp, everySecond: false))
            // A reading that gains or loses a character, like 10m becoming
            // 9m, resizes the capsule; the service measures the same reading.
            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                DispatchQueue.main.async { service.refreshPresentation() }
            }
    }
}

/// The working agents' marks, side by side, each in a frame wider than it.
private struct NotchCapsuleAgentMarks: View {
    let providers: [AgentProvider]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(providers) { NotchAgentGlyph(provider: $0, size: CapsuleLayout.agentMarkSize(working: providers.count)) }
        }
    }
}

/// What shares the capsule with a timer or an event: a download's arrow and
/// percentage, the working agents, the playing track's cover, or the next
/// event's dot and countdown.
private struct NotchCapsuleCompanionMark: View {
    let companion: NotchCompactActivity
    let geometry: NotchGeometry
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        switch companion {
        case .downloads:
            HStack(spacing: CapsuleLayout.markSpacing) {
                NotchCapsuleSymbol(name: "arrow.down.circle.fill")
                if let fraction = downloads.items.first(where: { $0.active && !$0.completed })?.fraction {
                    Text(fraction, format: NotchDownloadSupport.percentFormat(l10n.language))
                        .font(Font(CapsuleLayout.smallFont as CTFont)).lineLimit(1)
                        .frame(width: CapsuleLayout.downloadPercentWidth(l10n.language), alignment: .trailing)
                }
            }
        case .agents:
            NotchCapsuleAgentMarks(providers: AgentProvider.allCases.filter { provider in
                usage.snapshot.live.contains { $0.provider == provider }
            })
        case .music:
            let side = CapsuleLayout.artworkSide(geometry)
            NotchMusicCover(artwork: music.artwork, side: side, radius: side / 2)
        case .calendar:
            if let countdown = calendar.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NotchCapsuleCalendarStrip.clockMark(countdown, now: context.date)
                }
            }
        case .timer, .keepAwake, .watch:
            EmptyView()
        }
    }
}

/// A working agent: its mark and the reading the person chose.
struct NotchCapsuleAgentStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    private var working: [AgentProvider] {
        AgentProvider.allCases.filter { provider in usage.snapshot.live.contains { $0.provider == provider } }
    }

    var body: some View {
        let working = working
        NotchCapsuleRow(size: size, geometry: displayGeometry ?? service.geometry) {
            HStack(spacing: CapsuleLayout.spacing) {
                NotchCapsuleAgentMarks(providers: working)
                NotchAgentReadoutTimeline(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed) { date in
                    let text = reading(at: date)
                    Text(text)
                        .font(Font(CapsuleLayout.readingFont as CTFont))
                        .foregroundStyle(working.first?.tint ?? .white)
                        .lineLimit(1).fixedSize()
                        // A reading that gains a digit, like an hour passing,
                        // widens the capsule; the service measures the same.
                        .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                            DispatchQueue.main.async { service.refreshPresentation() }
                        }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(working.map(\.displayName).joined(separator: ", "))
        .accessibilityValue(reading(at: Date()))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date) -> String {
        NotchAgentSupport.stripReading(usage.snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                       display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                       focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// A download: its arrow and name, its progress and the percentage.
struct NotchCapsuleDownloadStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let item = downloads.items.first { $0.active && !$0.completed }
        let name = item?.name ?? FeatureStrings.notchFiles(l10n.language).downloadsTitle
        NotchCapsuleRow(size: size, geometry: displayGeometry ?? service.geometry) {
            HStack(spacing: CapsuleLayout.spacing) {
                NotchCapsuleSymbol(name: "arrow.down.circle.fill")
                Text(name).font(Font(CapsuleLayout.detailFont as CTFont)).lineLimit(1).truncationMode(.middle)
                if let fraction = item?.fraction {
                    NotchMeter(value: fraction, height: CapsuleLayout.meterHeight)
                        .frame(width: CapsuleLayout.downloadMeterWidth)
                        .padding(.leading, CapsuleLayout.groupSpacing - CapsuleLayout.spacing)
                    Text(fraction, format: NotchDownloadSupport.percentFormat(l10n.language))
                        .font(Font(CapsuleLayout.smallFont as CTFont))
                        .lineLimit(1)
                        .frame(width: CapsuleLayout.downloadPercentWidth(l10n.language), alignment: .trailing)
                } else {
                    ProgressView().controlSize(.mini).frame(width: CapsuleLayout.spinnerWidth)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(item?.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// A watched area: the eye, then what the area reads now, or the area
/// itself when it holds no text.
struct NotchCapsuleWatchStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let geometry = displayGeometry ?? service.geometry
        NotchCapsuleRow(size: size, geometry: geometry) {
            HStack(spacing: CapsuleLayout.spacing) {
                NotchWatchEye(size: CapsuleLayout.symbolSize, hidden: watch.state == .hidden)
                    .frame(width: CapsuleLayout.symbolWidth)
                if watch.showsThumbnail, let preview = watch.preview {
                    NotchWatchThumbnail(image: preview, height: max(8, geometry.stripBodyHeight - 6))
                } else if watch.headline.isEmpty {
                    // A hidden window's slashed eye says enough until it is read.
                    if watch.state == .hidden {
                        Color.clear.frame(width: CapsuleLayout.spinnerWidth, height: 1)
                    } else {
                        ProgressView().controlSize(.mini).frame(width: CapsuleLayout.spinnerWidth)
                    }
                } else {
                    Text(watch.headline).font(Font(CapsuleLayout.levelFont as CTFont))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.notchWatch(l10n.language).title)
        .accessibilityValue(watch.headline)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}

/// The next timed event, or the one under way: its color and title, and
/// the countdown with the time it starts or ends.
struct NotchCapsuleCalendarStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    var body: some View {
        if let countdown = calendar.countdown {
            let companion = service.compactCompanion
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let title = CapsuleLayout.calendarTitle(countdown, language: l10n.language)
                let remaining = NotchCalendarSupport.countdownText(until: countdown.target, now: context.date)
                NotchCapsuleRow(size: size, geometry: geometry,
                                leading: companion == .music ? CapsuleLayout.artworkInset(geometry) : CapsuleLayout.endPadding) {
                    if let companion {
                        // Paired, what shares the capsule takes the title's place,
                        // and the title moves to the tooltip and VoiceOver.
                        HStack(spacing: CapsuleLayout.markGap(.calendar)) {
                            NotchCapsuleCompanionMark(companion: companion, geometry: geometry)
                            Self.clockMark(countdown, now: context.date)
                        }
                    } else {
                        HStack(spacing: CapsuleLayout.spacing) {
                            Self.dot(countdown.event)
                            Text(title).capsuleTitle().truncationMode(.tail)
                            // The time left keeps its place; the start or end time
                            // beside it gives way first when the bar is short.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: CapsuleLayout.markSpacing) {
                                    Self.clock(remaining, ongoing: countdown.ongoing)
                                    Text(NotchCalendarSupport.timeText(countdown, locale: l10n.language.formattingLocale()))
                                        .font(Font(CapsuleLayout.smallFont as CTFont))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1).fixedSize()
                                }
                                Self.clock(remaining, ongoing: countdown.ongoing)
                            }
                            .padding(.leading, CapsuleLayout.groupSpacing - CapsuleLayout.spacing)
                            .layoutPriority(1)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(countdown.ongoing ? text.ongoing : text.next): \(title)")
                .accessibilityValue(NotchCalendarSupport.countdownAccessibilityText(
                    until: countdown.target, now: context.date, locale: l10n.language.formattingLocale()))
                .accessibilityHint(FeatureStrings.notch(l10n.language).open)
                .help(title)
            }
            .accessibilityIdentifier("notch.calendarCountdown")
        }
    }

    /// The event's dot and its countdown, as a pair shows the event.
    static func clockMark(_ countdown: NotchCalendarCountdown, now: Date) -> some View {
        HStack(spacing: CapsuleLayout.markSpacing) {
            dot(countdown.event)
            clock(NotchCalendarSupport.countdownText(until: countdown.target, now: now), ongoing: countdown.ongoing)
        }
    }

    private static func dot(_ event: NotchCalendarEvent) -> some View {
        Circle().fill(event.color.color)
            .frame(width: CapsuleLayout.calendarDotSide, height: CapsuleLayout.calendarDotSide)
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5) }
    }

    /// Time left in an event under way takes the agenda's "happening now"
    /// color, so it never reads as a wait for the next one.
    private static func clock(_ remaining: String, ongoing: Bool) -> some View {
        Text(remaining)
            .font(Font(CapsuleLayout.readingFont as CTFont))
            .lineLimit(1).fixedSize()
            .foregroundStyle(ongoing ? Color.mint : Color.white)
            .modifier(NotchRollingDigits(value: remaining, countsDown: true, everySecond: false))
    }
}

/// A running Keep Awake session: the cup of its tile, then the time it has
/// left, or infinity for a session without an end. The reading changes once
/// a minute, so the clock wakes only then.
struct NotchCapsuleKeepAwakeStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    /// Another display's capsule, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let end = awake.endDate {
            TimelineView(.periodic(from: NotchKeepAwakeSupport.tickStart(until: end, now: Date()), by: 60)) { context in
                row(end: end, now: context.date)
            }
        } else {
            row(end: nil, now: Date())
        }
    }

    private func row(end: Date?, now: Date) -> some View {
        NotchCapsuleRow(size: size, geometry: displayGeometry ?? service.geometry) {
            HStack(spacing: CapsuleLayout.spacing) {
                // The cup is wider than the slot other marks share; the
                // capsule measures it as drawn.
                Image(systemName: NotchKeepAwakeSupport.symbol)
                    .font(.system(size: CapsuleLayout.symbolSize, weight: .medium))
                    .foregroundStyle(.yellow)
                    .capsuleCentred(NotchKeepAwakeSupport.symbol)
                if let end {
                    let text = NotchKeepAwakeSupport.compactText(until: end, now: now,
                                                                locale: Locale(identifier: l10n.language.rawValue))
                    Text(text)
                        .font(Font(CapsuleLayout.readingFont as CTFont))
                        .foregroundStyle(.yellow)
                        .lineLimit(1).fixedSize()
                        // A reading that gains or loses a character, like 10m
                        // becoming 9m, resizes the capsule; the service measures the same.
                        .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                            DispatchQueue.main.async { service.refreshPresentation() }
                        }
                } else {
                    Image(systemName: NotchKeepAwakeSupport.openSymbol)
                        .font(.system(size: CapsuleLayout.readingFont.pointSize, weight: .medium))
                        .foregroundStyle(.yellow)
                        .capsuleCentred(NotchKeepAwakeSupport.openSymbol, size: CapsuleLayout.readingFont.pointSize)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.localized(l10n.language).keepAwakeTitle)
        .accessibilityValue(NotchKeepAwakeStrip.status(end: end, language: l10n.language))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.keepAwake")
    }
}

/// Screen capture controls folded while an area is chosen: the tool and the
/// way back to the controls.
struct NotchCapsuleCaptureStrip: View {
    let symbol: String
    let geometry: NotchGeometry
    let size: CGSize

    var body: some View {
        NotchCapsuleRow(size: size, geometry: geometry) {
            HStack(spacing: CapsuleLayout.spacing) {
                NotchCapsuleSymbol(name: symbol)
                NotchCapsuleSymbol(name: "chevron.down")
            }
        }
        .accessibilityHidden(true)
    }
}
