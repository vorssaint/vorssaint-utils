// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TouchBarFeatureStrings {
    let title: String
    let hubDescription: String
    let unavailable: String
}

extension TouchBarFeatureStrings {
    static let enUS = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Customize controls and information shown on the Touch Bar",
        unavailable: "This Mac does not have a Touch Bar."
    )

    static let ptBR = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personalize os controles e as informações exibidos na Touch Bar",
        unavailable: "Este Mac não possui uma Touch Bar."
    )

    static let tr = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Touch Bar'da gösterilen denetimleri ve bilgileri özelleştirin",
        unavailable: "Bu Mac'te Touch Bar yok."
    )

    static let ru = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Настройте элементы управления и информацию на Touch Bar",
        unavailable: "На этом Mac нет Touch Bar."
    )

    static let es = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personaliza los controles y la información que se muestran en la Touch Bar",
        unavailable: "Este Mac no tiene Touch Bar."
    )

    static let de = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Passe die Steuerelemente und Informationen auf der Touch Bar an",
        unavailable: "Dieser Mac hat keine Touch Bar."
    )

    static let fr = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personnalisez les commandes et les informations affichées sur la Touch Bar",
        unavailable: "Ce Mac ne possède pas de Touch Bar."
    )

    static let it = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personalizza i controlli e le informazioni mostrati sulla Touch Bar",
        unavailable: "Questo Mac non dispone di Touch Bar."
    )

    static let ja = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Touch Bar に表示するコントロールと情報をカスタマイズ",
        unavailable: "このMacにはTouch Barがありません。"
    )

    static let ko = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Touch Bar에 표시되는 제어 항목과 정보를 사용자화합니다",
        unavailable: "이 Mac에는 Touch Bar가 없습니다."
    )

    static let zhHans = TouchBarFeatureStrings(
        title: "触控栏",
        hubDescription: "自定义触控栏上显示的控制项和信息",
        unavailable: "此 Mac 没有触控栏。"
    )

    static let zhTW = TouchBarFeatureStrings(
        title: "觸控列",
        hubDescription: "自訂觸控列上顯示的控制項目與資訊",
        unavailable: "此 Mac 沒有觸控列。"
    )

    static let zhHK = TouchBarFeatureStrings(
        title: "觸控欄",
        hubDescription: "自訂觸控欄上顯示的控制項目與資料",
        unavailable: "此 Mac 沒有觸控欄。"
    )
}