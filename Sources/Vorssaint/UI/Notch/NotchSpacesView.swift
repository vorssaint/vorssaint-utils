// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchSpacesView: View {
    @ObservedObject private var spaces = NotchSpacesService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchSpacesStrings { FeatureStrings.notchSpaces(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if spaces.snapshot.spaces.isEmpty {
                    NotchEmptyView(symbol: NotchModule.spaces.symbol, message: text.unavailable)
                } else {
                    Text(spaces.snapshot.displayName).font(.caption).foregroundStyle(.secondary)
                    ForEach(spaces.snapshot.spaces) { space in
                        HStack(spacing: 10) {
                            Button { NotchService.shared.switchSpace(space.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: space.desktopNumber == nil ? "rectangle.inset.filled" : "rectangle")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(space.title(text)).lineLimit(1)
                                        if UserDefaults.standard.bool(forKey: DefaultsKey.notchSpacesAllDisplays) {
                                            Text(space.displayName).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if space.current { Image(systemName: "checkmark.circle.fill") }
                                }
                                .padding(10)
                                .background(space.current ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(space.current || spaces.switching || !permissions.accessibility)
                            .accessibilityAddTraits(space.current ? .isSelected : [])
                            if space.nameKey != nil {
                                Button { presentRename(space) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.plain)
                                .help(text.rename)
                                .accessibilityLabel(text.rename)
                            }
                        }
                    }
                    Text(text.gestureHint).font(.caption).foregroundStyle(.secondary)
                }
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                } else if spaces.shortcutUnavailable {
                    Text(text.shortcutHint).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { spaces.refresh() }
    }

    private func presentRename(_ space: NotchSpace) {
        DispatchQueue.main.async {
            let field = NSTextField(string: space.name ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            let alert = NSAlert()
            alert.messageText = text.rename
            alert.accessoryView = field
            alert.addButton(withTitle: text.rename)
            alert.addButton(withTitle: FeatureStrings.scratchpad(l10n.language).cancel)
            alert.addButton(withTitle: text.resetName)
            alert.window.initialFirstResponder = field
            switch NotchIslandAlert.run(alert, above: NotchService.shared.presentationWindow) {
            case .alertFirstButtonReturn: spaces.rename(space, to: field.stringValue)
            case .alertThirdButtonReturn: spaces.rename(space, to: "")
            default: break
            }
        }
    }
}

struct NotchSpacesSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchSpacesEnabled) private var enabled = true
    @AppStorage(DefaultsKey.notchSpacesShowCurrent) private var showCurrent = false
    @AppStorage(DefaultsKey.notchSpacesIdleEnabled) private var showWhenIdle = false
    private var text: NotchSpacesStrings { FeatureStrings.notchSpaces(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.title, isOn: $enabled)
            Text(text.description).font(.caption).foregroundStyle(.secondary)
            if enabled {
                Toggle(text.showWhenIdle, isOn: $showWhenIdle)
                Toggle(text.showCurrent, isOn: $showCurrent)
                Text(text.shortcutHint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: enabled) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: showWhenIdle) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: showCurrent) { _, _ in NotchService.shared.refreshPresentation() }
    }
}

struct NotchSpacesStrip: View {
    @ObservedObject var service: NotchService
    var size: CGSize? = nil
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var spaces = NotchSpacesService.shared
    @ObservedObject private var l10n = L10n.shared

    @AppStorage(DefaultsKey.notchSpacesAllDisplays) private var allDisplays = false

    @Environment(\.displayScale) private var displayScale

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var others: [NotchSpace] { spaces.snapshot.spaces.filter { $0.id != spaces.snapshot.current?.id } }

