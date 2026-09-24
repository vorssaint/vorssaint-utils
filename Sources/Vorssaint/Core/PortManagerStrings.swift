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
    let loadFailed: String
    let refresh: String
    let terminateFormat: String
    let terminateMessageFormat: String
    let hubDescription: String
    let allInterfaces: String
    let allInterfacesHelp: String
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
        }
    }
}

extension PortManagerFeatureStrings {
    static let enUS = PortManagerFeatureStrings(title: "Port Manager", filter: "Filter by port, process, or PID", openFormat: "%d open", empty: "No listening ports found", emptyHint: "Try refreshing or changing your search.", listeningCaption: "Your listening ports", kill: "Kill", forceKill: "Force Kill", loadFailed: "Could not read listening ports. Try refreshing.", refresh: "Refresh", terminateFormat: "Terminate %@?", terminateMessageFormat: "This closes port %d by terminating PID %d.", hubDescription: "View active listening ports and, with Kill Process installed, terminate the processes using them", allInterfaces: "All interfaces", allInterfacesHelp: "Listening on every network interface, so other devices on the network may be able to connect.")
    static let ptBR = PortManagerFeatureStrings(title: "Gerenciador de portas", filter: "Filtrar por porta, processo ou PID", openFormat: "%d abertas", empty: "Nenhuma porta de escuta encontrada", emptyHint: "Atualize ou altere a busca.", listeningCaption: "Suas portas de escuta", kill: "Encerrar", forceKill: "Forçar encerramento", loadFailed: "Não foi possível consultar as portas. Tente atualizar.", refresh: "Atualizar", terminateFormat: "Encerrar %@?", terminateMessageFormat: "Isso fecha a porta %d encerrando o PID %d.", hubDescription: "Visualize portas de escuta ativas e, com Encerrar Processo instalado, encerre os processos que as utilizam", allInterfaces: "Todas as interfaces", allInterfacesHelp: "Escutando em todas as interfaces de rede, então outros dispositivos na rede podem conseguir se conectar.")
    static let tr = PortManagerFeatureStrings(title: "Port Yöneticisi", filter: "Port, işlem veya PID ile filtrele", openFormat: "%d açık", empty: "Dinleyen port bulunamadı", emptyHint: "Yenilemeyi veya aramanızı değiştirmeyi deneyin.", listeningCaption: "Kullanıcınızın dinleyen portları", kill: "Sonlandır", forceKill: "Zorla sonlandır", loadFailed: "Dinleyen portlar okunamadı. Yenilemeyi deneyin.", refresh: "Yenile", terminateFormat: "%@ sonlandırılsın mı?", terminateMessageFormat: "Bu işlem PID %2$d sonlandırılarak %1$d portunu kapatır.", hubDescription: "Etkin dinleyen portları görüntüleyin ve İşlemi Sonlandır kuruluysa bunları kullanan işlemleri sonlandırın", allInterfaces: "Tüm arayüzler", allInterfacesHelp: "Tüm ağ arayüzlerinde dinliyor, bu yüzden ağdaki diğer cihazlar bağlanabilir.")
    static let ru = PortManagerFeatureStrings(title: "Диспетчер портов", filter: "Фильтр по порту, процессу или PID", openFormat: "%d открыто", empty: "Прослушиваемые порты не найдены", emptyHint: "Обновите список или измените поиск.", listeningCaption: "Ваши прослушиваемые порты", kill: "Завершить", forceKill: "Завершить принудительно", loadFailed: "Не удалось прочитать список портов. Попробуйте обновить.", refresh: "Обновить", terminateFormat: "Завершить %@?", terminateMessageFormat: "Порт %d будет закрыт завершением PID %d.", hubDescription: "Просмотр активных прослушиваемых портов и, если установлен «Завершить процесс», завершение использующих их процессов", allInterfaces: "Все интерфейсы", allInterfacesHelp: "Прослушивает все сетевые интерфейсы, поэтому другие устройства в сети могут подключиться.")
    static let es = PortManagerFeatureStrings(title: "Gestor de puertos", filter: "Filtrar por puerto, proceso o PID", openFormat: "%d abiertos", empty: "No se encontraron puertos de escucha", emptyHint: "Actualiza o cambia la búsqueda.", listeningCaption: "Tus puertos de escucha", kill: "Cerrar", forceKill: "Forzar cierre", loadFailed: "No se pudieron consultar los puertos. Intenta actualizar.", refresh: "Actualizar", terminateFormat: "¿Cerrar %@?", terminateMessageFormat: "Esto cierra el puerto %d terminando el PID %d.", hubDescription: "Consulta los puertos de escucha activos y, con Finalizar Proceso instalado, finaliza los procesos que los utilizan", allInterfaces: "Todas las interfaces", allInterfacesHelp: "Escucha en todas las interfaces de red, así que otros dispositivos de la red podrían conectarse.")
    static let de = PortManagerFeatureStrings(title: "Portverwaltung", filter: "Nach Port, Prozess oder PID filtern", openFormat: "%d offen", empty: "Keine lauschenden Ports gefunden", emptyHint: "Aktualisiere die Liste oder ändere die Suche.", listeningCaption: "Deine lauschenden Ports", kill: "Beenden", forceKill: "Sofort beenden", loadFailed: "Die Ports konnten nicht abgefragt werden. Versuche es erneut.", refresh: "Aktualisieren", terminateFormat: "%@ beenden?", terminateMessageFormat: "Port %d wird durch Beenden von PID %d geschlossen.", hubDescription: "Aktive lauschende Ports anzeigen und, wenn Prozess beenden installiert ist, die zugehörigen Prozesse beenden", allInterfaces: "Alle Schnittstellen", allInterfacesHelp: "Lauscht auf allen Netzwerkschnittstellen, daher können sich andere Geräte im Netzwerk möglicherweise verbinden.")
    static let fr = PortManagerFeatureStrings(title: "Gestionnaire de ports", filter: "Filtrer par port, processus ou PID", openFormat: "%d ouverts", empty: "Aucun port en écoute trouvé", emptyHint: "Actualisez ou modifiez votre recherche.", listeningCaption: "Vos ports en écoute", kill: "Quitter", forceKill: "Forcer l’arrêt", loadFailed: "Impossible de consulter les ports. Essayez d’actualiser.", refresh: "Actualiser", terminateFormat: "Arrêter %@ ?", terminateMessageFormat: "Le port %d sera fermé en arrêtant le PID %d.", hubDescription: "Affichez les ports en écoute actifs et, avec Forcer à quitter installé, arrêtez les processus qui les utilisent", allInterfaces: "Toutes les interfaces", allInterfacesHelp: "En écoute sur toutes les interfaces réseau, d’autres appareils du réseau peuvent donc s’y connecter.")
    static let it = PortManagerFeatureStrings(title: "Gestore porte", filter: "Filtra per porta, processo o PID", openFormat: "%d aperte", empty: "Nessuna porta in ascolto trovata", emptyHint: "Aggiorna o modifica la ricerca.", listeningCaption: "Le tue porte in ascolto", kill: "Termina", forceKill: "Termina forzatamente", loadFailed: "Impossibile leggere le porte in ascolto. Prova ad aggiornare.", refresh: "Aggiorna", terminateFormat: "Terminare %@?", terminateMessageFormat: "La porta %d verrà chiusa terminando il PID %d.", hubDescription: "Visualizza le porte in ascolto attive e, con Termina Processo installato, termina i processi che le utilizzano", allInterfaces: "Tutte le interfacce", allInterfacesHelp: "In ascolto su tutte le interfacce di rete, quindi altri dispositivi della rete potrebbero connettersi.")
    static let ja = PortManagerFeatureStrings(title: "ポートマネージャー", filter: "ポート、プロセス、PIDで絞り込む", openFormat: "%d 個が開いています", empty: "待ち受けポートがありません", emptyHint: "更新するか検索条件を変更してください。", listeningCaption: "あなたの待ち受けポート", kill: "終了", forceKill: "強制終了", loadFailed: "待ち受けポートを取得できませんでした。更新してください。", refresh: "更新", terminateFormat: "%@を終了しますか？", terminateMessageFormat: "PID %2$dを終了してポート%1$dを閉じます。", hubDescription: "アクティブな待機ポートを確認し、「プロセスを強制終了」がインストールされていれば、それらを使用しているプロセスを終了します", allInterfaces: "すべてのインターフェイス", allInterfacesHelp: "すべてのネットワークインターフェイスで待ち受けているため、同じネットワーク上の他のデバイスから接続できる可能性があります。")
    static let ko = PortManagerFeatureStrings(title: "포트 관리자", filter: "포트, 프로세스 또는 PID로 필터링", openFormat: "%d개 열림", empty: "수신 대기 중인 포트가 없습니다", emptyHint: "새로 고치거나 검색어를 변경해 보세요.", listeningCaption: "내 수신 대기 포트", kill: "종료", forceKill: "강제 종료", loadFailed: "수신 대기 포트를 확인할 수 없습니다. 새로 고쳐 보세요.", refresh: "새로 고침", terminateFormat: "%@을(를) 종료할까요?", terminateMessageFormat: "PID %2$d을(를) 종료하여 포트 %1$d을(를) 닫습니다.", hubDescription: "활성 수신 대기 포트를 확인하고, 프로세스 종료가 설치되어 있으면 이를 사용하는 프로세스를 종료합니다", allInterfaces: "모든 인터페이스", allInterfacesHelp: "모든 네트워크 인터페이스에서 수신 대기 중이므로 같은 네트워크의 다른 기기가 연결할 수 있습니다.")
    static let zhHans = PortManagerFeatureStrings(title: "端口管理器", filter: "按端口、进程或 PID 筛选", openFormat: "%d 个开放", empty: "未找到监听端口", emptyHint: "尝试刷新或更改搜索条件。", listeningCaption: "您的监听端口", kill: "终止", forceKill: "强制终止", loadFailed: "无法读取监听端口。请尝试刷新。", refresh: "刷新", terminateFormat: "要终止 %@ 吗？", terminateMessageFormat: "终止 PID %2$d 将关闭端口 %1$d。", hubDescription: "查看活动的监听端口，并在已安装“结束进程”时终止使用它们的进程", allInterfaces: "所有接口", allInterfacesHelp: "正在所有网络接口上监听，同一网络中的其他设备可能可以连接。")
    static let zhTW = PortManagerFeatureStrings(title: "連接埠管理器", filter: "依連接埠、程序或 PID 篩選", openFormat: "%d 個開啟", empty: "找不到監聽中的連接埠", emptyHint: "請嘗試重新整理或變更搜尋條件。", listeningCaption: "您的監聽中連接埠", kill: "結束", forceKill: "強制結束", loadFailed: "無法讀取監聽中的連接埠。請嘗試重新整理。", refresh: "重新整理", terminateFormat: "要結束 %@ 嗎？", terminateMessageFormat: "結束 PID %2$d 將關閉連接埠 %1$d。", hubDescription: "檢視使用中的監聽連接埠，並在已安裝「結束處理程序」時結束使用它們的程序", allInterfaces: "所有介面", allInterfacesHelp: "正在所有網路介面上監聽，同一網路中的其他裝置可能可以連線。")
    static let zhHK = PortManagerFeatureStrings(title: "連接埠管理員", filter: "按連接埠、程序或 PID 篩選", openFormat: "%d 個開啟", empty: "找不到監聽中的連接埠", emptyHint: "請嘗試重新整理或變更搜尋條件。", listeningCaption: "您的監聽中連接埠", kill: "結束", forceKill: "強制結束", loadFailed: "無法讀取監聽中的連接埠。請嘗試重新整理。", refresh: "重新整理", terminateFormat: "要結束 %@ 嗎？", terminateMessageFormat: "結束 PID %2$d 會關閉連接埠 %1$d。", hubDescription: "檢視使用中的監聽連接埠，並在已安裝「結束處理程序」時結束使用它們的程序", allInterfaces: "所有介面", allInterfacesHelp: "正在所有網絡介面上監聽，同一網絡中的其他裝置可能可以連線。")
}
