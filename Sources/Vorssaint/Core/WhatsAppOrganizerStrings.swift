// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WhatsAppOrganizerStrings {
    let title: String
    let experimental: String
    let description: String
    let enabled: String
    let enabledCaption: String
    let destination: String
    let chooseFolder: String
    let useDefault: String
    let invalidDestination: String
    let organization: String
    let flat: String
    let byType: String
    let byMonth: String
    let delay: String
    let minutesFormat: String
    let duplicateAction: String
    let trashDuplicate: String
    let keepBoth: String
    let replaceExisting: String
    let duplicateCaption: String
    let organizeNow: String
    let undo: String
    let waiting: String
    let working: String
    let resultFormat: String
    let lastRunFormat: String
    let neverRun: String
    let notificationTitle: String
    let notificationFormat: String
    let privacyNote: String

    static func localized(_ language: AppLanguage) -> WhatsAppOrganizerStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .tr: return .tr
        case .ru: return .ru
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

extension WhatsAppOrganizerStrings {
    static let enUS = WhatsAppOrganizerStrings(
        title: "Automatic organization",
        experimental: "Experimental",
        description: "Moves stable WhatsApp downloads to a dedicated folder and detects exact repeat downloads.",
        enabled: "Organize automatically",
        enabledCaption: "WhatsApp may download a moved file again. Vorssaint cannot prevent the network download, but it can detect and discard an identical extra copy.",
        destination: "Destination folder",
        chooseFolder: "Choose…",
        useDefault: "Use Downloads/WhatsApp",
        invalidDestination: "Choose a folder other than Downloads itself.",
        organization: "Folder structure",
        flat: "No subfolders",
        byType: "By file type",
        byMonth: "By year and month",
        delay: "Wait before moving",
        minutesFormat: "%d minutes",
        duplicateAction: "When the same file is downloaded again",
        trashDuplicate: "Move the new copy to Trash",
        keepBoth: "Keep both copies",
        replaceExisting: "Replace the organized copy",
        duplicateCaption: "Duplicates are confirmed with a private SHA-256 digest. The organized copy is rechecked before another copy is discarded.",
        organizeNow: "Organize eligible files now",
        undo: "Undo last organization",
        waiting: "Watching Downloads",
        working: "Organizing WhatsApp files…",
        resultFormat: "%1$d moved · %2$d duplicates · %3$d failed",
        lastRunFormat: "Last organization %@: %d moved · %d duplicates · %d failed",
        neverRun: "No organization has run yet.",
        notificationTitle: "WhatsApp organization",
        notificationFormat: "%1$d files organized. %2$d duplicate downloads handled. %3$d failed.",
        privacyNote: "To identify exact duplicates, file bytes are read locally only while calculating a cryptographic digest. Contents and chats are never stored or uploaded."
    )

    static let es = WhatsAppOrganizerStrings(
        title: "Organización automática",
        experimental: "Experimental",
        description: "Mueve las descargas estables de WhatsApp a una carpeta específica y detecta las descargas repetidas exactas.",
        enabled: "Organizar automáticamente",
        enabledCaption: "WhatsApp puede volver a descargar un archivo movido. Vorssaint no puede impedir esa descarga, pero sí detectar y descartar una nueva copia idéntica.",
        destination: "Carpeta de destino",
        chooseFolder: "Elegir…",
        useDefault: "Usar Descargas/WhatsApp",
        invalidDestination: "Elige una carpeta distinta de la propia carpeta Descargas.",
        organization: "Estructura de carpetas",
        flat: "Sin subcarpetas",
        byType: "Por tipo de archivo",
        byMonth: "Por año y mes",
        delay: "Esperar antes de mover",
        minutesFormat: "%d minutos",
        duplicateAction: "Si se vuelve a descargar el mismo archivo",
        trashDuplicate: "Enviar la nueva copia a la Papelera",
        keepBoth: "Conservar las dos copias",
        replaceExisting: "Reemplazar la copia organizada",
        duplicateCaption: "Los duplicados se confirman con una huella SHA-256 privada. La copia organizada se vuelve a comprobar antes de descartar otra.",
        organizeNow: "Organizar ahora los archivos disponibles",
        undo: "Deshacer la última organización",
        waiting: "Vigilando Descargas",
        working: "Organizando archivos de WhatsApp…",
        resultFormat: "%1$d movidos · %2$d duplicados · %3$d fallidos",
        lastRunFormat: "Última organización %@: %d movidos · %d duplicados · %d fallidos",
        neverRun: "Todavía no se ha realizado ninguna organización.",
        notificationTitle: "Organización de WhatsApp",
        notificationFormat: "%1$d archivos organizados. %2$d descargas duplicadas gestionadas. %3$d fallidos.",
        privacyNote: "Para reconocer duplicados exactos, los bytes del archivo solo se leen localmente mientras se calcula una huella criptográfica. El contenido y los chats nunca se guardan ni se envían."
    )

