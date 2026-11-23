// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct ClipboardShelfStrings {
    let edge: String
    let click: String
    let history: String
    let pinboards: String
    let newPinboard: String
    let renamePinboard: String
    let deletePinboard: String
    let pinboardName: String
    let moveToPinboard: String
    let removeFromPinboard: String
    let filterByType: String
    let allTypes: String
    let suggestions: String
    let suggestionsCaption: String
    let linkPreviews: String
    let linkPreviewsCaption: String
    let loadLinkPreview: String
    let linkPreviewUnavailable: String
    let privacyMode: String
    let privacyModeCaption: String
    let clipboardHidden: String
    let ignoreTransient: String
    let ignoreTransientCaption: String

    private let top: String
    private let bottom: String
    private let left: String
    private let right: String
    private let clickToSelect: String
    private let clickToPaste: String
    private let text: String
    private let link: String
    private let color: String
    private let image: String
    private let file: String

    static func forLanguage(_ language: AppLanguage) -> ClipboardShelfStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }

    func edgeName(_ edge: ClipboardShelfEdge) -> String {
        switch edge {
        case .top: return top
        case .bottom: return bottom
        case .left: return left
        case .right: return right
        }
    }

    func clickName(_ click: ClipboardShelfClick) -> String {
        switch click {
        case .select: return clickToSelect
        case .paste: return clickToPaste
        }
    }

    func typeName(_ type: ClipboardShelfContentType) -> String {
        switch type {
        case .text: return text
        case .link: return link
        case .color: return color
        case .image: return image
        case .file: return file
        }
    }
}

private extension ClipboardShelfStrings {
    static let enUS = ClipboardShelfStrings(
        edge: "Shelf edge",
        click: "Single click",
        history: "History",
        pinboards: "Pinboards",
        newPinboard: "New pinboard",
        renamePinboard: "Rename pinboard",
        deletePinboard: "Delete pinboard",
        pinboardName: "Pinboard name",
        moveToPinboard: "Move to pinboard",
        removeFromPinboard: "Remove from pinboard",
        filterByType: "Filter by type",
        allTypes: "All types",
        suggestions: "Clipboard suggestions",
        suggestionsCaption: "Suggestions use the active app and recent history on this Mac, without screen access.",
        linkPreviews: "Link previews",
        linkPreviewsCaption: "The shelf sends the selected link to its site only when you choose Load preview. This can activate the link.",
        loadLinkPreview: "Load preview",
        linkPreviewUnavailable: "Link preview unavailable",
        privacyMode: "Privacy mode",
        privacyModeCaption: "Turn this on to hide clipboard content and previews in the shelf on this Mac, including during screen sharing.",
        clipboardHidden: "Clipboard hidden",
        ignoreTransient: "Skip temporary copies",
        ignoreTransientCaption: "Skips copies marked temporary. Copies marked concealed are always skipped.",
        top: "Top", bottom: "Bottom", left: "Left", right: "Right",
        clickToSelect: "Click to select", clickToPaste: "Click to paste",
        text: "Text", link: "Link", color: "Color", image: "Image", file: "File"
    )

    static let ptBR = ClipboardShelfStrings(
        edge: "Borda da prateleira",
        click: "Clique simples",
        history: "Histórico",
        pinboards: "Murais",
        newPinboard: "Novo mural",
        renamePinboard: "Renomear mural",
        deletePinboard: "Excluir mural",
        pinboardName: "Nome do mural",
        moveToPinboard: "Mover para o mural",
        removeFromPinboard: "Remover do mural",
        filterByType: "Filtrar por tipo",
        allTypes: "Todos os tipos",
        suggestions: "Sugestões da área de transferência",
        suggestionsCaption: "As sugestões usam o app ativo e o histórico recente neste Mac, sem acessar a tela.",
        linkPreviews: "Pré-visualizações de links",
        linkPreviewsCaption: "A prateleira só envia o link selecionado ao site quando você escolhe Carregar prévia. Isso pode ativar o link.",
        loadLinkPreview: "Carregar prévia",
        linkPreviewUnavailable: "Prévia do link indisponível",
        privacyMode: "Modo de privacidade",
        privacyModeCaption: "Ative para ocultar o conteúdo e as prévias da área de transferência na prateleira deste Mac, inclusive ao compartilhar a tela.",
        clipboardHidden: "Área de transferência oculta",
        ignoreTransient: "Ignorar cópias temporárias",
        ignoreTransientCaption: "Ignora cópias marcadas como temporárias. Cópias marcadas como ocultas são sempre ignoradas.",
        top: "Superior", bottom: "Inferior", left: "Esquerda", right: "Direita",
        clickToSelect: "Clicar para selecionar", clickToPaste: "Clicar para colar",
        text: "Texto", link: "Link", color: "Cor", image: "Imagem", file: "Arquivo"
    )

