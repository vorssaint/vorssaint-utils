// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardImportStrings {
    let title: String
    let emptyBody: String
    let incompatibleBody: String
    let okButton: String

    static func localized(_ language: AppLanguage) -> ClipboardImportStrings {
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

extension ClipboardImportStrings {
    static let enUS = ClipboardImportStrings(
        title: "Couldn't paste",
        emptyBody: "The clipboard is empty.",
        incompatibleBody: "The clipboard doesn't contain a file, image, link, or text the shelf can use.",
        okButton: "OK")

    static let ptBR = ClipboardImportStrings(
        title: "Não foi possível colar",
        emptyBody: "A área de transferência está vazia.",
        incompatibleBody: "A área de transferência não contém um arquivo, imagem, link ou texto que a prateleira possa usar.",
        okButton: "OK")

    static let tr = ClipboardImportStrings(
        title: "Yapıştırılamadı",
        emptyBody: "Pano boş.",
        incompatibleBody: "Pano, rafın kullanabileceği bir dosya, görsel, bağlantı veya metin içermiyor.",
        okButton: "Tamam")

    static let ru = ClipboardImportStrings(
        title: "Не удалось вставить",
        emptyBody: "Буфер обмена пуст.",
        incompatibleBody: "В буфере обмена нет файла, изображения, ссылки или текста, который можно положить на полку.",
        okButton: "OK")

    static let es = ClipboardImportStrings(
        title: "No se pudo pegar",
        emptyBody: "El portapapeles está vacío.",
        incompatibleBody: "El portapapeles no contiene un archivo, imagen, enlace o texto que la bandeja pueda usar.",
        okButton: "OK")

    static let sk = ClipboardImportStrings(
        title: "Nepodarilo sa vložiť",
        emptyBody: "Schránka je prázdna.",
        incompatibleBody: "Schránka neobsahuje súbor, obrázok, odkaz ani text, ktorý by polica mohla použiť.",
        okButton: "OK")

    static let de = ClipboardImportStrings(
        title: "Einfügen nicht möglich",
        emptyBody: "Die Zwischenablage ist leer.",
        incompatibleBody: "Die Zwischenablage enthält keine Datei, kein Bild, keinen Link und keinen Text für das Ablagefach.",
        okButton: "OK")

    static let fr = ClipboardImportStrings(
        title: "Impossible de coller",
        emptyBody: "Le presse-papiers est vide.",
        incompatibleBody: "Le presse-papiers ne contient aucun fichier, image, lien ou texte utilisable par l'étagère.",
        okButton: "OK")

    static let it = ClipboardImportStrings(
        title: "Impossibile incollare",
        emptyBody: "Gli appunti sono vuoti.",
        incompatibleBody: "Gli appunti non contengono file, immagini, link o testo utilizzabili dallo scaffale.",
        okButton: "OK")

    static let ja = ClipboardImportStrings(
        title: "貼り付けできません",
        emptyBody: "クリップボードは空です。",
        incompatibleBody: "クリップボードに、シェルフで使用できるファイル、画像、リンク、テキストがありません。",
        okButton: "OK")

    static let ko = ClipboardImportStrings(
        title: "붙여넣을 수 없음",
        emptyBody: "클립보드가 비어 있습니다.",
        incompatibleBody: "클립보드에 선반에서 사용할 수 있는 파일, 이미지, 링크 또는 텍스트가 없습니다.",
        okButton: "확인")

    static let zhHans = ClipboardImportStrings(
        title: "无法粘贴",
        emptyBody: "剪贴板为空。",
        incompatibleBody: "剪贴板中没有临时搁板可用的文件、图片、链接或文本。",
        okButton: "好")

    static let zhTW = ClipboardImportStrings(
        title: "無法貼上",
        emptyBody: "剪貼簿是空的。",
        incompatibleBody: "剪貼簿中沒有暫存架可用的檔案、圖片、連結或文字。",
        okButton: "好")

    static let zhHK = ClipboardImportStrings(
        title: "無法貼上",
        emptyBody: "剪貼簿是空的。",
        incompatibleBody: "剪貼簿中沒有暫存架可用的檔案、圖片、連結或文字。",
        okButton: "好")

    static let uk = ClipboardImportStrings(
        title: "Не вдалося вставити",
        emptyBody: "Буфер обміну порожній.",
        incompatibleBody: "У буфері обміну немає файлу, зображення, посилання чи тексту, які можна покласти на полицю.",
        okButton: "OK")
}