    static let ptBR = WhatsAppOrganizerStrings(
        title: "Organização automática",
        experimental: "Experimental",
        description: "Move downloads estáveis do WhatsApp para uma pasta dedicada e detecta downloads repetidos idênticos.",
        enabled: "Organizar automaticamente",
        enabledCaption: "O WhatsApp pode baixar novamente um arquivo movido. O Vorssaint não impede o download, mas detecta e descarta uma nova cópia idêntica.",
        destination: "Pasta de destino",
        chooseFolder: "Escolher…",
        useDefault: "Usar Downloads/WhatsApp",
        invalidDestination: "Escolha uma pasta diferente da própria pasta Downloads.",
        organization: "Estrutura de pastas",
        flat: "Sem subpastas",
        byType: "Por tipo de arquivo",
        byMonth: "Por ano e mês",
        delay: "Aguardar antes de mover",
        minutesFormat: "%d minutos",
        duplicateAction: "Ao baixar o mesmo arquivo novamente",
        trashDuplicate: "Mover a nova cópia para a Lixeira",
        keepBoth: "Manter as duas cópias",
        replaceExisting: "Substituir a cópia organizada",
        duplicateCaption: "Duplicados são confirmados com um resumo SHA-256 privado. A cópia organizada é verificada antes de outra ser descartada.",
        organizeNow: "Organizar agora os arquivos disponíveis",
        undo: "Desfazer a última organização",
        waiting: "Monitorando Downloads",
        working: "Organizando arquivos do WhatsApp…",
        resultFormat: "%1$d movidos · %2$d duplicados · %3$d falharam",
        lastRunFormat: "Última organização %@: %d movidos · %d duplicados · %d falharam",
        neverRun: "Nenhuma organização foi executada ainda.",
        notificationTitle: "Organização do WhatsApp",
        notificationFormat: "%1$d arquivos organizados. %2$d downloads duplicados tratados. %3$d falharam.",
        privacyNote: "Para identificar duplicados exatos, os bytes do arquivo são lidos localmente apenas durante o cálculo do resumo criptográfico. Conteúdos e conversas nunca são salvos nem enviados."
    )