    static let tr = ClipboardShelfStrings(
        edge: "Rafın konumu",
        click: "Tek tıklama",
        history: "Geçmiş",
        pinboards: "Panolar",
        newPinboard: "Yeni pano",
        renamePinboard: "Panoyu yeniden adlandır",
        deletePinboard: "Panoyu sil",
        pinboardName: "Pano adı",
        moveToPinboard: "Panoya taşı",
        removeFromPinboard: "Panodan kaldır",
        filterByType: "Türe göre filtrele",
        allTypes: "Tüm türler",
        suggestions: "Pano önerileri",
        suggestionsCaption: "Öneriler, ekrana erişmeden bu Mac’teki etkin uygulamayı ve yakın geçmişi kullanır.",
        linkPreviews: "Bağlantı önizlemeleri",
        linkPreviewsCaption: "Raf, seçili bağlantıyı sitesine yalnızca Önizlemeyi yükle’yi seçtiğinizde gönderir. Bu işlem bağlantıyı etkinleştirebilir.",
        loadLinkPreview: "Önizlemeyi yükle",
        linkPreviewUnavailable: "Bağlantı önizlemesi kullanılamıyor",
        privacyMode: "Gizlilik modu",
        privacyModeCaption: "Ekran paylaşımı da dahil olmak üzere bu Mac’in rafındaki pano içeriğini ve önizlemeleri gizlemek için açın.",
        clipboardHidden: "Pano gizlendi",
        ignoreTransient: "Geçici kopyaları atla",
        ignoreTransientCaption: "Geçici olarak işaretlenen kopyalar atlanır. Gizli olarak işaretlenen kopyalar her zaman atlanır.",
        top: "Üst", bottom: "Alt", left: "Sol", right: "Sağ",
        clickToSelect: "Tıklayarak seç", clickToPaste: "Tıklayarak yapıştır",
        text: "Metin", link: "Bağlantı", color: "Renk", image: "Görsel", file: "Dosya"
    )

    static let ru = ClipboardShelfStrings(
        edge: "Расположение полки",
        click: "Один щелчок",
        history: "История",
        pinboards: "Доски",
        newPinboard: "Новая доска",
        renamePinboard: "Переименовать доску",
        deletePinboard: "Удалить доску",
        pinboardName: "Название доски",
        moveToPinboard: "Переместить на доску",
        removeFromPinboard: "Убрать с доски",
        filterByType: "Фильтр по типу",
        allTypes: "Все типы",
        suggestions: "Предложения буфера обмена",
        suggestionsCaption: "Для предложений используются активное приложение и недавняя история на этом Mac без доступа к экрану.",
        linkPreviews: "Предпросмотр ссылок",
        linkPreviewsCaption: "Полка отправляет выбранную ссылку на её сайт только по команде «Загрузить предпросмотр». Это может активировать ссылку.",
        loadLinkPreview: "Загрузить предпросмотр",
        linkPreviewUnavailable: "Предпросмотр ссылки недоступен",
        privacyMode: "Режим конфиденциальности",
        privacyModeCaption: "Включите, чтобы скрыть содержимое буфера обмена и его предпросмотр на полке этого Mac, в том числе при показе экрана.",
        clipboardHidden: "Буфер обмена скрыт",
        ignoreTransient: "Пропускать временные копии",
        ignoreTransientCaption: "Копии, отмеченные как временные, пропускаются. Копии, отмеченные как скрытые, пропускаются всегда.",
        top: "Сверху", bottom: "Снизу", left: "Слева", right: "Справа",
        clickToSelect: "Выбрать щелчком", clickToPaste: "Вставить щелчком",
        text: "Текст", link: "Ссылка", color: "Цвет", image: "Изображение", file: "Файл"
    )

