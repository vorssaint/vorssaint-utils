// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchMusicView: View {
    let size: CGSize
    /// Room lyrics or the queue may add below the player.
    let extrasHeight: CGFloat
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = false
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = false
    @State private var extra: MusicExtra?
    private enum MusicExtra { case lyrics, queue }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    /// The cover's own colour, used for its halo and for the moving parts that
    /// belong to this track. Neutral covers keep the panel white.
    private var accent: Color { service.artworkTint?.color ?? .white }
    private var halo: Color { service.artworkTint?.color ?? .clear }
    private var showsLyrics: Bool { lyricsEnabled && AppFeature.notchLyrics.isAvailable }
    private var showsQueue: Bool { queueEnabled && AppFeature.notchQueue.isAvailable }
    private var hasControlsRow: Bool { AppFeature.mixer.isAvailable || showsLyrics || showsQueue }
    private var openExtra: MusicExtra? {
        guard service.playback != nil else { return nil }
        switch extra {
        case .lyrics: return showsLyrics ? .lyrics : nil
        case .queue: return showsQueue ? .queue : nil
        case nil: return nil
        }
    }

    var body: some View {
        let controlsRow = hasControlsRow ? NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing : 0
        let extraHeight = openExtra == nil ? 0 : min(extrasHeight, max(0, size.height - controlsRow))
        // The player yields to lyrics or the queue only where the island is
        // too short to hold both.
        let showsPlayer = openExtra == nil || size.height - controlsRow - extraHeight - NotchLayout.rowSpacing >= 88
        let playerHeight = max(0, size.height - controlsRow - (openExtra == nil ? 0 : extraHeight + NotchLayout.rowSpacing))
        VStack(spacing: NotchLayout.rowSpacing) {
            if showsPlayer {
                if let playback = service.playback {
                    player(playback, height: playerHeight)
                } else if !service.awaitingPlayback {
                    idle(height: playerHeight)
                } else {
                    Color.clear.frame(height: playerHeight)
                }
            }
            if let openExtra, let playback = service.playback {
                Group {
                    switch openExtra {
                    case .lyrics: NotchLyricsView(playback: playback, height: extraHeight)
                    case .queue: NotchQueueView(playback: playback, height: extraHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: extraHeight, alignment: .top)
                .clipped()
            }
            if hasControlsRow {
                HStack(spacing: 8) {
                    if AppFeature.mixer.isAvailable { NotchAudioControls(style: .inline) }
                    Spacer(minLength: 0)
                    if showsLyrics {
                        extraButton(.lyrics, title: FeatureStrings.notchMusicExtras(l10n.language).lyrics, symbol: "quote.bubble")
                    }
                    if showsQueue {
                        extraButton(.queue, title: FeatureStrings.notchMusicExtras(l10n.language).queue, symbol: "list.bullet")
                    }
                }
                .frame(height: NotchLayout.musicControlsRowHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            // A preview in Settings leaves the island's size and extras alone.
            guard !preview else { return }
            syncExtras()
            service.refreshAutomation()
        }
        .onChange(of: extra) { syncExtras() }
        .onChange(of: service.playback.map(NotchMusicIdentity.init)) { syncExtras() }
        .onChange(of: features.revision) { syncExtras() }
        .onChange(of: lyricsEnabled) { syncExtras() }
        .onChange(of: queueEnabled) { syncExtras() }
        .onDisappear {
            guard !preview else { return }
            NotchService.shared.setMusicDetailsVisible(false)
            NotchLyricsService.shared.hide()
            service.setQueueVisible(false)
        }
    }

    private func syncExtras() {
        guard !preview else { return }
        NotchService.shared.setMusicDetailsVisible(openExtra != nil)
        NotchLyricsService.shared.update(playback: service.playback, visible: extra == .lyrics)
        service.setQueueVisible(extra == .queue)
    }

    private func idle(height: CGFloat) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 76, height: 76)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                if !service.sources.isEmpty || !service.sourceIsAutomatic {
                    sourcePicker(nil)
                } else {
                    Text(text.mediaNothingPlaying).font(.system(size: 17, weight: .semibold))
                }
                Text(FeatureStrings.notch(l10n.language).musicHint)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
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

    /// The artwork fills the row; the details beside it drop their artist
    /// line, then the timeline, before they would overflow a short island.
    private func player(_ playback: NotchPlayback, height: CGFloat) -> some View {
        let roomy = height >= 140
        return HStack(spacing: roomy ? 20 : 16) {
            Button { RadialNowPlayingApplication.open(playback.track) } label: {
                NotchArtwork(image: service.artwork, size: height)
                    .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.94)
                    .shadow(color: halo.opacity(0.42), radius: 20, y: 7)
                    .shadow(color: halo.opacity(0.2), radius: 42, y: 14)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playback.isPlaying)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: halo)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 24))
            .help(text.mediaNowPlaying)
            .accessibilityLabel(text.mediaNowPlaying)
            ViewThatFits(in: .vertical) {
                if roomy { details(playback, titleLines: 2, artist: true, timeline: true, roomy: roomy) }
                details(playback, titleLines: 1, artist: true, timeline: true, roomy: roomy)
                details(playback, titleLines: 1, artist: false, timeline: true, roomy: roomy)
                details(playback, titleLines: 1, artist: false, timeline: false, roomy: roomy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }

    private func details(_ playback: NotchPlayback, titleLines: Int, artist: Bool, timeline: Bool, roomy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: roomy ? 20 : 16, weight: .semibold))
                        .lineLimit(titleLines).help(playback.track.title ?? text.mediaNowPlaying)
                    Spacer(minLength: 0)
                    if service.sources.count > 1 || !service.sourceIsAutomatic {
                        sourcePicker(playback)
                    }
                    if playback.isPlaying {
                        NotchLiveEqualizerBars(bars: 3, barWidth: 2.5, height: 12, tint: accent)
                            .transition(.opacity)
                    }
                }
                if artist {
                    Text(service.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                         : playback.track.artist ?? playback.track.album ?? text.mediaNowPlaying)
                        .font(.system(size: roomy ? 13 : 12))
                        .foregroundStyle(service.commandFailed ? .orange : .secondary)
                        .lineLimit(1)
                }
            }
            if timeline { NotchMusicTimeline(playback: playback, service: service, tint: accent) }
            NotchMusicTransport(playback: playback, compact: !roomy).frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sourcePicker(_ playback: NotchPlayback?) -> some View {
        let extras = FeatureStrings.notchMusicExtras(l10n.language)
        let pid = playback?.track.appPID
        let name = service.sources.first(where: { $0.pid == pid })?.displayName
            ?? pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? playback?.track.appBundleIdentifier ?? extras.playbackSource
        return Menu {
            Button { service.selectSource(nil) } label: {
                if service.sourceIsAutomatic { Label(extras.automaticSource, systemImage: "checkmark") }
                else { Text(extras.automaticSource) }
            }
            Divider()
            ForEach(service.sources, id: \.pid) { source in
                let title = source.displayName ?? NSRunningApplication(processIdentifier: source.pid)?.localizedName ?? source.bundleIdentifier
                Button { service.selectSource(source.selection) } label: {
                    if !service.sourceIsAutomatic, source.pid == pid {
                        Label(title, systemImage: "checkmark")
                    } else { Text(title) }
                }
            }
        } label: {
            Text(name).lineLimit(1).truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 110)
        .fixedSize()
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityLabel(extras.playbackSource)
        .help(extras.playbackSource)
    }
}

