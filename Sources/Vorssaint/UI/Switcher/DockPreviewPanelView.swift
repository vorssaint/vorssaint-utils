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
            onPreview: service.preview,
            onEndPreview: service.endPreview,
            onCommit: service.commit,
            onCloseWindow: service.close,
            onToggleMinimized: service.toggleMinimized,
            onTogglePinned: service.togglePinned,
            onClosePanel: service.closePreviewPanel,
            onSelectPrevious: service.selectPreviousWindow,
            onSelectNext: service.selectNextWindow
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
            onPreview: panel.preview,
            onEndPreview: panel.endPreview,
            onCommit: panel.commit,
            onCloseWindow: panel.close,
            onToggleMinimized: panel.toggleMinimized,
            onTogglePinned: panel.closePreviewPanel,
            onClosePanel: panel.closePreviewPanel,
            onSelectPrevious: panel.selectPreviousWindow,
            onSelectNext: panel.selectNextWindow
        )
    }
}

private struct DockPreviewPanelContent: View {
    let windows: [SwitcherItem]
    let previews: [CGWindowID: CGImage]
    let selectedWindowID: CGWindowID?
    let currentAppName: String?
    let isPinned: Bool
    let onPreview: (SwitcherItem) -> Void
    let onEndPreview: (SwitcherItem) -> Void
    let onCommit: (SwitcherItem) -> Void
    let onCloseWindow: (SwitcherItem) -> Void
    let onToggleMinimized: (SwitcherItem) -> Void
    let onTogglePinned: () -> Void
    let onClosePanel: () -> Void
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DockPreviewSupport.cardSpacing) {
                        ForEach(windows) { window in
                            DockPreviewCard(
                                window: window,
                                preview: window.previewWindowID.flatMap { previews[$0] },
                                isSelected: selectedWindowID == window.windowID,
                                isPanelPinned: isPinned,
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
                }
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
        .frame(height: DockPreviewSupport.panelSize(itemCount: 1,
                                                    screenVisibleFrame: CGRect(x: 0, y: 0, width: 500, height: 500)).height)
        .background(HUDBackdrop(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var panelHeader: some View {
        HStack(spacing: 7) {
            dragTitleArea
            windowNavigationButtons
            Button {
                onTogglePinned()
            } label: {
                Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            .help(isPinned ? l10n.s.dockPreviewUnpinPanel : l10n.s.dockPreviewPinPanel)
            .accessibilityLabel(isPinned ? l10n.s.dockPreviewUnpinPanel : l10n.s.dockPreviewPinPanel)
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
                if let icon = windows.first?.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(currentAppName ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
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
    let onCommit: () -> Void
    let onClose: () -> Void
    let onToggleMinimized: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var isMinimizeHovering = false
    @State private var suppressNextCommit = false

    private var showsPreviewControls: Bool {
        isHovering || isSelected || isPanelPinned
    }

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.07))

                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(4)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                }

                if preview != nil, let icon = window.appIcon {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                    }
                }

                if hasStatusBadges {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            statusBadges
                            Spacer()
                        }
                        .padding(6)
                    }
                }

                previewTitleBar
            }
            .frame(width: DockPreviewSupport.cardWidth - 18,
                   height: DockPreviewSupport.cardHeight - 54)

            VStack(spacing: 1) {
                Text(window.displaySubtitle ?? window.displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if window.displaySubtitle != nil {
                    Text(window.displayTitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 24, alignment: .top)
                .frame(maxWidth: DockPreviewSupport.cardWidth - 22)
        }
        .padding(9)
        .frame(width: DockPreviewSupport.cardWidth, height: DockPreviewSupport.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            cardContextMenu
        }
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: showsPreviewControls)
        .accessibilityLabel(window.accessibilityTitle)
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
        Button(role: .destructive) {
            onClose()
        } label: {
            Label(l10n.s.dockPreviewCloseWindow, systemImage: "xmark.circle")
        }
    }

    private var previewTitleBar: some View {
        VStack {
            HStack(spacing: 6) {
                Text(window.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color.white.opacity(0.92))
                if isPanelPinned, isSelected {
                    Text(l10n.s.dockPreviewPinned)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                Spacer(minLength: 2)
                closeButton
                minimizeButton
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.44))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
            .padding(.horizontal, 7)
            .padding(.top, 7)
            .opacity(showsPreviewControls ? 1 : 0)
            .allowsHitTesting(showsPreviewControls)
            Spacer()
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        if window.isMinimized {
            statusBadge(systemName: "minus.rectangle")
        }
        if window.isFullscreen {
            statusBadge(systemName: "arrow.up.left.and.arrow.down.right")
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
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(isCloseHovering ? 0.95 : 0.72),
                                 Color(red: 1.0, green: 0.38, blue: 0.33).opacity(isCloseHovering ? 1 : 0.92))
                .frame(width: 24, height: 24)
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
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(isMinimizeHovering ? 0.95 : 0.72),
                                 Color.black.opacity(isMinimizeHovering ? 0.58 : 0.46))
                .frame(width: 24, height: 24)
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