    static let es = ClipboardShelfStrings(
        edge: "Posición del estante",
        click: "Un clic",
        history: "Historial",
        pinboards: "Tableros",
        newPinboard: "Nuevo tablero",
        renamePinboard: "Renombrar tablero",
        deletePinboard: "Eliminar tablero",
        pinboardName: "Nombre del tablero",
        moveToPinboard: "Mover al tablero",
        removeFromPinboard: "Quitar del tablero",
        filterByType: "Filtrar por tipo",
        allTypes: "Todos los tipos",
        suggestions: "Sugerencias del portapapeles",
        suggestionsCaption: "Las sugerencias usan la app activa y el historial reciente de este Mac, sin acceder a la pantalla.",
        linkPreviews: "Vistas previas de enlaces",
        linkPreviewsCaption: "El estante envía el enlace seleccionado a su sitio solo cuando eliges Cargar vista previa. Esto puede activar el enlace.",
        loadLinkPreview: "Cargar vista previa",
        linkPreviewUnavailable: "Vista previa del enlace no disponible",
        privacyMode: "Modo de privacidad",
        privacyModeCaption: "Actívalo para ocultar el contenido y las vistas previas del portapapeles en el estante de este Mac, incluso al compartir la pantalla.",
        clipboardHidden: "Portapapeles oculto",
        ignoreTransient: "Omitir copias temporales",
        ignoreTransientCaption: "Omite las copias marcadas como temporales. Las copias marcadas como ocultas se omiten siempre.",
        top: "Arriba", bottom: "Abajo", left: "Izquierda", right: "Derecha",
        clickToSelect: "Clic para seleccionar", clickToPaste: "Clic para pegar",
        text: "Texto", link: "Enlace", color: "Color", image: "Imagen", file: "Archivo"
    )

    static let sk = ClipboardShelfStrings(
        edge: "Poloha police",
        click: "Jedno kliknutie",
        history: "História",
        pinboards: "Nástenky",
        newPinboard: "Nová nástenka",
        renamePinboard: "Premenovať nástenku",
        deletePinboard: "Odstrániť nástenku",
        pinboardName: "Názov nástenky",
        moveToPinboard: "Presunúť na nástenku",
        removeFromPinboard: "Odobrať z nástenky",
        filterByType: "Filtrovať podľa typu",
        allTypes: "Všetky typy",
        suggestions: "Návrhy schránky",
        suggestionsCaption: "Návrhy používajú aktívnu aplikáciu a nedávnu históriu na tomto Macu bez prístupu k obrazovke.",
        linkPreviews: "Náhľady odkazov",
        linkPreviewsCaption: "Polica odošle vybraný odkaz na jeho web len po výbere možnosti Načítať náhľad. Tým sa môže odkaz aktivovať.",
        loadLinkPreview: "Načítať náhľad",
        linkPreviewUnavailable: "Náhľad odkazu nie je dostupný",
        privacyMode: "Režim súkromia",
        privacyModeCaption: "Zapnite ho, ak chcete skryť obsah schránky a náhľady na polici tohto Macu aj pri zdieľaní obrazovky.",
        clipboardHidden: "Schránka je skrytá",
        ignoreTransient: "Preskakovať dočasné kópie",
        ignoreTransientCaption: "Preskočí kópie označené ako dočasné. Kópie označené ako skryté sa vždy preskočia.",
        top: "Hore", bottom: "Dole", left: "Vľavo", right: "Vpravo",
        clickToSelect: "Vybrať kliknutím", clickToPaste: "Vložiť kliknutím",
        text: "Text", link: "Odkaz", color: "Farba", image: "Obrázok", file: "Súbor"
    )

