// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AutoClickerFeatureStrings {
    let title: String
    let caption: String
    let buttonSection: String
    let buttonLeft: String
    let buttonRight: String
    let buttonMiddle: String
    let intervalSection: String
    let intervalMsFormat: String
    let rateCpsFormat: String
    let repeatLimitSection: String
    let repeatLimitInfinite: String
    let repeatLimitCountFormat: String
    let shortcutSection: String
    let startAction: String
    let stopAction: String
    let statusRunning: String
    let statusIdle: String
    let emergencyStopHint: String
}

extension FeatureStrings {
    static func autoClicker(_ language: AppLanguage) -> AutoClickerFeatureStrings {
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

// MARK: - English (US)

extension AutoClickerFeatureStrings {
    static let enUS = AutoClickerFeatureStrings(
        title: "Auto Clicker",
        caption: "Automate mouse clicks at a configurable interval",
        buttonSection: "Mouse Button",
        buttonLeft: "Left",
        buttonRight: "Right",
        buttonMiddle: "Middle",
        intervalSection: "Interval",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clicks/s",
        repeatLimitSection: "Repeat Limit",
        repeatLimitInfinite: "Infinite",
        repeatLimitCountFormat: "%d clicks",
        shortcutSection: "Shortcut",
        startAction: "Start",
        stopAction: "Stop",
        statusRunning: "Running",
        statusIdle: "Idle",
        emergencyStopHint: "Press ESC to stop immediately"
    )
}

// MARK: - Portuguese (Brazil)

extension AutoClickerFeatureStrings {
    static let ptBR = AutoClickerFeatureStrings(
        title: "Clicador Automático",
        caption: "Automatize cliques do mouse em um intervalo configurável",
        buttonSection: "Botão do Mouse",
        buttonLeft: "Esquerdo",
        buttonRight: "Direito",
        buttonMiddle: "Central",
        intervalSection: "Intervalo",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d cliques/s",
        repeatLimitSection: "Limite de Repetição",
        repeatLimitInfinite: "Infinito",
        repeatLimitCountFormat: "%d cliques",
        shortcutSection: "Atalho",
        startAction: "Iniciar",
        stopAction: "Parar",
        statusRunning: "Em execução",
        statusIdle: "Ocioso",
        emergencyStopHint: "Pressione ESC para parar imediatamente"
    )
}

// MARK: - Turkish

extension AutoClickerFeatureStrings {
    static let tr = AutoClickerFeatureStrings(
        title: "Otomatik Tıklayıcı",
        caption: "Yapılandırılabilir aralıklarla fare tıklamalarını otomatikleştirin",
        buttonSection: "Fare Düğmesi",
        buttonLeft: "Sol",
        buttonRight: "Sağ",
        buttonMiddle: "Orta",
        intervalSection: "Aralık",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d tık/s",
        repeatLimitSection: "Tekrar Sınırı",
        repeatLimitInfinite: "Sınırsız",
        repeatLimitCountFormat: "%d tık",
        shortcutSection: "Kısayol",
        startAction: "Başlat",
        stopAction: "Durdur",
        statusRunning: "Çalışıyor",
        statusIdle: "Boşta",
        emergencyStopHint: "Hemen durdurmak için ESC'ye basın"
    )
}

// MARK: - Russian

extension AutoClickerFeatureStrings {
    static let ru = AutoClickerFeatureStrings(
        title: "Автокликер",
        caption: "Автоматизация кликов мыши с настраиваемым интервалом",
        buttonSection: "Кнопка мыши",
        buttonLeft: "Левая",
        buttonRight: "Правая",
        buttonMiddle: "Средняя",
        intervalSection: "Интервал",
        intervalMsFormat: "%d мс",
        rateCpsFormat: "%d кликов/с",
        repeatLimitSection: "Лимит повторений",
        repeatLimitInfinite: "Бесконечно",
        repeatLimitCountFormat: "%d кликов",
        shortcutSection: "Горячая клавиша",
        startAction: "Старт",
        stopAction: "Стоп",
        statusRunning: "Работает",
        statusIdle: "Ожидание",
        emergencyStopHint: "Нажмите ESC для немедленной остановки"
    )
}

// MARK: - Spanish

extension AutoClickerFeatureStrings {
    static let es = AutoClickerFeatureStrings(
        title: "Clic Automático",
        caption: "Automatiza los clics del ratón en un intervalo configurable",
        buttonSection: "Botón del Ratón",
        buttonLeft: "Izquierdo",
        buttonRight: "Derecho",
        buttonMiddle: "Central",
        intervalSection: "Intervalo",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clics/s",
        repeatLimitSection: "Límite de Repetición",
        repeatLimitInfinite: "Infinito",
        repeatLimitCountFormat: "%d clics",
        shortcutSection: "Atajo",
        startAction: "Iniciar",
        stopAction: "Detener",
        statusRunning: "En ejecución",
        statusIdle: "Inactivo",
        emergencyStopHint: "Pulsa ESC para detener inmediatamente"
    )
}

// MARK: - Slovak

extension AutoClickerFeatureStrings {
    static let sk = AutoClickerFeatureStrings(
        title: "Automatický klik",
        caption: "Automatizujte kliky myšou v nastaviteľnom intervale",
        buttonSection: "Tlačidlo myši",
        buttonLeft: "Ľavé",
        buttonRight: "Pravé",
        buttonMiddle: "Stredné",
        intervalSection: "Interval",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d klikov/s",
        repeatLimitSection: "Limit opakovania",
        repeatLimitInfinite: "Neobmedzené",
        repeatLimitCountFormat: "%d klikov",
        shortcutSection: "Klávesová skratka",
        startAction: "Štart",
        stopAction: "Zastav",
        statusRunning: "Beží",
        statusIdle: "Nečinné",
        emergencyStopHint: "Stlačte ESC pre okamžité zastavenie"
    )
}

// MARK: - German

extension AutoClickerFeatureStrings {
    static let de = AutoClickerFeatureStrings(
        title: "Autoklicker",
        caption: "Automatisieren Sie Mausklicks in einem konfigurierbaren Intervall",
        buttonSection: "Maustaste",
        buttonLeft: "Links",
        buttonRight: "Rechts",
        buttonMiddle: "Mittel",
        intervalSection: "Intervall",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d Klicks/s",
        repeatLimitSection: "Wiederholungsgrenze",
        repeatLimitInfinite: "Unbegrenzt",
        repeatLimitCountFormat: "%d Klicks",
        shortcutSection: "Tastenkürzel",
        startAction: "Start",
        stopAction: "Stopp",
        statusRunning: "Läuft",
        statusIdle: "Inaktiv",
        emergencyStopHint: "Drücken Sie ESC zum sofortigen Stoppen"
    )
}

// MARK: - French

extension AutoClickerFeatureStrings {
    static let fr = AutoClickerFeatureStrings(
        title: "Clic Automatique",
        caption: "Automatisez les clics de la souris à un intervalle configurable",
        buttonSection: "Bouton de la Souris",
        buttonLeft: "Gauche",
        buttonRight: "Droite",
        buttonMiddle: "Moyen",
        intervalSection: "Intervalle",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clics/s",
        repeatLimitSection: "Limite de Répétition",
        repeatLimitInfinite: "Infini",
        repeatLimitCountFormat: "%d clics",
        shortcutSection: "Raccourci",
        startAction: "Démarrer",
        stopAction: "Arrêter",
        statusRunning: "En cours",
        statusIdle: "Inactif",
        emergencyStopHint: "Appuyez sur ÉCH pour arrêter immédiatement"
    )
}

// MARK: - Italian

extension AutoClickerFeatureStrings {
    static let it = AutoClickerFeatureStrings(
        title: "Clic Automatico",
        caption: "Automatizza i clic del mouse a un intervallo configurabile",
        buttonSection: "Pulsante del Mouse",
        buttonLeft: "Sinistro",
        buttonRight: "Destro",
        buttonMiddle: "Centrale",
        intervalSection: "Intervallo",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clic/s",
        repeatLimitSection: "Limite di Ripetizione",
        repeatLimitInfinite: "Infinito",
        repeatLimitCountFormat: "%d clic",
        shortcutSection: "Scorciatoia",
        startAction: "Avvia",
        stopAction: "Ferma",
        statusRunning: "In esecuzione",
        statusIdle: "Inattivo",
        emergencyStopHint: "Premi ESC per fermare immediatamente"
    )
}

// MARK: - Japanese

extension AutoClickerFeatureStrings {
    static let ja = AutoClickerFeatureStrings(
        title: "自動クリック",
        caption: "設定可能な間隔でマウスクリックを自動化します",
        buttonSection: "マウスボタン",
        buttonLeft: "左",
        buttonRight: "右",
        buttonMiddle: "中",
        intervalSection: "間隔",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d クリック/秒",
        repeatLimitSection: "繰り返し上限",
        repeatLimitInfinite: "無制限",
        repeatLimitCountFormat: "%d クリック",
        shortcutSection: "ショートカット",
        startAction: "開始",
        stopAction: "停止",
        statusRunning: "実行中",
        statusIdle: "待機中",
        emergencyStopHint: "ESCキーで即座に停止します"
    )
}

// MARK: - Korean

extension AutoClickerFeatureStrings {
    static let ko = AutoClickerFeatureStrings(
        title: "자동 클릭기",
        caption: "설정 가능한 간격으로 마우스 클릭을 자동화합니다",
        buttonSection: "마우스 버튼",
        buttonLeft: "왼쪽",
        buttonRight: "오른쪽",
        buttonMiddle: "가운데",
        intervalSection: "간격",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d 클릭/초",
        repeatLimitSection: "반복 제한",
        repeatLimitInfinite: "무제한",
        repeatLimitCountFormat: "%d 클릭",
        shortcutSection: "단축키",
        startAction: "시작",
        stopAction: "정지",
        statusRunning: "실행 중",
        statusIdle: "대기 중",
        emergencyStopHint: "즉시 정지하려면 ESC를 누르세요"
    )
}

// MARK: - Chinese (Simplified)

extension AutoClickerFeatureStrings {
    static let zhHans = AutoClickerFeatureStrings(
        title: "自动点击器",
        caption: "以可配置的间隔自动执行鼠标点击",
        buttonSection: "鼠标按钮",
        buttonLeft: "左键",
        buttonRight: "右键",
        buttonMiddle: "中键",
        intervalSection: "间隔",
        intervalMsFormat: "%d 毫秒",
        rateCpsFormat: "%d 次/秒",
        repeatLimitSection: "重复限制",
        repeatLimitInfinite: "无限",
        repeatLimitCountFormat: "%d 次",
        shortcutSection: "快捷键",
        startAction: "开始",
        stopAction: "停止",
        statusRunning: "运行中",
        statusIdle: "空闲",
        emergencyStopHint: "按 ESC 立即停止"
    )
}

// MARK: - Chinese (Traditional, Taiwan)

extension AutoClickerFeatureStrings {
    static let zhTW = AutoClickerFeatureStrings(
        title: "自動點擊器",
        caption: "以可設定的間隔自動執行滑鼠點擊",
        buttonSection: "滑鼠按鈕",
        buttonLeft: "左鍵",
        buttonRight: "右鍵",
        buttonMiddle: "中鍵",
        intervalSection: "間隔",
        intervalMsFormat: "%d 毫秒",
        rateCpsFormat: "%d 次/秒",
        repeatLimitSection: "重複限制",
        repeatLimitInfinite: "無限",
        repeatLimitCountFormat: "%d 次",
        shortcutSection: "快捷鍵",
        startAction: "開始",
        stopAction: "停止",
        statusRunning: "執行中",
        statusIdle: "閒置",
        emergencyStopHint: "按 ESC 立即停止"
    )
}

// MARK: - Chinese (Traditional, Hong Kong)

extension AutoClickerFeatureStrings {
    static let zhHK = AutoClickerFeatureStrings(
        title: "自動點擊器",
        caption: "以可設定嘅間隔自動執行滑鼠點擊",
        buttonSection: "滑鼠掣",
        buttonLeft: "左掣",
        buttonRight: "右掣",
        buttonMiddle: "中掣",
        intervalSection: "間隔",
        intervalMsFormat: "%d 毫秒",
        rateCpsFormat: "%d 次/秒",
        repeatLimitSection: "重複限制",
        repeatLimitInfinite: "無限",
        repeatLimitCountFormat: "%d 次",
        shortcutSection: "快捷鍵",
        startAction: "開始",
        stopAction: "停止",
        statusRunning: "執行中",
        statusIdle: "閒置",
        emergencyStopHint: "撳 ESC 即刻停止"
    )
}

// MARK: - Ukrainian

extension AutoClickerFeatureStrings {
    static let uk = AutoClickerFeatureStrings(
        title: "Автоклікер",
        caption: "Автоматизуйте кліки миші з налаштовуваним інтервалом",
        buttonSection: "Кнопка миші",
        buttonLeft: "Ліва",
        buttonRight: "Права",
        buttonMiddle: "Середня",
        intervalSection: "Інтервал",
        intervalMsFormat: "%d мс",
        rateCpsFormat: "%d кліків/с",
        repeatLimitSection: "Ліміт повторень",
        repeatLimitInfinite: "Безлімітно",
        repeatLimitCountFormat: "%d кліків",
        shortcutSection: "Гаряча клавіша",
        startAction: "Старт",
        stopAction: "Стоп",
        statusRunning: "Працює",
        statusIdle: "Очікування",
        emergencyStopHint: "Натисніть ESC для негайної зупинки"
    )
}
