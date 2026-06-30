// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureStrings {
    static func settingsCategories(_ language: AppLanguage) -> SettingsCategoryStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .zhHans: return .zhHans
        }
    }

    static func clipboard(_ language: AppLanguage) -> ClipboardFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .zhHans: return .zhHans
        }
    }

    static func windowLayout(_ language: AppLanguage) -> WindowLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .zhHans: return .zhHans
        }
    }

    static func monitorAlerts(_ language: AppLanguage) -> MonitorAlertFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .zhHans: return .zhHans
        }
    }
}

struct SettingsCategoryStrings {
    let essentials: String
    let windowsControls: String
    let utilities: String
    let app: String

    static let enUS = SettingsCategoryStrings(
        essentials: "Essentials",
        windowsControls: "Window controls",
        utilities: "Utilities",
        app: "App"
    )

    static let ptBR = SettingsCategoryStrings(
        essentials: "Essenciais",
        windowsControls: "Janelas e controles",
        utilities: "Utilitários",
        app: "App"
    )

    static let tr = SettingsCategoryStrings(
        essentials: "Temel",
        windowsControls: "Pencereler ve denetimler",
        utilities: "Araçlar",
        app: "Uygulama"
    )

    static let es = SettingsCategoryStrings(
        essentials: "Esenciales",
        windowsControls: "Ventanas y controles",
        utilities: "Utilidades",
        app: "App"
    )

    static let de = SettingsCategoryStrings(
        essentials: "Grundlagen",
        windowsControls: "Fenster und Steuerung",
        utilities: "Dienstprogramme",
        app: "App"
    )

    static let fr = SettingsCategoryStrings(
        essentials: "Essentiel",
        windowsControls: "Fenêtres et contrôles",
        utilities: "Utilitaires",
        app: "App"
    )

    static let it = SettingsCategoryStrings(
        essentials: "Essenziali",
        windowsControls: "Finestre e controlli",
        utilities: "Utilità",
        app: "App"
    )

    static let ja = SettingsCategoryStrings(
        essentials: "基本機能",
        windowsControls: "ウインドウと操作",
        utilities: "ユーティリティ",
        app: "App"
    )

    static let zhHans = SettingsCategoryStrings(
        essentials: "基础功能",
        windowsControls: "窗口与控制",
        utilities: "实用工具",
        app: "App"
    )
}

struct ClipboardFeatureStrings {
    let title: String
    let enable: String
    let caption: String
    let localNote: String
    let skipSensitive: String
    let skipSensitiveCaption: String
    let limit: String
    let showInPanel: String
    let shortcut: String
    let shortcutCaption: String
    let shortcutHint: String
    let pinned: String
    let recent: String
    let pin: String
    let unpin: String
    let clearRecent: String
    let clearAll: String
    let empty: String
    let disabled: String
    let search: String
    let copy: String
    let copied: String
    let delete: String
    let selectMultiple: String
    let unselectMultiple: String
    let selectedCountFormat: String
    let clearSelection: String
    let moveUp: String
    let moveDown: String
    let noResults: String
    let newestFirst: String
    let active: String

