// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DisplayManagementStrings {
    let section: String
    let empty: String
    let presets: String
    let presetName: String
    let save: String
    let apply: String
    let deletePreset: String
    let emptyPresets: String
    let displayCountSingular: String
    let displayCountPlural: String
    let effects: String
    let effectsCaption: String
    let resolution: String
    let scale: String
    let native: String
    let makeMain: String
    let main: String
    let colorProfile: String
    let systemDefault: String
    let hdrUnavailable: String
    let autoBrightness: String
    let autoBrightnessCaption: String
    let sensitivity: String
    let hiDPIOverride: String
    let installHiDPI: String
    let removeHiDPI: String
    let arrangement: String
    let imageAdjustments: String
    let contrast: String
    let gamma: String
    let gain: String
    let warmth: String
    let invertColors: String
    let pauseAdjustments: String
    let reset: String
    let updatePreset: String
}

extension FeatureStrings {
    static func displayManagement(_ language: AppLanguage) -> DisplayManagementStrings {
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

extension DisplayManagementStrings {
    static let enUS = DisplayManagementStrings(
        section: "Display management",
        empty: "No active displays found.",
        presets: "Display presets",
        presetName: "Preset name",
        save: "Save",
        apply: "Apply",
        deletePreset: "Delete preset",
        emptyPresets: "Save the current resolution, brightness, arrangement, color profile and HDR choices for all connected displays.",
        displayCountSingular: "1 display",
        displayCountPlural: "%d displays",
        effects: "Screen effects",
        effectsCaption: "These switches mirror the system display controls when the Mac exposes them.",
        resolution: "Resolution",
        scale: "Scale",
        native: "Native",
        makeMain: "Make main display",
        main: "Main",
        colorProfile: "Color profile",
        systemDefault: "System default",
        hdrUnavailable: "HDR is detected, but this Mac does not expose a writable switch for this display.",
        autoBrightness: "Auto brightness",
        autoBrightnessCaption: "External displays follow the built-in display brightness.",
        sensitivity: "Sensitivity",
        hiDPIOverride: "HiDPI override",
        installHiDPI: "Install HiDPI",
        removeHiDPI: "Remove HiDPI",
        arrangement: "Arrangement",
        imageAdjustments: "Image adjustments",
        contrast: "Contrast",
        gamma: "Gamma",
        gain: "Gain",
        warmth: "Warmth",
        invertColors: "Invert colors",
        pauseAdjustments: "Pause adjustments",
        reset: "Reset",
        updatePreset: "Update from current displays"
    )

    static let ptBR = DisplayManagementStrings(
        section: "Gerenciamento de telas",
        empty: "Nenhuma tela ativa encontrada.",
        presets: "Predefinições de tela",
        presetName: "Nome da predefinição",
        save: "Salvar",
        apply: "Aplicar",
        deletePreset: "Apagar predefinição",
        emptyPresets: "Salve a resolução, brilho, organização, perfil de cor e HDR atuais de todas as telas conectadas.",
        displayCountSingular: "1 tela",
        displayCountPlural: "%d telas",
        effects: "Efeitos de tela",
        effectsCaption: "Estes controles acompanham os ajustes de tela do sistema quando o Mac os expõe.",
        resolution: "Resolução",
        scale: "Escala",
        native: "Nativa",
        makeMain: "Tornar tela principal",
        main: "Principal",
        colorProfile: "Perfil de cor",
        systemDefault: "Padrão do sistema",
        hdrUnavailable: "HDR foi detectado, mas este Mac não expõe um interruptor gravável para esta tela.",
        autoBrightness: "Brilho automático",
        autoBrightnessCaption: "Telas externas acompanham o brilho da tela integrada.",
        sensitivity: "Sensibilidade",
        hiDPIOverride: "Substituição HiDPI",
        installHiDPI: "Instalar HiDPI",
        removeHiDPI: "Remover HiDPI",
        arrangement: "Organização",
        imageAdjustments: "Ajustes de imagem",
        contrast: "Contraste",
        gamma: "Gama",
        gain: "Ganho",
        warmth: "Calor",
        invertColors: "Inverter cores",
        pauseAdjustments: "Pausar ajustes",
        reset: "Redefinir",
        updatePreset: "Atualizar com as telas atuais"
    )

    static let tr = DisplayManagementStrings(
        section: "Ekran yönetimi",
        empty: "Etkin ekran bulunamadı.",
        presets: "Ekran ön ayarları",
        presetName: "Ön ayar adı",
        save: "Kaydet",
        apply: "Uygula",
        deletePreset: "Ön ayarı sil",
        emptyPresets: "Bağlı tüm ekranların mevcut çözünürlük, parlaklık, düzen, renk profili ve HDR seçeneklerini kaydedin.",
        displayCountSingular: "1 ekran",
        displayCountPlural: "%d ekran",
        effects: "Ekran efektleri",
        effectsCaption: "Mac bunları sunduğunda bu anahtarlar sistem ekran denetimlerini izler.",
        resolution: "Çözünürlük",
        scale: "Ölçek",
        native: "Yerel",
        makeMain: "Ana ekran yap",
        main: "Ana",
        colorProfile: "Renk profili",
        systemDefault: "Sistem varsayılanı",
        hdrUnavailable: "HDR algılandı, ancak bu Mac bu ekran için yazılabilir bir anahtar sunmuyor.",
        autoBrightness: "Otomatik parlaklık",
        autoBrightnessCaption: "Harici ekranlar yerleşik ekran parlaklığını izler.",
        sensitivity: "Hassasiyet",
        hiDPIOverride: "HiDPI geçersiz kılma",
        installHiDPI: "HiDPI yükle",
        removeHiDPI: "HiDPI kaldır",
        arrangement: "Düzen",
        imageAdjustments: "Görüntü ayarları",
        contrast: "Kontrast",
        gamma: "Gama",
        gain: "Kazanç",
        warmth: "Sıcaklık",
        invertColors: "Renkleri ters çevir",
        pauseAdjustments: "Ayarları duraklat",
        reset: "Sıfırla",
        updatePreset: "Geçerli ekranlardan güncelle"
    )

    static let ru = DisplayManagementStrings(
        section: "Управление экранами",
        empty: "Активные экраны не найдены.",
        presets: "Пресеты экранов",
        presetName: "Название пресета",
        save: "Сохранить",
        apply: "Применить",
        deletePreset: "Удалить пресет",
        emptyPresets: "Сохраните текущие разрешение, яркость, расположение, цветовой профиль и HDR для всех подключённых экранов.",
        displayCountSingular: "1 экран",
        displayCountPlural: "%d экранов",
        effects: "Эффекты экрана",
        effectsCaption: "Эти переключатели повторяют системные настройки экрана, когда Mac их предоставляет.",
        resolution: "Разрешение",
        scale: "Масштаб",
        native: "Родное",
        makeMain: "Сделать основным",
        main: "Основной",
        colorProfile: "Цветовой профиль",
        systemDefault: "Системный профиль",
        hdrUnavailable: "HDR обнаружен, но этот Mac не предоставляет переключатель для этого экрана.",
        autoBrightness: "Автояркость",
        autoBrightnessCaption: "Внешние экраны следуют яркости встроенного экрана.",
        sensitivity: "Чувствительность",
        hiDPIOverride: "Переопределение HiDPI",
        installHiDPI: "Установить HiDPI",
        removeHiDPI: "Удалить HiDPI",
        arrangement: "Расположение",
        imageAdjustments: "Настройки изображения",
        contrast: "Контраст",
        gamma: "Гамма",
        gain: "Усиление",
        warmth: "Теплота",
        invertColors: "Инвертировать цвета",
        pauseAdjustments: "Приостановить настройки",
        reset: "Сбросить",
        updatePreset: "Обновить текущими экранами"
    )

    static let es = DisplayManagementStrings(
        section: "Gestión de pantallas",
        empty: "No se encontró ninguna pantalla activa.",
        presets: "Presets de pantalla",
        presetName: "Nombre del preset",
        save: "Guardar",
        apply: "Aplicar",
        deletePreset: "Eliminar preset",
        emptyPresets: "Guarda la resolución, brillo, disposición, perfil de color y HDR actuales para todas las pantallas conectadas.",
        displayCountSingular: "1 pantalla",
        displayCountPlural: "%d pantallas",
        effects: "Efectos de pantalla",
        effectsCaption: "Estos interruptores reflejan los controles de pantalla del sistema cuando el Mac los expone.",
        resolution: "Resolución",
        scale: "Escala",
        native: "Nativa",
        makeMain: "Hacer principal",
        main: "Principal",
        colorProfile: "Perfil de color",
        systemDefault: "Predeterminado del sistema",
        hdrUnavailable: "Se detecta HDR, pero este Mac no expone un interruptor escribible para esta pantalla.",
        autoBrightness: "Brillo automático",
        autoBrightnessCaption: "Las pantallas externas siguen el brillo de la pantalla integrada.",
        sensitivity: "Sensibilidad",
        hiDPIOverride: "Anulación HiDPI",
        installHiDPI: "Instalar HiDPI",
        removeHiDPI: "Quitar HiDPI",
        arrangement: "Disposición",
        imageAdjustments: "Ajustes de imagen",
        contrast: "Contraste",
        gamma: "Gamma",
        gain: "Ganancia",
        warmth: "Calidez",
        invertColors: "Invertir colores",
        pauseAdjustments: "Pausar ajustes",
        reset: "Restablecer",
        updatePreset: "Actualizar desde pantallas actuales"
    )

    static let de = DisplayManagementStrings(
        section: "Displayverwaltung",
        empty: "Keine aktiven Displays gefunden.",
        presets: "Display-Presets",
        presetName: "Preset-Name",
        save: "Sichern",
        apply: "Anwenden",
        deletePreset: "Preset löschen",
        emptyPresets: "Speichere aktuelle Auflösung, Helligkeit, Anordnung, Farbprofil und HDR für alle verbundenen Displays.",
        displayCountSingular: "1 Display",
        displayCountPlural: "%d Displays",
        effects: "Bildschirmeffekte",
        effectsCaption: "Diese Schalter spiegeln die System-Displaysteuerung, wenn der Mac sie bereitstellt.",
        resolution: "Auflösung",
        scale: "Skalierung",
        native: "Nativ",
        makeMain: "Als Hauptdisplay",
        main: "Hauptdisplay",
        colorProfile: "Farbprofil",
        systemDefault: "Systemstandard",
        hdrUnavailable: "HDR wurde erkannt, aber dieser Mac stellt keinen beschreibbaren Schalter für dieses Display bereit.",
        autoBrightness: "Automatische Helligkeit",
        autoBrightnessCaption: "Externe Displays folgen der Helligkeit des eingebauten Displays.",
        sensitivity: "Empfindlichkeit",
        hiDPIOverride: "HiDPI-Override",
        installHiDPI: "HiDPI installieren",
        removeHiDPI: "HiDPI entfernen",
        arrangement: "Anordnung",
        imageAdjustments: "Bildanpassungen",
        contrast: "Kontrast",
        gamma: "Gamma",
        gain: "Verstärkung",
        warmth: "Wärme",
        invertColors: "Farben umkehren",
        pauseAdjustments: "Anpassungen pausieren",
        reset: "Zurücksetzen",
        updatePreset: "Mit aktuellen Displays aktualisieren"
    )

    static let fr = DisplayManagementStrings(
        section: "Gestion des écrans",
        empty: "Aucun écran actif détecté.",
        presets: "Préréglages d'écran",
        presetName: "Nom du préréglage",
        save: "Enregistrer",
        apply: "Appliquer",
        deletePreset: "Supprimer le préréglage",
        emptyPresets: "Enregistrez la résolution, la luminosité, la disposition, le profil couleur et le HDR actuels de tous les écrans connectés.",
        displayCountSingular: "1 écran",
        displayCountPlural: "%d écrans",
        effects: "Effets d'écran",
        effectsCaption: "Ces interrupteurs reflètent les contrôles d'écran du système lorsque le Mac les expose.",
        resolution: "Résolution",
        scale: "Échelle",
        native: "Native",
        makeMain: "Rendre principal",
        main: "Principal",
        colorProfile: "Profil couleur",
        systemDefault: "Par défaut système",
        hdrUnavailable: "Le HDR est détecté, mais ce Mac n'expose pas d'interrupteur modifiable pour cet écran.",
        autoBrightness: "Luminosité automatique",
        autoBrightnessCaption: "Les écrans externes suivent la luminosité de l'écran intégré.",
        sensitivity: "Sensibilité",
        hiDPIOverride: "Remplacement HiDPI",
        installHiDPI: "Installer HiDPI",
        removeHiDPI: "Retirer HiDPI",
        arrangement: "Disposition",
        imageAdjustments: "Réglages d'image",
        contrast: "Contraste",
        gamma: "Gamma",
        gain: "Gain",
        warmth: "Chaleur",
        invertColors: "Inverser les couleurs",
        pauseAdjustments: "Suspendre les réglages",
        reset: "Réinitialiser",
        updatePreset: "Mettre à jour avec les écrans actuels"
    )

    static let it = DisplayManagementStrings(
        section: "Gestione schermi",
        empty: "Nessuno schermo attivo trovato.",
        presets: "Preset schermo",
        presetName: "Nome preset",
        save: "Salva",
        apply: "Applica",
        deletePreset: "Elimina preset",
        emptyPresets: "Salva risoluzione, luminosità, disposizione, profilo colore e HDR attuali per tutti gli schermi collegati.",
        displayCountSingular: "1 schermo",
        displayCountPlural: "%d schermi",
        effects: "Effetti schermo",
        effectsCaption: "Questi interruttori rispecchiano i controlli schermo di sistema quando il Mac li espone.",
        resolution: "Risoluzione",
        scale: "Scala",
        native: "Nativa",
        makeMain: "Rendi principale",
        main: "Principale",
        colorProfile: "Profilo colore",
        systemDefault: "Predefinito di sistema",
        hdrUnavailable: "HDR rilevato, ma questo Mac non espone un interruttore scrivibile per questo schermo.",
        autoBrightness: "Luminosità automatica",
        autoBrightnessCaption: "Gli schermi esterni seguono la luminosità dello schermo integrato.",
        sensitivity: "Sensibilità",
        hiDPIOverride: "Sostituzione HiDPI",
        installHiDPI: "Installa HiDPI",
        removeHiDPI: "Rimuovi HiDPI",
        arrangement: "Disposizione",
        imageAdjustments: "Regolazioni immagine",
        contrast: "Contrasto",
        gamma: "Gamma",
        gain: "Guadagno",
        warmth: "Calore",
        invertColors: "Inverti colori",
        pauseAdjustments: "Pausa regolazioni",
        reset: "Ripristina",
        updatePreset: "Aggiorna dagli schermi attuali"
    )

    static let ja = DisplayManagementStrings(
        section: "ディスプレイ管理",
        empty: "有効なディスプレイが見つかりません。",
        presets: "ディスプレイプリセット",
        presetName: "プリセット名",
        save: "保存",
        apply: "適用",
        deletePreset: "プリセットを削除",
        emptyPresets: "接続中のすべてのディスプレイの解像度、明るさ、配置、カラープロファイル、HDRを保存します。",
        displayCountSingular: "1台のディスプレイ",
        displayCountPlural: "%d台のディスプレイ",
        effects: "画面効果",
        effectsCaption: "Mac が提供している場合、システムのディスプレイ制御を反映します。",
        resolution: "解像度",
        scale: "スケール",
        native: "ネイティブ",
        makeMain: "メインにする",
        main: "メイン",
        colorProfile: "カラープロファイル",
        systemDefault: "システム標準",
        hdrUnavailable: "HDR は検出されていますが、この Mac はこのディスプレイ用の書き込み可能なスイッチを提供していません。",
        autoBrightness: "自動輝度",
        autoBrightnessCaption: "外部ディスプレイが内蔵ディスプレイの明るさに追従します。",
        sensitivity: "感度",
        hiDPIOverride: "HiDPIオーバーライド",
        installHiDPI: "HiDPIをインストール",
        removeHiDPI: "HiDPIを削除",
        arrangement: "配置",
        imageAdjustments: "画像調整",
        contrast: "コントラスト",
        gamma: "ガンマ",
        gain: "ゲイン",
        warmth: "暖かさ",
        invertColors: "色を反転",
        pauseAdjustments: "調整を一時停止",
        reset: "リセット",
        updatePreset: "現在のディスプレイで更新"
    )

    static let ko = DisplayManagementStrings(
        section: "디스플레이 관리",
        empty: "활성 디스플레이를 찾을 수 없습니다.",
        presets: "디스플레이 프리셋",
        presetName: "프리셋 이름",
        save: "저장",
        apply: "적용",
        deletePreset: "프리셋 삭제",
        emptyPresets: "연결된 모든 디스플레이의 현재 해상도, 밝기, 배치, 색상 프로파일 및 HDR 선택을 저장합니다.",
        displayCountSingular: "디스플레이 1대",
        displayCountPlural: "디스플레이 %d대",
        effects: "화면 효과",
        effectsCaption: "Mac에서 제공될 때 시스템 디스플레이 제어를 그대로 반영합니다.",
        resolution: "해상도",
        scale: "스케일",
        native: "기본",
        makeMain: "주 디스플레이로 설정",
        main: "주 디스플레이",
        colorProfile: "색상 프로파일",
        systemDefault: "시스템 기본값",
        hdrUnavailable: "HDR이 감지되었지만 이 Mac은 이 디스플레이에 쓸 수 있는 스위치를 제공하지 않습니다.",
        autoBrightness: "자동 밝기",
        autoBrightnessCaption: "외부 디스플레이가 내장 디스플레이 밝기를 따라갑니다.",
        sensitivity: "민감도",
        hiDPIOverride: "HiDPI 오버라이드",
        installHiDPI: "HiDPI 설치",
        removeHiDPI: "HiDPI 제거",
        arrangement: "배치",
        imageAdjustments: "이미지 조정",
        contrast: "대비",
        gamma: "감마",
        gain: "게인",
        warmth: "따뜻함",
        invertColors: "색상 반전",
        pauseAdjustments: "조정 일시 정지",
        reset: "재설정",
        updatePreset: "현재 디스플레이로 업데이트"
    )

    static let zhHans = DisplayManagementStrings(
        section: "显示器管理",
        empty: "未找到活动显示器。",
        presets: "显示器预设",
        presetName: "预设名称",
        save: "保存",
        apply: "应用",
        deletePreset: "删除预设",
        emptyPresets: "保存所有已连接显示器当前的分辨率、亮度、排列、颜色描述文件和 HDR 选择。",
        displayCountSingular: "1 台显示器",
        displayCountPlural: "%d 台显示器",
        effects: "屏幕效果",
        effectsCaption: "当 Mac 提供这些系统显示控制时，这些开关会与其同步。",
        resolution: "分辨率",
        scale: "缩放",
        native: "原生",
        makeMain: "设为主显示器",
        main: "主显示器",
        colorProfile: "颜色描述文件",
        systemDefault: "系统默认",
        hdrUnavailable: "检测到 HDR，但此 Mac 没有为这台显示器提供可写开关。",
        autoBrightness: "自动亮度",
        autoBrightnessCaption: "外接显示器跟随内置显示器亮度。",
        sensitivity: "灵敏度",
        hiDPIOverride: "HiDPI 覆盖",
        installHiDPI: "安装 HiDPI",
        removeHiDPI: "移除 HiDPI",
        arrangement: "排列",
        imageAdjustments: "图像调整",
        contrast: "对比度",
        gamma: "伽马",
        gain: "增益",
        warmth: "暖度",
        invertColors: "反转颜色",
        pauseAdjustments: "暂停调整",
        reset: "重置",
        updatePreset: "用当前显示器更新"
    )

    static let zhTW = DisplayManagementStrings(
        section: "顯示器管理",
        empty: "找不到作用中的顯示器。",
        presets: "顯示器預設",
        presetName: "預設名稱",
        save: "儲存",
        apply: "套用",
        deletePreset: "刪除預設",
        emptyPresets: "儲存所有已連接顯示器目前的解析度、亮度、排列、色彩描述檔和 HDR 選擇。",
        displayCountSingular: "1 台顯示器",
        displayCountPlural: "%d 台顯示器",
        effects: "螢幕效果",
        effectsCaption: "當 Mac 提供這些系統顯示控制時，這些開關會與其同步。",
        resolution: "解析度",
        scale: "縮放",
        native: "原生",
        makeMain: "設為主顯示器",
        main: "主顯示器",
        colorProfile: "色彩描述檔",
        systemDefault: "系統預設",
        hdrUnavailable: "偵測到 HDR，但此 Mac 沒有為這台顯示器提供可寫入開關。",
        autoBrightness: "自動亮度",
        autoBrightnessCaption: "外接顯示器跟隨內建顯示器亮度。",
        sensitivity: "靈敏度",
        hiDPIOverride: "HiDPI 覆寫",
        installHiDPI: "安裝 HiDPI",
        removeHiDPI: "移除 HiDPI",
        arrangement: "排列",
        imageAdjustments: "影像調整",
        contrast: "對比",
        gamma: "Gamma",
        gain: "增益",
        warmth: "暖度",
        invertColors: "反轉色彩",
        pauseAdjustments: "暫停調整",
        reset: "重置",
        updatePreset: "用目前顯示器更新"
    )

    static let zhHK = DisplayManagementStrings(
        section: "顯示器管理",
        empty: "找不到使用中的顯示器。",
        presets: "顯示器預設",
        presetName: "預設名稱",
        save: "儲存",
        apply: "套用",
        deletePreset: "刪除預設",
        emptyPresets: "儲存所有已連接顯示器目前的解像度、亮度、排列、色彩描述檔和 HDR 選擇。",
        displayCountSingular: "1 部顯示器",
        displayCountPlural: "%d 部顯示器",
        effects: "螢幕效果",
        effectsCaption: "當 Mac 提供這些系統顯示控制時，這些開關會與其同步。",
        resolution: "解像度",
        scale: "縮放",
        native: "原生",
        makeMain: "設為主顯示器",
        main: "主顯示器",
        colorProfile: "色彩描述檔",
        systemDefault: "系統預設",
        hdrUnavailable: "偵測到 HDR，但此 Mac 沒有為這部顯示器提供可寫入開關。",
        autoBrightness: "自動亮度",
        autoBrightnessCaption: "外置顯示器跟隨內置顯示器亮度。",
        sensitivity: "靈敏度",
        hiDPIOverride: "HiDPI 覆寫",
        installHiDPI: "安裝 HiDPI",
        removeHiDPI: "移除 HiDPI",
        arrangement: "排列",
        imageAdjustments: "影像調整",
        contrast: "對比",
        gamma: "Gamma",
        gain: "增益",
        warmth: "暖度",
        invertColors: "反轉色彩",
        pauseAdjustments: "暫停調整",
        reset: "重設",
        updatePreset: "用目前顯示器更新"
    )
}
