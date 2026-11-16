// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MediaDownloaderStrings {
    let toolsTitle: String
    let linkTitle: String
    let batchTitle: String
    let progressTitle: String

}

extension FeatureStrings {
    static func mediaDownloader(_ language: AppLanguage) -> MediaDownloaderStrings {
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

extension MediaDownloaderStrings {
    static let enUS = Self(toolsTitle: "Download tools", linkTitle: "Media link",
                          batchTitle: "Batch download", progressTitle: "Downloading")
    static let ptBR = Self(toolsTitle: "Ferramentas de download", linkTitle: "Link de mídia",
                          batchTitle: "Download em lote", progressTitle: "Baixando")
    static let tr = Self(toolsTitle: "İndirme araçları", linkTitle: "Medya bağlantısı",
                         batchTitle: "Toplu indirme", progressTitle: "İndiriliyor")
    static let ru = Self(toolsTitle: "Средства загрузки", linkTitle: "Ссылка на медиа",
                         batchTitle: "Пакетная загрузка", progressTitle: "Загрузка")
    static let es = Self(toolsTitle: "Herramientas de descarga", linkTitle: "Enlace multimedia",
                         batchTitle: "Descarga por lotes", progressTitle: "Descargando")
    static let sk = Self(toolsTitle: "Nástroje na sťahovanie", linkTitle: "Odkaz na médiá",
                         batchTitle: "Hromadné sťahovanie", progressTitle: "Sťahovanie")
    static let de = Self(toolsTitle: "Download-Werkzeuge", linkTitle: "Medienlink",
                         batchTitle: "Stapel-Download", progressTitle: "Wird geladen")
    static let fr = Self(toolsTitle: "Outils de téléchargement", linkTitle: "Lien du média",
                         batchTitle: "Téléchargement par lot", progressTitle: "Téléchargement")
    static let it = Self(toolsTitle: "Strumenti di download", linkTitle: "Link multimediale",
                         batchTitle: "Download in batch", progressTitle: "Download in corso")
    static let ja = Self(toolsTitle: "ダウンロードツール", linkTitle: "メディアリンク",
                         batchTitle: "一括ダウンロード", progressTitle: "ダウンロード中")
    static let ko = Self(toolsTitle: "다운로드 도구", linkTitle: "미디어 링크",
                         batchTitle: "일괄 다운로드", progressTitle: "다운로드 중")
    static let uk = Self(toolsTitle: "Засоби завантаження", linkTitle: "Посилання на медіа",
                         batchTitle: "Пакетне завантаження", progressTitle: "Завантаження")
    static let zhHans = Self(toolsTitle: "下载工具", linkTitle: "媒体链接",
                             batchTitle: "批量下载", progressTitle: "正在下载")
    static let zhTW = Self(toolsTitle: "下載工具", linkTitle: "媒體連結",
                           batchTitle: "批次下載", progressTitle: "正在下載")
    static let zhHK = Self(toolsTitle: "下載工具", linkTitle: "媒體連結",
                           batchTitle: "批次下載", progressTitle: "正在下載")
}
