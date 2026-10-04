// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// What the lock screen may show, settled when it appears: preferences cannot
/// change while the Mac is locked, so the views never read them again.
final class NotchLockScreenModel: ObservableObject {
    struct Gates: Equatable {
        var music = false
        var timer = false
        var agents = false
        var downloads = false
        var countdown = false
        var timeLeft = false
    }

    @Published var gates = Gates()
    /// Kept for the whole time the Mac stays locked, across the display
    /// sleeping and waking, and cleared once it unlocks.
    @Published var playedWhileLocked = false
    @Published var padlockOpen = false

    func showsMusic(_ playback: NotchPlayback?) -> Bool {
        gates.music && playback.map {
            NotchLockScreenSupport.showsMusic(isPlaying: $0.isPlaying, playedWhileLocked: playedWhileLocked)
        } == true
    }
}

/// The island at rest with a padlock beside the camera, and the music's bars
/// on the other side while a song plays. The padlock closes as the Mac locks
/// and opens as it unlocks, before the island returns underneath.
struct NotchLockScreenIsland: View {
    @ObservedObject var model: NotchLockScreenModel
    let size: CGSize
    let cameraWidth: CGFloat
    @ObservedObject private var music = NotchMusicService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shoulder = NotchLayout.shoulder(height: size.height)
        let wing = max(0, (size.width - cameraWidth) / 2 - shoulder)
        let playing = model.showsMusic(music.playback) && music.playback?.isPlaying == true
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height))
            .fill(.black)
            .overlay {
                HStack(spacing: 0) {
                    Image(systemName: model.padlockOpen ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: min(13, size.height * 0.42), weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, options: .speed(1.4), value: reduceMotion ? false : model.padlockOpen)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.padlockOpen)
                        .frame(width: wing, height: size.height)
                    Spacer(minLength: 0)
                    NotchEqualizerBars(isPlaying: playing, bars: 4, barWidth: 2.5, height: min(12, size.height * 0.38),
                                       tint: music.artworkTint?.color ?? .white)
                        .opacity(playing ? 1 : 0)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playing)
                        .frame(width: wing, height: size.height)
                }
                .padding(.horizontal, shoulder)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

/// The player's own Liquid Glass, clear so the wallpaper still reads through
/// it and bends at its edges, and smoked just enough for white type over any
/// photo: the glass the island itself takes when it is set to glass. Before
/// macOS 26 the frosted panel of the app's floating surfaces stands in, and
/// Reduce Transparency makes it solid.
private struct NotchLockScreenGlass: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(white: 0.12))
                } else {
                    ZStack {
                        glass(shape)
                        shape.fill(.black.opacity(contrast == .increased ? 0.5 : 0.24))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(.white.opacity(contrast == .increased ? 0.45 : 0), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder private func glass(_ shape: RoundedRectangle) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.clear, in: shape)
                .environment(\.appearsActive, true)
                .materialActiveAppearance(.active)
        } else {
            NotchLockScreenMaterial(cornerRadius: cornerRadius)
        }
#else
        NotchLockScreenMaterial(cornerRadius: cornerRadius)
#endif
    }
}

/// The frosted material has to round its own layer: SwiftUI clips what it
/// draws, not a material blurring what lies behind the window.
private struct NotchLockScreenMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

/// The song in the middle of the lock screen, on one pane of Liquid Glass:
/// the cover, its title, a timeline that seeks and the player's own buttons.
/// A smaller display takes a smaller cover, then lays it beside the title.
struct NotchLockScreenPlayer: View {
    @ObservedObject var model: NotchLockScreenModel
    let size: CGSize
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var accent: Color { music.artworkTint?.color ?? .white }

    var body: some View {
        let shown = model.showsMusic(music.playback)
        ZStack {
            if shown, let playback = music.playback {
                ViewThatFits(in: .vertical) {
                    player(playback, artwork: 112)
                    player(playback, artwork: 84)
                    compact(playback)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: shown)
    }

    private func player(_ playback: NotchPlayback, artwork: CGFloat) -> some View {
        VStack(spacing: 0) {
            cover(size: artwork, playback: playback)
                .padding(.bottom, 14)
            Text(playback.track.title ?? text.mediaNowPlaying)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
            if let artist = playback.track.artist ?? playback.track.album {
                Text(artist)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            NotchMusicTimeline(playback: playback, service: music, tint: accent)
                .padding(.top, 16)
            transport(playback)
        }
        .pane()
    }

    /// A short display lays the cover beside the title, as the island's own
    /// player does.
    private func compact(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                cover(size: 52, playback: playback)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: 16, weight: .bold))
                    if let artist = playback.track.artist ?? playback.track.album {
                        Text(artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            NotchMusicTimeline(playback: playback, service: music, tint: accent)
                .padding(.top, 12)
            transport(playback)
        }
        .pane()
    }

    private func cover(size: CGFloat, playback: NotchPlayback) -> some View {
        NotchArtwork(image: music.artwork, size: size)
            .shadow(color: (music.artworkTint?.color ?? .black).opacity(0.5), radius: size * 0.28, y: size * 0.1)
            .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.92)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: playback.isPlaying)
    }

