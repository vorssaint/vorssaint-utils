// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NetworkStatusFeatureStrings {
    /// Names the Network card block, its panel toggle and its hidden row.
    let title: String
    let history: String
    /// Whether the Mac has a usable network interface at all.
    let status: String
    /// The interface the default route uses, by name.
    let interface: String
    let physicalAddress: String
    let internet: String
    let publicIP: String
    let jitter: String
    let up: String
    let down: String
    let check: String
    /// Says what the check sends, how often and where.
    let checkCaption: String
    let interval: String
    let host: String
    let hostInvalid: String
    let showPublicIP: String
    /// Says whom the public address lookup asks and when.
    let publicIPCaption: String
    let turnOn: String
}

extension FeatureStrings {
    static func networkStatus(_ language: AppLanguage) -> NetworkStatusFeatureStrings {
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

extension NetworkStatusFeatureStrings {
    static let enUS = NetworkStatusFeatureStrings(
        title: "Connection status",
        history: "Connectivity history",
        status: "Status",
        interface: "Interface",
        physicalAddress: "Physical address",
        internet: "Internet connection",
        publicIP: "Public IP",
        jitter: "Jitter",
        up: "Up",
        down: "Down",
        check: "Check internet connection",
        checkCaption: "Sends a small request to the check host at every interval to chart connectivity, latency and jitter. Leave the host empty to use Cloudflare.",
        interval: "Check interval",
        host: "Check host",
        hostInvalid: "Not a valid host name or address. The check uses Cloudflare instead.",
        showPublicIP: "Show public IP",
        publicIPCaption: "Asks Cloudflare which address your connection uses when the panel opens and when the network changes.",
        turnOn: "Turn on"
    )

    static let ptBR = NetworkStatusFeatureStrings(
        title: "Status da conexão",
        history: "Histórico de conectividade",
        status: "Status",
        interface: "Interface",
        physicalAddress: "Endereço físico",
        internet: "Conexão com a internet",
        publicIP: "IP público",
        jitter: "Jitter",
        up: "Ativa",
        down: "Inativa",
        check: "Verificar conexão com a internet",
        checkCaption: "Envia uma pequena solicitação ao host da verificação a cada intervalo para registrar conectividade, latência e jitter. Deixe o host vazio para usar a Cloudflare.",
        interval: "Intervalo da verificação",
        host: "Host da verificação",
        hostInvalid: "Nome de host ou endereço inválido. A verificação usa a Cloudflare.",
        showPublicIP: "Mostrar IP público",
        publicIPCaption: "Pergunta à Cloudflare qual endereço sua conexão usa quando o painel abre e quando a rede muda.",
        turnOn: "Ativar"
    )

    static let tr = NetworkStatusFeatureStrings(
        title: "Bağlantı durumu",
        history: "Bağlantı geçmişi",
        status: "Durum",
        interface: "Arayüz",
        physicalAddress: "Fiziksel adres",
        internet: "İnternet bağlantısı",
        publicIP: "Genel IP",
        jitter: "Jitter",
        up: "Bağlı",
        down: "Bağlı değil",
        check: "İnternet bağlantısını denetle",
        checkCaption: "Bağlantıyı, gecikmeyi ve jitter’ı izlemek için her aralıkta denetim sunucusuna küçük bir istek gönderir. Cloudflare’i kullanmak için sunucuyu boş bırakın.",
        interval: "Denetim aralığı",
        host: "Denetim sunucusu",
        hostInvalid: "Geçerli bir sunucu adı veya adresi değil. Denetim bunun yerine Cloudflare’i kullanır.",
        showPublicIP: "Genel IP’yi göster",
        publicIPCaption: "Panel açıldığında ve ağ değiştiğinde bağlantınızın kullandığı adresi Cloudflare’e sorar.",
        turnOn: "Aç"
    )

    static let ru = NetworkStatusFeatureStrings(
        title: "Состояние подключения",
        history: "История подключения",
        status: "Статус",
        interface: "Интерфейс",
        physicalAddress: "Физический адрес",
        internet: "Подключение к интернету",
        publicIP: "Публичный IP",
        jitter: "Джиттер",
        up: "Активно",
        down: "Нет связи",
        check: "Проверять подключение к интернету",
        checkCaption: "С выбранным интервалом отправляет небольшой запрос на хост проверки, чтобы отслеживать связь, задержку и джиттер. Оставьте хост пустым, чтобы использовать Cloudflare.",
        interval: "Интервал проверки",
        host: "Хост проверки",
        hostInvalid: "Недопустимое имя хоста или адрес. Вместо него проверяется Cloudflare.",
        showPublicIP: "Показывать публичный IP",
        publicIPCaption: "Запрашивает у Cloudflare адрес вашего подключения при открытии панели и смене сети.",
        turnOn: "Включить"
    )

    static let es = NetworkStatusFeatureStrings(
        title: "Estado de la conexión",
        history: "Historial de conectividad",
        status: "Estado",
        interface: "Interfaz",
        physicalAddress: "Dirección física",
        internet: "Conexión a internet",
        publicIP: "IP pública",
        jitter: "Jitter",
        up: "Activa",
        down: "Inactiva",
        check: "Comprobar la conexión a internet",
        checkCaption: "Envía una pequeña solicitud al host de comprobación en cada intervalo para registrar la conectividad, la latencia y el jitter. Deja el host vacío para usar Cloudflare.",
        interval: "Intervalo de comprobación",
        host: "Host de comprobación",
        hostInvalid: "No es un nombre de host ni una dirección válidos. Se comprueba Cloudflare en su lugar.",
        showPublicIP: "Mostrar IP pública",
        publicIPCaption: "Pregunta a Cloudflare qué dirección usa tu conexión al abrir el panel y cuando cambia la red.",
        turnOn: "Activar"
    )

    static let sk = NetworkStatusFeatureStrings(
        title: "Stav pripojenia",
        history: "História pripojenia",
        status: "Stav",
        interface: "Rozhranie",
        physicalAddress: "Fyzická adresa",
        internet: "Pripojenie k internetu",
        publicIP: "Verejná IP",
        jitter: "Jitter",
        up: "Aktívne",
        down: "Neaktívne",
        check: "Kontrolovať pripojenie k internetu",
        checkCaption: "V každom intervale odošle malú požiadavku hostiteľovi kontroly na sledovanie pripojenia, latencie a jitteru. Ak chcete použiť Cloudflare, nechajte hostiteľa prázdneho.",
        interval: "Interval kontroly",
        host: "Hostiteľ kontroly",
        hostInvalid: "Neplatný názov hostiteľa alebo adresa. Namiesto toho sa kontroluje Cloudflare.",
        showPublicIP: "Zobraziť verejnú IP",
        publicIPCaption: "Pri otvorení panela a pri zmene siete sa opýta Cloudflare, akú adresu používa vaše pripojenie.",
        turnOn: "Zapnúť"
    )

    static let de = NetworkStatusFeatureStrings(
        title: "Verbindungsstatus",
        history: "Verbindungsverlauf",
        status: "Status",
        interface: "Schnittstelle",
        physicalAddress: "Physische Adresse",
        internet: "Internetverbindung",
        publicIP: "Öffentliche IP",
        jitter: "Jitter",
        up: "Aktiv",
        down: "Inaktiv",
        check: "Internetverbindung prüfen",
        checkCaption: "Sendet in jedem Intervall eine kleine Anfrage an den Prüfhost, um Verbindung, Latenz und Jitter aufzuzeichnen. Lass den Host leer, um Cloudflare zu verwenden.",
        interval: "Prüfintervall",
        host: "Prüfhost",
        hostInvalid: "Kein gültiger Hostname und keine gültige Adresse. Stattdessen wird Cloudflare geprüft.",
        showPublicIP: "Öffentliche IP anzeigen",
        publicIPCaption: "Fragt Cloudflare beim Öffnen des Panels und bei einem Netzwerkwechsel, welche Adresse deine Verbindung nutzt.",
        turnOn: "Einschalten"
    )

    static let fr = NetworkStatusFeatureStrings(
        title: "État de la connexion",
        history: "Historique de connectivité",
        status: "Statut",
        interface: "Interface",
        physicalAddress: "Adresse physique",
        internet: "Connexion Internet",
        publicIP: "IP publique",
        jitter: "Gigue",
        up: "Active",
        down: "Inactive",
        check: "Vérifier la connexion Internet",
        checkCaption: "Envoie une petite requête à l’hôte de vérification à chaque intervalle pour suivre la connectivité, la latence et la gigue. Laissez l’hôte vide pour utiliser Cloudflare.",
        interval: "Intervalle de vérification",
        host: "Hôte de vérification",
        hostInvalid: "Nom d’hôte ou adresse non valide. Cloudflare est vérifié à la place.",
        showPublicIP: "Afficher l’IP publique",
        publicIPCaption: "Demande à Cloudflare l’adresse utilisée par votre connexion à l’ouverture du panneau et lors d’un changement de réseau.",
        turnOn: "Activer"
    )

    static let it = NetworkStatusFeatureStrings(
        title: "Stato della connessione",
        history: "Cronologia della connettività",
        status: "Stato",
        interface: "Interfaccia",
        physicalAddress: "Indirizzo fisico",
        internet: "Connessione a Internet",
        publicIP: "IP pubblico",
        jitter: "Jitter",
        up: "Attiva",
        down: "Inattiva",
        check: "Controlla la connessione a Internet",
        checkCaption: "Invia una piccola richiesta all’host di controllo a ogni intervallo per registrare connettività, latenza e jitter. Lascia vuoto l’host per usare Cloudflare.",
        interval: "Intervallo di controllo",
        host: "Host di controllo",
        hostInvalid: "Nome host o indirizzo non valido. Viene controllato Cloudflare.",
        showPublicIP: "Mostra IP pubblico",
        publicIPCaption: "Chiede a Cloudflare quale indirizzo usa la connessione quando si apre il pannello e quando cambia la rete.",
        turnOn: "Abilita"
    )

    static let ja = NetworkStatusFeatureStrings(
        title: "接続状況",
        history: "接続履歴",
        status: "ステータス",
        interface: "インターフェイス",
        physicalAddress: "物理アドレス",
        internet: "インターネット接続",
        publicIP: "パブリックIP",
        jitter: "ジッター",
        up: "接続",
        down: "切断",
        check: "インターネット接続を確認",
        checkCaption: "接続状況、レイテンシ、ジッターを記録するため、間隔ごとに確認先ホストへ小さなリクエストを送信します。Cloudflareを使う場合はホストを空欄にします。",
        interval: "確認間隔",
        host: "確認先ホスト",
        hostInvalid: "有効なホスト名またはアドレスではありません。代わりにCloudflareを確認します。",
        showPublicIP: "パブリックIPを表示",
        publicIPCaption: "パネルを開いたときとネットワークが変わったときに、接続が使用しているアドレスをCloudflareに問い合わせます。",
        turnOn: "オンにする"
    )

    static let ko = NetworkStatusFeatureStrings(
        title: "연결 상태",
        history: "연결 기록",
        status: "상태",
        interface: "인터페이스",
        physicalAddress: "물리적 주소",
        internet: "인터넷 연결",
        publicIP: "공인 IP",
        jitter: "지터",
        up: "연결됨",
        down: "끊김",
        check: "인터넷 연결 확인",
        checkCaption: "연결, 지연 시간, 지터를 기록하기 위해 간격마다 확인 호스트에 작은 요청을 보냅니다. Cloudflare를 사용하려면 호스트를 비워 두세요.",
        interval: "확인 간격",
        host: "확인 호스트",
        hostInvalid: "유효한 호스트 이름이나 주소가 아닙니다. 대신 Cloudflare를 확인합니다.",
        showPublicIP: "공인 IP 표시",
        publicIPCaption: "패널을 열 때와 네트워크가 바뀔 때 연결에서 사용하는 주소를 Cloudflare에 확인합니다.",
        turnOn: "켜기"
    )

    static let zhHans = NetworkStatusFeatureStrings(
        title: "连接状态",
        history: "连接历史",
        status: "状态",
        interface: "接口",
        physicalAddress: "物理地址",
        internet: "互联网连接",
        publicIP: "公网 IP",
        jitter: "抖动",
        up: "已连接",
        down: "已断开",
        check: "检查互联网连接",
        checkCaption: "按所选间隔向检查主机发送一个小请求，以记录连接状况、延迟和抖动。将主机留空即使用 Cloudflare。",
        interval: "检查间隔",
        host: "检查主机",
        hostInvalid: "不是有效的主机名或地址，将改为检查 Cloudflare。",
        showPublicIP: "显示公网 IP",
        publicIPCaption: "在打开面板和网络变化时，向 Cloudflare 查询你的连接所使用的地址。",
        turnOn: "开启"
    )

    static let zhTW = NetworkStatusFeatureStrings(
        title: "連線狀態",
        history: "連線紀錄",
        status: "狀態",
        interface: "介面",
        physicalAddress: "實體位址",
        internet: "網際網路連線",
        publicIP: "公用 IP",
        jitter: "抖動",
        up: "已連線",
        down: "已中斷",
        check: "檢查網際網路連線",
        checkCaption: "依所選間隔向檢查主機傳送一個小型請求，以記錄連線狀況、延遲和抖動。將主機留空即使用 Cloudflare。",
        interval: "檢查間隔",
        host: "檢查主機",
        hostInvalid: "不是有效的主機名稱或位址，將改為檢查 Cloudflare。",
        showPublicIP: "顯示公用 IP",
        publicIPCaption: "在開啟面板及網路變更時，向 Cloudflare 查詢你的連線所使用的位址。",
        turnOn: "開啟"
    )

    static let zhHK = NetworkStatusFeatureStrings(
        title: "連線狀態",
        history: "連線記錄",
        status: "狀態",
        interface: "介面",
        physicalAddress: "實體地址",
        internet: "互聯網連線",
        publicIP: "公共 IP",
        jitter: "抖動",
        up: "已連線",
        down: "已中斷",
        check: "檢查互聯網連線",
        checkCaption: "依所選間隔向檢查主機傳送一個小型請求，以記錄連線狀況、延遲和抖動。將主機留空即使用 Cloudflare。",
        interval: "檢查間隔",
        host: "檢查主機",
        hostInvalid: "不是有效的主機名稱或地址，將改為檢查 Cloudflare。",
        showPublicIP: "顯示公共 IP",
        publicIPCaption: "在開啟面板及網絡變更時，向 Cloudflare 查詢你的連線所使用的地址。",
        turnOn: "開啟"
    )

    static let uk = NetworkStatusFeatureStrings(
        title: "Стан підключення",
        history: "Історія підключення",
        status: "Статус",
        interface: "Інтерфейс",
        physicalAddress: "Фізична адреса",
        internet: "Підключення до інтернету",
        publicIP: "Публічна IP",
        jitter: "Джитер",
        up: "Активне",
        down: "Немає зв’язку",
        check: "Перевіряти підключення до інтернету",
        checkCaption: "З вибраним інтервалом надсилає невеликий запит на хост перевірки, щоб відстежувати зв’язок, затримку та джитер. Залиште хост порожнім, щоб використовувати Cloudflare.",
        interval: "Інтервал перевірки",
        host: "Хост перевірки",
        hostInvalid: "Недійсне ім’я хоста або адреса. Натомість перевіряється Cloudflare.",
        showPublicIP: "Показувати публічну IP",
        publicIPCaption: "Запитує в Cloudflare адресу вашого підключення під час відкриття панелі та зміни мережі.",
        turnOn: "Увімкнути"
    )
}
