// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseExceptionStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let captionSmoothScroll: String
    let captionScrollDirection: String
    let captionNavigation: String
    let captionButtonShortcuts: String
    let captionMiddleClick: String

    func caption(for scope: MouseExceptionScope) -> String {
        switch scope {
        case .smoothScroll: return captionSmoothScroll
        case .scrollDirection: return captionScrollDirection
        case .navigation: return captionNavigation
        case .buttonShortcuts: return captionButtonShortcuts
        case .middleClick: return captionMiddleClick
        }
    }
}

extension FeatureStrings {
    static func mouseExceptions(_ language: AppLanguage) -> MouseExceptionStrings {
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

extension MouseExceptionStrings {
    static let enUS = MouseExceptionStrings(
        listTitle: "Apps to leave alone",
        addButton: "Add an app…",
        removeButton: "Remove",
        captionSmoothScroll: "The wheel keeps its plain steps in these apps, for apps that read it their own way, like 3D and design tools.",
        captionScrollDirection: "The wheel keeps the direction macOS gives it in these apps.",
        captionNavigation: "The side buttons keep doing whatever these apps already do with them.",
        captionButtonShortcuts: "Your button shortcuts stay quiet in these apps, and the press reaches them instead.",
        captionMiddleClick: "A three finger click stays a normal click in these apps."
    )

    static let ptBR = MouseExceptionStrings(
        listTitle: "Apps para não mexer",
        addButton: "Adicionar app…",
        removeButton: "Remover",
        captionSmoothScroll: "Nestes apps a roda continua com os passos normais, para apps que leem a roda do jeito deles, como ferramentas de 3D e design.",
        captionScrollDirection: "Nestes apps a roda mantém o sentido que o macOS dá a ela.",
        captionNavigation: "Nestes apps os botões laterais continuam fazendo o que eles já fazem.",
        captionButtonShortcuts: "Nestes apps seus atalhos de botão ficam quietos e o clique chega no app.",
        captionMiddleClick: "Nestes apps o clique de três dedos continua um clique normal."
    )

    static let tr = MouseExceptionStrings(
        listTitle: "Dokunulmayacak uygulamalar",
        addButton: "Uygulama ekle…",
        removeButton: "Kaldır",
        captionSmoothScroll: "Bu uygulamalarda tekerlek normal adımlarında kalır; tekerleği kendine göre okuyan 3B ve tasarım araçları için.",
        captionScrollDirection: "Bu uygulamalarda tekerlek macOS'un verdiği yönde kalır.",
        captionNavigation: "Bu uygulamalarda yan düğmeler zaten yaptıkları işi yapmayı sürdürür.",
        captionButtonShortcuts: "Bu uygulamalarda düğme kısayollarınız sessiz kalır ve basma uygulamaya ulaşır.",
        captionMiddleClick: "Bu uygulamalarda üç parmak tıklaması normal tıklama olarak kalır."
    )

    static let ru = MouseExceptionStrings(
        listTitle: "Приложения без вмешательства",
        addButton: "Добавить приложение…",
        removeButton: "Удалить",
        captionSmoothScroll: "В этих приложениях колесо крутится обычными шагами: для тех, кто читает его по-своему, например 3D-редакторов и графических программ.",
        captionScrollDirection: "В этих приложениях колесо сохраняет направление, которое даёт macOS.",
        captionNavigation: "В этих приложениях боковые кнопки продолжают делать то, что уже делают.",
        captionButtonShortcuts: "В этих приложениях ваши кнопочные сочетания молчат, а нажатие доходит до приложения.",
        captionMiddleClick: "В этих приложениях щелчок тремя пальцами остаётся обычным щелчком."
    )

    static let es = MouseExceptionStrings(
        listTitle: "Apps que no se tocan",
        addButton: "Añadir app…",
        removeButton: "Quitar",
        captionSmoothScroll: "En estas apps la rueda mantiene sus pasos normales, para las que la leen a su manera, como las de 3D y diseño.",
        captionScrollDirection: "En estas apps la rueda mantiene el sentido que le da macOS.",
        captionNavigation: "En estas apps los botones laterales siguen haciendo lo que ya hacen.",
        captionButtonShortcuts: "En estas apps tus atajos de botón se quedan callados y la pulsación llega a la app.",
        captionMiddleClick: "En estas apps el clic con tres dedos sigue siendo un clic normal."
    )

    static let de = MouseExceptionStrings(
        listTitle: "Apps, die unberührt bleiben",
        addButton: "App hinzufügen…",
        removeButton: "Entfernen",
        captionSmoothScroll: "In diesen Apps behält das Rad seine normalen Schritte, für Apps, die es selbst auswerten, etwa 3D- und Design-Werkzeuge.",
        captionScrollDirection: "In diesen Apps behält das Rad die Richtung, die macOS ihm gibt.",
        captionNavigation: "In diesen Apps tun die Seitentasten weiter, was sie dort schon tun.",
        captionButtonShortcuts: "In diesen Apps bleiben deine Tastenkürzel still und der Druck erreicht die App.",
        captionMiddleClick: "In diesen Apps bleibt ein Klick mit drei Fingern ein normaler Klick."
    )

    static let fr = MouseExceptionStrings(
        listTitle: "Apps à ne pas toucher",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        captionSmoothScroll: "Dans ces apps la molette garde ses crans normaux, pour celles qui la lisent à leur façon, comme les outils 3D et de design.",
        captionScrollDirection: "Dans ces apps la molette garde le sens que macOS lui donne.",
        captionNavigation: "Dans ces apps les boutons latéraux continuent de faire ce qu'ils y font déjà.",
        captionButtonShortcuts: "Dans ces apps vos raccourcis de bouton se taisent et l'appui atteint l'app.",
        captionMiddleClick: "Dans ces apps un clic à trois doigts reste un clic normal."
    )

    static let it = MouseExceptionStrings(
        listTitle: "App da non toccare",
        addButton: "Aggiungi app…",
        removeButton: "Rimuovi",
        captionSmoothScroll: "In queste app la rotellina mantiene i suoi scatti normali, per quelle che la leggono a modo loro, come gli strumenti 3D e di design.",
        captionScrollDirection: "In queste app la rotellina mantiene il verso che le dà macOS.",
        captionNavigation: "In queste app i pulsanti laterali continuano a fare quello che già fanno.",
        captionButtonShortcuts: "In queste app le tue scorciatoie sui pulsanti restano zitte e la pressione arriva all'app.",
        captionMiddleClick: "In queste app un clic con tre dita resta un clic normale."
    )

    static let ja = MouseExceptionStrings(
        listTitle: "そのままにするApp",
        addButton: "Appを追加…",
        removeButton: "削除",
        captionSmoothScroll: "これらのAppではホイールが元の刻みのままになります。3Dやデザインのツールのように、ホイールを独自に読むApp向けです。",
        captionScrollDirection: "これらのAppではホイールの向きがmacOSのままになります。",
        captionNavigation: "これらのAppでは横のボタンが元々の働きを続けます。",
        captionButtonShortcuts: "これらのAppではボタンの割り当てが働かず、押した操作がAppに届きます。",
        captionMiddleClick: "これらのAppでは3本指のクリックが普通のクリックのままです。"
    )

    static let ko = MouseExceptionStrings(
        listTitle: "건드리지 않을 앱",
        addButton: "앱 추가…",
        removeButton: "제거",
        captionSmoothScroll: "이 앱들에서는 휠이 원래 단계 그대로 움직입니다. 3D나 디자인 도구처럼 휠을 자기 방식으로 읽는 앱을 위한 것입니다.",
        captionScrollDirection: "이 앱들에서는 휠 방향이 macOS가 주는 그대로 유지됩니다.",
        captionNavigation: "이 앱들에서는 측면 버튼이 원래 하던 일을 계속합니다.",
        captionButtonShortcuts: "이 앱들에서는 버튼 단축키가 조용히 있고 누름이 앱에 전달됩니다.",
        captionMiddleClick: "이 앱들에서는 세 손가락 클릭이 보통 클릭으로 남습니다."
    )

    static let zhHans = MouseExceptionStrings(
        listTitle: "不干预的 App",
        addButton: "添加 App…",
        removeButton: "移除",
        captionSmoothScroll: "在这些 App 里滚轮保持原本的档位，适合自己解读滚轮的 App，比如 3D 和设计工具。",
        captionScrollDirection: "在这些 App 里滚轮保持 macOS 给它的方向。",
        captionNavigation: "在这些 App 里侧键继续做它们本来做的事。",
        captionButtonShortcuts: "在这些 App 里按键快捷键保持安静，按下会传给 App。",
        captionMiddleClick: "在这些 App 里三指点按仍是普通点按。"
    )

    static let zhTW = MouseExceptionStrings(
        listTitle: "不干預的 App",
        addButton: "加入 App…",
        removeButton: "移除",
        captionSmoothScroll: "在這些 App 裡滾輪保持原本的段落，適合自己解讀滾輪的 App，例如 3D 和設計工具。",
        captionScrollDirection: "在這些 App 裡滾輪保持 macOS 給它的方向。",
        captionNavigation: "在這些 App 裡側鍵繼續做它們原本做的事。",
        captionButtonShortcuts: "在這些 App 裡按鍵快速鍵保持安靜，按下會傳給 App。",
        captionMiddleClick: "在這些 App 裡三指點按仍是普通點按。"
    )

    static let zhHK = MouseExceptionStrings(
        listTitle: "不干預的 App",
        addButton: "加入 App…",
        removeButton: "移除",
        captionSmoothScroll: "在這些 App 裡滾輪保持原本的段落，適合自己解讀滾輪的 App，例如 3D 和設計工具。",
        captionScrollDirection: "在這些 App 裡滾輪保持 macOS 給它的方向。",
        captionNavigation: "在這些 App 裡側鍵繼續做它們原本做的事。",
        captionButtonShortcuts: "在這些 App 裡按鍵快速鍵保持安靜，按下會傳給 App。",
        captionMiddleClick: "在這些 App 裡三指點按仍是普通點按。"
    )
}
