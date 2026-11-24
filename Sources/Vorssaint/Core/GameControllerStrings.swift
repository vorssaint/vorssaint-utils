// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Game controller panel strings.
struct GameControllerFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelDescription: String
    let emptyTitle: String
    let emptyHint: String
    let batteryLabel: String
    let batteryNotReported: String
    let stateCharging: String
    let stateDischarging: String
    let stateFull: String
    let timeToFull: String
    let timeRemaining: String
    let estimating: String
    let connectedFor: String
    let connectedForLowerBoundHelp: String
    let connectionLabel: String
    let typeLabel: String
    let firmwareLabel: String
    let featuresLabel: String
    let featureHaptics: String
    let featureLightBar: String
    let featureMotion: String
    let featureAdaptiveTriggers: String
    let featureTouchpad: String
}

extension FeatureStrings {
    static func gameController(_ language: AppLanguage) -> GameControllerFeatureStrings {
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
}

extension GameControllerFeatureStrings {
    static let enUS = GameControllerFeatureStrings(
        pageTitle: "Game controller",
        hubDescription: "See a connected game controller’s battery, charge time and firmware",
        panelDescription: "See a connected game controller’s battery, charge time and firmware.",
        emptyTitle: "No controller connected",
        emptyHint: "Connect a controller over Bluetooth or a cable and it shows up here.",
        batteryLabel: "Battery",
        batteryNotReported: "Not reported",
        stateCharging: "Charging",
        stateDischarging: "On battery",
        stateFull: "Fully charged",
        timeToFull: "Time to full",
        timeRemaining: "Time remaining",
        estimating: "Estimating…",
        connectedFor: "Connected for",
        connectedForLowerBoundHelp: "At least this long: the controller was already connected when Vorssaint started.",
        connectionLabel: "Connection",
        typeLabel: "Type",
        firmwareLabel: "Firmware",
        featuresLabel: "Features",
        featureHaptics: "Haptics",
        featureLightBar: "Light bar",
        featureMotion: "Motion sensors",
        featureAdaptiveTriggers: "Adaptive triggers",
        featureTouchpad: "Touchpad")

    static let ptBR = GameControllerFeatureStrings(
        pageTitle: "Controle de jogo",
        hubDescription: "Veja bateria, tempo de carga e firmware de um controle de jogo conectado",
        panelDescription: "Veja bateria, tempo de carga e firmware de um controle de jogo conectado.",
        emptyTitle: "Nenhum controle conectado",
        emptyHint: "Conecte um controle por Bluetooth ou cabo e ele aparece aqui.",
        batteryLabel: "Bateria",
        batteryNotReported: "Não informada",
        stateCharging: "Carregando",
        stateDischarging: "Na bateria",
        stateFull: "Carga completa",
        timeToFull: "Tempo até carregar",
        timeRemaining: "Tempo restante",
        estimating: "Estimando…",
        connectedFor: "Conectado há",
        connectedForLowerBoundHelp: "No mínimo isso: o controle já estava conectado quando o Vorssaint iniciou.",
        connectionLabel: "Conexão",
        typeLabel: "Tipo",
        firmwareLabel: "Firmware",
        featuresLabel: "Recursos",
        featureHaptics: "Vibração háptica",
        featureLightBar: "Barra de luz",
        featureMotion: "Sensores de movimento",
        featureAdaptiveTriggers: "Gatilhos adaptativos",
        featureTouchpad: "Touchpad")

