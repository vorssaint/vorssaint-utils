// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SwitcherAppRulesStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let behaviorLabel: String
    let showWithoutWindows: String
    let windowsOnly: String
    let hidden: String
    let caption: String
}

extension FeatureStrings {
    static func switcherAppRules(_ language: AppLanguage) -> SwitcherAppRulesStrings {
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

extension SwitcherAppRulesStrings {
    static let enUS = SwitcherAppRulesStrings(
        listTitle: "Rules by app",
        addButton: "Add an app…",
        removeButton: "Remove",
        behaviorLabel: "Switcher behavior",
        showWithoutWindows: "Show without windows",
        windowsOnly: "Windows only",
        hidden: "Never show",
        caption: "Choose how each app appears. Apps without a rule use the choice above."
    )

    static let ptBR = SwitcherAppRulesStrings(
        listTitle: "Regras por app",
        addButton: "Adicionar app…",
        removeButton: "Remover",
        behaviorLabel: "Comportamento no alternador",
        showWithoutWindows: "Mostrar sem janelas",
        windowsOnly: "Só com janelas",
        hidden: "Nunca mostrar",
        caption: "Escolha como cada app aparece. Apps sem regra usam a opção acima."
    )

    static let tr = SwitcherAppRulesStrings(
        listTitle: "Uygulamaya göre kurallar",
        addButton: "Uygulama ekle…",
        removeButton: "Kaldır",
        behaviorLabel: "Değiştirici davranışı",
        showWithoutWindows: "Pencere olmadan göster",
        windowsOnly: "Yalnızca pencereler",
        hidden: "Asla gösterme",
        caption: "Her uygulamanın nasıl görüneceğini seçin. Kuralı olmayanlar yukarıdaki seçimi kullanır."
    )

    static let ru = SwitcherAppRulesStrings(
        listTitle: "Правила для приложений",
        addButton: "Добавить приложение…",
        removeButton: "Удалить",
        behaviorLabel: "Поведение в переключателе",
        showWithoutWindows: "Показывать без окон",
        windowsOnly: "Только с окнами",
        hidden: "Никогда не показывать",
        caption: "Выберите, как показывать каждое приложение. Без правила действует настройка выше."
    )

    static let es = SwitcherAppRulesStrings(
        listTitle: "Reglas por app",
        addButton: "Añadir app…",
        removeButton: "Quitar",
        behaviorLabel: "Comportamiento en el selector",
        showWithoutWindows: "Mostrar sin ventanas",
        windowsOnly: "Solo con ventanas",
        hidden: "No mostrar nunca",
        caption: "Elige cómo aparece cada app. Las apps sin regla usan la opción anterior."
    )

    static let de = SwitcherAppRulesStrings(
        listTitle: "Regeln pro App",
        addButton: "App hinzufügen…",
        removeButton: "Entfernen",
        behaviorLabel: "Verhalten im Umschalter",
        showWithoutWindows: "Ohne Fenster anzeigen",
        windowsOnly: "Nur mit Fenstern",
        hidden: "Nie anzeigen",
        caption: "Lege fest, wie jede App erscheint. Apps ohne Regel verwenden die Auswahl darüber."
    )

    static let fr = SwitcherAppRulesStrings(
        listTitle: "Règles par app",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        behaviorLabel: "Comportement dans le sélecteur",
        showWithoutWindows: "Afficher sans fenêtre",
        windowsOnly: "Avec fenêtres uniquement",
        hidden: "Ne jamais afficher",
        caption: "Choisissez comment chaque app apparaît. Sans règle, l’app utilise le choix ci-dessus."
    )

    static let it = SwitcherAppRulesStrings(
        listTitle: "Regole per app",
        addButton: "Aggiungi app…",
        removeButton: "Rimuovi",
        behaviorLabel: "Comportamento nel selettore",
        showWithoutWindows: "Mostra senza finestre",
        windowsOnly: "Solo con finestre",
        hidden: "Non mostrare mai",
        caption: "Scegli come appare ogni app. Le app senza regola usano l’opzione qui sopra."
    )

    static let ja = SwitcherAppRulesStrings(
        listTitle: "Appごとのルール",
        addButton: "Appを追加…",
        removeButton: "削除",
        behaviorLabel: "スイッチャーでの表示",
        showWithoutWindows: "ウインドウなしでも表示",
        windowsOnly: "ウインドウがある時のみ",
        hidden: "常に非表示",
        caption: "Appごとの表示方法を選びます。ルールのないAppには上の設定が使われます。"
    )

    static let ko = SwitcherAppRulesStrings(
        listTitle: "앱별 규칙",
        addButton: "앱 추가…",
        removeButton: "제거",
        behaviorLabel: "전환기 표시 방식",
        showWithoutWindows: "창 없이도 표시",
        windowsOnly: "창이 있을 때만",
        hidden: "항상 숨기기",
        caption: "각 앱의 표시 방식을 선택합니다. 규칙이 없는 앱은 위의 설정을 사용합니다."
    )

    static let zhHans = SwitcherAppRulesStrings(
        listTitle: "按 App 设置规则",
        addButton: "添加 App…",
        removeButton: "移除",
        behaviorLabel: "切换器显示方式",
        showWithoutWindows: "无窗口时也显示",
        windowsOnly: "仅有窗口时显示",
        hidden: "始终不显示",
        caption: "选择每个 App 的显示方式。未设置规则的 App 使用上方选项。"
    )

    static let zhTW = SwitcherAppRulesStrings(
        listTitle: "各 App 規則",
        addButton: "加入 App…",
        removeButton: "移除",
        behaviorLabel: "切換器顯示方式",
        showWithoutWindows: "沒有視窗時也顯示",
        windowsOnly: "僅有視窗時顯示",
        hidden: "一律不顯示",
        caption: "選擇每個 App 的顯示方式。沒有規則的 App 使用上方選項。"
    )

    static let zhHK = SwitcherAppRulesStrings(
        listTitle: "各 App 規則",
        addButton: "加入 App…",
        removeButton: "移除",
        behaviorLabel: "切換器顯示方式",
        showWithoutWindows: "沒有視窗時也顯示",
        windowsOnly: "僅有視窗時顯示",
        hidden: "一律不顯示",
        caption: "選擇每個 App 的顯示方式。沒有規則的 App 使用上方選項。"
    )
}
