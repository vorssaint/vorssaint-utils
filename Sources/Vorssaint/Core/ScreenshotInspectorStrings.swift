// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screenshot editor's measuring and inspection tools.
struct ScreenshotInspectorStrings {
    let toolRuler: String
    let measureHint: String
    let measureUnitLabel: String
}

extension FeatureStrings {
    static func screenshotInspector(_ language: AppLanguage) -> ScreenshotInspectorStrings {
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

extension ScreenshotInspectorStrings {
    static let enUS = ScreenshotInspectorStrings(
        toolRuler: "Ruler",
        measureHint: "Arrow keys measure the gap under the pointer, ⌥S and ⌥D show guides, a click marks it on the capture",
        measureUnitLabel: "Unit"
    )

    static let ptBR = ScreenshotInspectorStrings(
        toolRuler: "Régua",
        measureHint: "As setas medem o espaço sob o ponteiro, ⌥S e ⌥D mostram guias, um clique marca a medida na captura",
        measureUnitLabel: "Unidade"
    )

    static let tr = ScreenshotInspectorStrings(
        toolRuler: "Cetvel",
        measureHint: "Ok tuşları imlecin altındaki boşluğu ölçer, ⌥S ve ⌥D kılavuz gösterir, tıklayınca ölçü görsele eklenir",
        measureUnitLabel: "Birim"
    )

    static let ru = ScreenshotInspectorStrings(
        toolRuler: "Линейка",
        measureHint: "Стрелки измеряют промежуток под указателем, ⌥S и ⌥D показывают направляющие, щелчок наносит размер на снимок",
        measureUnitLabel: "Единицы"
    )

    static let es = ScreenshotInspectorStrings(
        toolRuler: "Regla",
        measureHint: "Las flechas miden el espacio bajo el puntero, ⌥S y ⌥D muestran guías y un clic marca la medida en la captura",
        measureUnitLabel: "Unidad"
    )

    static let sk = ScreenshotInspectorStrings(
        toolRuler: "Pravítko",
        measureHint: "Šípky zmerajú medzeru pod ukazovateľom, ⌥S a ⌥D zobrazia vodiace čiary, kliknutie vyznačí mieru na snímke",
        measureUnitLabel: "Jednotka"
    )

    static let de = ScreenshotInspectorStrings(
        toolRuler: "Lineal",
        measureHint: "Pfeiltasten messen den Abstand unter dem Zeiger, ⌥S und ⌥D zeigen Hilfslinien, ein Klick setzt das Maß aufs Bild",
        measureUnitLabel: "Einheit"
    )

    static let fr = ScreenshotInspectorStrings(
        toolRuler: "Règle",
        measureHint: "Les flèches mesurent l’espace sous le pointeur, ⌥S et ⌥D affichent des repères, un clic inscrit la mesure sur la capture",
        measureUnitLabel: "Unité"
    )

    static let it = ScreenshotInspectorStrings(
        toolRuler: "Righello",
        measureHint: "Le frecce misurano lo spazio sotto il puntatore, ⌥S e ⌥D mostrano le guide, un clic riporta la misura sulla cattura",
        measureUnitLabel: "Unità"
    )

    static let ja = ScreenshotInspectorStrings(
        toolRuler: "定規",
        measureHint: "矢印キーでポインタ下の間隔を測定、⌥S と ⌥D でガイドを表示、クリックで寸法を画像に書き込みます",
        measureUnitLabel: "単位"
    )

    static let ko = ScreenshotInspectorStrings(
        toolRuler: "눈금자",
        measureHint: "화살표 키로 포인터 아래 간격을 재고, ⌥S와 ⌥D로 안내선을 표시하며, 클릭하면 치수를 이미지에 남깁니다",
        measureUnitLabel: "단위"
    )

    static let zhHans = ScreenshotInspectorStrings(
        toolRuler: "标尺",
        measureHint: "方向键测量指针下方的间距，⌥S 和 ⌥D 显示参考线，点按可将尺寸标注到图片上",
        measureUnitLabel: "单位"
    )

    static let zhTW = ScreenshotInspectorStrings(
        toolRuler: "尺規",
        measureHint: "方向鍵測量指標下方的間距，⌥S 和 ⌥D 顯示參考線，按一下可將尺寸標註到圖片上",
        measureUnitLabel: "單位"
    )

    static let zhHK = ScreenshotInspectorStrings(
        toolRuler: "尺規",
        measureHint: "方向鍵量度指標下方的間距，⌥S 和 ⌥D 顯示參考線，按一下可將尺寸標註到圖片上",
        measureUnitLabel: "單位"
    )

    static let uk = ScreenshotInspectorStrings(
        toolRuler: "Лінійка",
        measureHint: "Стрілки вимірюють проміжок під вказівником, ⌥S і ⌥D показують напрямні, клацання наносить розмір на знімок",
        measureUnitLabel: "Одиниці"
    )
}
