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
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .foregroundStyle(.white)
            // The window server leaves Liquid Glass out of its hit test, so a
            // click or a wheel over empty glass would reach the window behind:
            // the page stops scrolling between cards and the island loses
            // focus. A fill too faint to see keeps the surface in this window,
            // as the black backdrop does.
            .background(shape.fill(Color.black.opacity(0.01)))
            .contentShape(shape)
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
            expanded
        } else if service.dragPlaceholder {
            Label(text.dropHint, systemImage: "tray.and.arrow.down")
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
                            NotchNoticeView(notice: notice, geometry: service.geometry)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                    activityStrip(activity, size: strip)
                        .frame(width: strip.width, height: layout.headerHeight, alignment: .top)
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
                activityStrip(activity, size: service.surfaceSize)
            }
        } else if let departingMusic = service.departingMusic {
            Group {
                if floats { NotchCapsuleMusicStrip(service: service, snapshot: departingMusic) }
                else { NotchMusicStrip(service: service, snapshot: departingMusic) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if floats {
            NotchCapsuleRestingView(service: service, size: service.surfaceSize)
                .transition(.opacity)
        } else {
            compact
                .transition(.opacity)
        }
    }

    /// The island floats as a capsule, whose strips run end to end.
    private var floats: Bool { service.geometry.floats }

    /// `size` is the capsule's; a hanging strip keeps the camera's geometry.
    @ViewBuilder private func activityStrip(_ activity: NotchCompactActivity, size: CGSize) -> some View {
        if floats {
            switch activity {
            case .timer: NotchCapsuleTimerStrip(service: service, size: size)
            case .downloads: NotchCapsuleDownloadStrip(service: service, size: size)
            case .agents: NotchCapsuleAgentStrip(service: service, size: size)
            case .calendar: NotchCapsuleCalendarStrip(service: service, size: size)
            case .music: NotchCapsuleMusicStrip(service: service, size: size)
            }
        } else {
            switch activity {
            case .timer: NotchTimerStrip(service: service)
            case .downloads: NotchDownloadStrip(service: service)
            case .agents: NotchAgentStrip(service: service)
            case .calendar: NotchCalendarStrip(service: service)
            case .music: NotchMusicStrip(service: service)
            }
        }
    }

    private var compact: some View { NotchRestingStrip(service: service) }

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
            let shortcuts = items.filter { $0 != .music && $0 != .volume && $0 != .brightness }
            size.height = max(size.height, NotchLayout.controls(
                hasCards: items.contains(.music) || items.contains(.volume) || items.contains(.brightness),
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

    /// The fan card opens Fan Control, so its page shares that title.
    private func detailTitle(_ metric: MetricDetailKind) -> String {
        metric == .fan ? FeatureStrings.fanControl(l10n.language).title : metric.title(l10n.s)
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
                    Text(service.showingAppPanel ? "Vorssaint" : service.selectedMetric.map(detailTitle) ?? text.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if !quickActions.contains(.explore) {
                        NotchIconButton(symbol: "square.grid.2x2", title: text.sectionsTitle, action: service.toggleSections)
                    }
                    Text(service.selected.title(l10n.language))
                        .font(.system(size: 16, weight: .semibold))
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
                    Menu {
                        Button(service.pinned ? text.unpin : text.pin) { service.pinned.toggle() }
                        Button(l10n.s.menuSettings, action: service.openSettings)
                        Button(text.collapse, action: service.collapse)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(text.title)
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
        .onHover { headerHovered = $0 }
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

    private var cameraHeaderActions: some View {
        ViewThatFits(in: .horizontal) {
            cameraHeaderActions(compactUpdate: false).fixedSize(horizontal: true, vertical: false)
            cameraHeaderActions(compactUpdate: true).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func cameraHeaderActions(compactUpdate: Bool) -> some View {
        HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate, compact: compactUpdate)
            Menu {
                if service.selected == .tools, !showsDetail, !service.showingSections, launcher.activeUtility == nil {
                    Button(text.customizeTools) { launcher.isEditing.toggle() }
                }
                if showsCapturesClear { NotchClearCapturesButton(inMenu: true) }
                Button(service.pinned ? text.unpin : text.pin) { service.pinned.toggle() }
                Button(l10n.s.menuSettings, action: service.openSettings)
                Button(text.collapse, action: service.collapse)
            } label: {
                Image(systemName: service.pinned ? "pin.fill" : "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(text.title)
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
            }
        }
    }
}

/// Observes the history on its own, so a new capture does not redraw the island.
private struct NotchClearCapturesButton: View {
    var inMenu = false
    @ObservedObject private var history = RecentCaptureService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let title = FeatureStrings.recentCaptures(l10n.language).clear
        let empty = RecentCapturesView.visible(history.entries).isEmpty
        if inMenu {
            Button(title, role: .destructive, action: RecentCapturesView.confirmClearAboveIsland)
                .disabled(empty)
        } else {
            NotchIconButton(symbol: "trash", title: title, action: RecentCapturesView.confirmClearAboveIsland)
                .disabled(empty)
        }
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

/// The closed island at rest beside a camera: the wings with the charge,
/// the song or the AI allowance the person chose, when the menus leave room.
struct NotchRestingStrip: View {
    @ObservedObject var service: NotchService
    /// Another display's strip, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var music = NotchMusicService.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    /// Centre battery content inside the wing's visible area, past its curved shoulder.
    private var restingBatteryInset: CGFloat {
        // Leave enough of the 44-point wing for the full 100% label at every height.
        min(16, NotchLayout.shoulder(height: geometry.stripHeight) + NotchLayout.compactEdgeGap)
    }

    var body: some View {
        HStack(spacing: 0) {
            if service.idleContent != .none, geometry.restingWingWidth > 0 {
                Group {
                    switch service.idleContent {
                    case .music:
                        if let artwork = music.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                                .frame(width: min(22, geometry.stripHeight - 6), height: min(22, geometry.stripHeight - 6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    case .battery:
                        Image(systemName: "battery.100percent").font(.system(size: 12))
                            .padding(.leading, restingBatteryInset)
                    case .agents:
                        NotchAgentRestingWing(leading: true)
                            .padding(.leading, restingBatteryInset)
                    case .none: EmptyView()
                    }
                }.frame(width: geometry.restingWingWidth, alignment: .trailing)
                Color.clear.frame(width: geometry.cameraWidth)
                Group {
                    switch service.idleContent {
                    case .music:
                        if music.playback?.isPlaying == true {
                            NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 11,
                                                   tint: music.artworkTint?.color ?? .white)
                        }
                    case .battery:
                        if let percent = service.power.chargePercent {
                            Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                                .lineLimit(1)
                                .padding(.trailing, restingBatteryInset)
                        }
                    case .agents:
                        NotchAgentRestingWing(leading: false)
                            .padding(.trailing, restingBatteryInset)
                    case .none: EmptyView()
                    }
                }.frame(width: geometry.restingWingWidth, alignment: .leading)
            } else { Color.clear }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .mixer: return L10n.shared.s.mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        case .scratchpad: return FeatureStrings.scratchpad(language).pageTitle
        case .agents: return FeatureStrings.notchAgents(language).title
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

/// Named choices appear below the camera, with the current activity highlighted.
struct NotchActivityPicker: View {
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
                                  systemImage: combination == pair ? "checkmark" : pair.companion.module.symbol)
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
                        Image(systemName: activity.module.symbol)
                        Text(activity.title(language)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchActivityPickerLayout.rowHeight)
                    .foregroundStyle(chosen ? Color.black : Color.white)
                    .background(chosen ? Color.white : Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8))
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
