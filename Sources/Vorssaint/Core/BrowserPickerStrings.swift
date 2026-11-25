// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct BrowserPickerStrings {
    let title: String
    let description: String
    let order: String
    let orderHint: String
    let scanBrowsers: String
    let openPicker: String
    let makeDefault: String
    let defaultActive: String
    let defaultHint: String
    let empty: String
}

extension FeatureStrings {
    static func browserPicker(_ language: AppLanguage) -> BrowserPickerStrings {
        switch language {
        case .enUS: return BrowserPickerStrings(
            title: "Browser Picker",
            description: "Choose a browser when opening web links.",
            order: "Browser order",
            orderHint: "Drag browsers to change their order. Use the switches to choose which appear in the picker.",
            scanBrowsers: "Scan for new browsers",
            openPicker: "Open browser picker",
            makeDefault: "Use Vorssaint for web links",
            defaultActive: "Vorssaint handles web links",
            defaultHint: "macOS will ask to change your default browser. To stop using the picker for links, choose another default browser in System Settings.",
            empty: "No web browsers found. Install a browser and refresh.")
        case .es: return BrowserPickerStrings(
            title: "Selector de navegador",
            description: "Elige un navegador al abrir enlaces web.",
            order: "Orden de navegadores",
            orderHint: "Arrastra los navegadores para cambiar su orden. Usa los interruptores para elegir cuáles aparecen.",
            scanBrowsers: "Buscar nuevos navegadores",
            openPicker: "Abrir selector de navegador",
            makeDefault: "Usar Vorssaint para enlaces web",
            defaultActive: "Vorssaint gestiona los enlaces web",
            defaultHint: "macOS pedirá cambiar el navegador predeterminado. Para dejar de usar el selector para enlaces, elige otro navegador en Ajustes del Sistema.",
            empty: "No se encontraron navegadores. Instala uno y actualiza.")
        case .ptBR: return BrowserPickerStrings(
            title: "Seletor de navegador",
            description: "Escolha um navegador ao abrir links da web.",
            order: "Ordem dos navegadores",
            orderHint: "Arraste os navegadores para mudar a ordem. Use os interruptores para escolher quais aparecem.",
            scanBrowsers: "Buscar novos navegadores",
            openPicker: "Abrir seletor de navegador",
            makeDefault: "Usar Vorssaint para links",
            defaultActive: "Vorssaint abre os links",
            defaultHint: "O macOS pedirá para mudar o navegador padrão. Para parar de usar o seletor, escolha outro navegador nos Ajustes do Sistema.",
            empty: "Nenhum navegador encontrado. Instale um e atualize.")
        case .de: return BrowserPickerStrings(
            title: "Browserauswahl",
            description: "Wähle beim Öffnen von Weblinks einen Browser.",
            order: "Browserreihenfolge",
            orderHint: "Ziehe Browser, um ihre Reihenfolge zu ändern. Wähle mit den Schaltern, welche angezeigt werden.",
            scanBrowsers: "Nach neuen Browsern suchen",
            openPicker: "Browserauswahl öffnen",
            makeDefault: "Vorssaint für Weblinks verwenden",
            defaultActive: "Vorssaint öffnet Weblinks",
            defaultHint: "macOS fragt nach dem Wechsel des Standardbrowsers. Wähle in den Systemeinstellungen einen anderen Standardbrowser, um die Auswahl für Links zu beenden.",
            empty: "Keine Browser gefunden. Installiere einen Browser und aktualisiere die Liste.")
        case .fr: return BrowserPickerStrings(
            title: "Sélecteur de navigateur",
            description: "Choisissez un navigateur pour ouvrir les liens web.",
            order: "Ordre des navigateurs",
            orderHint: "Faites glisser les navigateurs pour les réordonner. Utilisez les interrupteurs pour choisir ceux à afficher.",
            scanBrowsers: "Rechercher de nouveaux navigateurs",
            openPicker: "Ouvrir le sélecteur",
            makeDefault: "Utiliser Vorssaint pour les liens",
            defaultActive: "Vorssaint ouvre les liens",
            defaultHint: "macOS demandera de changer le navigateur par défaut. Pour ne plus utiliser le sélecteur, choisissez un autre navigateur dans Réglages Système.",
            empty: "Aucun navigateur trouvé. Installez-en un et actualisez.")
        case .it: return BrowserPickerStrings(
            title: "Selettore browser",
            description: "Scegli un browser per aprire i link web.",
            order: "Ordine dei browser",
            orderHint: "Trascina i browser per riordinarli. Usa gli interruttori per scegliere quali mostrare.",
            scanBrowsers: "Cerca nuovi browser",
            openPicker: "Apri selettore browser",
            makeDefault: "Usa Vorssaint per i link",
            defaultActive: "Vorssaint apre i link",
            defaultHint: "macOS chiederà di cambiare il browser predefinito. Per non usare più il selettore, scegli un altro browser nelle Impostazioni di Sistema.",
            empty: "Nessun browser trovato. Installane uno e aggiorna.")
        case .sk: return BrowserPickerStrings(
            title: "Výber prehliadača",
            description: "Vyberte prehliadač pri otváraní webových odkazov.",
            order: "Poradie prehliadačov",
            orderHint: "Presunutím prehliadačov zmeňte poradie. Prepínačmi vyberte, ktoré sa zobrazia.",
            scanBrowsers: "Vyhľadať nové prehliadače",
            openPicker: "Otvoriť výber prehliadača",
            makeDefault: "Používať Vorssaint pre odkazy",
            defaultActive: "Vorssaint otvára odkazy",
            defaultHint: "macOS požiada o zmenu predvoleného prehliadača. Ak nechcete používať výber pre odkazy, zvoľte iný prehliadač v Systémových nastaveniach.",
            empty: "Nenašli sa žiadne prehliadače. Nainštalujte prehliadač a obnovte zoznam.")
        case .tr: return BrowserPickerStrings(
            title: "Tarayıcı seçici",
            description: "Web bağlantılarını açarken bir tarayıcı seçin.",
            order: "Tarayıcı sırası",
            orderHint: "Sıralamayı değiştirmek için tarayıcıları sürükleyin. Görünecek olanları anahtarlarla seçin.",
            scanBrowsers: "Yeni tarayıcıları tara",
            openPicker: "Tarayıcı seçiciyi aç",
            makeDefault: "Bağlantılar için Vorssaint kullan",
            defaultActive: "Bağlantıları Vorssaint açar",
            defaultHint: "macOS varsayılan tarayıcıyı değiştirmenizi isteyecek. Bağlantılarda seçiciyi kullanmamak için Sistem Ayarları’ndan başka bir tarayıcı seçin.",
            empty: "Tarayıcı bulunamadı. Bir tarayıcı yükleyip yenileyin.")
        case .ru: return BrowserPickerStrings(
            title: "Выбор браузера",
            description: "Выберите браузер при открытии веб-ссылок.",
            order: "Порядок браузеров",
            orderHint: "Перетаскивайте браузеры для изменения порядка. Переключателями выберите, какие показывать.",
            scanBrowsers: "Найти новые браузеры",
            openPicker: "Открыть выбор браузера",
            makeDefault: "Использовать Vorssaint для ссылок",
            defaultActive: "Vorssaint открывает ссылки",
            defaultHint: "macOS предложит сменить браузер по умолчанию. Чтобы отключить выбор для ссылок, выберите другой браузер в Системных настройках.",
            empty: "Браузеры не найдены. Установите браузер и обновите список.")
        case .uk: return BrowserPickerStrings(
            title: "Вибір браузера",
            description: "Виберіть браузер для відкриття вебпосилань.",
            order: "Порядок браузерів",
            orderHint: "Перетягуйте браузери для зміни порядку. Перемикачами виберіть, які показувати.",
            scanBrowsers: "Знайти нові браузери",
            openPicker: "Відкрити вибір браузера",
            makeDefault: "Використовувати Vorssaint для посилань",
            defaultActive: "Vorssaint відкриває посилання",
            defaultHint: "macOS запропонує змінити типовий браузер. Щоб вимкнути вибір для посилань, виберіть інший браузер у Системних параметрах.",
            empty: "Браузери не знайдено. Встановіть браузер і оновіть список.")
        case .ja: return BrowserPickerStrings(
            title: "ブラウザ選択",
            description: "ウェブリンクを開くブラウザを選びます。",
            order: "ブラウザの順序",
            orderHint: "ブラウザをドラッグして並べ替えます。スイッチで表示するブラウザを選びます。",
            scanBrowsers: "新しいブラウザを検索",
            openPicker: "ブラウザ選択を開く",
            makeDefault: "リンクをVorssaintで開く",
            defaultActive: "Vorssaintがリンクを開きます",
            defaultHint: "macOSがデフォルトブラウザの変更を確認します。リンクの選択を停止するには、システム設定で別のデフォルトブラウザを選んでください。",
            empty: "ブラウザが見つかりません。インストールして更新してください。")
        case .ko: return BrowserPickerStrings(
            title: "브라우저 선택",
            description: "웹 링크를 열 브라우저를 선택하세요.",
            order: "브라우저 순서",
            orderHint: "브라우저를 드래그하여 순서를 바꾸세요. 스위치로 표시할 브라우저를 선택하세요.",
            scanBrowsers: "새 브라우저 검색",
            openPicker: "브라우저 선택 열기",
            makeDefault: "링크에 Vorssaint 사용",
            defaultActive: "Vorssaint가 링크를 엽니다",
            defaultHint: "macOS에서 기본 브라우저 변경을 확인합니다. 링크 선택을 중지하려면 시스템 설정에서 다른 기본 브라우저를 선택하세요.",
            empty: "브라우저를 찾을 수 없습니다. 설치한 후 새로 고치세요.")
        case .zhHans: return BrowserPickerStrings(
            title: "浏览器选择器",
            description: "选择用于打开网页链接的浏览器。",
            order: "浏览器顺序",
            orderHint: "拖动浏览器调整顺序，使用开关选择要显示的浏览器。",
            scanBrowsers: "扫描新浏览器",
            openPicker: "打开浏览器选择器",
            makeDefault: "使用 Vorssaint 打开链接",
            defaultActive: "Vorssaint 已接管网页链接",
            defaultHint: "macOS 将请求更改默认浏览器。若要停止为链接显示选择器，请在系统设置中选择其他默认浏览器。",
            empty: "未找到浏览器。请安装浏览器并刷新。")
        case .zhTW: return BrowserPickerStrings(
            title: "瀏覽器選擇器",
            description: "選擇用於開啟網頁連結的瀏覽器。",
            order: "瀏覽器順序",
            orderHint: "拖曳瀏覽器調整順序，使用開關選擇要顯示的瀏覽器。",
            scanBrowsers: "掃描新瀏覽器",
            openPicker: "開啟瀏覽器選擇器",
            makeDefault: "使用 Vorssaint 開啟連結",
            defaultActive: "Vorssaint 已接管網頁連結",
            defaultHint: "macOS 將要求更改預設瀏覽器。若要停止為連結顯示選擇器，請在系統設定中選擇其他預設瀏覽器。",
            empty: "找不到瀏覽器。請安裝瀏覽器並重新整理。")
        case .zhHK: return BrowserPickerStrings(
            title: "瀏覽器選擇器",
            description: "選擇用於開啟網頁連結的瀏覽器。",
            order: "瀏覽器次序",
            orderHint: "拖移瀏覽器調整次序，使用開關選擇要顯示的瀏覽器。",
            scanBrowsers: "掃描新瀏覽器",
            openPicker: "開啟瀏覽器選擇器",
            makeDefault: "使用 Vorssaint 開啟連結",
            defaultActive: "Vorssaint 已接管網頁連結",
            defaultHint: "macOS 將要求更改預設瀏覽器。如要停止為連結顯示選擇器，請在系統設定中選擇其他預設瀏覽器。",
            empty: "找不到瀏覽器。請安裝瀏覽器並重新整理。")
        }
    }
}