    static let enUS = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Save clipboard history",
        caption: "Stores copied text so you can reuse it later. Everything stays local and can be cleared anytime.",
        localNote: "Only text is saved. Images, files and very large items are ignored.",
        skipSensitive: "Skip text that looks sensitive",
        skipSensitiveCaption: "Avoids saving short no-space strings that look like passwords, tokens or keys.",
        limit: "Limit",
        showInPanel: "Show in panel",
        shortcut: "History shortcut",
        shortcutCaption: "Opens a quick window with search, pinned items and ⌘1 to ⌘9 shortcuts for pasting into the previous app.",
        shortcutHint: "In the quick window: Enter pastes, Shift+Enter only copies. Cmd-click selects multiple, arrows choose, ⌘1 to ⌘9 paste, Option+P pins, Option+Delete deletes.",
        pinned: "Pinned",
        recent: "Recent",
        pin: "Pin",
        unpin: "Unpin",
        clearRecent: "Clear recent",
        clearAll: "Clear unpinned",
        empty: "No saved text",
        disabled: "Enable history to start saving copied text.",
        search: "Search copied text",
        copy: "Copy",
        copied: "Copied",
        delete: "Delete item",
        selectMultiple: "Add to pile",
        unselectMultiple: "Remove from pile",
        selectedCountFormat: "%d selected",
        clearSelection: "Clear selection",
        moveUp: "Move up",
        moveDown: "Move down",
        noResults: "No results",
        newestFirst: "Newest first",
        active: "Saving new text"
    )

    static let ptBR = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Guardar histórico de clipboard",
        caption: "Guarda textos copiados para reutilizar depois. Tudo fica local e pode ser apagado a qualquer momento.",
        localNote: "Somente texto entra no histórico. Imagens, arquivos e itens grandes são ignorados.",
        skipSensitive: "Ignorar textos com aparência sensível",
        skipSensitiveCaption: "Evita salvar textos curtos sem espaços que parecem senha, token ou chave.",
        limit: "Limite",
        showInPanel: "Mostrar no painel",
        shortcut: "Atalho do histórico",
        shortcutCaption: "Abre uma janela rápida com busca, favoritos e atalhos ⌘1 a ⌘9 para colar no app anterior.",
        shortcutHint: "Na janela rápida: Enter cola, Shift+Enter só copia. ⌘+clique marca vários, setas escolhem, ⌘1 a ⌘9 colam, Option+P fixa, Option+Delete apaga.",
        pinned: "Fixados",
        recent: "Recentes",
        pin: "Fixar",
        unpin: "Desfixar",
        clearRecent: "Limpar recentes",
        clearAll: "Limpar não fixados",
        empty: "Nenhum texto salvo",
        disabled: "Ative o histórico para começar a guardar textos copiados.",
        search: "Buscar textos copiados",
        copy: "Copiar",
        copied: "Copiado",
        delete: "Apagar item",
        selectMultiple: "Marcar para pilha",
        unselectMultiple: "Remover da pilha",
        selectedCountFormat: "%d marcados",
        clearSelection: "Limpar seleção",
        moveUp: "Mover para cima",
        moveDown: "Mover para baixo",
        noResults: "Nenhum resultado",
        newestFirst: "Mais recentes primeiro",
        active: "Guardando novos textos"
    )

    static let tr = ClipboardFeatureStrings(
        title: "Pano",
        enable: "Pano geçmişini kaydet",
        caption: "Kopyalanan metinleri daha sonra yeniden kullanabilmen için saklar. Her şey yerel kalır ve istediğin zaman temizlenebilir.",
        localNote: "Yalnızca metin kaydedilir. Görseller, dosyalar ve çok büyük öğeler yok sayılır.",
        skipSensitive: "Hassas görünen metinleri atla",
        skipSensitiveCaption: "Parola, token veya anahtar gibi görünen kısa ve boşluksuz dizeleri kaydetmekten kaçınır.",
        limit: "Sınır",
        showInPanel: "Panelde göster",
        shortcut: "Geçmiş kısayolu",
        shortcutCaption: "Arama, sabitlenmiş öğeler ve önceki uygulamaya yapıştırmak için ⌘1 - ⌘9 kısayolları olan hızlı bir pencere açar.",
        shortcutHint: "Hızlı pencerede: Enter yapıştırır, Shift+Enter yalnızca kopyalar. Cmd-tıklama birden çok öğeyi seçer, oklar seçer, ⌘1 - ⌘9 yapıştırır, Option+P sabitler, Option+Delete siler.",
        pinned: "Sabitlenenler",
        recent: "Son",
        pin: "Sabitle",
        unpin: "Sabitlemeyi kaldır",
        clearRecent: "Sonları temizle",
        clearAll: "Sabitlenmeyenleri temizle",
        empty: "Kayıtlı metin yok",
        disabled: "Kopyalanan metinleri kaydetmeye başlamak için geçmişi etkinleştir.",
        search: "Kopyalanan metinlerde ara",
        copy: "Kopyala",
        copied: "Kopyalandı",
        delete: "Öğeyi sil",
        selectMultiple: "Yığına ekle",
        unselectMultiple: "Yığından çıkar",
        selectedCountFormat: "%d seçili",
        clearSelection: "Seçimi temizle",
        moveUp: "Yukarı taşı",
        moveDown: "Aşağı taşı",
        noResults: "Sonuç yok",
        newestFirst: "En yeniler önce",
        active: "Yeni metinler kaydediliyor"
    )

    static let es = ClipboardFeatureStrings(
        title: "Portapapeles",
        enable: "Guardar historial del portapapeles",
        caption: "Guarda el texto copiado para reutilizarlo después. Todo queda local y se puede borrar cuando quieras.",
        localNote: "Solo se guarda texto. Se ignoran imágenes, archivos y elementos muy grandes.",
        skipSensitive: "Omitir texto que parezca sensible",
        skipSensitiveCaption: "Evita guardar cadenas cortas sin espacios que parezcan contraseñas, tokens o claves.",
        limit: "Límite",
        showInPanel: "Mostrar en el panel",
        shortcut: "Atajo del historial",
        shortcutCaption: "Abre una ventana rápida con búsqueda, elementos fijados y atajos ⌘1 a ⌘9 para pegar en la app anterior.",
        shortcutHint: "En la ventana rápida: Enter pega, Shift+Enter solo copia. Cmd-clic selecciona varios, las flechas eligen, ⌘1 a ⌘9 pegan, Option+P fija, Option+Delete elimina.",
        pinned: "Fijados",
        recent: "Recientes",
        pin: "Fijar",
        unpin: "Desfijar",
        clearRecent: "Limpiar recientes",
        clearAll: "Limpiar no fijados",
        empty: "No hay texto guardado",
        disabled: "Activa el historial para empezar a guardar texto copiado.",
        search: "Buscar texto copiado",
        copy: "Copiar",
        copied: "Copiado",
        delete: "Eliminar elemento",
        selectMultiple: "Añadir a la pila",
        unselectMultiple: "Quitar de la pila",
        selectedCountFormat: "%d seleccionados",
        clearSelection: "Limpiar selección",
        moveUp: "Subir",
        moveDown: "Bajar",
        noResults: "Sin resultados",
        newestFirst: "Más recientes primero",
        active: "Guardando nuevo texto"
    )

    static let de = ClipboardFeatureStrings(
        title: "Zwischenablage",
        enable: "Zwischenablageverlauf speichern",
        caption: "Speichert kopierten Text, damit du ihn später wiederverwenden kannst. Alles bleibt lokal und kann jederzeit gelöscht werden.",
        localNote: "Nur Text wird gespeichert. Bilder, Dateien und sehr große Inhalte werden ignoriert.",
        skipSensitive: "Text überspringen, der sensibel wirkt",
        skipSensitiveCaption: "Speichert keine kurzen Zeichenfolgen ohne Leerzeichen, die wie Passwörter, Token oder Schlüssel wirken.",
        limit: "Limit",
        showInPanel: "Im Panel anzeigen",
        shortcut: "Verlaufskürzel",
        shortcutCaption: "Öffnet ein Schnellfenster mit Suche, angehefteten Einträgen und ⌘1 bis ⌘9 zum Einfügen in die vorherige App.",
        shortcutHint: "Im Schnellfenster: Enter fügt ein, Shift+Enter kopiert nur. Cmd-Klick markiert mehrere, Pfeile wählen, ⌘1 bis ⌘9 fügen ein, Option+P pinnt, Option+Delete löscht.",
        pinned: "Angeheftet",
        recent: "Zuletzt",
        pin: "Anheften",
        unpin: "Lösen",
        clearRecent: "Zuletzt löschen",
        clearAll: "Nicht angeheftete löschen",
        empty: "Kein gespeicherter Text",
        disabled: "Aktiviere den Verlauf, um kopierten Text zu speichern.",
        search: "Kopierten Text suchen",
        copy: "Kopieren",
        copied: "Kopiert",
        delete: "Eintrag löschen",
        selectMultiple: "Zum Stapel hinzufügen",
        unselectMultiple: "Aus dem Stapel entfernen",
        selectedCountFormat: "%d ausgewählt",
        clearSelection: "Auswahl löschen",
        moveUp: "Nach oben",
        moveDown: "Nach unten",
        noResults: "Keine Ergebnisse",
        newestFirst: "Neueste zuerst",
        active: "Speichert neuen Text"
    )

    static let fr = ClipboardFeatureStrings(
        title: "Presse-papiers",
        enable: "Enregistrer l'historique du presse-papiers",
        caption: "Enregistre le texte copié pour le réutiliser plus tard. Tout reste local et peut être effacé à tout moment.",
        localNote: "Seul le texte est enregistré. Les images, fichiers et très grands éléments sont ignorés.",
        skipSensitive: "Ignorer le texte qui semble sensible",
        skipSensitiveCaption: "Évite d'enregistrer les courtes chaînes sans espaces qui ressemblent à des mots de passe, jetons ou clés.",
        limit: "Limite",
        showInPanel: "Afficher dans le panneau",
        shortcut: "Raccourci de l'historique",
        shortcutCaption: "Ouvre une fenêtre rapide avec recherche, éléments épinglés et raccourcis ⌘1 à ⌘9 pour coller dans l'app précédente.",
        shortcutHint: "Dans la fenêtre rapide : Enter colle, Shift+Enter copie seulement. Cmd-clic sélectionne plusieurs éléments, les flèches choisissent, ⌘1 à ⌘9 collent, Option+P épingle, Option+Delete supprime.",
        pinned: "Épinglés",
        recent: "Récents",
        pin: "Épingler",
        unpin: "Désépingler",
        clearRecent: "Effacer les récents",
        clearAll: "Effacer non épinglés",
        empty: "Aucun texte enregistré",
        disabled: "Activez l'historique pour commencer à enregistrer le texte copié.",
        search: "Rechercher le texte copié",
        copy: "Copier",
        copied: "Copié",
        delete: "Supprimer l'élément",
        selectMultiple: "Ajouter à la pile",
        unselectMultiple: "Retirer de la pile",
        selectedCountFormat: "%d sélectionnés",
        clearSelection: "Effacer la sélection",
        moveUp: "Monter",
        moveDown: "Descendre",
        noResults: "Aucun résultat",
        newestFirst: "Plus récents d'abord",
        active: "Enregistre le nouveau texte"
    )

    static let it = ClipboardFeatureStrings(
        title: "Appunti",
        enable: "Salva cronologia degli appunti",
        caption: "Salva il testo copiato per riutilizzarlo in seguito. Tutto resta locale e può essere cancellato in qualsiasi momento.",
        localNote: "Viene salvato solo testo. Immagini, file ed elementi molto grandi vengono ignorati.",
        skipSensitive: "Ignora testo che sembra sensibile",
        skipSensitiveCaption: "Evita di salvare stringhe brevi senza spazi che sembrano password, token o chiavi.",
        limit: "Limite",
        showInPanel: "Mostra nel pannello",
        shortcut: "Scorciatoia cronologia",
        shortcutCaption: "Apre una finestra rapida con ricerca, elementi fissati e scorciatoie ⌘1 a ⌘9 per incollare nell'app precedente.",
        shortcutHint: "Nella finestra rapida: Enter incolla, Shift+Enter copia soltanto. Cmd-clic seleziona più elementi, le frecce scelgono, ⌘1 a ⌘9 incollano, Option+P fissa, Option+Delete elimina.",
        pinned: "Fissati",
        recent: "Recenti",
        pin: "Fissa",
        unpin: "Sblocca",
        clearRecent: "Cancella recenti",
        clearAll: "Cancella non fissati",
        empty: "Nessun testo salvato",
        disabled: "Attiva la cronologia per iniziare a salvare il testo copiato.",
        search: "Cerca testo copiato",
        copy: "Copia",
        copied: "Copiato",
        delete: "Elimina elemento",
        selectMultiple: "Aggiungi alla pila",
        unselectMultiple: "Rimuovi dalla pila",
        selectedCountFormat: "%d selezionati",
        clearSelection: "Cancella selezione",
        moveUp: "Sposta su",
        moveDown: "Sposta giù",
        noResults: "Nessun risultato",
        newestFirst: "Più recenti prima",
        active: "Salvataggio nuovo testo"
    )

    static let ja = ClipboardFeatureStrings(
        title: "クリップボード",
        enable: "クリップボード履歴を保存",
        caption: "コピーしたテキストを保存して、あとで再利用できます。すべてローカルに保存され、いつでも削除できます。",
        localNote: "保存されるのはテキストのみです。画像、ファイル、大きすぎる項目は無視されます。",
        skipSensitive: "機密らしいテキストを無視",
        skipSensitiveCaption: "パスワード、トークン、キーに見える短い空白なしの文字列を保存しません。",
        limit: "上限",
        showInPanel: "パネルに表示",
        shortcut: "履歴ショートカット",
        shortcutCaption: "検索、固定項目、前のアプリへ貼り付ける ⌘1 から ⌘9 のショートカットを備えたクイックウインドウを開きます。",
        shortcutHint: "クイックウインドウでは Enter で貼り付け、Shift+Enter でコピーのみ。Cmdクリックで複数選択、矢印で選択、⌘1 から ⌘9 で貼り付け、Option+P で固定、Option+Delete で削除します。",
        pinned: "固定済み",
        recent: "最近",
        pin: "固定",
        unpin: "固定解除",
        clearRecent: "最近を消去",
        clearAll: "未固定を消去",
        empty: "保存済みテキストなし",
        disabled: "履歴を有効にすると、コピーしたテキストを保存できます。",
        search: "コピーしたテキストを検索",
        copy: "コピー",
        copied: "コピー済み",
        delete: "項目を削除",
        selectMultiple: "束に追加",
        unselectMultiple: "束から削除",
        selectedCountFormat: "%d 件選択",
        clearSelection: "選択を解除",
        moveUp: "上へ移動",
        moveDown: "下へ移動",
        noResults: "結果なし",
        newestFirst: "新しい順",
        active: "新しいテキストを保存中"
    )

    static let zhHans = ClipboardFeatureStrings(
        title: "剪贴板",
        enable: "保存剪贴板历史",
        caption: "保存复制过的文本，方便之后再次使用。所有内容都保存在本机，可随时清除。",
        localNote: "只保存文本。图片、文件和特别大的内容会被忽略。",
        skipSensitive: "跳过疑似敏感文本",
        skipSensitiveCaption: "避免保存像密码、令牌或密钥的短文本。",
        limit: "数量上限",
        showInPanel: "在面板中显示",
        shortcut: "历史快捷键",
        shortcutCaption: "打开快速窗口，支持搜索、固定项目，以及用 ⌘1 到 ⌘9 粘贴到上一个 App。",
        shortcutHint: "快速窗口中：Enter 粘贴，Shift+Enter 仅复制。⌘+点击选择多个，方向键选择，⌘1 到 ⌘9 粘贴，Option+P 固定，Option+Delete 删除。",
        pinned: "已固定",
        recent: "最近",
        pin: "固定",
        unpin: "取消固定",
        clearRecent: "清除最近项目",
        clearAll: "清除未固定项目",
        empty: "没有保存的文本",
        disabled: "启用历史记录后即可开始保存复制的文本。",
        search: "搜索复制的文本",
        copy: "复制",
        copied: "已复制",
        delete: "删除项目",
        selectMultiple: "加入堆叠",
        unselectMultiple: "从堆叠移除",
        selectedCountFormat: "已选择 %d 项",
        clearSelection: "清除选择",
        moveUp: "上移",
        moveDown: "下移",
        noResults: "没有结果",
        newestFirst: "最新优先",
        active: "正在保存新文本"
    )
}

