// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MediaAudioStrings {
    let tool: String
    let convert: String
    let bitRate: String
    let smallCaption: String
    let balancedCaption: String
    let highCaption: String
    let noAudio: String
}

extension FeatureStrings {
    static func mediaAudio(_ language: AppLanguage) -> MediaAudioStrings {
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

extension MediaAudioStrings {
    static let enUS = MediaAudioStrings(
        tool: "Audio",
        convert: "Convert to MP3",
        bitRate: "Bitrate",
        smallCaption: "Smallest files. Good for speech and podcasts.",
        balancedCaption: "Good quality for music at a moderate size.",
        highCaption: "Highest quality, with larger files.",
        noAudio: "This file has no audio track."
    )

    static let ptBR = MediaAudioStrings(
        tool: "Áudio",
        convert: "Converter em MP3",
        bitRate: "Taxa de bits",
        smallCaption: "Arquivos menores. Bom para fala e podcasts.",
        balancedCaption: "Boa qualidade para música com tamanho moderado.",
        highCaption: "Qualidade máxima, com arquivos maiores.",
        noAudio: "Este arquivo não tem trilha de áudio."
    )

    static let tr = MediaAudioStrings(
        tool: "Ses",
        convert: "MP3’e dönüştür",
        bitRate: "Bit hızı",
        smallCaption: "En küçük dosyalar. Konuşma ve podcast için uygun.",
        balancedCaption: "Makul boyutta, müzik için iyi kalite.",
        highCaption: "En yüksek kalite, daha büyük dosyalar.",
        noAudio: "Bu dosyada ses izi yok."
    )

    static let ru = MediaAudioStrings(
        tool: "Аудио",
        convert: "Конвертировать в MP3",
        bitRate: "Битрейт",
        smallCaption: "Самые маленькие файлы. Подходит для речи и подкастов.",
        balancedCaption: "Хорошее качество музыки при умеренном размере.",
        highCaption: "Наивысшее качество, файлы больше.",
        noAudio: "У этого файла нет аудиодорожки."
    )

    static let es = MediaAudioStrings(
        tool: "Audio",
        convert: "Convertir a MP3",
        bitRate: "Tasa de bits",
        smallCaption: "Archivos más pequeños. Bien para voz y podcasts.",
        balancedCaption: "Buena calidad para música con un tamaño moderado.",
        highCaption: "Máxima calidad, con archivos más grandes.",
        noAudio: "Este archivo no tiene pista de audio."
    )

    static let sk = MediaAudioStrings(
        tool: "Zvuk",
        convert: "Konvertovať do MP3",
        bitRate: "Dátový tok",
        smallCaption: "Najmenšie súbory. Vhodné na reč a podcasty.",
        balancedCaption: "Dobrá kvalita hudby pri primeranej veľkosti.",
        highCaption: "Najvyššia kvalita, väčšie súbory.",
        noAudio: "Tento súbor nemá zvukovú stopu."
    )

    static let de = MediaAudioStrings(
        tool: "Audio",
        convert: "In MP3 umwandeln",
        bitRate: "Bitrate",
        smallCaption: "Kleinste Dateien. Gut für Sprache und Podcasts.",
        balancedCaption: "Gute Qualität für Musik bei moderater Größe.",
        highCaption: "Höchste Qualität, größere Dateien.",
        noAudio: "Diese Datei hat keine Tonspur."
    )

    static let fr = MediaAudioStrings(
        tool: "Audio",
        convert: "Convertir en MP3",
        bitRate: "Débit",
        smallCaption: "Fichiers les plus légers. Idéal pour la voix et les podcasts.",
        balancedCaption: "Bonne qualité pour la musique, taille modérée.",
        highCaption: "Qualité maximale, fichiers plus lourds.",
        noAudio: "Ce fichier ne contient pas de piste audio."
    )

    static let it = MediaAudioStrings(
        tool: "Audio",
        convert: "Converti in MP3",
        bitRate: "Bitrate",
        smallCaption: "File più piccoli. Adatto a voce e podcast.",
        balancedCaption: "Buona qualità per la musica con dimensioni contenute.",
        highCaption: "Qualità massima, file più grandi.",
        noAudio: "Questo file non contiene una traccia audio."
    )

    static let ja = MediaAudioStrings(
        tool: "音声",
        convert: "MP3に変換",
        bitRate: "ビットレート",
        smallCaption: "最小のファイルサイズ。音声やポッドキャストに適しています。",
        balancedCaption: "適度なサイズで、音楽にも十分な音質です。",
        highCaption: "最高音質。ファイルは大きくなります。",
        noAudio: "このファイルにはオーディオトラックがありません。"
    )

    static let ko = MediaAudioStrings(
        tool: "오디오",
        convert: "MP3로 변환",
        bitRate: "비트레이트",
        smallCaption: "가장 작은 파일. 음성과 팟캐스트에 적합합니다.",
        balancedCaption: "적당한 크기로 음악에 좋은 품질입니다.",
        highCaption: "최고 품질, 파일이 더 큽니다.",
        noAudio: "이 파일에는 오디오 트랙이 없습니다."
    )

    static let uk = MediaAudioStrings(
        tool: "Аудіо",
        convert: "Конвертувати в MP3",
        bitRate: "Бітрейт",
        smallCaption: "Найменші файли. Підходить для мовлення й подкастів.",
        balancedCaption: "Добра якість музики за помірного розміру.",
        highCaption: "Найвища якість, більші файли.",
        noAudio: "У цього файлу немає аудіодоріжки."
    )

    static let zhHans = MediaAudioStrings(
        tool: "音频",
        convert: "转换为 MP3",
        bitRate: "比特率",
        smallCaption: "文件最小，适合语音和播客。",
        balancedCaption: "大小适中，音乐音质良好。",
        highCaption: "音质最高，文件更大。",
        noAudio: "此文件没有音频轨道。"
    )

    static let zhTW = MediaAudioStrings(
        tool: "音訊",
        convert: "轉換為 MP3",
        bitRate: "位元率",
        smallCaption: "檔案最小，適合語音和 Podcast。",
        balancedCaption: "大小適中，音樂音質良好。",
        highCaption: "音質最高，檔案較大。",
        noAudio: "此檔案沒有音訊軌道。"
    )

    static let zhHK = MediaAudioStrings(
        tool: "音訊",
        convert: "轉換為 MP3",
        bitRate: "位元率",
        smallCaption: "檔案最小，適合語音和播客。",
        balancedCaption: "大小適中，音樂音質良好。",
        highCaption: "音質最高，檔案較大。",
        noAudio: "此檔案沒有音訊軌道。"
    )
}
