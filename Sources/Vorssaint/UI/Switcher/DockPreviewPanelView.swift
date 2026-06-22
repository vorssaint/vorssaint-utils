// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DockPreviewPanelView: View {
    @ObservedObject var service: DockPreviewService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DockPreviewSupport.cardSpacing) {
                ForEach(service.windows) { window in
                    DockPreviewCard(
                        window: window,
                        preview: window.previewWindowID.flatMap { service.previews[$0] },
                        isSelected: service.selectedWindowID == window.windowID,
                        onCommit: {
                            service.commit(window)
                        },
                        onClose: {
                            service.close(window)
                        }
                    )
                    .onHover { hovering in
                        if hovering {
                            service.preview(window)
                        } else {
                            service.endPreview(window)
                        }
                    }
                }
            }
            .padding(DockPreviewSupport.panelPadding)
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
}

private struct DockPreviewCard: View {
    let window: SwitcherItem
    let preview: CGImage?
    let isSelected: Bool
    let onCommit: () -> Void
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var suppressNextCommit = false

    private var showsCloseButton: Bool {
        isHovering || isSelected
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

                VStack {
                    HStack {
                        closeButton
                            .padding(5)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: DockPreviewSupport.cardWidth - 18,
                   height: DockPreviewSupport.cardHeight - 42)

            Text(window.displayTitle)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
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
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: showsCloseButton)
        .accessibilityLabel(window.displayTitle)
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
        .opacity(showsCloseButton ? 1 : 0)
        .allowsHitTesting(showsCloseButton)
        .onHover { isCloseHovering = $0 }
        .help(l10n.s.dockPreviewCloseWindow)
        .accessibilityLabel(l10n.s.dockPreviewCloseWindow)
    }
}
