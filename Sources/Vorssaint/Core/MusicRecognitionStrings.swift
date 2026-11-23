// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MusicRecognitionStrings {
    /// The button below the island, and the name of what it does.
    let title: String
    let listening: String
    let noMatch: String
    let failed: String
    let microphoneDenied: String
    let tryAgain: String

    static func localized(_ language: AppLanguage) -> MusicRecognitionStrings {
        switch language {
        case .enUS: return .init(title: "Recognise music", listening: "Listening…", noMatch: "No song recognised", failed: "Couldn’t recognise the song", microphoneDenied: "Allow the microphone for Vorssaint to recognise music", tryAgain: "Try again")
        case .ptBR: return .init(title: "Reconhecer música", listening: "Ouvindo…", noMatch: "Nenhuma música reconhecida", failed: "Não foi possível reconhecer a música", microphoneDenied: "Permita o microfone para o Vorssaint reconhecer músicas", tryAgain: "Tentar de novo")
        case .es: return .init(title: "Reconocer música", listening: "Escuchando…", noMatch: "No se reconoció ninguna canción", failed: "No se pudo reconocer la canción", microphoneDenied: "Permite el micrófono para que Vorssaint reconozca música", tryAgain: "Reintentar")
        case .sk: return .init(title: "Rozpoznať hudbu", listening: "Počúvam…", noMatch: "Nerozpoznala sa žiadna skladba", failed: "Skladbu sa nepodarilo rozpoznať", microphoneDenied: "Povoľte mikrofón, aby Vorssaint mohol rozpoznávať hudbu", tryAgain: "Skúsiť znova")
        case .de: return .init(title: "Musik erkennen", listening: "Hört zu …", noMatch: "Kein Song erkannt", failed: "Song konnte nicht erkannt werden", microphoneDenied: "Erlaube Vorssaint das Mikrofon, um Musik zu erkennen", tryAgain: "Erneut versuchen")
        case .fr: return .init(title: "Reconnaître la musique", listening: "Écoute…", noMatch: "Aucun morceau reconnu", failed: "Impossible de reconnaître le morceau", microphoneDenied: "Autorisez le micro pour que Vorssaint reconnaisse la musique", tryAgain: "Réessayer")
        case .it: return .init(title: "Riconosci musica", listening: "In ascolto…", noMatch: "Nessun brano riconosciuto", failed: "Impossibile riconoscere il brano", microphoneDenied: "Consenti il microfono perché Vorssaint riconosca la musica", tryAgain: "Riprova")
        case .ru: return .init(title: "Распознать музыку", listening: "Слушаю…", noMatch: "Песня не распознана", failed: "Не удалось распознать песню", microphoneDenied: "Разрешите Vorssaint доступ к микрофону, чтобы распознавать музыку", tryAgain: "Повторить")
        case .tr: return .init(title: "Müziği tanı", listening: "Dinleniyor…", noMatch: "Şarkı tanınamadı", failed: "Şarkı tanınamadı", microphoneDenied: "Vorssaint’in müziği tanıması için mikrofona izin verin", tryAgain: "Tekrar dene")
        case .ja: return .init(title: "音楽を認識", listening: "聴いています…", noMatch: "曲を認識できませんでした", failed: "曲を認識できませんでした", microphoneDenied: "音楽を認識するには Vorssaint にマイクを許可してください", tryAgain: "もう一度")
        case .ko: return .init(title: "음악 인식", listening: "듣는 중…", noMatch: "인식된 노래가 없습니다", failed: "노래를 인식할 수 없습니다", microphoneDenied: "음악을 인식하려면 Vorssaint에 마이크를 허용하세요", tryAgain: "다시 시도")
        case .zhHans: return .init(title: "识别音乐", listening: "正在聆听…", noMatch: "未识别到歌曲", failed: "无法识别这首歌", microphoneDenied: "允许 Vorssaint 使用麦克风以识别音乐", tryAgain: "重试")
        case .zhTW: return .init(title: "辨識音樂", listening: "正在聆聽…", noMatch: "未辨識到歌曲", failed: "無法辨識這首歌", microphoneDenied: "允許 Vorssaint 使用麥克風以辨識音樂", tryAgain: "重試")
        case .zhHK: return .init(title: "辨識音樂", listening: "正在聆聽…", noMatch: "未辨識到歌曲", failed: "無法辨識呢首歌", microphoneDenied: "允許 Vorssaint 使用咪高峰以辨識音樂", tryAgain: "再試")
        case .uk: return .init(title: "Розпізнати музику", listening: "Слухаю…", noMatch: "Пісню не розпізнано", failed: "Не вдалося розпізнати пісню", microphoneDenied: "Дозвольте Vorssaint доступ до мікрофона, щоб розпізнавати музику", tryAgain: "Ще раз")
        }
    }
}