    static let tr = GameControllerFeatureStrings(
        pageTitle: "Oyun kumandası",
        hubDescription: "Bağlı bir oyun kumandasının pilini, şarj süresini ve donanım yazılımını görün",
        panelDescription: "Bağlı bir oyun kumandasının pilini, şarj süresini ve donanım yazılımını görün.",
        emptyTitle: "Bağlı kumanda yok",
        emptyHint: "Bir kumandayı Bluetooth veya kabloyla bağlayın, burada görünür.",
        batteryLabel: "Pil",
        batteryNotReported: "Bildirilmiyor",
        stateCharging: "Şarj oluyor",
        stateDischarging: "Pilde",
        stateFull: "Tamamen şarj oldu",
        timeToFull: "Dolmasına kalan süre",
        timeRemaining: "Kalan süre",
        estimating: "Tahmin ediliyor…",
        connectedFor: "Bağlantı süresi",
        connectedForLowerBoundHelp: "En az bu kadar: kumanda Vorssaint açıldığında zaten bağlıydı.",
        connectionLabel: "Bağlantı",
        typeLabel: "Tür",
        firmwareLabel: "Donanım yazılımı",
        featuresLabel: "Özellikler",
        featureHaptics: "Haptik geri bildirim",
        featureLightBar: "Işık çubuğu",
        featureMotion: "Hareket sensörleri",
        featureAdaptiveTriggers: "Uyarlanabilir tetikler",
        featureTouchpad: "Dokunmatik yüzey")

    static let ru = GameControllerFeatureStrings(
        pageTitle: "Игровой контроллер",
        hubDescription: "Заряд, время зарядки и прошивка подключённого игрового контроллера",
        panelDescription: "Заряд, время зарядки и прошивка подключённого игрового контроллера.",
        emptyTitle: "Контроллер не подключён",
        emptyHint: "Подключите контроллер по Bluetooth или кабелю, и он появится здесь.",
        batteryLabel: "Батарея",
        batteryNotReported: "Не сообщается",
        stateCharging: "Заряжается",
        stateDischarging: "От батареи",
        stateFull: "Полностью заряжен",
        timeToFull: "До полной зарядки",
        timeRemaining: "Осталось",
        estimating: "Оценка…",
        connectedFor: "Подключён",
        connectedForLowerBoundHelp: "Не менее этого времени: контроллер уже был подключён при запуске Vorssaint.",
        connectionLabel: "Подключение",
        typeLabel: "Тип",
        firmwareLabel: "Прошивка",
        featuresLabel: "Возможности",
        featureHaptics: "Тактильная отдача",
        featureLightBar: "Световая панель",
        featureMotion: "Датчики движения",
        featureAdaptiveTriggers: "Адаптивные триггеры",
        featureTouchpad: "Тачпад")

    static let es = GameControllerFeatureStrings(
        pageTitle: "Mando de juegos",
        hubDescription: "Consulta la batería, el tiempo de carga y el firmware de un mando conectado",
        panelDescription: "Consulta la batería, el tiempo de carga y el firmware de un mando conectado.",
        emptyTitle: "Ningún mando conectado",
        emptyHint: "Conecta un mando por Bluetooth o cable y aparecerá aquí.",
        batteryLabel: "Batería",
        batteryNotReported: "No informada",
        stateCharging: "Cargando",
        stateDischarging: "Con batería",
        stateFull: "Carga completa",
        timeToFull: "Tiempo hasta la carga completa",
        timeRemaining: "Tiempo restante",
        estimating: "Calculando…",
        connectedFor: "Conectado desde hace",
        connectedForLowerBoundHelp: "Al menos este tiempo: el mando ya estaba conectado cuando se inició Vorssaint.",
        connectionLabel: "Conexión",
        typeLabel: "Tipo",
        firmwareLabel: "Firmware",
        featuresLabel: "Funciones",
        featureHaptics: "Respuesta háptica",
        featureLightBar: "Barra de luz",
        featureMotion: "Sensores de movimiento",
        featureAdaptiveTriggers: "Gatillos adaptativos",
        featureTouchpad: "Panel táctil")

    static let sk = GameControllerFeatureStrings(
        pageTitle: "Herný ovládač",
        hubDescription: "Zobrazte batériu, čas nabíjania a firmvér pripojeného herného ovládača",
        panelDescription: "Zobrazte batériu, čas nabíjania a firmvér pripojeného herného ovládača.",
        emptyTitle: "Nie je pripojený žiadny ovládač",
        emptyHint: "Pripojte ovládač cez Bluetooth alebo kábel a zobrazí sa tu.",
        batteryLabel: "Batéria",
        batteryNotReported: "Nehlásené",
        stateCharging: "Nabíja sa",
        stateDischarging: "Na batériu",
        stateFull: "Plne nabité",
        timeToFull: "Čas do nabitia",
        timeRemaining: "Zostávajúci čas",
        estimating: "Odhaduje sa…",
        connectedFor: "Pripojené už",
        connectedForLowerBoundHelp: "Najmenej toľko: ovládač bol pripojený už pri spustení Vorssaint.",
        connectionLabel: "Pripojenie",
        typeLabel: "Typ",
        firmwareLabel: "Firmvér",
        featuresLabel: "Funkcie",
        featureHaptics: "Haptická odozva",
        featureLightBar: "Svetelný pruh",
        featureMotion: "Snímače pohybu",
        featureAdaptiveTriggers: "Adaptívne spúšte",
        featureTouchpad: "Dotykový panel")

