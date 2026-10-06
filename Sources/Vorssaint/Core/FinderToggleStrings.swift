// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Finder toggle's own two fields, reached through `localized(_:)` rather
/// than through `FeatureStrings`: it is a single row's copy, the same shape as
/// `PointerDisplayStrings`, and it also supplies the `.toggleFinder` role's
/// display name so one table answers both surfaces and the two cannot drift.
struct FinderToggleStrings {
    /// Serves as the role name in the shortcut list as well as the row title,
    /// so the same words are never translated twice.
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> FinderToggleStrings {
        switch language {
        case .enUS: return .init(title: "Toggle Finder", caption: "Hides Finder, or brings it back.")
        case .ptBR: return .init(title: "Alternar Finder", caption: "Oculta o Finder ou o traz de volta.")
        case .tr: return .init(title: "Finder'ı aç/kapat", caption: "Finder'ı gizler veya geri getirir.")
        case .ru: return .init(title: "Переключить Finder", caption: "Скрывает Finder или возвращает его.")
        case .es: return .init(title: "Alternar Finder", caption: "Oculta Finder o lo vuelve a mostrar.")
        case .sk: return .init(title: "Prepnúť Finder", caption: "Skryje Finder alebo ho vráti späť.")
        case .de: return .init(title: "Finder ein-/ausblenden", caption: "Blendet Finder aus oder holt ihn zurück.")
        case .fr: return .init(title: "Basculer Finder", caption: "Masque Finder ou le ramène au premier plan.")
        case .it: return .init(title: "Mostra/nascondi Finder", caption: "Nasconde Finder o lo riporta in primo piano.")
        case .ja: return .init(title: "Finder の表示を切り替え", caption: "Finder を隠す、または再び前面に戻します。")
        case .ko: return .init(title: "Finder 표시 전환", caption: "Finder를 숨기거나 다시 앞으로 가져옵니다.")
        case .uk: return .init(title: "Перемкнути Finder", caption: "Ховає Finder або повертає його.")
        case .zhHans: return .init(title: "切换 Finder 显示", caption: "隐藏 Finder，或将其重新调回前台。")
        case .zhTW: return .init(title: "切換 Finder 顯示", caption: "隱藏 Finder，或將其重新調回前景。")
        case .zhHK: return .init(title: "切換 Finder 顯示", caption: "隱藏 Finder，或將其重新調回前景。")
        }
    }
}
