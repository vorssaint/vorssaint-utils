// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WhatsAppDownloadStrings {
    let title: String
    let hubDescription: String
    let intro: String
    let automatic: String
    let automaticCaption: String
    let folder: String
    let accessReady: String
    let accessDenied: String
    let fileTypes: String
    let allTypes: String
    let image: String
    let video: String
    let audio: String
    let document: String
    let archive: String
    let other: String
    let retention: String
    let retentionCaption: String
    let daysFormat: String
    let manualIntro: String
    let noFiles: String
    let resultsFormat: String
    let selectRules: String
    let cleanSelectedFormat: String
    let keep: String
    let manageAgain: String
    let activity: String
    let neverRun: String
    let lastRunFormat: String
    let nextRunFormat: String
    let firstTitle: String
    let firstMessageFormat: String
    let futureOnly: String
    let includeExisting: String
    let trashNote: String
    let localNote: String
    let notificationTitle: String
    let notificationFormat: String
    let scanFailed: String

    static func localized(_ language: AppLanguage) -> WhatsAppDownloadStrings {
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

extension WhatsAppDownloadStrings {
    static let enUS = WhatsAppDownloadStrings(
        title: "WhatsApp downloads",
        hubDescription: "Keeps WhatsApp files in Downloads under control",
        intro: "Finds files that macOS confirms came from WhatsApp. File contents and chats are never read.",
        automatic: "Clean up automatically",
        automaticCaption: "Checks once a day and sends matching files older than your limit to the Trash.",
        folder: "Watched folder",
        accessReady: "Downloads is accessible",
        accessDenied: "Vorssaint cannot access Downloads. Allow it in Files & Folders.",
        fileTypes: "File types",
        allTypes: "All",
        image: "Images",
        video: "Videos",
        audio: "Audio and voice notes",
        document: "Documents",
        archive: "Archives",
        other: "Other",
        retention: "Keep for",
        retentionCaption: "Recently edited files wait for the full period again.",
        daysFormat: "%d days",
        manualIntro: "Scan at any time. The initial selection follows your types and age limit; you can review every confirmed file.",
        noFiles: "No confirmed WhatsApp files found in Downloads.",
        resultsFormat: "%1$d confirmed files · %2$@",
        selectRules: "Select by my rules",
        cleanSelectedFormat: "Move %1$d to Trash · %2$@",
        keep: "Keep",
        manageAgain: "Manage again",
        activity: "Activity",
        neverRun: "No cleanup has run yet.",
        lastRunFormat: "Last cleanup %@: %d files · %@ · %d failed",
        nextRunFormat: "Next automatic check %@.",
        firstTitle: "What about existing files?",
        firstMessageFormat: "%d existing files already match your rules. Choose whether automation may manage them or only future downloads.",
        futureOnly: "Only future downloads",
        includeExisting: "Include existing files",
        trashNote: "Files are moved to the Trash and remain recoverable until you empty it.",
        localNote: "Only local file metadata is inspected. Vorssaint never reads chats or file contents.",
        notificationTitle: "WhatsApp cleanup",
        notificationFormat: "%1$d files (%2$@) moved to the Trash. %3$d failed.",
        scanFailed: "Downloads could not be scanned. Check Files & Folders in System Settings."
    )

    static let es = WhatsAppDownloadStrings(
        title: "Descargas de WhatsApp",
        hubDescription: "Mantiene bajo control los archivos de WhatsApp en Descargas",
        intro: "Encuentra los archivos que macOS confirma que proceden de WhatsApp. Nunca lee su contenido ni tus chats.",
        automatic: "Limpiar automáticamente",
        automaticCaption: "Comprueba una vez al día y envía a la Papelera los archivos seleccionados que superen el plazo.",
        folder: "Carpeta vigilada",
        accessReady: "Descargas está accesible",
        accessDenied: "Vorssaint no puede acceder a Descargas. Permite el acceso en Archivos y carpetas.",
        fileTypes: "Tipos de archivo",
        allTypes: "Todos",
        image: "Imágenes",
        video: "Vídeos",
        audio: "Audios y notas de voz",
        document: "Documentos",
        archive: "Comprimidos",
        other: "Otros",
        retention: "Conservar durante",
        retentionCaption: "Los archivos editados recientemente vuelven a esperar el plazo completo.",
        daysFormat: "%d días",
        manualIntro: "Analiza cuando quieras. La selección inicial respeta tus tipos y antigüedad, pero puedes revisar todos los archivos confirmados.",
        noFiles: "No se encontraron archivos confirmados de WhatsApp en Descargas.",
        resultsFormat: "%1$d archivos confirmados · %2$@",
        selectRules: "Seleccionar según mis reglas",
        cleanSelectedFormat: "Mover %1$d a la Papelera · %2$@",
        keep: "Conservar",
        manageAgain: "Volver a gestionar",
        activity: "Actividad",
        neverRun: "Todavía no se ha realizado ninguna limpieza.",
        lastRunFormat: "Última limpieza %@: %d archivos · %@ · %d fallidos",
        nextRunFormat: "Próxima comprobación automática %@.",
        firstTitle: "¿Qué hacemos con los archivos existentes?",
        firstMessageFormat: "%d archivos existentes ya cumplen tus reglas. Elige si la automatización puede gestionarlos o solo las futuras descargas.",
        futureOnly: "Solo futuras descargas",
        includeExisting: "Incluir los existentes",
        trashNote: "Los archivos se mueven a la Papelera y pueden recuperarse hasta que la vacíes.",
        localNote: "Solo se consultan metadatos locales. Vorssaint nunca lee los chats ni el contenido de los archivos.",
        notificationTitle: "Limpieza de WhatsApp",
        notificationFormat: "%1$d archivos (%2$@) movidos a la Papelera. %3$d fallidos.",
        scanFailed: "No se pudo analizar Descargas. Comprueba Archivos y carpetas en Ajustes del Sistema."
    )

    static let ptBR = WhatsAppDownloadStrings(
        title: "Downloads do WhatsApp",
        hubDescription: "Mantém sob controle os arquivos do WhatsApp em Downloads",
        intro: "Encontra arquivos que o macOS confirma que vieram do WhatsApp. Nunca lê o conteúdo nem suas conversas.",
        automatic: "Limpar automaticamente",
        automaticCaption: "Verifica uma vez por dia e envia para a Lixeira os arquivos selecionados acima do prazo.",
        folder: "Pasta monitorada",
        accessReady: "Downloads está acessível",
        accessDenied: "O Vorssaint não pode acessar Downloads. Permita em Arquivos e Pastas.",
        fileTypes: "Tipos de arquivo",
        allTypes: "Todos",
        image: "Imagens",
        video: "Vídeos",
        audio: "Áudios e mensagens de voz",
        document: "Documentos",
        archive: "Compactados",
        other: "Outros",
        retention: "Manter por",
        retentionCaption: "Arquivos editados recentemente aguardam o prazo completo novamente.",
        daysFormat: "%d dias",
        manualIntro: "Verifique quando quiser. A seleção inicial segue seus tipos e prazo; você pode revisar todos os arquivos confirmados.",
        noFiles: "Nenhum arquivo confirmado do WhatsApp em Downloads.",
        resultsFormat: "%1$d arquivos confirmados · %2$@",
        selectRules: "Selecionar pelas minhas regras",
        cleanSelectedFormat: "Mover %1$d para a Lixeira · %2$@",
        keep: "Manter",
        manageAgain: "Gerenciar novamente",
        activity: "Atividade",
        neverRun: "Nenhuma limpeza foi executada ainda.",
        lastRunFormat: "Última limpeza %@: %d arquivos · %@ · %d falharam",
        nextRunFormat: "Próxima verificação automática %@.",
        firstTitle: "E os arquivos existentes?",
        firstMessageFormat: "%d arquivos existentes já seguem suas regras. Escolha incluí-los ou gerenciar apenas downloads futuros.",
        futureOnly: "Só downloads futuros",
        includeExisting: "Incluir arquivos existentes",
        trashNote: "Os arquivos vão para a Lixeira e podem ser recuperados até ela ser esvaziada.",
        localNote: "Apenas metadados locais são consultados. O Vorssaint nunca lê conversas nem o conteúdo dos arquivos.",
        notificationTitle: "Limpeza do WhatsApp",
        notificationFormat: "%1$d arquivos (%2$@) movidos para a Lixeira. %3$d falharam.",
        scanFailed: "Não foi possível verificar Downloads. Confira Arquivos e Pastas nos Ajustes do Sistema."
    )

    static let de = translated(language: .de,
        title: "WhatsApp-Downloads", hub: "Hält WhatsApp-Dateien in Downloads unter Kontrolle",
        intro: "Findet Dateien, deren Herkunft von macOS als WhatsApp bestätigt wird. Inhalte und Chats werden nie gelesen.",
        automatic: "Automatisch aufräumen", folder: "Überwachter Ordner", accessReady: "Downloads ist zugänglich",
        accessDenied: "Vorssaint kann nicht auf Downloads zugreifen. Erlaube den Zugriff unter Dateien & Ordner.",
        types: "Dateitypen", all: "Alle", image: "Bilder", video: "Videos", audio: "Audio und Sprachnachrichten",
        document: "Dokumente", archive: "Archive", other: "Andere", retention: "Aufbewahren für", days: "%d Tage",
        noFiles: "Keine bestätigten WhatsApp-Dateien in Downloads gefunden.", keep: "Behalten", manage: "Wieder verwalten",
        activity: "Aktivität", never: "Noch keine Bereinigung ausgeführt.", future: "Nur zukünftige Downloads",
        existing: "Vorhandene Dateien einbeziehen", firstTitle: "Was ist mit vorhandenen Dateien?",
        trash: "Dateien werden in den Papierkorb verschoben und bleiben bis zu dessen Leerung wiederherstellbar.",
        notificationTitle: "WhatsApp-Bereinigung")

    static let fr = translated(language: .fr,
        title: "Téléchargements WhatsApp", hub: "Garde les fichiers WhatsApp de Téléchargements sous contrôle",
        intro: "Repère les fichiers dont macOS confirme la provenance WhatsApp. Le contenu et les discussions ne sont jamais lus.",
        automatic: "Nettoyer automatiquement", folder: "Dossier surveillé", accessReady: "Téléchargements est accessible",
        accessDenied: "Vorssaint ne peut pas accéder à Téléchargements. Autorisez-le dans Fichiers et dossiers.",
        types: "Types de fichiers", all: "Tous", image: "Images", video: "Vidéos", audio: "Audio et messages vocaux",
        document: "Documents", archive: "Archives", other: "Autres", retention: "Conserver pendant", days: "%d jours",
        noFiles: "Aucun fichier WhatsApp confirmé dans Téléchargements.", keep: "Conserver", manage: "Gérer à nouveau",
        activity: "Activité", never: "Aucun nettoyage effectué pour le moment.", future: "Téléchargements futurs uniquement",
        existing: "Inclure les fichiers existants", firstTitle: "Que faire des fichiers existants ?",
        trash: "Les fichiers sont placés dans la Corbeille et restent récupérables jusqu'à ce qu'elle soit vidée.",
        notificationTitle: "Nettoyage WhatsApp")

    static let it = translated(language: .it,
        title: "Download di WhatsApp", hub: "Tiene sotto controllo i file WhatsApp in Download",
        intro: "Trova i file che macOS conferma provenire da WhatsApp. Non legge mai contenuti o chat.",
        automatic: "Pulisci automaticamente", folder: "Cartella monitorata", accessReady: "Download è accessibile",
        accessDenied: "Vorssaint non può accedere a Download. Consenti l'accesso in File e cartelle.",
        types: "Tipi di file", all: "Tutti", image: "Immagini", video: "Video", audio: "Audio e messaggi vocali",
        document: "Documenti", archive: "Archivi", other: "Altro", retention: "Conserva per", days: "%d giorni",
        noFiles: "Nessun file WhatsApp confermato in Download.", keep: "Conserva", manage: "Gestisci di nuovo",
        activity: "Attività", never: "Nessuna pulizia ancora eseguita.", future: "Solo download futuri",
        existing: "Includi i file esistenti", firstTitle: "Cosa fare con i file esistenti?",
        trash: "I file vengono spostati nel Cestino e restano recuperabili finché non viene svuotato.",
        notificationTitle: "Pulizia WhatsApp")

    static let tr = translated(language: .tr,
        title: "WhatsApp indirmeleri", hub: "İndirilenler'deki WhatsApp dosyalarını kontrol altında tutar",
        intro: "macOS'in WhatsApp'tan geldiğini doğruladığı dosyaları bulur. İçerikler ve sohbetler asla okunmaz.",
        automatic: "Otomatik temizle", folder: "İzlenen klasör", accessReady: "İndirilenler erişilebilir",
        accessDenied: "Vorssaint İndirilenler'e erişemiyor. Dosyalar ve Klasörler'den izin verin.",
        types: "Dosya türleri", all: "Tümü", image: "Görseller", video: "Videolar", audio: "Ses ve sesli mesajlar",
        document: "Belgeler", archive: "Arşivler", other: "Diğer", retention: "Şu kadar sakla", days: "%d gün",
        noFiles: "İndirilenler'de doğrulanmış WhatsApp dosyası bulunamadı.", keep: "Sakla", manage: "Yeniden yönet",
        activity: "Etkinlik", never: "Henüz temizlik yapılmadı.", future: "Yalnızca gelecekteki indirmeler",
        existing: "Mevcut dosyaları dahil et", firstTitle: "Mevcut dosyalar ne olacak?",
        trash: "Dosyalar Çöp Sepeti'ne taşınır ve boşaltılana kadar kurtarılabilir.",
        notificationTitle: "WhatsApp temizliği")

    static let ru = translated(language: .ru,
        title: "Загрузки WhatsApp", hub: "Наводит порядок среди файлов WhatsApp в Загрузках",
        intro: "Находит файлы, происхождение из WhatsApp которых подтверждает macOS. Содержимое и чаты не читаются.",
        automatic: "Очищать автоматически", folder: "Отслеживаемая папка", accessReady: "Папка «Загрузки» доступна",
        accessDenied: "Vorssaint не может открыть Загрузки. Разрешите доступ в разделе «Файлы и папки».",
        types: "Типы файлов", all: "Все", image: "Изображения", video: "Видео", audio: "Аудио и голосовые сообщения",
        document: "Документы", archive: "Архивы", other: "Другие", retention: "Хранить", days: "%d дн.",
        noFiles: "Подтверждённых файлов WhatsApp в Загрузках нет.", keep: "Сохранить", manage: "Снова управлять",
        activity: "Активность", never: "Очистка ещё не выполнялась.", future: "Только будущие загрузки",
        existing: "Включить существующие файлы", firstTitle: "Что делать с существующими файлами?",
        trash: "Файлы перемещаются в Корзину и доступны для восстановления до её очистки.",
        notificationTitle: "Очистка WhatsApp")

    static let ja = translated(language: .ja,
        title: "WhatsAppのダウンロード", hub: "ダウンロード内のWhatsAppファイルを整理します",
        intro: "macOSがWhatsApp由来と確認したファイルを検出します。内容やチャットは一切読みません。",
        automatic: "自動的に整理", folder: "監視フォルダ", accessReady: "ダウンロードにアクセスできます",
        accessDenied: "ダウンロードにアクセスできません。「ファイルとフォルダ」で許可してください。",
        types: "ファイルの種類", all: "すべて", image: "画像", video: "ビデオ", audio: "音声とボイスメッセージ",
        document: "書類", archive: "アーカイブ", other: "その他", retention: "保存期間", days: "%d日",
        noFiles: "確認済みのWhatsAppファイルはありません。", keep: "保持", manage: "再び管理",
        activity: "履歴", never: "まだ整理を実行していません。", future: "今後のダウンロードのみ",
        existing: "既存ファイルを含める", firstTitle: "既存ファイルの扱い",
        trash: "ファイルはゴミ箱へ移動し、空にするまでは復元できます。", notificationTitle: "WhatsAppの整理")

    static let ko = translated(language: .ko,
        title: "WhatsApp 다운로드", hub: "다운로드 폴더의 WhatsApp 파일을 정리합니다",
        intro: "macOS가 WhatsApp에서 왔다고 확인한 파일을 찾습니다. 내용과 채팅은 읽지 않습니다.",
        automatic: "자동으로 정리", folder: "감시 폴더", accessReady: "다운로드 폴더에 접근할 수 있음",
        accessDenied: "다운로드 폴더에 접근할 수 없습니다. 파일 및 폴더에서 허용하세요.",
        types: "파일 유형", all: "모두", image: "이미지", video: "비디오", audio: "오디오 및 음성 메시지",
        document: "문서", archive: "압축 파일", other: "기타", retention: "보관 기간", days: "%d일",
        noFiles: "확인된 WhatsApp 파일이 없습니다.", keep: "보관", manage: "다시 관리",
        activity: "활동", never: "아직 정리한 기록이 없습니다.", future: "향후 다운로드만",
        existing: "기존 파일 포함", firstTitle: "기존 파일은 어떻게 할까요?",
        trash: "파일은 휴지통으로 이동하며 휴지통을 비우기 전까지 복구할 수 있습니다.", notificationTitle: "WhatsApp 정리")

    static let zhHans = translated(language: .zhHans,
        title: "WhatsApp 下载", hub: "管理下载文件夹中的 WhatsApp 文件",
        intro: "查找经 macOS 确认为来自 WhatsApp 的文件。绝不读取文件内容或聊天。",
        automatic: "自动清理", folder: "监控的文件夹", accessReady: "可以访问下载文件夹",
        accessDenied: "Vorssaint 无法访问下载文件夹。请在“文件与文件夹”中允许访问。",
        types: "文件类型", all: "全部", image: "图像", video: "视频", audio: "音频和语音消息",
        document: "文稿", archive: "压缩包", other: "其他", retention: "保留时间", days: "%d 天",
        noFiles: "下载文件夹中没有确认的 WhatsApp 文件。", keep: "保留", manage: "重新管理",
        activity: "活动", never: "尚未运行清理。", future: "仅未来下载",
        existing: "包括现有文件", firstTitle: "如何处理现有文件？",
        trash: "文件会移到废纸篓，在清倒前仍可恢复。", notificationTitle: "WhatsApp 清理")

    static let zhTW = translated(language: .zhTW,
        title: "WhatsApp 下載項目", hub: "管理下載項目中的 WhatsApp 檔案",
        intro: "尋找經 macOS 確認來自 WhatsApp 的檔案。絕不讀取檔案內容或對話。",
        automatic: "自動清理", folder: "監察的資料夾", accessReady: "可以取用下載項目",
        accessDenied: "Vorssaint 無法取用下載項目。請在「檔案與資料夾」允許取用。",
        types: "檔案類型", all: "全部", image: "圖片", video: "影片", audio: "音訊和語音訊息",
        document: "文件", archive: "壓縮檔", other: "其他", retention: "保留時間", days: "%d 天",
        noFiles: "下載項目中沒有已確認的 WhatsApp 檔案。", keep: "保留", manage: "重新管理",
        activity: "活動", never: "尚未執行清理。", future: "只限日後下載",
        existing: "包括現有檔案", firstTitle: "如何處理現有檔案？",
        trash: "檔案會移至垃圾桶，清空前仍可復原。", notificationTitle: "WhatsApp 清理")

    static let zhHK = translated(language: .zhHK,
        title: "WhatsApp 下載項目", hub: "管理下載項目中的 WhatsApp 檔案",
        intro: "尋找經 macOS 確認來自 WhatsApp 的檔案。絕不讀取檔案內容或對話。",
        automatic: "自動清理", folder: "監察的資料夾", accessReady: "可以取用下載項目",
        accessDenied: "Vorssaint 無法取用下載項目。請在「檔案與資料夾」允許取用。",
        types: "檔案類型", all: "全部", image: "圖片", video: "影片", audio: "音訊和語音訊息",
        document: "文件", archive: "壓縮檔", other: "其他", retention: "保留時間", days: "%d 日",
        noFiles: "下載項目中沒有已確認的 WhatsApp 檔案。", keep: "保留", manage: "重新管理",
        activity: "活動", never: "尚未執行清理。", future: "只限日後下載",
        existing: "包括現有檔案", firstTitle: "如何處理現有檔案？",
        trash: "檔案會移至垃圾桶，清空前仍可還原。", notificationTitle: "WhatsApp 清理")

    private struct OperationalStrings {
        let automaticCaption: String
        let retentionCaption: String
        let manualIntro: String
        let resultsFormat: String
        let selectRules: String
        let cleanSelectedFormat: String
        let lastRunFormat: String
        let nextRunFormat: String
        let firstMessageFormat: String
        let localNote: String
        let notificationFormat: String
        let scanFailed: String
    }

    private static func operational(_ language: AppLanguage) -> OperationalStrings {
        switch language {
        case .de:
            return OperationalStrings(
                automaticCaption: "Prüft einmal täglich und verschiebt passende Dateien nach Ablauf der Frist in den Papierkorb.",
                retentionCaption: "Kürzlich bearbeitete Dateien warten erneut die volle Frist.",
                manualIntro: "Jederzeit prüfen. Die Vorauswahl folgt Typen und Frist; alle bestätigten Dateien bleiben überprüfbar.",
                resultsFormat: "%1$d bestätigte Dateien · %2$@", selectRules: "Nach meinen Regeln auswählen",
                cleanSelectedFormat: "%1$d in den Papierkorb · %2$@",
                lastRunFormat: "Letzte Bereinigung %@: %d Dateien · %@ · %d fehlgeschlagen",
                nextRunFormat: "Nächste automatische Prüfung %@.",
                firstMessageFormat: "%d vorhandene Dateien erfüllen bereits deine Regeln. Wähle, ob sie oder nur künftige Downloads verwaltet werden.",
                localNote: "Nur lokale Metadaten werden geprüft. Vorssaint liest weder Chats noch Dateiinhalte.",
                notificationFormat: "%1$d Dateien (%2$@) in den Papierkorb verschoben. %3$d fehlgeschlagen.",
                scanFailed: "Downloads konnte nicht geprüft werden. Kontrolliere Dateien & Ordner in den Systemeinstellungen.")
        case .fr:
            return OperationalStrings(
                automaticCaption: "Vérifie une fois par jour et place dans la Corbeille les fichiers correspondants arrivés à échéance.",
                retentionCaption: "Un fichier récemment modifié attend à nouveau toute la durée.",
                manualIntro: "Analysez à tout moment. La sélection initiale suit vos types et votre durée, mais tous les fichiers confirmés restent vérifiables.",
                resultsFormat: "%1$d fichiers confirmés · %2$@", selectRules: "Sélectionner selon mes règles",
                cleanSelectedFormat: "Placer %1$d dans la Corbeille · %2$@",
                lastRunFormat: "Dernier nettoyage %@ : %d fichiers · %@ · %d échecs",
                nextRunFormat: "Prochaine vérification automatique %@.",
                firstMessageFormat: "%d fichiers existants correspondent déjà à vos règles. Choisissez de les inclure ou de ne gérer que les futurs téléchargements.",
                localNote: "Seules les métadonnées locales sont consultées. Vorssaint ne lit ni les discussions ni le contenu des fichiers.",
                notificationFormat: "%1$d fichiers (%2$@) placés dans la Corbeille. %3$d échecs.",
                scanFailed: "Impossible d'analyser Téléchargements. Vérifiez Fichiers et dossiers dans Réglages Système.")
        case .it:
            return OperationalStrings(
                automaticCaption: "Controlla una volta al giorno e sposta nel Cestino i file corrispondenti oltre il limite.",
                retentionCaption: "I file modificati di recente attendono nuovamente l'intero periodo.",
                manualIntro: "Controlla in qualsiasi momento. La selezione iniziale segue tipi e durata; puoi rivedere tutti i file confermati.",
                resultsFormat: "%1$d file confermati · %2$@", selectRules: "Seleziona con le mie regole",
                cleanSelectedFormat: "Sposta %1$d nel Cestino · %2$@",
                lastRunFormat: "Ultima pulizia %@: %d file · %@ · %d non riusciti",
                nextRunFormat: "Prossimo controllo automatico %@.",
                firstMessageFormat: "%d file esistenti rispettano già le regole. Scegli se includerli o gestire solo i download futuri.",
                localNote: "Vengono controllati solo metadati locali. Vorssaint non legge chat o contenuti dei file.",
                notificationFormat: "%1$d file (%2$@) spostati nel Cestino. %3$d non riusciti.",
                scanFailed: "Impossibile controllare Download. Verifica File e cartelle nelle Impostazioni di Sistema.")
        case .tr:
            return OperationalStrings(
                automaticCaption: "Günde bir kez denetler ve süresi dolan eşleşen dosyaları Çöp Sepeti'ne taşır.",
                retentionCaption: "Yakın zamanda düzenlenen dosyalar tam süreyi yeniden bekler.",
                manualIntro: "İstediğiniz zaman tarayın. İlk seçim tür ve süre kurallarınıza uyar; doğrulanan tüm dosyaları inceleyebilirsiniz.",
                resultsFormat: "%1$d doğrulanmış dosya · %2$@", selectRules: "Kurallarıma göre seç",
                cleanSelectedFormat: "%1$d dosyayı Çöp Sepeti'ne taşı · %2$@",
                lastRunFormat: "Son temizlik %@: %d dosya · %@ · %d başarısız",
                nextRunFormat: "Sonraki otomatik denetim %@.",
                firstMessageFormat: "%d mevcut dosya kurallarınıza uyuyor. Bunları dahil etmeyi veya yalnızca gelecekteki indirmeleri yönetmeyi seçin.",
                localNote: "Yalnızca yerel meta veriler incelenir. Vorssaint sohbetleri veya dosya içeriklerini okumaz.",
                notificationFormat: "%1$d dosya (%2$@) Çöp Sepeti'ne taşındı. %3$d başarısız.",
                scanFailed: "İndirilenler taranamadı. Sistem Ayarları'nda Dosyalar ve Klasörler'i denetleyin.")
        case .ru:
            return OperationalStrings(
                automaticCaption: "Раз в день проверяет и перемещает в Корзину подходящие файлы старше выбранного срока.",
                retentionCaption: "Для недавно изменённых файлов срок начинается заново.",
                manualIntro: "Запускайте проверку в любое время. Начальный выбор следует типам и сроку; все подтверждённые файлы доступны для просмотра.",
                resultsFormat: "%1$d подтверждённых файлов · %2$@", selectRules: "Выбрать по моим правилам",
                cleanSelectedFormat: "Переместить %1$d в Корзину · %2$@",
                lastRunFormat: "Последняя очистка %@: %d файлов · %@ · ошибок: %d",
                nextRunFormat: "Следующая автоматическая проверка %@.",
                firstMessageFormat: "%d существующих файлов уже подходят под правила. Включите их или управляйте только будущими загрузками.",
                localNote: "Проверяются только локальные метаданные. Vorssaint не читает чаты и содержимое файлов.",
                notificationFormat: "%1$d файлов (%2$@) перемещено в Корзину. Ошибок: %3$d.",
                scanFailed: "Не удалось проверить Загрузки. Проверьте «Файлы и папки» в Системных настройках.")
        case .ja:
            return OperationalStrings(
                automaticCaption: "1日1回確認し、期限を過ぎた対象ファイルをゴミ箱へ移動します。",
                retentionCaption: "最近編集したファイルは保存期間を最初から待ちます。",
                manualIntro: "いつでも確認できます。初期選択は種類と期間に従い、確認済みファイルをすべて見直せます。",
                resultsFormat: "確認済み%1$d件 · %2$@", selectRules: "ルールに従って選択",
                cleanSelectedFormat: "%1$d件をゴミ箱へ · %2$@",
                lastRunFormat: "前回の整理 %@：%d件 · %@ · 失敗%d件", nextRunFormat: "次回の自動確認は%@です。",
                firstMessageFormat: "既存の%d件がすでにルールに一致します。含めるか、今後のダウンロードだけを管理するか選んでください。",
                localNote: "ローカルのメタデータだけを確認します。チャットやファイル内容は読みません。",
                notificationFormat: "%1$d件（%2$@）をゴミ箱へ移動しました。失敗%3$d件。",
                scanFailed: "ダウンロードを確認できません。「ファイルとフォルダ」の許可を確認してください。")
        case .ko:
            return OperationalStrings(
                automaticCaption: "하루 한 번 확인하고 보관 기간이 지난 대상 파일을 휴지통으로 이동합니다.",
                retentionCaption: "최근 편집한 파일은 전체 보관 기간을 다시 기다립니다.",
                manualIntro: "언제든 검사할 수 있습니다. 최초 선택은 유형과 기간을 따르며 확인된 모든 파일을 검토할 수 있습니다.",
                resultsFormat: "확인된 파일 %1$d개 · %2$@", selectRules: "내 규칙으로 선택",
                cleanSelectedFormat: "%1$d개를 휴지통으로 이동 · %2$@",
                lastRunFormat: "마지막 정리 %@: %d개 · %@ · 실패 %d개", nextRunFormat: "다음 자동 확인 %@.",
                firstMessageFormat: "기존 파일 %d개가 이미 규칙에 맞습니다. 포함하거나 향후 다운로드만 관리하도록 선택하세요.",
                localNote: "로컬 메타데이터만 확인합니다. 채팅이나 파일 내용은 읽지 않습니다.",
                notificationFormat: "%1$d개(%2$@)를 휴지통으로 이동했습니다. %3$d개 실패.",
                scanFailed: "다운로드 폴더를 검사할 수 없습니다. 시스템 설정의 파일 및 폴더를 확인하세요.")
        case .zhHans:
            return OperationalStrings(
                automaticCaption: "每天检查一次，并将超过期限的匹配文件移到废纸篓。",
                retentionCaption: "最近编辑过的文件会重新等待完整保留期。",
                manualIntro: "可随时扫描。初始选择遵循类型和期限设置，所有确认文件均可查看。",
                resultsFormat: "%1$d 个确认文件 · %2$@", selectRules: "按我的规则选择",
                cleanSelectedFormat: "将 %1$d 个移到废纸篓 · %2$@",
                lastRunFormat: "上次清理 %@：%d 个文件 · %@ · %d 个失败", nextRunFormat: "下次自动检查 %@。",
                firstMessageFormat: "已有 %d 个文件符合规则。请选择包括它们，或仅管理未来下载。",
                localNote: "只检查本地元数据。Vorssaint 绝不读取聊天或文件内容。",
                notificationFormat: "%1$d 个文件（%2$@）已移到废纸篓。%3$d 个失败。",
                scanFailed: "无法扫描下载文件夹。请检查系统设置中的“文件与文件夹”。")
        case .zhTW, .zhHK:
            return OperationalStrings(
                automaticCaption: "每天檢查一次，並將超過期限的相符檔案移至垃圾桶。",
                retentionCaption: "最近編輯過的檔案會重新等待完整保留期。",
                manualIntro: "可隨時掃描。初始選擇依照類型和期限設定，所有已確認檔案均可檢視。",
                resultsFormat: "%1$d 個已確認檔案 · %2$@", selectRules: "依我的規則選擇",
                cleanSelectedFormat: "將 %1$d 個移至垃圾桶 · %2$@",
                lastRunFormat: "上次清理 %@：%d 個檔案 · %@ · %d 個失敗", nextRunFormat: "下次自動檢查 %@。",
                firstMessageFormat: "已有 %d 個檔案符合規則。請選擇包括它們，或只管理日後下載。",
                localNote: "只檢查本機中繼資料。Vorssaint 絕不讀取對話或檔案內容。",
                notificationFormat: "%1$d 個檔案（%2$@）已移至垃圾桶。%3$d 個失敗。",
                scanFailed: "無法掃描下載項目。請檢查系統設定中的「檔案與資料夾」。")
        case .enUS: return OperationalStrings(
            automaticCaption: enUS.automaticCaption, retentionCaption: enUS.retentionCaption,
            manualIntro: enUS.manualIntro, resultsFormat: enUS.resultsFormat,
            selectRules: enUS.selectRules, cleanSelectedFormat: enUS.cleanSelectedFormat,
            lastRunFormat: enUS.lastRunFormat, nextRunFormat: enUS.nextRunFormat,
            firstMessageFormat: enUS.firstMessageFormat, localNote: enUS.localNote,
            notificationFormat: enUS.notificationFormat, scanFailed: enUS.scanFailed)
        case .ptBR: return OperationalStrings(
            automaticCaption: ptBR.automaticCaption, retentionCaption: ptBR.retentionCaption,
            manualIntro: ptBR.manualIntro, resultsFormat: ptBR.resultsFormat,
            selectRules: ptBR.selectRules, cleanSelectedFormat: ptBR.cleanSelectedFormat,
            lastRunFormat: ptBR.lastRunFormat, nextRunFormat: ptBR.nextRunFormat,
            firstMessageFormat: ptBR.firstMessageFormat, localNote: ptBR.localNote,
            notificationFormat: ptBR.notificationFormat, scanFailed: ptBR.scanFailed)
        case .es: return OperationalStrings(
            automaticCaption: es.automaticCaption, retentionCaption: es.retentionCaption,
            manualIntro: es.manualIntro, resultsFormat: es.resultsFormat,
            selectRules: es.selectRules, cleanSelectedFormat: es.cleanSelectedFormat,
            lastRunFormat: es.lastRunFormat, nextRunFormat: es.nextRunFormat,
            firstMessageFormat: es.firstMessageFormat, localNote: es.localNote,
            notificationFormat: es.notificationFormat, scanFailed: es.scanFailed)
        }
    }

    private static func translated(language: AppLanguage,
                                   title: String, hub: String, intro: String,
                                   automatic: String, folder: String, accessReady: String,
                                   accessDenied: String, types: String, all: String,
                                   image: String, video: String, audio: String,
                                   document: String, archive: String, other: String,
                                   retention: String, days: String, noFiles: String,
                                   keep: String, manage: String, activity: String,
                                   never: String, future: String, existing: String,
                                   firstTitle: String, trash: String,
                                   notificationTitle: String) -> WhatsAppDownloadStrings {
        let value = operational(language)
        return WhatsAppDownloadStrings(
            title: title, hubDescription: hub, intro: intro,
            automatic: automatic, automaticCaption: value.automaticCaption,
            folder: folder, accessReady: accessReady, accessDenied: accessDenied,
            fileTypes: types, allTypes: all, image: image, video: video, audio: audio,
            document: document, archive: archive, other: other,
            retention: retention, retentionCaption: value.retentionCaption, daysFormat: days,
            manualIntro: value.manualIntro, noFiles: noFiles, resultsFormat: value.resultsFormat,
            selectRules: value.selectRules, cleanSelectedFormat: value.cleanSelectedFormat,
            keep: keep, manageAgain: manage, activity: activity, neverRun: never,
            lastRunFormat: value.lastRunFormat, nextRunFormat: value.nextRunFormat,
            firstTitle: firstTitle, firstMessageFormat: value.firstMessageFormat,
            futureOnly: future, includeExisting: existing, trashNote: trash,
            localNote: value.localNote, notificationTitle: notificationTitle,
            notificationFormat: value.notificationFormat, scanFailed: value.scanFailed)
    }
}