    static let de = WhatsAppOrganizerStrings(
        title: "Automatische Organisation",
        experimental: "Experimentell",
        description: "Verschiebt stabile WhatsApp-Downloads in einen eigenen Ordner und erkennt exakte Wiederholungs-Downloads.",
        enabled: "Automatisch organisieren",
        enabledCaption: "WhatsApp kann eine verschobene Datei erneut herunterladen. Vorssaint kann den Netzwerk-Download nicht verhindern, aber eine identische zusätzliche Kopie erkennen und aussortieren.",
        destination: "Zielordner",
        chooseFolder: "Auswählen…",
        useDefault: "Downloads/WhatsApp verwenden",
        invalidDestination: "Wähle einen anderen Ordner als Downloads selbst.",
        organization: "Ordnerstruktur",
        flat: "Keine Unterordner",
        byType: "Nach Dateityp",
        byMonth: "Nach Jahr und Monat",
        delay: "Vor dem Verschieben warten",
        minutesFormat: "%d Minuten",
        duplicateAction: "Wenn dieselbe Datei erneut heruntergeladen wird",
        trashDuplicate: "Neue Kopie in den Papierkorb legen",
        keepBoth: "Beide Kopien behalten",
        replaceExisting: "Organisierte Kopie ersetzen",
        duplicateCaption: "Duplikate werden mit einer privaten SHA-256-Prüfsumme bestätigt. Die organisierte Kopie wird erneut geprüft, bevor eine weitere Kopie aussortiert wird.",
        organizeNow: "Passende Dateien jetzt organisieren",
        undo: "Letzte Organisation rückgängig machen",
        waiting: "Downloads wird beobachtet",
        working: "WhatsApp-Dateien werden organisiert…",
        resultFormat: "%1$d verschoben · %2$d Duplikate · %3$d fehlgeschlagen",
        lastRunFormat: "Letzte Organisation %@: %d verschoben · %d Duplikate · %d fehlgeschlagen",
        neverRun: "Noch keine Organisation ausgeführt.",
        notificationTitle: "WhatsApp-Organisation",
        notificationFormat: "%1$d Dateien organisiert. %2$d doppelte Downloads behandelt. %3$d fehlgeschlagen.",
        privacyNote: "Zum Erkennen exakter Duplikate werden Dateibytes nur lokal gelesen, während eine kryptografische Prüfsumme berechnet wird. Inhalte und Chats werden nie gespeichert oder hochgeladen."
    )

    static let fr = WhatsAppOrganizerStrings(
        title: "Organisation automatique",
        experimental: "Expérimental",
        description: "Déplace les téléchargements WhatsApp stables vers un dossier dédié et détecte les téléchargements répétés identiques.",
        enabled: "Organiser automatiquement",
        enabledCaption: "WhatsApp peut retélécharger un fichier déplacé. Vorssaint ne peut pas empêcher le téléchargement réseau, mais peut détecter et écarter une copie supplémentaire identique.",
        destination: "Dossier de destination",
        chooseFolder: "Choisir…",
        useDefault: "Utiliser Téléchargements/WhatsApp",
        invalidDestination: "Choisissez un dossier autre que Téléchargements lui-même.",
        organization: "Structure des dossiers",
        flat: "Sans sous-dossiers",
        byType: "Par type de fichier",
        byMonth: "Par année et mois",
        delay: "Attendre avant de déplacer",
        minutesFormat: "%d minutes",
        duplicateAction: "Quand le même fichier est téléchargé à nouveau",
        trashDuplicate: "Placer la nouvelle copie dans la Corbeille",
        keepBoth: "Conserver les deux copies",
        replaceExisting: "Remplacer la copie organisée",
        duplicateCaption: "Les doublons sont confirmés par une empreinte SHA-256 privée. La copie organisée est revérifiée avant qu'une autre copie soit écartée.",
        organizeNow: "Organiser les fichiers éligibles maintenant",
        undo: "Annuler la dernière organisation",
        waiting: "Surveillance de Téléchargements",
        working: "Organisation des fichiers WhatsApp…",
        resultFormat: "%1$d déplacés · %2$d doublons · %3$d échecs",
        lastRunFormat: "Dernière organisation %@ : %d déplacés · %d doublons · %d échecs",
        neverRun: "Aucune organisation effectuée pour le moment.",
        notificationTitle: "Organisation WhatsApp",
        notificationFormat: "%1$d fichiers organisés. %2$d téléchargements en double traités. %3$d échecs.",
        privacyNote: "Pour identifier les doublons exacts, les octets des fichiers sont lus localement uniquement pendant le calcul d'une empreinte cryptographique. Les contenus et les discussions ne sont jamais stockés ni envoyés."
    )