struct WindowLayoutFeatureStrings {
    let title: String
    let caption: String
    let showInPanel: String
    let shortcuts: String
    let shortcutsCaption: String
    let permissionCaption: String
    let noWindow: String
    let missingPermission: String
    let failed: String
    let done: String
    let restored: String
    let noRestore: String
    let target: String
    let halves: String
    let thirds: String
    let corners: String
    let other: String
    let leftHalf: String
    let rightHalf: String
    let topHalf: String
    let bottomHalf: String
    let leftThird: String
    let centerThird: String
    let rightThird: String
    let leftTwoThirds: String
    let rightTwoThirds: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    let maximize: String
    let center: String
    let nextDisplay: String
    let restore: String

    static let enUS = WindowLayoutFeatureStrings(
        title: "Window layout",
        caption: "Moves the active window to halves, thirds, corners, another display, center or the usable screen.",
        showInPanel: "Show in panel",
        shortcuts: "Shortcuts",
        shortcutsCaption: "Use global shortcuts to arrange the active window without opening the panel.",
        permissionCaption: "Uses Accessibility to move only the active window.",
        noWindow: "No active window found.",
        missingPermission: "Grant Accessibility to move windows.",
        failed: "Could not move this window.",
        done: "Window arranged.",
        restored: "Window restored.",
        noRestore: "No previous layout to restore.",
        target: "Active window",
        halves: "Halves",
        thirds: "Thirds",
        corners: "Corners",
        other: "Actions",
        leftHalf: "Left",
        rightHalf: "Right",
        topHalf: "Top",
        bottomHalf: "Bottom",
        leftThird: "Left 1/3",
        centerThird: "Center 1/3",
        rightThird: "Right 1/3",
        leftTwoThirds: "Left 2/3",
        rightTwoThirds: "Right 2/3",
        topLeft: "Top left",
        topRight: "Top right",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        maximize: "Maximize",
        center: "Center",
        nextDisplay: "Next display",
        restore: "Restore"
    )

