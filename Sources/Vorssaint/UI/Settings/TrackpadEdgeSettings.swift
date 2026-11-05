// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct TrackpadEdgeSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = TrackpadEdgeService.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.trackpadEdgesEnabled) private var enabled = false
    @AppStorage(DefaultsKey.trackpadEdgeLeftAction) private var leftRaw = TrackpadEdge.left.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadEdgeRightAction) private var rightRaw = TrackpadEdge.right.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadEdgeTopAction) private var topRaw = TrackpadEdge.top.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadEdgeBottomAction) private var bottomRaw = TrackpadEdge.bottom.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadCornerTopLeftAction) private var topLeftRaw =
        TrackpadCorner.topLeft.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadCornerTopRightAction) private var topRightRaw =
        TrackpadCorner.topRight.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadCornerBottomLeftAction) private var bottomLeftRaw =
        TrackpadCorner.bottomLeft.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadCornerBottomRightAction) private var bottomRightRaw =
        TrackpadCorner.bottomRight.defaultAction.rawValue
    @AppStorage(DefaultsKey.trackpadEdgeMediaStripTap) private var mediaStripTap = true
    @AppStorage(DefaultsKey.trackpadEdgeWidth) private var edgeWidth = TrackpadEdgeConfiguration.defaultEdgeWidth
    @AppStorage(DefaultsKey.trackpadEdgeActiveArea) private var activeAreaRaw = TrackpadActiveArea.full.rawValue
    @AppStorage(DefaultsKey.trackpadEdgeSensitivity) private var sensitivityRaw = TrackpadSlideSensitivity.normal.rawValue
    @AppStorage(DefaultsKey.trackpadEdgePrecise) private var precise = false
    @AppStorage(DefaultsKey.trackpadEdgeHaptics) private var haptics = true
    @AppStorage(DefaultsKey.trackpadEdgeFreezeCursor) private var freezeCursor = true
    @AppStorage(DefaultsKey.trackpadEdgeModifier) private var modifierRaw = TrackpadEdgeModifier.none.rawValue
    @AppStorage(DefaultsKey.trackpadEdgeTapToSlide) private var tapToSlide = false

    private var text: TrackpadEdgeStrings { FeatureStrings.trackpadEdges(l10n.language) }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        resync()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TrackpadEdgeDiagram(configuration: configuration,
                                    strings: text,
                                    activeEdge: service.activeEdge,
                                    flashedTarget: service.flashedTarget)
                    .opacity(enabled ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.18), value: enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                Text(text.diagramHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                status
            }

            Section(text.edgesSection) {
                ForEach(TrackpadEdge.allCases) { edge in
                    slidePicker(edge)
                }
                if slideAction(.bottom) == .tracks {
                    Toggle(text.mediaStripToggle, isOn: $mediaStripTap)
                        .onChange(of: mediaStripTap) { _, _ in resync() }
                }
                Text(text.edgesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                captionedToggle(text.tapToSlideToggle, caption: text.tapToSlideCaption, isOn: $tapToSlide)
            }
            .disabled(!enabled)

            Section(text.cornersSection) {
                ForEach(TrackpadCorner.allCases) { corner in
                    cornerPicker(corner)
                }
                Text(text.cornersCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section(text.feelSection) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(text.edgeWidthLabel)
                        Spacer()
                        Text("\(Int((TrackpadEdgeConfiguration.sanitizedEdgeWidth(edgeWidth) * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: edgeWidthBinding,
                           in: TrackpadEdgeConfiguration.edgeWidthRange,
                           step: 0.01)
                    Text(text.edgeWidthCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(text.activeAreaLabel, selection: activeAreaBinding) {
                    ForEach(TrackpadActiveArea.allCases) { area in
                        Text(text.name(area)).tag(area)
                    }
                }
                Text(text.activeAreaCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(text.sensitivityLabel, selection: sensitivityBinding) {
                    ForEach(TrackpadSlideSensitivity.allCases) { sensitivity in
                        Text(text.name(sensitivity)).tag(sensitivity)
                    }
                }
                .pickerStyle(.segmented)
                captionedToggle(text.preciseToggle, caption: text.preciseCaption, isOn: $precise)
                captionedToggle(text.hapticsToggle, caption: text.hapticsCaption, isOn: $haptics)
                captionedToggle(text.freezeCursorToggle, caption: text.freezeCursorCaption, isOn: $freezeCursor)
                Picker(text.modifierLabel, selection: modifierBinding) {
                    ForEach(TrackpadEdgeModifier.allCases) { modifier in
                        Text(text.name(modifier)).tag(modifier)
                    }
                }
                Text(text.modifierCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        if enabled, service.touchDeviceMissing {
            Label(text.noTrackpad, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if enabled, service.isRunning {
            Label(text.activeNow, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
        Label(text.feedbackNote, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func captionedToggle(_ title: String, caption: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
                .onChange(of: isOn.wrappedValue) { _, _ in resync() }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func slidePicker(_ edge: TrackpadEdge) -> some View {
        let selected = slideAction(edge)
        let choices = TrackpadSlideAction.allCases.filter { action in
            action == selected || (isOffered(action) && (action != .tracks || !edge.isVertical))
        }
        return VStack(alignment: .leading, spacing: 2) {
            Picker(selection: slideBinding(edge)) {
                ForEach(choices) { action in
                    Label(text.name(action), systemImage: action.symbolName).tag(action)
                }
            } label: {
                Label(text.name(edge), systemImage: edgeSymbol(edge))
            }
            if let missing = selected.requiredFeature, !missing.isAvailable {
                missingFeatureNote(missing)
            }
        }
    }

    private func cornerPicker(_ corner: TrackpadCorner) -> some View {
        let selected = cornerAction(corner)
        let choices = TrackpadCornerAction.allCases.filter { action in
            action == selected || action.requiredFeature.map(\.isAvailable) != false
        }
        return VStack(alignment: .leading, spacing: 2) {
            Picker(selection: cornerBinding(corner)) {
                ForEach(choices) { action in
                    Label(text.name(action), systemImage: action.symbolName).tag(action)
                }
            } label: {
                Label(text.name(corner), systemImage: cornerSymbol(corner))
            }
            if let missing = selected.requiredFeature, !missing.isAvailable {
                missingFeatureNote(missing)
            }
        }
    }

    private func missingFeatureNote(_ feature: AppFeature) -> some View {
        Button {
            SettingsRouter.shared.request(FeatureSettingsDestination(.features), targetFeature: feature)
        } label: {
            Label(String(format: text.requiresFeatureFormat,
                         feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language))),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
    }

    private func isOffered(_ action: TrackpadSlideAction) -> Bool {
        if action == .keyboardBrightness { return BrightnessService.keyboardLightIsSupported }
        return action.requiredFeature.map(\.isAvailable) != false
    }

    private func edgeSymbol(_ edge: TrackpadEdge) -> String {
        switch edge {
        case .left: return "rectangle.lefthalf.inset.filled"
        case .right: return "rectangle.righthalf.inset.filled"
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }

    private func cornerSymbol(_ corner: TrackpadCorner) -> String {
        switch corner {
        case .topLeft: return "arrow.up.left.square"
        case .topRight: return "arrow.up.right.square"
        case .bottomLeft: return "arrow.down.left.square"
        case .bottomRight: return "arrow.down.right.square"
        }
    }

    private var configuration: TrackpadEdgeConfiguration {
        _ = features.revision
        return TrackpadEdgeConfiguration(
            slideActions: Dictionary(uniqueKeysWithValues: TrackpadEdge.allCases.map { ($0, slideAction($0)) }),
            cornerActions: Dictionary(uniqueKeysWithValues: TrackpadCorner.allCases.map { ($0, cornerAction($0)) }),
            mediaStripTap: mediaStripTap,
            edgeWidth: Float(TrackpadEdgeConfiguration.sanitizedEdgeWidth(edgeWidth)),
            activeArea: TrackpadActiveArea.sanitized(activeAreaRaw),
            sensitivity: TrackpadSlideSensitivity.sanitized(sensitivityRaw),
            precise: precise,
            tapToSlide: tapToSlide)
    }

    private func rawSlide(_ edge: TrackpadEdge) -> Binding<String> {
        switch edge {
        case .left: return $leftRaw
        case .right: return $rightRaw
        case .top: return $topRaw
        case .bottom: return $bottomRaw
        }
    }

    private func rawCorner(_ corner: TrackpadCorner) -> Binding<String> {
        switch corner {
        case .topLeft: return $topLeftRaw
        case .topRight: return $topRightRaw
        case .bottomLeft: return $bottomLeftRaw
        case .bottomRight: return $bottomRightRaw
        }
    }

    private func slideAction(_ edge: TrackpadEdge) -> TrackpadSlideAction {
        TrackpadSlideAction.sanitized(rawSlide(edge).wrappedValue, fallback: edge.defaultAction)
    }

    private func cornerAction(_ corner: TrackpadCorner) -> TrackpadCornerAction {
        TrackpadCornerAction.sanitized(rawCorner(corner).wrappedValue, fallback: corner.defaultAction)
    }

    private func slideBinding(_ edge: TrackpadEdge) -> Binding<TrackpadSlideAction> {
        Binding {
            slideAction(edge)
        } set: { action in
            rawSlide(edge).wrappedValue = action.rawValue
            resync()
        }
    }

    private func cornerBinding(_ corner: TrackpadCorner) -> Binding<TrackpadCornerAction> {
        Binding {
            cornerAction(corner)
        } set: { action in
            rawCorner(corner).wrappedValue = action.rawValue
            resync()
        }
    }

    private var edgeWidthBinding: Binding<Double> {
        Binding {
            TrackpadEdgeConfiguration.sanitizedEdgeWidth(edgeWidth)
        } set: { value in
            edgeWidth = TrackpadEdgeConfiguration.sanitizedEdgeWidth(value)
            resync()
        }
    }

    private var activeAreaBinding: Binding<TrackpadActiveArea> {
        Binding {
            TrackpadActiveArea.sanitized(activeAreaRaw)
        } set: { area in
            activeAreaRaw = area.rawValue
            resync()
        }
    }

    private var sensitivityBinding: Binding<TrackpadSlideSensitivity> {
        Binding {
            TrackpadSlideSensitivity.sanitized(sensitivityRaw)
        } set: { sensitivity in
            sensitivityRaw = sensitivity.rawValue
            resync()
        }
    }

    private var modifierBinding: Binding<TrackpadEdgeModifier> {
        Binding {
            TrackpadEdgeModifier.sanitized(modifierRaw)
        } set: { modifier in
            modifierRaw = modifier.rawValue
            resync()
        }
    }

    private func resync() {
        TrackpadEdgeService.shared.syncWithPreferences()
    }
}

struct TrackpadEdgeDiagram: View {
    let configuration: TrackpadEdgeConfiguration
    let strings: TrackpadEdgeStrings
    let activeEdge: TrackpadEdge?
    let flashedTarget: TrackpadTapTarget?

    private let size = CGSize(width: 320, height: 200)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14))
            ForEach(TrackpadEdge.allCases) { edge in
                band(edge)
            }
            if configuration.mediaStripArmed {
                badge(symbol: "playpause.fill", label: "2×",
                      highlighted: flashedTarget == .mediaStrip)
                    .position(x: size.width / 2,
                              y: size.height - bandThickness(.bottom) - 14)
            }
            ForEach(TrackpadCorner.allCases) { corner in
                cornerMarker(corner)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: activeEdge)
        .animation(.easeOut(duration: 0.2), value: flashedTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func bandThickness(_ edge: TrackpadEdge) -> CGFloat {
        edge.isVertical
            ? CGFloat(configuration.edgeWidth) * size.width
            : CGFloat(configuration.horizontalBand) * size.height
    }

    @ViewBuilder
    private func band(_ edge: TrackpadEdge) -> some View {
        let action = configuration.slideAction(edge)
        if action != .off {
            let thickness = max(bandThickness(edge), 8)
            let active = activeEdge == edge
            let activeHeight = size.height * CGFloat(configuration.activeArea.fraction)
            let frame: CGRect = {
                switch edge {
                case .left: return CGRect(x: 0, y: size.height - activeHeight, width: thickness, height: activeHeight)
                case .right: return CGRect(x: size.width - thickness, y: size.height - activeHeight,
                                           width: thickness, height: activeHeight)
                case .top: return CGRect(x: 0, y: 0, width: size.width, height: thickness)
                case .bottom: return CGRect(x: 0, y: size.height - thickness, width: size.width, height: thickness)
                }
            }()
            Rectangle()
                .fill(Color.accentColor.opacity(active ? 0.5 : 0.2))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            Image(systemName: action.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .position(iconPosition(edge, frame: frame))
        }
    }

    private func iconPosition(_ edge: TrackpadEdge, frame: CGRect) -> CGPoint {
        switch edge {
        case .left: return CGPoint(x: frame.maxX + 12, y: frame.midY)
        case .right: return CGPoint(x: frame.minX - 12, y: frame.midY)
        case .top: return CGPoint(x: frame.midX, y: frame.maxY + 12)
        case .bottom: return CGPoint(x: frame.midX - 44, y: frame.minY - 12)
        }
    }

    @ViewBuilder
    private func cornerMarker(_ corner: TrackpadCorner) -> some View {
        let action = configuration.cornerAction(corner)
        if action != .off {
            let inset: CGFloat = 26
            let x = corner.isLeft ? inset : size.width - inset
            let y = corner.isTop ? inset : size.height - inset
            badge(symbol: action.symbolName, label: "2×",
                  highlighted: flashedTarget == .corner(corner))
                .position(x: x, y: y)
                .help(strings.name(action))
        }
    }

    private func badge(symbol: String, label: String, highlighted: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(highlighted ? Color.white : Color.accentColor)
        .background(
            Capsule().fill(highlighted ? Color.accentColor : Color.accentColor.opacity(0.14))
        )
        .scaleEffect(highlighted ? 1.15 : 1)
    }

    private var accessibilitySummary: String {
        let edges = TrackpadEdge.allCases.compactMap { edge -> String? in
            let action = configuration.slideAction(edge)
            return action == .off ? nil : "\(strings.name(edge)): \(strings.name(action))"
        }
        let corners = TrackpadCorner.allCases.compactMap { corner -> String? in
            let action = configuration.cornerAction(corner)
            return action == .off ? nil : "\(strings.name(corner)): \(strings.name(action))"
        }
        return (edges + corners).joined(separator: ", ")
    }
}