    static let it = WhatsAppOrganizerStrings(
        title: "Organizzazione automatica",
        experimental: "Sperimentale",
        description: "Sposta i download WhatsApp stabili in una cartella dedicata e rileva i download ripetuti identici.",
        enabled: "Organizza automaticamente",
        enabledCaption: "WhatsApp può scaricare di nuovo un file spostato. Vorssaint non può impedire il download di rete, ma può rilevare e scartare una copia aggiuntiva identica.",
        destination: "Cartella di destinazione",
        chooseFolder: "Scegli…",
        useDefault: "Usa Download/WhatsApp",
        invalidDestination: "Scegli una cartella diversa da Download stessa.",
        organization: "Struttura delle cartelle",
        flat: "Senza sottocartelle",
        byType: "Per tipo di file",
        byMonth: "Per anno e mese",
        delay: "Attendi prima di spostare",
        minutesFormat: "%d minuti",
        duplicateAction: "Quando lo stesso file viene scaricato di nuovo",
        trashDuplicate: "Sposta la nuova copia nel Cestino",
        keepBoth: "Conserva entrambe le copie",
        replaceExisting: "Sostituisci la copia organizzata",
        duplicateCaption: "I duplicati sono confermati con un'impronta SHA-256 privata. La copia organizzata viene ricontrollata prima di scartare un'altra copia.",
        organizeNow: "Organizza ora i file idonei",
        undo: "Annulla l'ultima organizzazione",
        waiting: "Download sotto osservazione",
        working: "Organizzazione dei file WhatsApp…",
        resultFormat: "%1$d spostati · %2$d duplicati · %3$d falliti",
        lastRunFormat: "Ultima organizzazione %@: %d spostati · %d duplicati · %d falliti",
        neverRun: "Nessuna organizzazione ancora eseguita.",
        notificationTitle: "Organizzazione WhatsApp",
        notificationFormat: "%1$d file organizzati. %2$d download duplicati gestiti. %3$d falliti.",
        privacyNote: "Per individuare i duplicati esatti, i byte dei file vengono letti solo localmente durante il calcolo di un'impronta crittografica. Contenuti e chat non vengono mai salvati né inviati."
    )

    static let tr = WhatsAppOrganizerStrings(
        title: "Otomatik düzenleme",
        experimental: "Deneysel",
        description: "Kararlı WhatsApp indirmelerini özel bir klasöre taşır ve birebir tekrar indirmeleri saptar.",
        enabled: "Otomatik düzenle",
        enabledCaption: "WhatsApp taşınan bir dosyayı yeniden indirebilir. Vorssaint ağ indirmesini engelleyemez, ancak birebir aynı fazladan kopyayı saptayıp ayıklayabilir.",
        destination: "Hedef klasör",
        chooseFolder: "Seç…",
        useDefault: "İndirilenler/WhatsApp kullan",
        invalidDestination: "İndirilenler'in kendisi dışında bir klasör seçin.",
        organization: "Klasör yapısı",
        flat: "Alt klasörsüz",
        byType: "Dosya türüne göre",
        byMonth: "Yıl ve aya göre",
        delay: "Taşımadan önce bekle",
        minutesFormat: "%d dakika",
        duplicateAction: "Aynı dosya yeniden indirildiğinde",
        trashDuplicate: "Yeni kopyayı Çöp Sepeti'ne taşı",
        keepBoth: "İki kopyayı da tut",
        replaceExisting: "Düzenlenen kopyayı değiştir",
        duplicateCaption: "Kopyalar özel bir SHA-256 özetiyle doğrulanır. Bir kopya ayıklanmadan önce düzenlenen kopya yeniden denetlenir.",
        organizeNow: "Uygun dosyaları şimdi düzenle",
        undo: "Son düzenlemeyi geri al",
        waiting: "İndirilenler izleniyor",
        working: "WhatsApp dosyaları düzenleniyor…",
        resultFormat: "%1$d taşındı · %2$d kopya · %3$d başarısız",
        lastRunFormat: "Son düzenleme %@: %d taşındı · %d kopya · %d başarısız",
        neverRun: "Henüz düzenleme yapılmadı.",
        notificationTitle: "WhatsApp düzenlemesi",
        notificationFormat: "%1$d dosya düzenlendi. %2$d yinelenen indirme işlendi. %3$d başarısız.",
        privacyNote: "Birebir kopyaları saptamak için dosya baytları yalnızca yerel olarak, kriptografik özet hesaplanırken okunur. İçerikler ve sohbetler asla saklanmaz veya gönderilmez."
    )