    static let de = ClipboardShelfStrings(
        edge: "Position der Kartenleiste",
        click: "Einfacher Klick",
        history: "Verlauf",
        pinboards: "Pinnwände",
        newPinboard: "Neue Pinnwand",
        renamePinboard: "Pinnwand umbenennen",
        deletePinboard: "Pinnwand löschen",
        pinboardName: "Name der Pinnwand",
        moveToPinboard: "Auf Pinnwand verschieben",
        removeFromPinboard: "Von Pinnwand entfernen",
        filterByType: "Nach Typ filtern",
        allTypes: "Alle Typen",
        suggestions: "Vorschläge aus der Zwischenablage",
        suggestionsCaption: "Die Vorschläge verwenden die aktive App und den jüngsten Verlauf auf diesem Mac ohne Zugriff auf den Bildschirm.",
        linkPreviews: "Linkvorschauen",
        linkPreviewsCaption: "Die Kartenleiste sendet den ausgewählten Link nur an seine Website, wenn du „Vorschau laden“ wählst. Dabei kann der Link aktiviert werden.",
        loadLinkPreview: "Vorschau laden",
        linkPreviewUnavailable: "Linkvorschau nicht verfügbar",
        privacyMode: "Privatsphärenmodus",
        privacyModeCaption: "Schalte den Modus ein, um Inhalt und Vorschauen der Zwischenablage in der Kartenleiste auf diesem Mac auszublenden, auch bei Bildschirmfreigaben.",
        clipboardHidden: "Zwischenablage ausgeblendet",
        ignoreTransient: "Vorübergehende Kopien überspringen",
        ignoreTransientCaption: "Überspringt als vorübergehend markierte Kopien. Als verborgen markierte Kopien werden immer übersprungen.",
        top: "Oben", bottom: "Unten", left: "Links", right: "Rechts",
        clickToSelect: "Per Klick auswählen", clickToPaste: "Per Klick einfügen",
        text: "Text", link: "Link", color: "Farbe", image: "Bild", file: "Datei"
    )

    static let fr = ClipboardShelfStrings(
        edge: "Position du panneau",
        click: "Simple clic",
        history: "Historique",
        pinboards: "Tableaux",
        newPinboard: "Nouveau tableau",
        renamePinboard: "Renommer le tableau",
        deletePinboard: "Supprimer le tableau",
        pinboardName: "Nom du tableau",
        moveToPinboard: "Déplacer vers le tableau",
        removeFromPinboard: "Retirer du tableau",
        filterByType: "Filtrer par type",
        allTypes: "Tous les types",
        suggestions: "Suggestions du presse-papiers",
        suggestionsCaption: "Les suggestions utilisent l’app active et l’historique récent sur ce Mac, sans accéder à l’écran.",
        linkPreviews: "Aperçus de liens",
        linkPreviewsCaption: "Le panneau envoie le lien sélectionné à son site uniquement si vous choisissez Charger l’aperçu. Cela peut activer le lien.",
        loadLinkPreview: "Charger l’aperçu",
        linkPreviewUnavailable: "Aperçu du lien indisponible",
        privacyMode: "Mode de confidentialité",
        privacyModeCaption: "Activez-le pour masquer le contenu et les aperçus du presse-papiers dans le panneau sur ce Mac, même pendant un partage d’écran.",
        clipboardHidden: "Presse-papiers masqué",
        ignoreTransient: "Ignorer les copies temporaires",
        ignoreTransientCaption: "Ignore les copies marquées comme temporaires. Les copies marquées comme masquées sont toujours ignorées.",
        top: "En haut", bottom: "En bas", left: "À gauche", right: "À droite",
        clickToSelect: "Cliquer pour sélectionner", clickToPaste: "Cliquer pour coller",
        text: "Texte", link: "Lien", color: "Couleur", image: "Image", file: "Fichier"
    )

