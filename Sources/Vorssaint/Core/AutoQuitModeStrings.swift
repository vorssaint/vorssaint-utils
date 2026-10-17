// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AutoQuitModeStrings {
    let modeTitle: String
    let allExceptTitle: String
    let onlyListedTitle: String
    let includedTitle: String
    let includedEmpty: String
    let includedCaption: String
}

extension FeatureStrings {
    static func autoQuitMode(_ language: AppLanguage) -> AutoQuitModeStrings {
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

extension AutoQuitModeStrings {
    static let enUS = AutoQuitModeStrings(
        modeTitle: "Apps to quit",
        allExceptTitle: "All apps except the exceptions",
        onlyListedTitle: "Only the apps in the list",
        includedTitle: "Apps that quit",
        includedEmpty: "No apps listed, so nothing quits",
        includedCaption: "Only apps on this list quit when their last window closes."
    )

    static let ptBR = AutoQuitModeStrings(
        modeTitle: "Apps a encerrar",
        allExceptTitle: "Todos os apps, exceto as exceções",
        onlyListedTitle: "Somente os apps da lista",
        includedTitle: "Apps que são encerrados",
        includedEmpty: "Nenhum app na lista, então nada é encerrado",
        includedCaption: "Somente os apps desta lista são encerrados quando a última janela fecha."
    )

    static let tr = AutoQuitModeStrings(
        modeTitle: "Kapatılacak uygulamalar",
        allExceptTitle: "İstisnalar dışındaki tüm uygulamalar",
        onlyListedTitle: "Yalnızca listedeki uygulamalar",
        includedTitle: "Kapatılan uygulamalar",
        includedEmpty: "Listede uygulama yok, bu yüzden hiçbiri kapanmaz",
        includedCaption: "Son pencereleri kapandığında yalnızca bu listedeki uygulamalar kapatılır."
    )

    static let ru = AutoQuitModeStrings(
        modeTitle: "Какие приложения закрывать",
        allExceptTitle: "Все, кроме исключений",
        onlyListedTitle: "Только приложения из списка",
        includedTitle: "Приложения, которые закрываются",
        includedEmpty: "В списке нет приложений, поэтому ничего не закрывается",
        includedCaption: "Когда закрывается последнее окно, завершаются только приложения из этого списка."
    )

    static let es = AutoQuitModeStrings(
        modeTitle: "Apps que se cierran",
        allExceptTitle: "Todas las apps salvo las excepciones",
        onlyListedTitle: "Solo las apps de la lista",
        includedTitle: "Apps que se cierran",
        includedEmpty: "No hay apps en la lista, así que no se cierra ninguna",
        includedCaption: "Solo las apps de esta lista se cierran al cerrar su última ventana."
    )

    static let sk = AutoQuitModeStrings(
        modeTitle: "Aplikácie na ukončenie",
        allExceptTitle: "Všetky aplikácie okrem výnimiek",
        onlyListedTitle: "Iba aplikácie v zozname",
        includedTitle: "Aplikácie, ktoré sa ukončia",
        includedEmpty: "V zozname nie sú žiadne aplikácie, takže sa nič neukončí",
        includedCaption: "Po zatvorení posledného okna sa ukončia iba aplikácie z tohto zoznamu."
    )

    static let de = AutoQuitModeStrings(
        modeTitle: "Zu beendende Apps",
        allExceptTitle: "Alle Apps außer den Ausnahmen",
        onlyListedTitle: "Nur die Apps in der Liste",
        includedTitle: "Apps, die beendet werden",
        includedEmpty: "Keine Apps in der Liste, also wird nichts beendet",
        includedCaption: "Nur Apps in dieser Liste werden beendet, wenn ihr letztes Fenster geschlossen wird."
    )

    static let fr = AutoQuitModeStrings(
        modeTitle: "Apps à quitter",
        allExceptTitle: "Toutes les apps sauf les exceptions",
        onlyListedTitle: "Seulement les apps de la liste",
        includedTitle: "Apps qui se ferment",
        includedEmpty: "Aucune app dans la liste, donc rien ne se ferme",
        includedCaption: "Seules les apps de cette liste se ferment quand leur dernière fenêtre est fermée."
    )

    static let it = AutoQuitModeStrings(
        modeTitle: "App da chiudere",
        allExceptTitle: "Tutte le app tranne le eccezioni",
        onlyListedTitle: "Solo le app nell’elenco",
        includedTitle: "App che vengono chiuse",
        includedEmpty: "Nessuna app nell’elenco, quindi non si chiude nulla",
        includedCaption: "Solo le app in questo elenco si chiudono quando si chiude la loro ultima finestra."
    )

    static let ja = AutoQuitModeStrings(
        modeTitle: "終了するアプリ",
        allExceptTitle: "例外を除くすべてのアプリ",
        onlyListedTitle: "リストにあるアプリのみ",
        includedTitle: "終了するアプリ",
        includedEmpty: "リストにアプリがないため、何も終了しません",
        includedCaption: "最後のウインドウを閉じたときに終了するのは、このリストのアプリだけです。"
    )

    static let ko = AutoQuitModeStrings(
        modeTitle: "종료할 앱",
        allExceptTitle: "예외를 제외한 모든 앱",
        onlyListedTitle: "목록에 있는 앱만",
        includedTitle: "종료되는 앱",
        includedEmpty: "목록에 앱이 없으므로 종료되는 앱이 없습니다",
        includedCaption: "마지막 윈도우를 닫을 때 이 목록의 앱만 종료됩니다."
    )

    static let zhHans = AutoQuitModeStrings(
        modeTitle: "要退出的 App",
        allExceptTitle: "除例外外的所有 App",
        onlyListedTitle: "仅列表中的 App",
        includedTitle: "会退出的 App",
        includedEmpty: "列表中没有 App，因此不会退出任何 App",
        includedCaption: "关闭最后一个窗口时，只有此列表中的 App 会退出。"
    )

    static let zhTW = AutoQuitModeStrings(
        modeTitle: "要結束的 App",
        allExceptTitle: "除例外外的所有 App",
        onlyListedTitle: "僅清單中的 App",
        includedTitle: "會結束的 App",
        includedEmpty: "清單中沒有 App，因此不會結束任何 App",
        includedCaption: "關閉最後一個視窗時，只有此清單中的 App 會結束。"
    )

    static let zhHK = AutoQuitModeStrings(
        modeTitle: "要結束的 App",
        allExceptTitle: "除例外項目外的所有 App",
        onlyListedTitle: "僅清單中的 App",
        includedTitle: "會結束的 App",
        includedEmpty: "清單中沒有 App，因此不會結束任何 App",
        includedCaption: "關閉最後一個視窗時，只有此清單中的 App 會結束。"
    )

    static let uk = AutoQuitModeStrings(
        modeTitle: "Які програми закривати",
        allExceptTitle: "Усі, крім винятків",
        onlyListedTitle: "Лише програми зі списку",
        includedTitle: "Програми, які закриваються",
        includedEmpty: "У списку немає програм, тому нічого не закривається",
        includedCaption: "Коли закривається останнє вікно, завершуються лише програми з цього списку."
    )
}
