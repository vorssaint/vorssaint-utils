// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

struct DockPreviewPanelView: View {
    @ObservedObject var service: DockPreviewService

    var body: some View {
        DockPreviewPanelContent(
            windows: service.windows,
            previews: service.previews,
            selectedWindowID: service.selectedWindowID,
            currentAppName: service.currentAppName,
            isPinned: service.isPinned,
            orientation: service.orientation,
            onPreview: service.preview,
            onEndPreview: service.endPreview,
            onCommit: service.commit,
            onCloseWindow: service.close,
            onMiddleClick: service.closeWindow,
            onToggleMinimized: service.toggleMinimized,
            onTogglePinned: service.togglePinned,
            onClosePanel: service.closePreviewPanel,
            onSelectPrevious: {
                service.selectPreviousWindow()
                return service.selectedWindowID
            },
            onSelectNext: {
                service.selectNextWindow()
                return service.selectedWindowID
            },
            onBeginDrag: service.beginWindowDrag,
            onUpdateDrag: service.updateWindowDrag,
            onEndDrag: service.endWindowDrag
        )
    }
}

struct DockPreviewPinnedPanelView: View {
    @ObservedObject var panel: DockPreviewPinnedPanel

    var body: some View {
        DockPreviewPanelContent(
            windows: panel.windows,
            previews: panel.previews,
            selectedWindowID: panel.selectedWindowID,
            currentAppName: panel.currentAppName,
            isPinned: true,
            orientation: .bottom,
            onPreview: panel.preview,
            onEndPreview: panel.endPreview,
            onCommit: panel.commit,
            onCloseWindow: panel.close,
            onMiddleClick: panel.closeWindow,
            onToggleMinimized: panel.toggleMinimized,
            onTogglePinned: panel.closePreviewPanel,
            onClosePanel: panel.closePreviewPanel,
            onSelectPrevious: {
                panel.selectPreviousWindow()
                return panel.selectedWindowID
            },
            onSelectNext: {
                panel.selectNextWindow()
                return panel.selectedWindowID
            },
            // A pinned panel is a detached copy with no session to end, so it
            // carries the tap and button actions but not drag-to-place.
            onBeginDrag: { _ in },
            onUpdateDrag: {},
            onEndDrag: { _ in }
        )
    }
}

private struct DockPreviewPanelContent: View {
    let windows: [SwitcherItem]
    let previews: [CGWindowID: CGImage]
    let selectedWindowID: CGWindowID?
    let currentAppName: String?
    let isPinned: Bool
    let orientation: DockPreviewOrientation
    let onPreview: (SwitcherItem) -> Void
    let onEndPreview: (SwitcherItem) -> Void
    let onCommit: (SwitcherItem) -> Void
    let onCloseWindow: (SwitcherItem) -> Void
    let onMiddleClick: (SwitcherItem) -> Void
    let onToggleMinimized: (SwitcherItem) -> Void
    let onTogglePinned: () -> Void
    let onClosePanel: () -> Void
    let onSelectPrevious: () -> CGWindowID?
    let onSelectNext: () -> CGWindowID?
    let onBeginDrag: (SwitcherItem) -> Void
    let onUpdateDrag: () -> Void
    let onEndDrag: (SwitcherItem) -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var draggingWindowID: CGWindowID?
    @State private var shake = PreviewShakeDetector()
    @State private var shakeSpent = false
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @AppStorage(DefaultsKey.dockPreviewBackgroundOpacity) private var backgroundOpacity = 1.0
    @AppStorage(DefaultsKey.dockPreviewQuitAppOnClose) private var quitAppOnClose = false

