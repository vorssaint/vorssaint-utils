// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SelectionBarStrings {
    let title: String
    let caption: String
    let copy: String
    let tools: String
    let doubleClick: String
}

extension FeatureStrings {
    static func selectionBar(_ language: AppLanguage) -> SelectionBarStrings {
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

extension SelectionBarStrings {
    static let enUS = SelectionBarStrings(
        title: "Selection bar",
        caption: "Select text with the mouse and a small bar of actions appears next to it. Apps that do not share their selection with macOS do not show it.",
        copy: "Copy",
        tools: "Tools on the bar",
        doubleClick: "Open with a double click"
    )

    static let ptBR = SelectionBarStrings(
        title: "Barra de seleção",
        caption: "Selecione um texto com o mouse e uma pequena barra de ações aparece ao lado. Apps que não compartilham a seleção com o macOS não a mostram.",
        copy: "Copiar",
        tools: "Ferramentas na barra",
        doubleClick: "Abrir com um clique duplo"
    )

    static let tr = SelectionBarStrings(
        title: "Seçim çubuğu",
        caption: "Fareyle metin seçtiğinizde yanında küçük bir eylem çubuğu görünür. Seçimini macOS ile paylaşmayan uygulamalarda görünmez.",
        copy: "Kopyala",
        tools: "Çubuktaki araçlar",
        doubleClick: "Çift tıklamayla aç"
    )

    static let ru = SelectionBarStrings(
        title: "Панель выделения",
        caption: "Выделите текст мышью, и рядом появится небольшая панель действий. В приложениях, которые не сообщают macOS о выделении, она не появляется.",
        copy: "Скопировать",
        tools: "Инструменты на панели",
        doubleClick: "Открывать двойным щелчком"
    )

    static let es = SelectionBarStrings(
        title: "Barra de selección",
        caption: "Selecciona texto con el ratón y aparece una pequeña barra de acciones a su lado. Las apps que no comparten su selección con macOS no la muestran.",
        copy: "Copiar",
        tools: "Herramientas en la barra",
        doubleClick: "Abrir con doble clic"
    )

    static let sk = SelectionBarStrings(
        title: "Panel výberu",
        caption: "Vyberte text myšou a vedľa neho sa zobrazí malý panel akcií. Aplikácie, ktoré svoj výber nezdieľajú s macOS, ho nezobrazia.",
        copy: "Kopírovať",
        tools: "Nástroje na paneli",
        doubleClick: "Otvoriť dvojitým kliknutím"
    )

    static let de = SelectionBarStrings(
        title: "Auswahlleiste",
        caption: "Markiere Text mit der Maus, und daneben erscheint eine kleine Leiste mit Aktionen. Apps, die ihre Auswahl nicht mit macOS teilen, zeigen sie nicht.",
        copy: "Kopieren",
        tools: "Werkzeuge in der Leiste",
        doubleClick: "Mit einem Doppelklick öffnen"
    )

    static let fr = SelectionBarStrings(
        title: "Barre de sélection",
        caption: "Sélectionnez du texte à la souris et une petite barre d’actions apparaît à côté. Les apps qui ne partagent pas leur sélection avec macOS ne l’affichent pas.",
        copy: "Copier",
        tools: "Outils de la barre",
        doubleClick: "Ouvrir avec un double-clic"
    )

    static let it = SelectionBarStrings(
        title: "Barra di selezione",
        caption: "Seleziona del testo con il mouse e accanto compare una piccola barra di azioni. Le app che non condividono la selezione con macOS non la mostrano.",
        copy: "Copia",
        tools: "Strumenti nella barra",
        doubleClick: "Apri con un doppio clic"
    )

    static let ja = SelectionBarStrings(
        title: "選択バー",
        caption: "マウスでテキストを選択すると、その横に小さなアクションバーが表示されます。選択内容をmacOSに伝えないAppでは表示されません。",
        copy: "コピー",
        tools: "バーに表示するツール",
        doubleClick: "ダブルクリックで開く"
    )

    static let ko = SelectionBarStrings(
        title: "선택 막대",
        caption: "마우스로 텍스트를 선택하면 옆에 작은 동작 막대가 나타납니다. 선택 내용을 macOS와 공유하지 않는 앱에서는 나타나지 않습니다.",
        copy: "복사",
        tools: "막대에 표시할 도구",
        doubleClick: "두 번 클릭하여 열기"
    )

    static let zhHans = SelectionBarStrings(
        title: "选择栏",
        caption: "用鼠标选择文本后，旁边会出现一个小操作栏。不向 macOS 提供所选内容的 App 中不会出现。",
        copy: "拷贝",
        tools: "选择栏中的工具",
        doubleClick: "连按两次打开"
    )

    static let zhTW = SelectionBarStrings(
        title: "選取列",
        caption: "用滑鼠選取文字後，旁邊會出現一個小動作列。不向 macOS 提供選取內容的 App 中不會出現。",
        copy: "拷貝",
        tools: "選取列中的工具",
        doubleClick: "按兩下打開"
    )

    static let zhHK = SelectionBarStrings(
        title: "選取列",
        caption: "用滑鼠選取文字後，旁邊會出現一個小動作列。不向 macOS 提供選取內容的 App 中不會出現。",
        copy: "拷貝",
        tools: "選取列中的工具",
        doubleClick: "按兩下打開"
    )

    static let uk = SelectionBarStrings(
        title: "Панель виділення",
        caption: "Виділіть текст мишею, і поруч з’явиться невелика панель дій. У програмах, які не повідомляють macOS про виділення, вона не з’являється.",
        copy: "Скопіювати",
        tools: "Інструменти на панелі",
        doubleClick: "Відкривати подвійним клацанням"
    )
}