    static let ru = WhatsAppOrganizerStrings(
        title: "Автоматическая организация",
        experimental: "Экспериментально",
        description: "Перемещает устоявшиеся загрузки WhatsApp в отдельную папку и распознаёт точные повторные загрузки.",
        enabled: "Организовывать автоматически",
        enabledCaption: "WhatsApp может снова загрузить перемещённый файл. Vorssaint не может помешать сетевой загрузке, но распознаёт идентичную лишнюю копию и отсеивает её.",
        destination: "Папка назначения",
        chooseFolder: "Выбрать…",
        useDefault: "Использовать Загрузки/WhatsApp",
        invalidDestination: "Выберите папку, отличную от самих Загрузок.",
        organization: "Структура папок",
        flat: "Без подпапок",
        byType: "По типу файла",
        byMonth: "По году и месяцу",
        delay: "Подождать перед перемещением",
        minutesFormat: "%d минут",
        duplicateAction: "Когда тот же файл загружается снова",
        trashDuplicate: "Переместить новую копию в Корзину",
        keepBoth: "Оставить обе копии",
        replaceExisting: "Заменить организованную копию",
        duplicateCaption: "Дубликаты подтверждаются приватным хешем SHA-256. Организованная копия перепроверяется, прежде чем лишняя копия будет отсеяна.",
        organizeNow: "Организовать подходящие файлы сейчас",
        undo: "Отменить последнюю организацию",
        waiting: "Наблюдение за Загрузками",
        working: "Организация файлов WhatsApp…",
        resultFormat: "%1$d перемещено · %2$d дубликатов · %3$d с ошибкой",
        lastRunFormat: "Последняя организация %@: %d перемещено · %d дубликатов · %d с ошибкой",
        neverRun: "Организация ещё не выполнялась.",
        notificationTitle: "Организация WhatsApp",
        notificationFormat: "%1$d файлов организовано. %2$d повторных загрузок обработано. %3$d с ошибкой.",
        privacyNote: "Для поиска точных дубликатов байты файлов читаются только локально, во время расчёта криптографического хеша. Содержимое и переписка никогда не сохраняются и не отправляются."
    )

    static let ja = WhatsAppOrganizerStrings(
        title: "自動整理",
        experimental: "実験的",
        description: "安定した WhatsApp のダウンロードを専用フォルダへ移動し、完全に同一の再ダウンロードを検出します。",
        enabled: "自動的に整理",
        enabledCaption: "WhatsApp は移動したファイルを再びダウンロードすることがあります。ネットワークのダウンロード自体は防げませんが、同一の余分なコピーを検出して除外できます。",
        destination: "移動先フォルダ",
        chooseFolder: "選択…",
        useDefault: "ダウンロード/WhatsApp を使用",
        invalidDestination: "ダウンロードフォルダそのもの以外を選んでください。",
        organization: "フォルダ構成",
        flat: "サブフォルダなし",
        byType: "ファイルの種類別",
        byMonth: "年月別",
        delay: "移動までの待機",
        minutesFormat: "%d 分",
        duplicateAction: "同じファイルが再びダウンロードされたとき",
        trashDuplicate: "新しいコピーをゴミ箱へ",
        keepBoth: "両方のコピーを残す",
        replaceExisting: "整理済みのコピーを置き換える",
        duplicateCaption: "重複は非公開の SHA-256 ハッシュで確認します。コピーを除外する前に、整理済みのコピーを再確認します。",
        organizeNow: "対象ファイルを今すぐ整理",
        undo: "前回の整理を取り消す",
        waiting: "ダウンロードを監視中",
        working: "WhatsApp のファイルを整理中…",
        resultFormat: "移動 %1$d · 重複 %2$d · 失敗 %3$d",
        lastRunFormat: "前回の整理 %@: 移動 %d · 重複 %d · 失敗 %d",
        neverRun: "まだ整理は実行されていません。",
        notificationTitle: "WhatsApp の整理",
        notificationFormat: "%1$d 個のファイルを整理しました。重複ダウンロード %2$d 件を処理。%3$d 件失敗。",
        privacyNote: "完全な重複を見つけるため、ファイルの内容は暗号学的ハッシュの計算中にローカルでのみ読み取られます。内容やチャットが保存・送信されることはありません。"
    )

