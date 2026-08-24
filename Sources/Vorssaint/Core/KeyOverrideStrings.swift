// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the Key Overrides feature. Same contract as the other FeatureStrings structs.
struct KeyOverrideStrings {
    let pageTitle: String
    let hubDescription: String
    let intro: String
    let enableToggle: String
    let addButton: String
    let commonSetButton: String
    let commonSetCaption: String
    let keyMissionControl: String
    let keySpotlight: String
    let keyDictation: String
    let keyFocus: String
    let keyLaunchpad: String
    let actionRemapOnly: String
    let actionMicMute: String
    let actionPressShortcut: String
    let remapNote: String
    let mappingFailedNote: String
    let shortcutTakenNote: String
    let micMuteNeedsFeature: String
    let removeButton: String
    let emptyState: String
}

extension FeatureStrings {
    static func keyOverrides(_ language: AppLanguage) -> KeyOverrideStrings {
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

extension KeyOverrideStrings {
    static let enUS = KeyOverrideStrings(
        pageTitle: "Key Overrides",
        hubDescription: "Reclaim the F-row keys from macOS",
        intro: "The Mac answers these keys before apps ever see them — F5 starts dictation instead of muting a call. An override remaps the key at the keyboard level and gives it a job of your own.",
        enableToggle: "Enable key overrides",
        addButton: "Add Override",
        commonSetButton: "Add the Common Set",
        commonSetCaption: "The dictation key mutes the microphone; Spotlight and Focus become plain F4 and F6.",
        keyMissionControl: "Mission Control key",
        keySpotlight: "Spotlight key",
        keyDictation: "Dictation key",
        keyFocus: "Focus key",
        keyLaunchpad: "Launchpad key",
        actionRemapOnly: "Act as the plain key",
        actionMicMute: "Mute the microphone",
        actionPressShortcut: "Press a shortcut",
        remapNote: "Special keys are remapped at the keyboard level while their override is on, and restored when it goes off or the app quits.",
        mappingFailedNote: "The keyboard mapping could not be applied. Another remapping tool (such as Karabiner-Elements) may already own one of these keys.",
        shortcutTakenNote: "macOS refused one of these keys; another app may already hold it.",
        micMuteNeedsFeature: "Install Microphone Mute in the Features hub for this action to work.",
        removeButton: "Remove",
        emptyState: "No overrides yet. Add one, or start from the common set."
    )

    static let ptBR = KeyOverrideStrings(
        pageTitle: "Sobrescrever Teclas",
        hubDescription: "Recupere as teclas F do sistema",
        intro: "O Mac responde a essas teclas antes que os apps as vejam — F5 inicia o ditado em vez de silenciar uma chamada. Uma sobrescrição remapeia a tecla no nível do teclado e dá a ela uma função sua.",
        enableToggle: "Ativar sobrescrição de teclas",
        addButton: "Adicionar Sobrescrição",
        commonSetButton: "Adicionar o Conjunto Comum",
        commonSetCaption: "A tecla de ditado silencia o microfone; Spotlight e Foco tornam-se F4 e F6 simples.",
        keyMissionControl: "Tecla Mission Control",
        keySpotlight: "Tecla Spotlight",
        keyDictation: "Tecla de ditado",
        keyFocus: "Tecla de Foco",
        keyLaunchpad: "Tecla Launchpad",
        actionRemapOnly: "Agir como a tecla simples",
        actionMicMute: "Silenciar o microfone",
        actionPressShortcut: "Pressionar um atalho",
        remapNote: "As teclas especiais são remapeadas no nível do teclado enquanto a sobrescrição está ativa, e restauradas quando ela é desativada ou o app é encerrado.",
        mappingFailedNote: "Não foi possível aplicar o mapeamento do teclado. Outra ferramenta de remapeamento (como o Karabiner-Elements) pode já possuir uma dessas teclas.",
        shortcutTakenNote: "O macOS recusou uma dessas teclas; outro app pode já estar usando-a.",
        micMuteNeedsFeature: "Instale Silenciar Microfone na central de Recursos para esta ação funcionar.",
        removeButton: "Remover",
        emptyState: "Nenhuma sobrescrição ainda. Adicione uma ou comece pelo conjunto comum."
    )

    static let tr = KeyOverrideStrings(
        pageTitle: "Tuş Geçersiz Kılma",
        hubDescription: "F tuşlarını sistemden geri alın",
        intro: "Mac bu tuşlara uygulamalar görmeden yanıt verir — F5 bir aramayı susturmak yerine dikteyi başlatır. Geçersiz kılma, tuşu klavye düzeyinde yeniden eşler ve ona sizin seçtiğiniz bir görev verir.",
        enableToggle: "Tuş geçersiz kılmayı etkinleştir",
        addButton: "Geçersiz Kılma Ekle",
        commonSetButton: "Yaygın Kümeyi Ekle",
        commonSetCaption: "Dikte tuşu mikrofonu susturur; Spotlight ve Odak düz F4 ve F6 olur.",
        keyMissionControl: "Mission Control tuşu",
        keySpotlight: "Spotlight tuşu",
        keyDictation: "Dikte tuşu",
        keyFocus: "Odak tuşu",
        keyLaunchpad: "Launchpad tuşu",
        actionRemapOnly: "Düz tuş gibi davran",
        actionMicMute: "Mikrofonu sustur",
        actionPressShortcut: "Bir kısayola bas",
        remapNote: "Özel tuşlar, geçersiz kılmaları açıkken klavye düzeyinde yeniden eşlenir; kapatıldığında veya uygulama çıktığında geri yüklenir.",
        mappingFailedNote: "Klavye eşlemesi uygulanamadı. Başka bir yeniden eşleme aracı (Karabiner-Elements gibi) bu tuşlardan birine zaten sahip olabilir.",
        shortcutTakenNote: "macOS bu tuşlardan birini reddetti; başka bir uygulama onu zaten tutuyor olabilir.",
        micMuteNeedsFeature: "Bu eylemin çalışması için Özellikler merkezinden Mikrofonu Sustur özelliğini yükleyin.",
        removeButton: "Kaldır",
        emptyState: "Henüz geçersiz kılma yok. Bir tane ekleyin veya yaygın kümeyle başlayın."
    )

    static let ru = KeyOverrideStrings(
        pageTitle: "Переназначение клавиш",
        hubDescription: "Верните себе клавиши F-ряда",
        intro: "Mac отвечает на эти клавиши раньше, чем их видят приложения: F5 запускает диктовку вместо отключения микрофона. Переназначение перепрограммирует клавишу на уровне клавиатуры и даёт ей вашу задачу.",
        enableToggle: "Включить переназначение клавиш",
        addButton: "Добавить переназначение",
        commonSetButton: "Добавить типовой набор",
        commonSetCaption: "Клавиша диктовки отключает микрофон; Spotlight и «Фокусирование» становятся обычными F4 и F6.",
        keyMissionControl: "Клавиша Mission Control",
        keySpotlight: "Клавиша Spotlight",
        keyDictation: "Клавиша диктовки",
        keyFocus: "Клавиша «Фокусирование»",
        keyLaunchpad: "Клавиша Launchpad",
        actionRemapOnly: "Работать как обычная клавиша",
        actionMicMute: "Отключить микрофон",
        actionPressShortcut: "Нажать сочетание клавиш",
        remapNote: "Специальные клавиши перепрограммируются на уровне клавиатуры, пока переназначение включено, и восстанавливаются при его выключении или выходе из приложения.",
        mappingFailedNote: "Не удалось применить переназначение клавиатуры. Возможно, другой инструмент (например, Karabiner-Elements) уже владеет одной из этих клавиш.",
        shortcutTakenNote: "macOS отклонила одну из этих клавиш; возможно, её уже использует другое приложение.",
        micMuteNeedsFeature: "Чтобы это действие работало, установите «Отключение микрофона» в центре функций.",
        removeButton: "Удалить",
        emptyState: "Переназначений пока нет. Добавьте одно или начните с типового набора."
    )

    static let es = KeyOverrideStrings(
        pageTitle: "Redefinir Teclas",
        hubDescription: "Recupera las teclas F del sistema",
        intro: "El Mac responde a estas teclas antes de que las apps las vean: F5 inicia el dictado en lugar de silenciar una llamada. Una redefinición reasigna la tecla a nivel del teclado y le da una función tuya.",
        enableToggle: "Activar la redefinición de teclas",
        addButton: "Añadir Redefinición",
        commonSetButton: "Añadir el Conjunto Común",
        commonSetCaption: "La tecla de dictado silencia el micrófono; Spotlight y Concentración pasan a ser F4 y F6 normales.",
        keyMissionControl: "Tecla Mission Control",
        keySpotlight: "Tecla Spotlight",
        keyDictation: "Tecla de dictado",
        keyFocus: "Tecla de Concentración",
        keyLaunchpad: "Tecla Launchpad",
        actionRemapOnly: "Actuar como la tecla normal",
        actionMicMute: "Silenciar el micrófono",
        actionPressShortcut: "Pulsar un atajo",
        remapNote: "Las teclas especiales se reasignan a nivel del teclado mientras su redefinición está activa, y se restauran al desactivarla o al salir de la app.",
        mappingFailedNote: "No se pudo aplicar la asignación del teclado. Otra herramienta de reasignación (como Karabiner-Elements) puede poseer ya una de estas teclas.",
        shortcutTakenNote: "macOS rechazó una de estas teclas; puede que otra app ya la tenga.",
        micMuteNeedsFeature: "Instala Silenciar Micrófono en el centro de Funciones para que esta acción funcione.",
        removeButton: "Eliminar",
        emptyState: "Aún no hay redefiniciones. Añade una o empieza por el conjunto común."
    )

    static let de = KeyOverrideStrings(
        pageTitle: "Tastenbelegung",
        hubDescription: "Hol dir die F-Tasten zurück",
        intro: "Der Mac beantwortet diese Tasten, bevor Apps sie je sehen — F5 startet das Diktat, statt einen Anruf stummzuschalten. Eine Umbelegung ordnet die Taste auf Tastaturebene neu zu und gibt ihr eine eigene Aufgabe.",
        enableToggle: "Tastenbelegung aktivieren",
        addButton: "Umbelegung hinzufügen",
        commonSetButton: "Übliches Set hinzufügen",
        commonSetCaption: "Die Diktiertaste schaltet das Mikrofon stumm; Spotlight und Fokus werden zu einfachem F4 und F6.",
        keyMissionControl: "Mission-Control-Taste",
        keySpotlight: "Spotlight-Taste",
        keyDictation: "Diktiertaste",
        keyFocus: "Fokus-Taste",
        keyLaunchpad: "Launchpad-Taste",
        actionRemapOnly: "Als einfache Taste wirken",
        actionMicMute: "Mikrofon stummschalten",
        actionPressShortcut: "Kurzbefehl drücken",
        remapNote: "Sondertasten werden auf Tastaturebene umbelegt, solange ihre Umbelegung aktiv ist, und beim Abschalten oder Beenden der App wiederhergestellt.",
        mappingFailedNote: "Die Tastaturbelegung konnte nicht angewendet werden. Ein anderes Umbelegungswerkzeug (etwa Karabiner-Elements) besitzt möglicherweise bereits eine dieser Tasten.",
        shortcutTakenNote: "macOS hat eine dieser Tasten abgelehnt; eine andere App hält sie möglicherweise bereits.",
        micMuteNeedsFeature: "Installiere Mikrofon stummschalten im Funktions-Hub, damit diese Aktion funktioniert.",
        removeButton: "Entfernen",
        emptyState: "Noch keine Umbelegungen. Füge eine hinzu oder starte mit dem üblichen Set."
    )

    static let fr = KeyOverrideStrings(
        pageTitle: "Redéfinition des touches",
        hubDescription: "Récupérez les touches F du système",
        intro: "Le Mac répond à ces touches avant que les apps ne les voient — F5 lance la dictée au lieu de couper le micro d'un appel. Une redéfinition réattribue la touche au niveau du clavier et lui confie une tâche à vous.",
        enableToggle: "Activer la redéfinition des touches",
        addButton: "Ajouter une redéfinition",
        commonSetButton: "Ajouter l'ensemble courant",
        commonSetCaption: "La touche de dictée coupe le micro ; Spotlight et Concentration redeviennent F4 et F6 simples.",
        keyMissionControl: "Touche Mission Control",
        keySpotlight: "Touche Spotlight",
        keyDictation: "Touche de dictée",
        keyFocus: "Touche Concentration",
        keyLaunchpad: "Touche Launchpad",
        actionRemapOnly: "Agir comme la touche simple",
        actionMicMute: "Couper le micro",
        actionPressShortcut: "Saisir un raccourci",
        remapNote: "Les touches spéciales sont réattribuées au niveau du clavier tant que leur redéfinition est active, et restaurées quand elle est désactivée ou que l'app quitte.",
        mappingFailedNote: "L'attribution du clavier n'a pas pu être appliquée. Un autre outil de réattribution (comme Karabiner-Elements) possède peut-être déjà l'une de ces touches.",
        shortcutTakenNote: "macOS a refusé l'une de ces touches ; une autre app la détient peut-être déjà.",
        micMuteNeedsFeature: "Installez Couper le micro dans le hub des fonctionnalités pour que cette action fonctionne.",
        removeButton: "Supprimer",
        emptyState: "Aucune redéfinition pour l'instant. Ajoutez-en une ou partez de l'ensemble courant."
    )

    static let it = KeyOverrideStrings(
        pageTitle: "Ridefinizione Tasti",
        hubDescription: "Riprenditi i tasti F dal sistema",
        intro: "Il Mac risponde a questi tasti prima che le app li vedano — F5 avvia la dettatura invece di silenziare una chiamata. Una ridefinizione rimappa il tasto a livello di tastiera e gli affida un compito tuo.",
        enableToggle: "Attiva la ridefinizione dei tasti",
        addButton: "Aggiungi Ridefinizione",
        commonSetButton: "Aggiungi il Set Comune",
        commonSetCaption: "Il tasto dettatura silenzia il microfono; Spotlight e Full Immersion tornano F4 e F6 semplici.",
        keyMissionControl: "Tasto Mission Control",
        keySpotlight: "Tasto Spotlight",
        keyDictation: "Tasto dettatura",
        keyFocus: "Tasto Full Immersion",
        keyLaunchpad: "Tasto Launchpad",
        actionRemapOnly: "Agisci da tasto semplice",
        actionMicMute: "Silenzia il microfono",
        actionPressShortcut: "Premi un'abbreviazione",
        remapNote: "I tasti speciali vengono rimappati a livello di tastiera finché la loro ridefinizione è attiva, e ripristinati quando viene disattivata o l'app esce.",
        mappingFailedNote: "Impossibile applicare la mappatura della tastiera. Un altro strumento di rimappatura (come Karabiner-Elements) potrebbe già possedere uno di questi tasti.",
        shortcutTakenNote: "macOS ha rifiutato uno di questi tasti; un'altra app potrebbe già detenerlo.",
        micMuteNeedsFeature: "Installa Silenzia Microfono nell'hub delle Funzioni perché questa azione funzioni.",
        removeButton: "Rimuovi",
        emptyState: "Ancora nessuna ridefinizione. Aggiungine una o parti dal set comune."
    )

    static let ja = KeyOverrideStrings(
        pageTitle: "キーの上書き",
        hubDescription: "Fキーをシステムから取り戻します",
        intro: "Macはアプリより先にこれらのキーに応答します。F5は通話のミュートではなく音声入力を開始してしまいます。上書きはキーボードレベルでキーを再割り当てし、あなたの決めた役割を与えます。",
        enableToggle: "キーの上書きを有効にする",
        addButton: "上書きを追加",
        commonSetButton: "定番セットを追加",
        commonSetCaption: "音声入力キーはマイクを消音し、SpotlightキーとFocusキーは通常のF4とF6になります。",
        keyMissionControl: "Mission Controlキー",
        keySpotlight: "Spotlightキー",
        keyDictation: "音声入力キー",
        keyFocus: "集中モードキー",
        keyLaunchpad: "Launchpadキー",
        actionRemapOnly: "通常のキーとして動作",
        actionMicMute: "マイクを消音",
        actionPressShortcut: "ショートカットを押す",
        remapNote: "特殊キーは上書きが有効な間だけキーボードレベルで再割り当てされ、無効にするかアプリを終了すると元に戻ります。",
        mappingFailedNote: "キーボードマッピングを適用できませんでした。別の再割り当てツール（Karabiner-Elementsなど）がこれらのキーをすでに使用している可能性があります。",
        shortcutTakenNote: "macOSがこれらのキーの1つを拒否しました。別のアプリがすでに使用している可能性があります。",
        micMuteNeedsFeature: "このアクションを使うには、機能ハブで「マイク消音」をインストールしてください。",
        removeButton: "削除",
        emptyState: "上書きはまだありません。追加するか、定番セットから始めてください。"
    )

    static let ko = KeyOverrideStrings(
        pageTitle: "키 재정의",
        hubDescription: "F열 키를 시스템에서 되찾습니다",
        intro: "Mac은 앱이 보기도 전에 이 키들에 응답합니다. F5는 통화를 음소거하는 대신 받아쓰기를 시작합니다. 재정의는 키보드 수준에서 키를 다시 매핑하여 원하는 역할을 부여합니다.",
        enableToggle: "키 재정의 활성화",
        addButton: "재정의 추가",
        commonSetButton: "기본 세트 추가",
        commonSetCaption: "받아쓰기 키는 마이크를 음소거하고, Spotlight와 집중 모드 키는 일반 F4와 F6이 됩니다.",
        keyMissionControl: "Mission Control 키",
        keySpotlight: "Spotlight 키",
        keyDictation: "받아쓰기 키",
        keyFocus: "집중 모드 키",
        keyLaunchpad: "Launchpad 키",
        actionRemapOnly: "일반 키로 동작",
        actionMicMute: "마이크 음소거",
        actionPressShortcut: "단축키 누르기",
        remapNote: "특수 키는 재정의가 켜져 있는 동안 키보드 수준에서 다시 매핑되며, 끄거나 앱을 종료하면 복원됩니다.",
        mappingFailedNote: "키보드 매핑을 적용할 수 없습니다. 다른 재매핑 도구(예: Karabiner-Elements)가 이미 이 키들 중 하나를 사용 중일 수 있습니다.",
        shortcutTakenNote: "macOS가 이 키들 중 하나를 거부했습니다. 다른 앱이 이미 사용 중일 수 있습니다.",
        micMuteNeedsFeature: "이 동작이 작동하려면 기능 허브에서 마이크 음소거를 설치하세요.",
        removeButton: "제거",
        emptyState: "아직 재정의가 없습니다. 하나 추가하거나 기본 세트로 시작하세요."
    )

    static let zhHans = KeyOverrideStrings(
        pageTitle: "按键重定义",
        hubDescription: "从系统手中拿回 F 键",
        intro: "Mac 会在应用看到这些按键之前先行响应——F5 会启动听写，而不是静音通话。重定义在键盘层面重新映射按键，让它执行你自己的任务。",
        enableToggle: "启用按键重定义",
        addButton: "添加重定义",
        commonSetButton: "添加常用组合",
        commonSetCaption: "听写键静音麦克风；聚焦和专注模式键变回普通的 F4 和 F6。",
        keyMissionControl: "调度中心键",
        keySpotlight: "聚焦键",
        keyDictation: "听写键",
        keyFocus: "专注模式键",
        keyLaunchpad: "启动台键",
        actionRemapOnly: "充当普通按键",
        actionMicMute: "静音麦克风",
        actionPressShortcut: "按下快捷键",
        remapNote: "特殊按键在其重定义开启期间会在键盘层面被重新映射，关闭重定义或退出应用时即恢复原状。",
        mappingFailedNote: "无法应用键盘映射。另一个重映射工具（如 Karabiner-Elements）可能已占用其中某个按键。",
        shortcutTakenNote: "macOS 拒绝了其中一个按键；可能已被其他应用占用。",
        micMuteNeedsFeature: "请在功能中心安装“麦克风静音”，此操作才能生效。",
        removeButton: "移除",
        emptyState: "还没有重定义。添加一个，或从常用组合开始。"
    )

    static let zhTW = KeyOverrideStrings(
        pageTitle: "按鍵重新定義",
        hubDescription: "從系統取回 F 鍵",
        intro: "Mac 會在 App 看到這些按鍵之前先行回應——F5 會啟動聽寫，而不是將通話靜音。重新定義會在鍵盤層級重新對應按鍵，讓它執行你自己的任務。",
        enableToggle: "啟用按鍵重新定義",
        addButton: "加入重新定義",
        commonSetButton: "加入常用組合",
        commonSetCaption: "聽寫鍵靜音麥克風；Spotlight 和專注模式鍵變回普通的 F4 和 F6。",
        keyMissionControl: "指揮中心鍵",
        keySpotlight: "Spotlight 鍵",
        keyDictation: "聽寫鍵",
        keyFocus: "專注模式鍵",
        keyLaunchpad: "啟動台鍵",
        actionRemapOnly: "當作普通按鍵",
        actionMicMute: "靜音麥克風",
        actionPressShortcut: "按下快速鍵",
        remapNote: "特殊按鍵在其重新定義開啟期間會在鍵盤層級重新對應，關閉重新定義或結束 App 時即回復原狀。",
        mappingFailedNote: "無法套用鍵盤對應。另一個重新對應工具（如 Karabiner-Elements）可能已佔用其中某個按鍵。",
        shortcutTakenNote: "macOS 拒絕了其中一個按鍵；可能已被其他 App 佔用。",
        micMuteNeedsFeature: "請在功能中心安裝「麥克風靜音」，此動作才能運作。",
        removeButton: "移除",
        emptyState: "還沒有重新定義。加入一個，或從常用組合開始。"
    )

    static let zhHK = KeyOverrideStrings(
        pageTitle: "按鍵重新定義",
        hubDescription: "從系統取回 F 鍵",
        intro: "Mac 會在應用程式看到這些按鍵之前先行回應——F5 會啟動聽寫，而不是將通話靜音。重新定義會在鍵盤層級重新對應按鍵，讓它執行你自己的任務。",
        enableToggle: "啟用按鍵重新定義",
        addButton: "加入重新定義",
        commonSetButton: "加入常用組合",
        commonSetCaption: "聽寫鍵靜音麥克風；Spotlight 和專注模式鍵變回普通的 F4 和 F6。",
        keyMissionControl: "指揮中心鍵",
        keySpotlight: "Spotlight 鍵",
        keyDictation: "聽寫鍵",
        keyFocus: "專注模式鍵",
        keyLaunchpad: "啟動台鍵",
        actionRemapOnly: "當作普通按鍵",
        actionMicMute: "靜音麥克風",
        actionPressShortcut: "按下快速鍵",
        remapNote: "特殊按鍵在其重新定義開啟期間會在鍵盤層級重新對應，關閉重新定義或結束應用程式時即回復原狀。",
        mappingFailedNote: "無法套用鍵盤對應。另一個重新對應工具（如 Karabiner-Elements）可能已佔用其中某個按鍵。",
        shortcutTakenNote: "macOS 拒絕了其中一個按鍵；可能已被其他應用程式佔用。",
        micMuteNeedsFeature: "請在功能中心安裝「麥克風靜音」，此動作才能運作。",
        removeButton: "移除",
        emptyState: "還沒有重新定義。加入一個，或從常用組合開始。"
    )
}
