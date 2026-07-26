// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureStrings {
    static func settingsCategories(_ language: AppLanguage) -> SettingsCategoryStrings {
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

    static func clipboard(_ language: AppLanguage) -> ClipboardFeatureStrings {
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

    static func windowLayout(_ language: AppLanguage) -> WindowLayoutFeatureStrings {
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

    static func monitorAlerts(_ language: AppLanguage) -> MonitorAlertFeatureStrings {
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

    static func sensors(_ language: AppLanguage) -> SensorsFeatureStrings {
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

extension SettingsCategoryStrings {
    static let ko = SettingsCategoryStrings(
        essentials: "기본 기능",
        windowsControls: "윈도우 및 제어",
        files: "파일",
        utilities: "유틸리티",
        app: "앱"
    )
}

extension ClipboardFeatureStrings {
    static let ko = ClipboardFeatureStrings(
        title: "클립보드",
        enable: "클립보드 기록 저장",
        caption: "복사한 텍스트를 저장하여 나중에 다시 사용할 수 있습니다. 모든 항목은 로컬에 보관되며 언제든 지울 수 있습니다.",
        localNote: "모든 항목은 이 Mac에만 저장됩니다. 너무 큰 항목은 무시됩니다.",
        skipSensitive: "민감해 보이는 텍스트 건너뛰기",
        skipSensitiveCaption: "암호, 토큰, 키처럼 보이는 짧고 공백 없는 문자열을 저장하지 않습니다.",
        limit: "제한",
        showInPanel: "패널에 표시",
        shortcut: "기록 단축키",
        shortcutCaption: "검색, 고정 항목 및 이전 앱에 붙여넣기 위한 ⌘1~⌘9 단축키가 있는 빠른 윈도우를 엽니다.",
        shortcutHint: "행을 클릭하면 이전 앱에 붙여넣습니다. ⌘-클릭으로 여러 항목을 선택하고, ⌘C로 붙여넣지 않고 복사합니다.",
        clickRowShortcut: "행 클릭",
        commandClickShortcut: "⌘ 클릭",
        pinned: "고정됨",
        recent: "최근 항목",
        pin: "고정",
        unpin: "고정 해제",
        clearRecent: "최근 항목 지우기",
        clearAll: "고정되지 않은 항목 지우기",
        empty: "저장한 텍스트가 없습니다",
        disabled: "복사한 텍스트를 저장하려면 기록을 켜세요.",
        search: "복사한 텍스트 검색",
        copy: "복사",
        copied: "복사됨",
        delete: "항목 삭제",
        selectMultiple: "묶음에 추가",
        unselectMultiple: "묶음에서 제거",
        selectShortcutAction: "선택",
        pasteSelectedFormat: "%d개 붙여넣기",
        copySelectedFormat: "%d개 복사",
        clearSelection: "선택 해제",
        moveUp: "위로 이동",
        moveDown: "아래로 이동",
        noResults: "결과 없음",
        newestFirst: "최신순",
        active: "새 텍스트 저장 중",
        includeImagesFiles: "복사한 이미지와 파일도 저장",
        includeImagesFilesCaption: "이미지는 기록에 추가되고 파일은 위치 링크로 저장됩니다. 텍스트 항목처럼 고정하고 붙여넣을 수 있습니다.",
        imageEntryLabel: "이미지",
        fileCountFormat: "파일 %d개"
    )
}

extension WindowLayoutFeatureStrings {
    static let ko = WindowLayoutFeatureStrings(
        title: "윈도우 정렬",
        caption: "활성 윈도우를 화면의 절반, 3등분, 6등분, 모서리, 다른 디스플레이, 중앙 또는 사용 가능한 화면 영역으로 이동합니다.",
        showInPanel: "패널에 표시",
        shortcuts: "단축키",
        shortcutsCaption: "패널을 열지 않고 전역 단축키로 활성 윈도우를 정렬합니다.",
        permissionCaption: "손쉬운 사용 권한을 사용해 활성 윈도우만 이동합니다.",
        noWindow: "활성 윈도우를 찾을 수 없습니다.",
        missingPermission: "윈도우를 이동하려면 손쉬운 사용 권한을 허용하세요.",
        failed: "이 윈도우를 이동할 수 없습니다.",
        done: "윈도우를 정렬했습니다.",
        restored: "윈도우를 복원했습니다.",
        noRestore: "복원할 이전 정렬이 없습니다.",
        target: "활성 윈도우",
        halves: "2등분",
        thirds: "3등분",
        sixths: "6등분",
        corners: "모서리",
        other: "동작",
        leftHalf: "왼쪽",
        rightHalf: "오른쪽",
        topHalf: "위쪽",
        bottomHalf: "아래쪽",
        leftThird: "왼쪽 1/3",
        centerThird: "가운데 1/3",
        rightThird: "오른쪽 1/3",
        leftTwoThirds: "왼쪽 2/3",
        rightTwoThirds: "오른쪽 2/3",
        topLeftSixth: "왼쪽 위 1/6",
        topCenterSixth: "위쪽 가운데 1/6",
        topRightSixth: "오른쪽 위 1/6",
        bottomLeftSixth: "왼쪽 아래 1/6",
        bottomCenterSixth: "아래쪽 가운데 1/6",
        bottomRightSixth: "오른쪽 아래 1/6",
        topLeft: "왼쪽 위",
        topRight: "오른쪽 위",
        bottomLeft: "왼쪽 아래",
        bottomRight: "오른쪽 아래",
        maximize: "최대화",
        center: "가운데",
        nextDisplay: "다음 디스플레이",
        restore: "복원"
    )
}

extension MonitorAlertFeatureStrings {
    static let ko = MonitorAlertFeatureStrings(
        section: "알림",
        caption: "기본적으로 꺼져 있습니다. 켜면 모니터가 유의미한 상태가 계속될 때만 경고하고 알림 간격을 지킵니다.",
        notificationsDenied: "시스템 설정에서 Vorssaint 알림이 꺼져 있어 경고를 표시할 수 없습니다.",
        cpu: "높은 CPU 사용량",
        cpuTemperature: "높은 CPU 온도",
        memory: "위험한 메모리 압력",
        disk: "부족한 디스크 공간",
        battery: "낮은 배터리",
        cpuThreshold: "CPU 사용량",
        cpuTemperatureThreshold: "온도",
        diskThreshold: "남은 공간",
        batteryThreshold: "배터리 잔량",
        cooldown: "알림 간격",
        cooldown2: "2분",
        cooldown5: "5분",
        cooldown15: "15분",
        cooldown30: "30분",
        cooldown60: "1시간",
        cpuTitle: "높은 CPU 사용량",
        cpuBodyFormat: "CPU 사용량이 몇 초 동안 %d%%를 넘었습니다.",
        cpuTemperatureTitle: "CPU 과열",
        cpuTemperatureBodyFormat: "CPU 온도가 %d °C에 도달했습니다.",
        memoryTitle: "위험한 메모리",
        memoryBody: "메모리 압력이 위험 수준에 도달했습니다.",
        diskTitle: "부족한 디스크 공간",
        diskBodyFormat: "%@의 여유 공간이 %d%% 미만입니다.",
        batteryTitle: "낮은 배터리",
        batteryBodyFormat: "배터리 잔량이 %d%%입니다."
    )
}

struct SettingsCategoryStrings {
    let essentials: String
    let windowsControls: String
    let files: String
    let utilities: String
    let app: String

    static let enUS = SettingsCategoryStrings(
        essentials: "Essentials",
        windowsControls: "Window controls",
        files: "Files",
        utilities: "Utilities",
        app: "App"
    )

    static let ptBR = SettingsCategoryStrings(
        essentials: "Essenciais",
        windowsControls: "Janelas e controles",
        files: "Arquivos",
        utilities: "Utilitários",
        app: "App"
    )

    static let tr = SettingsCategoryStrings(
        essentials: "Temel",
        windowsControls: "Pencereler ve denetimler",
        files: "Dosyalar",
        utilities: "Araçlar",
        app: "Uygulama"
    )

    static let ru = SettingsCategoryStrings(
        essentials: "Основное",
        windowsControls: "Окна и управление",
        files: "Файлы",
        utilities: "Утилиты",
        app: "Приложение"
    )

    static let es = SettingsCategoryStrings(
        essentials: "Esenciales",
        windowsControls: "Ventanas y controles",
        files: "Archivos",
        utilities: "Utilidades",
        app: "App"
    )

    static let de = SettingsCategoryStrings(
        essentials: "Grundlagen",
        windowsControls: "Fenster und Steuerung",
        files: "Dateien",
        utilities: "Dienstprogramme",
        app: "App"
    )

    static let fr = SettingsCategoryStrings(
        essentials: "Essentiel",
        windowsControls: "Fenêtres et contrôles",
        files: "Fichiers",
        utilities: "Utilitaires",
        app: "App"
    )

    static let it = SettingsCategoryStrings(
        essentials: "Essenziali",
        windowsControls: "Finestre e controlli",
        files: "File",
        utilities: "Utilità",
        app: "App"
    )

    static let ja = SettingsCategoryStrings(
        essentials: "基本機能",
        windowsControls: "ウインドウと操作",
        files: "ファイル",
        utilities: "ユーティリティ",
        app: "App"
    )

    static let zhHans = SettingsCategoryStrings(
        essentials: "基础功能",
        windowsControls: "窗口与控制",
        files: "文件",
        utilities: "实用工具",
        app: "App"
    )

    static let zhTW = SettingsCategoryStrings(
        essentials: "基本功能",
        windowsControls: "視窗與控制",
        files: "檔案",
        utilities: "工具程式",
        app: "App"
    )

    static let zhHK = SettingsCategoryStrings(
        essentials: "基本功能",
        windowsControls: "視窗及控制",
        files: "檔案",
        utilities: "工具",
        app: "App"
    )
}

struct ClipboardFeatureStrings {
    let title: String
    let enable: String
    let caption: String
    let localNote: String
    let skipSensitive: String
    let skipSensitiveCaption: String
    let limit: String
    let showInPanel: String
    let shortcut: String
    let shortcutCaption: String
    let shortcutHint: String
    let clickRowShortcut: String
    let commandClickShortcut: String
    let pinned: String
    let recent: String
    let pin: String
    let unpin: String
    let clearRecent: String
    let clearAll: String
    let empty: String
    let disabled: String
    let search: String
    let copy: String
    let copied: String
    let delete: String
    let selectMultiple: String
    let unselectMultiple: String
    let selectShortcutAction: String
    let pasteSelectedFormat: String
    let copySelectedFormat: String
    let clearSelection: String
    let moveUp: String
    let moveDown: String
    let noResults: String
    let newestFirst: String
    let active: String
    let includeImagesFiles: String
    let includeImagesFilesCaption: String
    let imageEntryLabel: String
    let fileCountFormat: String

    static let enUS = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Save clipboard history",
        caption: "Stores copied text so you can reuse it later. Everything stays local and can be cleared anytime.",
        localNote: "Everything stays on this Mac. Very large items are ignored.",
        skipSensitive: "Skip text that looks sensitive",
        skipSensitiveCaption: "Avoids saving short no-space strings that look like passwords, tokens or keys.",
        limit: "Limit",
        showInPanel: "Show in panel",
        shortcut: "History shortcut",
        shortcutCaption: "Opens a quick window with search, pinned items and ⌘1 to ⌘9 shortcuts for pasting into the previous app.",
        shortcutHint: "Click a row to paste it into the previous app. ⌘-click selects several; ⌘C copies without pasting.",
        clickRowShortcut: "Click row",
        commandClickShortcut: "⌘ Click",
        pinned: "Pinned",
        recent: "Recent",
        pin: "Pin",
        unpin: "Unpin",
        clearRecent: "Clear recent",
        clearAll: "Clear unpinned",
        empty: "No saved text",
        disabled: "Enable history to start saving copied text.",
        search: "Search copied text",
        copy: "Copy",
        copied: "Copied",
        delete: "Delete item",
        selectMultiple: "Add to pile",
        unselectMultiple: "Remove from pile",
        selectShortcutAction: "Select",
        pasteSelectedFormat: "Paste %d",
        copySelectedFormat: "Copy %d",
        clearSelection: "Clear selection",
        moveUp: "Move up",
        moveDown: "Move down",
        noResults: "No results",
        newestFirst: "Newest first",
        active: "Saving new text",
        includeImagesFiles: "Also save copied images and files",
        includeImagesFilesCaption: "Images join the history and files are remembered as links to their location. Pin and paste them like any text item.",
        imageEntryLabel: "Image",
        fileCountFormat: "%d files"
    )

    static let ptBR = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Guardar histórico de clipboard",
        caption: "Guarda textos copiados para reutilizar depois. Tudo fica local e pode ser apagado a qualquer momento.",
        localNote: "Tudo fica neste Mac. Itens muito grandes são ignorados.",
        skipSensitive: "Ignorar textos com aparência sensível",
        skipSensitiveCaption: "Evita salvar textos curtos sem espaços que parecem senha, token ou chave.",
        limit: "Limite",
        showInPanel: "Mostrar no painel",
        shortcut: "Atalho do histórico",
        shortcutCaption: "Abre uma janela rápida com busca, favoritos e atalhos ⌘1 a ⌘9 para colar no app anterior.",
        shortcutHint: "Clique numa linha para colar no app anterior. ⌘+clique seleciona várias; ⌘C copia sem colar.",
        clickRowShortcut: "Clique na linha",
        commandClickShortcut: "⌘ Clique",
        pinned: "Fixados",
        recent: "Recentes",
        pin: "Fixar",
        unpin: "Desfixar",
        clearRecent: "Limpar recentes",
        clearAll: "Limpar não fixados",
        empty: "Nenhum texto salvo",
        disabled: "Ative o histórico para começar a guardar textos copiados.",
        search: "Buscar textos copiados",
        copy: "Copiar",
        copied: "Copiado",
        delete: "Apagar item",
        selectMultiple: "Marcar para pilha",
        unselectMultiple: "Remover da pilha",
        selectShortcutAction: "Selecionar",
        pasteSelectedFormat: "Colar %d",
        copySelectedFormat: "Copiar %d",
        clearSelection: "Limpar seleção",
        moveUp: "Mover para cima",
        moveDown: "Mover para baixo",
        noResults: "Nenhum resultado",
        newestFirst: "Mais recentes primeiro",
        active: "Guardando novos textos",
        includeImagesFiles: "Guardar também imagens e arquivos copiados",
        includeImagesFilesCaption: "Imagens entram no histórico e arquivos são lembrados como links para o local deles. Fixe e cole como qualquer texto.",
        imageEntryLabel: "Imagem",
        fileCountFormat: "%d arquivos"
    )

    static let tr = ClipboardFeatureStrings(
        title: "Pano",
        enable: "Pano geçmişini kaydet",
        caption: "Kopyalanan metinleri daha sonra yeniden kullanabilmen için saklar. Her şey yerel kalır ve istediğin zaman temizlenebilir.",
        localNote: "Her şey bu Mac'te kalır. Çok büyük öğeler yok sayılır.",
        skipSensitive: "Hassas görünen metinleri atla",
        skipSensitiveCaption: "Parola, token veya anahtar gibi görünen kısa ve boşluksuz dizeleri kaydetmekten kaçınır.",
        limit: "Sınır",
        showInPanel: "Panelde göster",
        shortcut: "Geçmiş kısayolu",
        shortcutCaption: "Arama, sabitlenmiş öğeler ve önceki uygulamaya yapıştırmak için ⌘1 - ⌘9 kısayolları olan hızlı bir pencere açar.",
        shortcutHint: "Bir satıra tıklayarak önceki uygulamaya yapıştırın. ⌘-tıklama birden çok öğe seçer; ⌘C yapıştırmadan kopyalar.",
        clickRowShortcut: "Satıra tıkla",
        commandClickShortcut: "⌘ Tıkla",
        pinned: "Sabitlenenler",
        recent: "Son",
        pin: "Sabitle",
        unpin: "Sabitlemeyi kaldır",
        clearRecent: "Sonları temizle",
        clearAll: "Sabitlenmeyenleri temizle",
        empty: "Kayıtlı metin yok",
        disabled: "Kopyalanan metinleri kaydetmeye başlamak için geçmişi etkinleştir.",
        search: "Kopyalanan metinlerde ara",
        copy: "Kopyala",
        copied: "Kopyalandı",
        delete: "Öğeyi sil",
        selectMultiple: "Yığına ekle",
        unselectMultiple: "Yığından çıkar",
        selectShortcutAction: "Seç",
        pasteSelectedFormat: "%d öğeyi yapıştır",
        copySelectedFormat: "%d öğeyi kopyala",
        clearSelection: "Seçimi temizle",
        moveUp: "Yukarı taşı",
        moveDown: "Aşağı taşı",
        noResults: "Sonuç yok",
        newestFirst: "En yeniler önce",
        active: "Yeni metinler kaydediliyor",
        includeImagesFiles: "Kopyalanan görselleri ve dosyaları da kaydet",
        includeImagesFilesCaption: "Görseller geçmişe eklenir, dosyalar konumlarına bağlantı olarak hatırlanır. Metin gibi sabitle ve yapıştır.",
        imageEntryLabel: "Görsel",
        fileCountFormat: "%d dosya"
    )

    static let ru = ClipboardFeatureStrings(
        title: "Буфер обмена",
        enable: "Сохранять историю буфера обмена",
        caption: "Сохраняет скопированный текст, чтобы вы могли использовать его позже. Всё остаётся локально и может быть очищено в любой момент.",
        localNote: "Всё остаётся на этом Mac. Слишком большие элементы игнорируются.",
        skipSensitive: "Пропускать текст, похожий на конфиденциальный",
        skipSensitiveCaption: "Не сохраняет короткие строки без пробелов, похожие на пароли, токены или ключи.",
        limit: "Лимит",
        showInPanel: "Показывать в панели",
        shortcut: "Горячая клавиша истории",
        shortcutCaption: "Открывает быстрое окно с поиском, закреплёнными элементами и сочетаниями ⌘1–⌘9 для вставки в предыдущее приложение.",
        shortcutHint: "Щёлкните по строке, чтобы вставить её в предыдущее приложение. ⌘-клик выбирает несколько; ⌘C копирует без вставки.",
        clickRowShortcut: "Щелчок по строке",
        commandClickShortcut: "⌘ Клик",
        pinned: "Закреплённые",
        recent: "Недавние",
        pin: "Закрепить",
        unpin: "Открепить",
        clearRecent: "Очистить недавнее",
        clearAll: "Очистить незакреплённые",
        empty: "Нет сохранённого текста",
        disabled: "Включите историю, чтобы начать сохранять скопированный текст.",
        search: "Поиск по скопированному тексту",
        copy: "Скопировать",
        copied: "Скопировано",
        delete: "Удалить элемент",
        selectMultiple: "Добавить в стопку",
        unselectMultiple: "Убрать из стопки",
        selectShortcutAction: "Выбрать",
        pasteSelectedFormat: "Вставить: %d",
        copySelectedFormat: "Копировать: %d",
        clearSelection: "Снять выделение",
        moveUp: "Вверх",
        moveDown: "Вниз",
        noResults: "Ничего не найдено",
        newestFirst: "Сначала новые",
        active: "Сохраняет новые элементы",
        includeImagesFiles: "Сохранять также изображения и файлы",
        includeImagesFilesCaption: "Изображения попадают в историю, а файлы запоминаются как ссылки на их расположение. Закрепляйте и вставляйте их как текст.",
        imageEntryLabel: "Изображение",
        fileCountFormat: "Файлов: %d"
    )

    static let es = ClipboardFeatureStrings(
        title: "Portapapeles",
        enable: "Guardar historial del portapapeles",
        caption: "Guarda el texto copiado para reutilizarlo después. Todo queda local y se puede borrar cuando quieras.",
        localNote: "Todo se queda en este Mac. Los elementos muy grandes se ignoran.",
        skipSensitive: "Omitir texto que parezca sensible",
        skipSensitiveCaption: "Evita guardar cadenas cortas sin espacios que parezcan contraseñas, tokens o claves.",
        limit: "Límite",
        showInPanel: "Mostrar en el panel",
        shortcut: "Atajo del historial",
        shortcutCaption: "Abre una ventana rápida con búsqueda, elementos fijados y atajos ⌘1 a ⌘9 para pegar en la app anterior.",
        shortcutHint: "Haz clic en una fila para pegarla en la app anterior. ⌘+clic selecciona varias; ⌘C copia sin pegar.",
        clickRowShortcut: "Clic en fila",
        commandClickShortcut: "⌘ Clic",
        pinned: "Fijados",
        recent: "Recientes",
        pin: "Fijar",
        unpin: "Desfijar",
        clearRecent: "Limpiar recientes",
        clearAll: "Limpiar no fijados",
        empty: "No hay texto guardado",
        disabled: "Activa el historial para empezar a guardar texto copiado.",
        search: "Buscar texto copiado",
        copy: "Copiar",
        copied: "Copiado",
        delete: "Eliminar elemento",
        selectMultiple: "Añadir a la pila",
        unselectMultiple: "Quitar de la pila",
        selectShortcutAction: "Seleccionar",
        pasteSelectedFormat: "Pegar %d",
        copySelectedFormat: "Copiar %d",
        clearSelection: "Limpiar selección",
        moveUp: "Subir",
        moveDown: "Bajar",
        noResults: "Sin resultados",
        newestFirst: "Más recientes primero",
        active: "Guardando nuevo texto",
        includeImagesFiles: "Guardar también imágenes y archivos copiados",
        includeImagesFilesCaption: "Las imágenes entran en el historial y los archivos se recuerdan como enlaces a su ubicación. Fíjalos y pégalos como cualquier texto.",
        imageEntryLabel: "Imagen",
        fileCountFormat: "%d archivos"
    )

    static let de = ClipboardFeatureStrings(
        title: "Zwischenablage",
        enable: "Zwischenablageverlauf speichern",
        caption: "Speichert kopierten Text, damit du ihn später wiederverwenden kannst. Alles bleibt lokal und kann jederzeit gelöscht werden.",
        localNote: "Alles bleibt auf diesem Mac. Sehr große Inhalte werden ignoriert.",
        skipSensitive: "Text überspringen, der sensibel wirkt",
        skipSensitiveCaption: "Speichert keine kurzen Zeichenfolgen ohne Leerzeichen, die wie Passwörter, Token oder Schlüssel wirken.",
        limit: "Limit",
        showInPanel: "Im Panel anzeigen",
        shortcut: "Verlaufskürzel",
        shortcutCaption: "Öffnet ein Schnellfenster mit Suche, angehefteten Einträgen und ⌘1 bis ⌘9 zum Einfügen in die vorherige App.",
        shortcutHint: "Klicke auf eine Zeile, um sie in die vorherige App einzufügen. ⌘-Klick wählt mehrere aus; ⌘C kopiert ohne Einfügen.",
        clickRowShortcut: "Zeile klicken",
        commandClickShortcut: "⌘ Klick",
        pinned: "Angeheftet",
        recent: "Zuletzt",
        pin: "Anheften",
        unpin: "Lösen",
        clearRecent: "Zuletzt löschen",
        clearAll: "Nicht angeheftete löschen",
        empty: "Kein gespeicherter Text",
        disabled: "Aktiviere den Verlauf, um kopierten Text zu speichern.",
        search: "Kopierten Text suchen",
        copy: "Kopieren",
        copied: "Kopiert",
        delete: "Eintrag löschen",
        selectMultiple: "Zum Stapel hinzufügen",
        unselectMultiple: "Aus dem Stapel entfernen",
        selectShortcutAction: "Auswählen",
        pasteSelectedFormat: "%d einfügen",
        copySelectedFormat: "%d kopieren",
        clearSelection: "Auswahl löschen",
        moveUp: "Nach oben",
        moveDown: "Nach unten",
        noResults: "Keine Ergebnisse",
        newestFirst: "Neueste zuerst",
        active: "Speichert neuen Text",
        includeImagesFiles: "Auch kopierte Bilder und Dateien speichern",
        includeImagesFilesCaption: "Bilder wandern in den Verlauf, Dateien werden als Verweise auf ihren Ort gemerkt. Anheften und Einsetzen wie bei Text.",
        imageEntryLabel: "Bild",
        fileCountFormat: "%d Dateien"
    )

    static let fr = ClipboardFeatureStrings(
        title: "Presse-papiers",
        enable: "Enregistrer l'historique du presse-papiers",
        caption: "Enregistre le texte copié pour le réutiliser plus tard. Tout reste local et peut être effacé à tout moment.",
        localNote: "Tout reste sur ce Mac. Les éléments très volumineux sont ignorés.",
        skipSensitive: "Ignorer le texte qui semble sensible",
        skipSensitiveCaption: "Évite d'enregistrer les courtes chaînes sans espaces qui ressemblent à des mots de passe, jetons ou clés.",
        limit: "Limite",
        showInPanel: "Afficher dans le panneau",
        shortcut: "Raccourci de l'historique",
        shortcutCaption: "Ouvre une fenêtre rapide avec recherche, éléments épinglés et raccourcis ⌘1 à ⌘9 pour coller dans l'app précédente.",
        shortcutHint: "Cliquez sur une ligne pour la coller dans l'app précédente. ⌘+clic en sélectionne plusieurs ; ⌘C copie sans coller.",
        clickRowShortcut: "Cliquer la ligne",
        commandClickShortcut: "⌘ Clic",
        pinned: "Épinglés",
        recent: "Récents",
        pin: "Épingler",
        unpin: "Désépingler",
        clearRecent: "Effacer les récents",
        clearAll: "Effacer non épinglés",
        empty: "Aucun texte enregistré",
        disabled: "Activez l'historique pour commencer à enregistrer le texte copié.",
        search: "Rechercher le texte copié",
        copy: "Copier",
        copied: "Copié",
        delete: "Supprimer l'élément",
        selectMultiple: "Ajouter à la pile",
        unselectMultiple: "Retirer de la pile",
        selectShortcutAction: "Sélectionner",
        pasteSelectedFormat: "Coller %d",
        copySelectedFormat: "Copier %d",
        clearSelection: "Effacer la sélection",
        moveUp: "Monter",
        moveDown: "Descendre",
        noResults: "Aucun résultat",
        newestFirst: "Plus récents d'abord",
        active: "Enregistre le nouveau texte",
        includeImagesFiles: "Enregistrer aussi les images et fichiers copiés",
        includeImagesFilesCaption: "Les images rejoignent l'historique et les fichiers sont mémorisés comme des liens vers leur emplacement. Épinglez-les et collez-les comme du texte.",
        imageEntryLabel: "Image",
        fileCountFormat: "%d fichiers"
    )

    static let it = ClipboardFeatureStrings(
        title: "Appunti",
        enable: "Salva cronologia degli appunti",
        caption: "Salva il testo copiato per riutilizzarlo in seguito. Tutto resta locale e può essere cancellato in qualsiasi momento.",
        localNote: "Tutto resta su questo Mac. Gli elementi molto grandi vengono ignorati.",
        skipSensitive: "Ignora testo che sembra sensibile",
        skipSensitiveCaption: "Evita di salvare stringhe brevi senza spazi che sembrano password, token o chiavi.",
        limit: "Limite",
        showInPanel: "Mostra nel pannello",
        shortcut: "Scorciatoia cronologia",
        shortcutCaption: "Apre una finestra rapida con ricerca, elementi fissati e scorciatoie ⌘1 a ⌘9 per incollare nell'app precedente.",
        shortcutHint: "Fai clic su una riga per incollarla nell'app precedente. ⌘+clic ne seleziona diverse; ⌘C copia senza incollare.",
        clickRowShortcut: "Clic sulla riga",
        commandClickShortcut: "⌘ Clic",
        pinned: "Fissati",
        recent: "Recenti",
        pin: "Fissa",
        unpin: "Sblocca",
        clearRecent: "Cancella recenti",
        clearAll: "Cancella non fissati",
        empty: "Nessun testo salvato",
        disabled: "Attiva la cronologia per iniziare a salvare il testo copiato.",
        search: "Cerca testo copiato",
        copy: "Copia",
        copied: "Copiato",
        delete: "Elimina elemento",
        selectMultiple: "Aggiungi alla pila",
        unselectMultiple: "Rimuovi dalla pila",
        selectShortcutAction: "Seleziona",
        pasteSelectedFormat: "Incolla %d",
        copySelectedFormat: "Copia %d",
        clearSelection: "Cancella selezione",
        moveUp: "Sposta su",
        moveDown: "Sposta giù",
        noResults: "Nessun risultato",
        newestFirst: "Più recenti prima",
        active: "Salvataggio nuovo testo",
        includeImagesFiles: "Salva anche immagini e file copiati",
        includeImagesFilesCaption: "Le immagini entrano nella cronologia e i file vengono ricordati come collegamenti alla loro posizione. Fissali e incollali come qualsiasi testo.",
        imageEntryLabel: "Immagine",
        fileCountFormat: "%d file"
    )

    static let ja = ClipboardFeatureStrings(
        title: "クリップボード",
        enable: "クリップボード履歴を保存",
        caption: "コピーしたテキストを保存して、あとで再利用できます。すべてローカルに保存され、いつでも削除できます。",
        localNote: "すべてこのMacに残ります。大きすぎる項目は無視されます。",
        skipSensitive: "機密らしいテキストを無視",
        skipSensitiveCaption: "パスワード、トークン、キーに見える短い空白なしの文字列を保存しません。",
        limit: "上限",
        showInPanel: "パネルに表示",
        shortcut: "履歴ショートカット",
        shortcutCaption: "検索、固定項目、前のアプリへ貼り付ける ⌘1 から ⌘9 のショートカットを備えたクイックウインドウを開きます。",
        shortcutHint: "行をクリックすると前のアプリに貼り付けます。⌘クリックで複数選択、⌘C は貼り付けずにコピーします。",
        clickRowShortcut: "行をクリック",
        commandClickShortcut: "⌘ クリック",
        pinned: "固定済み",
        recent: "最近",
        pin: "固定",
        unpin: "固定解除",
        clearRecent: "最近を消去",
        clearAll: "未固定を消去",
        empty: "保存済みテキストなし",
        disabled: "履歴を有効にすると、コピーしたテキストを保存できます。",
        search: "コピーしたテキストを検索",
        copy: "コピー",
        copied: "コピー済み",
        delete: "項目を削除",
        selectMultiple: "束に追加",
        unselectMultiple: "束から削除",
        selectShortcutAction: "選択",
        pasteSelectedFormat: "%d件を貼り付け",
        copySelectedFormat: "%d件をコピー",
        clearSelection: "選択を解除",
        moveUp: "上へ移動",
        moveDown: "下へ移動",
        noResults: "結果なし",
        newestFirst: "新しい順",
        active: "新しいテキストを保存中",
        includeImagesFiles: "コピーした画像やファイルも保存",
        includeImagesFilesCaption: "画像は履歴に入り、ファイルは場所へのリンクとして記憶されます。テキストと同じようにピン留めやペーストができます。",
        imageEntryLabel: "画像",
        fileCountFormat: "%d個のファイル"
    )

    static let zhHans = ClipboardFeatureStrings(
        title: "剪贴板",
        enable: "保存剪贴板历史",
        caption: "保存复制过的文本，方便之后再次使用。所有内容都保存在本机，可随时清除。",
        localNote: "一切都保留在这台 Mac 上。特别大的内容会被忽略。",
        skipSensitive: "跳过疑似敏感文本",
        skipSensitiveCaption: "避免保存像密码、令牌或密钥的短文本。",
        limit: "数量上限",
        showInPanel: "在面板中显示",
        shortcut: "历史快捷键",
        shortcutCaption: "打开快速窗口，支持搜索、固定项目，以及用 ⌘1 到 ⌘9 粘贴到上一个 App。",
        shortcutHint: "点击整行即可粘贴到上一个 App。⌘+点击可选择多项；⌘C 仅复制不粘贴。",
        clickRowShortcut: "点击整行",
        commandClickShortcut: "⌘ 点击",
        pinned: "已固定",
        recent: "最近",
        pin: "固定",
        unpin: "取消固定",
        clearRecent: "清除最近项目",
        clearAll: "清除未固定项目",
        empty: "没有保存的文本",
        disabled: "启用历史记录后即可开始保存复制的文本。",
        search: "搜索复制的文本",
        copy: "复制",
        copied: "已复制",
        delete: "删除项目",
        selectMultiple: "加入堆叠",
        unselectMultiple: "从堆叠移除",
        selectShortcutAction: "选择",
        pasteSelectedFormat: "粘贴 %d 项",
        copySelectedFormat: "复制 %d 项",
        clearSelection: "清除选择",
        moveUp: "上移",
        moveDown: "下移",
        noResults: "没有结果",
        newestFirst: "最新优先",
        active: "正在保存新文本",
        includeImagesFiles: "同时保存复制的图片和文件",
        includeImagesFilesCaption: "图片会进入历史记录，文件会以其位置链接的形式被记住。可以像文本一样固定和粘贴。",
        imageEntryLabel: "图片",
        fileCountFormat: "%d 个文件"
    )

    static let zhTW = ClipboardFeatureStrings(
        title: "剪貼簿",
        enable: "儲存剪貼簿紀錄",
        caption: "儲存複製過的文字，方便之後再次使用。所有內容都會儲存在這台裝置上，並可隨時清除。",
        localNote: "一切都保留在這台 Mac 上。過大的內容會被略過。",
        skipSensitive: "略過可能含有敏感資料的文字",
        skipSensitiveCaption: "避免儲存像是密碼、權杖或金鑰這類較短的文字。",
        limit: "數量上限",
        showInPanel: "在面板中顯示",
        shortcut: "剪貼簿紀錄快速鍵",
        shortcutCaption: "開啟快速視窗，可搜尋、釘選項目，並使用 ⌘1 到 ⌘9 貼到上一個 App。",
        shortcutHint: "點選整列即可貼到上一個 App。⌘+點選可選取多個項目；⌘C 只複製不貼上。",
        clickRowShortcut: "點選整列",
        commandClickShortcut: "⌘ 點選",
        pinned: "已釘選",
        recent: "最近",
        pin: "釘選",
        unpin: "取消釘選",
        clearRecent: "清除最近項目",
        clearAll: "清除未釘選項目",
        empty: "沒有儲存的文字",
        disabled: "開啟紀錄後，即可開始儲存複製的文字。",
        search: "搜尋複製的文字",
        copy: "複製",
        copied: "已複製",
        delete: "刪除項目",
        selectMultiple: "加入堆疊",
        unselectMultiple: "從堆疊移除",
        selectShortcutAction: "選取",
        pasteSelectedFormat: "貼上 %d 個",
        copySelectedFormat: "拷貝 %d 個",
        clearSelection: "清除選取項目",
        moveUp: "上移",
        moveDown: "下移",
        noResults: "沒有結果",
        newestFirst: "最新優先",
        active: "正在儲存新文字",
        includeImagesFiles: "同時保存拷貝的圖片和檔案",
        includeImagesFilesCaption: "圖片會進入歷史記錄，檔案會以其位置連結的形式被記住。可以像文字一樣固定和貼上。",
        imageEntryLabel: "圖片",
        fileCountFormat: "%d 個檔案"
    )

    static let zhHK = ClipboardFeatureStrings(
        title: "剪貼簿",
        enable: "儲存剪貼簿記錄",
        caption: "儲存複製過的文字，方便之後再次使用。所有內容都會儲存在此裝置上，並可隨時清除。",
        localNote: "一切都保留在這部 Mac 上。過大的內容會被略過。",
        skipSensitive: "略過可能含有敏感資料的文字",
        skipSensitiveCaption: "避免儲存密碼、權杖或密鑰等較短文字。",
        limit: "數量上限",
        showInPanel: "在面板中顯示",
        shortcut: "剪貼簿記錄快捷鍵",
        shortcutCaption: "開啟快速視窗，可搜尋、釘選項目，並使用 ⌘1 至 ⌘9 貼到上一個 App。",
        shortcutHint: "按一下整列即可貼到上一個 App。⌘+按一下可選取多個項目；⌘C 只複製不貼上。",
        clickRowShortcut: "按一下整列",
        commandClickShortcut: "⌘ 按一下",
        pinned: "已釘選",
        recent: "最近",
        pin: "釘選",
        unpin: "取消釘選",
        clearRecent: "清除最近項目",
        clearAll: "清除未釘選項目",
        empty: "沒有已儲存的文字",
        disabled: "開啟記錄後，即可開始儲存複製的文字。",
        search: "搜尋複製的文字",
        copy: "複製",
        copied: "已複製",
        delete: "刪除項目",
        selectMultiple: "加入堆疊",
        unselectMultiple: "從堆疊移除",
        selectShortcutAction: "選取",
        pasteSelectedFormat: "貼上 %d 個",
        copySelectedFormat: "複製 %d 個",
        clearSelection: "清除所選項目",
        moveUp: "上移",
        moveDown: "下移",
        noResults: "沒有結果",
        newestFirst: "最新優先",
        active: "正在儲存新文字",
        includeImagesFiles: "同時儲存拷貝的圖片和檔案",
        includeImagesFilesCaption: "圖片會加入歷史記錄，檔案會以其位置連結的形式被記住。可以像文字一樣固定和貼上。",
        imageEntryLabel: "圖片",
        fileCountFormat: "%d 個檔案"
    )
}

struct WindowLayoutFeatureStrings {
    let title: String
    let caption: String
    let showInPanel: String
    let shortcuts: String
    let shortcutsCaption: String
    let permissionCaption: String
    let noWindow: String
    let missingPermission: String
    let failed: String
    let done: String
    let restored: String
    let noRestore: String
    let target: String
    let halves: String
    let thirds: String
    let sixths: String
    let corners: String
    let other: String
    let leftHalf: String
    let rightHalf: String
    let topHalf: String
    let bottomHalf: String
    let leftThird: String
    let centerThird: String
    let rightThird: String
    let leftTwoThirds: String
    let rightTwoThirds: String
    let topLeftSixth: String
    let topCenterSixth: String
    let topRightSixth: String
    let bottomLeftSixth: String
    let bottomCenterSixth: String
    let bottomRightSixth: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    let maximize: String
    let center: String
    let nextDisplay: String
    let restore: String

    static let enUS = WindowLayoutFeatureStrings(
        title: "Window layout",
        caption: "Moves the active window to halves, thirds, sixths, corners, another display, center or the usable screen.",
        showInPanel: "Show in panel",
        shortcuts: "Shortcuts",
        shortcutsCaption: "Use global shortcuts to arrange the active window without opening the panel.",
        permissionCaption: "Uses Accessibility to move only the active window.",
        noWindow: "No active window found.",
        missingPermission: "Grant Accessibility to move windows.",
        failed: "Could not move this window.",
        done: "Window arranged.",
        restored: "Window restored.",
        noRestore: "No previous layout to restore.",
        target: "Active window",
        halves: "Halves",
        thirds: "Thirds",
        sixths: "Sixths",
        corners: "Corners",
        other: "Actions",
        leftHalf: "Left",
        rightHalf: "Right",
        topHalf: "Top",
        bottomHalf: "Bottom",
        leftThird: "Left 1/3",
        centerThird: "Center 1/3",
        rightThird: "Right 1/3",
        leftTwoThirds: "Left 2/3",
        rightTwoThirds: "Right 2/3",
        topLeftSixth: "Top left 1/6",
        topCenterSixth: "Top center 1/6",
        topRightSixth: "Top right 1/6",
        bottomLeftSixth: "Bottom left 1/6",
        bottomCenterSixth: "Bottom center 1/6",
        bottomRightSixth: "Bottom right 1/6",
        topLeft: "Top left",
        topRight: "Top right",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        maximize: "Maximize",
        center: "Center",
        nextDisplay: "Next display",
        restore: "Restore"
    )

    static let ptBR = WindowLayoutFeatureStrings(
        title: "Layout de janelas",
        caption: "Reposiciona a janela ativa em metades, terços, sextos, cantos, outro display, centro ou tela útil.",
        showInPanel: "Mostrar no painel",
        shortcuts: "Atalhos",
        shortcutsCaption: "Use atalhos globais para organizar a janela ativa sem abrir o painel.",
        permissionCaption: "Usa Acessibilidade para mover apenas a janela ativa.",
        noWindow: "Nenhuma janela ativa encontrada.",
        missingPermission: "Conceda Acessibilidade para mover janelas.",
        failed: "Não foi possível mover esta janela.",
        done: "Janela organizada.",
        restored: "Janela restaurada.",
        noRestore: "Nenhum layout anterior para restaurar.",
        target: "Janela ativa",
        halves: "Metades",
        thirds: "Terços",
        sixths: "Sextos",
        corners: "Cantos",
        other: "Ações",
        leftHalf: "Esquerda",
        rightHalf: "Direita",
        topHalf: "Topo",
        bottomHalf: "Base",
        leftThird: "1/3 esquerda",
        centerThird: "1/3 centro",
        rightThird: "1/3 direita",
        leftTwoThirds: "2/3 esquerda",
        rightTwoThirds: "2/3 direita",
        topLeftSixth: "1/6 topo esquerdo",
        topCenterSixth: "1/6 topo central",
        topRightSixth: "1/6 topo direito",
        bottomLeftSixth: "1/6 base esquerda",
        bottomCenterSixth: "1/6 base central",
        bottomRightSixth: "1/6 base direita",
        topLeft: "Topo esquerdo",
        topRight: "Topo direito",
        bottomLeft: "Base esquerda",
        bottomRight: "Base direita",
        maximize: "Maximizar",
        center: "Centralizar",
        nextDisplay: "Próximo display",
        restore: "Restaurar"
    )

    static let tr = WindowLayoutFeatureStrings(
        title: "Pencere yerleşimi",
        caption: "Etkin pencereyi yarımlara, üçlü ve altılı bölümlere, köşelere, başka ekrana, merkeze veya kullanılabilir ekrana taşır.",
        showInPanel: "Panelde göster",
        shortcuts: "Kısayollar",
        shortcutsCaption: "Paneli açmadan etkin pencereyi düzenlemek için genel kısayollar kullan.",
        permissionCaption: "Yalnızca etkin pencereyi taşımak için Erişilebilirlik kullanır.",
        noWindow: "Etkin pencere bulunamadı.",
        missingPermission: "Pencereleri taşımak için Erişilebilirlik izni ver.",
        failed: "Bu pencere taşınamadı.",
        done: "Pencere yerleştirildi.",
        restored: "Pencere geri yüklendi.",
        noRestore: "Geri yüklenecek önceki yerleşim yok.",
        target: "Etkin pencere",
        halves: "Yarımlar",
        thirds: "Üçlüler",
        sixths: "Altıda birler",
        corners: "Köşeler",
        other: "Eylemler",
        leftHalf: "Sol",
        rightHalf: "Sağ",
        topHalf: "Üst",
        bottomHalf: "Alt",
        leftThird: "Sol 1/3",
        centerThird: "Orta 1/3",
        rightThird: "Sağ 1/3",
        leftTwoThirds: "Sol 2/3",
        rightTwoThirds: "Sağ 2/3",
        topLeftSixth: "Sol üst 1/6",
        topCenterSixth: "Üst orta 1/6",
        topRightSixth: "Sağ üst 1/6",
        bottomLeftSixth: "Sol alt 1/6",
        bottomCenterSixth: "Alt orta 1/6",
        bottomRightSixth: "Sağ alt 1/6",
        topLeft: "Sol üst",
        topRight: "Sağ üst",
        bottomLeft: "Sol alt",
        bottomRight: "Sağ alt",
        maximize: "Büyüt",
        center: "Ortala",
        nextDisplay: "Sonraki ekran",
        restore: "Geri yükle"
    )

    static let ru = WindowLayoutFeatureStrings(
        title: "Раскладка окон",
        caption: "Перемещает активное окно в половины, трети, шестые части, углы, на другой дисплей, в центр или в полезную область экрана.",
        showInPanel: "Показывать в панели",
        shortcuts: "Горячие клавиши",
        shortcutsCaption: "Используйте глобальные сочетания клавиш, чтобы раскладывать активное окно без открытия панели.",
        permissionCaption: "Использует Универсальный доступ, чтобы перемещать только активное окно.",
        noWindow: "Активное окно не найдено.",
        missingPermission: "Выдайте Универсальный доступ для управления окнами.",
        failed: "Не удалось переместить это окно.",
        done: "Окно размещено.",
        restored: "Окно восстановлено.",
        noRestore: "Нет предыдущей раскладки для восстановления.",
        target: "Активное окно",
        halves: "Половины",
        thirds: "Трети",
        sixths: "Шестые",
        corners: "Углы",
        other: "Действия",
        leftHalf: "Левая половина",
        rightHalf: "Правая половина",
        topHalf: "Верхняя половина",
        bottomHalf: "Нижняя половина",
        leftThird: "Левая 1/3",
        centerThird: "Центр 1/3",
        rightThird: "Правая 1/3",
        leftTwoThirds: "Левые 2/3",
        rightTwoThirds: "Правые 2/3",
        topLeftSixth: "1/6 слева сверху",
        topCenterSixth: "1/6 сверху по центру",
        topRightSixth: "1/6 справа сверху",
        bottomLeftSixth: "1/6 слева снизу",
        bottomCenterSixth: "1/6 снизу по центру",
        bottomRightSixth: "1/6 справа снизу",
        topLeft: "Верхний левый угол",
        topRight: "Верхний правый угол",
        bottomLeft: "Нижний левый угол",
        bottomRight: "Нижний правый угол",
        maximize: "Развернуть",
        center: "По центру",
        nextDisplay: "Следующий дисплей",
        restore: "Восстановить"
    )

    static let es = WindowLayoutFeatureStrings(
        title: "Diseño de ventanas",
        caption: "Mueve la ventana activa a mitades, tercios, sextos, esquinas, otra pantalla, el centro o el área útil.",
        showInPanel: "Mostrar en el panel",
        shortcuts: "Atajos",
        shortcutsCaption: "Usa atajos globales para organizar la ventana activa sin abrir el panel.",
        permissionCaption: "Usa Accesibilidad para mover solo la ventana activa.",
        noWindow: "No se encontró una ventana activa.",
        missingPermission: "Concede Accesibilidad para mover ventanas.",
        failed: "No se pudo mover esta ventana.",
        done: "Ventana organizada.",
        restored: "Ventana restaurada.",
        noRestore: "No hay un diseño anterior para restaurar.",
        target: "Ventana activa",
        halves: "Mitades",
        thirds: "Tercios",
        sixths: "Sextos",
        corners: "Esquinas",
        other: "Acciones",
        leftHalf: "Izquierda",
        rightHalf: "Derecha",
        topHalf: "Arriba",
        bottomHalf: "Abajo",
        leftThird: "1/3 izquierda",
        centerThird: "1/3 centro",
        rightThird: "1/3 derecha",
        leftTwoThirds: "2/3 izquierda",
        rightTwoThirds: "2/3 derecha",
        topLeftSixth: "1/6 arriba izquierda",
        topCenterSixth: "1/6 arriba centro",
        topRightSixth: "1/6 arriba derecha",
        bottomLeftSixth: "1/6 abajo izquierda",
        bottomCenterSixth: "1/6 abajo centro",
        bottomRightSixth: "1/6 abajo derecha",
        topLeft: "Arriba izquierda",
        topRight: "Arriba derecha",
        bottomLeft: "Abajo izquierda",
        bottomRight: "Abajo derecha",
        maximize: "Maximizar",
        center: "Centrar",
        nextDisplay: "Siguiente pantalla",
        restore: "Restaurar"
    )

    static let de = WindowLayoutFeatureStrings(
        title: "Fensterlayout",
        caption: "Verschiebt das aktive Fenster in Hälften, Drittel, Sechstel, Ecken, auf ein anderes Display, in die Mitte oder auf die nutzbare Fläche.",
        showInPanel: "Im Panel anzeigen",
        shortcuts: "Kurzbefehle",
        shortcutsCaption: "Nutze globale Kurzbefehle, um das aktive Fenster ohne Panel zu arrangieren.",
        permissionCaption: "Nutzt Bedienungshilfen, um nur das aktive Fenster zu bewegen.",
        noWindow: "Kein aktives Fenster gefunden.",
        missingPermission: "Erlaube Bedienungshilfen, um Fenster zu bewegen.",
        failed: "Dieses Fenster konnte nicht bewegt werden.",
        done: "Fenster arrangiert.",
        restored: "Fenster wiederhergestellt.",
        noRestore: "Kein vorheriges Layout zum Wiederherstellen.",
        target: "Aktives Fenster",
        halves: "Hälften",
        thirds: "Drittel",
        sixths: "Sechstel",
        corners: "Ecken",
        other: "Aktionen",
        leftHalf: "Links",
        rightHalf: "Rechts",
        topHalf: "Oben",
        bottomHalf: "Unten",
        leftThird: "Linkes 1/3",
        centerThird: "Mittleres 1/3",
        rightThird: "Rechtes 1/3",
        leftTwoThirds: "Linke 2/3",
        rightTwoThirds: "Rechte 2/3",
        topLeftSixth: "1/6 oben links",
        topCenterSixth: "1/6 oben mittig",
        topRightSixth: "1/6 oben rechts",
        bottomLeftSixth: "1/6 unten links",
        bottomCenterSixth: "1/6 unten mittig",
        bottomRightSixth: "1/6 unten rechts",
        topLeft: "Oben links",
        topRight: "Oben rechts",
        bottomLeft: "Unten links",
        bottomRight: "Unten rechts",
        maximize: "Maximieren",
        center: "Zentrieren",
        nextDisplay: "Nächstes Display",
        restore: "Wiederherstellen"
    )

    static let fr = WindowLayoutFeatureStrings(
        title: "Disposition des fenêtres",
        caption: "Déplace la fenêtre active vers les moitiés, tiers, sixièmes, coins, un autre écran, le centre ou la zone utile.",
        showInPanel: "Afficher dans le panneau",
        shortcuts: "Raccourcis",
        shortcutsCaption: "Utilisez des raccourcis globaux pour organiser la fenêtre active sans ouvrir le panneau.",
        permissionCaption: "Utilise Accessibilité pour déplacer uniquement la fenêtre active.",
        noWindow: "Aucune fenêtre active trouvée.",
        missingPermission: "Autorisez Accessibilité pour déplacer les fenêtres.",
        failed: "Impossible de déplacer cette fenêtre.",
        done: "Fenêtre organisée.",
        restored: "Fenêtre restaurée.",
        noRestore: "Aucune disposition précédente à restaurer.",
        target: "Fenêtre active",
        halves: "Moitiés",
        thirds: "Tiers",
        sixths: "Sixièmes",
        corners: "Coins",
        other: "Actions",
        leftHalf: "Gauche",
        rightHalf: "Droite",
        topHalf: "Haut",
        bottomHalf: "Bas",
        leftThird: "1/3 gauche",
        centerThird: "1/3 centre",
        rightThird: "1/3 droite",
        leftTwoThirds: "2/3 gauche",
        rightTwoThirds: "2/3 droite",
        topLeftSixth: "1/6 en haut à gauche",
        topCenterSixth: "1/6 en haut au centre",
        topRightSixth: "1/6 en haut à droite",
        bottomLeftSixth: "1/6 en bas à gauche",
        bottomCenterSixth: "1/6 en bas au centre",
        bottomRightSixth: "1/6 en bas à droite",
        topLeft: "Haut gauche",
        topRight: "Haut droite",
        bottomLeft: "Bas gauche",
        bottomRight: "Bas droite",
        maximize: "Agrandir",
        center: "Centrer",
        nextDisplay: "Écran suivant",
        restore: "Restaurer"
    )

    static let it = WindowLayoutFeatureStrings(
        title: "Layout finestre",
        caption: "Sposta la finestra attiva in metà, terzi, sesti, angoli, su un altro display, al centro o nell'area utilizzabile.",
        showInPanel: "Mostra nel pannello",
        shortcuts: "Scorciatoie",
        shortcutsCaption: "Usa scorciatoie globali per organizzare la finestra attiva senza aprire il pannello.",
        permissionCaption: "Usa Accessibilità per spostare solo la finestra attiva.",
        noWindow: "Nessuna finestra attiva trovata.",
        missingPermission: "Concedi Accessibilità per spostare le finestre.",
        failed: "Impossibile spostare questa finestra.",
        done: "Finestra organizzata.",
        restored: "Finestra ripristinata.",
        noRestore: "Nessun layout precedente da ripristinare.",
        target: "Finestra attiva",
        halves: "Metà",
        thirds: "Terzi",
        sixths: "Sesti",
        corners: "Angoli",
        other: "Azioni",
        leftHalf: "Sinistra",
        rightHalf: "Destra",
        topHalf: "Alto",
        bottomHalf: "Basso",
        leftThird: "1/3 sinistra",
        centerThird: "1/3 centro",
        rightThird: "1/3 destra",
        leftTwoThirds: "2/3 sinistra",
        rightTwoThirds: "2/3 destra",
        topLeftSixth: "1/6 in alto a sinistra",
        topCenterSixth: "1/6 in alto al centro",
        topRightSixth: "1/6 in alto a destra",
        bottomLeftSixth: "1/6 in basso a sinistra",
        bottomCenterSixth: "1/6 in basso al centro",
        bottomRightSixth: "1/6 in basso a destra",
        topLeft: "Alto sinistra",
        topRight: "Alto destra",
        bottomLeft: "Basso sinistra",
        bottomRight: "Basso destra",
        maximize: "Massimizza",
        center: "Centra",
        nextDisplay: "Display successivo",
        restore: "Ripristina"
    )

    static let ja = WindowLayoutFeatureStrings(
        title: "ウインドウ配置",
        caption: "アクティブなウインドウを半分、3分割、6分割、四隅、別のディスプレイ、中央、または作業領域に移動します。",
        showInPanel: "パネルに表示",
        shortcuts: "ショートカット",
        shortcutsCaption: "パネルを開かずにグローバルショートカットでアクティブなウインドウを配置します。",
        permissionCaption: "アクセシビリティを使い、アクティブなウインドウだけを移動します。",
        noWindow: "アクティブなウインドウが見つかりません。",
        missingPermission: "ウインドウを移動するにはアクセシビリティを許可してください。",
        failed: "このウインドウを移動できませんでした。",
        done: "ウインドウを配置しました。",
        restored: "ウインドウを復元しました。",
        noRestore: "復元できる前回の配置はありません。",
        target: "アクティブなウインドウ",
        halves: "半分",
        thirds: "3分割",
        sixths: "6分割",
        corners: "四隅",
        other: "操作",
        leftHalf: "左",
        rightHalf: "右",
        topHalf: "上",
        bottomHalf: "下",
        leftThird: "左 1/3",
        centerThird: "中央 1/3",
        rightThird: "右 1/3",
        leftTwoThirds: "左 2/3",
        rightTwoThirds: "右 2/3",
        topLeftSixth: "左上 1/6",
        topCenterSixth: "上中央 1/6",
        topRightSixth: "右上 1/6",
        bottomLeftSixth: "左下 1/6",
        bottomCenterSixth: "下中央 1/6",
        bottomRightSixth: "右下 1/6",
        topLeft: "左上",
        topRight: "右上",
        bottomLeft: "左下",
        bottomRight: "右下",
        maximize: "最大化",
        center: "中央",
        nextDisplay: "次のディスプレイ",
        restore: "復元"
    )

    static let zhHans = WindowLayoutFeatureStrings(
        title: "窗口布局",
        caption: "将当前窗口移动到半屏、三分屏、六分屏、角落、另一台显示器、居中位置或可用屏幕区域。",
        showInPanel: "在面板中显示",
        shortcuts: "快捷键",
        shortcutsCaption: "使用全局快捷键整理当前窗口，无需打开面板。",
        permissionCaption: "使用辅助功能权限，仅移动当前窗口。",
        noWindow: "未找到当前窗口。",
        missingPermission: "请授予辅助功能权限以移动窗口。",
        failed: "无法移动此窗口。",
        done: "窗口已整理。",
        restored: "窗口已恢复。",
        noRestore: "没有可恢复的上一个布局。",
        target: "当前窗口",
        halves: "半屏",
        thirds: "三分屏",
        sixths: "六分屏",
        corners: "角落",
        other: "操作",
        leftHalf: "左半屏",
        rightHalf: "右半屏",
        topHalf: "上半屏",
        bottomHalf: "下半屏",
        leftThird: "左侧 1/3",
        centerThird: "中间 1/3",
        rightThird: "右侧 1/3",
        leftTwoThirds: "左侧 2/3",
        rightTwoThirds: "右侧 2/3",
        topLeftSixth: "左上 1/6",
        topCenterSixth: "上中 1/6",
        topRightSixth: "右上 1/6",
        bottomLeftSixth: "左下 1/6",
        bottomCenterSixth: "下中 1/6",
        bottomRightSixth: "右下 1/6",
        topLeft: "左上角",
        topRight: "右上角",
        bottomLeft: "左下角",
        bottomRight: "右下角",
        maximize: "最大化",
        center: "居中",
        nextDisplay: "下一台显示器",
        restore: "恢复"
    )

    static let zhTW = WindowLayoutFeatureStrings(
        title: "視窗排列",
        caption: "將目前視窗移到半邊、三等分、六等分、角落、另一台顯示器、置中位置或可用螢幕範圍。",
        showInPanel: "在面板中顯示",
        shortcuts: "快速鍵",
        shortcutsCaption: "使用全域快速鍵整理目前視窗，不需要打開面板。",
        permissionCaption: "使用輔助使用權限，只會移動目前視窗。",
        noWindow: "找不到目前視窗。",
        missingPermission: "請允許輔助使用權限以移動視窗。",
        failed: "無法移動此視窗。",
        done: "視窗已整理。",
        restored: "視窗已還原。",
        noRestore: "沒有可還原的上一個排列方式。",
        target: "目前視窗",
        halves: "半邊",
        thirds: "三等分",
        sixths: "六等分",
        corners: "角落",
        other: "其他操作",
        leftHalf: "左半邊",
        rightHalf: "右半邊",
        topHalf: "上半邊",
        bottomHalf: "下半邊",
        leftThird: "左側 1/3",
        centerThird: "中間 1/3",
        rightThird: "右側 1/3",
        leftTwoThirds: "左側 2/3",
        rightTwoThirds: "右側 2/3",
        topLeftSixth: "左上 1/6",
        topCenterSixth: "上方中央 1/6",
        topRightSixth: "右上 1/6",
        bottomLeftSixth: "左下 1/6",
        bottomCenterSixth: "下方中央 1/6",
        bottomRightSixth: "右下 1/6",
        topLeft: "左上角",
        topRight: "右上角",
        bottomLeft: "左下角",
        bottomRight: "右下角",
        maximize: "最大化",
        center: "置中",
        nextDisplay: "下一台顯示器",
        restore: "還原"
    )

    static let zhHK = WindowLayoutFeatureStrings(
        title: "視窗排列",
        caption: "將目前視窗移到半邊、三等分、六等分、角落、另一部顯示器、置中位置或可用螢幕範圍。",
        showInPanel: "在面板中顯示",
        shortcuts: "快捷鍵",
        shortcutsCaption: "使用全域快捷鍵整理目前視窗，毋須打開面板。",
        permissionCaption: "使用輔助使用權限，只會移動目前視窗。",
        noWindow: "找不到目前視窗。",
        missingPermission: "請同意輔助使用權限以移動視窗。",
        failed: "無法移動此視窗。",
        done: "視窗已整理。",
        restored: "視窗已還原。",
        noRestore: "沒有可還原的上一個排列方式。",
        target: "目前視窗",
        halves: "半邊",
        thirds: "三等分",
        sixths: "六等分",
        corners: "角落",
        other: "其他操作",
        leftHalf: "左半邊",
        rightHalf: "右半邊",
        topHalf: "上半邊",
        bottomHalf: "下半邊",
        leftThird: "左側 1/3",
        centerThird: "中間 1/3",
        rightThird: "右側 1/3",
        leftTwoThirds: "左側 2/3",
        rightTwoThirds: "右側 2/3",
        topLeftSixth: "左上 1/6",
        topCenterSixth: "上方中央 1/6",
        topRightSixth: "右上 1/6",
        bottomLeftSixth: "左下 1/6",
        bottomCenterSixth: "下方中央 1/6",
        bottomRightSixth: "右下 1/6",
        topLeft: "左上角",
        topRight: "右上角",
        bottomLeft: "左下角",
        bottomRight: "右下角",
        maximize: "最大化",
        center: "置中",
        nextDisplay: "下一部顯示器",
        restore: "還原"
    )
}

struct MonitorAlertFeatureStrings {
    let section: String
    let caption: String
    let notificationsDenied: String
    let cpu: String
    let cpuTemperature: String
    let memory: String
    let disk: String
    let battery: String
    let cpuThreshold: String
    let cpuTemperatureThreshold: String
    let diskThreshold: String
    let batteryThreshold: String
    let cooldown: String
    let cooldown2: String
    let cooldown5: String
    let cooldown15: String
    let cooldown30: String
    let cooldown60: String
    let cpuTitle: String
    let cpuBodyFormat: String
    let cpuTemperatureTitle: String
    let cpuTemperatureBodyFormat: String
    let memoryTitle: String
    let memoryBody: String
    let diskTitle: String
    let diskBodyFormat: String
    let batteryTitle: String
    let batteryBodyFormat: String

    static let enUS = MonitorAlertFeatureStrings(
        section: "Alerts",
        caption: "Off by default. When enabled, Monitor warns only after a useful condition and respects the alert interval.",
        notificationsDenied: "Notifications for Vorssaint are off in System Settings, so alerts cannot appear.",
        cpu: "High CPU",
        cpuTemperature: "High CPU temperature",
        memory: "Critical memory pressure",
        disk: "Low disk space",
        battery: "Low battery",
        cpuThreshold: "CPU above",
        cpuTemperatureThreshold: "Temperature above",
        diskThreshold: "Free space below",
        batteryThreshold: "Battery below",
        cooldown: "Alert interval",
        cooldown2: "2 minutes",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 hour",
        cpuTitle: "High CPU",
        cpuBodyFormat: "CPU stayed above %d%% for a few seconds.",
        cpuTemperatureTitle: "Hot CPU",
        cpuTemperatureBodyFormat: "CPU reached %d °C.",
        memoryTitle: "Critical memory",
        memoryBody: "Memory pressure reached the critical level.",
        diskTitle: "Low disk space",
        diskBodyFormat: "%@ has less than %d%% free.",
        batteryTitle: "Low battery",
        batteryBodyFormat: "Battery is at %d%%."
    )

    static let ptBR = MonitorAlertFeatureStrings(
        section: "Alertas",
        caption: "Desligado por padrão. Quando ligado, o Monitor avisa só depois de uma condição relevante e respeita o intervalo entre avisos.",
        notificationsDenied: "As notificações do Vorssaint estão desativadas nos Ajustes do Sistema, então os alertas não aparecem.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura alta da CPU",
        memory: "Pressão de memória crítica",
        disk: "Pouco espaço em disco",
        battery: "Bateria baixa",
        cpuThreshold: "CPU acima de",
        cpuTemperatureThreshold: "Temperatura acima de",
        diskThreshold: "Espaço livre abaixo de",
        batteryThreshold: "Bateria abaixo de",
        cooldown: "Intervalo entre avisos",
        cooldown2: "2 minutos",
        cooldown5: "5 minutos",
        cooldown15: "15 minutos",
        cooldown30: "30 minutos",
        cooldown60: "1 hora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "A CPU ficou acima de %d%% por alguns segundos.",
        cpuTemperatureTitle: "CPU quente",
        cpuTemperatureBodyFormat: "A CPU chegou a %d °C.",
        memoryTitle: "Memória crítica",
        memoryBody: "A pressão de memória chegou ao nível crítico.",
        diskTitle: "Pouco espaço em disco",
        diskBodyFormat: "%@ está com menos de %d%% livre.",
        batteryTitle: "Bateria baixa",
        batteryBodyFormat: "A bateria está em %d%%."
    )

    static let tr = MonitorAlertFeatureStrings(
        section: "Uyarılar",
        caption: "Varsayılan olarak kapalıdır. Etkinleştirildiğinde Monitör yalnızca anlamlı bir koşuldan sonra uyarır ve uyarı aralığına uyar.",
        notificationsDenied: "Sistem Ayarları'nda Vorssaint bildirimleri kapalı, bu yüzden uyarılar görünemez.",
        cpu: "Yüksek CPU",
        cpuTemperature: "Yüksek CPU sıcaklığı",
        memory: "Kritik bellek basıncı",
        disk: "Düşük disk alanı",
        battery: "Düşük pil",
        cpuThreshold: "CPU şu değerin üstünde",
        cpuTemperatureThreshold: "Sıcaklık şu değerin üstünde",
        diskThreshold: "Boş alan şu değerin altında",
        batteryThreshold: "Pil şu değerin altında",
        cooldown: "Uyarı aralığı",
        cooldown2: "2 dakika",
        cooldown5: "5 dakika",
        cooldown15: "15 dakika",
        cooldown30: "30 dakika",
        cooldown60: "1 saat",
        cpuTitle: "Yüksek CPU",
        cpuBodyFormat: "CPU birkaç saniye boyunca %d%% üzerinde kaldı.",
        cpuTemperatureTitle: "CPU sıcak",
        cpuTemperatureBodyFormat: "CPU %d °C değerine ulaştı.",
        memoryTitle: "Kritik bellek",
        memoryBody: "Bellek basıncı kritik seviyeye ulaştı.",
        diskTitle: "Düşük disk alanı",
        diskBodyFormat: "%@ diskinde %d%% altında boş alan var.",
        batteryTitle: "Düşük pil",
        batteryBodyFormat: "Pil %d%% seviyesinde."
    )

    static let ru = MonitorAlertFeatureStrings(
        section: "Оповещения",
        caption: "По умолчанию выключено. Когда функция включена, Monitor предупреждает только после полезного условия и соблюдает интервал между оповещениями.",
        notificationsDenied: "Уведомления Vorssaint выключены в Системных настройках, поэтому оповещения не появятся.",
        cpu: "Высокая нагрузка CPU",
        cpuTemperature: "Высокая температура CPU",
        memory: "Критическое давление памяти",
        disk: "Мало места на диске",
        battery: "Низкий заряд батареи",
        cpuThreshold: "CPU выше",
        cpuTemperatureThreshold: "Температура выше",
        diskThreshold: "Свободного места меньше",
        batteryThreshold: "Батарея ниже",
        cooldown: "Интервал оповещений",
        cooldown2: "2 минуты",
        cooldown5: "5 минут",
        cooldown15: "15 минут",
        cooldown30: "30 минут",
        cooldown60: "1 час",
        cpuTitle: "Высокая нагрузка CPU",
        cpuBodyFormat: "CPU держался выше %d%% несколько секунд.",
        cpuTemperatureTitle: "CPU перегрет",
        cpuTemperatureBodyFormat: "CPU достиг %d °C.",
        memoryTitle: "Критическая память",
        memoryBody: "Давление памяти достигло критического уровня.",
        diskTitle: "Мало места на диске",
        diskBodyFormat: "На %@ осталось меньше %d%% свободного места.",
        batteryTitle: "Низкий заряд батареи",
        batteryBodyFormat: "Заряд батареи: %d%%."
    )

    static let es = MonitorAlertFeatureStrings(
        section: "Alertas",
        caption: "Desactivado por defecto. Al activarlo, Monitor avisa solo tras una condición relevante y respeta el intervalo entre avisos.",
        notificationsDenied: "Las notificaciones de Vorssaint están desactivadas en Ajustes del Sistema, así que las alertas no aparecen.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura de CPU alta",
        memory: "Presión de memoria crítica",
        disk: "Poco espacio en disco",
        battery: "Batería baja",
        cpuThreshold: "CPU por encima de",
        cpuTemperatureThreshold: "Temperatura por encima de",
        diskThreshold: "Espacio libre por debajo de",
        batteryThreshold: "Batería por debajo de",
        cooldown: "Intervalo entre avisos",
        cooldown2: "2 minutos",
        cooldown5: "5 minutos",
        cooldown15: "15 minutos",
        cooldown30: "30 minutos",
        cooldown60: "1 hora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "La CPU estuvo por encima de %d%% durante unos segundos.",
        cpuTemperatureTitle: "CPU caliente",
        cpuTemperatureBodyFormat: "La CPU llegó a %d °C.",
        memoryTitle: "Memoria crítica",
        memoryBody: "La presión de memoria llegó al nivel crítico.",
        diskTitle: "Poco espacio en disco",
        diskBodyFormat: "%@ tiene menos de %d%% libre.",
        batteryTitle: "Batería baja",
        batteryBodyFormat: "La batería está al %d%%."
    )

    static let de = MonitorAlertFeatureStrings(
        section: "Warnungen",
        caption: "Standardmäßig aus. Wenn aktiviert, warnt der Monitor nur nach einem relevanten Zustand und beachtet das Warnintervall.",
        notificationsDenied: "Mitteilungen für Vorssaint sind in den Systemeinstellungen aus, daher können keine Warnungen erscheinen.",
        cpu: "Hohe CPU",
        cpuTemperature: "Hohe CPU-Temperatur",
        memory: "Kritischer Speicherdruck",
        disk: "Wenig Speicherplatz",
        battery: "Niedriger Akkustand",
        cpuThreshold: "CPU über",
        cpuTemperatureThreshold: "Temperatur über",
        diskThreshold: "Freier Platz unter",
        batteryThreshold: "Akku unter",
        cooldown: "Warnintervall",
        cooldown2: "2 Minuten",
        cooldown5: "5 Minuten",
        cooldown15: "15 Minuten",
        cooldown30: "30 Minuten",
        cooldown60: "1 Stunde",
        cpuTitle: "Hohe CPU",
        cpuBodyFormat: "Die CPU lag einige Sekunden über %d%%.",
        cpuTemperatureTitle: "Heiße CPU",
        cpuTemperatureBodyFormat: "Die CPU hat %d °C erreicht.",
        memoryTitle: "Kritischer Speicher",
        memoryBody: "Der Speicherdruck hat den kritischen Wert erreicht.",
        diskTitle: "Wenig Speicherplatz",
        diskBodyFormat: "%@ hat weniger als %d%% frei.",
        batteryTitle: "Niedriger Akkustand",
        batteryBodyFormat: "Der Akku ist bei %d%%."
    )

    static let fr = MonitorAlertFeatureStrings(
        section: "Alertes",
        caption: "Désactivé par défaut. Une fois activé, Monitor avertit seulement après une condition utile et respecte l'intervalle d'alerte.",
        notificationsDenied: "Les notifications de Vorssaint sont désactivées dans Réglages Système, les alertes ne peuvent donc pas apparaître.",
        cpu: "CPU élevé",
        cpuTemperature: "Température CPU élevée",
        memory: "Pression mémoire critique",
        disk: "Espace disque faible",
        battery: "Batterie faible",
        cpuThreshold: "CPU au-dessus de",
        cpuTemperatureThreshold: "Température au-dessus de",
        diskThreshold: "Espace libre sous",
        batteryThreshold: "Batterie sous",
        cooldown: "Intervalle d'alerte",
        cooldown2: "2 minutes",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 heure",
        cpuTitle: "CPU élevé",
        cpuBodyFormat: "Le CPU est resté au-dessus de %d%% pendant quelques secondes.",
        cpuTemperatureTitle: "CPU chaud",
        cpuTemperatureBodyFormat: "Le CPU a atteint %d °C.",
        memoryTitle: "Mémoire critique",
        memoryBody: "La pression mémoire a atteint le niveau critique.",
        diskTitle: "Espace disque faible",
        diskBodyFormat: "%@ a moins de %d%% libre.",
        batteryTitle: "Batterie faible",
        batteryBodyFormat: "La batterie est à %d%%."
    )

    static let it = MonitorAlertFeatureStrings(
        section: "Avvisi",
        caption: "Disattivato per impostazione predefinita. Quando attivo, Monitor avvisa solo dopo una condizione utile e rispetta l'intervallo tra gli avvisi.",
        notificationsDenied: "Le notifiche di Vorssaint sono disattivate in Impostazioni di Sistema, quindi gli avvisi non compaiono.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura CPU alta",
        memory: "Pressione memoria critica",
        disk: "Poco spazio su disco",
        battery: "Batteria scarica",
        cpuThreshold: "CPU sopra",
        cpuTemperatureThreshold: "Temperatura sopra",
        diskThreshold: "Spazio libero sotto",
        batteryThreshold: "Batteria sotto",
        cooldown: "Intervallo avvisi",
        cooldown2: "2 minuti",
        cooldown5: "5 minuti",
        cooldown15: "15 minuti",
        cooldown30: "30 minuti",
        cooldown60: "1 ora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "La CPU è rimasta sopra %d%% per alcuni secondi.",
        cpuTemperatureTitle: "CPU calda",
        cpuTemperatureBodyFormat: "La CPU ha raggiunto %d °C.",
        memoryTitle: "Memoria critica",
        memoryBody: "La pressione della memoria ha raggiunto il livello critico.",
        diskTitle: "Poco spazio su disco",
        diskBodyFormat: "%@ ha meno del %d%% libero.",
        batteryTitle: "Batteria scarica",
        batteryBodyFormat: "La batteria è al %d%%."
    )

    static let ja = MonitorAlertFeatureStrings(
        section: "アラート",
        caption: "デフォルトではオフです。有効にすると、Monitor は意味のある状態が続いた場合だけ通知し、通知間隔を守ります。",
        notificationsDenied: "システム設定でVorssaintの通知がオフのため、アラートは表示されません。",
        cpu: "CPU 高負荷",
        cpuTemperature: "CPU 温度が高い",
        memory: "メモリ圧迫が深刻",
        disk: "ディスク空き容量不足",
        battery: "バッテリー残量低下",
        cpuThreshold: "CPU が次を超過",
        cpuTemperatureThreshold: "温度が次を超過",
        diskThreshold: "空き容量が次を下回る",
        batteryThreshold: "バッテリーが次を下回る",
        cooldown: "通知間隔",
        cooldown2: "2 分",
        cooldown5: "5 分",
        cooldown15: "15 分",
        cooldown30: "30 分",
        cooldown60: "1 時間",
        cpuTitle: "CPU 高負荷",
        cpuBodyFormat: "CPU が数秒間 %d%% を超えました。",
        cpuTemperatureTitle: "CPU が高温",
        cpuTemperatureBodyFormat: "CPU が %d °C に達しました。",
        memoryTitle: "メモリが深刻",
        memoryBody: "メモリ圧迫が深刻レベルに達しました。",
        diskTitle: "ディスク空き容量不足",
        diskBodyFormat: "%@ の空き容量が %d%% 未満です。",
        batteryTitle: "バッテリー残量低下",
        batteryBodyFormat: "バッテリー残量は %d%% です。"
    )

    static let zhHans = MonitorAlertFeatureStrings(
        section: "提醒",
        caption: "默认关闭。启用后，监视器只会在出现有意义的状态时提醒，并遵守提醒间隔。",
        notificationsDenied: "Vorssaint 的通知已在系统设置中关闭，警报无法显示。",
        cpu: "CPU 过高",
        cpuTemperature: "CPU 温度过高",
        memory: "内存压力严重",
        disk: "磁盘空间不足",
        battery: "电池电量低",
        cpuThreshold: "CPU 高于",
        cpuTemperatureThreshold: "温度高于",
        diskThreshold: "可用空间低于",
        batteryThreshold: "电量低于",
        cooldown: "提醒间隔",
        cooldown2: "2 分钟",
        cooldown5: "5 分钟",
        cooldown15: "15 分钟",
        cooldown30: "30 分钟",
        cooldown60: "1 小时",
        cpuTitle: "CPU 过高",
        cpuBodyFormat: "CPU 已连续几秒高于 %d%%。",
        cpuTemperatureTitle: "CPU 过热",
        cpuTemperatureBodyFormat: "CPU 已达到 %d °C。",
        memoryTitle: "内存严重",
        memoryBody: "内存压力已达到严重级别。",
        diskTitle: "磁盘空间不足",
        diskBodyFormat: "%@ 的可用空间低于 %d%%。",
        batteryTitle: "电池电量低",
        batteryBodyFormat: "电池电量为 %d%%。"
    )

    static let zhTW = MonitorAlertFeatureStrings(
        section: "提醒",
        caption: "預設為關閉。開啟後，監控功能只會在出現需要注意的狀態時提醒，並依照提醒間隔發送通知。",
        notificationsDenied: "Vorssaint 的通知已在系統設定中關閉，警示無法顯示。",
        cpu: "CPU 使用率過高",
        cpuTemperature: "CPU 溫度過高",
        memory: "記憶體壓力過高",
        disk: "磁碟空間不足",
        battery: "電池電量偏低",
        cpuThreshold: "CPU 高於",
        cpuTemperatureThreshold: "溫度高於",
        diskThreshold: "可用空間低於",
        batteryThreshold: "電量低於",
        cooldown: "提醒間隔",
        cooldown2: "2 分鐘",
        cooldown5: "5 分鐘",
        cooldown15: "15 分鐘",
        cooldown30: "30 分鐘",
        cooldown60: "1 小時",
        cpuTitle: "CPU 使用率過高",
        cpuBodyFormat: "CPU 已連續數秒高於 %d%%。",
        cpuTemperatureTitle: "CPU 過熱",
        cpuTemperatureBodyFormat: "CPU 已達到 %d °C。",
        memoryTitle: "記憶體壓力過高",
        memoryBody: "記憶體壓力已達到嚴重等級。",
        diskTitle: "磁碟空間不足",
        diskBodyFormat: "%@ 的可用空間低於 %d%%。",
        batteryTitle: "電池電量偏低",
        batteryBodyFormat: "電池電量為 %d%%。"
    )

    static let zhHK = MonitorAlertFeatureStrings(
        section: "提示",
        caption: "預設為關閉。開啟後，監察功能只會在出現需要注意的狀態時提示，並會遵循提示間隔。",
        notificationsDenied: "Vorssaint 的通知已在系統設定中關閉，警示無法顯示。",
        cpu: "CPU 使用率過高",
        cpuTemperature: "CPU 溫度過高",
        memory: "記憶體壓力過高",
        disk: "磁碟空間不足",
        battery: "電池電量偏低",
        cpuThreshold: "CPU 高於",
        cpuTemperatureThreshold: "溫度高於",
        diskThreshold: "可用空間低於",
        batteryThreshold: "電量低於",
        cooldown: "提示間隔",
        cooldown2: "2 分鐘",
        cooldown5: "5 分鐘",
        cooldown15: "15 分鐘",
        cooldown30: "30 分鐘",
        cooldown60: "1 小時",
        cpuTitle: "CPU 使用率過高",
        cpuBodyFormat: "CPU 已連續數秒高於 %d%%。",
        cpuTemperatureTitle: "CPU 過熱",
        cpuTemperatureBodyFormat: "CPU 已達到 %d °C。",
        memoryTitle: "記憶體壓力過高",
        memoryBody: "記憶體壓力已達至嚴重水平。",
        diskTitle: "磁碟空間不足",
        diskBodyFormat: "%@ 的可用空間低於 %d%%。",
        batteryTitle: "電池電量偏低",
        batteryBodyFormat: "電池電量為 %d%%。"
    )
}

struct SensorsFeatureStrings {
    let section: String
    let temperature: String
    let power: String
    let fans: String
    let frequency: String
    let totalPower: String
    let fanOff: String
    let leftFan: String
    let rightFan: String
    let fan: String
    let cpuPerformance: String
    let cpuEfficiency: String
    let graphics: String
    let battery: String
    let ssd: String
    let wifi: String
    let airflow: String
    let memApp: String
    let memWired: String
    let memCompressed: String
    let memFree: String
    let voltage: String
    let amperage: String
    let cycles: String
    let condition: String
    let conditionNormal: String
    let capacity: String
    let poweredOn: String
    let awake: String
    let sleeping: String

    static let enUS = SensorsFeatureStrings(
        section: "Sensors", temperature: "Temperature", power: "Power", fans: "Fans",
        frequency: "Frequency", totalPower: "Total Power", fanOff: "Off",
        leftFan: "Left Fan", rightFan: "Right Fan", fan: "Fan",
        cpuPerformance: "CPU Performance Cores", cpuEfficiency: "CPU Efficiency Cores",
        graphics: "Graphics", battery: "Battery", ssd: "SSD", wifi: "Wi-Fi", airflow: "Airflow",
        memApp: "App", memWired: "Wired", memCompressed: "Compressed", memFree: "Free",
        voltage: "Voltage", amperage: "Amperage", cycles: "Cycles", condition: "Condition", conditionNormal: "Normal", capacity: "Capacity", poweredOn: "Powered On", awake: "Awake", sleeping: "Sleeping"
    )

    static let ptBR = SensorsFeatureStrings(
        section: "Sensores", temperature: "Temperatura", power: "Energia", fans: "Ventoinhas",
        frequency: "Frequência", totalPower: "Energia total", fanOff: "Desl.",
        leftFan: "Ventoinha esquerda", rightFan: "Ventoinha direita", fan: "Ventoinha",
        cpuPerformance: "Núcleos de desempenho", cpuEfficiency: "Núcleos de eficiência",
        graphics: "Gráficos", battery: "Bateria", ssd: "SSD", wifi: "Wi-Fi", airflow: "Fluxo de ar",
        memApp: "App", memWired: "Reservada", memCompressed: "Comprimida", memFree: "Livre",
        voltage: "Tensão", amperage: "Amperagem", cycles: "Ciclos", condition: "Condição", conditionNormal: "Normal", capacity: "Capacidade", poweredOn: "Ligado em", awake: "Ativo", sleeping: "Suspenso"
    )

    static let tr = SensorsFeatureStrings(
        section: "Sensörler", temperature: "Sıcaklık", power: "Güç", fans: "Fanlar",
        frequency: "Frekans", totalPower: "Toplam Güç", fanOff: "Kapalı",
        leftFan: "Sol Fan", rightFan: "Sağ Fan", fan: "Fan",
        cpuPerformance: "CPU Performans Çekirdekleri", cpuEfficiency: "CPU Verimlilik Çekirdekleri",
        graphics: "Grafik", battery: "Pil", ssd: "SSD", wifi: "Wi-Fi", airflow: "Hava Akışı",
        memApp: "Uygulama", memWired: "Sabit", memCompressed: "Sıkıştırılmış", memFree: "Boş",
        voltage: "Voltaj", amperage: "Amperaj", cycles: "Döngü", condition: "Durum", conditionNormal: "Normal", capacity: "Kapasite", poweredOn: "Açılış", awake: "Uyanık", sleeping: "Uyku"
    )

    static let ru = SensorsFeatureStrings(
        section: "Датчики", temperature: "Температура", power: "Питание", fans: "Вентиляторы",
        frequency: "Частота", totalPower: "Общая мощность", fanOff: "Выкл.",
        leftFan: "Левый вентилятор", rightFan: "Правый вентилятор", fan: "Вентилятор",
        cpuPerformance: "Производительные ядра ЦП", cpuEfficiency: "Энергоэффективные ядра ЦП",
        graphics: "Графика", battery: "Батарея", ssd: "SSD", wifi: "Wi-Fi", airflow: "Поток воздуха",
        memApp: "Прил.", memWired: "Резерв", memCompressed: "Сжатая", memFree: "Свободно",
        voltage: "Напряжение", amperage: "Ток", cycles: "Циклы", condition: "Состояние", conditionNormal: "Норма", capacity: "Ёмкость", poweredOn: "Включён", awake: "Активно", sleeping: "Сон"
    )

    static let es = SensorsFeatureStrings(
        section: "Sensores", temperature: "Temperatura", power: "Energía", fans: "Ventiladores",
        frequency: "Frecuencia", totalPower: "Energía total", fanOff: "Apag.",
        leftFan: "Ventilador izquierdo", rightFan: "Ventilador derecho", fan: "Ventilador",
        cpuPerformance: "Núcleos de rendimiento", cpuEfficiency: "Núcleos de eficiencia",
        graphics: "Gráficos", battery: "Batería", ssd: "SSD", wifi: "Wi-Fi", airflow: "Flujo de aire",
        memApp: "Apps", memWired: "Residente", memCompressed: "Comprimida", memFree: "Libre",
        voltage: "Voltaje", amperage: "Amperaje", cycles: "Ciclos", condition: "Estado", conditionNormal: "Normal", capacity: "Capacidad", poweredOn: "Encendido", awake: "Activo", sleeping: "Reposo"
    )

    static let de = SensorsFeatureStrings(
        section: "Sensoren", temperature: "Temperatur", power: "Leistung", fans: "Lüfter",
        frequency: "Frequenz", totalPower: "Gesamtleistung", fanOff: "Aus",
        leftFan: "Linker Lüfter", rightFan: "Rechter Lüfter", fan: "Lüfter",
        cpuPerformance: "CPU-Leistungskerne", cpuEfficiency: "CPU-Effizienzkerne",
        graphics: "Grafik", battery: "Batterie", ssd: "SSD", wifi: "WLAN", airflow: "Luftstrom",
        memApp: "Apps", memWired: "Belegt", memCompressed: "Komprimiert", memFree: "Frei",
        voltage: "Spannung", amperage: "Stromstärke", cycles: "Zyklen", condition: "Zustand", conditionNormal: "Normal", capacity: "Kapazität", poweredOn: "Eingeschaltet", awake: "Aktiv", sleeping: "Ruhezustand"
    )

    static let fr = SensorsFeatureStrings(
        section: "Capteurs", temperature: "Température", power: "Alimentation", fans: "Ventilateurs",
        frequency: "Fréquence", totalPower: "Puissance totale", fanOff: "Arrêt",
        leftFan: "Ventilateur gauche", rightFan: "Ventilateur droit", fan: "Ventilateur",
        cpuPerformance: "Cœurs performance", cpuEfficiency: "Cœurs efficacité",
        graphics: "Graphismes", battery: "Batterie", ssd: "SSD", wifi: "Wi-Fi", airflow: "Flux d'air",
        memApp: "Apps", memWired: "Résident", memCompressed: "Compressée", memFree: "Libre",
        voltage: "Tension", amperage: "Ampérage", cycles: "Cycles", condition: "État", conditionNormal: "Normal", capacity: "Capacité", poweredOn: "Allumé", awake: "Actif", sleeping: "Veille"
    )

    static let it = SensorsFeatureStrings(
        section: "Sensori", temperature: "Temperatura", power: "Alimentazione", fans: "Ventole",
        frequency: "Frequenza", totalPower: "Potenza totale", fanOff: "Off",
        leftFan: "Ventola sinistra", rightFan: "Ventola destra", fan: "Ventola",
        cpuPerformance: "Core prestazioni", cpuEfficiency: "Core efficienza",
        graphics: "Grafica", battery: "Batteria", ssd: "SSD", wifi: "Wi-Fi", airflow: "Flusso d'aria",
        memApp: "App", memWired: "Residente", memCompressed: "Compressa", memFree: "Libera",
        voltage: "Tensione", amperage: "Amperaggio", cycles: "Cicli", condition: "Condizione", conditionNormal: "Normale", capacity: "Capacità", poweredOn: "Acceso", awake: "Attivo", sleeping: "Sospeso"
    )

    static let ja = SensorsFeatureStrings(
        section: "センサー", temperature: "温度", power: "電力", fans: "ファン",
        frequency: "周波数", totalPower: "合計電力", fanOff: "オフ",
        leftFan: "左ファン", rightFan: "右ファン", fan: "ファン",
        cpuPerformance: "CPU パフォーマンスコア", cpuEfficiency: "CPU 効率コア",
        graphics: "グラフィックス", battery: "バッテリー", ssd: "SSD", wifi: "Wi-Fi", airflow: "エアフロー",
        memApp: "アプリ", memWired: "確保領域", memCompressed: "圧縮", memFree: "空き",
        voltage: "電圧", amperage: "電流", cycles: "サイクル", condition: "状態", conditionNormal: "正常", capacity: "容量", poweredOn: "起動", awake: "稼働", sleeping: "スリープ"
    )

    static let ko = SensorsFeatureStrings(
        section: "센서", temperature: "온도", power: "전력", fans: "팬",
        frequency: "주파수", totalPower: "총 전력", fanOff: "끔",
        leftFan: "왼쪽 팬", rightFan: "오른쪽 팬", fan: "팬",
        cpuPerformance: "CPU 성능 코어", cpuEfficiency: "CPU 효율 코어",
        graphics: "그래픽", battery: "배터리", ssd: "SSD", wifi: "Wi-Fi", airflow: "공기 흐름",
        memApp: "앱", memWired: "유선", memCompressed: "압축됨", memFree: "사용 가능",
        voltage: "전압", amperage: "전류", cycles: "사이클", condition: "상태", conditionNormal: "정상", capacity: "용량", poweredOn: "켜짐", awake: "가동", sleeping: "잠자기"
    )

    static let zhHans = SensorsFeatureStrings(
        section: "传感器", temperature: "温度", power: "功耗", fans: "风扇",
        frequency: "频率", totalPower: "总功耗", fanOff: "关闭",
        leftFan: "左风扇", rightFan: "右风扇", fan: "风扇",
        cpuPerformance: "CPU 性能核心", cpuEfficiency: "CPU 能效核心",
        graphics: "显卡", battery: "电池", ssd: "SSD", wifi: "Wi-Fi", airflow: "气流",
        memApp: "应用", memWired: "联动", memCompressed: "已压缩", memFree: "可用",
        voltage: "电压", amperage: "电流", cycles: "循环次数", condition: "状况", conditionNormal: "正常", capacity: "容量", poweredOn: "开机", awake: "唤醒", sleeping: "睡眠"
    )

    static let zhTW = SensorsFeatureStrings(
        section: "感測器", temperature: "溫度", power: "功耗", fans: "風扇",
        frequency: "頻率", totalPower: "總功耗", fanOff: "關閉",
        leftFan: "左風扇", rightFan: "右風扇", fan: "風扇",
        cpuPerformance: "CPU 效能核心", cpuEfficiency: "CPU 節能核心",
        graphics: "顯示卡", battery: "電池", ssd: "SSD", wifi: "Wi-Fi", airflow: "氣流",
        memApp: "應用程式", memWired: "聯動", memCompressed: "已壓縮", memFree: "可用",
        voltage: "電壓", amperage: "電流", cycles: "循環次數", condition: "狀況", conditionNormal: "正常", capacity: "容量", poweredOn: "開機", awake: "喚醒", sleeping: "睡眠"
    )

    static let zhHK = SensorsFeatureStrings(
        section: "感應器", temperature: "溫度", power: "功耗", fans: "風扇",
        frequency: "頻率", totalPower: "總功耗", fanOff: "關閉",
        leftFan: "左風扇", rightFan: "右風扇", fan: "風扇",
        cpuPerformance: "CPU 效能核心", cpuEfficiency: "CPU 節能核心",
        graphics: "顯示卡", battery: "電池", ssd: "SSD", wifi: "Wi-Fi", airflow: "氣流",
        memApp: "應用程式", memWired: "聯動", memCompressed: "已壓縮", memFree: "可用",
        voltage: "電壓", amperage: "電流", cycles: "循環次數", condition: "狀況", conditionNormal: "正常", capacity: "容量", poweredOn: "開機", awake: "喚醒", sleeping: "睡眠"
    )
}

// MARK: - App appearance (System / Light / Dark)

/// Labels for the app-wide light/dark override picker. Self-contained (its own
/// language switch) so it needs no edits across the 13 `Strings` files.
struct AppearanceStrings {
    let title: String
    let system: String
    let light: String
    let dark: String
    let caption: String

    static func of(_ language: AppLanguage) -> AppearanceStrings {
        switch language {
        case .enUS:
            return .init(title: "Appearance", system: "System", light: "Light", dark: "Dark",
                         caption: "Force Vorssaint's own light or dark look, independent of macOS.")
        case .ptBR:
            return .init(title: "Aparência", system: "Sistema", light: "Claro", dark: "Escuro",
                         caption: "Força a aparência clara ou escura do Vorssaint, independente do macOS.")
        case .tr:
            return .init(title: "Görünüm", system: "Sistem", light: "Açık", dark: "Koyu",
                         caption: "Vorssaint'in açık veya koyu görünümünü macOS'tan bağımsız olarak zorlar.")
        case .ru:
            return .init(title: "Оформление", system: "Системное", light: "Светлое", dark: "Тёмное",
                         caption: "Принудительно светлый или тёмный вид Vorssaint, независимо от macOS.")
        case .es:
            return .init(title: "Apariencia", system: "Sistema", light: "Claro", dark: "Oscuro",
                         caption: "Fuerza el aspecto claro u oscuro de Vorssaint, independiente de macOS.")
        case .de:
            return .init(title: "Erscheinungsbild", system: "System", light: "Hell", dark: "Dunkel",
                         caption: "Erzwingt Vorssaints helles oder dunkles Aussehen, unabhängig von macOS.")
        case .fr:
            return .init(title: "Apparence", system: "Système", light: "Clair", dark: "Sombre",
                         caption: "Force l'apparence claire ou sombre de Vorssaint, indépendamment de macOS.")
        case .it:
            return .init(title: "Aspetto", system: "Sistema", light: "Chiaro", dark: "Scuro",
                         caption: "Forza l'aspetto chiaro o scuro di Vorssaint, indipendente da macOS.")
        case .ja:
            return .init(title: "外観", system: "システム", light: "ライト", dark: "ダーク",
                         caption: "macOS とは独立して、Vorssaint 独自のライト/ダーク表示を固定します。")
        case .ko:
            return .init(title: "화면 모드", system: "시스템", light: "라이트", dark: "다크",
                         caption: "macOS와 별개로 Vorssaint의 라이트/다크 모드를 고정합니다.")
        case .zhHans:
            return .init(title: "外观", system: "系统", light: "浅色", dark: "深色",
                         caption: "独立于 macOS，强制 Vorssaint 使用浅色或深色外观。")
        case .zhTW:
            return .init(title: "外觀", system: "系統", light: "淺色", dark: "深色",
                         caption: "獨立於 macOS，強制 Vorssaint 使用淺色或深色外觀。")
        case .zhHK:
            return .init(title: "外觀", system: "系統", light: "淺色", dark: "深色",
                         caption: "獨立於 macOS，強制 Vorssaint 使用淺色或深色外觀。")
        }
    }
}

// MARK: - Storage "Purgeable" label (self-contained, no 13-file Strings edits)

func diskPurgeableLabel(_ language: AppLanguage) -> String {
    switch language {
    case .enUS: return "Purgeable"
    case .ptBR: return "Liberável"
    case .tr: return "Temizlenebilir"
    case .ru: return "Очищаемое"
    case .es: return "Liberable"
    case .de: return "Bereinigbar"
    case .fr: return "Récupérable"
    case .it: return "Liberabile"
    case .ja: return "解放可能"
    case .ko: return "제거 가능"
    case .zhHans: return "可清除"
    case .zhTW: return "可清除"
    case .zhHK: return "可清除"
    }
}
