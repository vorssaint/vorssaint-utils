// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SwitcherShortcutStrings {
    let allWindows: String
    let allWindowsCaption: String
}

extension FeatureStrings {
    static func switcherShortcuts(_ language: AppLanguage) -> SwitcherShortcutStrings {
        switch language {
        case .enUS:
            return .init(allWindows: "All windows",
                         allWindowsCaption: "Use a separate shortcut to cycle through windows from all apps in any layout. Your window filters still apply.")
        case .ptBR:
            return .init(allWindows: "Todas as janelas",
                         allWindowsCaption: "Use um atalho separado para percorrer janelas de todos os apps em qualquer layout. Os filtros de janelas continuam valendo.")
        case .tr:
            return .init(allWindows: "Tüm pencereler",
                         allWindowsCaption: "Her düzende tüm uygulamaların pencereleri arasında geçiş yapmak için ayrı bir kısayol kullanın. Pencere filtreleriniz geçerli kalır.")
        case .ru:
            return .init(allWindows: "Все окна",
                         allWindowsCaption: "Используйте отдельное сочетание клавиш для переключения между окнами всех приложений при любом виде переключателя. Фильтры окон продолжают действовать.")
        case .es:
            return .init(allWindows: "Todas las ventanas",
                         allWindowsCaption: "Usa un atajo independiente para recorrer las ventanas de todas las apps con cualquier diseño. Los filtros de ventanas siguen aplicándose.")
        case .sk:
            return .init(allWindows: "Všetky okná",
                         allWindowsCaption: "Samostatnou skratkou prepínajte medzi oknami všetkých aplikácií v ľubovoľnom rozložení. Filtre okien platia naďalej.")
        case .de:
            return .init(allWindows: "Alle Fenster",
                         allWindowsCaption: "Mit einem eigenen Tastenkürzel durch die Fenster aller Apps wechseln, in jedem Layout. Deine Fensterfilter gelten weiterhin.")
        case .fr:
            return .init(allWindows: "Toutes les fenêtres",
                         allWindowsCaption: "Utilisez un raccourci distinct pour parcourir les fenêtres de toutes les apps, quelle que soit la disposition. Vos filtres de fenêtres restent actifs.")
        case .it:
            return .init(allWindows: "Tutte le finestre",
                         allWindowsCaption: "Usa una scorciatoia separata per scorrere le finestre di tutte le app in qualsiasi layout. I filtri delle finestre restano attivi.")
        case .ja:
            return .init(allWindows: "すべてのウインドウ",
                         allWindowsCaption: "専用のショートカットで、どのレイアウトでもすべてのアプリのウインドウを順に切り替えます。ウインドウのフィルタは引き続き適用されます。")
        case .ko:
            return .init(allWindows: "모든 윈도우",
                         allWindowsCaption: "별도의 단축키로 모든 레이아웃에서 모든 앱의 윈도우를 차례로 전환합니다. 윈도우 필터는 계속 적용됩니다.")
        case .zhHans:
            return .init(allWindows: "所有窗口",
                         allWindowsCaption: "使用独立快捷键，在任意布局中依次切换所有应用的窗口。窗口筛选条件仍然适用。")
        case .zhTW:
            return .init(allWindows: "所有視窗",
                         allWindowsCaption: "使用獨立快捷鍵，在任何版面配置中依序切換所有 App 的視窗。視窗篩選條件仍然適用。")
        case .zhHK:
            return .init(allWindows: "所有視窗",
                         allWindowsCaption: "使用獨立快捷鍵，在任何版面配置中依次切換所有 App 的視窗。視窗篩選條件仍然適用。")
        case .uk:
            return .init(allWindows: "Усі вікна",
                         allWindowsCaption: "Використовуйте окреме сполучення клавіш для перемикання між вікнами всіх програм у будь-якому вигляді перемикача. Фільтри вікон діють і надалі.")
        }
    }
}