    static let it = ClipboardShelfStrings(
        edge: "Posizione del pannello",
        click: "Clic singolo",
        history: "Cronologia",
        pinboards: "Bacheche",
        newPinboard: "Nuova bacheca",
        renamePinboard: "Rinomina bacheca",
        deletePinboard: "Elimina bacheca",
        pinboardName: "Nome della bacheca",
        moveToPinboard: "Sposta nella bacheca",
        removeFromPinboard: "Rimuovi dalla bacheca",
        filterByType: "Filtra per tipo",
        allTypes: "Tutti i tipi",
        suggestions: "Suggerimenti degli appunti",
        suggestionsCaption: "I suggerimenti usano l’app attiva e la cronologia recente su questo Mac senza accedere allo schermo.",
        linkPreviews: "Anteprime dei link",
        linkPreviewsCaption: "Il pannello invia il link selezionato al suo sito solo quando scegli Carica anteprima. Questo può attivare il link.",
        loadLinkPreview: "Carica anteprima",
        linkPreviewUnavailable: "Anteprima del link non disponibile",
        privacyMode: "Modalità privacy",
        privacyModeCaption: "Attivala per nascondere il contenuto e le anteprime degli appunti nel pannello su questo Mac, anche durante la condivisione dello schermo.",
        clipboardHidden: "Appunti nascosti",
        ignoreTransient: "Ignora le copie temporanee",
        ignoreTransientCaption: "Ignora le copie contrassegnate come temporanee. Le copie contrassegnate come nascoste vengono sempre ignorate.",
        top: "In alto", bottom: "In basso", left: "A sinistra", right: "A destra",
        clickToSelect: "Clic per selezionare", clickToPaste: "Clic per incollare",
        text: "Testo", link: "Link", color: "Colore", image: "Immagine", file: "File"
    )

    static let ja = ClipboardShelfStrings(
        edge: "シェルフの位置",
        click: "シングルクリック",
        history: "履歴",
        pinboards: "ピンボード",
        newPinboard: "新しいピンボード",
        renamePinboard: "ピンボード名を変更",
        deletePinboard: "ピンボードを削除",
        pinboardName: "ピンボード名",
        moveToPinboard: "ピンボードに移動",
        removeFromPinboard: "ピンボードから取り除く",
        filterByType: "種類で絞り込む",
        allTypes: "すべての種類",
        suggestions: "クリップボードの候補",
        suggestionsCaption: "候補の表示には、このMacで開いているAppと最近の履歴を使います。画面にはアクセスしません。",
        linkPreviews: "リンクのプレビュー",
        linkPreviewsCaption: "「プレビューを読み込む」を選んだ場合にのみ、選択したリンクがリンク先のサイトに送信されます。これによりリンクが有効になることがあります。",
        loadLinkPreview: "プレビューを読み込む",
        linkPreviewUnavailable: "リンクのプレビューを表示できません",
        privacyMode: "プライバシーモード",
        privacyModeCaption: "オンにすると、このMacのシェルフでクリップボードの内容とプレビューを非表示にします。画面共有中にも適用されます。",
        clipboardHidden: "クリップボードは非表示です",
        ignoreTransient: "一時的なコピーを除外",
        ignoreTransientCaption: "一時的としてマークされたコピーを除外します。非公開としてマークされたコピーは常に除外します。",
        top: "上", bottom: "下", left: "左", right: "右",
        clickToSelect: "クリックで選択", clickToPaste: "クリックでペースト",
        text: "テキスト", link: "リンク", color: "カラー", image: "画像", file: "ファイル"
    )

