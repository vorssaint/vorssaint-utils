// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct RecorderExportFormatStrings {
    let format: String
    let video: String
    let gifSize: String
    let customSize: String
    let frameRate: String
}

extension FeatureStrings {
    static func recorderExportFormat(_ language: AppLanguage) -> RecorderExportFormatStrings {
        switch language {
        case .enUS:
            return RecorderExportFormatStrings(
                format: "Export format",
                video: "Video",
                gifSize: "GIF size",
                customSize: "Custom size",
                frameRate: "Frame rate")
        case .ptBR:
            return RecorderExportFormatStrings(
                format: "Formato de exportação",
                video: "Vídeo",
                gifSize: "Tamanho do GIF",
                customSize: "Tamanho personalizado",
                frameRate: "Taxa de quadros")
        case .tr:
            return RecorderExportFormatStrings(
                format: "Dışa aktarma biçimi",
                video: "Video",
                gifSize: "GIF boyutu",
                customSize: "Özel boyut",
                frameRate: "Kare hızı")
        case .ru:
            return RecorderExportFormatStrings(
                format: "Формат экспорта",
                video: "Видео",
                gifSize: "Размер GIF",
                customSize: "Свой размер",
                frameRate: "Частота кадров")
        case .es:
            return RecorderExportFormatStrings(
                format: "Formato de exportación",
                video: "Vídeo",
                gifSize: "Tamaño del GIF",
                customSize: "Tamaño personalizado",
                frameRate: "Fotogramas por segundo")
        case .sk:
            return RecorderExportFormatStrings(
                format: "Formát exportu",
                video: "Video",
                gifSize: "Veľkosť GIF",
                customSize: "Vlastná veľkosť",
                frameRate: "Snímková frekvencia")
        case .de:
            return RecorderExportFormatStrings(
                format: "Exportformat",
                video: "Video",
                gifSize: "GIF-Größe",
                customSize: "Eigene Größe",
                frameRate: "Bildrate")
        case .fr:
            return RecorderExportFormatStrings(
                format: "Format d’exportation",
                video: "Vidéo",
                gifSize: "Taille du GIF",
                customSize: "Taille personnalisée",
                frameRate: "Fréquence d’images")
        case .it:
            return RecorderExportFormatStrings(
                format: "Formato di esportazione",
                video: "Video",
                gifSize: "Dimensioni GIF",
                customSize: "Dimensioni personalizzate",
                frameRate: "Frequenza fotogrammi")
        case .ja:
            return RecorderExportFormatStrings(
                format: "書き出し形式",
                video: "動画",
                gifSize: "GIFサイズ",
                customSize: "カスタムサイズ",
                frameRate: "フレームレート")
        case .ko:
            return RecorderExportFormatStrings(
                format: "내보내기 형식",
                video: "동영상",
                gifSize: "GIF 크기",
                customSize: "사용자 지정 크기",
                frameRate: "프레임 속도")
        case .uk:
            return RecorderExportFormatStrings(
                format: "Формат експорту",
                video: "Відео",
                gifSize: "Розмір GIF",
                customSize: "Власний розмір",
                frameRate: "Частота кадрів")
        case .zhHans:
            return RecorderExportFormatStrings(
                format: "导出格式",
                video: "视频",
                gifSize: "GIF 大小",
                customSize: "自定义大小",
                frameRate: "帧率")
        case .zhTW:
            return RecorderExportFormatStrings(
                format: "匯出格式",
                video: "影片",
                gifSize: "GIF 大小",
                customSize: "自訂大小",
                frameRate: "影格率")
        case .zhHK:
            return RecorderExportFormatStrings(
                format: "匯出格式",
                video: "影片",
                gifSize: "GIF 大小",
                customSize: "自訂大小",
                frameRate: "影格率")
        case .ca:
            return RecorderExportFormatStrings(
                format: "Format d’exportació",
                video: "Vídeo",
                gifSize: "Mida del GIF",
                customSize: "Mida personalitzada",
                frameRate: "Freqüència de fotogrames")
        }
    }
}
