// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for multi-model transcription selection (Parakeet English
/// and ivrit.ai Hebrew) and automatic language routing across all 15 languages.
struct TranscriptionModelStrings {
    let modelChoiceLabel: String
    let modelAuto: String
    let modelParakeet: String
    let modelIvrit: String
    let modelAutoCaption: String
    let ivritModelTitle: String
    let ivritModelMissingStatus: String
    let detectedLanguageFormat: String
    let languageEnglish: String
    let languageHebrew: String
    let ivritModelReadyHUD: String

    static func localized(_ language: AppLanguage) -> TranscriptionModelStrings {
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

extension TranscriptionModelStrings {
    static let enUS = TranscriptionModelStrings(
        modelChoiceLabel: "Model",
        modelAuto: "Auto (English & Hebrew)",
        modelParakeet: "Parakeet 0.6B (English)",
        modelIvrit: "ivrit.ai Turbo (Hebrew)",
        modelAutoCaption: "Detects the spoken language automatically per recording and routes English to Parakeet 0.6B and Hebrew to ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Hebrew)",
        ivritModelMissingStatus: "Not downloaded (~895 MB one-time download)",
        detectedLanguageFormat: "Detected: %@",
        languageEnglish: "English",
        languageHebrew: "Hebrew",
        ivritModelReadyHUD: "ivrit.ai Hebrew model ready"
    )

    static let ptBR = TranscriptionModelStrings(
        modelChoiceLabel: "Modelo",
        modelAuto: "Automático (Inglês e Hebraico)",
        modelParakeet: "Parakeet 0.6B (Inglês)",
        modelIvrit: "ivrit.ai Turbo (Hebraico)",
        modelAutoCaption: "Detecta o idioma falado automaticamente por gravação e direciona inglês para o Parakeet 0.6B e hebraico para o ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Hebraico)",
        ivritModelMissingStatus: "Não baixado (~895 MB, download único)",
        detectedLanguageFormat: "Detectado: %@",
        languageEnglish: "Inglês",
        languageHebrew: "Hebraico",
        ivritModelReadyHUD: "Modelo hebraico ivrit.ai pronto"
    )

    static let es = TranscriptionModelStrings(
        modelChoiceLabel: "Modelo",
        modelAuto: "Automático (Inglés y Hebreo)",
        modelParakeet: "Parakeet 0.6B (Inglés)",
        modelIvrit: "ivrit.ai Turbo (Hebreo)",
        modelAutoCaption: "Detecta automáticamente el idioma hablado en cada grabación y usa Parakeet 0.6B para inglés e ivrit.ai Whisper Large v3 Turbo para hebreo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Hebreo)",
        ivritModelMissingStatus: "Sin descargar (~895 MB, descarga única)",
        detectedLanguageFormat: "Detectado: %@",
        languageEnglish: "Inglés",
        languageHebrew: "Hebreo",
        ivritModelReadyHUD: "Modelo hebreo ivrit.ai listo"
    )

    static let sk = TranscriptionModelStrings(
        modelChoiceLabel: "Model",
        modelAuto: "Automaticky (Angličtina a Hebrejčina)",
        modelParakeet: "Parakeet 0.6B (Angličtina)",
        modelIvrit: "ivrit.ai Turbo (Hebrejčina)",
        modelAutoCaption: "Automaticky rozpozná hovorený jazyk pre každú nahrávku a nasmeruje angličtinu na Parakeet 0.6B a hebrejčinu na ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Hebrejčina)",
        ivritModelMissingStatus: "Nestiahnuté (~895 MB, jednorazové stiahnutie)",
        detectedLanguageFormat: "Rozpoznané: %@",
        languageEnglish: "Angličtina",
        languageHebrew: "Hebrejčina",
        ivritModelReadyHUD: "Hebrejský model ivrit.ai je pripravený"
    )

    static let tr = TranscriptionModelStrings(
        modelChoiceLabel: "Model",
        modelAuto: "Otomatik (İngilizce ve İbranice)",
        modelParakeet: "Parakeet 0.6B (İngilizce)",
        modelIvrit: "ivrit.ai Turbo (İbranice)",
        modelAutoCaption: "Her kayıtta konuşulan dili otomatik algılar; İngilizceyi Parakeet 0.6B’ye, İbraniceyi ivrit.ai Whisper Large v3 Turbo’ya yönlendirir.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (İbranice)",
        ivritModelMissingStatus: "İndirilmedi (~895 MB tek seferlik indirme)",
        detectedLanguageFormat: "Algılanan: %@",
        languageEnglish: "İngilizce",
        languageHebrew: "İbranice",
        ivritModelReadyHUD: "ivrit.ai İbranice modeli hazır"
    )

    static let ru = TranscriptionModelStrings(
        modelChoiceLabel: "Модель",
        modelAuto: "Авто (Английский и Иврит)",
        modelParakeet: "Parakeet 0.6B (Английский)",
        modelIvrit: "ivrit.ai Turbo (Иврит)",
        modelAutoCaption: "Автоматически определяет язык речи в каждой записи и направляет английский в Parakeet 0.6B, а иврит в ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Иврит)",
        ivritModelMissingStatus: "Не загружено (~895 МБ, разовая загрузка)",
        detectedLanguageFormat: "Определено: %@",
        languageEnglish: "Английский",
        languageHebrew: "Иврит",
        ivritModelReadyHUD: "Модель иврита ivrit.ai готова"
    )

    static let de = TranscriptionModelStrings(
        modelChoiceLabel: "Modell",
        modelAuto: "Automatisch (Englisch & Hebräisch)",
        modelParakeet: "Parakeet 0.6B (Englisch)",
        modelIvrit: "ivrit.ai Turbo (Hebräisch)",
        modelAutoCaption: "Erkennt die gesprochene Sprache pro Aufnahme automatisch und leitet Englisch an Parakeet 0.6B und Hebräisch an ivrit.ai Whisper Large v3 Turbo weiter.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Hebräisch)",
        ivritModelMissingStatus: "Nicht geladen (~895 MB, einmaliger Download)",
        detectedLanguageFormat: "Erkannt: %@",
        languageEnglish: "Englisch",
        languageHebrew: "Hebräisch",
        ivritModelReadyHUD: "ivrit.ai Hebräisch-Modell bereit"
    )

    static let fr = TranscriptionModelStrings(
        modelChoiceLabel: "Modèle",
        modelAuto: "Auto (Anglais et Hébreu)",
        modelParakeet: "Parakeet 0.6B (Anglais)",
        modelIvrit: "ivrit.ai Turbo (Hébreu)",
        modelAutoCaption: "Détecte automatiquement la langue parlée pour chaque enregistrement et redirige l’anglais vers Parakeet 0.6B et l’hébreu vers ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Hébreu)",
        ivritModelMissingStatus: "Non téléchargé (~895 Mo, téléchargement unique)",
        detectedLanguageFormat: "Détecté\u{00A0}: %@",
        languageEnglish: "Anglais",
        languageHebrew: "Hébreu",
        ivritModelReadyHUD: "Modèle hébreu ivrit.ai prêt"
    )

    static let it = TranscriptionModelStrings(
        modelChoiceLabel: "Modello",
        modelAuto: "Automatico (Inglese ed Ebraico)",
        modelParakeet: "Parakeet 0.6B (Inglese)",
        modelIvrit: "ivrit.ai Turbo (Ebraico)",
        modelAutoCaption: "Rileva automaticamente la lingua parlata per ogni registrazione e indirizza l’inglese a Parakeet 0.6B e l’ebraico a ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Ebraico)",
        ivritModelMissingStatus: "Non scaricato (~895 MB, download unico)",
        detectedLanguageFormat: "Rilevato: %@",
        languageEnglish: "Inglese",
        languageHebrew: "Ebraico",
        ivritModelReadyHUD: "Modello ebraico ivrit.ai pronto"
    )

    static let ja = TranscriptionModelStrings(
        modelChoiceLabel: "モデル",
        modelAuto: "自動（英語・ヘブライ語）",
        modelParakeet: "Parakeet 0.6B（英語）",
        modelIvrit: "ivrit.ai Turbo（ヘブライ語）",
        modelAutoCaption: "録音ごとに話されている言語を自動検出し、英語は Parakeet 0.6B、ヘブライ語は ivrit.ai Whisper Large v3 Turbo に振り分けます。",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo（ヘブライ語）",
        ivritModelMissingStatus: "未ダウンロード（初回のみ約 895 MB）",
        detectedLanguageFormat: "検出言語: %@",
        languageEnglish: "英語",
        languageHebrew: "ヘブライ語",
        ivritModelReadyHUD: "ivrit.ai ヘブライ語モデルの準備完了"
    )

    static let ko = TranscriptionModelStrings(
        modelChoiceLabel: "모델",
        modelAuto: "자동 (영어 및 히브리어)",
        modelParakeet: "Parakeet 0.6B (영어)",
        modelIvrit: "ivrit.ai Turbo (히브리어)",
        modelAutoCaption: "녹음마다 음성의 언어를 자동 감지하여 영어는 Parakeet 0.6B로, 히브리어는 ivrit.ai Whisper Large v3 Turbo로 라우팅합니다.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (히브리어)",
        ivritModelMissingStatus: "다운로드되지 않음 (최초 약 895 MB)",
        detectedLanguageFormat: "감지됨: %@",
        languageEnglish: "영어",
        languageHebrew: "히브리어",
        ivritModelReadyHUD: "ivrit.ai 히브리어 모델 준비 완료"
    )

    static let uk = TranscriptionModelStrings(
        modelChoiceLabel: "Модель",
        modelAuto: "Авто (Англійська та Іврит)",
        modelParakeet: "Parakeet 0.6B (Англійська)",
        modelIvrit: "ivrit.ai Turbo (Іврит)",
        modelAutoCaption: "Автоматично визначає мову мовлення для кожного запису та спрямовує англійську в Parakeet 0.6B, а іврит в ivrit.ai Whisper Large v3 Turbo.",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo (Іврит)",
        ivritModelMissingStatus: "Не завантажено (~895 МБ, разове завантаження)",
        detectedLanguageFormat: "Визначено: %@",
        languageEnglish: "Англійська",
        languageHebrew: "Іврит",
        ivritModelReadyHUD: "Модель івриту ivrit.ai готова"
    )

    static let zhHans = TranscriptionModelStrings(
        modelChoiceLabel: "模型",
        modelAuto: "自动（英语和希伯来语）",
        modelParakeet: "Parakeet 0.6B（英语）",
        modelIvrit: "ivrit.ai Turbo（希伯来语）",
        modelAutoCaption: "按录音自动检测语音语种，将英语路由至 Parakeet 0.6B，将希伯来语路由至 ivrit.ai Whisper Large v3 Turbo。",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo（希伯来语）",
        ivritModelMissingStatus: "未下载（首次约 895 MB）",
        detectedLanguageFormat: "已检测：%@",
        languageEnglish: "英语",
        languageHebrew: "希伯来语",
        ivritModelReadyHUD: "ivrit.ai 希伯来语模型已就绪"
    )

    static let zhTW = TranscriptionModelStrings(
        modelChoiceLabel: "模型",
        modelAuto: "自動（英語與希伯來語）",
        modelParakeet: "Parakeet 0.6B（英語）",
        modelIvrit: "ivrit.ai Turbo（希伯來語）",
        modelAutoCaption: "依錄音自動偵測語音語種，將英語路由至 Parakeet 0.6B，將希伯來語路由至 ivrit.ai Whisper Large v3 Turbo。",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo（希伯來語）",
        ivritModelMissingStatus: "尚未下載（首次約 895 MB）",
        detectedLanguageFormat: "已偵測：%@",
        languageEnglish: "英語",
        languageHebrew: "希伯來語",
        ivritModelReadyHUD: "ivrit.ai 希伯來語模型已就緒"
    )

    static let zhHK = TranscriptionModelStrings(
        modelChoiceLabel: "模型",
        modelAuto: "自動（英語同希伯來語）",
        modelParakeet: "Parakeet 0.6B（英語）",
        modelIvrit: "ivrit.ai Turbo（希伯來語）",
        modelAutoCaption: "按錄音自動偵測語音語種，將英語交畀 Parakeet 0.6B，將希伯來語交畀 ivrit.ai Whisper Large v3 Turbo。",
        ivritModelTitle: "ivrit.ai Whisper Large v3 Turbo（希伯來語）",
        ivritModelMissingStatus: "未下載（首次約 895 MB）",
        detectedLanguageFormat: "已偵測：%@",
        languageEnglish: "英語",
        languageHebrew: "希伯來語",
        ivritModelReadyHUD: "ivrit.ai 希伯來語模型已準備好"
    )
}