    static let de = GameControllerFeatureStrings(
        pageTitle: "Gamecontroller",
        hubDescription: "Akku, Ladezeit und Firmware eines verbundenen Gamecontrollers ansehen",
        panelDescription: "Akku, Ladezeit und Firmware eines verbundenen Gamecontrollers ansehen.",
        emptyTitle: "Kein Controller verbunden",
        emptyHint: "Verbinde einen Controller per Bluetooth oder Kabel, dann erscheint er hier.",
        batteryLabel: "Akku",
        batteryNotReported: "Nicht gemeldet",
        stateCharging: "Wird geladen",
        stateDischarging: "Im Akkubetrieb",
        stateFull: "Vollständig geladen",
        timeToFull: "Zeit bis voll",
        timeRemaining: "Verbleibende Zeit",
        estimating: "Wird geschätzt…",
        connectedFor: "Verbunden seit",
        connectedForLowerBoundHelp: "Mindestens so lange: Der Controller war beim Start von Vorssaint bereits verbunden.",
        connectionLabel: "Verbindung",
        typeLabel: "Typ",
        firmwareLabel: "Firmware",
        featuresLabel: "Funktionen",
        featureHaptics: "Haptik",
        featureLightBar: "Lichtleiste",
        featureMotion: "Bewegungssensoren",
        featureAdaptiveTriggers: "Adaptive Trigger",
        featureTouchpad: "Touchpad")

    static let fr = GameControllerFeatureStrings(
        pageTitle: "Manette de jeu",
        hubDescription: "Consultez la batterie, le temps de charge et le firmware d’une manette connectée",
        panelDescription: "Consultez la batterie, le temps de charge et le firmware d’une manette connectée.",
        emptyTitle: "Aucune manette connectée",
        emptyHint: "Connectez une manette en Bluetooth ou par câble et elle apparaît ici.",
        batteryLabel: "Batterie",
        batteryNotReported: "Non communiquée",
        stateCharging: "En charge",
        stateDischarging: "Sur batterie",
        stateFull: "Chargée à 100 %",
        timeToFull: "Temps avant charge complète",
        timeRemaining: "Temps restant",
        estimating: "Estimation…",
        connectedFor: "Connectée depuis",
        connectedForLowerBoundHelp: "Au moins ce temps : la manette était déjà connectée au démarrage de Vorssaint.",
        connectionLabel: "Connexion",
        typeLabel: "Type",
        firmwareLabel: "Firmware",
        featuresLabel: "Fonctions",
        featureHaptics: "Retour haptique",
        featureLightBar: "Barre lumineuse",
        featureMotion: "Capteurs de mouvement",
        featureAdaptiveTriggers: "Gâchettes adaptatives",
        featureTouchpad: "Pavé tactile")

    static let it = GameControllerFeatureStrings(
        pageTitle: "Controller di gioco",
        hubDescription: "Controlla batteria, tempo di ricarica e firmware di un controller collegato",
        panelDescription: "Controlla batteria, tempo di ricarica e firmware di un controller collegato.",
        emptyTitle: "Nessun controller collegato",
        emptyHint: "Collega un controller via Bluetooth o cavo e comparirà qui.",
        batteryLabel: "Batteria",
        batteryNotReported: "Non indicata",
        stateCharging: "In carica",
        stateDischarging: "A batteria",
        stateFull: "Carica completa",
        timeToFull: "Tempo alla carica completa",
        timeRemaining: "Tempo rimanente",
        estimating: "Stima in corso…",
        connectedFor: "Collegato da",
        connectedForLowerBoundHelp: "Almeno questo tempo: il controller era già collegato all’avvio di Vorssaint.",
        connectionLabel: "Connessione",
        typeLabel: "Tipo",
        firmwareLabel: "Firmware",
        featuresLabel: "Funzioni",
        featureHaptics: "Feedback aptico",
        featureLightBar: "Barra luminosa",
        featureMotion: "Sensori di movimento",
        featureAdaptiveTriggers: "Grilletti adattivi",
        featureTouchpad: "Touchpad")

