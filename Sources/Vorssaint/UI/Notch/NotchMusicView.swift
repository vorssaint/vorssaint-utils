// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchMusicView: View {
    var compact = true
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = false
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = false
    @State private var extra: MusicExtra?
    private enum MusicExtra { case lyrics, queue }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    /// The cover's own colour, used for its halo and for the moving parts that
    /// belong to this track. Neutral covers keep the panel white.
    private var accent: Color { service.artworkTint?.color ?? .white }
    private var halo: Color { service.artworkTint?.color ?? .clear }

    var body: some View {
        VStack(spacing: 12) {
            if let playback = service.playback {
                ViewThatFits(in: .vertical) {
                    musicContent(playback).fixedSize(horizontal: false, vertical: true)
                    ScrollView { musicContent(playback).fixedSize(horizontal: false, vertical: true) }
                        .scrollIndicators(.automatic)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if !service.awaitingPlayback {
                HStack(spacing: 20) {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text.mediaNothingPlaying).font(.system(size: 17, weight: .semibold))
                        Text(FeatureStrings.notch(l10n.language).musicHint)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 84)
                .accessibilityElement(children: .combine)
            }
            if AppFeature.mixer.isAvailable { NotchAudioControls(inline: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { syncExtras(); service.refreshAutomation() }
        .onChange(of: extra) { syncExtras() }
        .onChange(of: service.playback.map(NotchMusicIdentity.init)) { syncExtras() }
        .onChange(of: features.revision) { syncExtras() }
        .onChange(of: lyricsEnabled) { syncExtras() }
        .onChange(of: queueEnabled) { syncExtras() }
        .onDisappear {
            NotchService.shared.setMusicDetailsVisible(false)
            NotchLyricsService.shared.hide()
            service.setQueueVisible(false)
        }
    }

    private func syncExtras() {
        let showingLyrics = extra == .lyrics && lyricsEnabled && AppFeature.notchLyrics.isAvailable
        let showingQueue = extra == .queue && queueEnabled && AppFeature.notchQueue.isAvailable
        NotchService.shared.setMusicDetailsVisible(service.playback != nil && (showingLyrics || showingQueue))
        NotchLyricsService.shared.update(playback: service.playback, visible: extra == .lyrics)
        service.setQueueVisible(extra == .queue)
    }

    private func musicContent(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 12) {
            player(playback)
            if (lyricsEnabled && AppFeature.notchLyrics.isAvailable) || (queueEnabled && AppFeature.notchQueue.isAvailable) {
                HStack(spacing: 8) {
                    if lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                        extraButton(.lyrics, title: FeatureStrings.notchMusicExtras(l10n.language).lyrics, symbol: "quote.bubble")
                    }
                    if queueEnabled, AppFeature.notchQueue.isAvailable {
                        extraButton(.queue, title: FeatureStrings.notchMusicExtras(l10n.language).queue, symbol: "list.bullet")
                    }
                    Spacer(minLength: 0)
                }
                if extra == .lyrics, lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                    NotchLyricsView(playback: playback)
                } else if extra == .queue, queueEnabled, AppFeature.notchQueue.isAvailable {
                    NotchQueueView(playback: playback)
                }
            }
        }
    }

    private func extraButton(_ target: MusicExtra, title: String, symbol: String) -> some View {
        Button { extra = extra == target ? nil : target } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 7)
                .background(.white.opacity(extra == target ? 0.14 : 0.05), in: Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 16))
        .accessibilityAddTraits(extra == target ? [.isSelected] : [])
    }

    private func player(_ playback: NotchPlayback) -> some View {
        HStack(spacing: compact ? 18 : 24) {
            Button { RadialNowPlayingApplication.open(playback.track) } label: {
                NotchArtwork(image: service.artwork, size: compact ? 112 : 140)
                    .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.94)
                    .shadow(color: halo.opacity(0.42), radius: 20, y: 7)
                    .shadow(color: halo.opacity(0.2), radius: 42, y: 14)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playback.isPlaying)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: halo)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 24))
            .help(text.mediaNowPlaying)
            .accessibilityLabel(text.mediaNowPlaying)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(playback.track.title ?? text.mediaNowPlaying)
                            .font(.system(size: compact ? 18 : 21, weight: .semibold))
                            .lineLimit(2).help(playback.track.title ?? text.mediaNowPlaying)
                        Spacer(minLength: 0)
                        if playback.isPlaying {
                            NotchLiveEqualizerBars(bars: 3, barWidth: 2.5, height: 12, tint: accent)
                                .transition(.opacity)
                        }
                    }
                    Text(service.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                         : playback.track.artist ?? playback.track.album ?? text.mediaNowPlaying)
                        .font(.system(size: 13))
                        .foregroundStyle(service.commandFailed ? .orange : .secondary)
                        .lineLimit(1)
                }
                NotchMusicTimeline(playback: playback, service: service, tint: accent)
                NotchMusicTransport(playback: playback).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 164)
    }
}

