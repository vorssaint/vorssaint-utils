// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var headerHovered = false
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        surface
            // An activity arriving over the resting companion fades in as the
            // companion fades out, and one ending fades back into it, instead
            // of cutting from one to the other in a frame. A song leaving has its
            // own departure. A companion that stays to react is drawn over the
            // new strip where it stood, so the swap under it is left
            // unanimated: two of it crossfading in one place would dim it.
            .transaction(value: service.compactActivity) { transaction in
                guard !reduceMotion, !service.mascotLingers else { return }
                let arrives = service.compactActivity != nil && service.mascotJustRested
                let leaves = service.compactActivity == nil && service.mascotAtRest
                    && service.departingMusic == nil && service.lingeringMusic == nil
                guard arrives || leaves else { return }
                transaction.animation = .easeInOut(duration: NotchMascotMotion.restCrossfade)
            }
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .foregroundStyle(.white)
            // The window server leaves Liquid Glass out of its hit test, so a
            // click or a wheel over empty glass would reach the window behind:
            // the page stops scrolling between cards and the island loses
            // focus. A fill too faint to see keeps the surface in this window,
            // as the black backdrop does.
            .background(shape.offset(x: service.surfaceShift).fill(Color.black.opacity(0.01)))
            .contentShape(shape.offset(x: service.surfaceShift))
            // The backdrop is a separate, non-interactive hosting view. Claim
            // empty space here so clicks and wheel events stay in this window.
            .onTapGesture { }
            .onChange(of: reduceTransparency) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .onChange(of: contrast) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .environment(\.notchGlassSurface, usesGlassSurface)
            .tint(.white)
            .accessibilityIdentifier("notch.surface")
    }

    private var usesGlassSurface: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *), glass, !reduceTransparency {
            // Resting wings, compact activities and small status notices keep
            // blending into the physical camera cutout.
            return service.usesGlassSurface
        }