    static let ko = ClipboardShelfStrings(
        edge: "선반 위치",
        click: "한 번 클릭",
        history: "기록",
        pinboards: "핀보드",
        newPinboard: "새 핀보드",
        renamePinboard: "핀보드 이름 변경",
        deletePinboard: "핀보드 삭제",
        pinboardName: "핀보드 이름",
        moveToPinboard: "핀보드로 이동",
        removeFromPinboard: "핀보드에서 제거",
        filterByType: "유형별 필터링",
        allTypes: "모든 유형",
        suggestions: "클립보드 추천",
        suggestionsCaption: "이 Mac의 활성 앱과 최근 기록으로 항목을 추천하며, 화면에는 접근하지 않습니다.",
        linkPreviews: "링크 미리보기",
        linkPreviewsCaption: "미리보기 불러오기를 선택할 때만 선택한 링크를 해당 사이트로 보냅니다. 이때 링크가 활성화될 수 있습니다.",
        loadLinkPreview: "미리보기 불러오기",
        linkPreviewUnavailable: "링크 미리보기를 사용할 수 없음",
        privacyMode: "개인정보 보호 모드",
        privacyModeCaption: "켜면 이 Mac의 선반에서 클립보드 내용과 미리보기를 숨깁니다. 화면 공유 중에도 적용됩니다.",
        clipboardHidden: "클립보드 숨김",
        ignoreTransient: "임시 복사 건너뛰기",
        ignoreTransientCaption: "임시로 표시된 복사는 건너뜁니다. 숨김으로 표시된 복사는 항상 건너뜁니다.",
        top: "상단", bottom: "하단", left: "왼쪽", right: "오른쪽",
        clickToSelect: "클릭하여 선택", clickToPaste: "클릭하여 붙여넣기",
        text: "텍스트", link: "링크", color: "색상", image: "이미지", file: "파일"
    )

    static let uk = ClipboardShelfStrings(
        edge: "Розташування полиці",
        click: "Один клік",
        history: "Історія",
        pinboards: "Дошки",
        newPinboard: "Нова дошка",
        renamePinboard: "Перейменувати дошку",
        deletePinboard: "Видалити дошку",
        pinboardName: "Назва дошки",
        moveToPinboard: "Перемістити на дошку",
        removeFromPinboard: "Прибрати з дошки",
        filterByType: "Фільтрувати за типом",
        allTypes: "Усі типи",
        suggestions: "Пропозиції буфера обміну",
        suggestionsCaption: "Пропозиції використовують активну програму й нещодавню історію на цьому Mac без доступу до екрана.",
        linkPreviews: "Попередній перегляд посилань",
        linkPreviewsCaption: "Полиця надсилає вибране посилання на його сайт лише за командою «Завантажити попередній перегляд». Це може активувати посилання.",
        loadLinkPreview: "Завантажити попередній перегляд",
        linkPreviewUnavailable: "Попередній перегляд посилання недоступний",
        privacyMode: "Режим приватності",
        privacyModeCaption: "Увімкніть, щоб приховати вміст буфера обміну та його попередній перегляд на полиці цього Mac, зокрема під час поширення екрана.",
        clipboardHidden: "Буфер обміну приховано",
        ignoreTransient: "Пропускати тимчасові копії",
        ignoreTransientCaption: "Копії з позначкою «тимчасова» пропускаються. Копії з позначкою «прихована» пропускаються завжди.",
        top: "Вгорі", bottom: "Внизу", left: "Ліворуч", right: "Праворуч",
        clickToSelect: "Клік для вибору", clickToPaste: "Клік для вставлення",
        text: "Текст", link: "Посилання", color: "Колір", image: "Зображення", file: "Файл"
    )

    static let zhHans = ClipboardShelfStrings(
        edge: "剪贴板卡片位置",
        click: "单击操作",
        history: "历史",
        pinboards: "收藏板",
        newPinboard: "新建收藏板",
        renamePinboard: "重命名收藏板",
        deletePinboard: "删除收藏板",
        pinboardName: "收藏板名称",
        moveToPinboard: "移到收藏板",
        removeFromPinboard: "从收藏板移除",
        filterByType: "按类型筛选",
        allTypes: "所有类型",
        suggestions: "剪贴板建议",
        suggestionsCaption: "建议仅使用此 Mac 上的当前 App 和最近的历史，不访问屏幕。",
        linkPreviews: "链接预览",
        linkPreviewsCaption: "只有在选择“加载预览”时，才会向所选链接的网站发送该链接。这可能会激活链接。",
        loadLinkPreview: "加载预览",
        linkPreviewUnavailable: "链接预览不可用",
        privacyMode: "隐私模式",
        privacyModeCaption: "开启后，此 Mac 上的剪贴板卡片窗口将隐藏剪贴板内容和预览，屏幕共享时也适用。",
        clipboardHidden: "剪贴板已隐藏",
        ignoreTransient: "跳过临时拷贝",
        ignoreTransientCaption: "跳过标记为临时的拷贝。标记为隐藏的拷贝始终会被跳过。",
        top: "顶部", bottom: "底部", left: "左侧", right: "右侧",
        clickToSelect: "单击选择", clickToPaste: "单击粘贴",
        text: "文本", link: "链接", color: "颜色", image: "图像", file: "文件"
    )

