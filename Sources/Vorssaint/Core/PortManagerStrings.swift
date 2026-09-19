// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PortManagerFeatureStrings {
    let title: String
    let filter: String
    let openFormat: String
    let empty: String
    let emptyHint: String
    let listeningCaption: String
    let kill: String
    let forceKill: String
    let refresh: String
    let terminateFormat: String
    let terminateMessageFormat: String
    let hubDescription: String
}

extension FeatureStrings {
    static func portManager(_ language: AppLanguage) -> PortManagerFeatureStrings {
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
        case .he: return .he
        }
    }
}

extension PortManagerFeatureStrings {
    static let enUS = PortManagerFeatureStrings(title: "Port Manager", filter: "Filter by port, process, or PID", openFormat: "%d open", empty: "No listening ports found", emptyHint: "Try refreshing or changing your search.", listeningCaption: "Your listening ports", kill: "Kill", forceKill: "Force Kill", refresh: "Refresh", terminateFormat: "Terminate %@?", terminateMessageFormat: "This closes port %d by terminating PID %d.", hubDescription: "View active listening ports and terminate the processes using them")

    static let he = PortManagerFeatureStrings(title: "מנהל פורטים", filter: "סנן לפי פורט, תהליך או PID", openFormat: "%d פתוחים", empty: "לא נמצאו פורטים מאזינים", emptyHint: "נסה לרענן או לשנות את החיפוש.", listeningCaption: "הפורטים המאזינים שלך", kill: "סיים", forceKill: "אלץ סיום", refresh: "רענן", terminateFormat: "לסיים את %@?", terminateMessageFormat: "פעולה זו סוגרת את פורט %d על ידי סיום PID %d.", hubDescription: "הצג פורטים מאזינים פעילים וסיים את התהליכים שמשתמשים בהם")
    static let ptBR = PortManagerFeatureStrings(title: "Gerenciador de portas", filter: "Filtrar por porta, processo ou PID", openFormat: "%d abertas", empty: "Nenhuma porta de escuta encontrada", emptyHint: "Atualize ou altere a busca.", listeningCaption: "Suas portas de escuta", kill: "Encerrar", forceKill: "Forçar encerramento", refresh: "Atualizar", terminateFormat: "Encerrar %@?", terminateMessageFormat: "Isso fecha a porta %d encerrando o PID %d.", hubDescription: "Visualize portas de escuta ativas e encerre os processos que as utilizam")
    static let tr = PortManagerFeatureStrings(title: "Port Yöneticisi", filter: "Port, işlem veya PID ile filtrele", openFormat: "%d açık", empty: "Dinleyen port bulunamadı", emptyHint: "Yenilemeyi veya aramanızı değiştirmeyi deneyin.", listeningCaption: "Kullanıcınızın dinleyen portları", kill: "Sonlandır", forceKill: "Zorla sonlandır", refresh: "Yenile", terminateFormat: "%@ sonlandırılsın mı?", terminateMessageFormat: "Bu işlem PID %2$d sonlandırılarak %1$d portunu kapatır.", hubDescription: "Etkin dinleyen portları görüntüleyin ve bunları kullanan işlemleri sonlandırın")
    static let ru = PortManagerFeatureStrings(title: "Диспетчер портов", filter: "Фильтр по порту, процессу или PID", openFormat: "%d открыто", empty: "Прослушиваемые порты не найдены", emptyHint: "Обновите список или измените поиск.", listeningCaption: "Ваши прослушиваемые порты", kill: "Завершить", forceKill: "Завершить принудительно", refresh: "Обновить", terminateFormat: "Завершить %@?", terminateMessageFormat: "Порт %d будет закрыт завершением PID %d.", hubDescription: "Просмотр активных прослушиваемых портов и завершение использующих их процессов")
    static let es = PortManagerFeatureStrings(title: "Gestor de puertos", filter: "Filtrar por puerto, proceso o PID", openFormat: "%d abiertos", empty: "No se encontraron puertos de escucha", emptyHint: "Actualiza o cambia la búsqueda.", listeningCaption: "Tus puertos de escucha", kill: "Cerrar", forceKill: "Forzar cierre", refresh: "Actualizar", terminateFormat: "¿Cerrar %@?", terminateMessageFormat: "Esto cierra el puerto %d terminando el PID %d.", hubDescription: "Consulta los puertos de escucha activos y finaliza los procesos que los utilizan")
    static let de = PortManagerFeatureStrings(title: "Portverwaltung", filter: "Nach Port, Prozess oder PID filtern", openFormat: "%d offen", empty: "Keine lauschenden Ports gefunden", emptyHint: "Aktualisiere die Liste oder ändere die Suche.", listeningCaption: "Deine lauschenden Ports", kill: "Beenden", forceKill: "Sofort beenden", refresh: "Aktualisieren", terminateFormat: "%@ beenden?", terminateMessageFormat: "Port %d wird durch Beenden von PID %d geschlossen.", hubDescription: "Aktive lauschende Ports anzeigen und die zugehörigen Prozesse beenden")
    static let fr = PortManagerFeatureStrings(title: "Gestionnaire de ports", filter: "Filtrer par port, processus ou PID", openFormat: "%d ouverts", empty: "Aucun port en écoute trouvé", emptyHint: "Actualisez ou modifiez votre recherche.", listeningCaption: "Vos ports en écoute", kill: "Quitter", forceKill: "Forcer l’arrêt", refresh: "Actualiser", terminateFormat: "Arrêter %@ ?", terminateMessageFormat: "Le port %d sera fermé en arrêtant le PID %d.", hubDescription: "Affichez les ports en écoute actifs et arrêtez les processus qui les utilisent")
    static let it = PortManagerFeatureStrings(title: "Gestore porte", filter: "Filtra per porta, processo o PID", openFormat: "%d aperte", empty: "Nessuna porta in ascolto trovata", emptyHint: "Aggiorna o modifica la ricerca.", listeningCaption: "Le tue porte in ascolto", kill: "Termina", forceKill: "Termina forzatamente", refresh: "Aggiorna", terminateFormat: "Terminare %@?", terminateMessageFormat: "La porta %d verrà chiusa terminando il PID %d.", hubDescription: "Visualizza le porte in ascolto attive e termina i processi che le utilizzano")
    static let ja = PortManagerFeatureStrings(title: "ポートマネージャー", filter: "ポート、プロセス、PIDで絞り込む", openFormat: "%d 個が開いています", empty: "待ち受けポートがありません", emptyHint: "更新するか検索条件を変更してください。", listeningCaption: "あなたの待ち受けポート", kill: "終了", forceKill: "強制終了", refresh: "更新", terminateFormat: "%@を終了しますか？", terminateMessageFormat: "PID %2$dを終了してポート%1$dを閉じます。", hubDescription: "アクティブな待機ポートを確認し、それらを使用しているプロセスを終了します")
    static let ko = PortManagerFeatureStrings(title: "포트 관리자", filter: "포트, 프로세스 또는 PID로 필터링", openFormat: "%d개 열림", empty: "수신 대기 중인 포트가 없습니다", emptyHint: "새로 고치거나 검색어를 변경해 보세요.", listeningCaption: "내 수신 대기 포트", kill: "종료", forceKill: "강제 종료", refresh: "새로 고침", terminateFormat: "%@을(를) 종료할까요?", terminateMessageFormat: "PID %2$d을(를) 종료하여 포트 %1$d을(를) 닫습니다.", hubDescription: "활성 수신 대기 포트를 확인하고 이를 사용하는 프로세스를 종료합니다")
    static let zhHans = PortManagerFeatureStrings(title: "端口管理器", filter: "按端口、进程或 PID 筛选", openFormat: "%d 个开放", empty: "未找到监听端口", emptyHint: "尝试刷新或更改搜索条件。", listeningCaption: "您的监听端口", kill: "终止", forceKill: "强制终止", refresh: "刷新", terminateFormat: "要终止 %@ 吗？", terminateMessageFormat: "终止 PID %2$d 将关闭端口 %1$d。", hubDescription: "查看活动的监听端口并终止使用它们的进程")
    static let zhTW = PortManagerFeatureStrings(title: "連接埠管理器", filter: "依連接埠、程序或 PID 篩選", openFormat: "%d 個開啟", empty: "找不到監聽中的連接埠", emptyHint: "請嘗試重新整理或變更搜尋條件。", listeningCaption: "您的監聽中連接埠", kill: "結束", forceKill: "強制結束", refresh: "重新整理", terminateFormat: "要結束 %@ 嗎？", terminateMessageFormat: "結束 PID %2$d 將關閉連接埠 %1$d。", hubDescription: "檢視使用中的監聽連接埠並結束使用它們的程序")
    static let zhHK = PortManagerFeatureStrings(title: "連接埠管理員", filter: "按連接埠、程序或 PID 篩選", openFormat: "%d 個開啟", empty: "找不到監聽中的連接埠", emptyHint: "請嘗試重新整理或變更搜尋條件。", listeningCaption: "您的監聽中連接埠", kill: "結束", forceKill: "強制結束", refresh: "重新整理", terminateFormat: "要結束 %@ 嗎？", terminateMessageFormat: "結束 PID %2$d 會關閉連接埠 %1$d。", hubDescription: "檢視使用中的監聽連接埠並結束使用它們的程序")
}