    var body: some View {
        let height = geometry.compactActivityContentHeight
        let title = spaces.snapshot.current?.compactLabel ?? ""
        let badgeHeight = NotchSpacesLayout.badgeHeight(contentHeight: height)
        let edgeInset = geometry.compactActivityEdgeInset(
            boxHeight: badgeHeight, radius: badgeHeight / 2,
            gap: NotchSpacesLayout.edgeGap(contentHeight: height))
        Group {
            if NotchSpacesSupport.isExternalDisplay(frame: geometry.screen) {
                let width = size?.width ?? geometry.compactActivitySize.width
                let inset = geometry.floats
                    ? NotchCapsuleLayout.side(geometry) + NotchSpacesLayout.edgeGap(contentHeight: height) : edgeInset
                expandedSpaces(width: width, height: badgeHeight, inset: inset)
                    .frame(width: width, height: size?.height ?? height)
            } else if let size {
                let layout = NotchCapsuleLayout.self
                HStack(spacing: layout.spacing) {
                    current(title, height: badgeHeight)
                        .frame(width: NotchSpacesLayout.labelWidth(title))
                    if !others.isEmpty {
                        otherSpaces(height: badgeHeight, width: NotchSpacesLayout.listWidth(spaces: others))
                            .frame(width: NotchSpacesLayout.listWidth(spaces: others))
                    }
                }
                .padding(.horizontal, layout.side(geometry) + layout.endPadding)
                .frame(width: size.width, height: size.height)
            } else {
                let wing = geometry.compactActivityWingWidth
                HStack(spacing: 0) {
                    Group {
                        if others.isEmpty {
                            Button { service.openActivity(.spaces) } label: {
                                Image(systemName: NotchModule.spaces.symbol)
                            }.buttonStyle(.plain)
                        } else {
                            otherSpaces(height: badgeHeight, width: max(0, wing - edgeInset))
                        }
                    }
                    .padding(.leading, edgeInset)
                    .frame(width: wing, alignment: .leading)
                    .opacity(wing >= 36 ? 1 : 0)
                    Color.clear.frame(width: geometry.compactActivityCameraGap)
                    current(title, height: badgeHeight)
                        .padding(.trailing, edgeInset)
                        .frame(width: wing, alignment: .trailing)
                        .clipped()
                        .opacity(wing >= 36 ? 1 : 0)
                }
                .frame(height: height)
                .padding(.horizontal, geometry.compactActivityHorizontalPadding)
                .padding(.top, geometry.compactActivityTopPadding)
            }
        }
        .background {
            Button { service.open() } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FeatureStrings.notch(l10n.language).open)
        }
        .accessibilityIdentifier("notch.spaces")
    }

    private func expandedSpaces(width: CGFloat, height: CGFloat, inset: CGFloat) -> some View {
        let row = spaces.snapshot.spaces
        let inset = (inset * displayScale).rounded(.up) / displayScale
        let available = max(0, width - inset * 2)
        let dividerPadding = row.reduce(CGFloat.zero) { $0 + displayDividerPadding(before: $1, in: row) }
        let pill = NotchSpacesLayout.expandedPillWidth(available: available - dividerPadding,
                                                     count: row.count, scale: displayScale)
        let contentWidth = pill * CGFloat(row.count) + NotchSpacesLayout.spacing * CGFloat(max(0, row.count - 1))
            + dividerPadding
        let pills = HStack(spacing: NotchSpacesLayout.spacing) {
            ForEach(row) { space in
                Button {
                    if space.current { service.open() }
                    else { service.switchSpace(space.id) }
                } label: {
                    Text(space.compactLabel)
                        .font(.system(size: NotchSpacesLayout.badgeFontSize, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 7)
                        .frame(width: pill, height: height)
                        .background(Color.white.opacity(space.current ? 0.16 : 0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(space.current ? 0.4 : 0), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(spaces.switching && !space.current)
                .accessibilityLabel(space.currentLabel(FeatureStrings.notchSpaces(l10n.language)))
                .accessibilityAddTraits(space.current ? .isSelected : [])
                .help(space.currentLabel(FeatureStrings.notchSpaces(l10n.language)))
                .overlay(alignment: .leading) {
                    displayDivider(before: space, in: row, height: height)
                }
                .padding(.leading, displayDividerPadding(before: space, in: row))
            }
        }
        return Group {
            if contentWidth <= available {
                pills.frame(width: available, height: height, alignment: .center)
            } else {
                NotchSpacesScrollView(width: available, height: height) { pills }
            }
        }
        .padding(.horizontal, inset)
    }

    private func displayDividerPadding(before space: NotchSpace, in row: [NotchSpace]) -> CGFloat {
        guard allDisplays, let index = row.firstIndex(where: { $0.id == space.id }), index > 0,
              let display = space.displayID, let previousDisplay = row[index - 1].displayID,
              display != previousDisplay else { return 0 }
        return 13 - NotchSpacesLayout.spacing
    }

    private func displayDivider(before space: NotchSpace, in row: [NotchSpace], height: CGFloat) -> some View {
        let padding = displayDividerPadding(before: space, in: row)
        return Group {
            if padding > 0 {
                Rectangle().fill(.white.opacity(0.3))
                    .frame(width: 1, height: max(0, height - 6))
                    .offset(x: -(NotchSpacesLayout.spacing + padding + 1) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func current(_ title: String, height: CGFloat) -> some View {
        let fullTitle = spaces.currentTitle(language: l10n.language)
        return Button { service.open() } label: {
            Text(title).font(.system(size: NotchSpacesLayout.badgeFontSize, weight: .semibold)).monospacedDigit()
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 7)
                .frame(height: height)
                .background(Color.white.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fullTitle)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .help(fullTitle)
    }

    private func otherSpaces(height: CGFloat, width: CGFloat) -> some View {
        NotchSpacesScrollView(width: width, height: height) {
            HStack(spacing: NotchSpacesLayout.spacing) {
                ForEach(others) { space in
                    Button { service.switchSpace(space.id) } label: {
                        Text(space.compactLabel)
                            .font(.system(size: NotchSpacesLayout.badgeFontSize, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).truncationMode(.tail)
                            .padding(.horizontal, 7)
                            .frame(height: height)
                            .frame(maxWidth: NotchSpacesLayout.badgeWidth)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(spaces.switching)
                    .accessibilityLabel(space.currentLabel(FeatureStrings.notchSpaces(l10n.language)))
                    .help(space.currentLabel(FeatureStrings.notchSpaces(l10n.language)))
                    .overlay(alignment: .leading) {
                        displayDivider(before: space, in: others, height: height)
                    }
                    .padding(.leading, displayDividerPadding(before: space, in: others))
                }
            }
            .frame(minWidth: width, alignment: .leading)
            .background {
                Button { service.open() } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(FeatureStrings.notch(l10n.language).open)
            }
        }
    }
}

private struct NotchSpacesScrollView<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var coordinateSpace = UUID()
    @State private var contentBounds = CGRect.zero

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: NotchSpacesScrollBounds.self,
                                               value: proxy.frame(in: .named(coordinateSpace)))
                    }
                }
        }
        .scrollIndicators(.never)
        .coordinateSpace(name: coordinateSpace)
        .frame(width: width, height: height)
        .onPreferenceChange(NotchSpacesScrollBounds.self) { contentBounds = $0 }
        .overlay(alignment: .bottomLeading) {
            if contentBounds.width > width + 0.5, width > 0 {
                let thumb = min(width, max(12, width * width / contentBounds.width))
                let progress = min(1, max(0, -contentBounds.minX / (contentBounds.width - width)))
                Capsule().fill(.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.45))
                            .frame(width: thumb)
                            .offset(x: progress * (width - thumb))
                    }
                    .frame(height: 2)
                    .offset(y: 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct NotchSpacesScrollBounds: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
