// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import Foundation

struct SelectionActionsStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggleTitle: String
    let enableToggleCaption: String
    let displayStyleLabel: String
    let displayStyleIcon: String
    let displayStyleWord: String
    let maxVisibleLabel: String
    let maxVisibleCaption: String
    let permissionTitle: String
    let permissionBody: String
    let permissionButton: String
    let actionsSectionTitle: String
    let actionsSectionCaption: String
    let excludedSectionTitle: String
    let excludedAppsTitle: String
    let excludedAppsCaption: String
    let excludedAppsAddButton: String
    let excludedAppsRemoveButton: String
    let excludedDomainsTitle: String
    let excludedDomainsCaption: String
    let excludedDomainsPlaceholder: String
    let excludedDomainsAddButton: String
    let excludedDomainsRemoveButton: String

    let copyTitle: String
    let cutTitle: String
    let pasteTitle: String
    let deleteTitle: String

    let copyDescription: String
    let cutDescription: String
    let pasteDescription: String
    let deleteDescription: String

    func title(for action: SelectionAction) -> String {
        switch action {
        case .copy: return copyTitle
        case .cut: return cutTitle
        case .paste: return pasteTitle
        case .delete: return deleteTitle
        }
    }

    func description(for action: SelectionAction) -> String {
        switch action {
        case .copy: return copyDescription
        case .cut: return cutDescription
        case .paste: return pasteDescription
        case .delete: return deleteDescription
        }
    }
}

