// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AutoClickerFeatureStrings {
    let title: String
    let caption: String
    let modeSection: String
    let modeSingle: String
    let modeMacro: String
    let buttonSection: String
    let buttonLeft: String
    let buttonRight: String
    let buttonMiddle: String
    let targetSection: String
    let targetCursor: String
    let targetFixedPoint: String
    let pickLocationAction: String
    let coordinatesFormat: String
    let pickerSingleHint: String
    let pickerMacroHint: String
    let pickerUndoAction: String
    let pickerDoneAction: String
    let pickerCancelAction: String
    let intervalSection: String
    let intervalMsFormat: String
    let rateCpsFormat: String
    let repeatLimitSection: String
    let repeatLimitInfinite: String
    let repeatLimitCountFormat: String
    let shortcutSection: String
    let macroSection: String
    let macroNewAction: String
    let macroDeleteAction: String
    let macroNamePlaceholder: String
    let macroRepeatSection: String
    let macroRecordStepsAction: String
    let macroClearStepsAction: String
    let macroEmptyHint: String
    let macroStepDelayLabel: String
    let macroSingleClick: String
    let macroDoubleClick: String
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
        modeSection: "Mode",
        modeSingle: "Single Click",
        modeMacro: "Click Macro",
        buttonSection: "Mouse Button",
        buttonLeft: "Left",
        buttonRight: "Right",
        buttonMiddle: "Middle",
        targetSection: "Click Location",
        targetCursor: "Cursor",
        targetFixedPoint: "Fixed Position",
        pickLocationAction: "Pick on Screen",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Click anywhere to set target · ESC to cancel",
        pickerMacroHint: "Click to add steps · ESC or Done to finish",
        pickerUndoAction: "Undo",
        pickerDoneAction: "Done",
        pickerCancelAction: "Cancel",
        intervalSection: "Interval",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clicks/s",
        repeatLimitSection: "Repeat Limit",
        repeatLimitInfinite: "Infinite",
        repeatLimitCountFormat: "%d clicks",
        shortcutSection: "Shortcut",
        macroSection: "Macro",
        macroNewAction: "New Macro",
        macroDeleteAction: "Delete",
        macroNamePlaceholder: "Macro name",
        macroRepeatSection: "Repeat Cycles",
        macroRecordStepsAction: "Record on Screen",
        macroClearStepsAction: "Clear Steps",
        macroEmptyHint: "No steps yet. Click \"Record on Screen\" to pick click locations.",
        macroStepDelayLabel: "Wait (s)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Modo",
        modeSingle: "Clique Único",
        modeMacro: "Macro de Cliques",
        buttonSection: "Botão do Mouse",
        buttonLeft: "Esquerdo",
        buttonRight: "Direito",
        buttonMiddle: "Central",
        targetSection: "Local do Clique",
        targetCursor: "Cursor",
        targetFixedPoint: "Posição Fixa",
        pickLocationAction: "Selecionar na Tela",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Clique em qualquer lugar para definir · ESC para cancelar",
        pickerMacroHint: "Clique para adicionar passos · ESC ou Concluir",
        pickerUndoAction: "Desfazer",
        pickerDoneAction: "Concluir",
        pickerCancelAction: "Cancelar",
        intervalSection: "Intervalo",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d cliques/s",
        repeatLimitSection: "Limite de Repetição",
        repeatLimitInfinite: "Infinito",
        repeatLimitCountFormat: "%d cliques",
        shortcutSection: "Atalho",
        macroSection: "Macro",
        macroNewAction: "Nova Macro",
        macroDeleteAction: "Excluir",
        macroNamePlaceholder: "Nome da macro",
        macroRepeatSection: "Repetições",
        macroRecordStepsAction: "Gravar na Tela",
        macroClearStepsAction: "Limpar Passos",
        macroEmptyHint: "Nenhum passo ainda. Clique em \"Gravar na Tela\" para selecionar os cliques.",
        macroStepDelayLabel: "Aguardar (s)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Mod",
        modeSingle: "Tek Tıklama",
        modeMacro: "Tıklama Makrosu",
        buttonSection: "Fare Düğmesi",
        buttonLeft: "Sol",
        buttonRight: "Sağ",
        buttonMiddle: "Orta",
        targetSection: "Tıklama Konumu",
        targetCursor: "İmleç",
        targetFixedPoint: "Sabit Konum",
        pickLocationAction: "Ekrandan Seç",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Hedef seçmek için tıklayın · İptal için ESC",
        pickerMacroHint: "Adım eklemek için tıklayın · Bitirmek için ESC veya Bitti",
        pickerUndoAction: "Geri Al",
        pickerDoneAction: "Bitti",
        pickerCancelAction: "İptal",
        intervalSection: "Aralık",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d tık/s",
        repeatLimitSection: "Tekrar Sınırı",
        repeatLimitInfinite: "Sınırsız",
        repeatLimitCountFormat: "%d tık",
        shortcutSection: "Kısayol",
        macroSection: "Makro",
        macroNewAction: "Yeni Makro",
        macroDeleteAction: "Sil",
        macroNamePlaceholder: "Makro adı",
        macroRepeatSection: "Tekrar Döngüsü",
        macroRecordStepsAction: "Ekranda Kaydet",
        macroClearStepsAction: "Adımları Temizle",
        macroEmptyHint: "Henüz adım yok. Konum seçmek için \"Ekranda Kaydet\"e tıklayın.",
        macroStepDelayLabel: "Gecikme (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Режим",
        modeSingle: "Одиночный клик",
        modeMacro: "Макрос кликов",
        buttonSection: "Кнопка мыши",
        buttonLeft: "Левая",
        buttonRight: "Правая",
        buttonMiddle: "Средняя",
        targetSection: "Место клика",
        targetCursor: "Курсор",
        targetFixedPoint: "Точка на экране",
        pickLocationAction: "Выбрать на экране",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Кликните для выбора точки · ESC для отмены",
        pickerMacroHint: "Кликайте для добавления шагов · ESC или Готово",
        pickerUndoAction: "Отменить",
        pickerDoneAction: "Готово",
        pickerCancelAction: "Отмена",
        intervalSection: "Интервал",
        intervalMsFormat: "%d мс",
        rateCpsFormat: "%d кликов/с",
        repeatLimitSection: "Лимит повторений",
        repeatLimitInfinite: "Бесконечно",
        repeatLimitCountFormat: "%d кликов",
        shortcutSection: "Горячая клавиша",
        macroSection: "Макрос",
        macroNewAction: "Новый макрос",
        macroDeleteAction: "Удалить",
        macroNamePlaceholder: "Название макроса",
        macroRepeatSection: "Повторы цикла",
        macroRecordStepsAction: "Записать на экране",
        macroClearStepsAction: "Очистить шаги",
        macroEmptyHint: "Шагов пока нет. Нажмите «Записать на экране».",
        macroStepDelayLabel: "Задержка (мс)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Modo",
        modeSingle: "Clic Único",
        modeMacro: "Macro de Clics",
        buttonSection: "Botón del Ratón",
        buttonLeft: "Izquierdo",
        buttonRight: "Derecho",
        buttonMiddle: "Central",
        targetSection: "Ubicación del Clic",
        targetCursor: "Cursor",
        targetFixedPoint: "Posición Fija",
        pickLocationAction: "Elegir en Pantalla",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Haz clic para elegir el punto · ESC para cancelar",
        pickerMacroHint: "Haz clic para añadir pasos · ESC o Listo",
        pickerUndoAction: "Deshacer",
        pickerDoneAction: "Listo",
        pickerCancelAction: "Cancelar",
        intervalSection: "Intervalo",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clics/s",
        repeatLimitSection: "Límite de Repetición",
        repeatLimitInfinite: "Infinito",
        repeatLimitCountFormat: "%d clics",
        shortcutSection: "Atajo",
        macroSection: "Macro",
        macroNewAction: "Nueva Macro",
        macroDeleteAction: "Eliminar",
        macroNamePlaceholder: "Nombre de la macro",
        macroRepeatSection: "Repeticiones",
        macroRecordStepsAction: "Grabar en Pantalla",
        macroClearStepsAction: "Limpiar Pasos",
        macroEmptyHint: "Sin pasos aún. Pulsa \"Grabar en Pantalla\" para añadir clics.",
        macroStepDelayLabel: "Espera (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Režim",
        modeSingle: "Jeden klik",
        modeMacro: "Makro klikov",
        buttonSection: "Tlačidlo myši",
        buttonLeft: "Ľavé",
        buttonRight: "Pravé",
        buttonMiddle: "Stredné",
        targetSection: "Miesto kliknutia",
        targetCursor: "Kurzor",
        targetFixedPoint: "Pevná pozícia",
        pickLocationAction: "Vybrať na obrazovke",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Kliknite pre výber cieľa · ESC pre zrušenie",
        pickerMacroHint: "Klikaním pridajte kroky · ESC alebo Hotovo",
        pickerUndoAction: "Späť",
        pickerDoneAction: "Hotovo",
        pickerCancelAction: "Zrušiť",
        intervalSection: "Interval",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d klikov/s",
        repeatLimitSection: "Limit opakovania",
        repeatLimitInfinite: "Neobmedzené",
        repeatLimitCountFormat: "%d klikov",
        shortcutSection: "Klávesová skratka",
        macroSection: "Makro",
        macroNewAction: "Nové makro",
        macroDeleteAction: "Odstrániť",
        macroNamePlaceholder: "Názov makra",
        macroRepeatSection: "Opakovanie cyklu",
        macroRecordStepsAction: "Nahrať na obrazovke",
        macroClearStepsAction: "Vymazať kroky",
        macroEmptyHint: "Zatiaľ žiadne kroky. Kliknite na \"Nahrať na obrazovke\".",
        macroStepDelayLabel: "Oneskorenie (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Modus",
        modeSingle: "Einzelklick",
        modeMacro: "Klick-Makro",
        buttonSection: "Maustaste",
        buttonLeft: "Links",
        buttonRight: "Rechts",
        buttonMiddle: "Mittel",
        targetSection: "Klickposition",
        targetCursor: "Mauszeiger",
        targetFixedPoint: "Feste Position",
        pickLocationAction: "Auf Bildschirm wählen",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Zum Festlegen klicken · ESC zum Abbrechen",
        pickerMacroHint: "Klicken für Schritte · ESC oder Fertig",
        pickerUndoAction: "Rückgängig",
        pickerDoneAction: "Fertig",
        pickerCancelAction: "Abbrechen",
        intervalSection: "Intervall",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d Klicks/s",
        repeatLimitSection: "Wiederholungsgrenze",
        repeatLimitInfinite: "Unbegrenzt",
        repeatLimitCountFormat: "%d Klicks",
        shortcutSection: "Tastenkürzel",
        macroSection: "Makro",
        macroNewAction: "Neues Makro",
        macroDeleteAction: "Löschen",
        macroNamePlaceholder: "Makroname",
        macroRepeatSection: "Wiederholungen",
        macroRecordStepsAction: "Auf Bildschirm aufnehmen",
        macroClearStepsAction: "Schritte löschen",
        macroEmptyHint: "Noch keine Schritte. Klicken Sie auf \"Auf Bildschirm aufnehmen\".",
        macroStepDelayLabel: "Pause (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Mode",
        modeSingle: "Clic Unique",
        modeMacro: "Macro de Clics",
        buttonSection: "Bouton de la Souris",
        buttonLeft: "Gauche",
        buttonRight: "Droite",
        buttonMiddle: "Moyen",
        targetSection: "Emplacement du Clic",
        targetCursor: "Curseur",
        targetFixedPoint: "Position Fixe",
        pickLocationAction: "Choisir à l'écran",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Cliquez pour définir la cible · ÉCH pour annuler",
        pickerMacroHint: "Cliquez pour ajouter des étapes · ÉCH ou Terminé",
        pickerUndoAction: "Annuler",
        pickerDoneAction: "Terminé",
        pickerCancelAction: "Fermer",
        intervalSection: "Intervalle",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clics/s",
        repeatLimitSection: "Limite de Répétition",
        repeatLimitInfinite: "Infini",
        repeatLimitCountFormat: "%d clics",
        shortcutSection: "Raccourci",
        macroSection: "Macro",
        macroNewAction: "Nouvelle Macro",
        macroDeleteAction: "Supprimer",
        macroNamePlaceholder: "Nom de la macro",
        macroRepeatSection: "Répétitions",
        macroRecordStepsAction: "Enregistrer à l'écran",
        macroClearStepsAction: "Effacer les étapes",
        macroEmptyHint: "Aucune étape. Cliquez sur \"Enregistrer à l'écran\".",
        macroStepDelayLabel: "Délai (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Modalità",
        modeSingle: "Clic Singolo",
        modeMacro: "Macro di Clic",
        buttonSection: "Pulsante del Mouse",
        buttonLeft: "Sinistro",
        buttonRight: "Destro",
        buttonMiddle: "Centrale",
        targetSection: "Posizione del Clic",
        targetCursor: "Cursore",
        targetFixedPoint: "Posizione Fissa",
        pickLocationAction: "Scegli sullo Schermo",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Fai clic per impostare · ESC per annullare",
        pickerMacroHint: "Fai clic per aggiungere passi · ESC o Fine",
        pickerUndoAction: "Annulla",
        pickerDoneAction: "Fine",
        pickerCancelAction: "Chiudi",
        intervalSection: "Intervallo",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d clic/s",
        repeatLimitSection: "Limite di Ripetizione",
        repeatLimitInfinite: "Infinito",
        repeatLimitCountFormat: "%d clic",
        shortcutSection: "Scorciatoia",
        macroSection: "Macro",
        macroNewAction: "Nuova Macro",
        macroDeleteAction: "Elimina",
        macroNamePlaceholder: "Nome macro",
        macroRepeatSection: "Cicli di Ripetizione",
        macroRecordStepsAction: "Registra sullo Schermo",
        macroClearStepsAction: "Cancella Passi",
        macroEmptyHint: "Nessun passo. Fai clic su \"Registra sullo Schermo\".",
        macroStepDelayLabel: "Ritardo (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "モード",
        modeSingle: "単一クリック",
        modeMacro: "クリックマクロ",
        buttonSection: "マウスボタン",
        buttonLeft: "左",
        buttonRight: "右",
        buttonMiddle: "中",
        targetSection: "クリック位置",
        targetCursor: "カーソル",
        targetFixedPoint: "固定座標",
        pickLocationAction: "画面で選択",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "クリックで位置を指定 · ESCでキャンセル",
        pickerMacroHint: "クリックで手順を追加 · ESCまたは完了",
        pickerUndoAction: "戻す",
        pickerDoneAction: "完了",
        pickerCancelAction: "キャンセル",
        intervalSection: "間隔",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d クリック/秒",
        repeatLimitSection: "繰り返し上限",
        repeatLimitInfinite: "無制限",
        repeatLimitCountFormat: "%d クリック",
        shortcutSection: "ショートカット",
        macroSection: "マクロ",
        macroNewAction: "新規マクロ",
        macroDeleteAction: "削除",
        macroNamePlaceholder: "マクロ名",
        macroRepeatSection: "繰り返し回数",
        macroRecordStepsAction: "画面で記録",
        macroClearStepsAction: "手順をクリア",
        macroEmptyHint: "手順がありません。「画面で記録」をクリックしてください。",
        macroStepDelayLabel: "待機 (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "모드",
        modeSingle: "단일 클릭",
        modeMacro: "클릭 매크로",
        buttonSection: "마우스 버튼",
        buttonLeft: "왼쪽",
        buttonRight: "오른쪽",
        buttonMiddle: "가운데",
        targetSection: "클릭 위치",
        targetCursor: "커서",
        targetFixedPoint: "고정 위치",
        pickLocationAction: "화면에서 선택",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "위치를 클릭하세요 · 취소하려면 ESC",
        pickerMacroHint: "클릭하여 단계 추가 · ESC 또는 완료",
        pickerUndoAction: "실행 취소",
        pickerDoneAction: "완료",
        pickerCancelAction: "취소",
        intervalSection: "간격",
        intervalMsFormat: "%d ms",
        rateCpsFormat: "%d 클릭/초",
        repeatLimitSection: "반복 제한",
        repeatLimitInfinite: "무제한",
        repeatLimitCountFormat: "%d 클릭",
        shortcutSection: "단축키",
        macroSection: "매크로",
        macroNewAction: "새 매크로",
        macroDeleteAction: "삭제",
        macroNamePlaceholder: "매크로 이름",
        macroRepeatSection: "반복 횟수",
        macroRecordStepsAction: "화면에서 기록",
        macroClearStepsAction: "단계 지우기",
        macroEmptyHint: "단계가 없습니다. \"화면에서 기록\"을 클릭하세요.",
        macroStepDelayLabel: "지연 (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "模式",
        modeSingle: "单点点击",
        modeMacro: "点击宏",
        buttonSection: "鼠标按钮",
        buttonLeft: "左键",
        buttonRight: "右键",
        buttonMiddle: "中键",
        targetSection: "点击位置",
        targetCursor: "光标",
        targetFixedPoint: "固定位置",
        pickLocationAction: "在屏幕上选择",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "点击任意位置设置目标 · 按 ESC 取消",
        pickerMacroHint: "点击添加步骤 · 按 ESC 或点击完成",
        pickerUndoAction: "撤销",
        pickerDoneAction: "完成",
        pickerCancelAction: "取消",
        intervalSection: "间隔",
        intervalMsFormat: "%d 毫秒",
        rateCpsFormat: "%d 次/秒",
        repeatLimitSection: "重复限制",
        repeatLimitInfinite: "无限",
        repeatLimitCountFormat: "%d 次",
        shortcutSection: "快捷键",
        macroSection: "宏",
        macroNewAction: "新建宏",
        macroDeleteAction: "删除",
        macroNamePlaceholder: "宏名称",
        macroRepeatSection: "循环次数",
        macroRecordStepsAction: "屏幕录制",
        macroClearStepsAction: "清空步骤",
        macroEmptyHint: "暂无步骤。点击“屏幕录制”选择点击位置。",
        macroStepDelayLabel: "延迟 (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "模式",
        modeSingle: "單點點擊",
        modeMacro: "點擊巨集",
        buttonSection: "滑鼠按鈕",
        buttonLeft: "左鍵",
        buttonRight: "右鍵",
        buttonMiddle: "中鍵",
        targetSection: "點擊位置",
        targetCursor: "游標",
        targetFixedPoint: "固定位置",
        pickLocationAction: "在螢幕上選擇",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "點擊任意位置設定目標 · 按 ESC 取消",
        pickerMacroHint: "點擊新增步驟 · 按 ESC 或點擊完成",
        pickerUndoAction: "復原",
        pickerDoneAction: "完成",
        pickerCancelAction: "取消",
        intervalSection: "間隔",
        intervalMsFormat: "%d 毫秒",
        rateCpsFormat: "%d 次/秒",
        repeatLimitSection: "重複限制",
        repeatLimitInfinite: "無限",
        repeatLimitCountFormat: "%d 次",
        shortcutSection: "快捷鍵",
        macroSection: "巨集",
        macroNewAction: "新增巨集",
        macroDeleteAction: "刪除",
        macroNamePlaceholder: "巨集名稱",
        macroRepeatSection: "循環次數",
        macroRecordStepsAction: "螢幕錄製",
        macroClearStepsAction: "清除步驟",
        macroEmptyHint: "尚無步驟。點擊「螢幕錄製」選擇點擊位置。",
        macroStepDelayLabel: "延遲 (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "模式",
        modeSingle: "單點點擊",
        modeMacro: "點擊巨集",
        buttonSection: "滑鼠掣",
        buttonLeft: "左掣",
        buttonRight: "右掣",
        buttonMiddle: "中掣",
        targetSection: "點擊位置",
        targetCursor: "游標",
        targetFixedPoint: "固定位置",
        pickLocationAction: "喺螢幕揀選",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "點擊任何位置設定目標 · 按 ESC 取消",
        pickerMacroHint: "點擊加入步驟 · 按 ESC 或點擊完成",
        pickerUndoAction: "復原",
        pickerDoneAction: "完成",
        pickerCancelAction: "取消",
        intervalSection: "間隔",
        intervalMsFormat: "%d 毫秒",
        rateCpsFormat: "%d 次/秒",
        repeatLimitSection: "重複限制",
        repeatLimitInfinite: "無限",
        repeatLimitCountFormat: "%d 次",
        shortcutSection: "快捷鍵",
        macroSection: "巨集",
        macroNewAction: "新增巨集",
        macroDeleteAction: "刪除",
        macroNamePlaceholder: "巨集名稱",
        macroRepeatSection: "循環次數",
        macroRecordStepsAction: "螢幕錄製",
        macroClearStepsAction: "清除步驟",
        macroEmptyHint: "未有步驟。點擊「螢幕錄製」揀選點擊位置。",
        macroStepDelayLabel: "延遲 (ms)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
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
        modeSection: "Режим",
        modeSingle: "Один клік",
        modeMacro: "Макрос кліків",
        buttonSection: "Кнопка миші",
        buttonLeft: "Ліва",
        buttonRight: "Права",
        buttonMiddle: "Середня",
        targetSection: "Місце кліку",
        targetCursor: "Курсор",
        targetFixedPoint: "Фіксована точка",
        pickLocationAction: "Обрати на екрані",
        coordinatesFormat: "X: %d, Y: %d",
        pickerSingleHint: "Клікніть для вибору точки · ESC для скасування",
        pickerMacroHint: "Клікайте для додавання кроків · ESC або Готово",
        pickerUndoAction: "Скасувати",
        pickerDoneAction: "Готово",
        pickerCancelAction: "Відміна",
        intervalSection: "Інтервал",
        intervalMsFormat: "%d мс",
        rateCpsFormat: "%d кліків/с",
        repeatLimitSection: "Ліміт повторень",
        repeatLimitInfinite: "Безлімітно",
        repeatLimitCountFormat: "%d кліків",
        shortcutSection: "Гаряча клавіша",
        macroSection: "Макрос",
        macroNewAction: "Новий макрос",
        macroDeleteAction: "Видалити",
        macroNamePlaceholder: "Назва макросу",
        macroRepeatSection: "Цикли повторення",
        macroRecordStepsAction: "Записати на екрані",
        macroClearStepsAction: "Очистити кроки",
        macroEmptyHint: "Кроків ще немає. Натисніть «Записати на екрані».",
        macroStepDelayLabel: "Затримка (мс)",
        macroSingleClick: "1×",
        macroDoubleClick: "2×",
        startAction: "Старт",
        stopAction: "Стоп",
        statusRunning: "Працює",
        statusIdle: "Очікування",
        emergencyStopHint: "Натисніть ESC для негайної зупинки"
    )
}
