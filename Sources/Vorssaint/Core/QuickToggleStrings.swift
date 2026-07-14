// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the quick toggles tab. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct QuickToggleFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let darkModeToDark: String
    let darkModeToLight: String
    let darkModeCaption: String
    let emptyTrashTitle: String
    let emptyTrashCaption: String
    let emptyTrashConfirmTitle: String
    let emptyTrashConfirmMessage: String
    let emptyTrashConfirmButton: String
    let ejectTitle: String
    let ejectCaption: String
    let hiddenFilesShow: String
    let hiddenFilesHide: String
    let desktopIconsHide: String
    let desktopIconsShow: String
    let finderRestartCaption: String
    let lockScreenTitle: String
    let lockScreenCaption: String
    let displayOffTitle: String
    let displayOffCaption: String
    let screenSaverTitle: String
    let screenSaverCaption: String
    let actionFailed: String
}

extension FeatureStrings {
    static func quickToggles(_ language: AppLanguage) -> QuickToggleFeatureStrings {
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

extension QuickToggleFeatureStrings {
    static let enUS = QuickToggleFeatureStrings(
        pageTitle: "Quick toggles",
        hubDescription: "One-click actions like dark mode and Trash",
        panelCaption: "One-click system actions in the menu bar panel and in the quick panel.",
        darkModeToDark: "Switch to dark mode",
        darkModeToLight: "Switch to light mode",
        darkModeCaption: "Changes the appearance of the whole system.",
        emptyTrashTitle: "Empty the Trash",
        emptyTrashCaption: "Removes everything from the Trash.",
        emptyTrashConfirmTitle: "Empty the Trash?",
        emptyTrashConfirmMessage: "All items in the Trash will be removed. This cannot be undone.",
        emptyTrashConfirmButton: "Empty the Trash",
        ejectTitle: "Eject all disks",
        ejectCaption: "Safely ejects every external disk.",
        hiddenFilesShow: "Show hidden files",
        hiddenFilesHide: "Hide hidden files",
        desktopIconsHide: "Hide desktop icons",
        desktopIconsShow: "Show desktop icons",
        finderRestartCaption: "The Finder restarts to apply it.",
        lockScreenTitle: "Lock the screen",
        lockScreenCaption: "Asks for the password to come back.",
        displayOffTitle: "Turn off the display",
        displayOffCaption: "The Mac keeps running with the screen off.",
        screenSaverTitle: "Start the screen saver",
        screenSaverCaption: "Starts right away, on every display.",
        actionFailed: "Could not complete."
    )

    static let ptBR = QuickToggleFeatureStrings(
        pageTitle: "Ações rápidas",
        hubDescription: "Ações de um clique como modo escuro e Lixeira",
        panelCaption: "Ações do sistema com um clique no painel da barra de menus e no quick panel.",
        darkModeToDark: "Ativar o modo escuro",
        darkModeToLight: "Ativar o modo claro",
        darkModeCaption: "Muda a aparência do sistema inteiro.",
        emptyTrashTitle: "Esvaziar a Lixeira",
        emptyTrashCaption: "Remove tudo o que está na Lixeira.",
        emptyTrashConfirmTitle: "Esvaziar a Lixeira?",
        emptyTrashConfirmMessage: "Todos os itens da Lixeira serão removidos. Isso não pode ser desfeito.",
        emptyTrashConfirmButton: "Esvaziar a Lixeira",
        ejectTitle: "Ejetar todos os discos",
        ejectCaption: "Ejeta com segurança todos os discos externos.",
        hiddenFilesShow: "Mostrar arquivos ocultos",
        hiddenFilesHide: "Ocultar arquivos ocultos",
        desktopIconsHide: "Ocultar ícones da mesa",
        desktopIconsShow: "Mostrar ícones da mesa",
        finderRestartCaption: "O Finder reinicia para aplicar.",
        lockScreenTitle: "Bloquear a tela",
        lockScreenCaption: "Pede a senha para voltar.",
        displayOffTitle: "Desligar a tela",
        displayOffCaption: "O Mac continua funcionando com a tela apagada.",
        screenSaverTitle: "Iniciar o protetor de tela",
        screenSaverCaption: "Começa na hora, em todas as telas.",
        actionFailed: "Não foi possível concluir."
    )

    static let tr = QuickToggleFeatureStrings(
        pageTitle: "Hızlı eylemler",
        hubDescription: "Karanlık mod ve Çöp Sepeti gibi tek tıklık eylemler",
        panelCaption: "Menü çubuğu panelinde ve hızlı panelde tek tıkla sistem eylemleri.",
        darkModeToDark: "Karanlık moda geç",
        darkModeToLight: "Açık moda geç",
        darkModeCaption: "Tüm sistemin görünümünü değiştirir.",
        emptyTrashTitle: "Çöp Sepeti'ni boşalt",
        emptyTrashCaption: "Çöp Sepeti'ndeki her şeyi kaldırır.",
        emptyTrashConfirmTitle: "Çöp Sepeti boşaltılsın mı?",
        emptyTrashConfirmMessage: "Çöp Sepeti'ndeki tüm öğeler kaldırılacak. Bu geri alınamaz.",
        emptyTrashConfirmButton: "Çöp Sepeti'ni boşalt",
        ejectTitle: "Tüm diskleri çıkar",
        ejectCaption: "Tüm harici diskleri güvenle çıkarır.",
        hiddenFilesShow: "Gizli dosyaları göster",
        hiddenFilesHide: "Gizli dosyaları gizle",
        desktopIconsHide: "Masaüstü simgelerini gizle",
        desktopIconsShow: "Masaüstü simgelerini göster",
        finderRestartCaption: "Uygulamak için Finder yeniden başlar.",
        lockScreenTitle: "Ekranı kilitle",
        lockScreenCaption: "Geri dönmek için parola ister.",
        displayOffTitle: "Ekranı kapat",
        displayOffCaption: "Mac ekran kapalıyken çalışmaya devam eder.",
        screenSaverTitle: "Ekran koruyucuyu başlat",
        screenSaverCaption: "Hemen, tüm ekranlarda başlar.",
        actionFailed: "Tamamlanamadı."
    )

    static let ru = QuickToggleFeatureStrings(
        pageTitle: "Быстрые действия",
        hubDescription: "Действия в один клик: тёмный режим, Корзина и другие",
        panelCaption: "Системные действия в один клик в панели строки меню и в быстрой панели.",
        darkModeToDark: "Включить тёмный режим",
        darkModeToLight: "Включить светлый режим",
        darkModeCaption: "Меняет оформление всей системы.",
        emptyTrashTitle: "Очистить Корзину",
        emptyTrashCaption: "Удаляет всё из Корзины.",
        emptyTrashConfirmTitle: "Очистить Корзину?",
        emptyTrashConfirmMessage: "Все объекты в Корзине будут удалены. Это нельзя отменить.",
        emptyTrashConfirmButton: "Очистить Корзину",
        ejectTitle: "Извлечь все диски",
        ejectCaption: "Безопасно извлекает все внешние диски.",
        hiddenFilesShow: "Показать скрытые файлы",
        hiddenFilesHide: "Скрыть скрытые файлы",
        desktopIconsHide: "Скрыть значки рабочего стола",
        desktopIconsShow: "Показать значки рабочего стола",
        finderRestartCaption: "Finder перезапустится, чтобы применить.",
        lockScreenTitle: "Заблокировать экран",
        lockScreenCaption: "Для возврата потребуется пароль.",
        displayOffTitle: "Выключить экран",
        displayOffCaption: "Mac продолжает работать с выключенным экраном.",
        screenSaverTitle: "Запустить заставку",
        screenSaverCaption: "Запускается сразу на всех экранах.",
        actionFailed: "Не удалось выполнить."
    )

    static let es = QuickToggleFeatureStrings(
        pageTitle: "Acciones rápidas",
        hubDescription: "Acciones de un clic como modo oscuro y Papelera",
        panelCaption: "Acciones del sistema con un clic en el panel de la barra de menús y en el panel rápido.",
        darkModeToDark: "Cambiar al modo oscuro",
        darkModeToLight: "Cambiar al modo claro",
        darkModeCaption: "Cambia la apariencia de todo el sistema.",
        emptyTrashTitle: "Vaciar la Papelera",
        emptyTrashCaption: "Elimina todo lo que hay en la Papelera.",
        emptyTrashConfirmTitle: "¿Vaciar la Papelera?",
        emptyTrashConfirmMessage: "Se eliminarán todos los ítems de la Papelera. Esto no se puede deshacer.",
        emptyTrashConfirmButton: "Vaciar la Papelera",
        ejectTitle: "Expulsar todos los discos",
        ejectCaption: "Expulsa con seguridad todos los discos externos.",
        hiddenFilesShow: "Mostrar archivos ocultos",
        hiddenFilesHide: "Ocultar archivos ocultos",
        desktopIconsHide: "Ocultar iconos del escritorio",
        desktopIconsShow: "Mostrar iconos del escritorio",
        finderRestartCaption: "El Finder se reinicia para aplicarlo.",
        lockScreenTitle: "Bloquear la pantalla",
        lockScreenCaption: "Pide la contraseña para volver.",
        displayOffTitle: "Apagar la pantalla",
        displayOffCaption: "El Mac sigue funcionando con la pantalla apagada.",
        screenSaverTitle: "Iniciar el salvapantallas",
        screenSaverCaption: "Empieza al momento, en todas las pantallas.",
        actionFailed: "No se pudo completar."
    )

    static let de = QuickToggleFeatureStrings(
        pageTitle: "Schnellaktionen",
        hubDescription: "Aktionen mit einem Klick wie Dunkelmodus und Papierkorb",
        panelCaption: "Systemaktionen mit einem Klick im Menüleistenpanel und im Schnellpanel.",
        darkModeToDark: "Zum Dunkelmodus wechseln",
        darkModeToLight: "Zum Hellmodus wechseln",
        darkModeCaption: "Ändert das Erscheinungsbild des ganzen Systems.",
        emptyTrashTitle: "Papierkorb entleeren",
        emptyTrashCaption: "Entfernt alles aus dem Papierkorb.",
        emptyTrashConfirmTitle: "Papierkorb entleeren?",
        emptyTrashConfirmMessage: "Alle Objekte im Papierkorb werden entfernt. Das lässt sich nicht widerrufen.",
        emptyTrashConfirmButton: "Papierkorb entleeren",
        ejectTitle: "Alle Festplatten auswerfen",
        ejectCaption: "Wirft alle externen Festplatten sicher aus.",
        hiddenFilesShow: "Versteckte Dateien einblenden",
        hiddenFilesHide: "Versteckte Dateien ausblenden",
        desktopIconsHide: "Schreibtischsymbole ausblenden",
        desktopIconsShow: "Schreibtischsymbole einblenden",
        finderRestartCaption: "Der Finder startet dafür neu.",
        lockScreenTitle: "Bildschirm sperren",
        lockScreenCaption: "Fragt beim Zurückkommen nach dem Passwort.",
        displayOffTitle: "Bildschirm ausschalten",
        displayOffCaption: "Der Mac läuft mit ausgeschaltetem Bildschirm weiter.",
        screenSaverTitle: "Bildschirmschoner starten",
        screenSaverCaption: "Startet sofort, auf allen Bildschirmen.",
        actionFailed: "Konnte nicht abgeschlossen werden."
    )

    static let fr = QuickToggleFeatureStrings(
        pageTitle: "Actions rapides",
        hubDescription: "Actions en un clic comme le mode sombre et la Corbeille",
        panelCaption: "Actions système en un clic dans le panneau de la barre des menus et dans le panneau rapide.",
        darkModeToDark: "Passer en mode sombre",
        darkModeToLight: "Passer en mode clair",
        darkModeCaption: "Change l'apparence de tout le système.",
        emptyTrashTitle: "Vider la Corbeille",
        emptyTrashCaption: "Supprime tout le contenu de la Corbeille.",
        emptyTrashConfirmTitle: "Vider la Corbeille ?",
        emptyTrashConfirmMessage: "Tous les éléments de la Corbeille seront supprimés. Cette action est définitive.",
        emptyTrashConfirmButton: "Vider la Corbeille",
        ejectTitle: "Éjecter tous les disques",
        ejectCaption: "Éjecte en toute sécurité tous les disques externes.",
        hiddenFilesShow: "Afficher les fichiers masqués",
        hiddenFilesHide: "Masquer les fichiers masqués",
        desktopIconsHide: "Masquer les icônes du bureau",
        desktopIconsShow: "Afficher les icônes du bureau",
        finderRestartCaption: "Le Finder redémarre pour appliquer.",
        lockScreenTitle: "Verrouiller l'écran",
        lockScreenCaption: "Demande le mot de passe au retour.",
        displayOffTitle: "Éteindre l'écran",
        displayOffCaption: "Le Mac continue de fonctionner écran éteint.",
        screenSaverTitle: "Lancer l'économiseur d'écran",
        screenSaverCaption: "Démarre aussitôt, sur tous les écrans.",
        actionFailed: "Impossible de terminer."
    )

    static let it = QuickToggleFeatureStrings(
        pageTitle: "Azioni rapide",
        hubDescription: "Azioni con un clic come modalità scura e Cestino",
        panelCaption: "Azioni di sistema con un clic nel pannello della barra dei menu e nel pannello rapido.",
        darkModeToDark: "Passa alla modalità scura",
        darkModeToLight: "Passa alla modalità chiara",
        darkModeCaption: "Cambia l'aspetto di tutto il sistema.",
        emptyTrashTitle: "Svuota il Cestino",
        emptyTrashCaption: "Rimuove tutto il contenuto del Cestino.",
        emptyTrashConfirmTitle: "Svuotare il Cestino?",
        emptyTrashConfirmMessage: "Tutti gli elementi nel Cestino verranno rimossi. Non si può annullare.",
        emptyTrashConfirmButton: "Svuota il Cestino",
        ejectTitle: "Espelli tutti i dischi",
        ejectCaption: "Espelle in sicurezza tutti i dischi esterni.",
        hiddenFilesShow: "Mostra i file nascosti",
        hiddenFilesHide: "Nascondi i file nascosti",
        desktopIconsHide: "Nascondi le icone della scrivania",
        desktopIconsShow: "Mostra le icone della scrivania",
        finderRestartCaption: "Il Finder si riavvia per applicare.",
        lockScreenTitle: "Blocca lo schermo",
        lockScreenCaption: "Chiede la password per tornare.",
        displayOffTitle: "Spegni lo schermo",
        displayOffCaption: "Il Mac continua a funzionare con lo schermo spento.",
        screenSaverTitle: "Avvia il salvaschermo",
        screenSaverCaption: "Parte subito, su tutti gli schermi.",
        actionFailed: "Impossibile completare."
    )

    static let ja = QuickToggleFeatureStrings(
        pageTitle: "クイックアクション",
        hubDescription: "ダークモードやゴミ箱などのワンクリック操作",
        panelCaption: "メニューバーパネルとクイックパネルで使えるワンクリックのシステム操作です。",
        darkModeToDark: "ダークモードに切り替える",
        darkModeToLight: "ライトモードに切り替える",
        darkModeCaption: "システム全体の外観を変えます。",
        emptyTrashTitle: "ゴミ箱を空にする",
        emptyTrashCaption: "ゴミ箱の中身をすべて削除します。",
        emptyTrashConfirmTitle: "ゴミ箱を空にしますか?",
        emptyTrashConfirmMessage: "ゴミ箱内のすべての項目が削除されます。この操作は取り消せません。",
        emptyTrashConfirmButton: "ゴミ箱を空にする",
        ejectTitle: "すべてのディスクを取り出す",
        ejectCaption: "すべての外部ディスクを安全に取り出します。",
        hiddenFilesShow: "不可視ファイルを表示",
        hiddenFilesHide: "不可視ファイルを隠す",
        desktopIconsHide: "デスクトップのアイコンを隠す",
        desktopIconsShow: "デスクトップのアイコンを表示",
        finderRestartCaption: "適用のため Finder が再起動します。",
        lockScreenTitle: "画面をロック",
        lockScreenCaption: "戻るときにパスワードを求めます。",
        displayOffTitle: "ディスプレイをオフにする",
        displayOffCaption: "画面を消しても Mac は動き続けます。",
        screenSaverTitle: "スクリーンセーバを開始",
        screenSaverCaption: "すべてのディスプレイですぐに始まります。",
        actionFailed: "完了できませんでした。"
    )

    static let ko = QuickToggleFeatureStrings(
        pageTitle: "빠른 동작",
        hubDescription: "다크 모드, 휴지통 등 클릭 한 번의 동작",
        panelCaption: "메뉴 막대 패널과 퀵 패널에서 클릭 한 번으로 실행하는 시스템 동작입니다.",
        darkModeToDark: "다크 모드로 전환",
        darkModeToLight: "라이트 모드로 전환",
        darkModeCaption: "시스템 전체의 화면 모드를 바꿉니다.",
        emptyTrashTitle: "휴지통 비우기",
        emptyTrashCaption: "휴지통의 모든 항목을 제거합니다.",
        emptyTrashConfirmTitle: "휴지통을 비울까요?",
        emptyTrashConfirmMessage: "휴지통의 모든 항목이 제거됩니다. 되돌릴 수 없습니다.",
        emptyTrashConfirmButton: "휴지통 비우기",
        ejectTitle: "모든 디스크 추출",
        ejectCaption: "모든 외장 디스크를 안전하게 추출합니다.",
        hiddenFilesShow: "숨겨진 파일 보기",
        hiddenFilesHide: "숨겨진 파일 가리기",
        desktopIconsHide: "데스크탑 아이콘 가리기",
        desktopIconsShow: "데스크탑 아이콘 보기",
        finderRestartCaption: "적용을 위해 Finder가 다시 시작됩니다.",
        lockScreenTitle: "화면 잠금",
        lockScreenCaption: "돌아올 때 암호를 요구합니다.",
        displayOffTitle: "디스플레이 끄기",
        displayOffCaption: "화면이 꺼져도 Mac은 계속 작동합니다.",
        screenSaverTitle: "화면 보호기 시작",
        screenSaverCaption: "모든 디스플레이에서 바로 시작됩니다.",
        actionFailed: "완료할 수 없습니다."
    )

    static let zhHans = QuickToggleFeatureStrings(
        pageTitle: "快捷操作",
        hubDescription: "深色模式、废纸篓等一键操作",
        panelCaption: "在菜单栏面板和快捷面板中一键执行的系统操作。",
        darkModeToDark: "切换到深色模式",
        darkModeToLight: "切换到浅色模式",
        darkModeCaption: "更改整个系统的外观。",
        emptyTrashTitle: "清倒废纸篓",
        emptyTrashCaption: "移除废纸篓中的所有内容。",
        emptyTrashConfirmTitle: "要清倒废纸篓吗?",
        emptyTrashConfirmMessage: "废纸篓中的所有项目都将被移除。此操作无法撤销。",
        emptyTrashConfirmButton: "清倒废纸篓",
        ejectTitle: "推出所有磁盘",
        ejectCaption: "安全推出所有外置磁盘。",
        hiddenFilesShow: "显示隐藏的文件",
        hiddenFilesHide: "不显示隐藏的文件",
        desktopIconsHide: "隐藏桌面图标",
        desktopIconsShow: "显示桌面图标",
        finderRestartCaption: "Finder 将重新启动以应用。",
        lockScreenTitle: "锁定屏幕",
        lockScreenCaption: "返回时需要输入密码。",
        displayOffTitle: "关闭显示器",
        displayOffCaption: "屏幕关闭后 Mac 继续运行。",
        screenSaverTitle: "启动屏幕保护程序",
        screenSaverCaption: "在所有显示器上立即启动。",
        actionFailed: "无法完成。"
    )

    static let zhTW = QuickToggleFeatureStrings(
        pageTitle: "快速動作",
        hubDescription: "深色模式、垃圾桶等一鍵動作",
        panelCaption: "在選單列面板和快速面板中一鍵執行的系統動作。",
        darkModeToDark: "切換到深色模式",
        darkModeToLight: "切換到淺色模式",
        darkModeCaption: "更改整個系統的外觀。",
        emptyTrashTitle: "清空垃圾桶",
        emptyTrashCaption: "移除垃圾桶中的所有內容。",
        emptyTrashConfirmTitle: "要清空垃圾桶嗎?",
        emptyTrashConfirmMessage: "垃圾桶中的所有項目都會被移除。此操作無法復原。",
        emptyTrashConfirmButton: "清空垃圾桶",
        ejectTitle: "退出所有磁碟",
        ejectCaption: "安全退出所有外接磁碟。",
        hiddenFilesShow: "顯示隱藏的檔案",
        hiddenFilesHide: "不顯示隱藏的檔案",
        desktopIconsHide: "隱藏桌面圖像",
        desktopIconsShow: "顯示桌面圖像",
        finderRestartCaption: "Finder 會重新啟動以套用。",
        lockScreenTitle: "鎖定螢幕",
        lockScreenCaption: "返回時需要輸入密碼。",
        displayOffTitle: "關閉顯示器",
        displayOffCaption: "螢幕關閉後 Mac 仍繼續運作。",
        screenSaverTitle: "啟動螢幕保護程式",
        screenSaverCaption: "在所有顯示器上立即啟動。",
        actionFailed: "無法完成。"
    )

    static let zhHK = QuickToggleFeatureStrings(
        pageTitle: "快速動作",
        hubDescription: "深色模式、垃圾桶等一鍵動作",
        panelCaption: "在選單列面板和快速面板中一鍵執行的系統動作。",
        darkModeToDark: "切換至深色模式",
        darkModeToLight: "切換至淺色模式",
        darkModeCaption: "更改整個系統的外觀。",
        emptyTrashTitle: "清空垃圾桶",
        emptyTrashCaption: "移除垃圾桶中的所有內容。",
        emptyTrashConfirmTitle: "要清空垃圾桶嗎?",
        emptyTrashConfirmMessage: "垃圾桶中的所有項目都會被移除。此操作無法復原。",
        emptyTrashConfirmButton: "清空垃圾桶",
        ejectTitle: "推出所有磁碟",
        ejectCaption: "安全推出所有外置磁碟。",
        hiddenFilesShow: "顯示隱藏的檔案",
        hiddenFilesHide: "不顯示隱藏的檔案",
        desktopIconsHide: "隱藏桌面圖像",
        desktopIconsShow: "顯示桌面圖像",
        finderRestartCaption: "Finder 會重新啟動以套用。",
        lockScreenTitle: "鎖定螢幕",
        lockScreenCaption: "返回時需要輸入密碼。",
        displayOffTitle: "關閉顯示器",
        displayOffCaption: "螢幕關閉後 Mac 仍繼續運作。",
        screenSaverTitle: "啟動螢幕保護程式",
        screenSaverCaption: "在所有顯示器上立即啟動。",
        actionFailed: "無法完成。"
    )
}
