// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the Kill Process feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct KillProcessFeatureStrings {
    let pageTitle: String
    let browseSubtitle: String
    let hubDescription: String
    let searchPlaceholder: String
    let columnProcess: String
    let columnCPU: String
    let columnMemory: String
    let columnPID: String
    let groupToggle: String
    let groupCaption: String
    let commandBarToggle: String
    let commandBarCaption: String
    let refreshTooltip: String
    let pidLabelFormat: String
    let processCountFormat: String
    let killButton: String
    let forceKillButton: String
    let killAllFormat: String
    let killTreeButton: String
    let restartButton: String
    let copyPID: String
    let copyPath: String
    let emptyStateTitle: String
    let confirmKillFormat: String
    let confirmForceKillFormat: String
    let confirmKillAllFormat: String
    let confirmKillTreeFormat: String
    let killFailedTitle: String
    let killFailedMessage: String
    let adminPromptFormat: String
}

extension FeatureStrings {
    static func killProcess(_ language: AppLanguage) -> KillProcessFeatureStrings {
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

extension KillProcessFeatureStrings {
    static let enUS = KillProcessFeatureStrings(
        pageTitle: "Kill Process",
        browseSubtitle: "Browse & Kill",
        hubDescription: "Search running processes and force quit, restart, or kill process trees",
        searchPlaceholder: "Filter by name",
        columnProcess: "Process",
        columnCPU: "CPU",
        columnMemory: "Memory",
        columnPID: "PID",
        groupToggle: "Group related processes",
        groupCaption: "Groups helper processes under the app responsible for them.",
        commandBarToggle: "Show in Command Bar",
        commandBarCaption: "Adds running processes to the Command Bar, so you can find and kill them without opening Settings.",
        refreshTooltip: "Refresh",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d processes",
        killButton: "Kill",
        forceKillButton: "Force Kill",
        killAllFormat: "Kill All “%@”",
        killTreeButton: "Kill Process Tree",
        restartButton: "Restart",
        copyPID: "Copy PID",
        copyPath: "Copy Path",
        emptyStateTitle: "No Processes Found",
        confirmKillFormat: "Kill %@?",
        confirmForceKillFormat: "Force Kill %@?",
        confirmKillAllFormat: "Kill all “%@” processes?",
        confirmKillTreeFormat: "Kill %@ and all its child processes?",
        killFailedTitle: "Couldn’t Kill Process",
        killFailedMessage: "The process may have already exited or require additional privileges.",
        adminPromptFormat: "Vorssaint needs administrator access to end “%@”."
    )

    static let ptBR = KillProcessFeatureStrings(
        pageTitle: "Encerrar Processo",
        browseSubtitle: "Ver e Encerrar",
        hubDescription: "Pesquise processos em execução e force o encerramento, reinicie ou encerre árvores de processos",
        searchPlaceholder: "Filtrar por nome",
        columnProcess: "Processo",
        columnCPU: "CPU",
        columnMemory: "Memória",
        columnPID: "PID",
        groupToggle: "Agrupar processos relacionados",
        groupCaption: "Agrupa processos auxiliares sob o app responsável por eles.",
        commandBarToggle: "Mostrar na Barra de Comandos",
        commandBarCaption: "Adiciona os processos em execução à Barra de Comandos, para encontrá-los e encerrá-los sem abrir os Ajustes.",
        refreshTooltip: "Atualizar",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d processos",
        killButton: "Encerrar",
        forceKillButton: "Forçar encerramento",
        killAllFormat: "Encerrar todos “%@”",
        killTreeButton: "Encerrar árvore de processos",
        restartButton: "Reiniciar",
        copyPID: "Copiar PID",
        copyPath: "Copiar caminho",
        emptyStateTitle: "Nenhum processo encontrado",
        confirmKillFormat: "Encerrar %@?",
        confirmForceKillFormat: "Forçar encerramento de %@?",
        confirmKillAllFormat: "Encerrar todos os processos “%@”?",
        confirmKillTreeFormat: "Encerrar %@ e todos os seus processos filhos?",
        killFailedTitle: "Não foi possível encerrar o processo",
        killFailedMessage: "O processo pode já ter saído ou exigir privilégios adicionais.",
        adminPromptFormat: "O Vorssaint precisa de acesso de administrador para encerrar “%@”."
    )

    static let tr = KillProcessFeatureStrings(
        pageTitle: "İşlemi Sonlandır",
        browseSubtitle: "Görüntüle ve Sonlandır",
        hubDescription: "Çalışan işlemleri arayın; zorla kapatın, yeniden başlatın veya işlem ağaçlarını sonlandırın",
        searchPlaceholder: "Ada göre filtrele",
        columnProcess: "İşlem",
        columnCPU: "CPU",
        columnMemory: "Bellek",
        columnPID: "PID",
        groupToggle: "İlgili işlemleri grupla",
        groupCaption: "Yardımcı işlemleri sorumlu oldukları uygulama altında gruplar.",
        commandBarToggle: "Komut Çubuğunda Göster",
        commandBarCaption: "Çalışan işlemleri Komut Çubuğuna ekler, böylece Ayarları açmadan bulup sonlandırabilirsiniz.",
        refreshTooltip: "Yenile",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d işlem",
        killButton: "Sonlandır",
        forceKillButton: "Zorla Sonlandır",
        killAllFormat: "Tüm “%@” işlemlerini sonlandır",
        killTreeButton: "İşlem Ağacını Sonlandır",
        restartButton: "Yeniden Başlat",
        copyPID: "PID’yi Kopyala",
        copyPath: "Yolu Kopyala",
        emptyStateTitle: "İşlem Bulunamadı",
        confirmKillFormat: "%@ sonlandırılsın mı?",
        confirmForceKillFormat: "%@ zorla sonlandırılsın mı?",
        confirmKillAllFormat: "Tüm “%@” işlemleri sonlandırılsın mı?",
        confirmKillTreeFormat: "%@ ve tüm alt işlemleri sonlandırılsın mı?",
        killFailedTitle: "İşlem Sonlandırılamadı",
        killFailedMessage: "İşlem zaten sona ermiş veya ek yetki gerektiriyor olabilir.",
        adminPromptFormat: "Vorssaint’in “%@” işlemini sonlandırması için yönetici erişimi gerekiyor."
    )

    static let ru = KillProcessFeatureStrings(
        pageTitle: "Завершить процесс",
        browseSubtitle: "Просмотр и завершение",
        hubDescription: "Поиск запущенных процессов, принудительное завершение, перезапуск или завершение дерева процессов",
        searchPlaceholder: "Фильтр по имени",
        columnProcess: "Процесс",
        columnCPU: "ЦП",
        columnMemory: "Память",
        columnPID: "PID",
        groupToggle: "Группировать связанные процессы",
        groupCaption: "Группирует вспомогательные процессы под ответственным за них приложением.",
        commandBarToggle: "Показывать в панели команд",
        commandBarCaption: "Добавляет запущенные процессы в панель команд, чтобы находить и завершать их без открытия настроек.",
        refreshTooltip: "Обновить",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d процессов",
        killButton: "Завершить",
        forceKillButton: "Завершить принудительно",
        killAllFormat: "Завершить все «%@»",
        killTreeButton: "Завершить дерево процессов",
        restartButton: "Перезапустить",
        copyPID: "Скопировать PID",
        copyPath: "Скопировать путь",
        emptyStateTitle: "Процессы не найдены",
        confirmKillFormat: "Завершить %@?",
        confirmForceKillFormat: "Принудительно завершить %@?",
        confirmKillAllFormat: "Завершить все процессы «%@»?",
        confirmKillTreeFormat: "Завершить %@ и все его дочерние процессы?",
        killFailedTitle: "Не удалось завершить процесс",
        killFailedMessage: "Процесс мог уже завершиться или требует дополнительных прав.",
        adminPromptFormat: "Vorssaint нужны права администратора, чтобы завершить «%@»."
    )

    static let es = KillProcessFeatureStrings(
        pageTitle: "Finalizar Proceso",
        browseSubtitle: "Ver y Finalizar",
        hubDescription: "Busca procesos en ejecución y fuerza su cierre, reinícialos o finaliza árboles de procesos",
        searchPlaceholder: "Filtrar por nombre",
        columnProcess: "Proceso",
        columnCPU: "CPU",
        columnMemory: "Memoria",
        columnPID: "PID",
        groupToggle: "Agrupar procesos relacionados",
        groupCaption: "Agrupa los procesos auxiliares bajo la app responsable de ellos.",
        commandBarToggle: "Mostrar en la Barra de Comandos",
        commandBarCaption: "Añade los procesos en ejecución a la Barra de Comandos, para encontrarlos y finalizarlos sin abrir los Ajustes.",
        refreshTooltip: "Actualizar",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d procesos",
        killButton: "Finalizar",
        forceKillButton: "Forzar finalización",
        killAllFormat: "Finalizar todos “%@”",
        killTreeButton: "Finalizar árbol de procesos",
        restartButton: "Reiniciar",
        copyPID: "Copiar PID",
        copyPath: "Copiar ruta",
        emptyStateTitle: "No se encontraron procesos",
        confirmKillFormat: "¿Finalizar %@?",
        confirmForceKillFormat: "¿Forzar la finalización de %@?",
        confirmKillAllFormat: "¿Finalizar todos los procesos “%@”?",
        confirmKillTreeFormat: "¿Finalizar %@ y todos sus procesos hijos?",
        killFailedTitle: "No se pudo finalizar el proceso",
        killFailedMessage: "El proceso puede haber terminado ya o requerir privilegios adicionales.",
        adminPromptFormat: "Vorssaint necesita acceso de administrador para finalizar “%@”."
    )

    static let de = KillProcessFeatureStrings(
        pageTitle: "Prozess beenden",
        browseSubtitle: "Anzeigen & Beenden",
        hubDescription: "Laufende Prozesse durchsuchen, erzwungen beenden, neu starten oder Prozessbäume beenden",
        searchPlaceholder: "Nach Namen filtern",
        columnProcess: "Prozess",
        columnCPU: "CPU",
        columnMemory: "Speicher",
        columnPID: "PID",
        groupToggle: "Zusammengehörige Prozesse gruppieren",
        groupCaption: "Gruppiert Hilfsprozesse unter der dafür verantwortlichen App.",
        commandBarToggle: "In der Befehlsleiste anzeigen",
        commandBarCaption: "Fügt laufende Prozesse der Befehlsleiste hinzu, sodass du sie finden und beenden kannst, ohne die Einstellungen zu öffnen.",
        refreshTooltip: "Aktualisieren",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d Prozesse",
        killButton: "Beenden",
        forceKillButton: "Beenden erzwingen",
        killAllFormat: "Alle „%@“ beenden",
        killTreeButton: "Prozessbaum beenden",
        restartButton: "Neu starten",
        copyPID: "PID kopieren",
        copyPath: "Pfad kopieren",
        emptyStateTitle: "Keine Prozesse gefunden",
        confirmKillFormat: "%@ beenden?",
        confirmForceKillFormat: "%@ zwangsweise beenden?",
        confirmKillAllFormat: "Alle „%@“-Prozesse beenden?",
        confirmKillTreeFormat: "%@ und alle untergeordneten Prozesse beenden?",
        killFailedTitle: "Prozess konnte nicht beendet werden",
        killFailedMessage: "Der Prozess wurde möglicherweise bereits beendet oder benötigt zusätzliche Rechte.",
        adminPromptFormat: "Vorssaint benötigt Administratorrechte, um „%@“ zu beenden."
    )

    static let fr = KillProcessFeatureStrings(
        pageTitle: "Forcer à quitter",
        browseSubtitle: "Parcourir et arrêter",
        hubDescription: "Recherchez les processus en cours et forcez-les à quitter, redémarrez-les ou arrêtez leurs arborescences",
        searchPlaceholder: "Filtrer par nom",
        columnProcess: "Processus",
        columnCPU: "CPU",
        columnMemory: "Mémoire",
        columnPID: "PID",
        groupToggle: "Regrouper les processus liés",
        groupCaption: "Regroupe les processus auxiliaires sous l'app qui en est responsable.",
        commandBarToggle: "Afficher dans la Barre de Commandes",
        commandBarCaption: "Ajoute les processus en cours à la Barre de Commandes, pour les trouver et les arrêter sans ouvrir les Réglages.",
        refreshTooltip: "Actualiser",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d processus",
        killButton: "Arrêter",
        forceKillButton: "Forcer l'arrêt",
        killAllFormat: "Arrêter tous les « %@ »",
        killTreeButton: "Arrêter l'arborescence du processus",
        restartButton: "Redémarrer",
        copyPID: "Copier le PID",
        copyPath: "Copier le chemin",
        emptyStateTitle: "Aucun processus trouvé",
        confirmKillFormat: "Arrêter %@ ?",
        confirmForceKillFormat: "Forcer l'arrêt de %@ ?",
        confirmKillAllFormat: "Arrêter tous les processus « %@ » ?",
        confirmKillTreeFormat: "Arrêter %@ et tous ses processus enfants ?",
        killFailedTitle: "Impossible d'arrêter le processus",
        killFailedMessage: "Le processus a peut-être déjà quitté ou nécessite des privilèges supplémentaires.",
        adminPromptFormat: "Vorssaint a besoin d'un accès administrateur pour arrêter « %@ »."
    )

    static let it = KillProcessFeatureStrings(
        pageTitle: "Termina Processo",
        browseSubtitle: "Sfoglia e Termina",
        hubDescription: "Cerca i processi in esecuzione e forzane l'uscita, riavviali o termina intere alberature di processi",
        searchPlaceholder: "Filtra per nome",
        columnProcess: "Processo",
        columnCPU: "CPU",
        columnMemory: "Memoria",
        columnPID: "PID",
        groupToggle: "Raggruppa processi correlati",
        groupCaption: "Raggruppa i processi ausiliari sotto l'app responsabile.",
        commandBarToggle: "Mostra nella Barra dei Comandi",
        commandBarCaption: "Aggiunge i processi in esecuzione alla Barra dei Comandi, per trovarli e terminarli senza aprire le Impostazioni.",
        refreshTooltip: "Aggiorna",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d processi",
        killButton: "Termina",
        forceKillButton: "Forza terminazione",
        killAllFormat: "Termina tutti “%@”",
        killTreeButton: "Termina alberatura del processo",
        restartButton: "Riavvia",
        copyPID: "Copia PID",
        copyPath: "Copia percorso",
        emptyStateTitle: "Nessun processo trovato",
        confirmKillFormat: "Terminare %@?",
        confirmForceKillFormat: "Forzare la terminazione di %@?",
        confirmKillAllFormat: "Terminare tutti i processi “%@”?",
        confirmKillTreeFormat: "Terminare %@ e tutti i suoi processi figli?",
        killFailedTitle: "Impossibile terminare il processo",
        killFailedMessage: "Il processo potrebbe essere già uscito o richiedere privilegi aggiuntivi.",
        adminPromptFormat: "Vorssaint richiede l'accesso da amministratore per terminare “%@”."
    )

    static let ja = KillProcessFeatureStrings(
        pageTitle: "プロセスを強制終了",
        browseSubtitle: "表示して終了",
        hubDescription: "実行中のプロセスを検索し、強制終了、再起動、プロセスツリーの終了ができます",
        searchPlaceholder: "名前で絞り込む",
        columnProcess: "プロセス",
        columnCPU: "CPU",
        columnMemory: "メモリ",
        columnPID: "PID",
        groupToggle: "関連プロセスをグループ化",
        groupCaption: "ヘルパープロセスを、責任を持つアプリの下にまとめます。",
        commandBarToggle: "コマンドバーに表示",
        commandBarCaption: "実行中のプロセスをコマンドバーに追加し、設定を開かずに検索して終了できるようにします。",
        refreshTooltip: "更新",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d個のプロセス",
        killButton: "終了",
        forceKillButton: "強制終了",
        killAllFormat: "「%@」をすべて終了",
        killTreeButton: "プロセスツリーを終了",
        restartButton: "再起動",
        copyPID: "PIDをコピー",
        copyPath: "パスをコピー",
        emptyStateTitle: "プロセスが見つかりません",
        confirmKillFormat: "%@を終了しますか？",
        confirmForceKillFormat: "%@を強制終了しますか？",
        confirmKillAllFormat: "「%@」のプロセスをすべて終了しますか？",
        confirmKillTreeFormat: "%@とすべての子プロセスを終了しますか？",
        killFailedTitle: "プロセスを終了できませんでした",
        killFailedMessage: "プロセスはすでに終了しているか、追加の権限が必要な可能性があります。",
        adminPromptFormat: "「%@」を終了するには管理者アクセスが必要です。"
    )

    static let ko = KillProcessFeatureStrings(
        pageTitle: "프로세스 종료",
        browseSubtitle: "보기 및 종료",
        hubDescription: "실행 중인 프로세스를 검색하고 강제 종료, 재시작 또는 프로세스 트리 종료를 수행합니다",
        searchPlaceholder: "이름으로 필터링",
        columnProcess: "프로세스",
        columnCPU: "CPU",
        columnMemory: "메모리",
        columnPID: "PID",
        groupToggle: "관련 프로세스 그룹화",
        groupCaption: "도우미 프로세스를 담당 앱 아래로 그룹화합니다.",
        commandBarToggle: "명령 막대에 표시",
        commandBarCaption: "실행 중인 프로세스를 명령 막대에 추가하여 설정을 열지 않고도 찾아서 종료할 수 있습니다.",
        refreshTooltip: "새로고침",
        pidLabelFormat: "PID %d",
        processCountFormat: "프로세스 %d개",
        killButton: "종료",
        forceKillButton: "강제 종료",
        killAllFormat: "“%@” 모두 종료",
        killTreeButton: "프로세스 트리 종료",
        restartButton: "재시작",
        copyPID: "PID 복사",
        copyPath: "경로 복사",
        emptyStateTitle: "프로세스를 찾을 수 없습니다",
        confirmKillFormat: "%@을(를) 종료할까요?",
        confirmForceKillFormat: "%@을(를) 강제 종료할까요?",
        confirmKillAllFormat: "“%@” 프로세스를 모두 종료할까요?",
        confirmKillTreeFormat: "%@와(과) 모든 하위 프로세스를 종료할까요?",
        killFailedTitle: "프로세스를 종료할 수 없습니다",
        killFailedMessage: "프로세스가 이미 종료되었거나 추가 권한이 필요할 수 있습니다.",
        adminPromptFormat: "“%@”을(를) 종료하려면 관리자 권한이 필요합니다."
    )

    static let zhHans = KillProcessFeatureStrings(
        pageTitle: "结束进程",
        browseSubtitle: "浏览并结束",
        hubDescription: "搜索正在运行的进程，强制退出、重新启动或结束整个进程树",
        searchPlaceholder: "按名称筛选",
        columnProcess: "进程",
        columnCPU: "CPU",
        columnMemory: "内存",
        columnPID: "PID",
        groupToggle: "合并相关进程",
        groupCaption: "将辅助进程归并到负责它们的 App 下面。",
        commandBarToggle: "在命令栏中显示",
        commandBarCaption: "将正在运行的进程加入命令栏，无需打开设置即可查找并结束它们。",
        refreshTooltip: "刷新",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d 个进程",
        killButton: "结束",
        forceKillButton: "强制结束",
        killAllFormat: "结束所有“%@”",
        killTreeButton: "结束进程树",
        restartButton: "重新启动",
        copyPID: "拷贝 PID",
        copyPath: "拷贝路径",
        emptyStateTitle: "未找到进程",
        confirmKillFormat: "要结束“%@”吗？",
        confirmForceKillFormat: "要强制结束“%@”吗？",
        confirmKillAllFormat: "要结束所有“%@”进程吗？",
        confirmKillTreeFormat: "要结束“%@”及其所有子进程吗？",
        killFailedTitle: "无法结束进程",
        killFailedMessage: "该进程可能已经退出，或需要额外的权限。",
        adminPromptFormat: "Vorssaint 需要您的管理员密码才能结束“%@”。"
    )

    static let zhTW = KillProcessFeatureStrings(
        pageTitle: "結束處理程序",
        browseSubtitle: "瀏覽並結束",
        hubDescription: "搜尋正在執行的處理程序，強制結束、重新啟動或結束整個處理程序樹",
        searchPlaceholder: "依名稱篩選",
        columnProcess: "處理程序",
        columnCPU: "CPU",
        columnMemory: "記憶體",
        columnPID: "PID",
        groupToggle: "合併相關處理程序",
        groupCaption: "將輔助處理程序歸併到負責它們的 App 底下。",
        commandBarToggle: "在指令列中顯示",
        commandBarCaption: "將正在執行的處理程序加入指令列，不必開啟設定即可尋找並結束它們。",
        refreshTooltip: "重新整理",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d 個處理程序",
        killButton: "結束",
        forceKillButton: "強制結束",
        killAllFormat: "結束所有「%@」",
        killTreeButton: "結束處理程序樹",
        restartButton: "重新啟動",
        copyPID: "拷貝 PID",
        copyPath: "拷貝路徑",
        emptyStateTitle: "找不到處理程序",
        confirmKillFormat: "要結束「%@」嗎？",
        confirmForceKillFormat: "要強制結束「%@」嗎？",
        confirmKillAllFormat: "要結束所有「%@」處理程序嗎？",
        confirmKillTreeFormat: "要結束「%@」及其所有子處理程序嗎？",
        killFailedTitle: "無法結束處理程序",
        killFailedMessage: "該處理程序可能已經結束，或需要額外的權限。",
        adminPromptFormat: "Vorssaint 需要管理員權限才能結束「%@」。"
    )

    static let zhHK = KillProcessFeatureStrings(
        pageTitle: "結束處理程序",
        browseSubtitle: "瀏覽並結束",
        hubDescription: "搜尋正在執行的處理程序，強制結束、重新啟動或結束整個處理程序樹",
        searchPlaceholder: "依名稱篩選",
        columnProcess: "處理程序",
        columnCPU: "CPU",
        columnMemory: "記憶體",
        columnPID: "PID",
        groupToggle: "合併相關處理程序",
        groupCaption: "將輔助處理程序歸併到負責它們的應用程式底下。",
        commandBarToggle: "在指令列中顯示",
        commandBarCaption: "將正在執行的處理程序加入指令列，不必開啟設定即可尋找並結束它們。",
        refreshTooltip: "重新整理",
        pidLabelFormat: "PID %d",
        processCountFormat: "%d 個處理程序",
        killButton: "結束",
        forceKillButton: "強制結束",
        killAllFormat: "結束所有「%@」",
        killTreeButton: "結束處理程序樹",
        restartButton: "重新啟動",
        copyPID: "拷貝 PID",
        copyPath: "拷貝路徑",
        emptyStateTitle: "找不到處理程序",
        confirmKillFormat: "要結束「%@」嗎？",
        confirmForceKillFormat: "要強制結束「%@」嗎？",
        confirmKillAllFormat: "要結束所有「%@」處理程序嗎？",
        confirmKillTreeFormat: "要結束「%@」及其所有子處理程序嗎？",
        killFailedTitle: "無法結束處理程序",
        killFailedMessage: "該處理程序可能已經結束，或需要額外的權限。",
        adminPromptFormat: "Vorssaint 需要管理員權限才能結束「%@」。"
    )
}