#endif
        return false
    }

    private var shape: NotchShape {
        NotchShape.island(height: service.surfaceSize.height, geometry: service.geometry)
    }

    @ViewBuilder private var surface: some View {
        if service.fullscreenCompact {
            Color.clear.accessibilityHidden(true)
        } else if let options = service.captureControls {
            if service.captureControlsCollapsed, floats {
                NotchCapsuleCaptureStrip(symbol: options.selectedTool.systemImageName, geometry: service.geometry,
                                         size: service.surfaceSize)
            } else if service.captureControlsCollapsed {
                HStack(spacing: 0) {
                    Image(systemName: options.selectedTool.systemImageName).frame(width: 28)
                    Color.clear.frame(width: service.geometry.cameraWidth)
                    Image(systemName: "chevron.down").frame(width: 28)
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            } else {
                NotchCaptureControlsView(options: options, service: service, layout: service.captureControlsLayout)
            }
        } else if service.expanded {
            if service.showingCommandBar {
                commandBarPage
            } else {
                expanded
                    // The companion beside the camera watches the pointer go
                    // over the island.
                    .onContinuousHover { phase in
                        guard service.mascotResidentShows else { return }
                        switch phase {
                        case .active: NotificationCenter.default.post(name: .notchMascotPointerMoved, object: nil)
                        case .ended: NotificationCenter.default.post(name: .notchMascotPointerLeft, object: nil)
                        }
                    }
                    .overlay(alignment: .top) { residentMascot }
            }
        } else if service.dragPlaceholder {
            Group {
                if service.mascotOn {
                    // The companion stands by the hint and watches the file come.
                    HStack(spacing: 8) {
                        NotchMascotView(look: NotchMascotSupport.look(), size: 20, followsDrag: true)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(text.dropHint)
                    }
                } else {
                    Label(text.dropHint, systemImage: "tray.and.arrow.down")
                }
            }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.24),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
                .padding(.top, service.geometry.safeContentTop)
        } else if let notice = service.notice ?? (service.peeking ? nil : service.departingNotice) {
            if service.noticeExpanded, let content = notice.notification {
                NotchNotificationPreviewView(notice: notice, content: content, service: service)
                    .padding(.horizontal, NotchLayout.horizontalInset)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, NotchLayout.bottomInset)
                    .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            } else {
                Button {
                    service.activateNotice(notice)
                } label: {
                    Group {
                        if floats {
                            // A departing notice keeps its own row while the capsule closes.
                            NotchCapsuleNoticeView(notice: notice, geometry: service.geometry,
                                                   size: service.notice == nil ? service.capsuleNoticeSurface(notice)
                                                       : service.surfaceSize)
                        } else {
                            NotchNoticeView(notice: notice, geometry: service.geometry, hidesMascot: service.mascotBridging)
                        }
                    }
                    // Beside a camera the notice reaches further toward its
                    // wider side, and takes clicks all the way to its end.
                    .contentShape(Rectangle().offset(x: floats ? 0
                        : service.geometry.noticeShift(notice.wings(in: service.geometry))))
                }
                // A floating capsule lights up under the pointer. Beside a
                // camera the wash would outline the housing, so the notch keeps
                // its notices plain, as its other strips are.
                .buttonStyle(NotchButtonStyle(cornerRadius: 14, lifts: false, highlights: floats))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.accessibilityText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { service.activateNotice(notice) }
                .accessibilityHint(text.open)
                .transition(.opacity)
            }
        } else if service.peeking {
            HStack {
                navigation
                Spacer(minLength: 8)
                NotchIconButton(symbol: "chevron.down", title: text.open) { service.open() }
            }
            .padding(.horizontal, NotchLayout.horizontalInset).padding(.top, service.geometry.safeContentTop)
        } else if let activity = service.compactActivity {
            if service.showsCompactActivityPicker {
                let layout = service.compactActivityPickerLayout
                VStack(spacing: 0) {
                    let strip = service.compactStripSize(for: activity, companion: service.compactCompanion)
                    ZStack(alignment: .top) {
                        activityStrip(activity, size: strip)
                            .frame(width: strip.width, height: layout.headerHeight, alignment: .top)
                            .id(NotchPickedStrip(activity: activity, companion: service.compactCompanion))
                            .transition(.blurReplace)
                    }
                    .frame(height: layout.headerHeight, alignment: .top)
                    NotchActivityPicker(activities: service.compactActivities, selected: activity,
                                        combinations: service.compactActivityCombinations,
                                        combination: service.compactCompanion.map {
                                            NotchActivityCombination(primary: activity, companion: $0)
                                        },
                                        columns: layout.columns, language: l10n.language,
                                        select: service.selectCompactActivity, combine: service.selectCompactCombination)
                        .padding(.horizontal, NotchActivityPickerLayout.horizontalInset)
                        .padding(.vertical, NotchActivityPickerLayout.verticalInset)
                }
            } else {
                // Hover grows the capsule around its strip, as it grows the
                // notch around its wings. Drawn at the grown size, a song's
                // cover and bars jumped out at once while the shape still grew.
                let strip = service.compactStripSize(for: activity, companion: service.compactCompanion)
                activityStrip(activity, size: strip)
                    .modifier(NotchMascotActivityVisit(service: service,
                                                       track: service.mascotTrack(overActivityStrip: strip),
                                                       ownStrip: true))
                    .transition(companionSwap)
            }
        } else if let departingMusic = service.departingMusic ?? service.lingeringMusic {
            Group {
                if floats { NotchCapsuleMusicStrip(service: service, snapshot: departingMusic) }
                else { NotchMusicStrip(service: service, snapshot: departingMusic) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if floats {
            NotchCapsuleRestingView(service: service, size: service.surfaceSize)
                .transition(companionSwap)
        } else {
            compact
                .transition(companionSwap)
        }
    }

    /// The island floats as a capsule, whose strips run end to end.
    private var floats: Bool { service.geometry.floats }

    /// A strip and the companion at rest swap through black, where a
    /// crossfade would show it half faded over the strip's text.
    private var companionSwap: AnyTransition { service.mascotAtRest ? .notchFadeThrough : .opacity }

    /// `size` is the capsule's; a hanging strip keeps the camera's geometry.
    @ViewBuilder private func activityStrip(_ activity: NotchCompactActivity, size: CGSize) -> some View {
        if floats {
            switch activity {
            case .timer: NotchCapsuleTimerStrip(service: service, size: size)
            case .watch: NotchCapsuleWatchStrip(service: service, size: size)
            case .downloads: NotchCapsuleDownloadStrip(service: service, size: size)
            case .agents: NotchCapsuleAgentStrip(service: service, size: size)
            case .calendar: NotchCapsuleCalendarStrip(service: service, size: size)
            case .music: NotchCapsuleMusicStrip(service: service, size: size, interactive: true)
            case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size)
            }
        } else {
            // Handed down, the wings stay as they were drawn while a strip
            // whose activity just ended leaves, instead of following the
            // service to an island with no activity, where they are empty.
            let geometry = service.compactActivityGeometry
            switch activity {
            case .timer: NotchTimerStrip(service: service, displayGeometry: geometry)
            case .watch: NotchWatchStrip(service: service, displayGeometry: geometry)
            case .downloads: NotchDownloadStrip(service: service, displayGeometry: geometry)
            case .agents: NotchAgentStrip(service: service, displayGeometry: geometry)
            case .calendar: NotchCalendarStrip(service: service, displayGeometry: geometry)
            case .music: NotchMusicStrip(service: service, displayGeometry: geometry, interactive: true)
            case .keepAwake: NotchKeepAwakeStrip(service: service, displayGeometry: geometry)
            }
        }
    }

    private var compact: some View { NotchRestingStrip(service: service) }

    /// Open beside a camera, the companion stays where it rested closed, and
    /// plays there what happens while the island is open.
    @ViewBuilder private var residentMascot: some View {
        if service.mascotResidentShows {
            let track = service.mascotResidentTrack(surfaceWidth: service.expandedSize.width)
            // Moved to the camera's other side, it crosses behind the camera here too.
            NotchMascotTrackView(look: NotchMascotSupport.look(), track: track, rests: true,
                                 visit: service.mascotVisit.flatMap { $0.kind == .cross ? $0 : nil },
                                 mood: service.mascotRestingMood, reaction: service.mascotReaction, followsIsland: true)
                .frame(width: track.width, height: track.height)
                // The window's own layer shows it while the island opens around it.
                .opacity(service.mascotBridging ? 0 : 1)
                .animation(nil, value: service.mascotBridging)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// The Command Bar in the open island: its field below the camera, its
    /// list below the field, and the island as tall as the two.
    private var commandBarPage: some View {
        CommandBarView(presentation: .island)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { service.updateCommandBarHeight($0) }
            .padding(.top, service.geometry.safeContentTop)
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
    }

    private var showsDetail: Bool { service.showingAppPanel || service.selectedMetric != nil }

    private var expanded: some View {
        VStack(spacing: NotchLayout.spacing) {
            header.zIndex(1)
            Group {
                if service.showingSections {
                    NotchSectionsView(service: service)
                } else if scrollsVertically {
                    ScrollView {
                        content
                            .frame(height: contentOverflows ? pageSize.height : nil)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.bottom, 4)
                            .contentShape(Rectangle())
                    }
                    .scrollIndicators(.automatic)
                    .notchScrollEdgeFade()
                } else {
                    content
                }
            }
            .frame(width: service.contentSize.width, height: service.contentSize.height, alignment: .top)
            .clipShape(NotchPageClip(top: service.expandedGeometry.headerTopInset
                                        + service.expandedGeometry.headerRowHeight + NotchLayout.spacing))
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, service.expandedGeometry.headerTopInset)
        .padding(.bottom, NotchLayout.bottomInset)
        .frame(width: service.expandedSize.width, height: service.expandedSize.height, alignment: .top)
    }

    /// Keep each page's minimum usable layout reachable when a custom height
    /// or the display leaves less room. The outer silhouette stays unchanged.
    private var pageSize: CGSize {
        var size = service.contentSize
        guard !showsDetail else { return size }
        switch service.selected {
        case .controls:
            let items = NotchSupport.controls()
            let shortcuts = items.filter { $0 != .music && !$0.isLevel }
            size.height = max(size.height, NotchLayout.controls(
                hasCards: items.contains(.music) || items.contains(where: \.isLevel),
                shortcutCount: shortcuts.count, width: size.width, height: size.height).height)
        case .timer:
            let session = NotchTimerService.shared.session
            size.height = max(size.height, NotchLayout.timer(
                mode: session.hasSession ? session.mode : NotchTimerSupport.savedMode(),
                hasSession: session.hasSession, width: size.width, height: size.height))
        case .calendar:
            size.height = max(size.height, NotchLayout.calendarMonthMinimumHeight)
        case .clipboard:
            // Search, spacing and a complete card with its action row.
            size.height = max(size.height, NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing
                              + NotchLayout.clipboardCardHeight)
        case .camera:
            // Keep permission and error messages, and the stop button, reachable.
            size.height = max(size.height, 144)
        case .mixer:
            // Shorten the tracks before pushing mute and level controls offscreen.
            size.height = max(size.height, 144)
        case .music:
            let controlsRow = AppFeature.mixer.isAvailable || NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
                ? NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing : 0
            let player = music.playback == nil ? NotchLayout.musicIdleHeight
                : NotchLayout.musicPlayerHeight(layout: service.geometry.layout, height: size.height)
            size.height = max(size.height, player + controlsRow)
        case .files:
            // One shelf tile, its vertical insets, the footer and their gap.
            size.height = max(size.height, 88 + 8 + 28 + NotchLayout.rowSpacing)
        default: break
        }
        return size
    }

    private var contentOverflows: Bool { pageSize.height > service.contentSize.height }

    private var scrollsVertically: Bool {
        guard !service.showingAppPanel else { return false }
        return contentOverflows || service.selectedMetric != nil
            || (service.selected == .captures && service.captureContent != nil)
            || (service.selected == .tools && launcher.isEditing && launcher.activeUtility == nil)
    }

    private var headerFeedback: NotchNotice? {
        guard let notice = service.notice, notice.level != nil,
              [.volume, .brightness, .keyboardLight].contains(notice.event) else { return nil }
        return notice
    }

    private var header: some View {
        HStack(spacing: service.expandedGeometry.headerCameraGap > 0 ? 0 : 6) {
            let quickActions = NotchQuickAccessConfiguration.current().actions
            HStack(spacing: 6) {
                if service.showingSections {
                    NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.toggleSections)
                    if service.expandedGeometry.headerCameraGap == 0 {
                        Text(text.sectionsTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    // Beside the camera the field takes the rest of its side,
                    // stopping a little short of the cutout.
                    NotchSectionSearch(service: service,
                                       maximumFieldWidth: service.expandedGeometry.headerCameraGap > 0 ? .infinity : 150)
                        .padding(.trailing, service.expandedGeometry.headerCameraGap > 0 ? 6 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if showsDetail || service.modules.isEmpty {
                    if showsDetail {
                        NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.goBack)
                    }
                    Text(service.detailTitle)
                        .font(Font(NotchLayout.detailTitleFont as CTFont))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if !quickActions.contains(.explore) {
                        NotchIconButton(symbol: "square.grid.2x2", title: text.sectionsTitle, action: service.toggleSections)
                    }
                    Text(service.selected.title(l10n.language))
                        .font(Font(NotchLayout.headerTitleFont as CTFont))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: service.expandedGeometry.headerCameraGap > 0 ? (service.contentSize.width - service.expandedGeometry.headerCameraGap) / 2 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep search mounted so a media key never discards its focus.
            .opacity(headerFeedback == nil ? 1 : 0)
            .allowsHitTesting(headerFeedback == nil)
            .accessibilityHidden(headerFeedback != nil)
            .overlay(alignment: .leading) {
                if let notice = headerFeedback { NotchExpandedLevelView(notice: notice) }
            }
            .clipped()
            if service.expandedGeometry.headerCameraGap > 0 {
                Color.clear.frame(width: service.expandedGeometry.headerCameraGap)
            }
            HStack(spacing: 6) {
                if service.selected == .captures, !showsDetail, !service.showingSections,
                   let actions = service.captureActions {
                    actions.fixedSize()
                    overflowMenu(items: overflowItems(tools: false, clear: false))
                } else if service.expandedGeometry.headerCameraGap > 0 {
                    cameraHeaderActions
                } else {
                    headerActions(quickActions: quickActions)
                }
            }
            .frame(width: service.expandedGeometry.headerCameraGap > 0 ? (service.contentSize.width - service.expandedGeometry.headerCameraGap) / 2 : nil,
                   alignment: .trailing)
        }
        .frame(height: service.expandedGeometry.headerRowHeight)
        .contentShape(Rectangle())
        // Each move reports, not only a crossing. After the watch below hides
        // the actions, SwiftUI may still count the pointer as inside and would
        // never report it entering again.
        .onContinuousHover { phase in
            switch phase {
            case .active: if !headerHovered { headerHovered = true }
            case .ended: headerHovered = false
            }
        }
        .background { NotchHoverExitWatch(active: headerHovered) { headerHovered = false } }
        .onAppear { UpdateService.shared.checkIfStale() }
        // Collapsing under the pointer takes the row away without a final
        // hover(false); the next opening starts with the actions out of sight.
        .onDisappear { headerHovered = false }
    }

    /// The island's history page shows only the cards, so its clear action
    /// sits in the header, where the panel's own header keeps it.
    private var showsCapturesClear: Bool {
        service.selected == .captures && service.captureContent == nil && !showsDetail
            && !service.showingSections && !service.modules.isEmpty
    }

    /// Notifications show only cards too; every row of height is theirs.
    private var showsNotificationsClear: Bool {
        service.selected == .notifications && !showsDetail
            && !service.showingSections && !service.modules.isEmpty
    }

    private var cameraHeaderActions: some View {
        ViewThatFits(in: .horizontal) {
            cameraHeaderActions(compactUpdate: false).fixedSize(horizontal: true, vertical: false)
            cameraHeaderActions(compactUpdate: true).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func cameraHeaderActions(compactUpdate: Bool) -> some View {
        HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate, compact: compactUpdate)
            overflowMenu(items: overflowItems(
                tools: service.selected == .tools && !showsDetail && !service.showingSections && launcher.activeUtility == nil,
                clear: showsCapturesClear, clearNotifications: showsNotificationsClear))
        }
    }

    /// The header's overflow entries, each with the glyph its own button
    /// wears when the pointer row shows them separately.
    private func overflowItems(tools: Bool, clear: Bool, clearNotifications: Bool = false) -> [NotchMenuItem] {
        var items: [NotchMenuItem] = []
        if tools {
            items.append(NotchMenuItem(title: text.customizeTools, checked: launcher.isEditing,
                                       symbol: "slider.horizontal.3") { launcher.isEditing.toggle() })
        }
        if clear {
            // As the header draws, the pointer on its way to this menu included,
            // and again when chosen: this view does not observe the history.
            let empty = { RecentCapturesView.visible(RecentCaptureService.shared.entries).isEmpty }
            items.append(NotchMenuItem(title: FeatureStrings.recentCaptures(l10n.language).clear, symbol: "trash",
                                       enabled: !empty(), action: {
                guard !empty() else { return }
                RecentCapturesView.confirmClearAboveIsland()
            }))
        }
        if clearNotifications {
            // Checked as the header draws and again when chosen, like the
            // captures entry: this view does not observe the notification service.
            let notifications = NotchNotificationService.shared
            let unavailable = { notifications.items.isEmpty || notifications.openingID != nil }
            items.append(NotchMenuItem(title: FeatureStrings.notchNotifications(l10n.language).clearAll, symbol: "trash",
                                       enabled: !unavailable(), action: {
                guard !unavailable() else { return }
                NotchClearNotificationsButton.confirmClearAboveIsland()
            }))
        }
        if !items.isEmpty { items.append(.separator) }
        items.append(NotchMenuItem(title: service.pinned ? text.unpin : text.pin,
                                   symbol: service.pinned ? "pin.slash" : "pin") { service.pinned.toggle() })
        items.append(NotchMenuItem(title: l10n.s.menuSettings, symbol: "gearshape", action: service.openSettings))
        items.append(NotchMenuItem(title: text.collapse, symbol: "chevron.up", action: service.collapse))
        return items
    }

    /// A native menu drawn in the island's dark appearance, so it reads as part
    /// of it, and each entry carries its glyph.
    private func overflowMenu(items: [NotchMenuItem]) -> some View {
        NotchMenuButton(title: text.title, items: items, cornerRadius: 8) {
            Image(systemName: service.pinned ? "pin.fill" : "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// The header's actions keep their room but stay out of sight until the
    /// pointer reaches the row: a title, not a toolbar. An available update
    /// leaves a dot so it is never missed, and a download stays in view.
    /// The fade follows the value instead of the hover callback's transaction,
    /// which reached the screen without its animation once the island was key.
    private func headerActions(quickActions: [NotchQuickAction]) -> some View {
        let updating = updates.state.isInProgress
        let revealed = headerHovered || updating
        return HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate)
            if service.selected == .tools, !service.showingAppPanel, !service.showingSections, service.selectedMetric == nil,
               !service.modules.isEmpty, launcher.activeUtility == nil {
                NotchIconButton(symbol: launcher.isEditing ? "checkmark" : "slider.horizontal.3",
                                title: text.customizeTools, selected: launcher.isEditing) {
                    withAnimation(.easeOut(duration: 0.15)) { launcher.isEditing.toggle() }
                }
            }
            if showsCapturesClear { NotchClearCapturesButton() }
            if showsNotificationsClear { NotchClearNotificationsButton() }
            // Keeping the island open is one click, like the floating buttons;
            // a header button steps aside when the same action floats beside it.
            if !quickActions.contains(.pin) {
                NotchIconButton(symbol: service.pinned ? "pin.fill" : "pin",
                                title: service.pinned ? text.unpin : text.pin, selected: service.pinned) {
                    service.pinned.toggle()
                }
            }
            if !quickActions.contains(.settings) {
                NotchIconButton(symbol: "gearshape", title: l10n.s.menuSettings, action: service.openSettings)
            }
            NotchIconButton(symbol: "chevron.up", title: text.collapse, action: service.collapse)
        }
        .opacity(revealed ? 1 : 0)
        .overlay(alignment: .trailing) {
            if !revealed {
                HStack(spacing: 5) {
                    if case .available(let version) = updates.state {
                        Circle()
                            .fill(UpdateServiceSupport.SemanticVersion(raw: version)?.isPrerelease == true ? Color.orange : Color.blue)
                            .frame(width: 6, height: 6)
                    }
                    // A kept-open island says so at rest, not only under the pointer.
                    if service.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: revealed)
    }

    private var navigationTitle: String {
        let destination = service.reopeningDestination
        return destination.appPanel || destination.sections
            ? text.sectionsTitle : destination.module.title(l10n.language)
    }

    private var navigation: some View {
        Button(action: service.toggleSections) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(navigationTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: NotchLayout.navigationHeight)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .accessibilityLabel(text.switchSection)
        .accessibilityValue(navigationTitle)
        .accessibilityIdentifier("notch.navigation")
        .help(text.switchSection + "  ⌘K")
    }

    @ViewBuilder private var content: some View {
        if service.showingAppPanel {
            MenuPanelView(notchSize: pageSize)
        } else if let metric = service.selectedMetric {
            if metric == .fan {
                NotchFanControlView()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { service.updateFanDetailHeight($0) }
            } else {
                MetricDetailView(kind: metric)
            }
        } else if service.modules.isEmpty {
            NotchEmptyView(symbol: "slider.horizontal.3", message: text.empty)
        } else {
            switch service.selected {
            case .timer: NotchTimerView(size: pageSize)
            case .camera: NotchCameraView(size: pageSize)
            case .notifications: NotchNotificationsView(size: pageSize)
            case .downloads: NotchDownloadsView(size: pageSize)
            case .calendar: NotchCalendarView(size: pageSize)
            case .controls: NotchControlsView(service: service, size: pageSize)
            case .mixer: NotchMixerView(size: pageSize)
            case .music: NotchMusicView(size: pageSize, extrasHeight: service.geometry.musicExtrasHeight)
            case .clipboard: NotchClipboardView(service: service, size: pageSize)
            case .captures:
                if let capture = service.captureContent {
                    capture.frame(maxWidth: .infinity)
                } else {
                    RecentCapturesView(onClose: nil, notchSize: pageSize)
                }
            case .files: NotchFilesView(service: service)
            case .system:
                NotchSystemView(size: pageSize) { service.showMetric($0) }
            case .tools: QuickLauncherView(notchSize: pageSize)
            case .scratchpad: NotchScratchpadView(service: service)
            case .agents: NotchAgentsView(size: pageSize)
            case .watch: NotchWatchView(size: pageSize)
            }
        }
    }
}

/// AppKit reports hover from the moves the island's window receives, and the
/// window server sends it none over the window's clear pixels. A pointer that
/// left the header across them, above a floating capsule or toward the side
/// buttons, was never reported gone, so the row's actions stayed in view.
/// While the row reads as hovered, every move is checked against it here.
private struct NotchHoverExitWatch: NSViewRepresentable {
    let active: Bool
    let exited: () -> Void

    func makeNSView(context: Context) -> NotchHoverExitView { NotchHoverExitView() }
    func updateNSView(_ view: NotchHoverExitView, context: Context) {
        view.exited = exited
        view.watch(active)
    }
    static func dismantleNSView(_ view: NotchHoverExitView, coordinator: ()) { view.watch(false) }
}

private final class NotchHoverExitView: NSView {
    var exited: (() -> Void)?
    private var monitors: [Any] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    deinit { monitors.forEach(NSEvent.removeMonitor) }

    /// Nothing is watched at rest.
    func watch(_ active: Bool) {
        guard active else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            return
        }
        guard monitors.isEmpty else { return }
        // A drag moves the pointer without mouse-moved events.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.check() }) {
            monitors.append(token)
        }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.check()
            return event
        }) { monitors.append(token) }
    }

    private func check() {
        // The pointer on a screen's top row reports y == maxY, which
        // `contains` excludes and NSMouseInRect keeps.
        guard let window,
              !NSMouseInRect(NSEvent.mouseLocation, window.convertToScreen(convert(bounds, to: nil)), false) else { return }
        exited?()
    }
}

/// Observes the history on its own, so a new capture does not redraw the island.
private struct NotchClearCapturesButton: View {
    @ObservedObject private var history = RecentCaptureService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NotchIconButton(symbol: "trash", title: FeatureStrings.recentCaptures(l10n.language).clear,
                        action: RecentCapturesView.confirmClearAboveIsland)
            .disabled(RecentCapturesView.visible(history.entries).isEmpty)
    }
}

/// Read-only RPM telemetry stays available when the protected fan helper fails.
private struct NotchFanControlView: View {
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        FanControlSection(collapsible: false, fallbackFanSpeeds: monitor.snapshot.fanSpeeds)
    }
}

private extension UpdateService.State {
    /// A download or install stays in view; an offer waits behind the dot.
    var isInProgress: Bool {
        switch self {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

/// The charge the closed island rests with, beside a camera or in the capsule.
enum NotchRestingBattery {
    /// Both halves of the charge turn amber, then red, together as it runs low.
    static func tint(for power: PowerReading, tint: Bool, threshold: Int,
                     early: Bool, earlyThreshold: Int) -> Color {
        switch NotchSupport.batteryWarning(percent: power.chargePercent,
                                           externalConnected: power.externalConnected,
                                           tint: tint, threshold: threshold,
                                           early: early, earlyThreshold: earlyThreshold) {
        case .low: return .red
        case .early: return .orange
        case .none: return .white.opacity(0.9)
        }
    }

    /// The icon empties with the charge, as the menu bar's does.
    static func symbol(for power: PowerReading) -> String {
        BatteryPowerSupport.menuBarSymbol(percent: power.chargePercent ?? 100,
                                          isCharging: power.isCharging,
                                          externalConnected: power.externalConnected)
    }
}

/// The closed island at rest beside a camera: the wings with the charge,
/// the song or the AI allowance the person chose, when the menus leave room.
/// The companion rests in a wing when nothing else is there, and walks
/// through on its visits.
struct NotchRestingStrip: View {
    @ObservedObject var service: NotchService
    /// Another display's strip, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.notchLowBatteryTint) private var lowBatteryTint = false
    @AppStorage(DefaultsKey.notchLowBatteryThreshold) private var lowBatteryThreshold = NotchSupport.defaultLowBatteryThreshold
    @AppStorage(DefaultsKey.notchLowBatteryEarly) private var earlyBatteryWarning = false
    @AppStorage(DefaultsKey.notchLowBatteryEarlyThreshold) private var earlyBatteryThreshold = NotchSupport.defaultEarlyBatteryThreshold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    private var batteryTint: Color {
        NotchRestingBattery.tint(for: service.power, tint: lowBatteryTint, threshold: lowBatteryThreshold,
                                 early: earlyBatteryWarning, earlyThreshold: earlyBatteryThreshold)
    }

    private var batterySymbol: String { NotchRestingBattery.symbol(for: service.power) }

    /// Centre battery content inside the wing's visible area, past its curved shoulder.
    private var restingBatteryInset: CGFloat {
        // Leave enough of the 44-point wing for the full 100% label at every height.
        min(16, NotchLayout.shoulder(height: geometry.stripHeight) + NotchLayout.compactEdgeGap)
    }

    /// A visit walks over what the island rests with, which steps aside
    /// meanwhile. Reacting in its own wing, it takes only that one, as over
    /// an activity, and the other side stays in view.
    private func wingStepsAside(_ side: NotchMascotSide) -> Bool {
        guard service.mascotStepsAside, !service.mascotAtRest else { return false }
        return service.mascotVisit?.kind.takesOnlyItsWing != true || side == service.mascotSide
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if service.idleContent != .none, geometry.restingWingWidth > 0 {
                    // Each wing keeps its width even when it has nothing to
                    // show, or the other one slides toward the camera.
                    ZStack(alignment: .trailing) {
                        Color.clear
                        switch service.idleContent {
                        case .music:
                            if let artwork = music.artwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                                    .frame(width: min(22, geometry.stripHeight - 6), height: min(22, geometry.stripHeight - 6))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        case .battery:
                            Image(systemName: batterySymbol).font(.system(size: 12))
                                .foregroundStyle(batteryTint)
                                .padding(.leading, restingBatteryInset)
                        case .agents:
                            NotchAgentRestingWing(leading: true)
                                .padding(.leading, restingBatteryInset)
                        case .none: EmptyView()
                        }
                    }
                    .frame(width: geometry.restingWingWidth)
                    .opacity(wingStepsAside(.left) ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: wingStepsAside(.left))
                    Color.clear.frame(width: geometry.cameraWidth)
                    ZStack(alignment: .leading) {
                        Color.clear
                        switch service.idleContent {
                        case .music:
                            if music.playback?.isPlaying == true {
                                NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 11,
                                                       tint: music.artworkTint?.color ?? .white)
                            }
                        case .battery:
                            if let percent = service.power.chargePercent {
                                Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(batteryTint)
                                    .lineLimit(1)
                                    .padding(.trailing, restingBatteryInset)
                            }
                        case .agents:
                            NotchAgentRestingWing(leading: false)
                                .padding(.trailing, restingBatteryInset)
                        case .none: EmptyView()
                        }
                    }
                    .frame(width: geometry.restingWingWidth)
                    .opacity(wingStepsAside(.right) ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: wingStepsAside(.right))
                } else { Color.clear }
            }
            if service.mascotShows(on: geometry) {
                NotchMascotTrackView(look: NotchMascotSupport.look(),
                                     track: NotchMascotSupport.track(stripWidth: geometry.collapsed.width,
                                                                     stripHeight: geometry.stripHeight,
                                                                     wing: geometry.restingWingWidth,
                                                                     cameraWidth: geometry.cameraWidth, floats: false,
                                                                     bodyHeight: geometry.stripBodyHeight,
                                                                     side: service.mascotSide),
                                     rests: service.mascotAtRest, visit: service.mascotVisit,
                                     mood: service.mascotRestingMood, reaction: service.mascotReaction,
                                     yieldsToActivities: true)
                    .frame(width: geometry.collapsed.width, height: geometry.stripHeight)
                    // The window's own layer shows it while the island closes around it.
                    .opacity(service.mascotBridging && displayGeometry == nil ? 0 : 1)
                    .animation(nil, value: service.mascotBridging)
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        // The strip stays in its band at the top: hover grows the island
        // around it, and centring it in the taller shape dropped it half
        // the growth in one frame.
        .frame(height: geometry.stripHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    /// A capsule floating this far inside the top and bottom of the rect,
    /// with its own corners, instead of the outline hanging from the edge.
    var floatingGap: CGFloat? = nil
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    /// The island's outline at a surface of `height`, as its display draws it.
    static func island(height: CGFloat, geometry: NotchGeometry) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height), floatingGap: geometry.floatingGap)
    }

    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        if let floatingGap { return Path(NotchLayout.capsulePath(in: rect, gap: floatingGap)) }
        let shoulder = NotchLayout.shoulder(height: rect.height)
        let bottom = min(radius, rect.height / 2, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                      control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
                      control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                      control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
                      control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
                      control2: CGPoint(x: shoulder * tangent, y: 0))
        path.closeSubpath()
        return path
    }
}

extension NotchModule: PanelOrderItem {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .timer: return FeatureStrings.notchActivities(language).timer
        case .camera: return FeatureStrings.notchActivities(language).camera
        case .notifications: return FeatureStrings.notchNotifications(language).title
        case .downloads: return FeatureStrings.notchFiles(language).downloadsTitle
        case .calendar: return FeatureStrings.notchCalendar(language).title
        case .controls: return FeatureStrings.notch(language).controls
        case .mixer: return Strings.localized(language).mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        case .scratchpad: return FeatureStrings.scratchpad(language).pageTitle
        case .agents: return FeatureStrings.notchAgents(language).title
        case .watch: return FeatureStrings.notchWatch(language).title
        }
    }
}

