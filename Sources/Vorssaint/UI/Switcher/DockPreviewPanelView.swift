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
            onToggleMinimized: service.toggleMinimized,
            onTogglePinned: service.togglePinned,
            onClosePanel: service.closePreviewPanel,
            onSelectPrevious: service.selectPreviousWindow,
            onSelectNext: service.selectNextWindow,
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
            onToggleMinimized: panel.toggleMinimized,
            onTogglePinned: panel.closePreviewPanel,
            onClosePanel: panel.closePreviewPanel,
            onSelectPrevious: panel.selectPreviousWindow,
            onSelectNext: panel.selectNextWindow,
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
    let onToggleMinimized: (SwitcherItem) -> Void
    let onTogglePinned: () -> Void
    let onClosePanel: () -> Void
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void
    let onBeginDrag: (SwitcherItem) -> Void
    let onUpdateDrag: () -> Void
    let onEndDrag: (SwitcherItem) -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var draggingWindowID: CGWindowID?
    @AppStorage(DefaultsKey.dockPreviewBackgroundOpacity) private var backgroundOpacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            if DockPreviewSupport.showsPanelHeader(isPinned: isPinned) {
                panelHeader
            }
            ScrollViewReader { proxy in
                ScrollView(stacksVertically ? .vertical : .horizontal, showsIndicators: false) {
                    cardRun {
                        ForEach(windows) { window in
                            DockPreviewCard(
                                window: window,
                                preview: window.previewWindowID.flatMap { previews[$0] },
                                isSelected: selectedWindowID == window.windowID,
                                isPanelPinned: isPinned,
                                onTogglePinned: onTogglePinned,
                                onCommit: {
                                    onCommit(window)
                                },
                                onClose: {
                                    onCloseWindow(window)
                                },
                                onToggleMinimized: {
                                    onToggleMinimized(window)
                                }
                            )
                            .id(window.id)
                            .gesture(
                                DragGesture(minimumDistance: DockPreviewSupport.dragLiftDistance,
                                            coordinateSpace: .global)
                                    .onChanged { _ in
                                        if draggingWindowID == nil {
                                            draggingWindowID = window.windowID
                                            onBeginDrag(window)
                                        }
                                        guard draggingWindowID == window.windowID else { return }
                                        onUpdateDrag()
                                    }
                                    .onEnded { _ in
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
                    .padding(.horizontal, DockPreviewSupport.panelPadding)
                    .padding(.bottom, DockPreviewSupport.panelPadding)
                    .padding(.top, showsHeader ? 0 : DockPreviewSupport.panelPadding)
                }
                // A panel that already shows every window has nothing to
                // scroll, and a scroll view that can move steals the drag that
                // carries a window out of the panel.
                .scrollDisabled(showsEveryWindow)
                .onChange(of: selectedWindowID) { _, selectedWindowID in
                    guard let selectedWindowID,
                          let selected = windows.first(where: { $0.windowID == selectedWindowID })
                    else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(selected.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: stacksVertically ? DockPreviewSupport.cardWidth
                   + DockPreviewSupport.panelPadding * 2 : nil,
               height: stacksVertically ? nil : cardRunHeight)
        .background(HUDBackdrop(cornerRadius: 18,
                                opacity: DockPreviewSupport.sanitizedBackgroundOpacity(backgroundOpacity)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // The hairline keeps its full strength as the material fades: it is what
        // still draws the panel's shape once the frost stops doing it.
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

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
        DockPreviewSupport.cardHeight + DockPreviewSupport.panelPadding * 2
            + (showsHeader ? DockPreviewSupport.panelHeaderHeight : 0)
    }

    @ViewBuilder
    private func cardRun<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if stacksVertically {
            VStack(spacing: DockPreviewSupport.cardSpacing) { content() }
        } else {
            HStack(spacing: DockPreviewSupport.cardSpacing) { content() }
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 7) {
            dragTitleArea
            windowNavigationButtons
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
    private var windowNavigationButtons: some View {
        if windows.count > 1 {
            HStack(spacing: 1) {
                Button {
                    onSelectPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .help(l10n.s.dockPreviewPreviousWindow)
                .accessibilityLabel(l10n.s.dockPreviewPreviousWindow)

                Button {
                    onSelectNext()
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
    let onCommit: () -> Void
    let onClose: () -> Void
    let onToggleMinimized: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var isMinimizeHovering = false
    @State private var suppressNextCommit = false

    private var showsPreviewControls: Bool {
        DockPreviewSupport.showsCardControls(isHovering: isHovering, isSelected: isSelected)
    }

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen || window.isOnHiddenSpace
    }

    private var showsAppBadge: Bool {
        DockPreviewSupport.showsCardAppBadge(hasPreview: preview != nil)
    }

    var body: some View {
        VStack(spacing: DockPreviewSupport.cardTitleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))

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
            .frame(width: DockPreviewSupport.cardThumbnailWidth,
                   height: DockPreviewSupport.cardThumbnailHeight)

            titleBand
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
            Label(l10n.s.dockPreviewCloseWindow, systemImage: "xmark.circle")
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
                               width: DockPreviewSupport.cardTitleTextWidth,
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
            }
        }
        .frame(width: DockPreviewSupport.cardThumbnailWidth,
               height: DockPreviewSupport.cardTitleHeight,
               alignment: .top)
    }

    @ViewBuilder
    private var statusBadges: some View {
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
        .help(l10n.s.dockPreviewCloseWindow)
        .accessibilityLabel(l10n.s.dockPreviewCloseWindow)
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