    /// The player's own buttons, never a permission prompt: a request made
    /// here would open behind the lock screen, where no one can answer it.
    private func transport(_ playback: NotchPlayback) -> some View {
        HStack(spacing: 46) {
            if !music.lacksTrackSkipping(.previous) {
                button("backward.fill", size: 22, title: text.mediaPrevious, command: .previous, playback: playback)
            }
            button(playback.isPlaying ? "pause.fill" : "play.fill", size: 30, title: text.mediaPlayPause,
                   command: .toggle, playback: playback)
            if !music.lacksTrackSkipping(.next) {
                button("forward.fill", size: 22, title: text.mediaNext, command: .next, playback: playback)
            }
        }
        .frame(height: 46)
    }

    private func button(_ symbol: String, size: CGFloat, title: String, command: NotchMusicService.Command,
                        playback: NotchPlayback) -> some View {
        Button { music.send(command, context: playback.commandContext) } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: symbol)
                .frame(width: 48, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .disabled(!music.canPerform(command))
        .accessibilityLabel(title)
    }
}

private extension View {
    /// The player's pane, as wide as the timeline needs and no wider.
    func pane() -> some View {
        foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(width: NotchLockScreenLayout.paneWidth)
            .modifier(NotchLockScreenGlass(cornerRadius: 34))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The activities as one line under the clock, where a phone keeps the
/// widgets of its lock screen: a mark and a reading each, with no card. A
/// line too long for the display gives up its last activities first.
struct NotchLockScreenActivities: View {
    @ObservedObject var model: NotchLockScreenModel
    let size: CGSize
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let items = available(at: context.date)
            ViewThatFits(in: .horizontal) {
                line(items, at: context.date)
                line(Array(items.prefix(3)), at: context.date)
                line(Array(items.prefix(2)), at: context.date)
                line(Array(items.prefix(1)), at: context.date)
            }
            .frame(width: size.width, height: size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: items)
        }
        .allowsHitTesting(false)
    }

    private func available(at date: Date) -> [NotchLockScreenActivity] {
        let gates = model.gates
        return NotchLockScreenSupport.activities(
            timer: gates.timer && timer.session.hasSession,
            calendar: calendar.countdown.map {
                ($0.ongoing ? gates.timeLeft : gates.countdown || calendar.isChosen($0.event)) && $0.isShown(at: date)
            } == true,
            agents: gates.agents && !usage.snapshot.live.isEmpty,
            downloads: gates.downloads && downloads.items.contains { $0.active && !$0.completed })
    }

    private func line(_ items: [NotchLockScreenActivity], at date: Date) -> some View {
        HStack(spacing: 26) {
            ForEach(items) { item in
                entry(item, at: date)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .fixedSize()
        .legibleOnWallpaper()
    }

    @ViewBuilder private func entry(_ item: NotchLockScreenActivity, at date: Date) -> some View {
        switch item {
        case .timer:
            let session = timer.session
            let now = timer.now
            let finished = NotchLockScreenSupport.timerFinished(session, at: now)
            let text = FeatureStrings.notchActivities(l10n.language)
            let clock = finished ? text.finished : NotchTimerSupport.clockText(for: session, at: now)
            HStack(spacing: 7) {
                Image(systemName: finished ? "checkmark.circle.fill" : session.isPaused ? "pause.circle.fill"
                      : session.countsUp ? "stopwatch.fill" : "timer")
                    .foregroundStyle(.orange)
                Text(session.mode == .pomodoro && !finished ? text.phase(session.phase) + " " + clock : clock)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text.phase(session.phase))
            .accessibilityValue(clock)
        case .calendar:
            if let countdown = calendar.countdown {
                let text = FeatureStrings.notchCalendar(l10n.language)
                HStack(spacing: 7) {
                    Image(systemName: "calendar").foregroundStyle(countdown.event.color.color)
                    Text(NotchCalendarStrip.displayTitle(countdown.event, untitled: text.untitled))
                        .frame(maxWidth: 240, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NotchCalendarSupport.countdownText(until: countdown.target, now: date))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(countdown.ongoing ? text.ongoing : text.next)
            }
        case .agents:
            let working = AgentProvider.allCases.filter { provider in usage.snapshot.live.contains { $0.provider == provider } }
            let reading = NotchAgentSupport.stripReading(usage.snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                                         display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                                         focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: date)
            // The agents and their reading only: a project's name stays off
            // a screen anyone can walk up to.
            HStack(spacing: 7) {
                HStack(spacing: 1) {
                    ForEach(working) { NotchAgentGlyph(provider: $0, size: 13) }
                }
                Text(working.map(\.displayName).joined(separator: " · ") + " " + reading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(working.map(\.displayName).joined(separator: ", ") + ", "
                                + FeatureStrings.notchLockScreen(l10n.language).working)
            .accessibilityValue(reading)
        case .downloads:
            // Progress without the file's name, which stays off the lock screen.
            let fraction = downloads.items.first(where: { $0.active && !$0.completed })?.fraction
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                if let fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                } else {
                    Text(FeatureStrings.notchFiles(l10n.language).inProgress)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private extension View {
    /// White type over any wallpaper, the way the lock screen's own clock
    /// stays readable over a bright photo.
    func legibleOnWallpaper() -> some View {
        shadow(color: .black.opacity(0.3), radius: 8, y: 1)
    }
}
