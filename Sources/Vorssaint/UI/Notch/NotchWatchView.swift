// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchWatchSettingsControls: View {
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchWatchEnabled) private var enabled = true
    @AppStorage(DefaultsKey.notchWatchSound) private var sound = true
    private var text: NotchWatchStrings { FeatureStrings.notchWatch(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.title, isOn: $enabled)
                .disabled(!AppFeature.notchWatch.isAvailable)
            Text(text.description).font(.caption).foregroundStyle(.secondary)
            if enabled {
                Toggle(text.sound, isOn: $sound)
                PermissionRow(kind: .screenRecording)
            }
        }
        .onChange(of: enabled) { NotchService.shared.syncWithPreferences() }
    }
}

/// The page: what to watch and the rule, the live area and its reading.
struct NotchWatchView: View {
    let size: CGSize
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchWatchEnabled) private var enabled = true
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchWatchStrings { FeatureStrings.notchWatch(l10n.language) }

    var body: some View {
        Group {
            if !enabled || watch.target == nil || preview {
                NotchWatchSetupView()
            } else {
                VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
                    header
                    NotchWatchAreaCard()
                        .frame(maxHeight: .infinity)
                    NotchWatchRuleRow()
                    footer
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if !preview { watch.pageVisible = true } }
        .onDisappear { if !preview { watch.pageVisible = false } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = watch.target?.appIcon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
            } else {
                Image(systemName: NotchModule.watch.symbol).foregroundStyle(NotchWatchStrip.tint)
            }
            Text(headerTitle).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            NotchIconButton(symbol: "viewfinder", title: text.chooseAgain) {
                NotchService.shared.perform { NotchWatchService.shared.chooseArea() }
            }
            NotchIconButton(symbol: "xmark", title: text.stop) { watch.stop() }
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(height: 24)
    }

    private var headerTitle: String {
        guard let target = watch.target else { return text.title }
        guard let title = target.windowTitle, title != target.appName else { return target.appName }
        return "\(target.appName) · \(title)"
    }

    @ViewBuilder private var footer: some View {
        if case .finished = watch.state {
            HStack(spacing: 8) {
                if watch.canWatchAgain {
                    NotchWatchPillButton(title: text.watchAgain, prominent: true) { watch.watchAgain() }
                }
                NotchWatchPillButton(title: text.chooseAgain, prominent: !watch.canWatchAgain) {
                    NotchService.shared.perform { NotchWatchService.shared.chooseArea() }
                }
                Spacer(minLength: 0)
            }
        } else if let started = watch.startedAt {
            Text(text.since(started.formatted(Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(l10n.language.formattingLocale()))))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// The live area with its reading below it, and what happened once the
/// watch ended.
private struct NotchWatchAreaCard: View {
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchWatchStrings { FeatureStrings.notchWatch(l10n.language) }

    private var lines: [String] { NotchWatchSupport.lines(in: watch.text) }

    /// What the island shows, picked automatically or chosen line by line
    /// when the automatic pick lands on the wrong words.
    private var headlineMenu: some View {
        Menu {
            Section(text.inIsland) {
                choice(text.automatic, selected: watch.headlineLine == nil) { watch.setHeadlineLine(nil) }
                ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { index, line in
                    choice(line, selected: watch.headlineLine == index) { watch.setHeadlineLine(index) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(watch.headline.isEmpty ? text.noText : watch.headline)
                    .monospacedDigit().lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.system(size: 15, weight: .semibold))
        .fixedSize()
        .help(text.inIsland)
        .accessibilityLabel(text.inIsland)
        .accessibilityValue(watch.headline)
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image = watch.preview {
                    Image(decorative: image, scale: 2)
                        .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(watch.state == .hidden ? 0.35 : 1)
                } else {
                    ProgressView().controlSize(.small)
                }
                if watch.state == .hidden {
                    Label(watch.permissionMissing ? text.permissionHint : text.hidden,
                          systemImage: watch.permissionMissing ? "lock" : "eye.slash")
                        .font(.caption).multilineTextAlignment(.center)
                        .padding(8)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if case .finished(let outcome) = watch.state {
                    Image(systemName: outcome == .closed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(outcome == .closed ? Color.secondary : Color.green)
                    Text(text.outcome(outcome)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                } else if lines.isEmpty {
                    Text(text.noText).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                } else {
                    headlineMenu
                }
                Spacer(minLength: 0)
            }
            let full = watch.text.replacingOccurrences(of: "\n", with: " ")
            if !full.isEmpty, full != watch.headline {
                Text(full).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// When to speak up. A word or a number applies once Return is pressed or
/// the field is left, so typing never ends the watch halfway. After a watch
/// ends the rule can still change, for the next Watch Again.
private struct NotchWatchRuleRow: View {
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draftText = ""
    @State private var draftNumber = ""
    @FocusState private var focused: Bool
    private var text: NotchWatchStrings { FeatureStrings.notchWatch(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(text.tellMe).font(.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(NotchWatchCondition.allCases) { condition in
                        Button { watch.setCondition(condition) } label: {
                            Label(text.condition(condition), systemImage: condition.symbol)
                        }
                    }
                } label: {
                    Label(text.condition(watch.condition), systemImage: watch.condition.symbol)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                if watch.condition == .contains || watch.condition == .reaches {
                    field
                }
                Spacer(minLength: 0)
            }
            if watch.condition == .settles {
                Text(text.settlesHint).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .onAppear {
            draftText = watch.matchText
            draftNumber = watch.matchNumber.map {
                NotchWatchSupport.formatted($0, locale: l10n.language.formattingLocale())
            } ?? ""
        }
    }

    private var field: some View {
        let number = watch.condition == .reaches
        return TextField(number ? text.numberPlaceholder : text.textPlaceholder,
                         text: number ? $draftNumber : $draftText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focused)
            .onSubmit(apply)
            .onChange(of: focused) { _, isFocused in if !isFocused { apply() } }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: 180)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.34 : 0), lineWidth: 1)
            }
            .accessibilityLabel(text.condition(watch.condition))
    }

    private func apply() {
        if watch.condition == .reaches { watch.setMatchNumber(draftNumber) } else { watch.setMatchText(draftText) }
    }
}

/// Before anything is watched: what the page does, and the one step that
/// starts it, in the same voice as the island's other empty pages.
private struct NotchWatchSetupView: View {
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchWatchEnabled) private var enabled = true
    /// The page follows a grant made in System Settings while it is shown;
    /// nothing checks for one while it is away.
    @State private var pollingDemandID = UUID()
    private var text: NotchWatchStrings { FeatureStrings.notchWatch(l10n.language) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                glyph
                copy.multilineTextAlignment(.center)
                actions
            }
            HStack(spacing: 16) {
                glyph
                VStack(alignment: .leading, spacing: 10) {
                    copy.multilineTextAlignment(.leading)
                    actions
                }
            }
        }
        .frame(maxWidth: 360)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { permissions.setActivePermissionSurface(pollingDemandID, visible: true) }
        .onDisappear { permissions.setActivePermissionSurface(pollingDemandID, visible: false) }
    }

    private var glyph: some View {
        Image(systemName: NotchModule.watch.symbol)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 56, height: 56)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var copy: some View {
        Text(!enabled ? text.description : permissions.screenRecording ? text.setupHint : text.permissionHint)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var actions: some View {
        if !enabled {
            if AppFeature.notchWatch.isAvailable {
                Toggle(text.title, isOn: $enabled)
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { NotchService.shared.syncWithPreferences() }
            }
        } else if !permissions.screenRecording {
            NotchWatchPillButton(title: text.allowAccess, prominent: true) {
                Permissions.shared.requestScreenRecording()
            }
        } else {
            NotchWatchPillButton(title: text.choose, prominent: true) {
                NotchService.shared.perform { NotchWatchService.shared.chooseArea() }
            }
        }
    }
}

private struct NotchWatchPillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .semibold : .medium))
                .foregroundStyle(.white.opacity(prominent ? 1 : 0.7))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(.white.opacity(prominent ? 0.14 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
    }
}

/// The area itself, small, where a reading would be when it holds no text.
struct NotchWatchThumbnail: View {
    let image: CGImage
    let height: CGFloat

    var body: some View {
        // Whole, so a bar shows how far it has filled.
        Image(decorative: image, scale: 2)
            .resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(width: NotchWatchSupport.thumbnailWidth, height: height)
            .accessibilityHidden(true)
    }
}

/// The watching eye, breathing like a working agent's mark while the area
/// is read, and still, crossed out, while its window is hidden. The motion
/// runs in the compositor and stops whenever the island is not on screen.
struct NotchWatchEye: View {
    let size: CGFloat
    var hidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchWatchEyeBridge(size: size, hidden: hidden, animates: !hidden && !reduceMotion)
            .frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct NotchWatchEyeBridge: NSViewRepresentable {
    let size: CGFloat
    let hidden: Bool
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        let image = NSImage(systemSymbolName: hidden ? "eye.slash" : "eye", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        view.configureGlyph(image: image, size: size, tint: NotchWatchStrip.eyeTint, animates: animates)
    }
    static func dismantleNSView(_ view: NotchAgentAnimationView, coordinator: ()) { view.stop() }
}

/// The eye at the left end and what the area reads at the right, each
/// anchored to its own edge so the silhouette's curve decides the margin.
struct NotchWatchStrip: View {
    static let tint = Color.purple
    /// Softer than the reading, so the mark does not outshine it.
    static let eyeTint = NSColor.systemPurple.withAlphaComponent(0.75)

    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    /// The size of a working agent's mark, which breathes the same way.
    private var iconSize: CGFloat {
        NotchTimerSupport.stripAgentMarkSize(height: geometry.compactActivityContentHeight, working: 1)
    }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2) }
    private var textInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) }

    var body: some View {
        Button { service.openActivity(.watch) } label: {
            HStack(spacing: 0) {
                NotchWatchEye(size: iconSize, hidden: watch.state == .hidden)
                    .padding(.leading, iconInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
                    .opacity(geometry.compactActivityWingWidth >= 28 ? 1 : 0)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                reading
                    .padding(.trailing, textInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                    .clipped()
            }
            .frame(height: geometry.compactActivityContentHeight)
            .padding(.horizontal, geometry.compactActivityHorizontalPadding)
            .padding(.top, geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FeatureStrings.notchWatch(l10n.language).title)
        .accessibilityValue(watch.headline)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    @ViewBuilder private var reading: some View {
        if geometry.compactActivityWingWidth < 36 {
            EmptyView()
        } else if watch.showsThumbnail, let preview = watch.preview {
            NotchWatchThumbnail(image: preview, height: max(8, geometry.compactActivityContentHeight - 6))
        } else if watch.headline.isEmpty {
            // A hidden window's slashed eye says enough until it is read.
            if watch.state != .hidden { ProgressView().controlSize(.mini) }
        } else {
            // A reading can change on every pass; rolling each change would
            // keep the closed island animating.
            Text(watch.headline)
                .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                .foregroundStyle(Self.tint)
                .lineLimit(1).minimumScaleFactor(0.7).truncationMode(.tail)
        }
    }
}
