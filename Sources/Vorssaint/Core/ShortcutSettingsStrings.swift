// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ShortcutSettingsStrings {
    let active: String
    let inactive: String
    let superKeyAlternativeFormat: String
}

extension FeatureStrings {
    static func shortcuts(_ language: AppLanguage) -> ShortcutSettingsStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension ShortcutSettingsStrings {
    static let enUS = ShortcutSettingsStrings(
        active: "Active",
        inactive: "Inactive",
        superKeyAlternativeFormat: "or %@"
    )

    static let ptBR = ShortcutSettingsStrings(
        active: "Ativo",
        inactive: "Inativo",
        superKeyAlternativeFormat: "ou %@"
    )

    static let tr = ShortcutSettingsStrings(
        active: "Etkin",
        inactive: "Etkin değil",
        superKeyAlternativeFormat: "veya %@"
    )

    static let ru = ShortcutSettingsStrings(
        active: "Активно",
        inactive: "Неактивно",
        superKeyAlternativeFormat: "или %@"
    )

    static let es = ShortcutSettingsStrings(
        active: "Activo",
        inactive: "Inactivo",
        superKeyAlternativeFormat: "o %@"
    )

    static let de = ShortcutSettingsStrings(
        active: "Aktiv",
        inactive: "Inaktiv",
        superKeyAlternativeFormat: "oder %@"
    )

    static let fr = ShortcutSettingsStrings(
        active: "Actif",
        inactive: "Inactif",
        superKeyAlternativeFormat: "ou %@"
    )

    static let it = ShortcutSettingsStrings(
        active: "Attiva",
        inactive: "Inattiva",
        superKeyAlternativeFormat: "oppure %@"
    )

    static let ja = ShortcutSettingsStrings(
        active: "有効",
        inactive: "無効",
        superKeyAlternativeFormat: "または %@"
    )

    static let ko = ShortcutSettingsStrings(
        active: "활성",
        inactive: "비활성",
        superKeyAlternativeFormat: "또는 %@"
    )

    static let zhHans = ShortcutSettingsStrings(
        active: "已启用",
        inactive: "未启用",
        superKeyAlternativeFormat: "或 %@"
    )

    static let zhTW = ShortcutSettingsStrings(
        active: "已啟用",
        inactive: "未啟用",
        superKeyAlternativeFormat: "或 %@"
    )

    static let zhHK = ShortcutSettingsStrings(
        active: "已啟用",
        inactive: "未啟用",
        superKeyAlternativeFormat: "或 %@"
    )
}
