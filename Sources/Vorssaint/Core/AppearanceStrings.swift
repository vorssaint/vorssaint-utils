// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AppearanceStrings {
    let label: String
    let system: String
    let light: String
    let dark: String
}

extension FeatureStrings {
    static func appearance(_ language: AppLanguage) -> AppearanceStrings {
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

extension AppearanceStrings {
    static let enUS = AppearanceStrings(
        label: "Appearance",
        system: "System",
        light: "Light",
        dark: "Dark"
    )

    static let ptBR = AppearanceStrings(
        label: "Aparência",
        system: "Sistema",
        light: "Clara",
        dark: "Escura"
    )

    static let tr = AppearanceStrings(
        label: "Görünüm",
        system: "Sistem",
        light: "Açık",
        dark: "Koyu"
    )

    static let ru = AppearanceStrings(
        label: "Оформление",
        system: "Системное",
        light: "Светлое",
        dark: "Тёмное"
    )

    static let es = AppearanceStrings(
        label: "Apariencia",
        system: "Sistema",
        light: "Clara",
        dark: "Oscura"
    )

    static let de = AppearanceStrings(
        label: "Erscheinungsbild",
        system: "System",
        light: "Hell",
        dark: "Dunkel"
    )

    static let fr = AppearanceStrings(
        label: "Apparence",
        system: "Système",
        light: "Clair",
        dark: "Sombre"
    )

    static let it = AppearanceStrings(
        label: "Aspetto",
        system: "Sistema",
        light: "Chiaro",
        dark: "Scuro"
    )

    static let ja = AppearanceStrings(
        label: "外観",
        system: "システム",
        light: "ライト",
        dark: "ダーク"
    )

    static let ko = AppearanceStrings(
        label: "외관",
        system: "시스템",
        light: "밝게",
        dark: "어둡게"
    )

    static let zhHans = AppearanceStrings(
        label: "外观",
        system: "跟随系统",
        light: "浅色",
        dark: "深色"
    )

    static let zhTW = AppearanceStrings(
        label: "外觀",
        system: "跟隨系統",
        light: "淺色",
        dark: "深色"
    )

    static let zhHK = AppearanceStrings(
        label: "外觀",
        system: "跟隨系統",
        light: "淺色",
        dark: "深色"
    )
}
