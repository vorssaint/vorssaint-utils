// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DefaultAppsFeatureStrings {
    let title: String
    let hubDescription: String
    let openWith: String
    let openWithCaption: String
    let chooseApp: String
    let noApp: String
    let noFormats: String
    let currentFormat: String
    let currentNone: String
    let alreadyFormat: String
    let moreFormat: String
    let selectedFormat: String
    let setDefault: String
    let confirmNote: String
    let video: String
    let audio: String
    let image: String
    let text: String
    let archive: String
    let other: String

    func name(of category: DefaultAppsSupport.Category) -> String {
        switch category {
        case .video: return video
        case .audio: return audio
        case .image: return image
        case .text: return text
        case .archive: return archive
        case .other: return other
        }
    }
}

extension FeatureStrings {
    static func defaultApps(_ language: AppLanguage) -> DefaultAppsFeatureStrings {
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

extension DefaultAppsFeatureStrings {
    static let enUS = DefaultAppsFeatureStrings(
        title: "Default Apps",
        hubDescription: "Choose which app opens each file format",
        openWith: "Open with this app",
        openWithCaption: "Only the formats this app declares it can open are listed.",
        chooseApp: "Choose App…", noApp: "None",
        noFormats: "This app does not declare any file formats it can open.",
        currentFormat: "Now: %@", currentNone: "Now: none", alreadyFormat: "Already %@",
        moreFormat: "%d more…", selectedFormat: "%d formats selected", setDefault: "Set as Default",
        confirmNote: "macOS asks you to confirm each format.",
        video: "Video", audio: "Audio", image: "Images", text: "Text", archive: "Archives", other: "Other")

    static let ptBR = DefaultAppsFeatureStrings(
        title: "Apps padrão",
        hubDescription: "Escolha qual app abre cada formato de arquivo",
        openWith: "Abrir com este app",
        openWithCaption: "Só aparecem os formatos que este app declara conseguir abrir.",
        chooseApp: "Escolher app…", noApp: "Nenhum",
        noFormats: "Este app não declara nenhum formato de arquivo que consiga abrir.",
        currentFormat: "Agora: %@", currentNone: "Agora: nenhum", alreadyFormat: "Já é %@",
        moreFormat: "Mais %d…", selectedFormat: "%d formatos selecionados", setDefault: "Definir como padrão",
        confirmNote: "O macOS pede confirmação para cada formato.",
        video: "Vídeo", audio: "Áudio", image: "Imagens", text: "Texto", archive: "Arquivos compactados", other: "Outros")

    static let tr = DefaultAppsFeatureStrings(
        title: "Varsayılan uygulamalar",
        hubDescription: "Her dosya biçimini hangi uygulamanın açacağını seçin",
        openWith: "Bu uygulamayla aç",
        openWithCaption: "Yalnızca bu uygulamanın açabildiğini bildirdiği biçimler listelenir.",
        chooseApp: "Uygulama seç…", noApp: "Yok",
        noFormats: "Bu uygulama açabildiği hiçbir dosya biçimi bildirmiyor.",
        currentFormat: "Şu an: %@", currentNone: "Şu an: yok", alreadyFormat: "Zaten %@",
        moreFormat: "%d tane daha…", selectedFormat: "%d biçim seçildi", setDefault: "Varsayılan yap",
        confirmNote: "macOS her biçim için onay ister.",
        video: "Video", audio: "Ses", image: "Görüntüler", text: "Metin", archive: "Arşivler", other: "Diğer")

    static let ru = DefaultAppsFeatureStrings(
        title: "Приложения по умолчанию",
        hubDescription: "Выберите, какое приложение открывает каждый формат файлов",
        openWith: "Открывать этим приложением",
        openWithCaption: "Показаны только форматы, которые приложение само объявляет открываемыми.",
        chooseApp: "Выбрать приложение…", noApp: "Нет",
        noFormats: "Это приложение не объявляет форматов файлов, которые может открыть.",
        currentFormat: "Сейчас: %@", currentNone: "Сейчас: нет", alreadyFormat: "Уже %@",
        moreFormat: "Ещё %d…", selectedFormat: "Выбрано форматов: %d", setDefault: "Сделать по умолчанию",
        confirmNote: "macOS попросит подтвердить каждый формат.",
        video: "Видео", audio: "Аудио", image: "Изображения", text: "Текст", archive: "Архивы", other: "Другое")

    static let es = DefaultAppsFeatureStrings(
        title: "Apps predeterminadas",
        hubDescription: "Elige qué app abre cada formato de archivo",
        openWith: "Abrir con esta app",
        openWithCaption: "Solo aparecen los formatos que esta app declara que puede abrir.",
        chooseApp: "Elegir app…", noApp: "Ninguna",
        noFormats: "Esta app no declara ningún formato de archivo que pueda abrir.",
        currentFormat: "Ahora: %@", currentNone: "Ahora: ninguna", alreadyFormat: "Ya es %@",
        moreFormat: "%d más…", selectedFormat: "%d formatos seleccionados", setDefault: "Establecer como predeterminada",
        confirmNote: "macOS pide confirmación para cada formato.",
        video: "Vídeo", audio: "Audio", image: "Imágenes", text: "Texto", archive: "Archivos comprimidos", other: "Otros")

    static let sk = DefaultAppsFeatureStrings(
        title: "Predvolené aplikácie",
        hubDescription: "Vyberte, ktorá aplikácia otvára každý formát súborov",
        openWith: "Otvárať touto aplikáciou",
        openWithCaption: "Zobrazia sa len formáty, ktoré aplikácia sama uvádza ako podporované.",
        chooseApp: "Vybrať aplikáciu…", noApp: "Žiadna",
        noFormats: "Táto aplikácia neuvádza žiadne formáty súborov, ktoré dokáže otvoriť.",
        currentFormat: "Teraz: %@", currentNone: "Teraz: žiadna", alreadyFormat: "Už %@",
        moreFormat: "Ďalšie: %d…", selectedFormat: "Vybrané formáty: %d", setDefault: "Nastaviť ako predvolenú",
        confirmNote: "macOS si vyžiada potvrdenie pre každý formát.",
        video: "Video", audio: "Zvuk", image: "Obrázky", text: "Text", archive: "Archívy", other: "Ostatné")

    static let de = DefaultAppsFeatureStrings(
        title: "Standard-Apps",
        hubDescription: "Wähle, welche App jedes Dateiformat öffnet",
        openWith: "Mit dieser App öffnen",
        openWithCaption: "Nur Formate, die diese App selbst als öffenbar angibt, werden aufgelistet.",
        chooseApp: "App wählen…", noApp: "Keine",
        noFormats: "Diese App gibt keine Dateiformate an, die sie öffnen kann.",
        currentFormat: "Jetzt: %@", currentNone: "Jetzt: keine", alreadyFormat: "Bereits %@",
        moreFormat: "%d weitere …", selectedFormat: "%d Formate ausgewählt", setDefault: "Als Standard festlegen",
        confirmNote: "macOS fragt für jedes Format nach einer Bestätigung.",
        video: "Video", audio: "Audio", image: "Bilder", text: "Text", archive: "Archive", other: "Andere")

    static let fr = DefaultAppsFeatureStrings(
        title: "Apps par défaut",
        hubDescription: "Choisissez quelle app ouvre chaque format de fichier",
        openWith: "Ouvrir avec cette app",
        openWithCaption: "Seuls les formats que cette app déclare savoir ouvrir sont listés.",
        chooseApp: "Choisir une app…", noApp: "Aucune",
        noFormats: "Cette app ne déclare aucun format de fichier qu’elle sait ouvrir.",
        currentFormat: "Actuellement\u{00A0}: %@", currentNone: "Actuellement\u{00A0}: aucune", alreadyFormat: "Déjà %@",
        moreFormat: "%d de plus…", selectedFormat: "%d formats sélectionnés", setDefault: "Définir par défaut",
        confirmNote: "macOS demande une confirmation pour chaque format.",
        video: "Vidéo", audio: "Audio", image: "Images", text: "Texte", archive: "Archives", other: "Autres")

    static let it = DefaultAppsFeatureStrings(
        title: "App predefinite",
        hubDescription: "Scegli quale app apre ogni formato di file",
        openWith: "Apri con questa app",
        openWithCaption: "Sono elencati solo i formati che questa app dichiara di saper aprire.",
        chooseApp: "Scegli app…", noApp: "Nessuna",
        noFormats: "Questa app non dichiara alcun formato di file che sa aprire.",
        currentFormat: "Ora: %@", currentNone: "Ora: nessuna", alreadyFormat: "Già %@",
        moreFormat: "Altri %d…", selectedFormat: "%d formati selezionati", setDefault: "Imposta come predefinita",
        confirmNote: "macOS chiede conferma per ogni formato.",
        video: "Video", audio: "Audio", image: "Immagini", text: "Testo", archive: "Archivi", other: "Altro")

    static let ja = DefaultAppsFeatureStrings(
        title: "デフォルトのアプリ",
        hubDescription: "ファイル形式ごとに開くアプリを選択します",
        openWith: "このアプリで開く",
        openWithCaption: "このアプリが自ら開けると宣言している形式だけを表示します。",
        chooseApp: "アプリを選択…", noApp: "なし",
        noFormats: "このアプリは開けるファイル形式を宣言していません。",
        currentFormat: "現在：%@", currentNone: "現在：なし", alreadyFormat: "すでに%@",
        moreFormat: "ほか%d種類…", selectedFormat: "%d種類の形式を選択中", setDefault: "デフォルトに設定",
        confirmNote: "macOSが形式ごとに確認を求めます。",
        video: "ビデオ", audio: "オーディオ", image: "イメージ", text: "テキスト", archive: "アーカイブ", other: "その他")

    static let ko = DefaultAppsFeatureStrings(
        title: "기본 앱",
        hubDescription: "파일 형식마다 어떤 앱으로 열지 선택합니다",
        openWith: "이 앱으로 열기",
        openWithCaption: "이 앱이 열 수 있다고 직접 선언한 형식만 표시합니다.",
        chooseApp: "앱 선택…", noApp: "없음",
        noFormats: "이 앱은 열 수 있는 파일 형식을 선언하지 않습니다.",
        currentFormat: "현재: %@", currentNone: "현재: 없음", alreadyFormat: "이미 %@",
        moreFormat: "%d개 더…", selectedFormat: "형식 %d개 선택됨", setDefault: "기본으로 설정",
        confirmNote: "macOS가 형식마다 확인을 요청합니다.",
        video: "비디오", audio: "오디오", image: "이미지", text: "텍스트", archive: "압축 파일", other: "기타")

    static let uk = DefaultAppsFeatureStrings(
        title: "Програми за замовчуванням",
        hubDescription: "Виберіть, яка програма відкриває кожен формат файлів",
        openWith: "Відкривати цією програмою",
        openWithCaption: "Показано лише формати, які програма сама оголошує відкриваними.",
        chooseApp: "Вибрати програму…", noApp: "Немає",
        noFormats: "Ця програма не оголошує форматів файлів, які може відкрити.",
        currentFormat: "Зараз: %@", currentNone: "Зараз: немає", alreadyFormat: "Уже %@",
        moreFormat: "Ще %d…", selectedFormat: "Вибрано форматів: %d", setDefault: "Зробити за замовчуванням",
        confirmNote: "macOS попросить підтвердити кожен формат.",
        video: "Відео", audio: "Аудіо", image: "Зображення", text: "Текст", archive: "Архіви", other: "Інше")

    static let zhHans = DefaultAppsFeatureStrings(
        title: "默认打开方式",
        hubDescription: "设定每种文件格式用哪个 App 打开",
        openWith: "用这个 App 打开",
        openWithCaption: "只列出这个 App 自己声明能打开的格式。",
        chooseApp: "选择 App…", noApp: "未选择",
        noFormats: "这个 App 没有声明能打开的文件格式。",
        currentFormat: "现在：%@", currentNone: "现在：无", alreadyFormat: "已是 %@",
        moreFormat: "还有 %d 种…", selectedFormat: "已选 %d 种格式", setDefault: "设为默认",
        confirmNote: "macOS 会对每种格式请你确认一次。",
        video: "视频", audio: "音频", image: "图片", text: "文本", archive: "压缩包", other: "其他")

    static let zhTW = DefaultAppsFeatureStrings(
        title: "預設打開方式",
        hubDescription: "設定每種檔案格式用哪個 App 打開",
        openWith: "用這個 App 打開",
        openWithCaption: "只列出這個 App 自己宣告能打開的格式。",
        chooseApp: "選擇 App…", noApp: "未選擇",
        noFormats: "這個 App 沒有宣告能打開的檔案格式。",
        currentFormat: "目前：%@", currentNone: "目前：無", alreadyFormat: "已是 %@",
        moreFormat: "還有 %d 種…", selectedFormat: "已選 %d 種格式", setDefault: "設為預設",
        confirmNote: "macOS 會對每種格式請你確認一次。",
        video: "影片", audio: "音訊", image: "影像", text: "文字", archive: "壓縮檔", other: "其他")

    static let zhHK = DefaultAppsFeatureStrings(
        title: "預設打開方式",
        hubDescription: "設定每種檔案格式用哪個 App 打開",
        openWith: "用這個 App 打開",
        openWithCaption: "只列出這個 App 自己聲明能打開的格式。",
        chooseApp: "選擇 App…", noApp: "未選擇",
        noFormats: "這個 App 沒有聲明能打開的檔案格式。",
        currentFormat: "現在：%@", currentNone: "現在：無", alreadyFormat: "已是 %@",
        moreFormat: "還有 %d 種…", selectedFormat: "已選 %d 種格式", setDefault: "設為預設",
        confirmNote: "macOS 會對每種格式請你確認一次。",
        video: "影片", audio: "音訊", image: "影像", text: "文字", archive: "壓縮檔", other: "其他")
}
