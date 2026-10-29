// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screenshot file format setting.
struct ScreenshotFormatStrings {
    let saveFormatLabel: String
    let saveFormatAutomatic: String
    let saveFormatCaption: String
}

extension FeatureStrings {
    static func screenshotFormat(_ language: AppLanguage) -> ScreenshotFormatStrings {
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

extension ScreenshotFormatStrings {
    static let enUS = ScreenshotFormatStrings(
        saveFormatLabel: "File format",
        saveFormatAutomatic: "Automatic",
        saveFormatCaption: "Automatic keeps text and interface captures as PNG and saves photos and gradients as JPEG. Copying always uses PNG."
    )

    static let ptBR = ScreenshotFormatStrings(
        saveFormatLabel: "Formato do arquivo",
        saveFormatAutomatic: "Automático",
        saveFormatCaption: "Automático mantém capturas de texto e interface em PNG e salva fotos e degradês em JPEG. Copiar sempre usa PNG."
    )

    static let tr = ScreenshotFormatStrings(
        saveFormatLabel: "Dosya biçimi",
        saveFormatAutomatic: "Otomatik",
        saveFormatCaption: "Otomatik, metin ve arayüz görüntülerini PNG, fotoğraf ve gradyanları JPEG olarak kaydeder. Kopyalama her zaman PNG kullanır."
    )

    static let ru = ScreenshotFormatStrings(
        saveFormatLabel: "Формат файла",
        saveFormatAutomatic: "Автоматически",
        saveFormatCaption: "Автоматически сохраняет снимки текста и интерфейса в PNG, а фотографии и градиенты в JPEG. Копирование всегда использует PNG."
    )

    static let es = ScreenshotFormatStrings(
        saveFormatLabel: "Formato de archivo",
        saveFormatAutomatic: "Automático",
        saveFormatCaption: "Automático guarda las capturas de texto e interfaz en PNG y las fotos y degradados en JPEG. Copiar siempre usa PNG."
    )

    static let sk = ScreenshotFormatStrings(
        saveFormatLabel: "Formát súboru",
        saveFormatAutomatic: "Automaticky",
        saveFormatCaption: "Automaticky ukladá snímky textu a rozhrania ako PNG a fotografie a prechody ako JPEG. Kopírovanie vždy používa PNG."
    )

    static let de = ScreenshotFormatStrings(
        saveFormatLabel: "Dateiformat",
        saveFormatAutomatic: "Automatisch",
        saveFormatCaption: "Automatisch sichert Text- und Oberflächenaufnahmen als PNG, Fotos und Verläufe als JPEG. Kopieren verwendet immer PNG."
    )

    static let fr = ScreenshotFormatStrings(
        saveFormatLabel: "Format de fichier",
        saveFormatAutomatic: "Automatique",
        saveFormatCaption: "Automatique garde les captures de texte et d’interface en PNG et enregistre photos et dégradés en JPEG. La copie utilise toujours le PNG."
    )

    static let it = ScreenshotFormatStrings(
        saveFormatLabel: "Formato file",
        saveFormatAutomatic: "Automatico",
        saveFormatCaption: "Automatico salva le catture di testo e interfaccia in PNG e foto e sfumature in JPEG. La copia usa sempre PNG."
    )

    static let ja = ScreenshotFormatStrings(
        saveFormatLabel: "ファイル形式",
        saveFormatAutomatic: "自動",
        saveFormatCaption: "自動では、文字や UI のキャプチャを PNG、写真やグラデーションを JPEG で保存します。コピーは常に PNG です。"
    )

    static let ko = ScreenshotFormatStrings(
        saveFormatLabel: "파일 형식",
        saveFormatAutomatic: "자동",
        saveFormatCaption: "자동은 텍스트와 인터페이스 캡처를 PNG로, 사진과 그라디언트를 JPEG로 저장합니다. 복사는 항상 PNG를 사용합니다."
    )

    static let zhHans = ScreenshotFormatStrings(
        saveFormatLabel: "文件格式",
        saveFormatAutomatic: "自动",
        saveFormatCaption: "自动会将文字和界面截图存储为 PNG，将照片和渐变存储为 JPEG。拷贝始终使用 PNG。"
    )

    static let zhTW = ScreenshotFormatStrings(
        saveFormatLabel: "檔案格式",
        saveFormatAutomatic: "自動",
        saveFormatCaption: "自動會將文字與介面截圖儲存為 PNG，將照片與漸層儲存為 JPEG。拷貝一律使用 PNG。"
    )

    static let zhHK = ScreenshotFormatStrings(
        saveFormatLabel: "檔案格式",
        saveFormatAutomatic: "自動",
        saveFormatCaption: "自動會將文字與介面截圖儲存為 PNG，將相片與漸變儲存為 JPEG。拷貝一律使用 PNG。"
    )

    static let uk = ScreenshotFormatStrings(
        saveFormatLabel: "Формат файлу",
        saveFormatAutomatic: "Автоматично",
        saveFormatCaption: "Автоматично зберігає знімки тексту й інтерфейсу як PNG, а фото й градієнти як JPEG. Копіювання завжди використовує PNG."
    )
}
