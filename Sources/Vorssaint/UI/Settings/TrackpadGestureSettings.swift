// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The trackpad gestures card on the Mouse page: the switch, one row per
/// gesture with the action it runs and why a gesture may be taken, and the
/// apps gestures leave alone. Actions are edited with the radial menu's own
/// action editor, so both offer the same catalog.
struct TrackpadGesturesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = TrackpadGestureService.shared
    @ObservedObject private var touch = TrackpadTouchService.shared
    @AppStorage(DefaultsKey.trackpadGesturesEnabled) private var enabled = false
    @AppStorage(DefaultsKey.trackpadGestureMappings) private var mappingsData: Data?
    @State private var editing: GestureEdit?

    private struct GestureEdit: Identifiable {
        let gesture: TrackpadGesture
        let item: RadialMenuItem
        let isNew: Bool
        var id: String { gesture.key }
    }

    private struct RowNote {
        let text: String
        let warning: Bool
        let offersFeatures: Bool
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
                VStack(alignment: .leading, spacing: 16) {
                    if touch.touchDeviceMissing {
                        caption(l10n.s.middleClickNoTrackpad, color: .orange)
                    }
                    ForEach([3, 4, 5], id: \.self) { fingers in
                        fingerGroup(fingers, mappings: current)
                    }
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
                             save: { store(.item($0), for: edit.gesture) },
                             delete: edit.isNew ? nil : { store(nil, for: edit.gesture) })
        }
    }

    // MARK: - Rows

    private func fingerGroup(_ fingers: Int, mappings: [TrackpadGesture: TriggerAction]) -> some View {
        let gestures = TrackpadGesture.all.filter { $0.fingers == fingers }
        // Three-finger drag takes the whole group; saying so once beats
        // repeating it under every row.
        let dragTakesAll = gestures.allSatisfy { service.systemClaims[$0] == .threeFingerDrag }
        return VStack(alignment: .leading, spacing: 6) {
            Text(fingerTitle(fingers))
                .font(.subheadline.weight(.medium))
            if dragTakesAll {
                caption(text.claimedThreeFingerDrag, color: .orange)
            }
            ForEach(gestures, id: \.key) { gesture in
                gestureRow(gesture, action: mappings[gesture], groupNoteShown: dragTakesAll)
            }
        }
    }

    private func gestureRow(_ gesture: TrackpadGesture, action: TriggerAction?,
                            groupNoteShown: Bool) -> some View {
        let owner = gesture.kind == .tap ? service.reservations[gesture.fingers] : nil
        let note = rowNote(gesture, action: action, owner: owner, groupNoteShown: groupNoteShown)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: gesture.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(kindTitle(gesture.kind))
                Spacer(minLength: 12)
                actionMenu(gesture, action: action)
                    .disabled(owner != nil)
            }
            if let note {
                caption(note.text, color: note.warning ? .orange : .secondary)
                    .padding(.leading, 26)
                if note.offersFeatures {
                    Button(text.openFeatures) {
                        SettingsRouter.shared.page = .features
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.leading, 26)
                }
            }
        }
    }

    /// One explanation per row, the most useful first: a tap another feature
    /// owns, then an action that cannot run, then a gesture macOS also uses.
    private func rowNote(_ gesture: TrackpadGesture, action: TriggerAction?,
                         owner: TrackpadTapOwner?, groupNoteShown: Bool) -> RowNote? {
        switch owner {
        case .middleClick?:
            return RowNote(text: text.ownedByMiddleClick, warning: false, offersFeatures: false)
        case .radialMenu?:
            return RowNote(text: text.ownedByRadialMenu, warning: false, offersFeatures: false)
        case nil:
            break
        }
        if let action, let problem = TriggerActionRunner.unavailability(action) {
            switch problem {
            case .featureMissing:
                return RowNote(text: text.unavailableFeature, warning: true, offersFeatures: true)
            case .targetMissing:
                return RowNote(text: text.unavailableTarget, warning: true, offersFeatures: false)
            case .systemShortcutOff:
                return RowNote(text: text.unavailableShortcut, warning: true, offersFeatures: false)
            }
        }
        guard !groupNoteShown, let claim = service.systemClaims[gesture] else { return nil }
        return RowNote(text: claimText(claim), warning: action != nil, offersFeatures: false)
    }

    private func actionMenu(_ gesture: TrackpadGesture, action: TriggerAction?) -> some View {
        let accessibilityName = kindTitle(gesture.kind) + ", " + text.actionLabel
        return Menu {
            Button(text.noAction) { store(nil, for: gesture) }
            Section {
                ForEach(MouseNavigationDirection.allCases, id: \.self) { direction in
                    Button {
                        store(.backForward(direction), for: gesture)
                    } label: {
                        Label(backForwardTitle(direction),
                              systemImage: direction == .back ? "chevron.left" : "chevron.right")
                    }
                }
            }
            Section(text.navigationSection) {
                ForEach(SpaceNavigation.allCases) { navigation in
                    Button {
                        store(.navigation(navigation), for: gesture)
                    } label: {
                        Label(navigationTitle(navigation), systemImage: navigation.symbolName)
                    }
                }
            }
            Divider()
            Button(text.otherAction) {
                if case .item(let item)? = action {
                    editing = GestureEdit(gesture: gesture, item: item, isNew: false)
                } else {
                    editing = GestureEdit(gesture: gesture, item: RadialMenuItem(kind: .shortcut), isNew: true)
                }
            }
        } label: {
            Text(actionTitle(action))
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityLabel(accessibilityName)
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

    private func claimText(_ claim: TrackpadSystemClaim) -> String {
        switch claim {
        case .moreGestures: return text.claimedMoreGestures
        case .lookUp: return text.claimedLookUp
        case .threeFingerDrag: return text.claimedThreeFingerDrag
        }
    }
}
