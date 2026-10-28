// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Sidebar bounds and persistence. Toolbar and search geometry belong to macOS.
enum SettingsShellLayout {
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarDefaultWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 340
    /// Room the detail pane keeps beside the widest sidebar, so the sidebar's
    /// bounds win when the window is at its minimum width.
    static let minDetailWidth: CGFloat = 420

    static let sidebarWidthKey = DefaultsKey.settingsSidebarWidth

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sidebarMinWidth), sidebarMaxWidth)
    }

    /// 0 or less means unset; anything else is clamped to the range the
    /// divider itself allows.
    static func sidebarWidth(saved: Double) -> CGFloat {
        guard saved.isFinite, saved > 0 else { return sidebarDefaultWidth }
        return clampedSidebarWidth(CGFloat(saved))
    }

    static func storedSidebarWidth(defaults: UserDefaults = .standard) -> CGFloat {
        sidebarWidth(saved: defaults.double(forKey: sidebarWidthKey))
    }

    /// Stores a width the user chose, ignoring the sub-point jitter a drag
    /// reports, so the same position is not written over and over.
    static func storeSidebarWidth(_ width: CGFloat, defaults: UserDefaults = .standard) {
        let clamped = clampedSidebarWidth(width)
        guard abs(defaults.double(forKey: sidebarWidthKey) - Double(clamped)) > 0.5 else { return }
        defaults.set(Double(clamped), forKey: sidebarWidthKey)
    }
}

struct SettingsShellStrings {
    let suggestions: String
    let recents: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(suggestions: "Suggestions", recents: "Recents")
        case .ptBR:
            return Self(suggestions: "Sugestões", recents: "Recentes")
        case .tr:
            return Self(suggestions: "Öneriler", recents: "Son Kullanılanlar")
        case .ru:
            return Self(suggestions: "Предложения", recents: "Недавние")
        case .es:
            return Self(suggestions: "Sugerencias", recents: "Recientes")
        case .sk:
            return Self(suggestions: "Návrhy", recents: "Nedávne")
        case .de:
            return Self(suggestions: "Vorschläge", recents: "Zuletzt verwendet")
        case .fr:
            return Self(suggestions: "Suggestions", recents: "Récents")
        case .it:
            return Self(suggestions: "Suggerimenti", recents: "Recenti")
        case .ja:
            return Self(suggestions: "検索候補", recents: "最近使った項目")
        case .ko:
            return Self(suggestions: "제안", recents: "최근 항목")
        case .uk:
            return Self(suggestions: "Пропозиції", recents: "Нещодавні")
        case .zhHans:
            return Self(suggestions: "建议", recents: "最近使用")
        case .zhTW, .zhHK:
            return Self(suggestions: "建議", recents: "最近使用")
        }
    }
}
