// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screen recorder.
struct RecorderFeatureStrings {
    let moreOptions: String
    let gifTooLongFormat: String
    let microphonePermissionName: String
    let microphonePermissionExplain: String
}

extension FeatureStrings {
    static func recorder(_ language: AppLanguage) -> RecorderFeatureStrings {
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

extension RecorderFeatureStrings {
    static let enUS = RecorderFeatureStrings(
        moreOptions: "More options",
        gifTooLongFormat: "A GIF can be up to %d seconds long",
        microphonePermissionName: "Microphone",
        microphonePermissionExplain: "Lets screen recordings include your voice when you turn it on."
    )

    static let ptBR = RecorderFeatureStrings(
        moreOptions: "Mais opções",
        gifTooLongFormat: "Um GIF pode ter até %d segundos",
        microphonePermissionName: "Microfone",
        microphonePermissionExplain: "Permite incluir sua voz nas gravações de tela quando você ativar."
    )

    static let tr = RecorderFeatureStrings(
        moreOptions: "Diğer seçenekler",
        gifTooLongFormat: "GIF en fazla %d saniye uzunluğunda olabilir",
        microphonePermissionName: "Mikrofon",
        microphonePermissionExplain: "Açtığınızda ekran kayıtlarına sesinizi ekler."
    )

    static let ru = RecorderFeatureStrings(
        moreOptions: "Дополнительно",
        gifTooLongFormat: "GIF может длиться до %d секунд",
        microphonePermissionName: "Микрофон",
        microphonePermissionExplain: "Добавляет ваш голос в запись экрана, когда вы это включаете."
    )

    static let es = RecorderFeatureStrings(
        moreOptions: "Más opciones",
        gifTooLongFormat: "Un GIF puede durar como máximo %d segundos",
        microphonePermissionName: "Micrófono",
        microphonePermissionExplain: "Permite incluir tu voz en las grabaciones de pantalla al activarlo."
    )

    static let sk = RecorderFeatureStrings(
        moreOptions: "Ďalšie možnosti",
        gifTooLongFormat: "Maximálna dĺžka GIF: %d s",
        microphonePermissionName: "Mikrofón",
        microphonePermissionExplain: "Po zapnutí umožňuje pridať váš hlas do nahrávok obrazovky."
    )

    static let de = RecorderFeatureStrings(
        moreOptions: "Weitere Optionen",
        gifTooLongFormat: "Ein GIF darf höchstens %d Sekunden lang sein",
        microphonePermissionName: "Mikrofon",
        microphonePermissionExplain: "Nimmt deine Stimme auf Wunsch in Bildschirmaufnahmen auf."
    )

    static let fr = RecorderFeatureStrings(
        moreOptions: "Plus d’options",
        gifTooLongFormat: "Un GIF peut durer jusqu’à %d secondes",
        microphonePermissionName: "Microphone",
        microphonePermissionExplain: "Permet d’ajouter votre voix aux enregistrements d’écran si vous l’activez."
    )

    static let it = RecorderFeatureStrings(
        moreOptions: "Altre opzioni",
        gifTooLongFormat: "Una GIF può durare al massimo %d secondi",
        microphonePermissionName: "Microfono",
        microphonePermissionExplain: "Include la tua voce nelle registrazioni dello schermo quando lo attivi."
    )

    static let ja = RecorderFeatureStrings(
        moreOptions: "その他のオプション",
        gifTooLongFormat: "GIFの長さは最大%d秒です",
        microphonePermissionName: "マイク",
        microphonePermissionExplain: "オンにすると画面収録に声を含められます。"
    )

    static let ko = RecorderFeatureStrings(
        moreOptions: "추가 옵션",
        gifTooLongFormat: "GIF는 최대 %d초까지 만들 수 있습니다",
        microphonePermissionName: "마이크",
        microphonePermissionExplain: "켜면 화면 녹화에 음성을 포함합니다."
    )

    static let zhHans = RecorderFeatureStrings(
        moreOptions: "更多选项",
        gifTooLongFormat: "GIF 最长为 %d 秒",
        microphonePermissionName: "麦克风",
        microphonePermissionExplain: "开启后可在屏幕录制中加入你的声音。"
    )

    static let zhTW = RecorderFeatureStrings(
        moreOptions: "更多選項",
        gifTooLongFormat: "GIF 長度最多 %d 秒",
        microphonePermissionName: "麥克風",
        microphonePermissionExplain: "開啟後可在螢幕錄製中加入你的聲音。"
    )

    static let zhHK = RecorderFeatureStrings(
        moreOptions: "更多選項",
        gifTooLongFormat: "GIF 最長 %d 秒",
        microphonePermissionName: "咪高風",
        microphonePermissionExplain: "開啟後可在螢幕錄製加入你的聲音。"
    )
    static let uk = RecorderFeatureStrings(
        moreOptions: "Більше опцій",
        gifTooLongFormat: "GIF може тривати щонайбільше %d с",
        microphonePermissionName: "Мікрофон",
        microphonePermissionExplain: "Дозволяє записам екрана включати ваш голос, коли ви це вмикаєте."
    )
}
