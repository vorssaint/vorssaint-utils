// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DockNumberSwitchStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let needsAccessibility: String
    let unavailableShortcuts: String
}

extension FeatureStrings {
    static func dockNumberSwitch(_ language: AppLanguage) -> DockNumberSwitchStrings {
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

extension DockNumberSwitchStrings {
    static let enUS = DockNumberSwitchStrings(
        pageTitle: "Dock number keys",
        hubDescription: "Jump to a Dock app with the super key and its number.",
        enableToggle: "Activate a Dock app with the super key and its number",
        enableCaption: "With the super key on, press it with 1 to 9 to activate the app in that Dock position. Finder is 1.",
        needsAccessibility: "Reading the Dock order needs Accessibility.",
        unavailableShortcuts: "Another app has taken one of these combinations, so a number may not work."
    )

    static let ptBR = DockNumberSwitchStrings(
        pageTitle: "Teclas numéricas do Dock",
        hubDescription: "Abra um app do Dock com a tecla super e o número dele.",
        enableToggle: "Ativar um app do Dock com a tecla super e o número dele",
        enableCaption: "Com a tecla super ativa, pressione-a com 1 a 9 para ativar o app naquela posição do Dock. O Finder é o 1.",
        needsAccessibility: "Ler a ordem do Dock requer Acessibilidade.",
        unavailableShortcuts: "Outro app assumiu uma dessas combinações, então um número pode não funcionar."
    )

    static let tr = DockNumberSwitchStrings(
        pageTitle: "Dock sayı tuşları",
        hubDescription: "Süper tuş ve numarasıyla bir Dock uygulamasına geçin.",
        enableToggle: "Süper tuş ve numarasıyla bir Dock uygulamasını etkinleştir",
        enableCaption: "Süper tuş açıkken, o Dock konumundaki uygulamayı etkinleştirmek için 1–9 ile birlikte basın. Finder 1'dir.",
        needsAccessibility: "Dock sırasını okumak için Erişilebilirlik gerekir.",
        unavailableShortcuts: "Başka bir uygulama bu kombinasyonlardan birini almış, bu yüzden bir numara çalışmayabilir."
    )

    static let ru = DockNumberSwitchStrings(
        pageTitle: "Цифровые клавиши Dock",
        hubDescription: "Переход к приложению в Dock с помощью суперклавиши и его номера.",
        enableToggle: "Открывать приложение из Dock суперклавишей и его номером",
        enableCaption: "Когда суперклавиша включена, нажмите её с 1–9, чтобы открыть приложение на этой позиции в Dock. Finder — это 1.",
        needsAccessibility: "Для чтения порядка Dock нужен Универсальный доступ.",
        unavailableShortcuts: "Другое приложение заняло одну из этих комбинаций, поэтому какой-то номер может не работать."
    )

    static let es = DockNumberSwitchStrings(
        pageTitle: "Teclas numéricas del Dock",
        hubDescription: "Ve a una app del Dock con la tecla súper y su número.",
        enableToggle: "Activar una app del Dock con la tecla súper y su número",
        enableCaption: "Con la tecla súper activada, púlsala con 1 a 9 para activar la app en esa posición del Dock. Finder es la 1.",
        needsAccessibility: "Leer el orden del Dock requiere Accesibilidad.",
        unavailableShortcuts: "Otra app ha tomado una de estas combinaciones, por lo que un número podría no funcionar."
    )

    static let de = DockNumberSwitchStrings(
        pageTitle: "Dock-Zifferntasten",
        hubDescription: "Mit der Supertaste und ihrer Nummer zu einer Dock-App springen.",
        enableToggle: "Eine Dock-App mit der Supertaste und ihrer Nummer aktivieren",
        enableCaption: "Wenn die Supertaste aktiv ist, drücke sie mit 1 bis 9, um die App an dieser Dock-Position zu aktivieren. Finder ist 1.",
        needsAccessibility: "Zum Lesen der Dock-Reihenfolge sind Bedienungshilfen nötig.",
        unavailableShortcuts: "Eine andere App hat eine dieser Kombinationen belegt, daher funktioniert eine Nummer möglicherweise nicht."
    )

    static let fr = DockNumberSwitchStrings(
        pageTitle: "Touches numériques du Dock",
        hubDescription: "Accédez à une app du Dock avec la touche super et son numéro.",
        enableToggle: "Activer une app du Dock avec la touche super et son numéro",
        enableCaption: "Quand la touche super est activée, appuyez dessus avec 1 à 9 pour activer l’app à cette position du Dock. Le Finder est 1.",
        needsAccessibility: "Lire l’ordre du Dock nécessite l’Accessibilité.",
        unavailableShortcuts: "Une autre app a pris l’une de ces combinaisons ; un numéro peut donc ne pas fonctionner."
    )

    static let it = DockNumberSwitchStrings(
        pageTitle: "Tasti numerici del Dock",
        hubDescription: "Passa a un’app del Dock con il tasto super e il suo numero.",
        enableToggle: "Attiva un’app del Dock con il tasto super e il suo numero",
        enableCaption: "Con il tasto super attivo, premilo con 1–9 per attivare l’app in quella posizione del Dock. Il Finder è 1.",
        needsAccessibility: "Leggere l’ordine del Dock richiede l’Accessibilità.",
        unavailableShortcuts: "Un’altra app ha preso una di queste combinazioni, quindi un numero potrebbe non funzionare."
    )

    static let ja = DockNumberSwitchStrings(
        pageTitle: "Dock 番号キー",
        hubDescription: "スーパーキーと番号で Dock のアプリに切り替えます。",
        enableToggle: "スーパーキーと番号で Dock のアプリを起動する",
        enableCaption: "スーパーキーがオンのとき、1〜9 と一緒に押すと、その Dock の位置にあるアプリが起動します。Finder は 1 です。",
        needsAccessibility: "Dock の並び順を読み取るにはアクセシビリティが必要です。",
        unavailableShortcuts: "別のアプリがこの組み合わせのいずれかを使用しているため、一部の番号が動作しないことがあります。"
    )

    static let ko = DockNumberSwitchStrings(
        pageTitle: "Dock 숫자 키",
        hubDescription: "슈퍼 키와 숫자로 Dock 앱으로 전환합니다.",
        enableToggle: "슈퍼 키와 숫자로 Dock 앱 활성화",
        enableCaption: "슈퍼 키가 켜져 있을 때 1~9와 함께 누르면 해당 Dock 위치의 앱이 활성화됩니다. Finder가 1입니다.",
        needsAccessibility: "Dock 순서를 읽으려면 손쉬운 사용 권한이 필요합니다.",
        unavailableShortcuts: "다른 앱이 이 조합 중 하나를 사용 중이라 일부 숫자가 작동하지 않을 수 있습니다."
    )

    static let zhHans = DockNumberSwitchStrings(
        pageTitle: "Dock 数字键",
        hubDescription: "用超级键加数字切换到 Dock 中的应用。",
        enableToggle: "用超级键加数字激活 Dock 中的应用",
        enableCaption: "开启超级键后，与 1 到 9 一起按下即可激活该 Dock 位置的应用。访达是 1。",
        needsAccessibility: "读取 Dock 顺序需要辅助功能权限。",
        unavailableShortcuts: "另一个应用已占用其中一个组合，因此某个数字可能无法使用。"
    )

    static let zhTW = DockNumberSwitchStrings(
        pageTitle: "Dock 數字鍵",
        hubDescription: "用超級鍵加數字切換到 Dock 中的 App。",
        enableToggle: "用超級鍵加數字啟用 Dock 中的 App",
        enableCaption: "開啟超級鍵後，與 1 至 9 一起按下即可啟用該 Dock 位置的 App。Finder 是 1。",
        needsAccessibility: "讀取 Dock 順序需要輔助使用權限。",
        unavailableShortcuts: "另一個 App 已佔用其中一個組合，因此某個數字可能無法使用。"
    )

    static let zhHK = DockNumberSwitchStrings(
        pageTitle: "Dock 數字鍵",
        hubDescription: "用超級鍵加數字切換到 Dock 中的 App。",
        enableToggle: "用超級鍵加數字啟用 Dock 中的 App",
        enableCaption: "開啟超級鍵後，與 1 至 9 一起按下即可啟用該 Dock 位置的 App。Finder 是 1。",
        needsAccessibility: "讀取 Dock 順序需要輔助使用權限。",
        unavailableShortcuts: "另一個 App 已佔用其中一個組合，因此某個數字可能無法使用。"
    )
}
