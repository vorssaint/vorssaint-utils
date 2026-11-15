// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DiskAnalyzerFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let scanHome: String
    let scanStartupDisk: String
    let chooseFolder: String
    let rescan: String
    let cancel: String
    let includeHidden: String
    let includeHiddenCaption: String
    let scanningFormat: String
    let emptyTitle: String
    let emptySubtitle: String
    let scanFailed: String
    let revealInFinder: String
    let open: String
    let copyPath: String
    let moveToTrash: String
    let confirmTrashFormat: String
    let confirmTrashMessage: String
    let trashUnavailable: String
    let zoomIn: String
    let sizeLabel: String
    let percentOfParentFormat: String
    let filesFormat: String
    let selectedNone: String
    let fullDiskNote: String
}

extension FeatureStrings {
    static func diskAnalyzer(_ language: AppLanguage) -> DiskAnalyzerFeatureStrings {
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

extension DiskAnalyzerFeatureStrings {
    static let enUS = DiskAnalyzerFeatureStrings(
        pageTitle: "Disk Analyzer",
        hubDescription: "See what fills your disk with a colored treemap, then reveal or trash large folders",
        panelCaption: "Find what uses space",
        scanHome: "Scan Home",
        scanStartupDisk: "Scan Startup Disk",
        chooseFolder: "Choose Folder…",
        rescan: "Rescan",
        cancel: "Cancel",
        includeHidden: "Include hidden files",
        includeHiddenCaption: "Counts dotfiles and other items Finder normally hides.",
        scanningFormat: "Scanning… %@ · %d items",
        emptyTitle: "Scan a folder to begin",
        emptySubtitle: "Home is a good start. Full Disk Access helps when scanning system areas.",
        scanFailed: "Couldn’t scan that location. Check permissions and try again.",
        revealInFinder: "Reveal in Finder",
        open: "Open",
        copyPath: "Copy Path",
        moveToTrash: "Move to Trash",
        confirmTrashFormat: "Move “%@” to the Trash?",
        confirmTrashMessage: "You can restore it from the Trash later.",
        trashUnavailable: "This item can’t be moved to the Trash with the current permissions.",
        zoomIn: "Zoom In",
        sizeLabel: "Size",
        percentOfParentFormat: "%@ of parent",
        filesFormat: "%d items",
        selectedNone: "Click a box to inspect it",
        fullDiskNote: "Full Disk Access unlocks system folders the scan can’t see yet."
    )

    static let ptBR = DiskAnalyzerFeatureStrings(
        pageTitle: "Analisador de Disco",
        hubDescription: "Veja o que ocupa o disco em um mapa de cores e revele ou envie pastas grandes à Lixeira",
        panelCaption: "Descubra o que usa espaço",
        scanHome: "Analisar Início",
        scanStartupDisk: "Analisar disco de inicialização",
        chooseFolder: "Escolher pasta…",
        rescan: "Analisar de novo",
        cancel: "Cancelar",
        includeHidden: "Incluir arquivos ocultos",
        includeHiddenCaption: "Conta arquivos com ponto e outros itens que o Finder normalmente oculta.",
        scanningFormat: "Analisando… %@ · %d itens",
        emptyTitle: "Analise uma pasta para começar",
        emptySubtitle: "A pasta Início é um bom começo. O Acesso Total ao Disco ajuda em áreas do sistema.",
        scanFailed: "Não foi possível analisar esse local. Verifique as permissões e tente de novo.",
        revealInFinder: "Mostrar no Finder",
        open: "Abrir",
        copyPath: "Copiar caminho",
        moveToTrash: "Mover para a Lixeira",
        confirmTrashFormat: "Mover “%@” para a Lixeira?",
        confirmTrashMessage: "Você pode restaurá-lo depois pela Lixeira.",
        trashUnavailable: "Este item não pode ir para a Lixeira com as permissões atuais.",
        zoomIn: "Aproximar",
        sizeLabel: "Tamanho",
        percentOfParentFormat: "%@ do pai",
        filesFormat: "%d itens",
        selectedNone: "Clique em uma caixa para inspecionar",
        fullDiskNote: "O Acesso Total ao Disco libera pastas do sistema que a análise ainda não vê."
    )

    static let tr = DiskAnalyzerFeatureStrings(
        pageTitle: "Disk Analizi",
        hubDescription: "Renkli bir treemap ile diski neyin doldurduğunu görün, büyük klasörleri gösterin veya Çöp Kutusu’na taşıyın",
        panelCaption: "Alanı neyin kullandığını bulun",
        scanHome: "Ana Klasörü Tara",
        scanStartupDisk: "Başlangıç diskini tara",
        chooseFolder: "Klasör seç…",
        rescan: "Yeniden tara",
        cancel: "İptal",
        includeHidden: "Gizli dosyaları dahil et",
        includeHiddenCaption: "Finder’ın genelde gizlediği noktalı dosyaları ve diğer öğeleri sayar.",
        scanningFormat: "Taranıyor… %@ · %d öğe",
        emptyTitle: "Başlamak için bir klasör tarayın",
        emptySubtitle: "Ana klasör iyi bir başlangıçtır. Sistem alanları için Tam Disk Erişimi yardımcı olur.",
        scanFailed: "Bu konum taranamadı. İzinleri kontrol edip yeniden deneyin.",
        revealInFinder: "Finder’da Göster",
        open: "Aç",
        copyPath: "Yolu Kopyala",
        moveToTrash: "Çöp Kutusu’na Taşı",
        confirmTrashFormat: "“%@” Çöp Kutusu’na taşınsın mı?",
        confirmTrashMessage: "Daha sonra Çöp Kutusu’ndan geri yükleyebilirsiniz.",
        trashUnavailable: "Bu öğe mevcut izinlerle Çöp Kutusu’na taşınamıyor.",
        zoomIn: "Yakınlaştır",
        sizeLabel: "Boyut",
        percentOfParentFormat: "üst öğenin %@",
        filesFormat: "%d öğe",
        selectedNone: "İncelemek için bir kutuya tıklayın",
        fullDiskNote: "Tam Disk Erişimi, taramanın henüz göremediği sistem klasörlerini açar."
    )

    static let ru = DiskAnalyzerFeatureStrings(
        pageTitle: "Анализ диска",
        hubDescription: "Цветная карта покажет, что занимает место; можно открыть или удалить крупные папки",
        panelCaption: "Найти, что занимает место",
        scanHome: "Сканировать Домой",
        scanStartupDisk: "Сканировать системный диск",
        chooseFolder: "Выбрать папку…",
        rescan: "Повторить",
        cancel: "Отмена",
        includeHidden: "Включать скрытые файлы",
        includeHiddenCaption: "Учитывает файлы с точкой и другое, что Finder обычно скрывает.",
        scanningFormat: "Сканирование… %@ · %d объектов",
        emptyTitle: "Начните со сканирования папки",
        emptySubtitle: "Домашняя папка — удобный старт. Полный доступ к диску помогает в системных областях.",
        scanFailed: "Не удалось просканировать. Проверьте права доступа и повторите.",
        revealInFinder: "Показать в Finder",
        open: "Открыть",
        copyPath: "Скопировать путь",
        moveToTrash: "Переместить в Корзину",
        confirmTrashFormat: "Переместить «%@» в Корзину?",
        confirmTrashMessage: "Позже можно восстановить из Корзины.",
        trashUnavailable: "Недостаточно прав, чтобы переместить этот объект в Корзину.",
        zoomIn: "Увеличить",
        sizeLabel: "Размер",
        percentOfParentFormat: "%@ от родителя",
        filesFormat: "%d объектов",
        selectedNone: "Нажмите на блок, чтобы проверить его",
        fullDiskNote: "Полный доступ к диску открывает системные папки, которые пока не видны."
    )

    static let es = DiskAnalyzerFeatureStrings(
        pageTitle: "Analizador de disco",
        hubDescription: "Mira qué llena el disco con un mapa de colores y revela o mueve carpetas grandes a la Papelera",
        panelCaption: "Descubre qué ocupa espacio",
        scanHome: "Analizar Inicio",
        scanStartupDisk: "Analizar disco de arranque",
        chooseFolder: "Elegir carpeta…",
        rescan: "Volver a analizar",
        cancel: "Cancelar",
        includeHidden: "Incluir archivos ocultos",
        includeHiddenCaption: "Cuenta archivos con punto y otros que el Finder suele ocultar.",
        scanningFormat: "Analizando… %@ · %d elementos",
        emptyTitle: "Analiza una carpeta para empezar",
        emptySubtitle: "Inicio es un buen comienzo. El acceso completo al disco ayuda en zonas del sistema.",
        scanFailed: "No se pudo analizar esa ubicación. Comprueba los permisos e inténtalo de nuevo.",
        revealInFinder: "Mostrar en el Finder",
        open: "Abrir",
        copyPath: "Copiar ruta",
        moveToTrash: "Mover a la Papelera",
        confirmTrashFormat: "¿Mover “%@” a la Papelera?",
        confirmTrashMessage: "Podrás restaurarlo desde la Papelera más tarde.",
        trashUnavailable: "No se puede mover este elemento a la Papelera con los permisos actuales.",
        zoomIn: "Acercar",
        sizeLabel: "Tamaño",
        percentOfParentFormat: "%@ del superior",
        filesFormat: "%d elementos",
        selectedNone: "Haz clic en un cuadro para inspeccionarlo",
        fullDiskNote: "El acceso completo al disco abre carpetas del sistema que el análisis aún no ve."
    )

    static let sk = DiskAnalyzerFeatureStrings(
        pageTitle: "Analyzátor disku",
        hubDescription: "Farebná mapa ukáže, čo zapĺňa disk; veľké priečinky môžete zobraziť alebo presunúť do Koša",
        panelCaption: "Zistite, čo zaberá miesto",
        scanHome: "Skenovať Domov",
        scanStartupDisk: "Skenovať štartovací disk",
        chooseFolder: "Vybrať priečinok…",
        rescan: "Znova skenovať",
        cancel: "Zrušiť",
        includeHidden: "Zahrnúť skryté súbory",
        includeHiddenCaption: "Počíta súbory s bodkou a iné položky, ktoré Finder bežne skrýva.",
        scanningFormat: "Skenuje sa… %@ · %d položiek",
        emptyTitle: "Začnite skenovaním priečinka",
        emptySubtitle: "Domovský priečinok je dobrý začiatok. Úplný prístup k disku pomôže v systémových oblastiach.",
        scanFailed: "Toto umiestnenie sa nepodarilo naskenovať. Skontrolujte oprávnenia a skúste znova.",
        revealInFinder: "Zobraziť vo Finderi",
        open: "Otvoriť",
        copyPath: "Kopírovať cestu",
        moveToTrash: "Presunúť do Koša",
        confirmTrashFormat: "Presunúť „%@“ do Koša?",
        confirmTrashMessage: "Neskôr ho môžete obnoviť z Koša.",
        trashUnavailable: "Túto položku nemožno s aktuálnymi oprávneniami presunúť do Koša.",
        zoomIn: "Priblížiť",
        sizeLabel: "Veľkosť",
        percentOfParentFormat: "%@ z nadradeného",
        filesFormat: "%d položiek",
        selectedNone: "Kliknite na políčko na kontrolu",
        fullDiskNote: "Úplný prístup k disku odomkne systémové priečinky, ktoré sken ešte nevidí."
    )

    static let de = DiskAnalyzerFeatureStrings(
        pageTitle: "Festplattenanalyse",
        hubDescription: "Farbige Karte zeigt, was den Speicher füllt; große Ordner anzeigen oder in den Papierkorb legen",
        panelCaption: "Speicherfresser finden",
        scanHome: "Benutzerordner scannen",
        scanStartupDisk: "Startdatenträger scannen",
        chooseFolder: "Ordner wählen…",
        rescan: "Erneut scannen",
        cancel: "Abbrechen",
        includeHidden: "Versteckte Dateien einbeziehen",
        includeHiddenCaption: "Zählt Punktdateien und anderes, was der Finder normalerweise ausblendet.",
        scanningFormat: "Scannen… %@ · %d Elemente",
        emptyTitle: "Ordner scannen, um zu starten",
        emptySubtitle: "Der Benutzerordner ist ein guter Start. Voller Festplattenzugriff hilft in Systembereichen.",
        scanFailed: "Dieser Ort ließ sich nicht scannen. Prüfe die Rechte und versuche es erneut.",
        revealInFinder: "Im Finder zeigen",
        open: "Öffnen",
        copyPath: "Pfad kopieren",
        moveToTrash: "In den Papierkorb",
        confirmTrashFormat: "„%@“ in den Papierkorb legen?",
        confirmTrashMessage: "Du kannst es später aus dem Papierkorb wiederherstellen.",
        trashUnavailable: "Mit den aktuellen Rechten lässt sich dieses Element nicht in den Papierkorb legen.",
        zoomIn: "Vergrößern",
        sizeLabel: "Größe",
        percentOfParentFormat: "%@ des Übergeordneten",
        filesFormat: "%d Elemente",
        selectedNone: "Klicke auf ein Feld zur Prüfung",
        fullDiskNote: "Voller Festplattenzugriff öffnet Systemordner, die der Scan noch nicht sieht."
    )

    static let fr = DiskAnalyzerFeatureStrings(
        pageTitle: "Analyseur de disque",
        hubDescription: "Carte colorée de l’espace disque ; affichez ou mettez à la Corbeille les gros dossiers",
        panelCaption: "Trouver ce qui prend de la place",
        scanHome: "Analyser Accueil",
        scanStartupDisk: "Analyser le disque de démarrage",
        chooseFolder: "Choisir un dossier…",
        rescan: "Relancer",
        cancel: "Annuler",
        includeHidden: "Inclure les fichiers masqués",
        includeHiddenCaption: "Compte les fichiers point et autres éléments que le Finder masque d’habitude.",
        scanningFormat: "Analyse… %@ · %d éléments",
        emptyTitle: "Analysez un dossier pour commencer",
        emptySubtitle: "Le dossier Accueil est un bon début. L’accès complet au disque aide pour le système.",
        scanFailed: "Impossible d’analyser cet emplacement. Vérifiez les permissions et réessayez.",
        revealInFinder: "Afficher dans le Finder",
        open: "Ouvrir",
        copyPath: "Copier le chemin",
        moveToTrash: "Mettre à la Corbeille",
        confirmTrashFormat: "Mettre « %@ » à la Corbeille ?",
        confirmTrashMessage: "Vous pourrez le restaurer plus tard depuis la Corbeille.",
        trashUnavailable: "Cet élément ne peut pas aller à la Corbeille avec les permissions actuelles.",
        zoomIn: "Zoom avant",
        sizeLabel: "Taille",
        percentOfParentFormat: "%@ du parent",
        filesFormat: "%d éléments",
        selectedNone: "Cliquez une case pour l’inspecter",
        fullDiskNote: "L’accès complet au disque ouvre les dossiers système encore invisibles."
    )

    static let it = DiskAnalyzerFeatureStrings(
        pageTitle: "Analizzatore disco",
        hubDescription: "Mappa colorata di cosa occupa il disco; mostra o sposta cartelle grandi nel Cestino",
        panelCaption: "Scopri cosa usa spazio",
        scanHome: "Analizza Inizio",
        scanStartupDisk: "Analizza disco di avvio",
        chooseFolder: "Scegli cartella…",
        rescan: "Ripeti analisi",
        cancel: "Annulla",
        includeHidden: "Includi file nascosti",
        includeHiddenCaption: "Conta i file con punto e altri elementi che il Finder di solito nasconde.",
        scanningFormat: "Analisi… %@ · %d elementi",
        emptyTitle: "Analizza una cartella per iniziare",
        emptySubtitle: "La cartella Inizio è un buon inizio. L’accesso completo al disco aiuta nelle aree di sistema.",
        scanFailed: "Impossibile analizzare quella posizione. Controlla i permessi e riprova.",
        revealInFinder: "Mostra nel Finder",
        open: "Apri",
        copyPath: "Copia percorso",
        moveToTrash: "Sposta nel Cestino",
        confirmTrashFormat: "Spostare “%@” nel Cestino?",
        confirmTrashMessage: "Potrai ripristinarlo dal Cestino in seguito.",
        trashUnavailable: "Con i permessi attuali questo elemento non può andare nel Cestino.",
        zoomIn: "Ingrandisci",
        sizeLabel: "Dimensione",
        percentOfParentFormat: "%@ del genitore",
        filesFormat: "%d elementi",
        selectedNone: "Fai clic su una casella per ispezionarla",
        fullDiskNote: "L’accesso completo al disco sblocca cartelle di sistema ancora non visibili."
    )

    static let ja = DiskAnalyzerFeatureStrings(
        pageTitle: "ディスクアナライザー",
        hubDescription: "色分けされたマップでディスクの使用状況を確認し、大きなフォルダを表示またはゴミ箱へ移動",
        panelCaption: "容量を使うものを探す",
        scanHome: "ホームをスキャン",
        scanStartupDisk: "起動ディスクをスキャン",
        chooseFolder: "フォルダを選択…",
        rescan: "再スキャン",
        cancel: "キャンセル",
        includeHidden: "非表示ファイルを含める",
        includeHiddenCaption: "Finderが通常隠すドットファイルなどを含めます。",
        scanningFormat: "スキャン中… %@ · %d 項目",
        emptyTitle: "フォルダをスキャンして開始",
        emptySubtitle: "ホームから始めるのがおすすめです。システム領域にはフルディスクアクセスが役立ちます。",
        scanFailed: "その場所をスキャンできませんでした。権限を確認して再試行してください。",
        revealInFinder: "Finderに表示",
        open: "開く",
        copyPath: "パスをコピー",
        moveToTrash: "ゴミ箱に入れる",
        confirmTrashFormat: "“%@”をゴミ箱に入れますか？",
        confirmTrashMessage: "あとからゴミ箱から復元できます。",
        trashUnavailable: "現在の権限ではこの項目をゴミ箱に入れられません。",
        zoomIn: "ズームイン",
        sizeLabel: "サイズ",
        percentOfParentFormat: "親の%@",
        filesFormat: "%d 項目",
        selectedNone: "ボックスをクリックして確認",
        fullDiskNote: "フルディスクアクセスで、まだ見えないシステムフォルダを開けます。"
    )

    static let ko = DiskAnalyzerFeatureStrings(
        pageTitle: "디스크 분석기",
        hubDescription: "색상 트리맵으로 디스크를 채우는 항목을 보고 큰 폴더를 열거나 휴지통으로 이동",
        panelCaption: "공간을 쓰는 항목 찾기",
        scanHome: "홈 스캔",
        scanStartupDisk: "시동 디스크 스캔",
        chooseFolder: "폴더 선택…",
        rescan: "다시 스캔",
        cancel: "취소",
        includeHidden: "숨김 파일 포함",
        includeHiddenCaption: "Finder가 보통 숨기는 점 파일 등을 포함합니다.",
        scanningFormat: "스캔 중… %@ · %d개 항목",
        emptyTitle: "폴더를 스캔하여 시작",
        emptySubtitle: "홈부터 시작하면 좋습니다. 시스템 영역에는 전체 디스크 접근이 도움이 됩니다.",
        scanFailed: "해당 위치를 스캔할 수 없습니다. 권한을 확인하고 다시 시도하세요.",
        revealInFinder: "Finder에서 보기",
        open: "열기",
        copyPath: "경로 복사",
        moveToTrash: "휴지통으로 이동",
        confirmTrashFormat: "“%@”을(를) 휴지통으로 이동할까요?",
        confirmTrashMessage: "나중에 휴지통에서 복원할 수 있습니다.",
        trashUnavailable: "현재 권한으로는 이 항목을 휴지통으로 옮길 수 없습니다.",
        zoomIn: "확대",
        sizeLabel: "크기",
        percentOfParentFormat: "상위 항목의 %@",
        filesFormat: "%d개 항목",
        selectedNone: "상자를 클릭해 검사",
        fullDiskNote: "전체 디스크 접근으로 아직 보이지 않는 시스템 폴더를 엽니다."
    )

    static let zhHans = DiskAnalyzerFeatureStrings(
        pageTitle: "磁盘分析",
        hubDescription: "用彩色树状图查看磁盘占用，并可显示或将大文件夹移到废纸篓",
        panelCaption: "找出占用空间的内容",
        scanHome: "扫描主文件夹",
        scanStartupDisk: "扫描启动磁盘",
        chooseFolder: "选择文件夹…",
        rescan: "重新扫描",
        cancel: "取消",
        includeHidden: "包含隐藏文件",
        includeHiddenCaption: "统计以点开头等 Finder 通常隐藏的项目。",
        scanningFormat: "正在扫描… %@ · %d 项",
        emptyTitle: "扫描文件夹以开始",
        emptySubtitle: "从主文件夹开始比较合适。完整磁盘访问有助于系统区域。",
        scanFailed: "无法扫描该位置。请检查权限后重试。",
        revealInFinder: "在 Finder 中显示",
        open: "打开",
        copyPath: "拷贝路径",
        moveToTrash: "移到废纸篓",
        confirmTrashFormat: "将“%@”移到废纸篓？",
        confirmTrashMessage: "之后可从废纸篓还原。",
        trashUnavailable: "以当前权限无法将该项目移到废纸篓。",
        zoomIn: "放大",
        sizeLabel: "大小",
        percentOfParentFormat: "占上级 %@",
        filesFormat: "%d 项",
        selectedNone: "点击方块以检查",
        fullDiskNote: "完整磁盘访问可打开扫描尚不可见的系统文件夹。"
    )

    static let zhTW = DiskAnalyzerFeatureStrings(
        pageTitle: "磁碟分析",
        hubDescription: "用彩色樹狀圖查看磁碟占用，並可顯示或將大型檔案夾移到垃圾桶",
        panelCaption: "找出占用空間的內容",
        scanHome: "掃描主檔案夾",
        scanStartupDisk: "掃描開機磁碟",
        chooseFolder: "選擇檔案夾…",
        rescan: "重新掃描",
        cancel: "取消",
        includeHidden: "包含隱藏檔案",
        includeHiddenCaption: "計算以點開頭等 Finder 通常隱藏的項目。",
        scanningFormat: "正在掃描… %@ · %d 項目",
        emptyTitle: "掃描檔案夾以開始",
        emptySubtitle: "從主檔案夾開始較合適。完整磁碟取用有助於系統區域。",
        scanFailed: "無法掃描該位置。請檢查權限後再試。",
        revealInFinder: "在 Finder 中顯示",
        open: "打開",
        copyPath: "拷貝路徑",
        moveToTrash: "移到垃圾桶",
        confirmTrashFormat: "要將「%@」移到垃圾桶嗎？",
        confirmTrashMessage: "之後可從垃圾桶還原。",
        trashUnavailable: "以目前權限無法將此項目移到垃圾桶。",
        zoomIn: "放大",
        sizeLabel: "大小",
        percentOfParentFormat: "佔上層 %@",
        filesFormat: "%d 項目",
        selectedNone: "按一下方塊以檢查",
        fullDiskNote: "完整磁碟取用可開啟掃描尚不可見的系統檔案夾。"
    )

    static let zhHK = DiskAnalyzerFeatureStrings(
        pageTitle: "磁碟分析",
        hubDescription: "用彩色樹狀圖查看磁碟佔用，並可顯示或將大型資料夾移到廢紙簍",
        panelCaption: "找出佔用空間的內容",
        scanHome: "掃描主資料夾",
        scanStartupDisk: "掃描開機磁碟",
        chooseFolder: "選擇資料夾…",
        rescan: "重新掃描",
        cancel: "取消",
        includeHidden: "包含隱藏檔案",
        includeHiddenCaption: "計算以點開頭等 Finder 通常隱藏的項目。",
        scanningFormat: "正在掃描… %@ · %d 項目",
        emptyTitle: "掃描資料夾以開始",
        emptySubtitle: "從主資料夾開始較合適。完整磁碟取用有助於系統區域。",
        scanFailed: "無法掃描該位置。請檢查權限後再試。",
        revealInFinder: "在 Finder 中顯示",
        open: "開啟",
        copyPath: "拷貝路徑",
        moveToTrash: "移到廢紙簍",
        confirmTrashFormat: "要將「%@」移到廢紙簍嗎？",
        confirmTrashMessage: "之後可從廢紙簍還原。",
        trashUnavailable: "以目前權限無法將此項目移到廢紙簍。",
        zoomIn: "放大",
        sizeLabel: "大小",
        percentOfParentFormat: "佔上層 %@",
        filesFormat: "%d 項目",
        selectedNone: "按一下方塊以檢查",
        fullDiskNote: "完整磁碟取用可開啟掃描尚不可見的系統資料夾。"
    )

    static let uk = DiskAnalyzerFeatureStrings(
        pageTitle: "Аналіз диска",
        hubDescription: "Кольорова карта покаже, що займає місце; можна відкрити або перемістити великі папки в Смітник",
        panelCaption: "Знайти, що займає місце",
        scanHome: "Сканувати Домівку",
        scanStartupDisk: "Сканувати системний диск",
        chooseFolder: "Вибрати папку…",
        rescan: "Повторити",
        cancel: "Скасувати",
        includeHidden: "Включати приховані файли",
        includeHiddenCaption: "Рахує файли з крапкою та інше, що Finder зазвичай ховає.",
        scanningFormat: "Сканування… %@ · %d об’єктів",
        emptyTitle: "Почніть зі сканування папки",
        emptySubtitle: "Домашня папка — зручний старт. Повний доступ до диска допомагає в системних областях.",
        scanFailed: "Не вдалося просканувати. Перевірте права доступу та повторіть.",
        revealInFinder: "Показати у Finder",
        open: "Відкрити",
        copyPath: "Скопіювати шлях",
        moveToTrash: "Перемістити в Смітник",
        confirmTrashFormat: "Перемістити «%@» в Смітник?",
        confirmTrashMessage: "Пізніше можна відновити зі Смітника.",
        trashUnavailable: "Недостатньо прав, щоб перемістити цей об’єкт у Смітник.",
        zoomIn: "Збільшити",
        sizeLabel: "Розмір",
        percentOfParentFormat: "%@ від батьківського",
        filesFormat: "%d об’єктів",
        selectedNone: "Натисніть блок, щоб перевірити",
        fullDiskNote: "Повний доступ до диска відкриває системні папки, які ще не видно."
    )
}
