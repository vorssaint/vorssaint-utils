// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AppearanceStrings {
    let label: String
    let system: String
    let light: String
    let dark: String
    let liquidGlass: String
    let accentColor: String
    let accentColorCaption: String
    let accentColorSystem: String
    let accentColorFollowSystem: String
}

extension FeatureStrings {
    static func appearance(_ language: AppLanguage) -> AppearanceStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension AppearanceStrings {
    static let enUS = AppearanceStrings(
        label: "Appearance",
        system: "System",
        light: "Light",
        dark: "Dark",
        liquidGlass: "Liquid Glass",
        accentColor: "Accent colour",
        accentColorCaption: "The colour Vorssaint uses for buttons, selections and highlights in its own windows.",
        accentColorSystem: "System",
        accentColorFollowSystem: "Follow the Mac"
    )

    static let ptBR = AppearanceStrings(
        label: "Aparência",
        system: "Sistema",
        light: "Clara",
        dark: "Escura",
        liquidGlass: "Liquid Glass",
        accentColor: "Cor de destaque",
        accentColorCaption: "A cor que o Vorssaint usa em botões, seleções e destaques nas suas próprias janelas.",
        accentColorSystem: "Sistema",
        accentColorFollowSystem: "Seguir o Mac"
    )

    static let tr = AppearanceStrings(
        label: "Görünüm",
        system: "Sistem",
        light: "Açık",
        dark: "Koyu",
        liquidGlass: "Liquid Glass",
        accentColor: "Vurgu rengi",
        accentColorCaption: "Vorssaint’in kendi pencerelerinde düğmeler, seçimler ve vurgular için kullandığı renk.",
        accentColorSystem: "Sistem",
        accentColorFollowSystem: "Mac’i takip et"
    )

    static let ru = AppearanceStrings(
        label: "Оформление",
        system: "Системное",
        light: "Светлое",
        dark: "Тёмное",
        liquidGlass: "Liquid Glass",
        accentColor: "Акцентный цвет",
        accentColorCaption: "Цвет, который Vorssaint использует для кнопок, выделения и акцентов в собственных окнах.",
        accentColorSystem: "Системное",
        accentColorFollowSystem: "Как на Mac"
    )

    static let es = AppearanceStrings(
        label: "Apariencia",
        system: "Sistema",
        light: "Clara",
        dark: "Oscura",
        liquidGlass: "Liquid Glass",
        accentColor: "Color de acento",
        accentColorCaption: "El color que Vorssaint usa en botones, selecciones y resaltados de sus propias ventanas.",
        accentColorSystem: "Sistema",
        accentColorFollowSystem: "Seguir el Mac"
    )

    static let sk = AppearanceStrings(
        label: "Vzhľad",
        system: "Systémový",
        light: "Svetlý",
        dark: "Tmavý",
        liquidGlass: "Liquid Glass",
        accentColor: "Farebný akcent",
        accentColorCaption: "Farba, ktorú Vorssaint používa na tlačidlá, výbery a zvýraznenia vo vlastných oknách.",
        accentColorSystem: "Systémový",
        accentColorFollowSystem: "Podľa systému Mac"
    )

    static let de = AppearanceStrings(
        label: "Erscheinungsbild",
        system: "System",
        light: "Hell",
        dark: "Dunkel",
        liquidGlass: "Liquid Glass",
        accentColor: "Akzentfarbe",
        accentColorCaption: "Die Farbe, die Vorssaint für Schaltflächen, Auswahlen und Hervorhebungen in eigenen Fenstern nutzt.",
        accentColorSystem: "System",
        accentColorFollowSystem: "Dem Mac folgen"
    )

    static let fr = AppearanceStrings(
        label: "Apparence",
        system: "Système",
        light: "Clair",
        dark: "Sombre",
        liquidGlass: "Liquid Glass",
        accentColor: "Couleur d’accentuation",
        accentColorCaption: "La couleur que Vorssaint utilise pour les boutons, sélections et surlignages dans ses propres fenêtres.",
        accentColorSystem: "Système",
        accentColorFollowSystem: "Suivre le Mac"
    )

    static let it = AppearanceStrings(
        label: "Aspetto",
        system: "Sistema",
        light: "Chiaro",
        dark: "Scuro",
        liquidGlass: "Liquid Glass",
        accentColor: "Colore principale",
        accentColorCaption: "Il colore che Vorssaint usa per pulsanti, selezioni ed evidenziazioni nelle proprie finestre.",
        accentColorSystem: "Sistema",
        accentColorFollowSystem: "Segui il Mac"
    )

    static let ja = AppearanceStrings(
        label: "外観",
        system: "システム",
        light: "ライト",
        dark: "ダーク",
        liquidGlass: "Liquid Glass",
        accentColor: "アクセントカラー",
        accentColorCaption: "Vorssaint が自身のウインドウのボタン、選択、ハイライトに使う色です。",
        accentColorSystem: "システム",
        accentColorFollowSystem: "Mac に合わせる"
    )

    static let ko = AppearanceStrings(
        label: "외관",
        system: "시스템",
        light: "밝게",
        dark: "어둡게",
        liquidGlass: "Liquid Glass",
        accentColor: "강조 색상",
        accentColorCaption: "Vorssaint가 자체 윈도우의 버튼, 선택, 강조 표시에 사용하는 색상입니다.",
        accentColorSystem: "시스템",
        accentColorFollowSystem: "Mac 따르기"
    )

    static let zhHans = AppearanceStrings(
        label: "外观",
        system: "跟随系统",
        light: "浅色",
        dark: "深色",
        liquidGlass: "Liquid Glass",
        accentColor: "强调色",
        accentColorCaption: "Vorssaint 在自身窗口中用于按钮、选中项和高亮的颜色。",
        accentColorSystem: "跟随系统",
        accentColorFollowSystem: "跟随 Mac"
    )

    static let zhTW = AppearanceStrings(
        label: "外觀",
        system: "跟隨系統",
        light: "淺色",
        dark: "深色",
        liquidGlass: "Liquid Glass",
        accentColor: "強調色",
        accentColorCaption: "Vorssaint 在自身視窗中用於按鈕、選取項目和醒目標示的顏色。",
        accentColorSystem: "跟隨系統",
        accentColorFollowSystem: "跟隨 Mac"
    )

    static let zhHK = AppearanceStrings(
        label: "外觀",
        system: "跟隨系統",
        light: "淺色",
        dark: "深色",
        liquidGlass: "Liquid Glass",
        accentColor: "強調色",
        accentColorCaption: "Vorssaint 在自身視窗中用於按鈕、選取項目和醒目標示的顏色。",
        accentColorSystem: "跟隨系統",
        accentColorFollowSystem: "跟隨 Mac"
    )
    static let uk = AppearanceStrings(
        label: "Вигляд",
        system: "Система",
        light: "Світлий",
        dark: "Темний",
        liquidGlass: "Liquid Glass",
        accentColor: "Акцентний колір",
        accentColorCaption: "Колір, який Vorssaint використовує для кнопок, виділення та підсвічування у власних вікнах.",
        accentColorSystem: "Система",
        accentColorFollowSystem: "Як на Mac"
    )
}
