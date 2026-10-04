// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TouchBarControl: String, CaseIterable, Hashable {
    case keepAwake
    case micMute
    case clipboard
    case systemMetrics
    case media
    case quickLauncher
    case killProcess

    var visibilityKey: String {
        switch self {
        case .keepAwake:
            return DefaultsKey.touchBarShowKeepAwake
        case .micMute:
            return DefaultsKey.touchBarShowMicMute
        case .clipboard:
            return DefaultsKey.touchBarShowClipboard
        case .systemMetrics:
            return DefaultsKey.touchBarShowSystemMetrics
        case .media:
            return DefaultsKey.touchBarShowMedia
        case .quickLauncher:
            return DefaultsKey.touchBarShowQuickLauncher
        case .killProcess:
            return DefaultsKey.touchBarShowKillProcess
        }
    }

    static var ordered: [TouchBarControl] {
        let defaultOrder = allCases.map(\.rawValue)
        let raw = UserDefaults.standard.string(
            forKey: DefaultsKey.touchBarControlOrder
        ) ?? ""

        return Defaults
            .sanitizedPanelItemOrder(raw, defaultOrder: defaultOrder)
            .compactMap(TouchBarControl.init(rawValue:))
    }

    static var visibleOrdered: [TouchBarControl] {
        ordered.filter {
            UserDefaults.standard.bool(forKey: $0.visibilityKey)
        }
    }

    static func setOrder(_ controls: [TouchBarControl]) {
        UserDefaults.standard.set(
            controls.map(\.rawValue).joined(separator: ","),
            forKey: DefaultsKey.touchBarControlOrder
        )
    }
}
