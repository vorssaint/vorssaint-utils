// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderToolsCategory: String, CaseIterable, Identifiable {
    case files, copy, media, pdf, system
    var id: String { rawValue }
    func title(language: String) -> String {
        let values: [String]
        switch language {
        case "pt-BR": values = ["Arquivos", "Copiar como", "Imagens e mídia", "PDF", "Sistema"]
        case "tr": values = ["Dosyalar", "Farklı Kopyala", "Görseller ve Medya", "PDF", "Sistem"]
        case "ru": values = ["Файлы", "Копировать как", "Изображения и медиа", "PDF", "Система"]
        case "es": values = ["Archivos", "Copiar como", "Imágenes y multimedia", "PDF", "Sistema"]
        case "sk": values = ["Súbory", "Kopírovať ako", "Obrázky a médiá", "PDF", "Systém"]
        case "de": values = ["Dateien", "Kopieren als", "Bilder und Medien", "PDF", "System"]
        case "fr": values = ["Fichiers", "Copier comme", "Images et médias", "PDF", "Système"]
        case "it": values = ["File", "Copia come", "Immagini e media", "PDF", "Sistema"]
        case "ja": values = ["ファイル", "形式を選んでコピー", "画像とメディア", "PDF", "システム"]
        case "ko": values = ["파일", "다음으로 복사", "이미지 및 미디어", "PDF", "시스템"]
        case "zh-Hans": values = ["文件", "复制为", "图像和媒体", "PDF", "系统"]
        case "zh-TW", "zh-HK": values = ["檔案", "複製為", "影像和媒體", "PDF", "系統"]
        case "uk": values = ["Файли", "Копіювати як", "Зображення й медіа", "PDF", "Система"]
        default: values = ["Files", "Copy As", "Images and Media", "PDF", "System"]
        }
        return values[Self.allCases.firstIndex(of: self)!]
    }
}

extension FinderToolsAction {
    var category: FinderToolsCategory {
        switch self {
        case .mergePDF, .splitPDF, .watermarkPDF, .compressPDF: return .pdf
        case .rotateLeft, .rotateRight, .stitchHorizontal, .stitchVertical, .removeBackground,
             .replaceBackground, .recolor, .readQR, .editImage, .convertImages, .convertVideo,
             .extractText, .extractIcon, .extractAudio, .pasteImage: return .media
        case .copyPath, .copyName, .copyStem, .copyMarkdown, .copyContents, .fileTree, .directoryTree,
             .size, .sha256, .copySummary: return .copy
        case .recordAudio, .recordVideo, .quickLook, .reveal, .info, .eject, .wallpaper, .share, .openTerminal: return .system
        default: return .files
        }
    }
}
