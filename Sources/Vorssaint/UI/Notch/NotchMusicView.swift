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
    @ObservedObject private var shuffle = NotchShuffleService.shared
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = true
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = true
    @State private var extra: MusicExtra?
    private enum MusicExtra { case lyrics, queue }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.notchBand) private var band
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    /// The cover's own colour, used for the moving parts that belong to this
    /// track. Neutral covers keep them white.
    private var accent: Color { service.artworkTint?.color ?? .white }
    private var showsLyrics: Bool { lyricsEnabled && AppFeature.notchLyrics.isAvailable }
    private var showsQueue: Bool { queueEnabled && AppFeature.notchQueue.isAvailable }
    private var openExtra: MusicExtra? {
        guard service.playback != nil else { return nil }
        switch extra {
        case .lyrics: return showsLyrics ? .lyrics : nil
        case .queue: return showsQueue ? .queue : nil
        case nil: return nil
        }
    }
    /// The page starts at the top of the row beside the camera, where the
    /// cover tucks in beside it; without one the cover leads the page.
    private var bandHeight: CGFloat { band.besideCamera ? band.height : 0 }

    var body: some View {
        // A custom size can be too short to hold both, and the player yields
        // there; elsewhere the island grows by the extra and the player keeps
        // its height. That height comes from the geometry, not from this page,
        // which is still the idle page when music starts with lyrics chosen.
        let geometry = NotchService.shared.geometry
        let split = NotchLayout.musicSplit(
            height: size.height, extras: extrasHeight,
            resting: NotchLayout.musicPlayerHeight(band: bandHeight, playing: service.playback != nil),
            keepsPlayer: !preview && geometry.layout != .custom, extraOpen: openExtra != nil)
        // With the player gone the list starts below the camera's row, which
        // keeps its toggles; without that row they come back in one of their
        // own above the list, to close it.
        let reserve = split.showsPlayer ? 0
            : band.besideCamera ? bandHeight + NotchLayout.spacing : 28 + NotchLayout.rowSpacing
        VStack(spacing: NotchLayout.rowSpacing) {
            if split.showsPlayer {
                if let playback = service.playback {
                    player(playback)
                } else if !service.awaitingPlayback {
                    idle
                } else {
                    Color.clear.frame(height: split.player)
                }
            } else if band.besideCamera {
                Color.clear.frame(height: reserve - NotchLayout.rowSpacing)
            } else {
                HStack(spacing: 6) { Spacer(minLength: 0); extraButtons }.frame(height: 28)
            }
            if let openExtra, let playback = service.playback {
                Group {
                    switch openExtra {
                    case .lyrics: NotchLyricsView(playback: playback)
                    case .queue: NotchQueueView(playback: playback)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: max(0, min(split.extra, size.height - reserve)), alignment: .top)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Beside the camera the row holds the song's extras, across from the cover.
        .notchBand(trailing: {
            if band.besideCamera, service.playback != nil { extraButtons }
        })
        .onAppear {
            // A preview in Settings leaves the island's size and extras alone.
            guard !preview else { return }
            syncExtras()
            service.refreshAutomation()
            shuffle.refresh(for: service.playback)
        }
        .onChange(of: extra) { syncExtras() }
        .onChange(of: service.playback.map(NotchMusicIdentity.init)) {
            syncExtras()
            if !preview { shuffle.refresh(for: service.playback) }
        }
        // Shuffle and the playback buttons share one consent, so a grant
        // through the playback buttons also shows on shuffle.
        .onChange(of: service.automationAvailability?.access) { old, new in
            if !preview, old != nil, new != nil { shuffle.refresh(for: service.playback) }
        }
        .onChange(of: features.revision) { syncExtras() }
        .onChange(of: lyricsEnabled) { syncExtras() }
        .onChange(of: queueEnabled) { syncExtras() }
        .onDisappear {
            guard !preview else { return }
            NotchService.shared.setMusicDetailsVisible(false)
            NotchService.shared.setPageLayer(.music, close: nil)
            NotchLyricsService.shared.hide()
            service.setQueueVisible(false)
            shuffle.stop()
        }
    }

    private func syncExtras() {
        guard !preview else { return }
        NotchService.shared.setMusicDetailsVisible(openExtra != nil)
        // Escape closes lyrics or the queue before the island.
        NotchService.shared.setPageLayer(.music, close: openExtra == nil ? nil : { extra = nil })
        NotchLyricsService.shared.update(playback: service.playback, visible: extra == .lyrics)
        service.setQueueVisible(extra == .queue)
    }

    /// The cover and what goes beside it. Beside a camera the cover reaches
    /// up into the row and the song sits below the camera, level with the
    /// cover's foot; without one the song is centred on the cover.
    /// The cover and what goes beside it: the song level with the cover's
    /// foot, below the camera where the cover reaches up beside it, and the
    /// bars at the far end, level with the cover's middle. Without a camera
    /// row the song's toggles take the corner above the bars.
    private func head<Artwork: View, Titles: View, Accessory: View, Corner: View>(
        corner showsCorner: Bool = false,
        @ViewBuilder artwork: () -> Artwork, @ViewBuilder titles: () -> Titles,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder corner: () -> Corner = { EmptyView() }) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            artwork()
            titles()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: NotchLayout.musicTitleHeight)
            VStack(alignment: .trailing, spacing: 0) {
                if showsCorner {
                    HStack(spacing: 6) { corner() }.frame(height: 28)
                }
                HStack(spacing: 8) { accessory() }.frame(maxHeight: .infinity)
            }
            .frame(height: NotchLayout.musicArtworkSize)
        }
        .frame(height: NotchLayout.musicHeadHeight(band: bandHeight), alignment: .bottom)
    }

    private var idle: some View {
        let player = preview ? nil : NotchPreferredPlayer.current()
        let opens = player != nil
        let openTitle = player.map { NotchPreferredPlayer.openTitle(for: $0) } ?? ""
        return VStack(spacing: NotchLayout.musicHeadSpacing) {
            head {
                // With a music app to open, the cover and the buttons below open it.
                Button { NotchPreferredPlayer.open() } label: {
                    NotchArtwork(image: nil, size: NotchLayout.musicArtworkSize)
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.musicArtworkSize * 0.19))
                .disabled(!opens)
                .help(openTitle)
                .accessibilityLabel(opens ? openTitle : text.mediaNothingPlaying)
            } titles: {
                VStack(alignment: .leading, spacing: 2) {
                    if !service.sources.isEmpty || !service.sourceIsAutomatic {
                        sourcePicker(nil)
                    } else {
                        Text(text.mediaNothingPlaying).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    // Where the song's artist goes: which app the buttons open.
                    if opens {
                        Text(openTitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } accessory: {
                EmptyView()
            }
            Group {
                if opens {
                    transportRow(leading: { EmptyView() }) { slot in
                        NotchMusicIdleTransport(openTitle: openTitle, slot: slot)
                    }
                } else {
                    Text(FeatureStrings.notch(l10n.language).musicHint)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: NotchLayout.musicTransportHeight)
            .padding(.bottom, NotchLayout.musicBottomRoom)
        }
        .accessibilityElement(children: .contain)
    }

    /// Lyrics and the queue are toggles, named by their glyphs as a player's own are.
    @ViewBuilder private var extraButtons: some View {
        if showsLyrics {
            extraButton(.lyrics, title: FeatureStrings.notchMusicExtras(l10n.language).lyrics, symbol: "quote.bubble")
        }
        if showsQueue {
            extraButton(.queue, title: FeatureStrings.notchMusicExtras(l10n.language).queue, symbol: "list.bullet")
        }
    }

    private func extraButton(_ target: MusicExtra, title: String, symbol: String) -> some View {
        NotchIconButton(symbol: symbol, title: title, selected: extra == target) {
            extra = extra == target ? nil : target
        }
    }

    /// The player's own shuffle switch. A player not yet allowed to be
    /// controlled asks for that first, as the playback buttons do.
    private var shuffleButton: some View {
        let strings = FeatureStrings.notchMusicExtras(l10n.language)
        let consent = shuffle.availability?.access == .consent
        return NotchMusicSideButton(symbol: "shuffle", title: strings.shuffle, hint: consent ? strings.allowPlayback : nil,
                                    active: shuffle.enabled == true, tint: accent) { shuffle.toggle() }
            .disabled(shuffle.requestingAccess || !shuffle.allowed)
    }

    /// One row of five equal places across the island, the transport in the
    /// middle three: shuffle before it and the output after it, each place
    /// kept when its button is not offered so play stays in the middle.
    private func transportRow<Leading: View, Middle: View>(
        @ViewBuilder leading: () -> Leading, @ViewBuilder middle: (CGFloat) -> Middle) -> some View {
        let slot = size.width / 5
        // An empty place keeps its width: a missing button must not pull the
        // transport off the island's middle.
        return HStack(spacing: 0) {
            Color.clear.frame(width: slot).overlay { leading() }
            middle(slot).frame(width: slot * 3)
            Color.clear.frame(width: slot).overlay {
                if AppFeature.mixer.isAvailable { NotchMusicOutputButton() }
            }
        }
        .frame(height: NotchLayout.musicTransportHeight)
    }

    /// The cover and the song, the timeline across the island, then one row
    /// of buttons, as a phone's island lays out its player.
    private func player(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 0) {
            head(corner: !band.besideCamera && (showsLyrics || showsQueue)) {
                Button { RadialNowPlayingApplication.open(playback.track) } label: {
                    NotchArtwork(image: service.artwork, size: NotchLayout.musicArtworkSize)
                        .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.94)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playback.isPlaying)
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.musicArtworkSize * 0.19))
                .help(text.mediaNowPlaying)
                .accessibilityLabel(text.mediaNowPlaying)
            } titles: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .help(playback.track.title ?? text.mediaNowPlaying)
                    Text(service.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                         : playback.track.artist ?? playback.track.album ?? text.mediaNowPlaying)
                        .font(.system(size: 13))
                        .foregroundStyle(service.commandFailed ? .orange : .secondary)
                        .lineLimit(1)
                }
            } accessory: {
                // Which player the buttons drive, by its icon, when there is a choice.
                if service.sources.count > 1 || !service.sourceIsAutomatic {
                    sourceMenu(playback)
                }
                // Quiet beside the song, as the timeline's times are. The
                // bars rest flat while paused, so the title keeps its width.
                NotchLiveEqualizerBars(isPlaying: playback.isPlaying, bars: 4, barWidth: 2.5, height: 15,
                                       tint: .white.opacity(0.5))
            } corner: {
                extraButtons
            }
            NotchMusicTimeline(playback: playback, service: service, tint: accent, timesBeside: true)
                .padding(.top, NotchLayout.musicHeadSpacing)
            transportRow {
                if !preview && shuffle.isOffered { shuffleButton }
            } middle: { slot in
                NotchMusicTransport(playback: playback, slot: slot)
            }
            .padding(.top, NotchLayout.rowSpacing)
            Color.clear.frame(height: NotchLayout.musicBottomRoom)
        }
        .modifier(NotchMusicSwipeFeedback())
    }

    /// The player the buttons drive, as its icon, opening the same choice.
    private func sourceMenu(_ playback: NotchPlayback) -> some View {
        let extras = FeatureStrings.notchMusicExtras(l10n.language)
        let current = service.sources.first { $0.pid == playback.track.appPID }
        let app = playback.track.appPID.map { NotchPlayerApps.app(pid: $0, bundle: playback.track.appBundleIdentifier) }
        let name = current?.displayName ?? app?.name ?? playback.track.appBundleIdentifier ?? extras.playbackSource
        let icon = app?.icon
        var items = [NotchMenuItem(title: extras.automaticSource, checked: service.sourceIsAutomatic) { service.selectSource(nil) },
                     .separator]
        items += service.sources.map { source in
            let title = source.displayName ?? NotchPlayerApps.app(pid: source.pid, bundle: source.bundleIdentifier).name
                ?? source.bundleIdentifier
            // The chosen row, even while the automatic player fills its gap.
            return NotchMenuItem(title: title, checked: source.pid == service.selectedSourcePID) { service.selectSource(source.selection) }
        }
        return NotchMenuButton(title: extras.playbackSource, items: items, cornerRadius: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .padding(3)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help("\(extras.playbackSource): \(name)")
        .accessibilityValue([service.sourceIsAutomatic ? extras.automaticSource : nil, name].compactMap { $0 }.joined(separator: ", "))
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
                    // The chosen row, even while the automatic player fills its gap.
                    if source.pid == service.selectedSourcePID {
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
        .accessibilityValue([service.sourceIsAutomatic ? extras.automaticSource : nil,
                             playback == nil ? nil : name].compactMap { $0 }.joined(separator: ", "))
        .help(extras.playbackSource)
    }
}

/// A switch beside the transport, drawn like its buttons: a dimmed glyph
/// with no plate while it is off. On, it takes the timeline's colour on the
/// faint plate the island's other toggles use, which still reads where a
/// neutral cover leaves that colour white.
private struct NotchMusicSideButton: View {
    let symbol: String
    let title: String
    /// What a press does first when that is not switching, as asking for consent.
    var hint: String?
    let active: Bool
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let height: CGFloat = 44
    private let plate: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? tint : .white.opacity(isEnabled ? 0.55 : 0.3))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: plate, height: plate)
                .background(.white.opacity(active ? 0.12 : 0), in: Circle())
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: active)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .help(hint ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A player's name and icon, looked up once per running process: the player
/// redraws every second while a song plays. A process number another app
/// took since is looked up again.
private enum NotchPlayerApps {
    private static var known: [Int32: (bundle: String?, name: String?, icon: NSImage?)] = [:]

    static func app(pid: Int32, bundle: String?) -> (name: String?, icon: NSImage?) {
        if let entry = known[pid], bundle == nil || entry.bundle == bundle { return (entry.name, entry.icon) }
        let running = NSRunningApplication(processIdentifier: pid)
        if known.count >= 16 { known.removeAll() }
        known[pid] = (running?.bundleIdentifier ?? bundle, running?.localizedName, running?.icon)
        return (running?.localizedName, running?.icon)
    }
}

/// The output the island plays to, at the end of the player's row as on a
/// phone's island: its glyph opens the list of outputs, and the mixer.
private struct NotchMusicOutputButton: View {
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared

    private var deviceName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name ?? l10n.s.mixerSystemOutputTitle
    }

    /// The kind of output playing now: this Mac, headphones or a speaker.
    private var symbol: String {
        guard let device = mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID }) else { return "airplay.audio" }
        if device.isHeadphones { return NotchAccessorySupport.symbol(for: .audio, name: device.name) }
        switch device.priorityTier {
        case .builtIn: return PowerSampler.hasInternalBattery ? "laptopcomputer" : "desktopcomputer"
        case .hardware: return "hifispeaker"
        case .virtual: return "airplay.audio"
        }
    }

    var body: some View {
        NotchMenuButton(title: l10n.s.mixerSystemOutputTitle, items: items, cornerRadius: 22) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .help(mixer.outputSwitchError ?? deviceName)
        .accessibilityValue(deviceName)
    }

    private var items: [NotchMenuItem] { NotchAudioControls.outputItems(mixer: mixer, notch: notch, l10n: l10n) }
}

