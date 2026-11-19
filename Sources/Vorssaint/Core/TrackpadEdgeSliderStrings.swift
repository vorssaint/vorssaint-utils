// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TrackpadEdgeSliderStrings {
    let title: String
    let caption: String
    let leftLabel: String
    let rightLabel: String
    let actionOff: String
    let actionBrightness: String
    let actionVolume: String
    let widthLabel: String
    let sensitivityLabel: String
    let hapticsLabel: String
    let reverseLabel: String

    func label(for action: TrackpadEdgeSliderAction) -> String {
        switch action {
        case .off: return actionOff
        case .brightness: return actionBrightness
        case .volume: return actionVolume
        }
    }
}

extension FeatureStrings {
    static func trackpadEdgeSliders(_ language: AppLanguage) -> TrackpadEdgeSliderStrings {
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

extension TrackpadEdgeSliderStrings {
    static let enUS = TrackpadEdgeSliderStrings(
        title: "Trackpad edge sliders",
        caption: "Slide one finger along the left or right edge of the trackpad to change brightness or volume.",
        leftLabel: "Left edge",
        rightLabel: "Right edge",
        actionOff: "Off",
        actionBrightness: "Brightness",
        actionVolume: "Volume",
        widthLabel: "Edge width",
        sensitivityLabel: "Sensitivity",
        hapticsLabel: "Haptic feedback",
        reverseLabel: "Reverse direction"
    )

    static let ptBR = TrackpadEdgeSliderStrings(
        title: "Controles nas bordas do trackpad",
        caption: "Deslize um dedo pela borda esquerda ou direita do trackpad para mudar o brilho ou o volume.",
        leftLabel: "Borda esquerda",
        rightLabel: "Borda direita",
        actionOff: "Desligado",
        actionBrightness: "Brilho",
        actionVolume: "Volume",
        widthLabel: "Largura da borda",
        sensitivityLabel: "Sensibilidade",
        hapticsLabel: "Resposta tátil",
        reverseLabel: "Inverter direção"
    )

    static let tr = TrackpadEdgeSliderStrings(
        title: "İzleme dörtgeni kenar kaydırıcıları",
        caption: "Parlaklığı veya sesi değiştirmek için tek parmağınızı izleme dörtgeninin sol ya da sağ kenarı boyunca kaydırın.",
        leftLabel: "Sol kenar",
        rightLabel: "Sağ kenar",
        actionOff: "Kapalı",
        actionBrightness: "Parlaklık",
        actionVolume: "Ses",
        widthLabel: "Kenar genişliği",
        sensitivityLabel: "Hassasiyet",
        hapticsLabel: "Dokunsal geri bildirim",
        reverseLabel: "Yönü ters çevir"
    )

    static let ru = TrackpadEdgeSliderStrings(
        title: "Ползунки по краям трекпада",
        caption: "Проведите одним пальцем вдоль левого или правого края трекпада, чтобы изменить яркость или громкость.",
        leftLabel: "Левый край",
        rightLabel: "Правый край",
        actionOff: "Выключено",
        actionBrightness: "Яркость",
        actionVolume: "Громкость",
        widthLabel: "Ширина края",
        sensitivityLabel: "Чувствительность",
        hapticsLabel: "Тактильный отклик",
        reverseLabel: "Обратное направление"
    )

    static let es = TrackpadEdgeSliderStrings(
        title: "Deslizadores en los bordes del trackpad",
        caption: "Desliza un dedo por el borde izquierdo o derecho del trackpad para cambiar el brillo o el volumen.",
        leftLabel: "Borde izquierdo",
        rightLabel: "Borde derecho",
        actionOff: "Desactivado",
        actionBrightness: "Brillo",
        actionVolume: "Volumen",
        widthLabel: "Ancho del borde",
        sensitivityLabel: "Sensibilidad",
        hapticsLabel: "Respuesta háptica",
        reverseLabel: "Invertir dirección"
    )

    static let sk = TrackpadEdgeSliderStrings(
        title: "Posuvníky na okrajoch trackpadu",
        caption: "Posunutím jedného prsta po ľavom alebo pravom okraji trackpadu zmeníte jas alebo hlasitosť.",
        leftLabel: "Ľavý okraj",
        rightLabel: "Pravý okraj",
        actionOff: "Vypnuté",
        actionBrightness: "Jas",
        actionVolume: "Hlasitosť",
        widthLabel: "Šírka okraja",
        sensitivityLabel: "Citlivosť",
        hapticsLabel: "Haptická odozva",
        reverseLabel: "Obrátiť smer"
    )

    static let de = TrackpadEdgeSliderStrings(
        title: "Schieberegler am Trackpad-Rand",
        caption: "Mit einem Finger am linken oder rechten Rand des Trackpads entlangstreichen, um Helligkeit oder Lautstärke zu ändern.",
        leftLabel: "Linker Rand",
        rightLabel: "Rechter Rand",
        actionOff: "Aus",
        actionBrightness: "Helligkeit",
        actionVolume: "Lautstärke",
        widthLabel: "Randbreite",
        sensitivityLabel: "Empfindlichkeit",
        hapticsLabel: "Haptisches Feedback",
        reverseLabel: "Richtung umkehren"
    )

    static let fr = TrackpadEdgeSliderStrings(
        title: "Curseurs sur les bords du trackpad",
        caption: "Faites glisser un doigt le long du bord gauche ou droit du trackpad pour modifier la luminosité ou le volume.",
        leftLabel: "Bord gauche",
        rightLabel: "Bord droit",
        actionOff: "Désactivé",
        actionBrightness: "Luminosité",
        actionVolume: "Volume",
        widthLabel: "Largeur du bord",
        sensitivityLabel: "Sensibilité",
        hapticsLabel: "Retour haptique",
        reverseLabel: "Inverser le sens"
    )

    static let it = TrackpadEdgeSliderStrings(
        title: "Cursori sui bordi del trackpad",
        caption: "Fai scorrere un dito lungo il bordo sinistro o destro del trackpad per cambiare la luminosità o il volume.",
        leftLabel: "Bordo sinistro",
        rightLabel: "Bordo destro",
        actionOff: "Disattivato",
        actionBrightness: "Luminosità",
        actionVolume: "Volume",
        widthLabel: "Larghezza del bordo",
        sensitivityLabel: "Sensibilità",
        hapticsLabel: "Feedback aptico",
        reverseLabel: "Inverti direzione"
    )

    static let ja = TrackpadEdgeSliderStrings(
        title: "トラックパッドのエッジスライダー",
        caption: "トラックパッドの左端または右端に沿って指を1本滑らせると、輝度または音量を変更できます。",
        leftLabel: "左端",
        rightLabel: "右端",
        actionOff: "オフ",
        actionBrightness: "輝度",
        actionVolume: "音量",
        widthLabel: "端の幅",
        sensitivityLabel: "感度",
        hapticsLabel: "触覚フィードバック",
        reverseLabel: "方向を反転"
    )

    static let ko = TrackpadEdgeSliderStrings(
        title: "트랙패드 가장자리 슬라이더",
        caption: "트랙패드의 왼쪽 또는 오른쪽 가장자리를 따라 손가락 하나를 밀어 밝기나 음량을 조절합니다.",
        leftLabel: "왼쪽 가장자리",
        rightLabel: "오른쪽 가장자리",
        actionOff: "끔",
        actionBrightness: "밝기",
        actionVolume: "음량",
        widthLabel: "가장자리 너비",
        sensitivityLabel: "감도",
        hapticsLabel: "햅틱 피드백",
        reverseLabel: "방향 반전"
    )

    static let zhHans = TrackpadEdgeSliderStrings(
        title: "触控板边缘滑动条",
        caption: "用一根手指沿触控板的左边缘或右边缘滑动，即可调节亮度或音量。",
        leftLabel: "左边缘",
        rightLabel: "右边缘",
        actionOff: "关闭",
        actionBrightness: "亮度",
        actionVolume: "音量",
        widthLabel: "边缘宽度",
        sensitivityLabel: "灵敏度",
        hapticsLabel: "触感反馈",
        reverseLabel: "反转方向"
    )

    static let zhTW = TrackpadEdgeSliderStrings(
        title: "觸控式軌跡板邊緣滑桿",
        caption: "用一根手指沿著觸控式軌跡板的左邊緣或右邊緣滑動，即可調整亮度或音量。",
        leftLabel: "左邊緣",
        rightLabel: "右邊緣",
        actionOff: "關閉",
        actionBrightness: "亮度",
        actionVolume: "音量",
        widthLabel: "邊緣寬度",
        sensitivityLabel: "靈敏度",
        hapticsLabel: "觸覺回饋",
        reverseLabel: "反轉方向"
    )

    static let zhHK = TrackpadEdgeSliderStrings(
        title: "觸控板邊緣滑桿",
        caption: "用一隻手指沿著觸控板的左邊緣或右邊緣滑動，即可調整亮度或音量。",
        leftLabel: "左邊緣",
        rightLabel: "右邊緣",
        actionOff: "關閉",
        actionBrightness: "亮度",
        actionVolume: "音量",
        widthLabel: "邊緣寬度",
        sensitivityLabel: "靈敏度",
        hapticsLabel: "觸感回饋",
        reverseLabel: "反轉方向"
    )

    static let uk = TrackpadEdgeSliderStrings(
        title: "Повзунки по краях трекпеда",
        caption: "Проведіть одним пальцем уздовж лівого або правого краю трекпеда, щоб змінити яскравість або гучність.",
        leftLabel: "Лівий край",
        rightLabel: "Правий край",
        actionOff: "Вимкнено",
        actionBrightness: "Яскравість",
        actionVolume: "Гучність",
        widthLabel: "Ширина краю",
        sensitivityLabel: "Чутливість",
        hapticsLabel: "Тактильний відгук",
        reverseLabel: "Зворотний напрям"
    )
}