    static let ptBR = WindowLayoutFeatureStrings(
        title: "Layout de janelas",
        caption: "Reposiciona a janela ativa em metades, terços, cantos, outro display, centro ou tela útil.",
        showInPanel: "Mostrar no painel",
        shortcuts: "Atalhos",
        shortcutsCaption: "Use atalhos globais para organizar a janela ativa sem abrir o painel.",
        permissionCaption: "Usa Acessibilidade para mover apenas a janela ativa.",
        noWindow: "Nenhuma janela ativa encontrada.",
        missingPermission: "Conceda Acessibilidade para mover janelas.",
        failed: "Não foi possível mover esta janela.",
        done: "Janela organizada.",
        restored: "Janela restaurada.",
        noRestore: "Nenhum layout anterior para restaurar.",
        target: "Janela ativa",
        halves: "Metades",
        thirds: "Terços",
        corners: "Cantos",
        other: "Ações",
        leftHalf: "Esquerda",
        rightHalf: "Direita",
        topHalf: "Topo",
        bottomHalf: "Base",
        leftThird: "1/3 esquerda",
        centerThird: "1/3 centro",
        rightThird: "1/3 direita",
        leftTwoThirds: "2/3 esquerda",
        rightTwoThirds: "2/3 direita",
        topLeft: "Topo esquerdo",
        topRight: "Topo direito",
        bottomLeft: "Base esquerda",
        bottomRight: "Base direita",
        maximize: "Maximizar",
        center: "Centralizar",
        nextDisplay: "Próximo display",
        restore: "Restaurar"
    )