/// The transport as it looks with nothing playing. Every button opens the
/// music app, since there is no player to send a command to yet.
struct NotchMusicIdleTransport: View {
    var compact = false
    let openTitle: String
    /// The player's row gives each button an equal place across the island.
    var slot: CGFloat? = nil
    @ObservedObject private var l10n = L10n.shared
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var height: CGFloat { compact ? 36 : 44 }

    var body: some View {
        HStack(spacing: slot == nil ? (compact ? 12 : 18) : 0) {
            button("backward.fill", title: text.mediaPrevious, size: compact ? 16 : 19).frame(width: slot)
            button("play.fill", title: text.mediaPlayPause, size: compact ? 22 : slot == nil ? 26 : 28).frame(width: slot)
            button("forward.fill", title: text.mediaNext, size: compact ? 16 : 19).frame(width: slot)
        }
        .frame(height: height)
    }

    private func button(_ symbol: String, title: String, size: CGFloat) -> some View {
        Button { NotchPreferredPlayer.open() } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .accessibilityLabel(title)
        // VoiceOver says what the press does: it opens the app, not a skip.
        .accessibilityHint(openTitle)
        .help(openTitle)
    }
}

private struct NotchMusicTransport: View {
    let playback: NotchPlayback
    /// The home card and a short player use the smaller buttons.
    var compact = false
    /// The player's row gives each button an equal place across the island,
    /// and keeps the place of a skip the player does not offer.
    var slot: CGFloat? = nil
    // Automation discovery and consent finish after the first render while the
    // track stays the same, so this row must observe the service itself.
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    /// What a tap on play or pause asked for, shown at once while the player
    /// takes its round trip to say so. It gives way to the player's word.
    @State private var requestedPlaying: Bool?
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var height: CGFloat { compact ? 36 : 44 }
    private var showsPlaying: Bool { requestedPlaying ?? playback.isPlaying }

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

