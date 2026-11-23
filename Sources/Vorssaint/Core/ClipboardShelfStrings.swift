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
        linkPreviews: "Link previews",
        linkPreviewsCaption: "Automatically load thumbnails for visible links in the clipboard shelf. Pages may load resources from other sites. Loading can activate a link.",
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
        linkPreviews: "Pré-visualizações de links",
        linkPreviewsCaption: "Carrega automaticamente miniaturas dos links visíveis na barra da área de transferência. As páginas podem carregar recursos de outros sites. Isso pode ativar um link.",
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
        linkPreviews: "Bağlantı önizlemeleri",
        linkPreviewsCaption: "Pano rafında görünen bağlantıların küçük resimlerini otomatik olarak yükler. Sayfalar başka sitelerden kaynak yükleyebilir. Yükleme bağlantıyı etkinleştirebilir.",
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
        linkPreviews: "Предпросмотр ссылок",
        linkPreviewsCaption: "Автоматически загружает миниатюры видимых ссылок на панели буфера обмена. Страницы могут загружать ресурсы с других сайтов. Загрузка может активировать ссылку.",
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
        linkPreviews: "Vistas previas de enlaces",
        linkPreviewsCaption: "Carga automáticamente las miniaturas de los enlaces visibles en el panel del portapapeles. Las páginas pueden cargar recursos de otros sitios. La carga puede activar un enlace.",
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
        linkPreviews: "Náhľady odkazov",
        linkPreviewsCaption: "Automaticky načíta miniatúry viditeľných odkazov na paneli schránky. Stránky môžu načítať zdroje z iných webov. Načítaním sa môže odkaz aktivovať.",
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
        linkPreviews: "Linkvorschauen",
        linkPreviewsCaption: "Lädt automatisch Miniaturansichten für sichtbare Links in der Zwischenablageleiste. Seiten können Ressourcen von anderen Websites laden. Dabei kann ein Link aktiviert werden.",
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
        linkPreviews: "Aperçus de liens",
        linkPreviewsCaption: "Charge automatiquement les vignettes des liens visibles dans le panneau du presse-papiers. Les pages peuvent charger des ressources d’autres sites. Cela peut activer un lien.",
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
        linkPreviews: "Anteprime dei link",
        linkPreviewsCaption: "Carica automaticamente le miniature dei link visibili nel pannello degli appunti. Le pagine possono caricare risorse da altri siti. Il caricamento può attivare un link.",
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
        linkPreviews: "リンクのプレビュー",
        linkPreviewsCaption: "クリップボードシェルフに表示されたリンクのサムネイルを自動で読み込みます。ページが他のサイトからリソースを取得したり、読み込みによってリンクが有効になったりすることがあります。",
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
        linkPreviews: "링크 미리보기",
        linkPreviewsCaption: "클립보드 선반에 표시되는 링크의 썸네일을 자동으로 불러옵니다. 페이지에서 다른 사이트의 리소스를 불러올 수 있습니다. 불러오면 링크가 활성화될 수 있습니다.",
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
        linkPreviews: "Попередній перегляд посилань",
        linkPreviewsCaption: "Автоматично завантажує мініатюри видимих посилань на панелі буфера обміну. Сторінки можуть завантажувати ресурси з інших сайтів. Завантаження може активувати посилання.",
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
        linkPreviews: "链接预览",
        linkPreviewsCaption: "自动加载剪贴板面板中可见链接的缩略图。网页可能会加载其他网站的资源。加载可能会激活链接。",
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
        linkPreviews: "連結預覽",
        linkPreviewsCaption: "自動載入剪貼簿面板中可見連結的縮圖。網頁可能會載入其他網站的資源。載入可能會啟用連結。",
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
        linkPreviews: "連結預覽",
        linkPreviewsCaption: "自動載入剪貼簿面板中可見連結的縮圖。網頁可能會載入其他網站的資源。載入可能會啟用連結。",
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