/// A page may draw into the island's own margins and behind its header, which
/// the silhouette already bounds: the artwork's halo and hover growth fade out
/// there instead of ending at a hard edge. The header stays above the page.
private struct NotchPageClip: Shape {
    /// From the top of the page to the top of the island.
    let top: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - NotchLayout.horizontalInset, y: rect.minY - top,
                    width: rect.width + NotchLayout.horizontalInset * 2,
                    height: rect.height + top + NotchLayout.bottomInset))
    }
}

/// The strip the picker shows, a new one for each choice.
private struct NotchPickedStrip: Hashable {
    let activity: NotchCompactActivity
    let companion: NotchCompactActivity?
}

/// Named choices appear below the camera, with the current activity highlighted.
struct NotchActivityPicker: View {
    @Namespace private var choice
    let activities: [NotchCompactActivity]
    let selected: NotchCompactActivity
    let combinations: [NotchActivityCombination]
    let combination: NotchActivityCombination?
    let columns: Int
    let language: AppLanguage
    let select: (NotchCompactActivity) -> Void
    let combine: (NotchActivityCombination) -> Void

    var body: some View {
        VStack(spacing: NotchActivityPickerLayout.spacing) {
            individualChoices
            if !combinations.isEmpty {
                Menu {
                    ForEach(combinations) { pair in
                        Button { combine(pair) } label: {
                            Label(pair.title(language),
                                  systemImage: combination == pair ? "checkmark" : pair.companion.symbol)
                        }
                    }
                } label: {
                    Label(combination?.title(language) ?? FeatureStrings.notch(language).combineActivities,
                          systemImage: combination == nil ? "plus" : "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(combination == nil ? 0.75 : 1))
                        .frame(height: NotchActivityPickerLayout.combinationHeight)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("notch.activity.combine")
            }
        }
    }

    private var individualChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchActivityPickerLayout.spacing),
                                 count: columns), spacing: NotchActivityPickerLayout.spacing) {
            ForEach(activities) { activity in
                let chosen = activity == selected && combination == nil
                Button { select(activity) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: activity.symbol)
                        Text(activity.title(language)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchActivityPickerLayout.rowHeight)
                    .foregroundStyle(chosen ? Color.black : Color.white)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                            if chosen {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                                    .matchedGeometryEffect(id: "choice", in: choice)
                            }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.title(language))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("notch.activity.\(activity.rawValue)")
            }
        }
    }
}