    /// The player's own glyphs, white on the island with no plate behind
    /// them, as on the lock screen. Play and pause stand out by size.
    private var transportButtons: some View {
        HStack(spacing: slot == nil ? (compact ? 12 : 18) : 0) {
            if !service.lacksTrackSkipping(.previous) {
                playbackButton("backward.fill", title: text.mediaPrevious, command: .previous).frame(width: slot)
            } else if let slot {
                Color.clear.frame(width: slot)
            }
            toggleButton.frame(width: slot)
            if !service.lacksTrackSkipping(.next) {
                playbackButton("forward.fill", title: text.mediaNext, command: .next).frame(width: slot)
            } else if let slot {
                Color.clear.frame(width: slot)
            }
        }
        .frame(height: height)
    }

    private var toggleButton: some View {
        Button {
            if service.canPerform(.toggle) {
                // Only a player the island writes to directly answers fast enough
                // to show its word early; a slower path waits for the player.
                let direct = playback.canSendCommandsDirectly
                if service.send(.toggle, context: playback.commandContext), direct { requestedPlaying = !showsPlaying }
            } else { service.requestAutomationAccess() }
        } label: {
            Image(systemName: showsPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 22 : slot == nil ? 26 : 28, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: showsPlaying)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        // A second tap before the player answers asks for the state after it,
        // so only the player reaching what was asked ends the early word.
        .onChange(of: playback.isPlaying) { if playback.isPlaying == requestedPlaying { requestedPlaying = nil } }
        .onChange(of: playback.track) { requestedPlaying = nil }
        // A player that never answers leaves the button as it was.
        .task(id: requestedPlaying) {
            guard requestedPlaying != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { requestedPlaying = nil }
        }
        .disabled(!service.canPerform(.toggle)
                  && (service.automationAvailability?.access != .consent || service.requestingAutomation))
        // A preview in Settings must not take Space from the window it sits in.
        .keyboardShortcut(preview ? nil : KeyboardShortcut(.space, modifiers: []))
        .accessibilityLabel(text.mediaPlayPause)
        .help(service.automationAvailability?.access == .consent
              ? FeatureStrings.notchMusicExtras(l10n.language).allowPlayback : text.mediaPlayPause)
    }

    private func playbackButton(_ symbol: String, title: String, command: NotchMusicService.Command) -> some View {
        Button { service.send(command, context: playback.commandContext) } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 16 : 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .disabled(!service.canPerform(command))
        .accessibilityLabel(title)
        .help(title)
    }
}

struct NotchMusicTimeline: View {
    let playback: NotchPlayback
    @ObservedObject var service: NotchMusicService
    var tint: Color = .white
    /// The island's player sets the times beside the bar, as a phone's
    /// island does, which leaves its short row room for the artist.
    var timesBeside = false
    @ObservedObject private var l10n = L10n.shared
    @State private var scrubPosition: Double?
    @State private var scrubTrack: RadialNowPlayingSnapshot?
    @State private var scrubContext: NotchPlaybackContext?
    @State private var pendingSeek: UUID?