    static let ja = GameControllerFeatureStrings(
        pageTitle: "ゲームコントローラ",
        hubDescription: "接続中のゲームコントローラのバッテリー、充電時間、ファームウェアを表示します",
        panelDescription: "接続中のゲームコントローラのバッテリー、充電時間、ファームウェアを表示します。",
        emptyTitle: "コントローラが接続されていません",
        emptyHint: "Bluetoothまたはケーブルでコントローラを接続すると、ここに表示されます。",
        batteryLabel: "バッテリー",
        batteryNotReported: "未報告",
        stateCharging: "充電中",
        stateDischarging: "バッテリー駆動",
        stateFull: "充電完了",
        timeToFull: "満充電まで",
        timeRemaining: "残り時間",
        estimating: "計算中…",
        connectedFor: "接続時間",
        connectedForLowerBoundHelp: "Vorssaintの起動時にすでに接続されていたため、少なくともこの時間です。",
        connectionLabel: "接続",
        typeLabel: "種類",
        firmwareLabel: "ファームウェア",
        featuresLabel: "機能",
        featureHaptics: "触覚フィードバック",
        featureLightBar: "ライトバー",
        featureMotion: "モーションセンサー",
        featureAdaptiveTriggers: "アダプティブトリガー",
        featureTouchpad: "タッチパッド")

    static let ko = GameControllerFeatureStrings(
        pageTitle: "게임 컨트롤러",
        hubDescription: "연결된 게임 컨트롤러의 배터리, 충전 시간, 펌웨어를 확인합니다",
        panelDescription: "연결된 게임 컨트롤러의 배터리, 충전 시간, 펌웨어를 확인합니다.",
        emptyTitle: "연결된 컨트롤러 없음",
        emptyHint: "Bluetooth나 케이블로 컨트롤러를 연결하면 여기에 표시됩니다.",
        batteryLabel: "배터리",
        batteryNotReported: "보고되지 않음",
        stateCharging: "충전 중",
        stateDischarging: "배터리 사용 중",
        stateFull: "충전 완료",
        timeToFull: "완충까지",
        timeRemaining: "남은 시간",
        estimating: "계산 중…",
        connectedFor: "연결 시간",
        connectedForLowerBoundHelp: "최소 이 시간: Vorssaint 시작 시 컨트롤러가 이미 연결되어 있었습니다.",
        connectionLabel: "연결",
        typeLabel: "종류",
        firmwareLabel: "펌웨어",
        featuresLabel: "기능",
        featureHaptics: "햅틱",
        featureLightBar: "라이트 바",
        featureMotion: "모션 센서",
        featureAdaptiveTriggers: "적응형 트리거",
        featureTouchpad: "터치패드")

    static let uk = GameControllerFeatureStrings(
        pageTitle: "Ігровий контролер",
        hubDescription: "Заряд, час зарядки та прошивка підключеного ігрового контролера",
        panelDescription: "Заряд, час зарядки та прошивка підключеного ігрового контролера.",
        emptyTitle: "Контролер не підключено",
        emptyHint: "Підключіть контролер через Bluetooth або кабель, і він з’явиться тут.",
        batteryLabel: "Батарея",
        batteryNotReported: "Не повідомляється",
        stateCharging: "Заряджається",
        stateDischarging: "Від батареї",
        stateFull: "Повністю заряджено",
        timeToFull: "До повної зарядки",
        timeRemaining: "Залишилося",
        estimating: "Оцінювання…",
        connectedFor: "Підключено",
        connectedForLowerBoundHelp: "Не менше цього часу: контролер уже був підключений під час запуску Vorssaint.",
        connectionLabel: "Підключення",
        typeLabel: "Тип",
        firmwareLabel: "Прошивка",
        featuresLabel: "Можливості",
        featureHaptics: "Тактильний відгук",
        featureLightBar: "Світлова смуга",
        featureMotion: "Датчики руху",
        featureAdaptiveTriggers: "Адаптивні тригери",
        featureTouchpad: "Тачпад")

