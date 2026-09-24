// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Wallpaper panel strings.
struct WallpaperFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    /// Sentence form for the panel layout list, whose descriptions end in a stop.
    let panelDescription: String
    let filterAll: String
    let filterOwn: String
    let filterApple: String
    let applyAllDisplays: String
    let addImage: String
    let addFolder: String
    let removeAdded: String
    let doneRemoving: String
    let sourceUnavailable: String
    let addImagePrompt: String
    let addFolderPrompt: String
    let openSystemSettings: String
    let emptyAll: String
    let emptyOwn: String
    let emptyApple: String
    let downloading: String
    let downloadFailed: String
    let applyFailed: String
    let previousPage: String
    let nextPage: String
}

extension FeatureStrings {
    static func wallpaper(_ language: AppLanguage) -> WallpaperFeatureStrings {
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

extension WallpaperFeatureStrings {
    static let enUS = WallpaperFeatureStrings(
        pageTitle: "Wallpaper",
        hubDescription: "Pick a still wallpaper without opening System Settings",
        panelDescription: "Pick a still wallpaper without opening System Settings.",
        filterAll: "All",
        filterOwn: "Your pictures",
        filterApple: "Apple",
        applyAllDisplays: "Show on all Spaces",
        addImage: "Add image",
        addFolder: "Add folder",
        removeAdded: "Remove",
        doneRemoving: "Done",
        sourceUnavailable: "Unavailable",
        addImagePrompt: "Choose images to keep in Vorssaint’s wallpaper list",
        addFolderPrompt: "Choose a folder of images to keep in Vorssaint’s wallpaper list",
        openSystemSettings: "Open Wallpaper settings",
        emptyAll: "No wallpapers found",
        emptyOwn: "No pictures added yet",
        emptyApple: "No Apple stills found",
        downloading: "Downloading…",
        downloadFailed: "Could not download the wallpaper",
        applyFailed: "Could not set the wallpaper",
        previousPage: "Previous",
        nextPage: "Next"
    )

    static let ptBR = WallpaperFeatureStrings(
        pageTitle: "Papel de parede",
        hubDescription: "Escolha um papel de parede sem abrir os Ajustes do Sistema",
        panelDescription: "Escolha um papel de parede sem abrir os Ajustes do Sistema.",
        filterAll: "Todos",
        filterOwn: "Somente próprios",
        filterApple: "Somente da Apple",
        applyAllDisplays: "Mostrar em todos os Spaces",
        addImage: "Adicionar imagem",
        addFolder: "Adicionar pasta",
        removeAdded: "Remover",
        doneRemoving: "Concluído",
        sourceUnavailable: "Indisponível",
        addImagePrompt: "Escolha imagens para manter na lista do Vorssaint",
        addFolderPrompt: "Escolha uma pasta de imagens para manter na lista do Vorssaint",
        openSystemSettings: "Abrir Ajustes de papel de parede",
        emptyAll: "Nenhum papel de parede encontrado",
        emptyOwn: "Nenhuma imagem adicionada ainda",
        emptyApple: "Nenhum papel da Apple encontrado",
        downloading: "Baixando…",
        downloadFailed: "Não foi possível baixar o papel de parede",
        applyFailed: "Não foi possível definir o papel de parede",
        previousPage: "Anterior",
        nextPage: "Próximo"
    )

    static let tr = WallpaperFeatureStrings(
        pageTitle: "Duvar kağıdı",
        hubDescription: "Sistem Ayarları’nı açmadan sabit bir duvar kağıdı seçin",
        panelDescription: "Sistem Ayarları’nı açmadan sabit bir duvar kağıdı seçin.",
        filterAll: "Tümü",
        filterOwn: "Sadece sizinki",
        filterApple: "Sadece Apple",
        applyAllDisplays: "Tüm Spaces’te göster",
        addImage: "Görüntü ekle",
        addFolder: "Klasör ekle",
        removeAdded: "Kaldır",
        doneRemoving: "Bitti",
        sourceUnavailable: "Kullanılamıyor",
        addImagePrompt: "Vorssaint listesinde tutulacak görüntüleri seçin",
        addFolderPrompt: "Vorssaint listesinde tutulacak bir görüntü klasörü seçin",
        openSystemSettings: "Duvar kağıdı ayarlarını aç",
        emptyAll: "Duvar kağıdı bulunamadı",
        emptyOwn: "Henüz görüntü eklenmedi",
        emptyApple: "Apple duvar kağıdı bulunamadı",
        downloading: "İndiriliyor…",
        downloadFailed: "Duvar kağıdı indirilemedi",
        applyFailed: "Duvar kağıdı ayarlanamadı",
        previousPage: "Önceki",
        nextPage: "Sonraki"
    )

    static let ru = WallpaperFeatureStrings(
        pageTitle: "Обои",
        hubDescription: "Выберите статичные обои без открытия Системных настроек",
        panelDescription: "Выберите статичные обои без открытия Системных настроек.",
        filterAll: "Все",
        filterOwn: "Только свои",
        filterApple: "Только Apple",
        applyAllDisplays: "Показывать на всех Space",
        addImage: "Добавить изображение",
        addFolder: "Добавить папку",
        removeAdded: "Удалить",
        doneRemoving: "Готово",
        sourceUnavailable: "Недоступно",
        addImagePrompt: "Выберите изображения для списка Vorssaint",
        addFolderPrompt: "Выберите папку с изображениями для списка Vorssaint",
        openSystemSettings: "Открыть настройки обоев",
        emptyAll: "Обои не найдены",
        emptyOwn: "Изображения ещё не добавлены",
        emptyApple: "Обои Apple не найдены",
        downloading: "Загрузка…",
        downloadFailed: "Не удалось загрузить обои",
        applyFailed: "Не удалось установить обои",
        previousPage: "Назад",
        nextPage: "Далее"
    )

    static let es = WallpaperFeatureStrings(
        pageTitle: "Fondo de pantalla",
        hubDescription: "Elige un fondo fijo sin abrir Ajustes del Sistema",
        panelDescription: "Elige un fondo fijo sin abrir Ajustes del Sistema.",
        filterAll: "Todos",
        filterOwn: "Solo propios",
        filterApple: "Solo de Apple",
        applyAllDisplays: "Mostrar en todos los Spaces",
        addImage: "Añadir imagen",
        addFolder: "Añadir carpeta",
        removeAdded: "Quitar",
        doneRemoving: "Listo",
        sourceUnavailable: "No disponible",
        addImagePrompt: "Elige imágenes para la lista de Vorssaint",
        addFolderPrompt: "Elige una carpeta de imágenes para la lista de Vorssaint",
        openSystemSettings: "Abrir ajustes de fondo",
        emptyAll: "No se encontraron fondos",
        emptyOwn: "Aún no hay imágenes añadidas",
        emptyApple: "No se encontraron fondos de Apple",
        downloading: "Descargando…",
        downloadFailed: "No se pudo descargar el fondo",
        applyFailed: "No se pudo establecer el fondo",
        previousPage: "Anterior",
        nextPage: "Siguiente"
    )

    static let de = WallpaperFeatureStrings(
        pageTitle: "Hintergrundbild",
        hubDescription: "Wähle ein Standbild ohne die Systemeinstellungen zu öffnen",
        panelDescription: "Wähle ein Standbild ohne die Systemeinstellungen zu öffnen.",
        filterAll: "Alle",
        filterOwn: "Nur eigene",
        filterApple: "Nur Apple",
        applyAllDisplays: "Auf allen Spaces zeigen",
        addImage: "Bild hinzufügen",
        addFolder: "Ordner hinzufügen",
        removeAdded: "Entfernen",
        doneRemoving: "Fertig",
        sourceUnavailable: "Nicht verfügbar",
        addImagePrompt: "Bilder für die Vorssaint-Liste wählen",
        addFolderPrompt: "Ordner mit Bildern für die Vorssaint-Liste wählen",
        openSystemSettings: "Hintergrundbild-Einstellungen öffnen",
        emptyAll: "Keine Hintergrundbilder gefunden",
        emptyOwn: "Noch keine eigenen Bilder",
        emptyApple: "Keine Apple-Bilder gefunden",
        downloading: "Wird geladen…",
        downloadFailed: "Hintergrundbild konnte nicht geladen werden",
        applyFailed: "Hintergrundbild konnte nicht gesetzt werden",
        previousPage: "Zurück",
        nextPage: "Weiter"
    )

    static let fr = WallpaperFeatureStrings(
        pageTitle: "Fond d’écran",
        hubDescription: "Choisissez une image fixe sans ouvrir Réglages Système",
        panelDescription: "Choisissez une image fixe sans ouvrir Réglages Système.",
        filterAll: "Tous",
        filterOwn: "Seulement les vôtres",
        filterApple: "Seulement Apple",
        applyAllDisplays: "Afficher sur tous les Spaces",
        addImage: "Ajouter une image",
        addFolder: "Ajouter un dossier",
        removeAdded: "Retirer",
        doneRemoving: "Terminé",
        sourceUnavailable: "Indisponible",
        addImagePrompt: "Choisissez des images pour la liste Vorssaint",
        addFolderPrompt: "Choisissez un dossier d’images pour la liste Vorssaint",
        openSystemSettings: "Ouvrir les réglages de fond d’écran",
        emptyAll: "Aucun fond d’écran trouvé",
        emptyOwn: "Aucune image ajoutée pour l’instant",
        emptyApple: "Aucun fond Apple trouvé",
        downloading: "Téléchargement…",
        downloadFailed: "Impossible de télécharger le fond d’écran",
        applyFailed: "Impossible de définir le fond d’écran",
        previousPage: "Précédent",
        nextPage: "Suivant"
    )

    static let it = WallpaperFeatureStrings(
        pageTitle: "Sfondo",
        hubDescription: "Scegli uno sfondo fisso senza aprire Impostazioni di Sistema",
        panelDescription: "Scegli uno sfondo fisso senza aprire Impostazioni di Sistema.",
        filterAll: "Tutti",
        filterOwn: "Solo i tuoi",
        filterApple: "Solo Apple",
        applyAllDisplays: "Mostra su tutti gli Spaces",
        addImage: "Aggiungi immagine",
        addFolder: "Aggiungi cartella",
        removeAdded: "Rimuovi",
        doneRemoving: "Fine",
        sourceUnavailable: "Non disponibile",
        addImagePrompt: "Scegli immagini per l’elenco di Vorssaint",
        addFolderPrompt: "Scegli una cartella di immagini per l’elenco di Vorssaint",
        openSystemSettings: "Apri impostazioni sfondo",
        emptyAll: "Nessuno sfondo trovato",
        emptyOwn: "Nessuna immagine aggiunta ancora",
        emptyApple: "Nessuno sfondo Apple trovato",
        downloading: "Download in corso…",
        downloadFailed: "Impossibile scaricare lo sfondo",
        applyFailed: "Impossibile impostare lo sfondo",
        previousPage: "Precedente",
        nextPage: "Successiva"
    )

    static let ja = WallpaperFeatureStrings(
        pageTitle: "壁紙",
        hubDescription: "システム設定を開かずに静止壁紙を選べます",
        panelDescription: "システム設定を開かずに静止壁紙を選べます。",
        filterAll: "すべて",
        filterOwn: "自分のみ",
        filterApple: "Appleのみ",
        applyAllDisplays: "すべてのスペースに表示",
        addImage: "画像を追加",
        addFolder: "フォルダを追加",
        removeAdded: "削除",
        doneRemoving: "完了",
        sourceUnavailable: "利用できません",
        addImagePrompt: "Vorssaintの一覧に残す画像を選んでください",
        addFolderPrompt: "Vorssaintの一覧に残す画像フォルダを選んでください",
        openSystemSettings: "壁紙設定を開く",
        emptyAll: "壁紙が見つかりません",
        emptyOwn: "まだ画像がありません",
        emptyApple: "Appleの壁紙が見つかりません",
        downloading: "ダウンロード中…",
        downloadFailed: "壁紙をダウンロードできませんでした",
        applyFailed: "壁紙を設定できませんでした",
        previousPage: "前へ",
        nextPage: "次へ"
    )

    static let ko = WallpaperFeatureStrings(
        pageTitle: "배경화면",
        hubDescription: "시스템 설정을 열지 않고 고정 배경을 고릅니다",
        panelDescription: "시스템 설정을 열지 않고 고정 배경을 고릅니다.",
        filterAll: "전체",
        filterOwn: "내 사진만",
        filterApple: "Apple만",
        applyAllDisplays: "모든 Space에 표시",
        addImage: "이미지 추가",
        addFolder: "폴더 추가",
        removeAdded: "제거",
        doneRemoving: "완료",
        sourceUnavailable: "사용할 수 없음",
        addImagePrompt: "Vorssaint 목록에 둘 이미지를 선택하세요",
        addFolderPrompt: "Vorssaint 목록에 둘 이미지 폴더를 선택하세요",
        openSystemSettings: "배경화면 설정 열기",
        emptyAll: "배경화면을 찾을 수 없습니다",
        emptyOwn: "아직 추가한 이미지가 없습니다",
        emptyApple: "Apple 배경을 찾을 수 없습니다",
        downloading: "다운로드 중…",
        downloadFailed: "배경화면을 다운로드할 수 없습니다",
        applyFailed: "배경화면을 설정할 수 없습니다",
        previousPage: "이전",
        nextPage: "다음"
    )

    static let zhHans = WallpaperFeatureStrings(
        pageTitle: "壁纸",
        hubDescription: "无需打开系统设置即可选择静态壁纸",
        panelDescription: "无需打开系统设置即可选择静态壁纸。",
        filterAll: "全部",
        filterOwn: "仅自己的",
        filterApple: "仅 Apple",
        applyAllDisplays: "在所有空间显示",
        addImage: "添加图片",
        addFolder: "添加文件夹",
        removeAdded: "移除",
        doneRemoving: "完成",
        sourceUnavailable: "不可用",
        addImagePrompt: "选择要保留在 Vorssaint 列表中的图片",
        addFolderPrompt: "选择要保留在 Vorssaint 列表中的图片文件夹",
        openSystemSettings: "打开壁纸设置",
        emptyAll: "未找到壁纸",
        emptyOwn: "尚未添加图片",
        emptyApple: "未找到 Apple 壁纸",
        downloading: "正在下载…",
        downloadFailed: "无法下载壁纸",
        applyFailed: "无法设置壁纸",
        previousPage: "上一页",
        nextPage: "下一页"
    )

    static let zhTW = WallpaperFeatureStrings(
        pageTitle: "桌布",
        hubDescription: "不必打開系統設定即可選擇靜態桌布",
        panelDescription: "不必打開系統設定即可選擇靜態桌布。",
        filterAll: "全部",
        filterOwn: "僅自己的",
        filterApple: "僅 Apple",
        applyAllDisplays: "在所有空間顯示",
        addImage: "新增圖片",
        addFolder: "新增資料夾",
        removeAdded: "移除",
        doneRemoving: "完成",
        sourceUnavailable: "無法使用",
        addImagePrompt: "選擇要保留在 Vorssaint 清單中的圖片",
        addFolderPrompt: "選擇要保留在 Vorssaint 清單中的圖片資料夾",
        openSystemSettings: "開啟桌布設定",
        emptyAll: "找不到桌布",
        emptyOwn: "尚未新增圖片",
        emptyApple: "找不到 Apple 桌布",
        downloading: "下載中…",
        downloadFailed: "無法下載桌布",
        applyFailed: "無法設定桌布",
        previousPage: "上一頁",
        nextPage: "下一頁"
    )

    static let zhHK = WallpaperFeatureStrings(
        pageTitle: "桌布",
        hubDescription: "唔使開系統設定都可以揀靜態桌布",
        panelDescription: "唔使開系統設定都可以揀靜態桌布。",
        filterAll: "全部",
        filterOwn: "淨係自己嘅",
        filterApple: "淨係 Apple",
        applyAllDisplays: "喺所有空間顯示",
        addImage: "新增圖片",
        addFolder: "新增資料夾",
        removeAdded: "移除",
        doneRemoving: "完成",
        sourceUnavailable: "無法使用",
        addImagePrompt: "選擇要保留喺 Vorssaint 清單嘅圖片",
        addFolderPrompt: "選擇要保留喺 Vorssaint 清單嘅圖片資料夾",
        openSystemSettings: "開啟桌布設定",
        emptyAll: "搵唔到桌布",
        emptyOwn: "未新增圖片",
        emptyApple: "搵唔到 Apple 桌布",
        downloading: "下載中…",
        downloadFailed: "無法下載桌布",
        applyFailed: "無法設定桌布",
        previousPage: "上一頁",
        nextPage: "下一頁"
    )
}