    var body: some View {
        if playback.duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { context in
                let position = scrubPosition ?? playback.position(at: context.date)
                Group {
                    if timesBeside {
                        HStack(spacing: 8) {
                            // The song's longest reading holds each side's
                            // width, so the bar keeps its length as it plays.
                            ZStack(alignment: .leading) {
                                Text(timestamp(playback.duration)).hidden()
                                Text(timestamp(position))
                            }
                            bar(position)
                            ZStack(alignment: .trailing) {
                                Text("−" + timestamp(playback.duration)).hidden()
                                Text("−" + timestamp(playback.duration - position))
                            }
                        }
                    } else {
                        VStack(spacing: 3) {
                            bar(position)
                            HStack {
                                Text(timestamp(position))
                                Spacer()
                                Text("−" + timestamp(playback.duration - position))
                            }
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .frame(height: timesBeside ? NotchLayout.musicTimelineHeight : 30)
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

    @ViewBuilder private func bar(_ position: TimeInterval) -> some View {
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

/// The home surface shares playback actions without opening lyrics or queue
/// readers: the player's cover, the title and artist beside it, and the
/// transport at the end of their line, or under the title where a level card
/// shares the row.
struct NotchMusicControlsView: View {
    @ObservedObject var notch: NotchService
    var height: CGFloat = NotchLayout.cardHeight
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var isIdle: Bool {
        !preview && music.playback == nil && !music.awaitingPlayback
    }

    var body: some View {
        let player = isIdle ? NotchPreferredPlayer.current() : nil
        let idleOpens = player != nil
        let openTitle = player.map { NotchPreferredPlayer.openTitle(for: $0) } ?? ""
        HStack(spacing: 12) {
            // With nothing playing, the cover opens the music app instead.
            Button {
                if isIdle, NotchPreferredPlayer.open() { return }
                notch.select(.music)
            } label: {
                NotchArtwork(image: music.artwork, size: max(40, height - 24))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 16))
            .accessibilityLabel(idleOpens ? openTitle : text.mediaNowPlaying)
            .help(idleOpens ? openTitle : text.mediaNowPlaying)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    // Measured at its narrowest, so a long title truncates
                    // before the transport moves under it.
                    titles(artist: true)
                        .frame(minWidth: 80, idealWidth: 80, maxWidth: .infinity, alignment: .leading)
                    transport(idleOpens: idleOpens, openTitle: openTitle).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    // A shortened card keeps the title and the transport.
                    titles(artist: height >= 84)
                    transport(idleOpens: idleOpens, openTitle: openTitle).frame(maxWidth: .infinity)
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

    private func titles(artist: Bool) -> some View {
        Button { notch.select(.music) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(music.playback?.track.title ?? (music.awaitingPlayback ? text.mediaNowPlaying : text.mediaNothingPlaying))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if artist {
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
    }

    @ViewBuilder private func transport(idleOpens: Bool, openTitle: String) -> some View {
        if let playback = music.playback {
            NotchMusicTransport(playback: playback, compact: true)
        } else if idleOpens {
            NotchMusicIdleTransport(compact: true, openTitle: openTitle)
        }
    }
}
