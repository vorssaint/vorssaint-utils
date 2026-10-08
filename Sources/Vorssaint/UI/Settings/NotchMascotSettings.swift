// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The companion's own page. It lives at the top in a slice of the island,
/// bigger than life, and acts out what it does on request; below are how it
/// looks, how it behaves and whether the Command Bar comes out with it.
struct NotchMascotSettings: View {
    /// Shown as a tab of the Dynamic Island page, which keeps its own margins.
    var embedded = false
    @ObservedObject private var l10n = L10n.shared
    /// Redraws when the island or the Command Bar is installed or removed.
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.notchEnabled) private var islandEnabled = false
    @AppStorage(DefaultsKey.notchSilhouette) private var silhouette = NotchSilhouette.capsule.rawValue
    @AppStorage(DefaultsKey.notchMascotEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchMascotVisits) private var visits = true
    @AppStorage(DefaultsKey.notchMascotReactions) private var reactions = true
    @AppStorage(DefaultsKey.notchMascotHidesWhenIdle) private var hidesWhenIdle = false
    @AppStorage(DefaultsKey.notchMascotStyle) private var style = NotchMascotStyle.minimal.rawValue
    @AppStorage(DefaultsKey.notchMascotShape) private var shape = NotchMascotShape.ball.rawValue
    @AppStorage(DefaultsKey.notchMascotPalette) private var palette = NotchMascotPalette.pearl.rawValue
    @AppStorage(DefaultsKey.notchMascotSide) private var side = NotchMascotSide.left.rawValue
    @AppStorage(DefaultsKey.notchMascotVisitFrequency) private var frequency = NotchMascotVisitFrequency.normal.rawValue
    @AppStorage(DefaultsKey.notchCommandBar) private var commandBar = true
    @AppStorage(DefaultsKey.notchCommandBarStyle) private var commandBarStyle = NotchCommandBarStyle.droplet.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: NotchMascotStrings { FeatureStrings.notchMascot(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    private var look: NotchMascotLook {
        NotchMascotLook(style: NotchMascotStyle(rawValue: style) ?? .minimal,
                        shape: NotchMascotShape(rawValue: shape) ?? .ball,
                        palette: NotchMascotPalette(rawValue: palette) ?? .pearl)
    }

    private var restingSide: NotchMascotSide { NotchMascotSide(rawValue: side) ?? .left }

    /// The island it lives in is installed and on.
    private var islandOn: Bool { features.isAvailable(.notch) && islandEnabled }

    /// It rests beside a camera, real or drawn, so the side it takes matters.
    /// A capsule holds it in the middle.
    private var restsBesideCamera: Bool {
        NotchSupport.hasNotchedDisplay || NotchSilhouette(rawValue: silhouette) == .notch
    }

    private var animation: Animation? { reduceMotion ? nil : .smooth(duration: 0.25) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !islandOn { islandNote }
                NotchMascotStageCard(look: look, side: restingSide, awake: enabled, canGreet: enabled && islandOn,
                                     visits: visits, reactions: reactions, hides: hidesWhenIdle, text: text,
                                     language: l10n.language)
                appearance
                behavior
                commandBarCard
            }
            .padding(embedded ? [.bottom] : .all, 22)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text.title).font(.title2.bold())
                Text(text.hint).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(text.title, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                .accessibilityLabel(text.title)
        }
    }

    /// With the island off or uninstalled the companion has nowhere to live,
    /// so the page says so and offers the way to bring the island back.
    private var islandNote: some View {
        let installed = features.isAvailable(.notch)
        let notch = FeatureStrings.notch(l10n.language)
        return HStack(spacing: 12) {
            Image(systemName: AppFeature.notch.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(text.livesInIsland)
                if !installed {
                    Text(AppFeature.notch.enableReason(l10n)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if installed {
                Button(notch.enable) {
                    islandEnabled = true
                    NotchService.shared.syncWithPreferences()
                }
            } else {
                Button(editor.openFeatures) { AppFeature.notch.showInFeatures() }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Appearance

    private var appearance: some View {
        SettingsCard(title: text.appearance) {
            SettingsRow(symbol: "paintpalette", title: text.style) { EmptyView() }
            HStack(spacing: 10) {
                ForEach(NotchMascotStyle.allCases) { item in
                    NotchMascotChoiceTile(title: text.style(item), selected: look.style == item) {
                        style = item.rawValue
                    } preview: {
                        NotchMascotView(look: NotchMascotLook(style: item, shape: look.shape, palette: look.palette),
                                        size: 30, idles: false)
                            .frame(width: 30, height: 30)
                            .frame(width: 64, height: 42)
                            .background(Color.black, in: Capsule())
                    }
                }
            }
            .padding(.leading, settingsRowTextInset)
            if look.style == .minimal {
                SettingsRow(symbol: "circle.square", title: text.shape) {
                    Text(text.shape(look.shape)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
                shapes
                    .transition(.opacity)
            }
            SettingsRow(symbol: "swatchpalette", title: text.color) {
                Text(text.palette(look.palette)).foregroundStyle(.secondary)
            }
            swatches
        }
        .animation(animation, value: look.style)
    }

    private var shapes: some View {
        HStack(spacing: 8) {
            ForEach(NotchMascotShape.allCases) { item in
                let selected = look.shape == item
                Button { shape = item.rawValue } label: {
                    NotchMascotView(look: NotchMascotLook(style: .minimal, shape: item, palette: look.palette),
                                    size: 24, idles: false)
                        .frame(width: 24, height: 24)
                        .frame(width: 58, height: 40)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(text.shape(item))
                .accessibilityLabel(text.shape(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
            }
        }
        .padding(.leading, settingsRowTextInset)
    }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(NotchMascotPalette.allCases) { item in
                let selected = look.palette == item
                Button { palette = item.rawValue } label: {
                    Circle()
                        .fill(LinearGradient(colors: [Color(cgColor: item.light.cgColor), Color(cgColor: item.shade.cgColor)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(text.palette(item))
                .accessibilityLabel(text.palette(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
            }
        }
        .padding(.leading, settingsRowTextInset)
    }

    // MARK: Behavior

    private var behavior: some View {
        SettingsCard(title: text.behavior) {
            if restsBesideCamera {
                SettingsRow(symbol: "arrow.left.and.right", title: text.side) { EmptyView() }
                HStack(spacing: 10) {
                    ForEach(NotchMascotSide.allCases) { item in
                        NotchMascotChoiceTile(title: text.side(item), selected: restingSide == item) {
                            side = item.rawValue
                        } preview: {
                            NotchMascotSideSample(look: look, side: item)
                        }
                    }
                }
                .padding(.leading, settingsRowTextInset)
            }
            switchRow("eye.slash", text.hidesWhenIdle, caption: text.hidesWhenIdleHint, isOn: $hidesWhenIdle)
            switchRow("figure.walk", text.visits, caption: text.visitsHint, isOn: $visits)
            if visits {
                SettingsChoiceRow(symbol: "clock", title: text.frequency, selection: $frequency) {
                    ForEach(NotchMascotVisitFrequency.allCases) { Text(text.frequency($0)).tag($0.rawValue) }
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
            }
            switchRow("theatermasks", text.reactions, caption: text.reactionsHint, isOn: $reactions)
        }
        .animation(animation, value: visits)
    }

    // MARK: Command Bar

    private var commandBarCard: some View {
        let available = features.isAvailable(.commandBar)
        let bar = FeatureStrings.commandBar(l10n.language)
        return SettingsCard(title: bar.pageTitle) {
            SettingsFeatureSwitchRow(symbol: "command", title: text.commandBar, caption: text.commandBarHint,
                                     isOn: $commandBar, feature: .commandBar)
            if available, commandBar {
                SettingsRow(symbol: "drop", title: text.opensAs) { EmptyView() }
                    .transition(.opacity)
                HStack(spacing: 10) {
                    ForEach(NotchCommandBarStyle.allCases) { item in
                        NotchMascotChoiceTile(title: text.commandBarStyle(item),
                                              selected: (NotchCommandBarStyle(rawValue: commandBarStyle) ?? .droplet) == item) {
                            commandBarStyle = item.rawValue
                        } preview: {
                            NotchCommandBarStyleSample(style: item, look: look)
                        }
                    }
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
            }
        }
        .animation(animation, value: available && commandBar)
    }

    /// An option with its icon, a line about it and a switch, like the rest of Settings.
    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

// MARK: - Stage

/// The companion in a slice of the island as it rests there, bigger: it
/// blinks, its eyes follow the pointer, a moment's rest of the pointer on it
/// pets it, and it acts out a visit or a moment on request. Switched off,
/// it sleeps.
private struct NotchMascotStageCard: View {
    let look: NotchMascotLook
    let side: NotchMascotSide
    let awake: Bool
    /// Whether it can say hello in the island itself.
    let canGreet: Bool
    /// Turned on, each plays at once what it brings.
    let visits: Bool
    let reactions: Bool
    let hides: Bool
    let text: NotchMascotStrings
    let language: AppLanguage
    @State private var visit: NotchMascotVisit?
    @State private var reaction: NotchMascotReactionEvent?
    @State private var playing: NotchMascotMoment?
    @State private var playingWork: DispatchWorkItem?
    @State private var lookWork: DispatchWorkItem?
    /// The next moment a click on the companion acts out.
    @State private var nextMoment = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let reactions = NotchMascotMoment.allCases.filter { $0.reaction != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                NotchMascotStage(look: look, side: side, awake: awake, visit: visit, reaction: reaction,
                                 caption: playing.map { (text.moment($0, language: language), $0.symbol) },
                                 width: proxy.size.width)
                    .contentShape(Rectangle())
                    .onTapGesture { playNext() }
            }
            .frame(height: NotchMascotStage.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.preview)
            .accessibilityHint(awake ? text.previewHint : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { playNext() }
            HStack(alignment: .firstTextBaseline) {
                Text(text.momentsTitle).font(.headline)
                Spacer(minLength: 12)
                Button {
                    // Out of room in the island just now, it says hello here instead.
                    if !NotchService.shared.greetMascot() { play(.visit) }
                } label: {
                    Label(text.sayHi, systemImage: "hand.wave")
                }
                .controlSize(.small)
                .disabled(!canGreet)
                .help(text.sayHiHint)
            }
            FlowLayoutLite(spacing: 6) {
                ForEach(NotchMascotMoment.allCases) { moment in
                    NotchMascotMomentChip(title: text.moment(moment, language: language), symbol: moment.symbol,
                                          playing: playing == moment) { play(moment) }
                        .opacity(visit != nil && playing != moment ? 0.45 : 1)
                        .disabled(!awake)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: visit == nil)
            // Said here rather than as a tooltip, which came up over the
            // companion just as a resting pointer pets it.
            Label(text.previewHint + " " + text.petTip, systemImage: "hand.point.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Asleep while it is switched off, it answers none of this,
                // so the tip dims with the moments.
                .opacity(awake ? 1 : 0.45)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: awake) { _, awake in
            // A moment still playing ends; switched on, it wakes up with a
            // stretch, and off, it yawns and dozes off. Hidden a moment ago
            // to show how it hides, it is back in its place for that.
            playingWork?.cancel(); playingWork = nil
            playing = nil
            if visit?.kind == NotchMascotSupport.hideAway { visit = nil }
            react(awake ? .wakeUp : .yawn)
        }
        .onChange(of: side) { _, _ in
            // To the camera's other side: behind it, across and out, as in the island.
            guard awake, visit == nil else { return }
            startVisit(.cross, greeting: .wink)
        }
        .onChange(of: visits) { _, visits in
            // Its visits back on, it takes one right away.
            if visits { play(.visit) }
        }
        .onChange(of: reactions) { _, reactions in
            // Reacting again, it perks up.
            if reactions, awake, visit == nil { react(.perk) }
        }
        .onChange(of: hides) { _, hides in
            // Set to hide when idle, it shows how it goes into the island,
            // and a moment later comes back out, as the preview keeps it in sight.
            guard hides, awake, visit == nil else { return }
            playingWork?.cancel()
            playing = nil
            let away = NotchMascotVisit(id: UUID(), kind: NotchMascotSupport.hideAway, greeting: .idle,
                                        start: CACurrentMediaTime())
            visit = away
            let work = DispatchWorkItem {
                guard visit?.id == away.id else { return }
                startVisit(.arrive, greeting: .wink)
            }
            playingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + away.duration + 0.8, execute: work)
        }
        .onChange(of: look) { _, _ in
            // A new look, and it is glad of it, once the choosing settles.
            lookWork?.cancel()
            guard awake else { return }
            let work = DispatchWorkItem { if visit == nil { react(.celebrate) } }
            lookWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        .onDisappear {
            playingWork?.cancel()
            lookWork?.cancel()
            // Never left hidden for the next time the page shows.
            if visit?.kind == NotchMascotSupport.hideAway { visit = nil }
        }
    }

    private func playNext() {
        guard awake, visit == nil else { return }
        let moment = Self.reactions[nextMoment % Self.reactions.count]
        nextMoment += 1
        play(moment)
    }

    private func play(_ moment: NotchMascotMoment) {
        guard awake, visit == nil else { return }
        playingWork?.cancel()
        playing = moment
        let length: TimeInterval
        if let reaction = moment.reaction {
            react(reaction)
            length = reaction.length + 0.15
        } else {
            length = startVisit(.lap, greeting: .wink)
        }
        guard let followUp = moment.followUp else {
            let work = DispatchWorkItem { playing = nil }
            playingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: work)
            return
        }
        // The second beat, then the caption goes once it is over too.
        let work = DispatchWorkItem {
            guard playing == moment else { return }
            react(followUp)
            let done = DispatchWorkItem { playing = nil }
            playingWork = done
            DispatchQueue.main.asyncAfter(deadline: .now() + followUp.length + 0.15, execute: done)
        }
        playingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.2, execute: work)
    }

    private func react(_ reaction: NotchMascotReaction) {
        self.reaction = NotchMascotReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime())
    }

    /// Starts a stroll and clears it once it is over, returning how long it takes.
    @discardableResult
    private func startVisit(_ kind: NotchMascotVisit.Kind, greeting: NotchMascotMood) -> TimeInterval {
        let started = NotchMascotVisit(id: UUID(), kind: kind, greeting: greeting, start: CACurrentMediaTime())
        visit = started
        DispatchQueue.main.asyncAfter(deadline: .now() + started.duration) {
            if visit?.id == started.id { visit = nil }
        }
        return started.duration
    }
}

/// The slice of screen the stage draws: a menu bar with the island hanging
/// from it, the companion in its place beside the camera, or in a capsule's
/// middle, as the island on this Mac has it.
private struct NotchMascotStage: View {
    let look: NotchMascotLook
    let side: NotchMascotSide
    let awake: Bool
    let visit: NotchMascotVisit?
    let reaction: NotchMascotReactionEvent?
    /// The moment it acts out, named under the island while it plays.
    let caption: (title: String, symbol: String)?
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 104

    var body: some View {
        let model = NotchMascotStageModel(side: side)
        let scale = model.scale(toFit: width)
        let island = CGSize(width: model.strip.width * scale, height: model.strip.height * scale)
        let bar = model.menuBarHeight * scale
        let track = model.track.scaled(by: scale)
        let dark = colorScheme == .dark
        ZStack(alignment: .top) {
            // The desktop, washed with the accent color like a wallpaper,
            // and the menu bar across it, translucent as the real one.
            LinearGradient(colors: [Color.accentColor.opacity(dark ? 0.30 : 0.20),
                                    Color.accentColor.opacity(dark ? 0.08 : 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(dark ? Color.black.opacity(0.28) : Color.white.opacity(0.55))
                .frame(height: bar)
            menuBarItems(bar: bar, island: island.width)
            model.shape(height: island.height)
                .fill(.black)
                .frame(width: island.width, height: island.height)
                .overlay(alignment: .topLeading) {
                    if model.hasCamera, let camera = track.hidden {
                        NotchMascotLens(diameter: 6 * scale)
                            .position(x: (camera.lowerBound + camera.upperBound) / 2, y: island.height / 2)
                    }
                }
                .overlay(alignment: .top) {
                    NotchMascotTrackView(look: look, track: track, rests: true, visit: visit, mood: .idle,
                                         reaction: reaction, awake: awake)
                        .frame(width: track.width, height: track.height)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if !awake {
                        NotchMascotSleepZs(origin: CGPoint(x: track.rest, y: track.baseline - track.size * 0.05),
                                           size: track.size, toward: track.mirrored ? -1 : 1)
                            .transition(.opacity)
                    }
                }
                .clipShape(model.shape(height: island.height))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: awake)
            if let caption {
                Label(caption.title, systemImage: caption.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
                    .id(caption.title)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: caption?.title)
        .frame(width: width, height: Self.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }

    /// Menus on the left and status icons on the right, as far as they fit
    /// clear of the island.
    private func menuBarItems(bar: CGFloat, island: CGFloat) -> some View {
        let inset = bar * 0.42
        let room = (width - island) / 2 - inset * 2
        let menus: [CGFloat] = [0.55, 0.85, 0.7, 0.75].map { $0 * bar }
        let icon = bar * 0.3
        let gap = bar * 0.3
        let shownMenus = Self.fitting(menus, gap: gap, in: room)
        let shownIcons = Self.fitting(Array(repeating: icon, count: 4), gap: gap, in: room)
        return HStack(spacing: gap) {
            ForEach(Array(shownMenus.enumerated()), id: \.offset) { _, menu in
                Capsule().fill(.primary.opacity(0.2)).frame(width: menu, height: bar * 0.2)
            }
            Spacer(minLength: 0)
            ForEach(Array(shownIcons.enumerated()), id: \.offset) { _, size in
                Circle().fill(.primary.opacity(0.2)).frame(width: size, height: size)
            }
        }
        .padding(.horizontal, inset)
        .frame(height: bar)
        .accessibilityHidden(true)
    }

    /// The leading items that fit in `room` with `gap` between them.
    private static func fitting(_ items: [CGFloat], gap: CGFloat, in room: CGFloat) -> [CGFloat] {
        var used: CGFloat = 0
        var shown: [CGFloat] = []
        for item in items {
            let next = used + (shown.isEmpty ? 0 : gap) + item
            guard next <= room else { break }
            used = next
            shown.append(item)
        }
        return shown
    }
}

/// The island the stage draws, at its real size: the closed island at rest
/// with the companion, its wings beside the camera or a floating capsule,
/// taken from this Mac's island when it has one to go by.
struct NotchMascotStageModel {
    let strip: CGSize
    let menuBarHeight: CGFloat
    let floatingGap: CGFloat?
    let track: NotchMascotTrack
    /// A real camera sits in the middle, not a drawn cutout.
    let hasCamera: Bool

    init(side: NotchMascotSide, geometry live: NotchGeometry = NotchService.shared.geometry,
         islandRuns: Bool = NotchService.shared.running) {
        // An island that is not running has not measured its display.
        let usable = islandRuns && live.screen.width > 0 && live.stripHeight >= 16
        let geometry = usable ? live : Self.template
        floatingGap = geometry.floatingGap
        hasCamera = geometry.isNotched
        if geometry.floats {
            let size = geometry.restingSize(showsContent: false)
            strip = size
            menuBarHeight = max(geometry.menuBarHeight, size.height)
            track = NotchMascotSupport.track(stripWidth: size.width, stripHeight: geometry.stripHeight, wing: 0,
                                             cameraWidth: 0, floats: true, bodyHeight: geometry.stripBodyHeight)
        } else {
            // A crowded menu bar can leave the closed island no wings, but
            // the preview always shows where it would rest.
            let wing: CGFloat = 44
            strip = CGSize(width: geometry.cameraWidth + wing * 2, height: geometry.stripHeight)
            menuBarHeight = geometry.menuBarHeight
            track = NotchMascotSupport.track(stripWidth: strip.width, stripHeight: strip.height, wing: wing,
                                             cameraWidth: geometry.cameraWidth, floats: false,
                                             bodyHeight: geometry.stripBodyHeight, side: side)
        }
    }

    /// A MacBook's island, for a Mac whose island has not measured itself yet.
    static var template: NotchGeometry {
        NotchSupport.hasNotchedDisplay
            ? NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185,
                            menuBarHeight: 32)
            : NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                            menuBarHeight: 24, silhouette: .capsule)
    }

    /// As large as leaves the menu bar room on both sides, at most twice its size.
    func scale(toFit width: CGFloat) -> CGFloat {
        guard strip.width > 0, strip.height > 0 else { return 1 }
        let byWidth = width * 0.66 / strip.width
        let byHeight = (NotchMascotStage.height - 36) / menuBarHeight
        return max(1, min(2, byWidth, byHeight))
    }

    func shape(height: CGFloat) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height),
                   floatingGap: floatingGap.map { $0 * height / max(1, strip.height) })
    }
}

/// Asleep, little z's drift up from its head and fade. Each one rises on
/// its own share of the same beat, so they never bunch up; with Reduce
/// Motion two of them stay still.
private struct NotchMascotSleepZs: View {
    /// Where they start, in the island's points.
    let origin: CGPoint
    let size: CGFloat
    /// Toward the camera, where the island has black to spare.
    let toward: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settingsWindow = SettingsWindowVisibility.shared

    private static let period: TimeInterval = 2.7

    var body: some View {
        Group {
            if reduceMotion {
                ZStack(alignment: .topLeading) {
                    z(phase: 0.35)
                    z(phase: 0.7)
                }
            } else {
                // Drifting slowly, they need no more than 30 frames a second,
                // and none while Settings is closed or out of sight.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !settingsWindow.isVisible)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate / Self.period
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<3, id: \.self) { index in
                            z(phase: (time + Double(index) / 3).truncatingRemainder(dividingBy: 1))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One z, `phase` of the way through its rise.
    private func z(phase: Double) -> some View {
        let share = CGFloat(phase)
        return Text(verbatim: "z")
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .scaleEffect(0.5 + 0.6 * share)
            .opacity(0.8 * sin(Double.pi * phase))
            .position(x: origin.x + toward * size * (0.6 + 0.9 * share),
                      y: origin.y - size * 0.62 * share)
    }
}

/// The camera's lens, faint in the black, so the island reads as the one
/// around the camera.
private struct NotchMascotLens: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.085))
            Circle().fill(Color(red: 0.10, green: 0.11, blue: 0.19)).padding(diameter * 0.26)
            Circle().fill(Color.white.opacity(0.18)).frame(width: diameter * 0.14, height: diameter * 0.14)
                .offset(x: -diameter * 0.1, y: -diameter * 0.1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// One moment the stage can act out, named as the island names it.
private struct NotchMascotMomentChip: View {
    let title: String
    let symbol: String
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(playing ? Color.accentColor : .primary)
                .background(Capsule().fill(playing ? Color.accentColor.opacity(0.16)
                                           : Color.primary.opacity(hovering && isEnabled ? 0.11 : 0.06)))
                .overlay(Capsule().strokeBorder(playing ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: playing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(playing ? .isSelected : [])
    }
}

// MARK: - Tiles

/// A choice drawn as what it gives, with its name under it, like the size
/// and shape choices on the Dynamic Island page.
private struct NotchMascotChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(8)
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        // The button keeps its own element, so VoiceOver can press it.
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
    }
}

/// Black reads as the island's own color on a light page, and needs a faint
/// edge to stand off a dark one.
private extension Shape {
    func islandSample() -> some View {
        fill(.black).overlay(stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

/// A small island with the companion resting on one side of the camera.
private struct NotchMascotSideSample: View {
    let look: NotchMascotLook
    let side: NotchMascotSide

    var body: some View {
        let size = CGSize(width: 92, height: 20)
        let wing: CGFloat = 22
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height))
            .islandSample()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: side == .left ? .leading : .trailing) {
                NotchMascotView(look: look, size: 13, idles: false)
                    .frame(width: 13, height: 13)
                    .frame(width: wing, height: size.height)
                    .padding(side == .left ? .leading : .trailing, 4)
            }
            .frame(height: 30)
            .accessibilityHidden(true)
    }
}

/// How the Command Bar comes out: a drop falling from the island into a
/// bar below it, or the bar inside the opened island.
private struct NotchCommandBarStyleSample: View {
    let style: NotchCommandBarStyle
    let look: NotchMascotLook

    var body: some View {
        Group {
            switch style {
            case .droplet:
                VStack(spacing: 2) {
                    NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: 9))
                        .islandSample()
                        .frame(width: 46, height: 9)
                    Circle().islandSample().frame(width: 5, height: 5)
                    bar(width: 84, height: 18)
                }
            case .island:
                NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: 32))
                    .islandSample()
                    .frame(width: 92, height: 34)
                    .overlay(alignment: .bottom) {
                        field.padding(.bottom, 6)
                    }
            }
        }
        .frame(height: 38, alignment: .top)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .islandSample()
            .frame(width: width, height: height)
            .overlay { field }
    }

    /// The bar's field with the companion as its face.
    private var field: some View {
        HStack(spacing: 4) {
            NotchMascotView(look: look, size: 10, idles: false).frame(width: 10, height: 10)
            Capsule().fill(.white.opacity(0.28)).frame(width: 38, height: 3)
        }
        .frame(width: 68, alignment: .leading)
    }
}
