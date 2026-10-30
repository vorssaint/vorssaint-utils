// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AutoQuitDockAppsStrings {
    let listTitle: String
    let caption: String
    let addButton: String
    let removeButton: String
    let emptyNote: String
}

extension FeatureStrings {
    static func autoQuitDockApps(_ language: AppLanguage) -> AutoQuitDockAppsStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .cs: return .cs
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension AutoQuitDockAppsStrings {
    static let enUS = AutoQuitDockAppsStrings(
        listTitle: "Menu bar apps to quit",
        caption: "Menu bar apps stay open by default. Apps you select here can quit after their last window closes while they are in the Dock. Exceptions still keep them open.",
        addButton: "Add an app…",
        removeButton: "Remove",
        emptyNote: "No menu bar apps available to add."
    )

    static let ptBR = AutoQuitDockAppsStrings(
        listTitle: "Encerrar apps da barra de menus",
        caption: "Apps da barra de menus continuam abertos por padrão. Os selecionados aqui podem ser encerrados após fechar a última janela enquanto aparecem no Dock. As exceções continuam mantendo os apps abertos.",
        addButton: "Adicionar app…",
        removeButton: "Remover",
        emptyNote: "Nenhum app da barra de menus disponível para adicionar."
    )

    static let tr = AutoQuitDockAppsStrings(
        listTitle: "Çıkılacak menü çubuğu uygulamaları",
        caption: "Menü çubuğu uygulamaları varsayılan olarak açık kalır. Burada seçtiğiniz uygulamalardan, son pencereleri kapandıktan sonra Dock’ta görünüyorlarsa çıkılabilir. İstisnalar yine açık tutulur.",
        addButton: "Uygulama ekle…",
        removeButton: "Kaldır",
        emptyNote: "Eklenebilecek menü çubuğu uygulaması yok."
    )

    static let ru = AutoQuitDockAppsStrings(
        listTitle: "Завершать приложения строки меню",
        caption: "По умолчанию приложения строки меню остаются открытыми. Выбранные здесь приложения могут завершаться после закрытия последнего окна, если они отображаются в Dock. Приложения из списка исключений остаются открытыми.",
        addButton: "Добавить приложение…",
        removeButton: "Удалить",
        emptyNote: "Нет приложений строки меню, доступных для добавления."
    )

    static let es = AutoQuitDockAppsStrings(
        listTitle: "Cerrar apps de la barra de menús",
        caption: "Las apps de la barra de menús permanecen abiertas por defecto. Las apps que selecciones aquí pueden cerrarse al cerrar su última ventana si aparecen en el Dock. Las excepciones siguen manteniéndolas abiertas.",
        addButton: "Añadir app…",
        removeButton: "Quitar",
        emptyNote: "No hay apps de la barra de menús disponibles para añadir."
    )

    static let sk = AutoQuitDockAppsStrings(
        listTitle: "Ukončovať aplikácie v lište s ponukami",
        caption: "Aplikácie v lište s ponukami predvolene zostávajú otvorené. Vybrané aplikácie sa môžu ukončiť po zatvorení posledného okna, ak sa zobrazujú v Docku. Aplikácie v zozname výnimiek zostávajú otvorené.",
        addButton: "Pridať aplikáciu…",
        removeButton: "Odstrániť",
        emptyNote: "Nie sú k dispozícii žiadne aplikácie v lište s ponukami na pridanie."
    )

    static let cs = AutoQuitDockAppsStrings(
        listTitle: "Ukončovat aplikace na řádku nabídek",
        caption: "Aplikace na řádku nabídek ve výchozím stavu zůstávají otevřené. Vybrané aplikace se mohou ukončit po zavření posledního okna, pokud se zobrazují v Docku. Aplikace v seznamu výjimek zůstávají otevřené.",
        addButton: "Přidat aplikaci…",
        removeButton: "Odstranit",
        emptyNote: "Nejsou k dispozici žádné aplikace na řádku nabídek k přidání."
    )

    static let de = AutoQuitDockAppsStrings(
        listTitle: "Menüleisten-Apps zum Beenden",
        caption: "Menüleisten-Apps bleiben standardmäßig geöffnet. Hier ausgewählte Apps können nach dem Schließen ihres letzten Fensters beendet werden, wenn sie im Dock erscheinen. Ausnahmen bleiben weiterhin geöffnet.",
        addButton: "App hinzufügen…",
        removeButton: "Entfernen",
        emptyNote: "Keine Menüleisten-Apps zum Hinzufügen verfügbar."
    )

    static let fr = AutoQuitDockAppsStrings(
        listTitle: "Apps de la barre des menus à quitter",
        caption: "Les apps de la barre des menus restent ouvertes par défaut. Les apps sélectionnées ici peuvent quitter après la fermeture de leur dernière fenêtre si elles apparaissent dans le Dock. Les exceptions restent ouvertes.",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        emptyNote: "Aucune app de la barre des menus à ajouter."
    )

    static let it = AutoQuitDockAppsStrings(
        listTitle: "App della barra dei menu da chiudere",
        caption: "Le app della barra dei menu restano aperte per impostazione predefinita. Le app selezionate qui possono essere chiuse dopo la chiusura dell’ultima finestra se compaiono nel Dock. Le eccezioni restano aperte.",
        addButton: "Aggiungi app…",
        removeButton: "Rimuovi",
        emptyNote: "Nessuna app della barra dei menu disponibile da aggiungere."
    )

    static let ja = AutoQuitDockAppsStrings(
        listTitle: "終了するメニューバーApp",
        caption: "メニューバーAppは標準では起動したままになります。ここで選択したAppは、最後のウインドウを閉じた後もDockに表示されている場合、終了できます。例外リストのAppは起動したままになります。",
        addButton: "Appを追加…",
        removeButton: "削除",
        emptyNote: "追加できるメニューバーAppはありません。"
    )

    static let ko = AutoQuitDockAppsStrings(
        listTitle: "종료할 메뉴 막대 앱",
        caption: "메뉴 막대 앱은 기본적으로 계속 실행됩니다. 여기서 선택한 앱은 마지막 창을 닫은 뒤에도 Dock에 표시되어 있으면 종료될 수 있습니다. 예외 목록의 앱은 계속 실행됩니다.",
        addButton: "앱 추가…",
        removeButton: "제거",
        emptyNote: "추가할 수 있는 메뉴 막대 앱이 없습니다."
    )

    static let uk = AutoQuitDockAppsStrings(
        listTitle: "Завершувати програми смуги меню",
        caption: "Типово програми смуги меню залишаються відкритими. Вибрані тут програми можуть завершуватися після закриття останнього вікна, якщо вони відображаються в Dock. Програми зі списку винятків залишаються відкритими.",
        addButton: "Додати програму…",
        removeButton: "Видалити",
        emptyNote: "Немає програм смуги меню, доступних для додавання."
    )

    static let zhHans = AutoQuitDockAppsStrings(
        listTitle: "允许退出的菜单栏 App",
        caption: "菜单栏 App 默认保持运行。在此选择的 App 关闭最后一个窗口后，如果仍显示在程序坞中，则可以退出。例外列表中的 App 仍会保持运行。",
        addButton: "添加 App…",
        removeButton: "移除",
        emptyNote: "没有可添加的菜单栏 App。"
    )

    static let zhTW = AutoQuitDockAppsStrings(
        listTitle: "允許結束的選單列 App",
        caption: "選單列 App 預設會保持執行。在此選取的 App 關閉最後一個視窗後，如果仍顯示在 Dock 中，即可結束。例外清單中的 App 仍會保持執行。",
        addButton: "加入 App…",
        removeButton: "移除",
        emptyNote: "沒有可加入的選單列 App。"
    )

    static let zhHK = AutoQuitDockAppsStrings(
        listTitle: "允許結束的選單列 App",
        caption: "選單列 App 預設會保持執行。在此選取的 App 關閉最後一個視窗後，如果仍顯示在 Dock 中，即可結束。例外清單中的 App 仍會保持執行。",
        addButton: "加入 App…",
        removeButton: "移除",
        emptyNote: "沒有可加入的選單列 App。"
    )
}