    private var closeActionTitle: String {
        DockPreviewSupport.closeAction(quitAppOnClose: quitAppOnClose) == .quitApp
            ? l10n.s.panelQuit
            : l10n.s.dockPreviewCloseWindow
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if DockPreviewSupport.showsPanelHeader(isPinned: isPinned) {
                    panelHeader(proxy: proxy)
                }
                ScrollView(compact || stacksVertically ? .vertical : .horizontal, showsIndicators: false) {
                    cardRun {
                        ForEach(windows) { window in
                            if compact {
                                compactRow(window)
                            } else {
                            DockPreviewCard(
                                window: window,
                                preview: window.previewWindowID.flatMap { previews[$0] },
                                isSelected: selectedWindowID == window.windowID,
                                isPanelPinned: isPinned,
                                onTogglePinned: onTogglePinned,
                                closeActionTitle: closeActionTitle,
                                onCommit: {
                                    onCommit(window)
                                },
                                onClose: {
                                    onCloseWindow(window)
                                },
                                onMiddleClick: { middleClick(window) },
                                onToggleMinimized: { onToggleMinimized(window) },
                                onCloseAll: { for item in windows { onMiddleClick(item) } },
                                onMinimizeAll: minimizeAllWindows

                            )
                            .background {
                                if DockOption.gestures.bool {
                                    PreviewSwipeReader(enabled: true, orientation: orientation) { action in
                                        if action == .minimize { onToggleMinimized(window) }
                                        else { _ = WindowEnhancementActions.perform(action, on: window) }
                                    }
                                }
                            }
                            .id(window.id)
                            .gesture(
                                DragGesture(minimumDistance: DockPreviewSupport.dragLiftDistance,
                                            coordinateSpace: .global)
                                    .onChanged { value in
                                        if shakeSpent { return }
                                        if DockOption.shakeAction.string == "minimizeOthers",
                                           shake.sample(value.location, at: ProcessInfo.processInfo.systemUptime) {
                                            shakeSpent = true
                                            if !isPinned { DockPreviewService.shared.cancelWindowDrag() }
                                            for other in windows where other.windowID != window.windowID && !other.isMinimized {
                                                _ = WindowEnhancementActions.perform(.minimize, on: other)
                                            }
                                            return
                                        }
                                        if draggingWindowID == nil {
                                            draggingWindowID = window.windowID
                                            onBeginDrag(window)
                                        }
                                        guard draggingWindowID == window.windowID else { return }
                                        onUpdateDrag()
                                    }
                                    .onEnded { _ in
                                        shake = .init()
                                        if shakeSpent { shakeSpent = false; draggingWindowID = nil; return }
                                        guard draggingWindowID == window.windowID else { return }
                                        draggingWindowID = nil
                                        onEndDrag(window)
                                    }
                            )
                            .onHover { hovering in
                                if hovering {
                                    onPreview(window)
                                } else {
                                    onEndPreview(window)
                                }
                            }
                            }
                        }
                    }
                    .padding(.horizontal, DockPreviewSupport.panelPadding)
                    .padding(.bottom, DockPreviewSupport.panelPadding)
                    .padding(.top, showsHeader ? 0 : DockPreviewSupport.panelPadding)
                }
                // A panel that already shows every window has nothing to
                // scroll, and a scroll view that can move steals the drag that
                // carries a window out of the panel.
                .scrollDisabled(showsEveryWindow)
            }
        }
        .frame(width: !compact && stacksVertically ? CGFloat(lanes) * DockPreviewSupport.cardWidth
                   + CGFloat(lanes - 1) * DockPreviewLayout.spacing + DockPreviewSupport.panelPadding * 2 : nil,
               height: compact || stacksVertically ? nil : cardRunHeight)
        .background(HUDBackdrop(cornerRadius: DockPreviewLayout.radius,
                                opacity: DockPreviewSupport.sanitizedBackgroundOpacity(backgroundOpacity)))
        .clipShape(RoundedRectangle(cornerRadius: DockPreviewLayout.radius, style: .continuous))
        // The hairline keeps its full strength as the material fades: it is what
        // still draws the panel's shape once the frost stops doing it.
        .overlay(
            RoundedRectangle(cornerRadius: DockPreviewLayout.radius, style: .continuous)
                .strokeBorder(minimalPreviews ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var compact: Bool { DockPreviewLayout.compact(windows.count) }
    private var lanes: Int { DockPreviewLayout.lanes(windows.count, orientation: orientation, isPinned: isPinned) }

    private var stacksVertically: Bool {
        DockPreviewSupport.stacksVertically(orientation: orientation, isPinned: isPinned)
    }

    private var showsHeader: Bool {
        DockPreviewSupport.showsPanelHeader(isPinned: isPinned)
    }

    /// The panel is sized by the service against the real screen; this only
    /// keeps the content from collapsing before the first capture lands, so a
    /// nominal screen is enough for it.
    private var showsEveryWindow: Bool {
        DockPreviewSupport.visibleCardCount(
            itemCount: windows.count,
            screenVisibleFrame: NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900),
            orientation: orientation,
            isPinned: isPinned
        ) >= windows.count
    }

    private var cardRunHeight: CGFloat {
        CGFloat(lanes) * DockPreviewSupport.cardHeight + CGFloat(lanes - 1) * DockPreviewLayout.spacing + DockPreviewSupport.panelPadding * 2
            + (showsHeader ? DockPreviewSupport.panelHeaderHeight : 0)
    }

    @ViewBuilder
    private func cardRun<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if compact {
            VStack(spacing: 0) { content() }
        } else if stacksVertically {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(DockPreviewSupport.cardWidth), spacing: DockPreviewLayout.spacing), count: lanes), spacing: DockPreviewLayout.spacing) { content() }
        } else {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(DockPreviewSupport.cardHeight), spacing: DockPreviewLayout.spacing), count: lanes), spacing: DockPreviewLayout.spacing) { content() }
        }
    }

    private func middleClick(_ item: SwitcherItem) {
        if DockOption.middleClickAction.string == "close" { onMiddleClick(item) }
        else if let action = WindowEnhancementAction(rawValue: DockOption.middleClickAction.string) { _ = WindowEnhancementActions.perform(action, on: item) }
    }

    private func minimizeAllWindows() {
        for item in windows where !item.isMinimized { onToggleMinimized(item) }
    }

    private func compactRow(_ item: SwitcherItem) -> some View {
        HStack(spacing: 8) {
            if let icon = item.appIcon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
            Text(item.displayTitle).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if item.isMinimized { Image(systemName: "minus.rectangle") }
            if let space = DockPreviewLayout.spaceLabel(item) { Text(space).font(.caption.monospacedDigit()) }
            Button { onToggleMinimized(item) } label: { Image(systemName: "minus") }.help(l10n.s.dockPreviewMinimizeWindow)
            Button { onCloseWindow(item) } label: { Image(systemName: "xmark") }.help(closeActionTitle)
        }
        .buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 8).frame(width: 396, height: 36)
        .background(selectedWindowID == item.windowID ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle()).onTapGesture { onCommit(item) }
        .onHover { $0 ? onPreview(item) : onEndPreview(item) }
        .overlay { DockPreviewMiddleClick(onClose: { middleClick(item) }) }
        .contextMenu {
            Button(l10n.s.dockPreviewPinPanel, action: onTogglePinned)
            Button(DockEnhancementStrings.text(.minimizeAll), action: minimizeAllWindows)
            Button(DockEnhancementStrings.text(.closeAll)) { for window in windows { onMiddleClick(window) } }
        }
        .id(item.id)
    }

    private func panelHeader(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 7) {
            dragTitleArea
            windowNavigationButtons(proxy: proxy)
            // Both belong to the pinned panel alone. A hovered panel is
            // dismissed by moving off it, and pinning one is a named item in
            // any card's menu.
            if isPinned {
                Button {
                    onTogglePinned()
                } label: {
                    Image(systemName: "pin.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(l10n.s.dockPreviewUnpinPanel)
                .accessibilityLabel(l10n.s.dockPreviewUnpinPanel)
                Button {
                    onClosePanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help(l10n.s.dockPreviewClosePanel)
                .accessibilityLabel(l10n.s.dockPreviewClosePanel)
            }
        }
        .focusEffectDisabled()
        .padding(.horizontal, DockPreviewSupport.panelPadding)
        .frame(height: DockPreviewSupport.panelHeaderHeight)
    }

    private var dragTitleArea: some View {
        ZStack(alignment: .leading) {
            if isPinned {
                NativeWindowDragHandle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 7) {
                // A hovered panel sits above the Dock icon the pointer is
                // resting on. A pinned panel outlives that pointer and has to
                // name itself.
                if isPinned {
                    if let icon = windows.first?.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(currentAppName ?? "")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let positionText = DockPreviewSupport.windowPositionText(
                    selectedWindowID: selectedWindowID,
                    windowIDs: windows.compactMap(\.windowID)
                ) {
                    HStack(spacing: 3) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 9, weight: .semibold))
                        Text(positionText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                if isPinned {
                    Text(l10n.s.dockPreviewPinned)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: DockPreviewSupport.panelHeaderHeight)
        .layoutPriority(1)
    }

    @ViewBuilder
    private func windowNavigationButtons(proxy: ScrollViewProxy) -> some View {
        if windows.count > 1 {
            HStack(spacing: 1) {
                Button {
                    revealSelection(onSelectPrevious(), proxy: proxy)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .help(l10n.s.dockPreviewPreviousWindow)
                .accessibilityLabel(l10n.s.dockPreviewPreviousWindow)

                Button {
                    revealSelection(onSelectNext(), proxy: proxy)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .help(l10n.s.dockPreviewNextWindow)
                .accessibilityLabel(l10n.s.dockPreviewNextWindow)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
    }

    private func revealSelection(_ windowID: CGWindowID?, proxy: ScrollViewProxy) {
        guard let windowID,
              let selected = windows.first(where: { $0.windowID == windowID }) else { return }
        // Hover only highlights. Recentering each card that crosses the pointer
        // during a scroll feeds another jump into the gesture.
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(selected.id, anchor: .center)
        }
    }
}

private struct NativeWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.performDrag(with: event)
        }
    }
}

private struct DockPreviewCard: View {
    let window: SwitcherItem
    let preview: CGImage?
    let isSelected: Bool
    let isPanelPinned: Bool
    let onTogglePinned: () -> Void
    let closeActionTitle: String
    let onCommit: () -> Void
    let onClose: () -> Void
    let onMiddleClick: () -> Void
    let onToggleMinimized: () -> Void
    let onCloseAll: () -> Void
    let onMinimizeAll: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var isMinimizeHovering = false
    @State private var suppressNextCommit = false

    private var showsPreviewControls: Bool {
        !minimalPreviews && DockPreviewSupport.showsCardControls(isHovering: isHovering, isSelected: isSelected)
    }

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen || window.isOnHiddenSpace || DockOption.spaceNumbers.bool
    }

    private var showsAppBadge: Bool {
        DockPreviewSupport.showsCardAppBadge(hasPreview: preview != nil)
    }

    var body: some View {
        VStack(spacing: DockPreviewSupport.cardTitleSpacing) {
            if !minimalPreviews && DockOption.controlsPosition.string == "top" { titleBand }
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(minimalPreviews ? Color.clear : Color.white.opacity(0.06))

                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(DockPreviewSupport.cardThumbnailInset)
                } else if let icon = window.appIcon {
                    // Drawn as a watermark, not as content. Every card in a
                    // panel belongs to the app whose Dock icon opened it, and
                    // that icon is already in the header, so this says nothing
                    // new — it only fills the space until a capture lands. At
                    // full strength the capture replacing it reads as a jump;
                    // at this weight it reads as the space filling in, and it
                    // costs no transition, so nothing takes longer.
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: DockPreviewSupport.cardFallbackIconSize,
                               height: DockPreviewSupport.cardFallbackIconSize)
                        .opacity(0.35)
                }

                // One row along the bottom of the picture: the app on the
                // left, the window's state on the right, sharing a baseline --
                // the App Switcher's card, which shows the same two things
                // about the same kind of thing.
                if !minimalPreviews {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 8) {
                            if let icon = window.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: DockPreviewSupport.cardAppBadgeSize,
                                           height: DockPreviewSupport.cardAppBadgeSize)
                                    .shadow(radius: 3)
                                    .padding(.leading, -DockPreviewSupport.cardAppBadgeArtworkInset)
                                    .padding(.bottom, -DockPreviewSupport.cardAppBadgeArtworkInset)
                                    .opacity(showsAppBadge ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                            Spacer(minLength: 0)
                            if hasStatusBadges {
                                HStack(spacing: 5) {
                                    statusBadges
                                }
                            }
                        }
                        .padding(7)
                    }
                }
            }
            .frame(width: DockPreviewSupport.cardThumbnailWidth,
                   height: DockPreviewSupport.cardThumbnailHeight)

            if !minimalPreviews && DockOption.controlsPosition.string != "top" { titleBand }
        }
        .padding(DockPreviewSupport.cardPadding)
        .frame(width: DockPreviewSupport.cardWidth, height: DockPreviewSupport.cardHeight)
        // The selection animates on the two layers that draw it. Animating
        // the card instead put every child in the transaction, so arriving on a
        // card re-composited the shadowed app badge and it blinked once.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
                .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isSelected)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isSelected)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if window.windowID != nil {
                DockPreviewMiddleClick(onClose: onMiddleClick)
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            cardContextMenu
        }
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel(window.spokenLabel(noOpenWindow: l10n.s.switcherNoOpenWindow,
                                               hiddenApp: l10n.s.panelHiddenItem,
                                               otherDesktop: l10n.s.switcherOtherDesktop))
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button(DockEnhancementStrings.text(.closeAll), action: onCloseAll)
        Button(DockEnhancementStrings.text(.minimizeAll), action: onMinimizeAll)
        Button(DockEnhancementStrings.text(.fullscreen)) { _ = WindowEnhancementActions.perform(.fullscreen, on: window) }
        Button(DockEnhancementStrings.text(.quit)) { _ = WindowEnhancementActions.perform(.quit, on: window) }
        Button(DockEnhancementStrings.text(.maximize)) { _ = WindowEnhancementActions.perform(.maximize, on: window) }
        Button(DockEnhancementStrings.text(.center)) { _ = WindowEnhancementActions.perform(.center, on: window) }
        Button {
            onCommit()
        } label: {
            Label(l10n.s.dockPreviewOpenWindow, systemImage: "macwindow")
        }
        if !window.isFullscreen {
            Button {
                onToggleMinimized()
            } label: {
                Label(window.isMinimized ? l10n.s.dockPreviewRestoreWindow : l10n.s.dockPreviewMinimizeWindow,
                      systemImage: window.isMinimized ? "plus.rectangle" : "minus.rectangle")
            }
        }
        Divider()
        Button {
            onTogglePinned()
        } label: {
            Label(isPanelPinned ? l10n.s.dockPreviewUnpinPanel : l10n.s.dockPreviewPinPanel,
                  systemImage: isPanelPinned ? "pin.slash" : "pin")
        }
        Divider()
        Button(role: .destructive) {
            onClose()
        } label: {
            Label(closeActionTitle, systemImage: "xmark.circle")
        }
    }

    /// The title and the two window controls, side by side under the picture.
    /// The controls used to float over the thumbnail in a capsule a third of
    /// its height. The room they take here is held whether or not they are
    /// drawn, so the title does not shift as the pointer arrives.
    private var titleBand: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                // Full strength whether or not the card is selected. The App
                // Switcher dims an unselected name because a grid of them is
                // read at a glance and the selection has to carry; a Dock
                // preview holds the windows of one app, where the name is the
                // only thing telling them apart.
                ScrollingTitle(text: window.displayTitle,
                               weight: isSelected ? .semibold : .regular,
                               width: max(70, DockPreviewSupport.cardTitleTextWidth - 32),
                               alignment: .leading,
                               scrolls: isHovering)
                    .foregroundStyle(.primary)
                if let subtitle = window.displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                closeButton
                minimizeButton
                Button { _ = WindowEnhancementActions.perform(.fullscreen, on: window) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)) }.buttonStyle(.plain).help(DockEnhancementStrings.text(.fullscreen))
                Button { _ = WindowEnhancementActions.perform(.quit, on: window) } label: { Image(systemName: "power").font(.system(size: 9)) }.buttonStyle(.plain).help(DockEnhancementStrings.text(.quit))
            }
        }
        .frame(width: DockPreviewSupport.cardThumbnailWidth,
               height: DockPreviewSupport.cardTitleHeight,
               alignment: .top)
    }

    @ViewBuilder
    private var statusBadges: some View {
        if let space = DockPreviewLayout.spaceLabel(window) { Text(space).font(.caption.monospacedDigit()) }
        if window.isMinimized {
            statusBadge(systemName: "minus.rectangle")
        }
        if window.isFullscreen {
            statusBadge(systemName: "arrow.up.left.and.arrow.down.right")
        }
        if window.isOnHiddenSpace {
            statusBadge(systemName: "rectangle.stack")
        }
    }

    private func statusBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 19, height: 17)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.46))
            )
            .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button {
            suppressNextCommit = true
            onClose()
            DispatchQueue.main.async {
                suppressNextCommit = false
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(isCloseHovering ? 0.95 : 0.72),
                                 Color(red: 1.0, green: 0.38, blue: 0.33).opacity(isCloseHovering ? 1 : 0.92))
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(showsPreviewControls ? 1 : 0)
        .allowsHitTesting(showsPreviewControls)
        .onHover { isCloseHovering = $0 }
        .help(closeActionTitle)
        .accessibilityLabel(closeActionTitle)
    }

    private var minimizeButton: some View {
        Button {
            suppressNextCommit = true
            onToggleMinimized()
            DispatchQueue.main.async {
                suppressNextCommit = false
            }
        } label: {
            Image(systemName: window.isMinimized ? "plus.circle.fill" : "minus.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(isMinimizeHovering ? 0.95 : 0.72),
                                 Color.black.opacity(isMinimizeHovering ? 0.58 : 0.46))
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(showsPreviewControls && !window.isFullscreen ? 1 : 0)
        .allowsHitTesting(showsPreviewControls && !window.isFullscreen)
        .onHover { isMinimizeHovering = $0 }
        .help(window.isMinimized ? l10n.s.dockPreviewRestoreWindow : l10n.s.dockPreviewMinimizeWindow)
        .accessibilityLabel(window.isMinimized ? l10n.s.dockPreviewRestoreWindow : l10n.s.dockPreviewMinimizeWindow)
    }
}

/// Only middle clicks belong to this view; ordinary clicks and drags keep
/// reaching the SwiftUI card underneath, including its context menu.
private struct DockPreviewMiddleClick: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) {
        view.onClose = onClose
    }

    final class ClickView: NSView {
        var onClose: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  DockPreviewSupport.handlesMiddleClick(
                    eventType: event.type, buttonNumber: event.buttonNumber,
                    point: convert(point, from: superview), visibleRect: visibleRect,
                    isHidden: isHiddenOrHasHiddenAncestor)
            else { return nil }
            return self
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func otherMouseDown(with event: NSEvent) {
            guard event.buttonNumber == 2 else { return }
            onClose?()
        }

        override func otherMouseUp(with event: NSEvent) {}
    }
}