    static let zhHans = GameControllerFeatureStrings(
        pageTitle: "游戏手柄",
        hubDescription: "查看已连接游戏手柄的电量、充电时间和固件",
        panelDescription: "查看已连接游戏手柄的电量、充电时间和固件。",
        emptyTitle: "未连接手柄",
        emptyHint: "通过蓝牙或数据线连接手柄后，它会显示在这里。",
        batteryLabel: "电量",
        batteryNotReported: "未报告",
        stateCharging: "充电中",
        stateDischarging: "电池供电",
        stateFull: "已充满",
        timeToFull: "充满所需时间",
        timeRemaining: "剩余时间",
        estimating: "正在估算…",
        connectedFor: "已连接时长",
        connectedForLowerBoundHelp: "至少这么久：Vorssaint 启动时手柄已处于连接状态。",
        connectionLabel: "连接方式",
        typeLabel: "类型",
        firmwareLabel: "固件",
        featuresLabel: "功能",
        featureHaptics: "触觉反馈",
        featureLightBar: "灯条",
        featureMotion: "动作传感器",
        featureAdaptiveTriggers: "自适应扳机",
        featureTouchpad: "触控板")

    static let zhTW = GameControllerFeatureStrings(
        pageTitle: "遊戲控制器",
        hubDescription: "查看已連接遊戲控制器的電量、充電時間與韌體",
        panelDescription: "查看已連接遊戲控制器的電量、充電時間與韌體。",
        emptyTitle: "未連接控制器",
        emptyHint: "透過藍牙或傳輸線連接控制器後，會顯示在這裡。",
        batteryLabel: "電量",
        batteryNotReported: "未回報",
        stateCharging: "充電中",
        stateDischarging: "使用電池",
        stateFull: "已充飽",
        timeToFull: "充飽所需時間",
        timeRemaining: "剩餘時間",
        estimating: "估算中…",
        connectedFor: "已連接時間",
        connectedForLowerBoundHelp: "至少這麼久：Vorssaint 啟動時控制器已處於連接狀態。",
        connectionLabel: "連接方式",
        typeLabel: "類型",
        firmwareLabel: "韌體",
        featuresLabel: "功能",
        featureHaptics: "觸覺回饋",
        featureLightBar: "燈條",
        featureMotion: "動態感測器",
        featureAdaptiveTriggers: "自適應扳機",
        featureTouchpad: "觸控板")

    static let zhHK = GameControllerFeatureStrings(
        pageTitle: "遊戲控制器",
        hubDescription: "查看已連接遊戲控制器的電量、充電時間及韌體",
        panelDescription: "查看已連接遊戲控制器的電量、充電時間及韌體。",
        emptyTitle: "未連接控制器",
        emptyHint: "透過藍牙或傳輸線連接控制器後，會顯示在這裡。",
        batteryLabel: "電量",
        batteryNotReported: "未回報",
        stateCharging: "充電中",
        stateDischarging: "使用電池",
        stateFull: "已充滿",
        timeToFull: "充滿所需時間",
        timeRemaining: "剩餘時間",
        estimating: "估算中…",
        connectedFor: "已連接時間",
        connectedForLowerBoundHelp: "至少這麼久：Vorssaint 啟動時控制器已處於連接狀態。",
        connectionLabel: "連接方式",
        typeLabel: "類型",
        firmwareLabel: "韌體",
        featuresLabel: "功能",
        featureHaptics: "觸覺回饋",
        featureLightBar: "燈條",
        featureMotion: "動態感測器",
        featureAdaptiveTriggers: "自適應扳機",
        featureTouchpad: "觸控板")
}