private struct NotchMusicTransport: View {
    let playback: NotchPlayback
    /// The home card and a short player use the smaller buttons.
    var compact = false
    // Automation discovery and consent finish after the first render while the
    // track stays the same, so this row must observe the service itself.
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var height: CGFloat { compact ? 36 : 44 }

    var body: some View {
        if !playback.canSendCommandsDirectly, service.automationAvailability?.access != .granted {
            HStack(spacing: 10) {
                toggleButton
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
            .buttonStyle(.borderless).font(.caption).frame(height: height)
        } else {
            transportButtons
        }
    }

    private var transportButtons: some View {
        HStack(spacing: compact ? 14 : 22) {
            playbackButton("backward.end.fill", title: text.mediaPrevious, command: .previous)
            toggleButton
            playbackButton("forward.end.fill", title: text.mediaNext, command: .next)
        }
        .frame(height: height)
    }

    private var toggleButton: some View {
        Button {
            if service.canPerform(.toggle) { service.send(.toggle, context: playback.commandContext) }
            else { service.requestAutomationAccess() }
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 14 : 17, weight: .semibold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: playback.isPlaying)
                .frame(width: height, height: height)
                .background(.white, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .disabled(!service.canPerform(.toggle)
                  && (service.automationAvailability?.access != .consent || service.requestingAutomation))
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(text.mediaPlayPause)
        .help(service.automationAvailability?.access == .consent
              ? FeatureStrings.notchMusicExtras(l10n.language).allowPlayback : text.mediaPlayPause)
    }

    private func playbackButton(_ symbol: String, title: String, command: NotchMusicService.Command) -> some View {
        Button { service.send(command, context: playback.commandContext) } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 15 : 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: compact ? 28 : 32, height: height - 8)
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
    var height: CGFloat = NotchLayout.cardHeight
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        HStack(spacing: 12) {
            Button { notch.select(.music) } label: {
                NotchArtwork(image: music.artwork, size: max(40, height - 24))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 16))
            .accessibilityLabel(text.mediaNowPlaying)
            .help(text.mediaNowPlaying)
            VStack(alignment: .leading, spacing: 4) {
                Button { notch.select(.music) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.playback?.track.title ?? (music.awaitingPlayback ? text.mediaNowPlaying : text.mediaNothingPlaying))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        // A shortened card keeps the title and the transport.
                        if height >= 84 {
                            Text(music.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                                 : music.playback?.track.artist ?? music.playback?.track.album
                                    ?? (music.awaitingPlayback ? "" : FeatureStrings.notch(l10n.language).musicHint))
                                .font(.system(size: 11))
                                .foregroundStyle(music.commandFailed ? .orange : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let playback = music.playback {
                    NotchMusicTransport(playback: playback, compact: true).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .modifier(NotchControlSurface(cornerRadius: 18))
        .onAppear { if !preview { music.refreshAutomation() } }
    }
}
