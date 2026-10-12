// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Moving between Spaces or opening an overview, replayed through the user's
/// own system shortcuts so remaps are honored. Raw values persist inside the
/// mappings blob; never rename them.
enum SpaceNavigation: String, Codable, CaseIterable, Identifiable {
    case spaceLeft, spaceRight, missionControl, appExpose

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .spaceLeft: return "arrow.left.square"
        case .spaceRight: return "arrow.right.square"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "macwindow.on.rectangle"
        }
    }
}

/// What a gesture runs: any action a radial-menu slice can hold, a Space
/// navigation, or Back and Forward in the app in front. Submenus have no
/// meaning outside the wheel and are refused.
enum TriggerAction: Equatable {
    case item(RadialMenuItem)
    case navigation(SpaceNavigation)
    case backForward(MouseNavigationDirection)
}

extension TriggerAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case item, navigation, backForward
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let navigation = try container.decodeIfPresent(SpaceNavigation.self, forKey: .navigation) {
            self = .navigation(navigation)
        } else if let direction = try container.decodeIfPresent(MouseNavigationDirection.self,
                                                                forKey: .backForward) {
            self = .backForward(direction)
        } else {
            self = .item(try container.decode(RadialMenuItem.self, forKey: .item))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .item(let item): try container.encode(item, forKey: .item)
        case .navigation(let navigation): try container.encode(navigation, forKey: .navigation)
        case .backForward(let direction): try container.encode(direction, forKey: .backForward)
        }
    }
}

/// Why a saved action cannot run right now. Settings shows it instead of
/// letting the gesture fail silently.
enum TriggerActionUnavailability: Equatable {
    /// The feature behind the action is uninstalled or switched off.
    case featureMissing(AppFeature)
    /// The application or file is no longer where it was picked.
    case targetMissing
    /// The system shortcut the navigation replays is switched off.
    case systemShortcutOff
}

/// The pure half of gesture mappings: how they persist and what may be
/// stored. Unknown gestures and dead actions are dropped on read, so a blob
/// written by a newer version or edited by hand never fires something broken.
enum TrackpadGestureMappingSupport {
    /// Keeps an action only when it can run. Item payloads are validated and
    /// normalized exactly as for a wheel slice.
    static func sanitized(_ action: TriggerAction) -> TriggerAction? {
        switch action {
        case .navigation, .backForward:
            return action
        case .item(let item):
            guard item.kind != .submenu,
                  var clean = RadialMenuSupport.sanitized([item]).first else { return nil }
            clean.children = []
            clean.customIconData = nil
            return .item(clean)
        }
    }

    static func decode(_ data: Data?) -> [TrackpadGesture: TriggerAction] {
        guard let data,
              let raw = try? JSONDecoder().decode([String: FailableTriggerAction].self, from: data)
        else { return [:] }
        var mappings: [TrackpadGesture: TriggerAction] = [:]
        for (key, entry) in raw {
            guard let gesture = TrackpadGesture(key: key),
                  let action = entry.value.flatMap(sanitized) else { continue }
            mappings[gesture] = action
        }
        return mappings
    }

    static func encode(_ mappings: [TrackpadGesture: TriggerAction]) -> Data? {
        var raw: [String: TriggerAction] = [:]
        for (gesture, action) in mappings {
            guard let clean = sanitized(action) else { continue }
            raw[gesture.key] = clean
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(raw)
    }

    /// Whether the action needs Accessibility to run: posting keys, moving
    /// windows, replaying Space shortcuts and pressing an app's Back or
    /// Forward all do.
    static func needsAccessibility(_ action: TriggerAction) -> Bool {
        switch action {
        case .navigation, .backForward: return true
        case .item(let item): return RadialMenuSupport.needsAccessibility([item])
        }
    }

    static func unavailability(_ action: TriggerAction,
                               isFeatureAvailable: (AppFeature) -> Bool,
                               boolFor: (String) -> Bool,
                               fileExists: (String) -> Bool,
                               systemShortcutExists: (SpaceNavigation) -> Bool) -> TriggerActionUnavailability? {
        switch action {
        case .navigation(let navigation):
            return systemShortcutExists(navigation) ? nil : .systemShortcutOff
        case .backForward:
            return nil
        case .item(let item):
            switch item.kind {
            case .tool:
                guard let tool = item.tool else { return .featureMissing(.radialMenu) }
                return tool.isRunnable(isFeatureAvailable: isFeatureAvailable, boolFor: boolFor)
                    ? nil : .featureMissing(tool.feature)
            case .quickToggle:
                return isFeatureAvailable(.quickToggles) ? nil : .featureMissing(.quickToggles)
            case .windowLayout:
                return isFeatureAvailable(.windowLayout) ? nil : .featureMissing(.windowLayout)
            case .app, .file:
                return fileExists((item.payload as NSString).expandingTildeInPath) ? nil : .targetMissing
            case .url, .shortcut, .media, .submenu:
                return nil
            }
        }
    }
}

/// Decodes one entry without failing the whole blob.
private struct FailableTriggerAction: Decodable {
    let value: TriggerAction?

    init(from decoder: Decoder) throws {
        value = try? TriggerAction(from: decoder)
    }
}
