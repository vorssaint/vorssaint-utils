// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

private enum SwitcherIconStyle {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceRaised = Color(nsColor: .windowBackgroundColor)
    static let tile = Color.primary.opacity(0.045)
    static let tileSelected = Color.accentColor.opacity(0.15)
    static let stroke = Color.primary.opacity(0.12)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
    static let thumbnailBackground = Color.primary.opacity(0.055)
}

/// Content of the switcher panel: a grid of large window cards with live
/// thumbnails, hover/keyboard selection and a springy highlight.
struct SwitcherView: View {
    @EnvironmentObject private var switcher: AppSwitcher
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.switcherIconRowMode) private var iconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var simpleMode = false
    @AppStorage(DefaultsKey.switcherShortcut) private var switcherShortcutStorage = GlobalShortcut.switcherDefault.storageValue
    @AppStorage(DefaultsKey.switcherWindowShortcut) private var switcherWindowShortcutStorage = GlobalShortcut.switcherWindowDefault.storageValue

    var body: some View {
        if SwitcherSupport.usesIconRowLayout(iconRowMode: iconRowMode,
                                             simpleMode: simpleMode),
           !switcher.windows.isEmpty {
            iconRowPanel
        } else {
            standardPanel
        }
    }

    private var standardPanel: some View {
        Group {
            if switcher.windows.isEmpty {
                emptyState
            } else {
                cardGrid
            }
        }
        .padding(SwitcherGrid.padding)
        .background(HUDBackdrop(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            searchChip
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if switcher.searchQuery.isEmpty {
            Text(l10n.s.switcherNoWindows)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(switcher.searchQuery)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: SwitcherGrid.cardWidth - 36)
                Text("0/\(switcher.totalWindowCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iconRowPanel: some View {
        iconRowSwitcher
            .frame(width: iconRowPanelSize.width,
                   height: iconRowPanelSize.height,
                   alignment: .center)
            .overlay(alignment: .topTrailing) {
                searchChip
            }
    }

    @ViewBuilder
    private var searchChip: some View {
        if !switcher.searchQuery.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .bold))
                Text(switcher.searchQuery)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                Text("\(switcher.windows.count)/\(switcher.totalWindowCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.42))
            )
            .padding(12)
        }
    }

    private var cardGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(SwitcherGrid.cardWidth),
                                                       spacing: SwitcherGrid.spacing),
                                   count: switcher.grid.columns),
                    spacing: SwitcherGrid.spacing
                ) {
                    ForEach(Array(switcher.windows.enumerated()), id: \.element.id) { index, window in
                        WindowCard(window: window,
                                   preview: window.previewWindowID.flatMap { switcher.previews[$0] },
                                   isSelected: index == switcher.selectedIndex,
                                   onCommit: {
                                       switcher.select(index: index)
                                       switcher.commitSession()
                                   },
                                   onClose: {
                                       switcher.closeWindow(window)
                                   })
                            .id(window.id)
                            .onHover { hovering in
                                if hovering { switcher.hoverSelect(index: index) }
                            }
                    }
                }
            }
            .scrollDisabled(switcher.grid.rows <= switcher.grid.visibleRows)
            .onChange(of: switcher.selectedIndex) { _, newIndex in
                guard switcher.windows.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(switcher.windows[newIndex].id, anchor: nil)
                }
            }
        }
    }

    private var iconRowSwitcher: some View {
        VStack(spacing: 0) {
            if simpleMode {
                selectedAppTitlePanel
                Spacer()
                    .frame(height: SwitcherIconRowLayout.simpleTitleGap)
            } else {
                selectedAppPreviewPanel
                Spacer()
                    .frame(height: SwitcherIconRowLayout.previewGap)
            }
            iconRowSurface
            Spacer()
                .frame(height: SwitcherIconRowLayout.hintGap)
            shortcutHintBar
        }
        .padding(SwitcherIconRowLayout.padding)
    }

    private var iconRowPanelSize: CGSize {
        simpleMode ? switcher.iconRowLayout.simplePanelSize : switcher.iconRowLayout.panelSize
    }

    private var shortcutHintBar: some View {
        let shortcut = GlobalShortcut(storageValue: switcherShortcutStorage) ?? .switcherDefault
        let windowShortcut = GlobalShortcut(storageValue: switcherWindowShortcutStorage) ?? .switcherWindowDefault
        let hints = SwitcherSupport.shortcutHints(for: shortcut, windowShortcut: windowShortcut)
        return HStack(spacing: 12) {
            shortcutHint(label: l10n.s.switcherShortcutHintApps, value: hints.apps)
            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.18))
            shortcutHint(label: l10n.s.switcherShortcutHintWindows, value: hints.windows)
        }
        .padding(.horizontal, 12)
        .frame(width: min(SwitcherIconRowLayout.hintBarWidth, iconRowContentWidth),
               height: SwitcherIconRowLayout.hintHeight)
        .background(
            Capsule(style: .continuous)
                .fill(SwitcherIconStyle.surfaceRaised)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func shortcutHint(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SwitcherIconStyle.secondaryText)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(SwitcherIconStyle.text)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var selectedAppPreviewPanel: some View {
        if let selected = selectedWindow {
            let appWindows = selectedAppWindows
            let placement = selectedPreviewPlacement
            ZStack(alignment: .topLeading) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        if let icon = selected.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(selected.appName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwitcherIconStyle.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(selected.displayTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SwitcherIconStyle.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Text("\(appWindows.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SwitcherIconStyle.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(SwitcherIconStyle.tile))
                    }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SwitcherIconRowLayout.spacing) {
                                ForEach(appWindows, id: \.element.id) { index, window in
                                    SwitcherWindowPreviewTile(window: window,
                                                              preview: window.previewWindowID.flatMap { switcher.previews[$0] },
                                                              isSelected: index == switcher.selectedIndex,
                                                              onCommit: {
                                                                  switcher.select(index: index)
                                                                  switcher.commitSession()
                                                              },
                                                              onClose: {
                                                                  switcher.closeWindow(window)
                                                              })
                                        .id(window.id)
                                        .onHover { hovering in
                                            if hovering { switcher.hoverSelect(index: index) }
                                        }
                                    }
                                }
                            .frame(height: SwitcherIconRowLayout.previewCardHeight, alignment: .center)
                        }
                        .scrollDisabled(appWindows.count <= Int(switcher.iconRowLayout.previewContentWidth / SwitcherIconRowLayout.previewCardWidth))
                        .frame(width: switcher.iconRowLayout.previewContentWidth,
                               height: SwitcherIconRowLayout.previewCardHeight)
                        .onChange(of: switcher.selectedIndex) { _, newIndex in
                            guard switcher.windows.indices.contains(newIndex) else { return }
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(switcher.windows[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
                .padding(SwitcherIconRowLayout.previewPanelPadding)
                .frame(width: switcher.iconRowLayout.previewSurfaceWidth,
                       height: SwitcherIconRowLayout.previewHeight)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SwitcherIconStyle.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(SwitcherIconStyle.stroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 5)
                .offset(x: placement.leading)
            }
            .frame(width: placement.contentWidth,
                   height: SwitcherIconRowLayout.previewHeight,
                   alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var selectedAppTitlePanel: some View {
        if let selected = selectedWindow {
            let appWindows = selectedAppWindows
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let icon = selected.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(selected.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SwitcherIconStyle.text)
                        .lineLimit(1)
                    Text("\(appWindows.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SwitcherIconStyle.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(SwitcherIconStyle.tile))
                    Text(selected.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SwitcherIconStyle.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(appWindows, id: \.element.id) { entry in
                                SwitcherWindowTitleChip(
                                    window: entry.element,
                                    isSelected: entry.offset == switcher.selectedIndex,
                                    onSelect: {
                                        switcher.select(index: entry.offset)
                                        switcher.commitSession()
                                    },
                                    onHover: { hovering in
                                        if hovering { switcher.hoverSelect(index: entry.offset) }
                                    }
                                )
                                .id(entry.element.id)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .onChange(of: switcher.selectedIndex) { _, newIndex in
                        guard switcher.windows.indices.contains(newIndex) else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(switcher.windows[newIndex].id, anchor: .center)
                        }
                    }
                }
                .frame(height: 25 * SwitcherIconRowLayout.scale)
            }
            .padding(10 * SwitcherIconRowLayout.scale)
            .frame(width: iconRowContentWidth,
                   height: SwitcherIconRowLayout.simpleTitleHeight,
                   alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(SwitcherIconStyle.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(SwitcherIconStyle.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
    }

    private var iconRowSurface: some View {
        iconRow
            .padding(.horizontal, SwitcherIconRowLayout.rowHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SwitcherIconStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(SwitcherIconStyle.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
            .frame(width: switcher.iconRowLayout.appRowSurfaceWidth,
                   height: SwitcherIconRowLayout.rowHeight)
    }

    private var iconRow: some View {
        let groups = appGroups
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: SwitcherIconRowLayout.spacing) {
                    ForEach(groups) { group in
                        let index = group.representativeIndex
                        let window = switcher.windows[index]
                        SwitcherIconTile(window: window,
                                         windowCount: group.windowCount,
                                         isSelected: group.pid == selectedWindow?.pid,
                                         onCommit: {
                                             switcher.select(index: index)
                                             switcher.commitSession()
                                         })
                            .id(group.id)
                            .onHover { hovering in
                                if hovering { switcher.hoverSelect(index: index) }
                            }
                    }
                }
                .padding(.horizontal, 2)
                .frame(height: SwitcherIconRowLayout.rowHeight, alignment: .center)
            }
            .scrollDisabled(groups.count <= switcher.iconRowLayout.visibleIconCount)
            .frame(width: switcher.iconRowLayout.appRowContentWidth,
                   height: SwitcherIconRowLayout.rowHeight)
            .onChange(of: switcher.selectedIndex) { _, newIndex in
                guard switcher.windows.indices.contains(newIndex) else { return }
                let pid = switcher.windows[newIndex].pid
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(pid, anchor: .center)
                }
            }
        }
    }

    private var selectedWindow: SwitcherItem? {
        guard switcher.windows.indices.contains(switcher.selectedIndex) else { return nil }
        return switcher.windows[switcher.selectedIndex]
    }

    private var selectedAppWindows: [(offset: Int, element: SwitcherItem)] {
        guard let selectedWindow else { return [] }
        return Array(switcher.windows.enumerated()).filter { $0.element.pid == selectedWindow.pid }
    }

    private var appGroups: [SwitcherAppGroup] {
        SwitcherSupport.appGroups(items: switcher.windows)
    }

    private var iconRowContentWidth: CGFloat {
        if simpleMode {
            return max(switcher.iconRowLayout.appRowSurfaceWidth,
                       SwitcherIconRowLayout.hintBarWidth)
        }
        return max(switcher.iconRowLayout.appRowSurfaceWidth,
                   switcher.iconRowLayout.previewSurfaceWidth,
                   SwitcherIconRowLayout.hintBarWidth)
    }

    private var selectedPreviewPlacement: SwitcherIconRowPreviewPlacement {
        let groups = appGroups
        let selectedIndex = selectedWindow
            .flatMap { selected in groups.firstIndex { $0.pid == selected.pid } }
            ?? 0
        return SwitcherSupport.selectedPreviewPlacement(
            appCount: groups.count,
            selectedAppIndex: selectedIndex,
            selectedWindowIndex: selectedAppWindows.firstIndex { $0.offset == switcher.selectedIndex } ?? 0,
            selectedWindowCount: selectedAppWindows.count,
            visibleIconCount: switcher.iconRowLayout.visibleIconCount,
            appRowContentWidth: switcher.iconRowLayout.appRowContentWidth,
            appRowSurfaceWidth: switcher.iconRowLayout.appRowSurfaceWidth,
            previewContentWidth: switcher.iconRowLayout.previewContentWidth,
            previewSurfaceWidth: switcher.iconRowLayout.previewSurfaceWidth
        )
    }
}

private struct SwitcherWindowTitleChip: View {
    let window: SwitcherItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if window.isMinimized {
                Image(systemName: "minus.rectangle")
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(window.displayTitle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: SwitcherIconRowLayout.simpleTitleChipMaxWidth)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? SwitcherIconStyle.tileSelected : SwitcherIconStyle.tile)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : SwitcherIconStyle.stroke,
                              lineWidth: isSelected ? 1.15 : 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
        .accessibilityLabel(window.accessibilityTitle)
    }
}

private struct SwitcherIconTile: View {
    let window: SwitcherItem
    let windowCount: Int
    let isSelected: Bool
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isSelected ? SwitcherIconRowLayout.selectedIconSize : SwitcherIconRowLayout.iconSize,
                               height: isSelected ? SwitcherIconRowLayout.selectedIconSize : SwitcherIconRowLayout.iconSize)
                }
                if windowCount > 1 {
                    Text("\(windowCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Color.accentColor))
                        .offset(x: -2, y: 2)
                } else if window.isMinimized || window.isFullscreen {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .offset(x: 1, y: -1)
                }
            }
            .frame(width: SwitcherIconRowLayout.selectedIconSize,
                   height: SwitcherIconRowLayout.selectedIconSize,
                   alignment: .bottom)
            Text(window.appName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: SwitcherIconRowLayout.iconLabelWidth)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? SwitcherIconStyle.tileSelected : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.92) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onCommit)
        .scaleEffect(isSelected ? 1 : 0.96)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
        .accessibilityLabel(window.appName)
    }
}

private struct SwitcherWindowPreviewTile: View {
    let window: SwitcherItem
    let preview: CGImage?
    let isSelected: Bool
    let onCommit: () -> Void
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var suppressNextCommit = false

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen
    }

    private var showsCloseButton: Bool {
        isHovering && window.windowID != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SwitcherIconStyle.thumbnailBackground)

                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(5)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                }

                if hasStatusBadges {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
                            statusBadges
                            Spacer()
                        }
                        .padding(7)
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
            .frame(width: SwitcherIconRowLayout.previewCardWidth - 16,
                   height: SwitcherIconRowLayout.previewCardHeight - 38)

            Text(window.displayTitle)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: SwitcherIconRowLayout.previewCardWidth - 20)
        }
        .padding(8)
        .frame(width: SwitcherIconRowLayout.previewCardWidth,
               height: SwitcherIconRowLayout.previewCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? SwitcherIconStyle.tileSelected : SwitcherIconStyle.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : SwitcherIconStyle.stroke,
                              lineWidth: isSelected ? 1.25 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: showsCloseButton)
        .accessibilityLabel(window.accessibilityTitle)
    }

    @ViewBuilder
    private var closeButton: some View {
        if showsCloseButton {
            Button {
                suppressNextCommit = true
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    suppressNextCommit = false
                }
            } label: {
                Image(systemName: isCloseHovering ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCloseHovering ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
            .help(l10n.s.dockPreviewCloseWindow)
            .accessibilityLabel(l10n.s.dockPreviewCloseWindow)
            .onHover { isCloseHovering = $0 }
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 4) {
            if window.isMinimized {
                statusBadge(systemName: "minus.rectangle")
            }
            if window.isFullscreen {
                statusBadge(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
    }

    private func statusBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 20, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.46))
            )
            .accessibilityHidden(true)
    }
}

private struct WindowCard: View {
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
        isHovering && window.windowID != nil
    }

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(5)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                }

                // Small app badge over the thumbnail corner.
                if preview != nil, let icon = window.appIcon {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .shadow(radius: 3)
                                .padding(7)
                        }
                    }
                }

                if hasStatusBadges {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
                            statusBadges
                            Spacer()
                        }
                        .padding(7)
                    }
                }

                VStack {
                    HStack {
                        closeButton
                            .padding(6)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: SwitcherGrid.cardWidth - 20,
                   height: SwitcherGrid.cardHeight - 72)

            VStack(spacing: 2) {
                Text(window.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if let subtitle = window.displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 29, alignment: .top)
                .frame(maxWidth: SwitcherGrid.cardWidth - 28)
        }
        .padding(10)
        .frame(width: SwitcherGrid.cardWidth, height: SwitcherGrid.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: showsCloseButton)
        .accessibilityLabel(window.accessibilityTitle)
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
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 22, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                .font(.system(size: 19, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(isCloseHovering ? 0.95 : 0.72),
                                 Color(red: 1.0, green: 0.38, blue: 0.33).opacity(isCloseHovering ? 1 : 0.92))
                .frame(width: 26, height: 26)
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