    static let ko = WhatsAppOrganizerStrings(
        title: "자동 정리",
        experimental: "실험적",
        description: "안정된 WhatsApp 다운로드를 전용 폴더로 옮기고 완전히 동일한 재다운로드를 감지합니다.",
        enabled: "자동으로 정리",
        enabledCaption: "WhatsApp이 옮긴 파일을 다시 다운로드할 수 있습니다. 네트워크 다운로드 자체는 막을 수 없지만, 동일한 여분의 사본을 감지해 걸러낼 수 있습니다.",
        destination: "대상 폴더",
        chooseFolder: "선택…",
        useDefault: "다운로드/WhatsApp 사용",
        invalidDestination: "다운로드 폴더 자체가 아닌 다른 폴더를 선택하세요.",
        organization: "폴더 구조",
        flat: "하위 폴더 없음",
        byType: "파일 유형별",
        byMonth: "연도와 월별",
        delay: "옮기기 전 대기",
        minutesFormat: "%d분",
        duplicateAction: "같은 파일이 다시 다운로드되면",
        trashDuplicate: "새 사본을 휴지통으로",
        keepBoth: "두 사본 모두 유지",
        replaceExisting: "정리된 사본 교체",
        duplicateCaption: "중복은 비공개 SHA-256 해시로 확인합니다. 사본을 걸러내기 전에 정리된 사본을 다시 검사합니다.",
        organizeNow: "대상 파일 지금 정리",
        undo: "마지막 정리 실행 취소",
        waiting: "다운로드 폴더 감시 중",
        working: "WhatsApp 파일 정리 중…",
        resultFormat: "이동 %1$d · 중복 %2$d · 실패 %3$d",
        lastRunFormat: "마지막 정리 %@: 이동 %d · 중복 %d · 실패 %d",
        neverRun: "아직 정리를 실행하지 않았습니다.",
        notificationTitle: "WhatsApp 정리",
        notificationFormat: "파일 %1$d개를 정리했습니다. 중복 다운로드 %2$d개 처리. %3$d개 실패.",
        privacyNote: "완전한 중복을 찾기 위해 파일 내용은 암호학적 해시를 계산하는 동안에만 로컬에서 읽힙니다. 내용과 대화는 절대 저장되거나 전송되지 않습니다."
    )

    static let zhHans = WhatsAppOrganizerStrings(
        title: "自动整理",
        experimental: "实验性",
        description: "将稳定的 WhatsApp 下载移动到专用文件夹，并识别完全相同的重复下载。",
        enabled: "自动整理",
        enabledCaption: "WhatsApp 可能会再次下载已移动的文件。Vorssaint 无法阻止网络下载，但能识别并剔除完全相同的多余副本。",
        destination: "目标文件夹",
        chooseFolder: "选择…",
        useDefault: "使用 下载/WhatsApp",
        invalidDestination: "请选择下载文件夹本身以外的文件夹。",
        organization: "文件夹结构",
        flat: "不建子文件夹",
        byType: "按文件类型",
        byMonth: "按年份和月份",
        delay: "移动前等待",
        minutesFormat: "%d 分钟",
        duplicateAction: "当同一文件被再次下载时",
        trashDuplicate: "将新副本移到废纸篓",
        keepBoth: "保留两个副本",
        replaceExisting: "替换已整理的副本",
        duplicateCaption: "重复文件通过私有 SHA-256 摘要确认。剔除副本前会重新核对已整理的副本。",
        organizeNow: "立即整理符合条件的文件",
        undo: "撤销上次整理",
        waiting: "正在监视下载文件夹",
        working: "正在整理 WhatsApp 文件…",
        resultFormat: "移动 %1$d · 重复 %2$d · 失败 %3$d",
        lastRunFormat: "上次整理 %@：移动 %d · 重复 %d · 失败 %d",
        neverRun: "尚未执行过整理。",
        notificationTitle: "WhatsApp 整理",
        notificationFormat: "已整理 %1$d 个文件。处理了 %2$d 个重复下载。%3$d 个失败。",
        privacyNote: "为识别完全相同的重复文件，文件内容仅在本地计算加密摘要时被读取。内容和聊天绝不会被保存或上传。"
    )