private struct NotchMusicTransport: View {
    let playback: NotchPlayback
    // Automation discovery and consent finish after the first render while the
    // track stays the same, so this row must observe the service itself.
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        if !playback.canSendCommandsDirectly, service.automationAvailability?.access != .granted {
            HStack(spacing: 10) {
                if service.automationAvailability?.access == .consent {
                    Button(FeatureStrings.notchMusicExtras(l10n.language).allowPlayback) { service.requestAutomationAccess() }
                        .disabled(service.requestingAutomation)
                    if service.requestingAutomation { ProgressView().controlSize(.small) }
                } else if service.automationAvailability?.access == .denied {
                    Button(l10n.s.permissionOpenSettings) { Permissions.shared.openAutomationSettings() }
                    Button { service.refreshAutomation() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(FeatureStrings.notchMusicExtras(l10n.language).refresh)
                } else {
                    Button(FeatureStrings.notchMusicExtras(l10n.language).openPlayer) { RadialNowPlayingApplication.open(playback.track) }
                }
            }
            .buttonStyle(.borderless).font(.caption).frame(height: 44)
        } else {
            transportButtons
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 22) {
            playbackButton("backward.end.fill", title: text.mediaPrevious, command: .previous)
            Button { service.send(.toggle, context: playback.commandContext) } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: playback.isPlaying)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 20))
            .disabled(!service.canPerform(.toggle))
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(text.mediaPlayPause)
            .help(text.mediaPlayPause)
            playbackButton("forward.end.fill", title: text.mediaNext, command: .next)
        }
        .frame(height: 44)
    }

    private func playbackButton(_ symbol: String, title: String, command: NotchMusicService.Command) -> some View {
        Button { service.send(command, context: playback.commandContext) } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(NotchButtonStyle())
        .disabled(!service.canPerform(command))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct NotchMusicTimeline: View {
    let playback: NotchPlayback
    @ObservedObject var service: NotchMusicService
    var tint: Color = .white
    @ObservedObject private var l10n = L10n.shared
    @State private var scrubPosition: Double?
    @State private var scrubTrack: RadialNowPlayingSnapshot?
    @State private var scrubContext: NotchPlaybackContext?
    @State private var pendingSeek: UUID?

    var body: some View {
        if playback.duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { context in
                let position = scrubPosition ?? playback.position(at: context.date)
                VStack(spacing: 3) {
                    if service.canSeek {
                        NotchLevelSlider(
                            value: Binding(get: { position }, set: {
                                if scrubTrack == nil {
                                    scrubTrack = playback.track
                                    scrubContext = playback.commandContext
                                }
                                scrubPosition = $0
                            }),
                            label: FeatureStrings.notch(l10n.language).playbackPosition,
                            range: 0...playback.duration,
                            tint: tint,
                            valueLabel: timestamp(position),
                            onEditingChanged: { editing in
                                if editing {
                                    pendingSeek = nil
                                } else if let scrubPosition, let scrubTrack {
                                    service.seek(to: scrubPosition, in: scrubTrack, context: scrubContext)
                                    pendingSeek = UUID()
                                }
                            })
                            .frame(height: 10)
                            .disabled(service.commandPending)
                    } else {
                        NotchMeter(value: position / playback.duration, height: 6, tint: tint)
                    }
                    HStack {
                        Text(timestamp(position))
                        Spacer()
                        Text("−" + timestamp(playback.duration - position))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 30)
            .onChange(of: playback.track) { clearScrub() }
            .onChange(of: playback.commandContext) { clearScrub() }
            .onChange(of: playback.sampledAt) {
                if pendingSeek != nil, let scrubPosition,
                   abs(playback.position(at: Date()) - scrubPosition) <= 2 { clearScrub() }
            }
            .task(id: pendingSeek) {
                guard pendingSeek != nil else { return }
                // Keep the released thumb still while the player responds,
                // but always return to observed playback if it ignores seeking.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                clearScrub()
            }
        }
    }

    private func clearScrub() {
        pendingSeek = nil
        scrubPosition = nil
        scrubTrack = nil
        scrubContext = nil
    }

    private func timestamp(_ interval: TimeInterval) -> String {
        let seconds = Int(min(604_800, max(0, interval)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The home surface shares playback actions without opening lyrics or queue readers.
struct NotchMusicControlsView: View {
    @ObservedObject var notch: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        HStack(spacing: 14) {
            Button { notch.select(.music) } label: {
                NotchArtwork(image: music.artwork, size: 64)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 16))
            .accessibilityLabel(text.mediaNowPlaying)
            .help(text.mediaNowPlaying)
            VStack(alignment: .leading, spacing: 6) {
                Button { notch.select(.music) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(music.playback?.track.title ?? (music.awaitingPlayback ? text.mediaNowPlaying : text.mediaNothingPlaying))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(music.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                             : music.playback?.track.artist ?? music.playback?.track.album
                                ?? (music.awaitingPlayback ? "" : FeatureStrings.notch(l10n.language).musicHint))
                            .font(.system(size: 11))
                            .foregroundStyle(music.commandFailed ? .orange : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let playback = music.playback {
                    NotchMusicTransport(playback: playback).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: NotchLayout.musicControlHeight)
        .modifier(NotchControlSurface(cornerRadius: 18))
        .onAppear { music.refreshAutomation() }
    }
}
