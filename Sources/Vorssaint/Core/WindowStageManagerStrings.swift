// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct WindowStageManagerStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> WindowStageManagerStrings {
        switch language {
        case .enUS: return .init(title: "Reserve space for Stage Manager", caption: "Keep recent apps visible when maximizing or arranging windows, while Stage Manager and Show recent apps are on.")
        case .ptBR: return .init(title: "Reservar espaço para o Organizador Visual", caption: "Mantenha os apps recentes visíveis ao maximizar ou organizar janelas, quando o Organizador Visual e Mostrar apps recentes estiverem ativados.")
        case .tr: return .init(title: "Sahne Yöneticisi için yer ayır", caption: "Sahne Yöneticisi ve Son uygulamaları göster açıkken pencereleri büyütürken veya düzenlerken son uygulamaları görünür tutar.")
        case .ru: return .init(title: "Оставлять место для Постановщика", caption: "Сохраняет недавние приложения видимыми при разворачивании и размещении окон, если Постановщик и показ недавних приложений включены.")
        case .es: return .init(title: "Reservar espacio para el Organizador Visual", caption: "Mantiene las apps recientes visibles al maximizar u organizar ventanas, cuando el Organizador Visual y Mostrar apps recientes están activados.")
        case .sk: return .init(title: "Vyhradiť miesto pre Stage Manager", caption: "Pri maximalizovaní alebo usporiadaní okien ponechá nedávne apky viditeľné, keď je zapnutý Stage Manager a zobrazovanie nedávnych apiek.")
        case .de: return .init(title: "Platz für Stage Manager reservieren", caption: "Hält zuletzt verwendete Apps beim Maximieren oder Anordnen von Fenstern sichtbar, wenn Stage Manager und die Anzeige letzter Apps aktiviert sind.")
        case .fr: return .init(title: "Réserver de l’espace pour Stage Manager", caption: "Garde les apps récentes visibles lors de l’agrandissement ou de l’organisation des fenêtres, si Stage Manager et l’affichage des apps récentes sont activés.")
        case .it: return .init(title: "Riserva spazio per Stage Manager", caption: "Mantiene visibili le app recenti quando ingrandisci o disponi le finestre, se Stage Manager e Mostra app recenti sono attivi.")
        case .ja: return .init(title: "ステージマネージャの領域を確保", caption: "ステージマネージャと最近使ったアプリケーションの表示が有効な場合、ウインドウを最大化・配置しても最近使ったアプリを表示したままにします。")
        case .ko: return .init(title: "스테이지 매니저 공간 확보", caption: "스테이지 매니저와 최근 사용한 앱 표시가 켜져 있으면 윈도우를 최대화하거나 배치할 때 최근 앱을 계속 표시합니다.")
        case .zhHans: return .init(title: "为台前调度预留空间", caption: "开启台前调度和显示最近使用的 App 时，最大化或排列窗口仍保留最近使用的 App 列表。")
        case .zhTW: return .init(title: "為幕前調度保留空間", caption: "開啟幕前調度和顯示最近使用的 App 時，最大化或排列視窗仍保留最近使用的 App 列表。")
        case .zhHK: return .init(title: "為幕前調度預留空間", caption: "開啟幕前調度和顯示最近使用的 App 時，最大化或排列視窗仍保留最近使用的 App 列表。")
        case .uk: return .init(title: "Залишати місце для Постановника", caption: "Зберігає недавні програми видимими під час розгортання й упорядкування вікон, якщо Постановник і показ недавніх програм увімкнені.")
        }
    }
}
