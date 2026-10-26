// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TrackpadGuardStrings {
    let title: String
    let description: String
    let appsTitle: String
    let ignoring: String
    let unavailable: String

    static let enUS = TrackpadGuardStrings(
        title: "Trackpad guard",
        description: "Ignore the built-in trackpad in selected apps while a mouse is connected.",
        appsTitle: "Apps",
        ignoring: "Ignoring the built-in trackpad.",
        unavailable: "Trackpad control is unavailable. Turn this feature off and on to retry."
    )

    static let ptBR = TrackpadGuardStrings(
        title: "Proteção do trackpad",
        description: "Ignore o trackpad integrado nos apps escolhidos enquanto um mouse estiver conectado.",
        appsTitle: "Apps",
        ignoring: "Ignorando o trackpad integrado.",
        unavailable: "O controle do trackpad está indisponível. Desative e reative este recurso para tentar novamente."
    )

    static let fr = TrackpadGuardStrings(
        title: "Protection du trackpad",
        description: "Ignore le trackpad intégré dans les apps choisies lorsqu’une souris est connectée.",
        appsTitle: "Apps",
        ignoring: "Trackpad intégré ignoré.",
        unavailable: "Le contrôle du trackpad est indisponible. Désactivez puis réactivez cette fonction pour réessayer."
    )

    static let de = TrackpadGuardStrings(
        title: "Trackpad-Schutz",
        description: "Ignoriert das integrierte Trackpad in ausgewählten Apps, solange eine Maus verbunden ist.",
        appsTitle: "Apps",
        ignoring: "Integriertes Trackpad wird ignoriert.",
        unavailable: "Die Trackpad-Steuerung ist nicht verfügbar. Schalte diese Funktion aus und wieder ein, um es erneut zu versuchen."
    )

    static let es = TrackpadGuardStrings(
        title: "Protección del trackpad",
        description: "Ignora el trackpad integrado en las apps elegidas mientras haya un ratón conectado.",
        appsTitle: "Apps",
        ignoring: "Ignorando el trackpad integrado.",
        unavailable: "El control del trackpad no está disponible. Desactiva y vuelve a activar esta función para reintentarlo."
    )

    static let it = TrackpadGuardStrings(
        title: "Protezione del trackpad",
        description: "Ignora il trackpad integrato nelle app scelte mentre è collegato un mouse.",
        appsTitle: "App",
        ignoring: "Trackpad integrato ignorato.",
        unavailable: "Il controllo del trackpad non è disponibile. Disattiva e riattiva questa funzione per riprovare."
    )

    static let ru = TrackpadGuardStrings(
        title: "Защита трекпада",
        description: "Игнорирует встроенный трекпад в выбранных приложениях, пока подключена мышь.",
        appsTitle: "Приложения",
        ignoring: "Встроенный трекпад игнорируется.",
        unavailable: "Управление трекпадом недоступно. Выключите и снова включите эту функцию, чтобы повторить попытку."
    )

    static let uk = TrackpadGuardStrings(
        title: "Захист трекпада",
        description: "Ігнорує вбудований трекпад у вибраних програмах, поки підключено мишу.",
        appsTitle: "Програми",
        ignoring: "Вбудований трекпад ігнорується.",
        unavailable: "Керування трекпадом недоступне. Вимкніть і знову ввімкніть цю функцію, щоб повторити спробу."
    )

    static let sk = TrackpadGuardStrings(
        title: "Ochrana trackpadu",
        description: "Ignoruje vstavaný trackpad vo vybraných aplikáciách, kým je pripojená myš.",
        appsTitle: "Aplikácie",
        ignoring: "Vstavaný trackpad sa ignoruje.",
        unavailable: "Ovládanie trackpadu nie je dostupné. Vypnite a znova zapnite túto funkciu a skúste to znova."
    )

    static let tr = TrackpadGuardStrings(
        title: "İzleme dörtgeni koruması",
        description: "Fare bağlıyken seçilen uygulamalarda yerleşik izleme dörtgenini yok sayar.",
        appsTitle: "Uygulamalar",
        ignoring: "Yerleşik izleme dörtgeni yok sayılıyor.",
        unavailable: "İzleme dörtgeni denetimi kullanılamıyor. Yeniden denemek için bu özelliği kapatıp açın."
    )

    static let ja = TrackpadGuardStrings(
        title: "トラックパッド保護",
        description: "マウスの接続中、選択したアプリで内蔵トラックパッドを無視します。",
        appsTitle: "アプリ",
        ignoring: "内蔵トラックパッドを無視しています。",
        unavailable: "トラックパッドを制御できません。この機能をオフにしてからオンにして、再試行してください。"
    )

    static let ko = TrackpadGuardStrings(
        title: "트랙패드 보호",
        description: "마우스가 연결된 동안 선택한 앱에서 내장 트랙패드를 무시합니다.",
        appsTitle: "앱",
        ignoring: "내장 트랙패드를 무시하는 중입니다.",
        unavailable: "트랙패드를 제어할 수 없습니다. 다시 시도하려면 이 기능을 껐다가 켜세요."
    )

    static let zhHans = TrackpadGuardStrings(
        title: "触控板保护",
        description: "连接鼠标时，在所选应用中忽略内建触控板。",
        appsTitle: "应用",
        ignoring: "正在忽略内建触控板。",
        unavailable: "触控板控制不可用。请关闭并重新开启此功能以重试。"
    )

    static let zhTW = TrackpadGuardStrings(
        title: "觸控板保護",
        description: "連接滑鼠時，在所選 App 中忽略內建觸控板。",
        appsTitle: "App",
        ignoring: "正在忽略內建觸控板。",
        unavailable: "觸控板控制無法使用。請關閉並重新開啟此功能以重試。"
    )

    static let zhHK = TrackpadGuardStrings(
        title: "觸控板保護",
        description: "連接滑鼠時，在所選 App 中忽略內置觸控板。",
        appsTitle: "App",
        ignoring: "正在忽略內置觸控板。",
        unavailable: "無法控制觸控板。請關閉並重新開啟此功能以重試。"
    )

}

extension FeatureStrings {
    static func trackpadGuard(_ language: AppLanguage) -> TrackpadGuardStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .fr: return .fr
        case .de: return .de
        case .es: return .es
        case .it: return .it
        case .ru: return .ru
        case .uk: return .uk
        case .sk: return .sk
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}