    static let zhTW = WhatsAppOrganizerStrings(
        title: "自動整理",
        experimental: "實驗性",
        description: "將穩定的 WhatsApp 下載移到專用資料夾，並辨識完全相同的重複下載。",
        enabled: "自動整理",
        enabledCaption: "WhatsApp 可能會再次下載已移動的檔案。Vorssaint 無法阻止網路下載，但能辨識並剔除完全相同的多餘副本。",
        destination: "目標資料夾",
        chooseFolder: "選擇…",
        useDefault: "使用 下載項目/WhatsApp",
        invalidDestination: "請選擇下載資料夾本身以外的資料夾。",
        organization: "資料夾結構",
        flat: "不建子資料夾",
        byType: "依檔案類型",
        byMonth: "依年份與月份",
        delay: "移動前等待",
        minutesFormat: "%d 分鐘",
        duplicateAction: "當同一檔案再次被下載時",
        trashDuplicate: "將新副本移到垃圾桶",
        keepBoth: "保留兩個副本",
        replaceExisting: "取代已整理的副本",
        duplicateCaption: "重複檔案以私有 SHA-256 摘要確認。剔除副本前會重新核對已整理的副本。",
        organizeNow: "立即整理符合條件的檔案",
        undo: "撤銷上次整理",
        waiting: "正在監看下載項目",
        working: "正在整理 WhatsApp 檔案…",
        resultFormat: "移動 %1$d · 重複 %2$d · 失敗 %3$d",
        lastRunFormat: "上次整理 %@：移動 %d · 重複 %d · 失敗 %d",
        neverRun: "尚未執行過整理。",
        notificationTitle: "WhatsApp 整理",
        notificationFormat: "已整理 %1$d 個檔案。處理了 %2$d 個重複下載。%3$d 個失敗。",
        privacyNote: "為辨識完全相同的重複檔案，檔案內容僅在本機計算加密摘要時被讀取。內容與聊天絕不會被儲存或上傳。"
    )

    static let zhHK = WhatsAppOrganizerStrings(
        title: "自動整理",
        experimental: "實驗性",
        description: "將穩定的 WhatsApp 下載移到專用資料夾，並辨識完全相同的重複下載。",
        enabled: "自動整理",
        enabledCaption: "WhatsApp 可能會再次下載已移動的檔案。Vorssaint 無法阻止網路下載，但能辨識並剔除完全相同的多餘副本。",
        destination: "目標資料夾",
        chooseFolder: "選擇…",
        useDefault: "使用 下載項目/WhatsApp",
        invalidDestination: "請選擇下載資料夾本身以外的資料夾。",
        organization: "資料夾結構",
        flat: "不建子資料夾",
        byType: "依檔案類型",
        byMonth: "依年份與月份",
        delay: "移動前等待",
        minutesFormat: "%d 分鐘",
        duplicateAction: "當同一檔案再次被下載時",
        trashDuplicate: "將新副本移到垃圾桶",
        keepBoth: "保留兩個副本",
        replaceExisting: "取代已整理的副本",
        duplicateCaption: "重複檔案以私有 SHA-256 摘要確認。剔除副本前會重新核對已整理的副本。",
        organizeNow: "立即整理符合條件的檔案",
        undo: "撤銷上次整理",
        waiting: "正在監察下載項目",
        working: "正在整理 WhatsApp 檔案…",
        resultFormat: "移動 %1$d · 重複 %2$d · 失敗 %3$d",
        lastRunFormat: "上次整理 %@：移動 %d · 重複 %d · 失敗 %d",
        neverRun: "尚未執行過整理。",
        notificationTitle: "WhatsApp 整理",
        notificationFormat: "已整理 %1$d 個檔案。處理了 %2$d 個重複下載。%3$d 個失敗。",
        privacyNote: "為辨識完全相同的重複檔案，檔案內容僅在本機計算加密摘要時被讀取。內容與聊天絕不會被儲存或上傳。"
    )
}