extension FeatureStrings {
    static func selectionActions(_ language: AppLanguage) -> SelectionActionsStrings {
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

extension SelectionActionsStrings {
    static let enUS = SelectionActionsStrings(
        pageTitle: "Selection Actions",
        hubDescription: "Quick actions on any text you select",
        enableToggleTitle: "Enable Selection Actions",
        enableToggleCaption: "Shows a small toolbar next to text you select in any app",
        displayStyleLabel: "Show actions as",
        displayStyleIcon: "Icons",
        displayStyleWord: "Words",
        maxVisibleLabel: "Show at most",
        maxVisibleCaption: "The rest collapse under a ▾ in the bar",
        permissionTitle: "Accessibility Access Needed",
        permissionBody: "Selection Actions reads what you select and can replace it, which requires Accessibility access.",
        permissionButton: "Grant Access",
        actionsSectionTitle: "Actions",
        actionsSectionCaption: "Drag to reorder. Only actions that make sense for the current selection appear in the bar.",
        excludedSectionTitle: "Excluded",
        excludedAppsTitle: "Apps",
        excludedAppsCaption: "Selection Actions never appears in these apps.",
        excludedAppsAddButton: "Add App…",
        excludedAppsRemoveButton: "Remove",
        excludedDomainsTitle: "Websites",
        excludedDomainsCaption: "One website per line. Works in Safari, Chrome, Edge, Brave and Firefox — other browsers may not report the page address.",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "Add",
        excludedDomainsRemoveButton: "Remove",
        copyTitle: "Copy",
        cutTitle: "Cut",
        pasteTitle: "Paste",
        deleteTitle: "Delete",
        copyDescription: "Copies the selection to the clipboard.",
        cutDescription: "Copies the selection, then removes it.",
        pasteDescription: "Replaces the selection with what's on the clipboard.",
        deleteDescription: "Removes the selection without copying it."
    )

    static let ptBR = SelectionActionsStrings(
        pageTitle: "Ações de Seleção",
        hubDescription: "Ações rápidas sobre qualquer texto selecionado",
        enableToggleTitle: "Ativar Ações de Seleção",
        enableToggleCaption: "Mostra uma pequena barra ao lado do texto selecionado em qualquer app",
        displayStyleLabel: "Mostrar ações como",
        displayStyleIcon: "Ícones",
        displayStyleWord: "Palavras",
        maxVisibleLabel: "Mostrar no máximo",
        maxVisibleCaption: "O restante fica dentro de um ▾ na barra",
        permissionTitle: "Acesso de Acessibilidade Necessário",
        permissionBody: "Ações de Seleção lê o texto selecionado e pode substituí-lo, o que exige acesso de Acessibilidade.",
        permissionButton: "Conceder Acesso",
        actionsSectionTitle: "Ações",
        actionsSectionCaption: "Arraste para reordenar. Só aparecem na barra as ações que fazem sentido para a seleção atual.",
        excludedSectionTitle: "Excluídos",
        excludedAppsTitle: "Apps",
        excludedAppsCaption: "Ações de Seleção nunca aparece nestes apps.",
        excludedAppsAddButton: "Adicionar App…",
        excludedAppsRemoveButton: "Remover",
        excludedDomainsTitle: "Sites",
        excludedDomainsCaption: "Um site por linha. Funciona no Safari, Chrome, Edge, Brave e Firefox — outros navegadores podem não informar o endereço da página.",
        excludedDomainsPlaceholder: "exemplo.com",
        excludedDomainsAddButton: "Adicionar",
        excludedDomainsRemoveButton: "Remover",
        copyTitle: "Copiar",
        cutTitle: "Recortar",
        pasteTitle: "Colar",
        deleteTitle: "Excluir",
        copyDescription: "Copia a seleção para a área de transferência.",
        cutDescription: "Copia a seleção e a remove em seguida.",
        pasteDescription: "Substitui a seleção pelo conteúdo da área de transferência.",
        deleteDescription: "Remove a seleção sem copiá-la."
    )

    static let tr = SelectionActionsStrings(
        pageTitle: "Seçim Eylemleri",
        hubDescription: "Seçtiğiniz herhangi bir metin üzerinde hızlı eylemler",
        enableToggleTitle: "Seçim Eylemlerini Etkinleştir",
        enableToggleCaption: "Herhangi bir uygulamada seçtiğiniz metnin yanında küçük bir araç çubuğu gösterir",
        displayStyleLabel: "Eylemleri şu şekilde göster",
        displayStyleIcon: "Simgeler",
        displayStyleWord: "Kelimeler",
        maxVisibleLabel: "En fazla şunu göster",
        maxVisibleCaption: "Kalanlar çubukta bir ▾ altında toplanır",
        permissionTitle: "Erişilebilirlik İzni Gerekli",
        permissionBody: "Seçim Eylemleri, seçtiğiniz metni okur ve değiştirebilir; bu da Erişilebilirlik izni gerektirir.",
        permissionButton: "İzin Ver",
        actionsSectionTitle: "Eylemler",
        actionsSectionCaption: "Yeniden sıralamak için sürükleyin. Çubukta yalnızca geçerli seçim için anlamlı olan eylemler görünür.",
        excludedSectionTitle: "Hariç Tutulanlar",
        excludedAppsTitle: "Uygulamalar",
        excludedAppsCaption: "Seçim Eylemleri bu uygulamalarda hiç görünmez.",
        excludedAppsAddButton: "Uygulama Ekle…",
        excludedAppsRemoveButton: "Kaldır",
        excludedDomainsTitle: "Web Siteleri",
        excludedDomainsCaption: "Satır başına bir web sitesi. Safari, Chrome, Edge, Brave ve Firefox'ta çalışır — diğer tarayıcılar sayfa adresini bildirmeyebilir.",
        excludedDomainsPlaceholder: "ornek.com",
        excludedDomainsAddButton: "Ekle",
        excludedDomainsRemoveButton: "Kaldır",
        copyTitle: "Kopyala",
        cutTitle: "Kes",
        pasteTitle: "Yapıştır",
        deleteTitle: "Sil",
        copyDescription: "Seçimi panoya kopyalar.",
        cutDescription: "Seçimi kopyalar, sonra kaldırır.",
        pasteDescription: "Seçimi panodaki içerikle değiştirir.",
        deleteDescription: "Seçimi kopyalamadan kaldırır."
    )

    static let ru = SelectionActionsStrings(
        pageTitle: "Действия с выделением",
        hubDescription: "Быстрые действия с любым выделенным текстом",
        enableToggleTitle: "Включить действия с выделением",
        enableToggleCaption: "Показывает небольшую панель рядом с выделенным текстом в любом приложении",
        displayStyleLabel: "Показывать действия как",
        displayStyleIcon: "Значки",
        displayStyleWord: "Слова",
        maxVisibleLabel: "Показывать не более",
        maxVisibleCaption: "Остальные скрываются под ▾ на панели",
        permissionTitle: "Требуется доступ Универсального доступа",
        permissionBody: "«Действия с выделением» считывает выделенный текст и может заменить его, для чего требуется доступ Универсального доступа.",
        permissionButton: "Предоставить доступ",
        actionsSectionTitle: "Действия",
        actionsSectionCaption: "Перетащите, чтобы изменить порядок. На панели показываются только действия, подходящие для текущего выделения.",
        excludedSectionTitle: "Исключения",
        excludedAppsTitle: "Приложения",
        excludedAppsCaption: "«Действия с выделением» никогда не появляются в этих приложениях.",
        excludedAppsAddButton: "Добавить приложение…",
        excludedAppsRemoveButton: "Удалить",
        excludedDomainsTitle: "Сайты",
        excludedDomainsCaption: "По одному сайту на строку. Работает в Safari, Chrome, Edge, Brave и Firefox — другие браузеры могут не сообщать адрес страницы.",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "Добавить",
        excludedDomainsRemoveButton: "Удалить",
        copyTitle: "Копировать",
        cutTitle: "Вырезать",
        pasteTitle: "Вставить",
        deleteTitle: "Удалить",
        copyDescription: "Копирует выделение в буфер обмена.",
        cutDescription: "Копирует выделение, затем удаляет его.",
        pasteDescription: "Заменяет выделение содержимым буфера обмена.",
        deleteDescription: "Удаляет выделение без копирования."
    )

    static let es = SelectionActionsStrings(
        pageTitle: "Acciones de Selección",
        hubDescription: "Acciones rápidas sobre cualquier texto seleccionado",
        enableToggleTitle: "Activar Acciones de Selección",
        enableToggleCaption: "Muestra una pequeña barra junto al texto que selecciones en cualquier app",
        displayStyleLabel: "Mostrar acciones como",
        displayStyleIcon: "Iconos",
        displayStyleWord: "Palabras",
        maxVisibleLabel: "Mostrar como máximo",
        maxVisibleCaption: "El resto queda dentro de un ▾ en la barra",
        permissionTitle: "Se necesita acceso de Accesibilidad",
        permissionBody: "Acciones de Selección lee el texto seleccionado y puede reemplazarlo, lo que requiere acceso de Accesibilidad.",
        permissionButton: "Conceder Acceso",
        actionsSectionTitle: "Acciones",
        actionsSectionCaption: "Arrastra para reordenar. Solo las acciones que tienen sentido para la selección actual aparecen en la barra.",
        excludedSectionTitle: "Excluidos",
        excludedAppsTitle: "Apps",
        excludedAppsCaption: "Acciones de Selección nunca aparece en estas apps.",
        excludedAppsAddButton: "Añadir App…",
        excludedAppsRemoveButton: "Eliminar",
        excludedDomainsTitle: "Sitios Web",
        excludedDomainsCaption: "Un sitio web por línea. Funciona en Safari, Chrome, Edge, Brave y Firefox; otros navegadores podrían no indicar la dirección de la página.",
        excludedDomainsPlaceholder: "ejemplo.com",
        excludedDomainsAddButton: "Añadir",
        excludedDomainsRemoveButton: "Eliminar",
        copyTitle: "Copiar",
        cutTitle: "Cortar",
        pasteTitle: "Pegar",
        deleteTitle: "Eliminar",
        copyDescription: "Copia la selección al portapapeles.",
        cutDescription: "Copia la selección y luego la elimina.",
        pasteDescription: "Reemplaza la selección con el contenido del portapapeles.",
        deleteDescription: "Elimina la selección sin copiarla."
    )

    static let de = SelectionActionsStrings(
        pageTitle: "Auswahlaktionen",
        hubDescription: "Schnelle Aktionen für jeden ausgewählten Text",
        enableToggleTitle: "Auswahlaktionen aktivieren",
        enableToggleCaption: "Zeigt eine kleine Leiste neben Text, den du in einer beliebigen App auswählst",
        displayStyleLabel: "Aktionen anzeigen als",
        displayStyleIcon: "Symbole",
        displayStyleWord: "Wörter",
        maxVisibleLabel: "Höchstens anzeigen",
        maxVisibleCaption: "Der Rest wird in der Leiste unter einem ▾ zusammengefasst",
        permissionTitle: "Bedienungshilfen-Zugriff erforderlich",
        permissionBody: "Auswahlaktionen liest den ausgewählten Text und kann ihn ersetzen, wofür Zugriff auf die Bedienungshilfen nötig ist.",
        permissionButton: "Zugriff gewähren",
        actionsSectionTitle: "Aktionen",
        actionsSectionCaption: "Zum Umsortieren ziehen. In der Leiste erscheinen nur Aktionen, die zur aktuellen Auswahl passen.",
        excludedSectionTitle: "Ausgeschlossen",
        excludedAppsTitle: "Apps",
        excludedAppsCaption: "Auswahlaktionen erscheint in diesen Apps nie.",
        excludedAppsAddButton: "App hinzufügen…",
        excludedAppsRemoveButton: "Entfernen",
        excludedDomainsTitle: "Websites",
        excludedDomainsCaption: "Eine Website pro Zeile. Funktioniert in Safari, Chrome, Edge, Brave und Firefox — andere Browser melden die Seitenadresse möglicherweise nicht.",
        excludedDomainsPlaceholder: "beispiel.de",
        excludedDomainsAddButton: "Hinzufügen",
        excludedDomainsRemoveButton: "Entfernen",
        copyTitle: "Kopieren",
        cutTitle: "Ausschneiden",
        pasteTitle: "Einfügen",
        deleteTitle: "Löschen",
        copyDescription: "Kopiert die Auswahl in die Zwischenablage.",
        cutDescription: "Kopiert die Auswahl und entfernt sie dann.",
        pasteDescription: "Ersetzt die Auswahl durch den Inhalt der Zwischenablage.",
        deleteDescription: "Entfernt die Auswahl, ohne sie zu kopieren."
    )

    static let fr = SelectionActionsStrings(
        pageTitle: "Actions de sélection",
        hubDescription: "Actions rapides sur tout texte sélectionné",
        enableToggleTitle: "Activer les actions de sélection",
        enableToggleCaption: "Affiche une petite barre à côté du texte sélectionné dans n'importe quelle app",
        displayStyleLabel: "Afficher les actions en",
        displayStyleIcon: "Icônes",
        displayStyleWord: "Mots",
        maxVisibleLabel: "Afficher au maximum",
        maxVisibleCaption: "Le reste se replie sous un ▾ dans la barre",
        permissionTitle: "Accès Accessibilité requis",
        permissionBody: "Actions de sélection lit le texte sélectionné et peut le remplacer, ce qui nécessite l'accès Accessibilité.",
        permissionButton: "Autoriser l'accès",
        actionsSectionTitle: "Actions",
        actionsSectionCaption: "Faites glisser pour réorganiser. Seules les actions pertinentes pour la sélection actuelle apparaissent dans la barre.",
        excludedSectionTitle: "Exclusions",
        excludedAppsTitle: "Apps",
        excludedAppsCaption: "Actions de sélection n'apparaît jamais dans ces apps.",
        excludedAppsAddButton: "Ajouter une app…",
        excludedAppsRemoveButton: "Supprimer",
        excludedDomainsTitle: "Sites web",
        excludedDomainsCaption: "Un site par ligne. Fonctionne dans Safari, Chrome, Edge, Brave et Firefox — les autres navigateurs peuvent ne pas signaler l'adresse de la page.",
        excludedDomainsPlaceholder: "exemple.com",
        excludedDomainsAddButton: "Ajouter",
        excludedDomainsRemoveButton: "Supprimer",
        copyTitle: "Copier",
        cutTitle: "Couper",
        pasteTitle: "Coller",
        deleteTitle: "Supprimer",
        copyDescription: "Copie la sélection dans le presse-papiers.",
        cutDescription: "Copie la sélection, puis la supprime.",
        pasteDescription: "Remplace la sélection par le contenu du presse-papiers.",
        deleteDescription: "Supprime la sélection sans la copier."
    )

    static let it = SelectionActionsStrings(
        pageTitle: "Azioni di selezione",
        hubDescription: "Azioni rapide su qualsiasi testo selezionato",
        enableToggleTitle: "Attiva Azioni di selezione",
        enableToggleCaption: "Mostra una piccola barra accanto al testo selezionato in qualsiasi app",
        displayStyleLabel: "Mostra le azioni come",
        displayStyleIcon: "Icone",
        displayStyleWord: "Parole",
        maxVisibleLabel: "Mostra al massimo",
        maxVisibleCaption: "Il resto si raccoglie sotto un ▾ nella barra",
        permissionTitle: "Accesso Accessibilità richiesto",
        permissionBody: "Azioni di selezione legge il testo selezionato e può sostituirlo, il che richiede l'accesso Accessibilità.",
        permissionButton: "Concedi accesso",
        actionsSectionTitle: "Azioni",
        actionsSectionCaption: "Trascina per riordinare. Nella barra compaiono solo le azioni pertinenti alla selezione attuale.",
        excludedSectionTitle: "Esclusi",
        excludedAppsTitle: "App",
        excludedAppsCaption: "Azioni di selezione non appare mai in queste app.",
        excludedAppsAddButton: "Aggiungi App…",
        excludedAppsRemoveButton: "Rimuovi",
        excludedDomainsTitle: "Siti Web",
        excludedDomainsCaption: "Un sito per riga. Funziona in Safari, Chrome, Edge, Brave e Firefox — altri browser potrebbero non segnalare l'indirizzo della pagina.",
        excludedDomainsPlaceholder: "esempio.com",
        excludedDomainsAddButton: "Aggiungi",
        excludedDomainsRemoveButton: "Rimuovi",
        copyTitle: "Copia",
        cutTitle: "Taglia",
        pasteTitle: "Incolla",
        deleteTitle: "Elimina",
        copyDescription: "Copia la selezione negli appunti.",
        cutDescription: "Copia la selezione, poi la rimuove.",
        pasteDescription: "Sostituisce la selezione con il contenuto degli appunti.",
        deleteDescription: "Rimuove la selezione senza copiarla."
    )

    static let ja = SelectionActionsStrings(
        pageTitle: "選択アクション",
        hubDescription: "選択したテキストに対するクイックアクション",
        enableToggleTitle: "選択アクションを有効にする",
        enableToggleCaption: "どのアプリでもテキストを選択すると、近くに小さなツールバーを表示します",
        displayStyleLabel: "アクションの表示形式",
        displayStyleIcon: "アイコン",
        displayStyleWord: "文字",
        maxVisibleLabel: "表示する最大数",
        maxVisibleCaption: "残りはバー内の▾にまとめられます",
        permissionTitle: "アクセシビリティのアクセスが必要です",
        permissionBody: "選択アクションは選択したテキストを読み取り、置き換えることがあるため、アクセシビリティへのアクセスが必要です。",
        permissionButton: "アクセスを許可",
        actionsSectionTitle: "アクション",
        actionsSectionCaption: "ドラッグして並べ替えられます。現在の選択に該当するアクションのみバーに表示されます。",
        excludedSectionTitle: "除外",
        excludedAppsTitle: "App",
        excludedAppsCaption: "選択アクションはこれらのAppでは表示されません。",
        excludedAppsAddButton: "Appを追加…",
        excludedAppsRemoveButton: "削除",
        excludedDomainsTitle: "Webサイト",
        excludedDomainsCaption: "1行に1サイト。Safari、Chrome、Edge、Brave、Firefoxで動作します — 他のブラウザではページのアドレスを取得できない場合があります。",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "追加",
        excludedDomainsRemoveButton: "削除",
        copyTitle: "コピー",
        cutTitle: "カット",
        pasteTitle: "ペースト",
        deleteTitle: "削除",
        copyDescription: "選択範囲をクリップボードにコピーします。",
        cutDescription: "選択範囲をコピーしてから削除します。",
        pasteDescription: "選択範囲をクリップボードの内容で置き換えます。",
        deleteDescription: "選択範囲をコピーせずに削除します。"
    )

    static let ko = SelectionActionsStrings(
        pageTitle: "선택 항목 작업",
        hubDescription: "선택한 텍스트에 대한 빠른 작업",
        enableToggleTitle: "선택 항목 작업 사용",
        enableToggleCaption: "어떤 앱에서든 텍스트를 선택하면 작은 도구 모음을 표시합니다",
        displayStyleLabel: "작업 표시 방식",
        displayStyleIcon: "아이콘",
        displayStyleWord: "단어",
        maxVisibleLabel: "최대 표시 개수",
        maxVisibleCaption: "나머지는 도구 모음의 ▾ 안에 모입니다",
        permissionTitle: "손쉬운 사용 접근 권한 필요",
        permissionBody: "선택 항목 작업은 선택한 텍스트를 읽고 바꿀 수 있으며, 이를 위해 손쉬운 사용 접근 권한이 필요합니다.",
        permissionButton: "접근 허용",
        actionsSectionTitle: "작업",
        actionsSectionCaption: "드래그하여 순서를 바꿀 수 있습니다. 현재 선택 항목에 해당하는 작업만 도구 모음에 표시됩니다.",
        excludedSectionTitle: "제외",
        excludedAppsTitle: "앱",
        excludedAppsCaption: "선택 항목 작업은 이 앱들에서 나타나지 않습니다.",
        excludedAppsAddButton: "앱 추가…",
        excludedAppsRemoveButton: "제거",
        excludedDomainsTitle: "웹사이트",
        excludedDomainsCaption: "한 줄에 하나씩 입력하세요. Safari, Chrome, Edge, Brave, Firefox에서 작동하며, 다른 브라우저는 페이지 주소를 알려주지 않을 수 있습니다.",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "추가",
        excludedDomainsRemoveButton: "제거",
        copyTitle: "복사",
        cutTitle: "잘라내기",
        pasteTitle: "붙여넣기",
        deleteTitle: "삭제",
        copyDescription: "선택 항목을 클립보드에 복사합니다.",
        cutDescription: "선택 항목을 복사한 후 제거합니다.",
        pasteDescription: "선택 항목을 클립보드 내용으로 바꿉니다.",
        deleteDescription: "선택 항목을 복사하지 않고 제거합니다."
    )

    static let zhHans = SelectionActionsStrings(
        pageTitle: "选择操作",
        hubDescription: "对任意选中文本执行快捷操作",
        enableToggleTitle: "启用选择操作",
        enableToggleCaption: "在任意应用中选中文本时，在旁边显示一个小工具栏",
        displayStyleLabel: "操作显示方式",
        displayStyleIcon: "图标",
        displayStyleWord: "文字",
        maxVisibleLabel: "最多显示",
        maxVisibleCaption: "其余操作会收进工具栏中的 ▾",
        permissionTitle: "需要辅助功能权限",
        permissionBody: "选择操作会读取所选文本并可能替换它，这需要辅助功能权限。",
        permissionButton: "授予权限",
        actionsSectionTitle: "操作",
        actionsSectionCaption: "拖动即可重新排序。工具栏中只显示适用于当前选中内容的操作。",
        excludedSectionTitle: "排除项",
        excludedAppsTitle: "应用",
        excludedAppsCaption: "选择操作永远不会在这些应用中出现。",
        excludedAppsAddButton: "添加应用…",
        excludedAppsRemoveButton: "移除",
        excludedDomainsTitle: "网站",
        excludedDomainsCaption: "每行一个网站。适用于 Safari、Chrome、Edge、Brave 和 Firefox — 其他浏览器可能无法报告网页地址。",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "添加",
        excludedDomainsRemoveButton: "移除",
        copyTitle: "拷贝",
        cutTitle: "剪切",
        pasteTitle: "粘贴",
        deleteTitle: "删除",
        copyDescription: "将所选内容复制到剪贴板。",
        cutDescription: "先复制所选内容，再将其移除。",
        pasteDescription: "用剪贴板内容替换所选内容。",
        deleteDescription: "移除所选内容但不复制。"
    )

    static let zhTW = SelectionActionsStrings(
        pageTitle: "選取操作",
        hubDescription: "對任意選取的文字執行快速操作",
        enableToggleTitle: "啟用選取操作",
        enableToggleCaption: "在任何 App 中選取文字時，於旁邊顯示一個小工具列",
        displayStyleLabel: "操作顯示方式",
        displayStyleIcon: "圖示",
        displayStyleWord: "文字",
        maxVisibleLabel: "最多顯示",
        maxVisibleCaption: "其餘操作會收進工具列中的 ▾",
        permissionTitle: "需要輔助使用權限",
        permissionBody: "選取操作會讀取所選文字並可能取代它，這需要輔助使用權限。",
        permissionButton: "授予權限",
        actionsSectionTitle: "操作",
        actionsSectionCaption: "拖曳即可重新排序。工具列中只會顯示適用於目前選取內容的操作。",
        excludedSectionTitle: "排除項目",
        excludedAppsTitle: "App",
        excludedAppsCaption: "選取操作永遠不會在這些 App 中出現。",
        excludedAppsAddButton: "新增 App…",
        excludedAppsRemoveButton: "移除",
        excludedDomainsTitle: "網站",
        excludedDomainsCaption: "每行一個網站。適用於 Safari、Chrome、Edge、Brave 和 Firefox — 其他瀏覽器可能無法回報網頁位址。",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "新增",
        excludedDomainsRemoveButton: "移除",
        copyTitle: "拷貝",
        cutTitle: "剪下",
        pasteTitle: "貼上",
        deleteTitle: "刪除",
        copyDescription: "將所選內容複製到剪貼簿。",
        cutDescription: "先複製所選內容，再將其移除。",
        pasteDescription: "用剪貼簿內容取代所選內容。",
        deleteDescription: "移除所選內容但不複製。"
    )

    static let zhHK = SelectionActionsStrings(
        pageTitle: "選取操作",
        hubDescription: "對任意選取的文字執行快速操作",
        enableToggleTitle: "啟用選取操作",
        enableToggleCaption: "在任何 App 中選取文字時，於旁邊顯示一個小工具列",
        displayStyleLabel: "操作顯示方式",
        displayStyleIcon: "圖示",
        displayStyleWord: "文字",
        maxVisibleLabel: "最多顯示",
        maxVisibleCaption: "其餘操作會收進工具列中的 ▾",
        permissionTitle: "需要輔助使用權限",
        permissionBody: "選取操作會讀取所選文字並可能取代它，這需要輔助使用權限。",
        permissionButton: "授予權限",
        actionsSectionTitle: "操作",
        actionsSectionCaption: "拖曳即可重新排序。工具列中只會顯示適用於目前選取內容的操作。",
        excludedSectionTitle: "排除項目",
        excludedAppsTitle: "App",
        excludedAppsCaption: "選取操作永遠不會在這些 App 中出現。",
        excludedAppsAddButton: "新增 App…",
        excludedAppsRemoveButton: "移除",
        excludedDomainsTitle: "網站",
        excludedDomainsCaption: "每行一個網站。適用於 Safari、Chrome、Edge、Brave 和 Firefox — 其他瀏覽器可能無法回報網頁位址。",
        excludedDomainsPlaceholder: "example.com",
        excludedDomainsAddButton: "新增",
        excludedDomainsRemoveButton: "移除",
        copyTitle: "拷貝",
        cutTitle: "剪下",
        pasteTitle: "貼上",
        deleteTitle: "刪除",
        copyDescription: "將所選內容複製到剪貼簿。",
        cutDescription: "先複製所選內容，再將其移除。",
        pasteDescription: "用剪貼簿內容取代所選內容。",
        deleteDescription: "移除所選內容但不複製。"
    )
}