    static let tr = WindowLayoutFeatureStrings(
        title: "Pencere yerleşimi",
        caption: "Etkin pencereyi yarımlara, üçlü bölümlere, köşelere, başka ekrana, merkeze veya kullanılabilir ekrana taşır.",
        showInPanel: "Panelde göster",
        shortcuts: "Kısayollar",
        shortcutsCaption: "Paneli açmadan etkin pencereyi düzenlemek için genel kısayollar kullan.",
        permissionCaption: "Yalnızca etkin pencereyi taşımak için Erişilebilirlik kullanır.",
        noWindow: "Etkin pencere bulunamadı.",
        missingPermission: "Pencereleri taşımak için Erişilebilirlik izni ver.",
        failed: "Bu pencere taşınamadı.",
        done: "Pencere yerleştirildi.",
        restored: "Pencere geri yüklendi.",
        noRestore: "Geri yüklenecek önceki yerleşim yok.",
        target: "Etkin pencere",
        halves: "Yarımlar",
        thirds: "Üçlüler",
        corners: "Köşeler",
        other: "Eylemler",
        leftHalf: "Sol",
        rightHalf: "Sağ",
        topHalf: "Üst",
        bottomHalf: "Alt",
        leftThird: "Sol 1/3",
        centerThird: "Orta 1/3",
        rightThird: "Sağ 1/3",
        leftTwoThirds: "Sol 2/3",
        rightTwoThirds: "Sağ 2/3",
        topLeft: "Sol üst",
        topRight: "Sağ üst",
        bottomLeft: "Sol alt",
        bottomRight: "Sağ alt",
        maximize: "Büyüt",
        center: "Ortala",
        nextDisplay: "Sonraki ekran",
        restore: "Geri yükle"
    )

    static let es = WindowLayoutFeatureStrings(
        title: "Diseño de ventanas",
        caption: "Mueve la ventana activa a mitades, tercios, esquinas, otra pantalla, el centro o el área útil.",
        showInPanel: "Mostrar en el panel",
        shortcuts: "Atajos",
        shortcutsCaption: "Usa atajos globales para organizar la ventana activa sin abrir el panel.",
        permissionCaption: "Usa Accesibilidad para mover solo la ventana activa.",
        noWindow: "No se encontró una ventana activa.",
        missingPermission: "Concede Accesibilidad para mover ventanas.",
        failed: "No se pudo mover esta ventana.",
        done: "Ventana organizada.",
        restored: "Ventana restaurada.",
        noRestore: "No hay un diseño anterior para restaurar.",
        target: "Ventana activa",
        halves: "Mitades",
        thirds: "Tercios",
        corners: "Esquinas",
        other: "Acciones",
        leftHalf: "Izquierda",
        rightHalf: "Derecha",
        topHalf: "Arriba",
        bottomHalf: "Abajo",
        leftThird: "1/3 izquierda",
        centerThird: "1/3 centro",
        rightThird: "1/3 derecha",
        leftTwoThirds: "2/3 izquierda",
        rightTwoThirds: "2/3 derecha",
        topLeft: "Arriba izquierda",
        topRight: "Arriba derecha",
        bottomLeft: "Abajo izquierda",
        bottomRight: "Abajo derecha",
        maximize: "Maximizar",
        center: "Centrar",
        nextDisplay: "Siguiente pantalla",
        restore: "Restaurar"
    )

    static let de = WindowLayoutFeatureStrings(
        title: "Fensterlayout",
        caption: "Verschiebt das aktive Fenster in Hälften, Drittel, Ecken, auf ein anderes Display, in die Mitte oder auf die nutzbare Fläche.",
        showInPanel: "Im Panel anzeigen",
        shortcuts: "Kurzbefehle",
        shortcutsCaption: "Nutze globale Kurzbefehle, um das aktive Fenster ohne Panel zu arrangieren.",
        permissionCaption: "Nutzt Bedienungshilfen, um nur das aktive Fenster zu bewegen.",
        noWindow: "Kein aktives Fenster gefunden.",
        missingPermission: "Erlaube Bedienungshilfen, um Fenster zu bewegen.",
        failed: "Dieses Fenster konnte nicht bewegt werden.",
        done: "Fenster arrangiert.",
        restored: "Fenster wiederhergestellt.",
        noRestore: "Kein vorheriges Layout zum Wiederherstellen.",
        target: "Aktives Fenster",
        halves: "Hälften",
        thirds: "Drittel",
        corners: "Ecken",
        other: "Aktionen",
        leftHalf: "Links",
        rightHalf: "Rechts",
        topHalf: "Oben",
        bottomHalf: "Unten",
        leftThird: "Linkes 1/3",
        centerThird: "Mittleres 1/3",
        rightThird: "Rechtes 1/3",
        leftTwoThirds: "Linke 2/3",
        rightTwoThirds: "Rechte 2/3",
        topLeft: "Oben links",
        topRight: "Oben rechts",
        bottomLeft: "Unten links",
        bottomRight: "Unten rechts",
        maximize: "Maximieren",
        center: "Zentrieren",
        nextDisplay: "Nächstes Display",
        restore: "Wiederherstellen"
    )

    static let fr = WindowLayoutFeatureStrings(
        title: "Disposition des fenêtres",
        caption: "Déplace la fenêtre active vers les moitiés, tiers, coins, un autre écran, le centre ou la zone utile.",
        showInPanel: "Afficher dans le panneau",
        shortcuts: "Raccourcis",
        shortcutsCaption: "Utilisez des raccourcis globaux pour organiser la fenêtre active sans ouvrir le panneau.",
        permissionCaption: "Utilise Accessibilité pour déplacer uniquement la fenêtre active.",
        noWindow: "Aucune fenêtre active trouvée.",
        missingPermission: "Autorisez Accessibilité pour déplacer les fenêtres.",
        failed: "Impossible de déplacer cette fenêtre.",
        done: "Fenêtre organisée.",
        restored: "Fenêtre restaurée.",
        noRestore: "Aucune disposition précédente à restaurer.",
        target: "Fenêtre active",
        halves: "Moitiés",
        thirds: "Tiers",
        corners: "Coins",
        other: "Actions",
        leftHalf: "Gauche",
        rightHalf: "Droite",
        topHalf: "Haut",
        bottomHalf: "Bas",
        leftThird: "1/3 gauche",
        centerThird: "1/3 centre",
        rightThird: "1/3 droite",
        leftTwoThirds: "2/3 gauche",
        rightTwoThirds: "2/3 droite",
        topLeft: "Haut gauche",
        topRight: "Haut droite",
        bottomLeft: "Bas gauche",
        bottomRight: "Bas droite",
        maximize: "Agrandir",
        center: "Centrer",
        nextDisplay: "Écran suivant",
        restore: "Restaurer"
    )