    static let zhTW = ClipboardShelfStrings(
        edge: "剪貼簿卡片位置",
        click: "點一下的動作",
        history: "紀錄",
        pinboards: "收藏板",
        newPinboard: "新增收藏板",
        renamePinboard: "重新命名收藏板",
        deletePinboard: "刪除收藏板",
        pinboardName: "收藏板名稱",
        moveToPinboard: "移至收藏板",
        removeFromPinboard: "從收藏板移除",
        filterByType: "依類型篩選",
        allTypes: "所有類型",
        suggestions: "剪貼簿建議",
        suggestionsCaption: "建議會使用這部 Mac 上的使用中 App 和近期紀錄，不會存取螢幕。",
        linkPreviews: "連結預覽",
        linkPreviewsCaption: "只有選擇「載入預覽」時，才會將選取的連結傳送至其網站。這可能會啟用連結。",
        loadLinkPreview: "載入預覽",
        linkPreviewUnavailable: "無法使用連結預覽",
        privacyMode: "隱私模式",
        privacyModeCaption: "開啟後，這部 Mac 上的剪貼簿卡片視窗會隱藏剪貼簿內容和預覽，螢幕共享時也適用。",
        clipboardHidden: "剪貼簿已隱藏",
        ignoreTransient: "略過暫時複製的項目",
        ignoreTransientCaption: "略過標示為暫時的複製項目。標示為隱藏的複製項目一律略過。",
        top: "頂端", bottom: "底端", left: "左側", right: "右側",
        clickToSelect: "點一下來選取", clickToPaste: "點一下來貼上",
        text: "文字", link: "連結", color: "顏色", image: "影像", file: "檔案"
    )

    static let zhHK = ClipboardShelfStrings(
        edge: "剪貼簿卡片位置",
        click: "單按操作",
        history: "記錄",
        pinboards: "收藏板",
        newPinboard: "新增收藏板",
        renamePinboard: "重新命名收藏板",
        deletePinboard: "刪除收藏板",
        pinboardName: "收藏板名稱",
        moveToPinboard: "移至收藏板",
        removeFromPinboard: "從收藏板移除",
        filterByType: "按類型篩選",
        allTypes: "所有類型",
        suggestions: "剪貼簿建議",
        suggestionsCaption: "建議會使用這部 Mac 上使用中的 App 和近期記錄，不會存取螢幕。",
        linkPreviews: "連結預覽",
        linkPreviewsCaption: "只有選擇「載入預覽」時，才會把選取的連結傳送至其網站。這可能會啟用該連結。",
        loadLinkPreview: "載入預覽",
        linkPreviewUnavailable: "連結預覽無法使用",
        privacyMode: "私隱模式",
        privacyModeCaption: "開啟後，這部 Mac 的剪貼簿卡片視窗會隱藏內容及預覽，共享螢幕期間亦會隱藏。",
        clipboardHidden: "剪貼簿已隱藏",
        ignoreTransient: "略過暫時複製的項目",
        ignoreTransientCaption: "略過標記為暫時的複製項目。標記為隱藏的複製項目一律略過。",
        top: "頂部", bottom: "底部", left: "左側", right: "右側",
        clickToSelect: "單按選取", clickToPaste: "單按貼上",
        text: "文字", link: "連結", color: "顏色", image: "影像", file: "檔案"
    )
}
