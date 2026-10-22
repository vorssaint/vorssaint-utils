// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The trackpad gestures card on the Mouse page: the switch, one finger
/// count at a time with the action each gesture runs and what macOS does
/// with it, and the apps gestures leave alone. Actions are edited with the
/// radial menu's own action editor, so both offer the same catalog.
struct TrackpadGesturesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = TrackpadGestureService.shared
    @ObservedObject private var touch = TrackpadTouchService.shared
    @AppStorage(DefaultsKey.trackpadGesturesEnabled) private var enabled = false
    @AppStorage(DefaultsKey.trackpadGestureMappings) private var mappingsData: Data?
    @State private var fingers = 3
    @State private var editing: GestureEdit?

    private struct GestureEdit: Identifiable {
        let gesture: TrackpadGesture
        let item: RadialMenuItem
        let isNew: Bool
        var id: String { gesture.key }
    }

    private var text: TrackpadGestureStrings { FeatureStrings.trackpadGestures(l10n.language) }
    private var radialText: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var goText: SettingsNavigationStrings { .localized(l10n.language) }
    private var mappings: [TrackpadGesture: TriggerAction] {
        TrackpadGestureMappingSupport.decode(mappingsData)
    }

    var body: some View {
        SettingsCard(title: text.title) {
            SettingsRow(symbol: AppFeature.trackpadGestures.symbolName, title: text.enableLabel,
                        caption: text.enableCaption) {
                Toggle(text.enableLabel, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, on in
                        TrackpadGestureService.shared.syncWithPreferences()
                        if on, !permissions.accessibility { permissions.requestAccessibility() }
                    }
            }
            if enabled {
                let current = mappings
                VStack(alignment: .leading, spacing: 12) {
                    if touch.touchDeviceMissing {
                        caption(l10n.s.middleClickNoTrackpad, color: .orange)
                    }
                    HStack(spacing: 8) {
                        ForEach([3, 4, 5], id: \.self) { count in
                            fingerChip(count, mappings: current)
                        }
                    }
                    fingerGroup(fingers, mappings: current)
                }
                .padding(.leading, settingsRowTextInset)
                MouseExceptionsList(scope: .trackpadGestures)
            }
        }
        .onAppear { TrackpadGestureService.shared.refreshSystemClaims() }
        .sheet(item: $editing) { edit in
            RadialItemEditor(text: radialText,
                             item: edit.item,
                             isNew: edit.isNew,
                             allowsSubmenu: false,
                             targetsOnly: true,
                             save: { store(.item($0), for: edit.gesture) },
                             delete: edit.isNew ? nil : { store(nil, for: edit.gesture) })
        }
    }

    // MARK: - Groups

    /// One chip per finger count, with how many of its gestures run an action.
    private func fingerChip(_ count: Int, mappings: [TrackpadGesture: TriggerAction]) -> some View {
        let selected = fingers == count
        let mapped = mappings.keys.filter {
            $0.fingers == count && ($0.kind != .tap || service.reservations[count] == nil)
        }.count
        let title = mapped > 0 ? "\(fingerTitle(count)) · \(mapped)" : fingerTitle(count)
        return SettingsChip(title: title,
                            symbol: selected ? "\(count).circle.fill" : "\(count).circle",
                            selected: selected) { fingers = count }
    }

    private func fingerGroup(_ fingers: Int, mappings: [TrackpadGesture: TriggerAction]) -> some View {
        let gestures = TrackpadGesture.all.filter { $0.fingers == fingers }
        // Three-finger drag takes the whole group; saying so once beats
        // tagging every row.
        let dragTakesAll = gestures.allSatisfy { service.systemClaims[$0] == .threeFingerDrag }
        let tagged = !dragTakesAll && gestures.contains { systemName(service.systemClaims[$0]) != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text(fingerTitle(fingers))
                .font(.subheadline.weight(.medium))
            if dragTakesAll {
                caption(text.claimedThreeFingerDrag, color: .orange)
            }
            VStack(spacing: 0) {
                ForEach(Array(gestures.enumerated()), id: \.element.key) { index, gesture in
                    if index > 0 { Divider() }
                    gestureRow(gesture, action: mappings[gesture], showsClaim: !dragTakesAll)
                }
            }
            if tagged {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "apple.logo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    caption(text.systemFootnote, color: .secondary)
                    Button(text.openTrackpadSettings, action: openTrackpadSettings)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Rows

    private func gestureRow(_ gesture: TrackpadGesture, action: TriggerAction?,
                            showsClaim: Bool) -> some View {
        let owner = gesture.kind == .tap ? service.reservations[gesture.fingers] : nil
        let problem = owner == nil ? action.flatMap(TriggerActionRunner.unavailability) : nil
        let claimName = showsClaim && owner == nil ? systemName(service.systemClaims[gesture]) : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: gesture.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(kindTitle(gesture.kind))
                Spacer(minLength: 12)
                if let claimName {
                    systemTag(claimName, overridden: action != nil)
                }
                if let owner {
                    ownerValue(owner)
                } else {
                    actionMenu(gesture, action: action)
                }
            }
            if let problem {
                caption(problemText(problem), color: .orange)
                    .padding(.leading, 26)
                if case .featureMissing = problem {
                    Button(text.openFeatures) {
                        SettingsRouter.shared.page = .features
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// What macOS does with the gesture: a quiet mark while the gesture is
    /// free here, a warning once an action here runs on top of it.
    private func systemTag(_ name: String, overridden: Bool) -> some View {
        Label(overridden ? String(format: text.systemAlso, name) : "macOS · \(name)",
              systemImage: overridden ? "exclamationmark.triangle.fill" : "apple.logo")
            .font(.caption)
            .foregroundStyle(overridden ? Color.orange : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((overridden ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    /// A tap another feature owns, named with a way to its own settings.
    private func ownerValue(_ owner: TrackpadTapOwner) -> some View {
        let feature: AppFeature = owner == .middleClick ? .middleClick : .radialMenu
        return HStack(spacing: 6) {
            Text(owner == .middleClick ? l10n.s.middleClickSection : radialText.pageTitle)
                .foregroundStyle(.secondary)
            Button(text.change) {
                SettingsRouter.shared.request(feature.settingsDestination, sidebarFeature: feature)
            }
            .buttonStyle(.link)
        }
        .help(owner == .middleClick ? text.ownedByMiddleClick : text.ownedByRadialMenu)
    }

    /// Suggestions for the gesture's direction first, then every action by
    /// family, then the actions that need a target picked in the editor.
    private func actionMenu(_ gesture: TrackpadGesture, action: TriggerAction?) -> some View {
        let accessibilityName = kindTitle(gesture.kind) + ", " + text.actionLabel
        let windowText = FeatureStrings.windowLayout(l10n.language)
        let suggested = TrackpadGestureMappingSupport.suggestions(for: gesture.kind)
            .filter { TriggerActionRunner.unavailability($0) == nil }
        let tools = RadialMenuTool.allCases.filter { $0.isRunnable() }
        let mainLayouts = Self.layoutGroups.flatMap { $0 }
        return Menu {
            Button(text.noAction) { store(nil, for: gesture) }
            if !suggested.isEmpty {
                Section(text.suggested) {
                    ForEach(Array(suggested.enumerated()), id: \.offset) { _, choice in
                        choiceButton(choice, for: gesture)
                    }
                }
            }
            Divider()
            submenu(text.categoryNavigation, symbol: "arrow.left.arrow.right") {
                ForEach(MouseNavigationDirection.allCases, id: \.self) { direction in
                    choiceButton(.backForward(direction), for: gesture)
                }
            }
            // Window Layout missing still lists these: the row then says so
            // and offers the Features page.
            submenu(windowText.title, symbol: AppFeature.windowLayout.symbolName) {
                ForEach(Array(Self.layoutGroups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { layout in
                        choiceButton(TrackpadGestureMappingSupport.windowLayout(layout), for: gesture)
                    }
                }
                Divider()
                submenu(text.moreLayouts, symbol: "square.grid.3x3") {
                    ForEach(WindowLayoutAction.allCases.filter { !mainLayouts.contains($0) }) { layout in
                        choiceButton(TrackpadGestureMappingSupport.windowLayout(layout), for: gesture)
                    }
                }
            }
            submenu(text.navigationSection, symbol: "rectangle.3.group") {
                ForEach(SpaceNavigation.allCases) { navigation in
                    choiceButton(.navigation(navigation), for: gesture)
                }
            }
            submenu(radialText.kindMedia, symbol: "playpause") {
                ForEach(RadialMenuMediaKey.allCases) { key in
                    choiceButton(.item(RadialMenuItem(kind: .media, payload: key.rawValue)), for: gesture)
                }
            }
            if !tools.isEmpty {
                submenu(radialText.kindTool, symbol: "wrench.and.screwdriver") {
                    ForEach(tools) { tool in
                        choiceButton(.item(RadialMenuItem(kind: .tool, payload: tool.rawValue)), for: gesture)
                    }
                }
            }
            if AppFeature.quickToggles.isAvailable {
                submenu(FeatureStrings.quickToggles(l10n.language).pageTitle, symbol: "switch.2") {
                    ForEach(RadialMenuQuickToggle.allCases) { toggle in
                        choiceButton(.item(RadialMenuItem(kind: .quickToggle, payload: toggle.rawValue)),
                                     for: gesture)
                    }
                }
            }
            Divider()
            ForEach(Self.editedKinds, id: \.self) { kind in
                Button {
                    edit(kind, for: gesture, current: action)
                } label: {
                    Label(editedTitle(kind) + "…", systemImage: RadialMenuItem(kind: kind).defaultSymbolName)
                }
            }
        } label: {
            Text(actionTitle(action))
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityLabel(accessibilityName)
    }

    /// The window layouts listed first, in groups; the rest sit one level down.
    private static let layoutGroups: [[WindowLayoutAction]] = [
        [.minimize, .maximize, .fullScreen, .center, .restore],
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.previousDisplay, .nextDisplay],
    ]

    /// Actions whose target is picked in the editor sheet.
    private static let editedKinds: [RadialMenuItem.Kind] = [.shortcut, .app, .file, .url]

    private func submenu<Content: View>(_ title: String, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private func choiceButton(_ choice: TriggerAction, for gesture: TrackpadGesture) -> some View {
        Button {
            store(choice, for: gesture)
        } label: {
            Label(actionTitle(choice), systemImage: actionSymbol(choice))
        }
    }

    /// Opens the editor on the gesture's own action when it is of that kind,
    /// on a new one otherwise.
    private func edit(_ kind: RadialMenuItem.Kind, for gesture: TrackpadGesture, current action: TriggerAction?) {
        if case .item(let item)? = action, item.kind == kind {
            editing = GestureEdit(gesture: gesture, item: item, isNew: false)
        } else {
            editing = GestureEdit(gesture: gesture, item: RadialMenuItem(kind: kind), isNew: true)
        }
    }

    // MARK: - Storage

    private func store(_ action: TriggerAction?, for gesture: TrackpadGesture) {
        var updated = mappings
        updated[gesture] = action.flatMap(TrackpadGestureMappingSupport.sanitized)
        mappingsData = updated.isEmpty ? nil : TrackpadGestureMappingSupport.encode(updated)
        TrackpadGestureService.shared.syncWithPreferences()
        if let action, TrackpadGestureMappingSupport.needsAccessibility(action), !permissions.accessibility {
            permissions.requestAccessibility()
        }
    }

    private func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Text

    private func caption(_ string: String, color: Color) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fingerTitle(_ fingers: Int) -> String {
        switch fingers {
        case 3: return text.threeFingers
        case 4: return text.fourFingers
        default: return text.fiveFingers
        }
    }

    private func kindTitle(_ kind: TrackpadGestureKind) -> String {
        switch kind {
        case .tap: return text.kindTap
        case .swipeLeft: return text.kindSwipeLeft
        case .swipeRight: return text.kindSwipeRight
        case .swipeUp: return text.kindSwipeUp
        case .swipeDown: return text.kindSwipeDown
        case .pinchIn: return text.kindPinchIn
        case .pinchOut: return text.kindPinchOut
        }
    }

    private func navigationTitle(_ navigation: SpaceNavigation) -> String {
        switch navigation {
        case .spaceLeft: return text.spaceLeft
        case .spaceRight: return text.spaceRight
        case .missionControl: return text.missionControl
        case .appExpose: return text.appExpose
        }
    }

    /// The names the Settings Go menu already carries in every language.
    private func backForwardTitle(_ direction: MouseNavigationDirection) -> String {
        direction == .back ? goText.back : goText.forward
    }

    private func actionTitle(_ action: TriggerAction?) -> String {
        switch action {
        case nil: return text.noAction
        case .navigation(let navigation)?: return navigationTitle(navigation)
        case .backForward(let direction)?: return backForwardTitle(direction)
        case .item(let item)?: return item.displayName(radialText)
        }
    }

    private func actionSymbol(_ action: TriggerAction) -> String {
        switch action {
        case .navigation(let navigation): return navigation.symbolName
        case .backForward(let direction): return direction == .back ? "chevron.left" : "chevron.right"
        case .item(let item): return item.defaultSymbolName
        }
    }

    private func editedTitle(_ kind: RadialMenuItem.Kind) -> String {
        switch kind {
        case .app: return radialText.kindApp
        case .file: return radialText.kindFile
        case .url: return radialText.kindURL
        default: return radialText.kindShortcut
        }
    }

    private func problemText(_ problem: TriggerActionUnavailability) -> String {
        switch problem {
        case .featureMissing: return text.unavailableFeature
        case .targetMissing: return text.unavailableTarget
        case .systemShortcutOff: return text.unavailableShortcut
        }
    }

    /// The name of what macOS does with a gesture, nil when macOS leaves it
    /// free or three-finger drag takes the whole group.
    private func systemName(_ claim: TrackpadSystemClaim?) -> String? {
        switch claim {
        case .moreGestures(let action)?:
            switch action {
            case .spaces: return text.systemSpaces
            case .missionControl: return text.missionControl
            case .appExpose: return text.appExpose
            // macOS 26 replaced Launchpad with Apps under the same gesture.
            case .launchpad:
                return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
                    ? text.systemApps : "Launchpad"
            case .showDesktop: return text.systemShowDesktop
            }
        case .lookUp?: return text.systemLookUp
        case .threeFingerDrag?, nil: return nil
        }
    }
}