    static let it = WindowLayoutFeatureStrings(
        title: "Layout finestre",
        caption: "Sposta la finestra attiva in metà, terzi, angoli, su un altro display, al centro o nell'area utilizzabile.",
        showInPanel: "Mostra nel pannello",
        shortcuts: "Scorciatoie",
        shortcutsCaption: "Usa scorciatoie globali per organizzare la finestra attiva senza aprire il pannello.",
        permissionCaption: "Usa Accessibilità per spostare solo la finestra attiva.",
        noWindow: "Nessuna finestra attiva trovata.",
        missingPermission: "Concedi Accessibilità per spostare le finestre.",
        failed: "Impossibile spostare questa finestra.",
        done: "Finestra organizzata.",
        restored: "Finestra ripristinata.",
        noRestore: "Nessun layout precedente da ripristinare.",
        target: "Finestra attiva",
        halves: "Metà",
        thirds: "Terzi",
        corners: "Angoli",
        other: "Azioni",
        leftHalf: "Sinistra",
        rightHalf: "Destra",
        topHalf: "Alto",
        bottomHalf: "Basso",
        leftThird: "1/3 sinistra",
        centerThird: "1/3 centro",
        rightThird: "1/3 destra",
        leftTwoThirds: "2/3 sinistra",
        rightTwoThirds: "2/3 destra",
        topLeft: "Alto sinistra",
        topRight: "Alto destra",
        bottomLeft: "Basso sinistra",
        bottomRight: "Basso destra",
        maximize: "Massimizza",
        center: "Centra",
        nextDisplay: "Display successivo",
        restore: "Ripristina"
    )

    static let ja = WindowLayoutFeatureStrings(
        title: "ウインドウ配置",
        caption: "アクティブなウインドウを半分、3分割、四隅、別のディスプレイ、中央、または作業領域に移動します。",
        showInPanel: "パネルに表示",
        shortcuts: "ショートカット",
        shortcutsCaption: "パネルを開かずにグローバルショートカットでアクティブなウインドウを配置します。",
        permissionCaption: "アクセシビリティを使い、アクティブなウインドウだけを移動します。",
        noWindow: "アクティブなウインドウが見つかりません。",
        missingPermission: "ウインドウを移動するにはアクセシビリティを許可してください。",
        failed: "このウインドウを移動できませんでした。",
        done: "ウインドウを配置しました。",
        restored: "ウインドウを復元しました。",
        noRestore: "復元できる前回の配置はありません。",
        target: "アクティブなウインドウ",
        halves: "半分",
        thirds: "3分割",
        corners: "四隅",
        other: "操作",
        leftHalf: "左",
        rightHalf: "右",
        topHalf: "上",
        bottomHalf: "下",
        leftThird: "左 1/3",
        centerThird: "中央 1/3",
        rightThird: "右 1/3",
        leftTwoThirds: "左 2/3",
        rightTwoThirds: "右 2/3",
        topLeft: "左上",
        topRight: "右上",
        bottomLeft: "左下",
        bottomRight: "右下",
        maximize: "最大化",
        center: "中央",
        nextDisplay: "次のディスプレイ",
        restore: "復元"
    )

    static let zhHans = WindowLayoutFeatureStrings(
        title: "窗口布局",
        caption: "将当前窗口移动到半屏、三分屏、角落、另一台显示器、居中位置或可用屏幕区域。",
        showInPanel: "在面板中显示",
        shortcuts: "快捷键",
        shortcutsCaption: "使用全局快捷键整理当前窗口，无需打开面板。",
        permissionCaption: "使用辅助功能权限，仅移动当前窗口。",
        noWindow: "未找到当前窗口。",
        missingPermission: "请授予辅助功能权限以移动窗口。",
        failed: "无法移动此窗口。",
        done: "窗口已整理。",
        restored: "窗口已恢复。",
        noRestore: "没有可恢复的上一个布局。",
        target: "当前窗口",
        halves: "半屏",
        thirds: "三分屏",
        corners: "角落",
        other: "操作",
        leftHalf: "左半屏",
        rightHalf: "右半屏",
        topHalf: "上半屏",
        bottomHalf: "下半屏",
        leftThird: "左侧 1/3",
        centerThird: "中间 1/3",
        rightThird: "右侧 1/3",
        leftTwoThirds: "左侧 2/3",
        rightTwoThirds: "右侧 2/3",
        topLeft: "左上角",
        topRight: "右上角",
        bottomLeft: "左下角",
        bottomRight: "右下角",
        maximize: "最大化",
        center: "居中",
        nextDisplay: "下一台显示器",
        restore: "恢复"
    )
}

struct MonitorAlertFeatureStrings {
    let section: String
    let caption: String
    let cpu: String
    let cpuTemperature: String
    let memory: String
    let disk: String
    let battery: String
    let cpuThreshold: String
    let cpuTemperatureThreshold: String
    let diskThreshold: String
    let batteryThreshold: String
    let cooldown: String
    let cooldown5: String
    let cooldown15: String
    let cooldown30: String
    let cooldown60: String
    let cpuTitle: String
    let cpuBodyFormat: String
    let cpuTemperatureTitle: String
    let cpuTemperatureBodyFormat: String
    let memoryTitle: String
    let memoryBody: String
    let diskTitle: String
    let diskBodyFormat: String
    let batteryTitle: String
    let batteryBodyFormat: String