struct BrowserPickerOptionsStrings {
    let showNumbers: String
    let position: String
    let center: String
    let cursor: String
    let noneEnabled: String
}

extension FeatureStrings {
    static func browserPickerOptions(_ language: AppLanguage) -> BrowserPickerOptionsStrings {
        switch language {
        case .enUS: return BrowserPickerOptionsStrings(
            showNumbers: "Show number shortcuts",
            position: "Picker position",
            center: "Center of screen",
            cursor: "Near cursor",
            noneEnabled: "No browsers selected. Enable a browser in Settings → Quick Tools → Browser Picker.")
        case .es: return BrowserPickerOptionsStrings(
            showNumbers: "Mostrar atajos numéricos",
            position: "Posición del selector",
            center: "Centro de la pantalla",
            cursor: "Cerca del cursor",
            noneEnabled: "No hay navegadores seleccionados. Activa uno en Ajustes → Herramientas rápidas → Selector de navegador.")
        case .ptBR: return BrowserPickerOptionsStrings(
            showNumbers: "Mostrar atalhos numéricos",
            position: "Posição do seletor",
            center: "Centro da tela",
            cursor: "Perto do cursor",
            noneEnabled: "Nenhum navegador selecionado. Ative um em Ajustes → Ferramentas rápidas → Seletor de navegador.")
        case .de: return BrowserPickerOptionsStrings(
            showNumbers: "Ziffernkürzel anzeigen",
            position: "Position der Browserauswahl",
            center: "Bildschirmmitte",
            cursor: "Beim Mauszeiger",
            noneEnabled: "Kein Browser ausgewählt. Aktiviere einen unter Einstellungen → Schnellwerkzeuge → Browserauswahl.")
        case .fr: return BrowserPickerOptionsStrings(
            showNumbers: "Afficher les raccourcis numériques",
            position: "Position du sélecteur",
            center: "Au centre de l’écran",
            cursor: "Près du curseur",
            noneEnabled: "Aucun navigateur sélectionné. Activez-en un dans Réglages → Outils rapides → Sélecteur de navigateur.")
        case .it: return BrowserPickerOptionsStrings(
            showNumbers: "Mostra scorciatoie numeriche",
            position: "Posizione del selettore",
            center: "Centro dello schermo",
            cursor: "Vicino al cursore",
            noneEnabled: "Nessun browser selezionato. Attivane uno in Impostazioni → Strumenti rapidi → Selettore browser.")
        case .sk: return BrowserPickerOptionsStrings(
            showNumbers: "Zobraziť číselné skratky",
            position: "Poloha výberu",
            center: "Stred obrazovky",
            cursor: "Pri kurzore",
            noneEnabled: "Nie je vybraný žiadny prehliadač. Zapnite ho v Nastavenia → Rýchle nástroje → Výber prehliadača.")
        case .tr: return BrowserPickerOptionsStrings(
            showNumbers: "Sayı kısayollarını göster",
            position: "Seçici konumu",
            center: "Ekranın ortasında",
            cursor: "İmlecin yanında",
            noneEnabled: "Tarayıcı seçilmedi. Ayarlar → Hızlı araçlar → Tarayıcı seçici bölümünden birini etkinleştirin.")
        case .ru: return BrowserPickerOptionsStrings(
            showNumbers: "Показывать цифровые сочетания",
            position: "Положение выбора",
            center: "В центре экрана",
            cursor: "Рядом с курсором",
            noneEnabled: "Браузеры не выбраны. Включите браузер в Настройки → Быстрые инструменты → Выбор браузера.")
        case .uk: return BrowserPickerOptionsStrings(
            showNumbers: "Показувати цифрові скорочення",
            position: "Розташування вибору",
            center: "У центрі екрана",
            cursor: "Біля курсора",
            noneEnabled: "Браузери не вибрано. Увімкніть браузер у Параметри → Швидкі інструменти → Вибір браузера.")
        case .ja: return BrowserPickerOptionsStrings(
            showNumbers: "数字ショートカットを表示",
            position: "表示位置",
            center: "画面の中央",
            cursor: "カーソルの近く",
            noneEnabled: "ブラウザが選択されていません。設定 → クイックツール → ブラウザ選択で有効にしてください。")
        case .ko: return BrowserPickerOptionsStrings(
            showNumbers: "숫자 단축키 표시",
            position: "선택기 위치",
            center: "화면 중앙",
            cursor: "커서 근처",
            noneEnabled: "선택된 브라우저가 없습니다. 설정 → 빠른 도구 → 브라우저 선택에서 활성화하세요.")
        case .zhHans: return BrowserPickerOptionsStrings(
            showNumbers: "显示数字快捷键",
            position: "选择器位置",
            center: "屏幕中央",
            cursor: "光标附近",
            noneEnabled: "未选择浏览器。请在设置 → 快捷工具 → 浏览器选择器中启用浏览器。")
        case .zhTW: return BrowserPickerOptionsStrings(
            showNumbers: "顯示數字快捷鍵",
            position: "選擇器位置",
            center: "螢幕中央",
            cursor: "游標附近",
            noneEnabled: "未選擇瀏覽器。請在設定 → 快速工具 → 瀏覽器選擇器中啟用瀏覽器。")
        case .zhHK: return BrowserPickerOptionsStrings(
            showNumbers: "顯示數字快捷鍵",
            position: "選擇器位置",
            center: "螢幕中央",
            cursor: "游標附近",
            noneEnabled: "未選擇瀏覽器。請在設定 → 快速工具 → 瀏覽器選擇器中啟用瀏覽器。")
        }
    }
}
