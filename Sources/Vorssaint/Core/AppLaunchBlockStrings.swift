// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AppLaunchBlockStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
    let protectedApp: String
}

extension FeatureStrings {
    static func appLaunchBlock(_ language: AppLanguage) -> AppLaunchBlockStrings {
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

extension AppLaunchBlockStrings {
    static let enUS = AppLaunchBlockStrings(
        listTitle: "Blocked apps",
        addButton: "Choose app…",
        removeButton: "Remove",
        caption: "Apps on this list are quit as soon as they open. A copy already running is left alone until its next launch.",
        protectedApp: "Vorssaint and macOS system components such as Finder and the Dock can’t be blocked."
    )

    static let ptBR = AppLaunchBlockStrings(
        listTitle: "Apps bloqueados",
        addButton: "Escolher app…",
        removeButton: "Remover",
        caption: "Os apps desta lista são encerrados assim que abrem. Uma cópia que já está aberta não é afetada até a próxima vez que abrir.",
        protectedApp: "O Vorssaint e componentes do sistema macOS, como o Finder e o Dock, não podem ser bloqueados."
    )

    static let tr = AppLaunchBlockStrings(
        listTitle: "Engellenen uygulamalar",
        addButton: "Uygulama seç…",
        removeButton: "Kaldır",
        caption: "Bu listedeki uygulamalar açılır açılmaz kapatılır. Zaten çalışan bir kopyaya bir sonraki açılışına kadar dokunulmaz.",
        protectedApp: "Vorssaint ve Finder ile Dock gibi macOS sistem bileşenleri engellenemez."
    )

    static let ru = AppLaunchBlockStrings(
        listTitle: "Заблокированные приложения",
        addButton: "Выбрать приложение…",
        removeButton: "Удалить",
        caption: "Приложения из этого списка закрываются сразу после открытия. Уже запущенная копия остаётся открытой до следующего запуска.",
        protectedApp: "Нельзя заблокировать Vorssaint и системные компоненты macOS, такие как Finder и Dock."
    )

    static let es = AppLaunchBlockStrings(
        listTitle: "Apps bloqueadas",
        addButton: "Elegir app…",
        removeButton: "Quitar",
        caption: "Las apps de esta lista se cierran en cuanto se abren. Una copia que ya está abierta no se toca hasta la próxima vez que se abra.",
        protectedApp: "No se pueden bloquear Vorssaint ni componentes del sistema macOS como el Finder y el Dock."
    )

    static let sk = AppLaunchBlockStrings(
        listTitle: "Blokované aplikácie",
        addButton: "Vybrať aplikáciu…",
        removeButton: "Odstrániť",
        caption: "Aplikácie z tohto zoznamu sa ukončia hneď po otvorení. Kópia, ktorá už beží, zostane otvorená až do ďalšieho spustenia.",
        protectedApp: "Vorssaint a systémové súčasti macOS, ako sú Finder a Dock, sa nedajú zablokovať."
    )

    static let de = AppLaunchBlockStrings(
        listTitle: "Blockierte Apps",
        addButton: "App wählen…",
        removeButton: "Entfernen",
        caption: "Apps auf dieser Liste werden beendet, sobald sie sich öffnen. Eine bereits laufende App bleibt bis zum nächsten Start unberührt.",
        protectedApp: "Vorssaint und macOS-Systemkomponenten wie Finder und Dock können nicht blockiert werden."
    )

    static let fr = AppLaunchBlockStrings(
        listTitle: "Apps bloquées",
        addButton: "Choisir une app…",
        removeButton: "Retirer",
        caption: "Les apps de cette liste sont quittées dès leur ouverture. Une copie déjà ouverte n’est pas touchée avant sa prochaine ouverture.",
        protectedApp: "Vorssaint et les composants système de macOS, comme le Finder et le Dock, ne peuvent pas être bloqués."
    )

    static let it = AppLaunchBlockStrings(
        listTitle: "App bloccate",
        addButton: "Scegli app…",
        removeButton: "Rimuovi",
        caption: "Le app in questo elenco vengono chiuse appena si aprono. Una copia già aperta resta com’è fino alla prossima apertura.",
        protectedApp: "Non è possibile bloccare Vorssaint né i componenti di sistema di macOS come il Finder e il Dock."
    )

    static let ja = AppLaunchBlockStrings(
        listTitle: "ブロックするアプリ",
        addButton: "アプリを選択…",
        removeButton: "削除",
        caption: "このリストのアプリは開いた直後に終了されます。すでに実行中のアプリはそのままで、次に開いたときから有効になります。",
        protectedApp: "Vorssaint 自体や、Finder や Dock などの macOS システムコンポーネントはブロックできません。"
    )

    static let ko = AppLaunchBlockStrings(
        listTitle: "차단할 앱",
        addButton: "앱 선택…",
        removeButton: "제거",
        caption: "이 목록의 앱은 열리자마자 종료됩니다. 이미 실행 중인 앱은 그대로 두고 다음에 열 때부터 적용됩니다.",
        protectedApp: "Vorssaint 자체나 Finder, Dock 같은 macOS 시스템 구성 요소는 차단할 수 없습니다."
    )

    static let zhHans = AppLaunchBlockStrings(
        listTitle: "阻止打开的 App",
        addButton: "选择 App…",
        removeButton: "移除",
        caption: "列表中的 App 一打开就会被退出。已经在运行的 App 不受影响，下次打开时生效。",
        protectedApp: "无法阻止 Vorssaint 本身，或访达、程序坞等 macOS 系统组件。"
    )

    static let zhTW = AppLaunchBlockStrings(
        listTitle: "阻止開啟的 App",
        addButton: "選擇 App…",
        removeButton: "移除",
        caption: "列表中的 App 一開啟就會被結束。已在執行的 App 不受影響，下次開啟時生效。",
        protectedApp: "無法阻止 Vorssaint 本身，或 Finder、Dock 等 macOS 系統元件。"
    )

    static let zhHK = AppLaunchBlockStrings(
        listTitle: "阻止開啟的 App",
        addButton: "選擇 App…",
        removeButton: "移除",
        caption: "列表中的 App 一開啟就會被結束。已在執行的 App 不受影響，下次開啟時生效。",
        protectedApp: "無法阻止 Vorssaint 本身，或 Finder、Dock 等 macOS 系統元件。"
    )

    static let uk = AppLaunchBlockStrings(
        listTitle: "Заблоковані програми",
        addButton: "Вибрати програму…",
        removeButton: "Видалити",
        caption: "Програми з цього списку закриваються одразу після відкриття. Уже запущена копія лишається відкритою до наступного запуску.",
        protectedApp: "Не можна заблокувати Vorssaint і системні компоненти macOS, як-от Finder і Dock."
    )
}