    static let enUS = MonitorAlertFeatureStrings(
        section: "Alerts",
        caption: "Off by default. When enabled, Monitor warns only after a useful condition and respects the alert interval.",
        cpu: "High CPU",
        cpuTemperature: "High CPU temperature",
        memory: "Critical memory pressure",
        disk: "Low disk space",
        battery: "Low battery",
        cpuThreshold: "CPU above",
        cpuTemperatureThreshold: "Temperature above",
        diskThreshold: "Free space below",
        batteryThreshold: "Battery below",
        cooldown: "Alert interval",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 hour",
        cpuTitle: "High CPU",
        cpuBodyFormat: "CPU stayed above %d%% for a few seconds.",
        cpuTemperatureTitle: "Hot CPU",
        cpuTemperatureBodyFormat: "CPU reached %d °C.",
        memoryTitle: "Critical memory",
        memoryBody: "Memory pressure reached the critical level.",
        diskTitle: "Low disk space",
        diskBodyFormat: "%@ has less than %d%% free.",
        batteryTitle: "Low battery",
        batteryBodyFormat: "Battery is at %d%%."
    )

    static let ptBR = MonitorAlertFeatureStrings(
        section: "Alertas",
        caption: "Desligado por padrão. Quando ligado, o Monitor avisa só depois de uma condição relevante e respeita o intervalo entre avisos.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura alta da CPU",
        memory: "Pressão de memória crítica",
        disk: "Pouco espaço em disco",
        battery: "Bateria baixa",
        cpuThreshold: "CPU acima de",
        cpuTemperatureThreshold: "Temperatura acima de",
        diskThreshold: "Espaço livre abaixo de",
        batteryThreshold: "Bateria abaixo de",
        cooldown: "Intervalo entre avisos",
        cooldown5: "5 minutos",
        cooldown15: "15 minutos",
        cooldown30: "30 minutos",
        cooldown60: "1 hora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "A CPU ficou acima de %d%% por alguns segundos.",
        cpuTemperatureTitle: "CPU quente",
        cpuTemperatureBodyFormat: "A CPU chegou a %d °C.",
        memoryTitle: "Memória crítica",
        memoryBody: "A pressão de memória chegou ao nível crítico.",
        diskTitle: "Pouco espaço em disco",
        diskBodyFormat: "%@ está com menos de %d%% livre.",
        batteryTitle: "Bateria baixa",
        batteryBodyFormat: "A bateria está em %d%%."
    )

    static let tr = MonitorAlertFeatureStrings(
        section: "Uyarılar",
        caption: "Varsayılan olarak kapalıdır. Etkinleştirildiğinde Monitör yalnızca anlamlı bir koşuldan sonra uyarır ve uyarı aralığına uyar.",
        cpu: "Yüksek CPU",
        cpuTemperature: "Yüksek CPU sıcaklığı",
        memory: "Kritik bellek basıncı",
        disk: "Düşük disk alanı",
        battery: "Düşük pil",
        cpuThreshold: "CPU şu değerin üstünde",
        cpuTemperatureThreshold: "Sıcaklık şu değerin üstünde",
        diskThreshold: "Boş alan şu değerin altında",
        batteryThreshold: "Pil şu değerin altında",
        cooldown: "Uyarı aralığı",
        cooldown5: "5 dakika",
        cooldown15: "15 dakika",
        cooldown30: "30 dakika",
        cooldown60: "1 saat",
        cpuTitle: "Yüksek CPU",
        cpuBodyFormat: "CPU birkaç saniye boyunca %d%% üzerinde kaldı.",
        cpuTemperatureTitle: "CPU sıcak",
        cpuTemperatureBodyFormat: "CPU %d °C değerine ulaştı.",
        memoryTitle: "Kritik bellek",
        memoryBody: "Bellek basıncı kritik seviyeye ulaştı.",
        diskTitle: "Düşük disk alanı",
        diskBodyFormat: "%@ diskinde %d%% altında boş alan var.",
        batteryTitle: "Düşük pil",
        batteryBodyFormat: "Pil %d%% seviyesinde."
    )

    static let es = MonitorAlertFeatureStrings(
        section: "Alertas",
        caption: "Desactivado por defecto. Al activarlo, Monitor avisa solo tras una condición relevante y respeta el intervalo entre avisos.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura de CPU alta",
        memory: "Presión de memoria crítica",
        disk: "Poco espacio en disco",
        battery: "Batería baja",
        cpuThreshold: "CPU por encima de",
        cpuTemperatureThreshold: "Temperatura por encima de",
        diskThreshold: "Espacio libre por debajo de",
        batteryThreshold: "Batería por debajo de",
        cooldown: "Intervalo entre avisos",
        cooldown5: "5 minutos",
        cooldown15: "15 minutos",
        cooldown30: "30 minutos",
        cooldown60: "1 hora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "La CPU estuvo por encima de %d%% durante unos segundos.",
        cpuTemperatureTitle: "CPU caliente",
        cpuTemperatureBodyFormat: "La CPU llegó a %d °C.",
        memoryTitle: "Memoria crítica",
        memoryBody: "La presión de memoria llegó al nivel crítico.",
        diskTitle: "Poco espacio en disco",
        diskBodyFormat: "%@ tiene menos de %d%% libre.",
        batteryTitle: "Batería baja",
        batteryBodyFormat: "La batería está al %d%%."
    )

    static let de = MonitorAlertFeatureStrings(
        section: "Warnungen",
        caption: "Standardmäßig aus. Wenn aktiviert, warnt der Monitor nur nach einem relevanten Zustand und beachtet das Warnintervall.",
        cpu: "Hohe CPU",
        cpuTemperature: "Hohe CPU-Temperatur",
        memory: "Kritischer Speicherdruck",
        disk: "Wenig Speicherplatz",
        battery: "Niedriger Akkustand",
        cpuThreshold: "CPU über",
        cpuTemperatureThreshold: "Temperatur über",
        diskThreshold: "Freier Platz unter",
        batteryThreshold: "Akku unter",
        cooldown: "Warnintervall",
        cooldown5: "5 Minuten",
        cooldown15: "15 Minuten",
        cooldown30: "30 Minuten",
        cooldown60: "1 Stunde",
        cpuTitle: "Hohe CPU",
        cpuBodyFormat: "Die CPU lag einige Sekunden über %d%%.",
        cpuTemperatureTitle: "Heiße CPU",
        cpuTemperatureBodyFormat: "Die CPU hat %d °C erreicht.",
        memoryTitle: "Kritischer Speicher",
        memoryBody: "Der Speicherdruck hat den kritischen Wert erreicht.",
        diskTitle: "Wenig Speicherplatz",
        diskBodyFormat: "%@ hat weniger als %d%% frei.",
        batteryTitle: "Niedriger Akkustand",
        batteryBodyFormat: "Der Akku ist bei %d%%."
    )

