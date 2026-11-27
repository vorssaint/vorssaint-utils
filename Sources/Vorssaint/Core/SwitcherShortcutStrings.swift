// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SwitcherShortcutStrings {
    let allWindows: String
    let allWindowsCaption: String
    let appLayout: String
    let windowLayout: String
    let windowLayoutCaption: String
    let sameAsAppLayout: String
}

extension FeatureStrings {
    static func switcherShortcuts(_ language: AppLanguage) -> SwitcherShortcutStrings {
        switch language {
        case .enUS:
            return .init(allWindows: "All windows",
                         allWindowsCaption: "Use a separate shortcut to cycle through windows from all apps in any layout. Your window filters still apply.",
                         appLayout: "App switching layout",
                         windowLayout: "Window switching layout",
                         windowLayoutCaption: "Used by the shortcuts for the current app’s windows and all windows.",
                         sameAsAppLayout: "Same as app switching")
        case .ptBR:
            return .init(allWindows: "Todas as janelas",
                         allWindowsCaption: "Use um atalho separado para percorrer janelas de todos os apps em qualquer layout. Os filtros de janelas continuam valendo.",
                         appLayout: "Layout da alternância de apps",
                         windowLayout: "Layout da alternância de janelas",
                         windowLayoutCaption: "Usado pelos atalhos de janelas do app atual e de todas as janelas.",
                         sameAsAppLayout: "Mesmo da alternância de apps")
        case .tr:
            return .init(allWindows: "Tüm pencereler",
                         allWindowsCaption: "Her düzende tüm uygulamaların pencereleri arasında geçiş yapmak için ayrı bir kısayol kullanın. Pencere filtreleriniz geçerli kalır.",
                         appLayout: "Uygulama değiştirme düzeni",
                         windowLayout: "Pencere değiştirme düzeni",
                         windowLayoutCaption: "Geçerli uygulamanın pencereleri ve tüm pencereler için kullanılan kısayollarda geçerlidir.",
                         sameAsAppLayout: "Uygulama değiştirmeyle aynı")
        case .ru:
            return .init(allWindows: "Все окна",
                         allWindowsCaption: "Используйте отдельное сочетание клавиш для переключения между окнами всех приложений при любом виде переключателя. Фильтры окон продолжают действовать.",
                         appLayout: "Вид переключателя приложений",
                         windowLayout: "Вид переключателя окон",
                         windowLayoutCaption: "Используется для переключения между окнами текущего приложения и между всеми окнами.",
                         sameAsAppLayout: "Как при переключении приложений")
        case .es:
            return .init(allWindows: "Todas las ventanas",
                         allWindowsCaption: "Usa un atajo independiente para recorrer las ventanas de todas las apps con cualquier diseño. Los filtros de ventanas siguen aplicándose.",
                         appLayout: "Diseño del selector de apps",
                         windowLayout: "Diseño del selector de ventanas",
                         windowLayoutCaption: "Se usa en los atajos de las ventanas de la app actual y de todas las ventanas.",
                         sameAsAppLayout: "Igual que al cambiar de app")
        case .sk:
            return .init(allWindows: "Všetky okná",
                         allWindowsCaption: "Samostatnou skratkou prepínajte medzi oknami všetkých aplikácií v ľubovoľnom rozložení. Filtre okien platia naďalej.",
                         appLayout: "Rozloženie prepínača aplikácií",
                         windowLayout: "Rozloženie prepínača okien",
                         windowLayoutCaption: "Používa sa pri prepínaní okien aktuálnej aplikácie aj všetkých okien.",
                         sameAsAppLayout: "Rovnaké ako pri prepínaní aplikácií")
        case .de:
            return .init(allWindows: "Alle Fenster",
                         allWindowsCaption: "Mit einem eigenen Tastenkürzel durch die Fenster aller Apps wechseln, in jedem Layout. Deine Fensterfilter gelten weiterhin.",
                         appLayout: "Layout für den App-Wechsel",
                         windowLayout: "Layout für den Fensterwechsel",
                         windowLayoutCaption: "Gilt für die Tastenkürzel für Fenster der aktuellen App und für alle Fenster.",
                         sameAsAppLayout: "Wie beim App-Wechsel")
        case .fr:
            return .init(allWindows: "Toutes les fenêtres",
                         allWindowsCaption: "Utilisez un raccourci distinct pour parcourir les fenêtres de toutes les apps, quelle que soit la disposition. Vos filtres de fenêtres restent actifs.",
                         appLayout: "Disposition du sélecteur d’apps",
                         windowLayout: "Disposition du sélecteur de fenêtres",
                         windowLayoutCaption: "S’applique aux raccourcis pour les fenêtres de l’app active et pour toutes les fenêtres.",
                         sameAsAppLayout: "Identique au sélecteur d’apps")
        case .it:
            return .init(allWindows: "Tutte le finestre",
                         allWindowsCaption: "Usa una scorciatoia separata per scorrere le finestre di tutte le app in qualsiasi layout. I filtri delle finestre restano attivi.",
                         appLayout: "Layout per cambiare app",
                         windowLayout: "Layout per cambiare finestra",
                         windowLayoutCaption: "Usato dalle scorciatoie per le finestre dell’app attuale e per tutte le finestre.",
                         sameAsAppLayout: "Come per il cambio di app")
        case .ja:
            return .init(allWindows: "すべてのウインドウ",
                         allWindowsCaption: "専用のショートカットで、どのレイアウトでもすべてのアプリのウインドウを順に切り替えます。ウインドウのフィルタは引き続き適用されます。",
                         appLayout: "アプリ切り替えのレイアウト",
                         windowLayout: "ウインドウ切り替えのレイアウト",
                         windowLayoutCaption: "現在のアプリのウインドウと、すべてのウインドウを切り替えるショートカットに適用されます。",
                         sameAsAppLayout: "アプリ切り替えと同じ")
        case .ko:
            return .init(allWindows: "모든 윈도우",
                         allWindowsCaption: "별도의 단축키로 모든 레이아웃에서 모든 앱의 윈도우를 차례로 전환합니다. 윈도우 필터는 계속 적용됩니다.",
                         appLayout: "앱 전환 레이아웃",
                         windowLayout: "윈도우 전환 레이아웃",
                         windowLayoutCaption: "현재 앱의 윈도우와 모든 윈도우를 전환하는 단축키에 적용됩니다.",
                         sameAsAppLayout: "앱 전환과 동일")
        case .zhHans:
            return .init(allWindows: "所有窗口",
                         allWindowsCaption: "使用独立快捷键，在任意布局中依次切换所有应用的窗口。窗口筛选条件仍然适用。",
                         appLayout: "应用切换布局",
                         windowLayout: "窗口切换布局",
                         windowLayoutCaption: "适用于切换当前应用的窗口和切换所有窗口的快捷键。",
                         sameAsAppLayout: "跟随应用切换布局")
        case .zhTW:
            return .init(allWindows: "所有視窗",
                         allWindowsCaption: "使用獨立快捷鍵，在任何版面配置中依序切換所有 App 的視窗。視窗篩選條件仍然適用。",
                         appLayout: "App 切換版面配置",
                         windowLayout: "視窗切換版面配置",
                         windowLayoutCaption: "適用於切換目前 App 的視窗及切換所有視窗的快速鍵。",
                         sameAsAppLayout: "與 App 切換相同")
        case .zhHK:
            return .init(allWindows: "所有視窗",
                         allWindowsCaption: "使用獨立快捷鍵，在任何版面配置中依次切換所有 App 的視窗。視窗篩選條件仍然適用。",
                         appLayout: "App 切換版面配置",
                         windowLayout: "視窗切換版面配置",
                         windowLayoutCaption: "適用於切換目前 App 的視窗及切換所有視窗的快捷鍵。",
                         sameAsAppLayout: "與 App 切換相同")
        case .uk:
            return .init(allWindows: "Усі вікна",
                         allWindowsCaption: "Використовуйте окреме сполучення клавіш для перемикання між вікнами всіх програм у будь-якому вигляді перемикача. Фільтри вікон діють і надалі.",
                         appLayout: "Вигляд перемикача програм",
                         windowLayout: "Вигляд перемикача вікон",
                         windowLayoutCaption: "Застосовується до скорочень для вікон поточної програми й для всіх вікон.",
                         sameAsAppLayout: "Як у перемикачі програм")
        }
    }
}