    static let fr = MonitorAlertFeatureStrings(
        section: "Alertes",
        caption: "Désactivé par défaut. Une fois activé, Monitor avertit seulement après une condition utile et respecte l'intervalle d'alerte.",
        cpu: "CPU élevé",
        cpuTemperature: "Température CPU élevée",
        memory: "Pression mémoire critique",
        disk: "Espace disque faible",
        battery: "Batterie faible",
        cpuThreshold: "CPU au-dessus de",
        cpuTemperatureThreshold: "Température au-dessus de",
        diskThreshold: "Espace libre sous",
        batteryThreshold: "Batterie sous",
        cooldown: "Intervalle d'alerte",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 heure",
        cpuTitle: "CPU élevé",
        cpuBodyFormat: "Le CPU est resté au-dessus de %d%% pendant quelques secondes.",
        cpuTemperatureTitle: "CPU chaud",
        cpuTemperatureBodyFormat: "Le CPU a atteint %d °C.",
        memoryTitle: "Mémoire critique",
        memoryBody: "La pression mémoire a atteint le niveau critique.",
        diskTitle: "Espace disque faible",
        diskBodyFormat: "%@ a moins de %d%% libre.",
        batteryTitle: "Batterie faible",
        batteryBodyFormat: "La batterie est à %d%%."
    )

    static let it = MonitorAlertFeatureStrings(
        section: "Avvisi",
        caption: "Disattivato per impostazione predefinita. Quando attivo, Monitor avvisa solo dopo una condizione utile e rispetta l'intervallo tra gli avvisi.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura CPU alta",
        memory: "Pressione memoria critica",
        disk: "Poco spazio su disco",
        battery: "Batteria scarica",
        cpuThreshold: "CPU sopra",
        cpuTemperatureThreshold: "Temperatura sopra",
        diskThreshold: "Spazio libero sotto",
        batteryThreshold: "Batteria sotto",
        cooldown: "Intervallo avvisi",
        cooldown5: "5 minuti",
        cooldown15: "15 minuti",
        cooldown30: "30 minuti",
        cooldown60: "1 ora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "La CPU è rimasta sopra %d%% per alcuni secondi.",
        cpuTemperatureTitle: "CPU calda",
        cpuTemperatureBodyFormat: "La CPU ha raggiunto %d °C.",
        memoryTitle: "Memoria critica",
        memoryBody: "La pressione della memoria ha raggiunto il livello critico.",
        diskTitle: "Poco spazio su disco",
        diskBodyFormat: "%@ ha meno del %d%% libero.",
        batteryTitle: "Batteria scarica",
        batteryBodyFormat: "La batteria è al %d%%."
    )

    static let ja = MonitorAlertFeatureStrings(
        section: "アラート",
        caption: "デフォルトではオフです。有効にすると、Monitor は意味のある状態が続いた場合だけ通知し、通知間隔を守ります。",
        cpu: "CPU 高負荷",
        cpuTemperature: "CPU 温度が高い",
        memory: "メモリ圧迫が深刻",
        disk: "ディスク空き容量不足",
        battery: "バッテリー残量低下",
        cpuThreshold: "CPU が次を超過",
        cpuTemperatureThreshold: "温度が次を超過",
        diskThreshold: "空き容量が次を下回る",
        batteryThreshold: "バッテリーが次を下回る",
        cooldown: "通知間隔",
        cooldown5: "5 分",
        cooldown15: "15 分",
        cooldown30: "30 分",
        cooldown60: "1 時間",
        cpuTitle: "CPU 高負荷",
        cpuBodyFormat: "CPU が数秒間 %d%% を超えました。",
        cpuTemperatureTitle: "CPU が高温",
        cpuTemperatureBodyFormat: "CPU が %d °C に達しました。",
        memoryTitle: "メモリが深刻",
        memoryBody: "メモリ圧迫が深刻レベルに達しました。",
        diskTitle: "ディスク空き容量不足",
        diskBodyFormat: "%@ の空き容量が %d%% 未満です。",
        batteryTitle: "バッテリー残量低下",
        batteryBodyFormat: "バッテリー残量は %d%% です。"
    )

    static let zhHans = MonitorAlertFeatureStrings(
        section: "提醒",
        caption: "默认关闭。启用后，监视器只会在出现有意义的状态时提醒，并遵守提醒间隔。",
        cpu: "CPU 过高",
        cpuTemperature: "CPU 温度过高",
        memory: "内存压力严重",
        disk: "磁盘空间不足",
        battery: "电池电量低",
        cpuThreshold: "CPU 高于",
        cpuTemperatureThreshold: "温度高于",
        diskThreshold: "可用空间低于",
        batteryThreshold: "电量低于",
        cooldown: "提醒间隔",
        cooldown5: "5 分钟",
        cooldown15: "15 分钟",
        cooldown30: "30 分钟",
        cooldown60: "1 小时",
        cpuTitle: "CPU 过高",
        cpuBodyFormat: "CPU 已连续几秒高于 %d%%。",
        cpuTemperatureTitle: "CPU 过热",
        cpuTemperatureBodyFormat: "CPU 已达到 %d °C。",
        memoryTitle: "内存严重",
        memoryBody: "内存压力已达到严重级别。",
        diskTitle: "磁盘空间不足",
        diskBodyFormat: "%@ 的可用空间低于 %d%%。",
        batteryTitle: "电池电量低",
        batteryBodyFormat: "电池电量为 %d%%。"
    )
}
