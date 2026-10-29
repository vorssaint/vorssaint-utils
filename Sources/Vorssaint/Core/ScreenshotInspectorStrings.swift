// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screenshot editor's measuring and inspection tools.
struct ScreenshotInspectorStrings {
    let toolRuler: String
    let measureHint: String
    let measureUnitLabel: String
    let pointerColorHint: String
    let averageColorLabel: String
    let contrastLabel: String
    let contrastHelp: String
    let fitToContent: String
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
        measureUnitLabel: "Unit",
        pointerColorHint: "Tab copies this color, ⇧Tab the nearby text color",
        averageColorLabel: "Average color",
        contrastLabel: "Contrast",
        contrastHelp: "Contrast of the selection’s most distinct color on its background, as a WCAG 2 ratio and APCA Lc",
        fitToContent: "Fit to content"
    )

    static let ptBR = ScreenshotInspectorStrings(
        toolRuler: "Régua",
        measureHint: "As setas medem o espaço sob o ponteiro, ⌥S e ⌥D mostram guias, um clique marca a medida na captura",
        measureUnitLabel: "Unidade",
        pointerColorHint: "Tab copia esta cor, ⇧Tab a cor do texto próximo",
        averageColorLabel: "Cor média",
        contrastLabel: "Contraste",
        contrastHelp: "Contraste da cor mais distinta da seleção sobre o fundo, como razão WCAG 2 e APCA Lc",
        fitToContent: "Ajustar ao conteúdo"
    )

    static let tr = ScreenshotInspectorStrings(
        toolRuler: "Cetvel",
        measureHint: "Ok tuşları imlecin altındaki boşluğu ölçer, ⌥S ve ⌥D kılavuz gösterir, tıklayınca ölçü görsele eklenir",
        measureUnitLabel: "Birim",
        pointerColorHint: "Tab bu rengi, ⇧Tab yakındaki metnin rengini kopyalar",
        averageColorLabel: "Ortalama renk",
        contrastLabel: "Kontrast",
        contrastHelp: "Seçimdeki en belirgin rengin arka plana karşı kontrastı, WCAG 2 oranı ve APCA Lc olarak",
        fitToContent: "İçeriğe sığdır"
    )

    static let ru = ScreenshotInspectorStrings(
        toolRuler: "Линейка",
        measureHint: "Стрелки измеряют промежуток под указателем, ⌥S и ⌥D показывают направляющие, щелчок наносит размер на снимок",
        measureUnitLabel: "Единицы",
        pointerColorHint: "Tab копирует этот цвет, ⇧Tab цвет текста рядом",
        averageColorLabel: "Средний цвет",
        contrastLabel: "Контраст",
        contrastHelp: "Контраст самого заметного цвета выделения с фоном: отношение WCAG 2 и APCA Lc",
        fitToContent: "Подогнать к содержимому"
    )

    static let es = ScreenshotInspectorStrings(
        toolRuler: "Regla",
        measureHint: "Las flechas miden el espacio bajo el puntero, ⌥S y ⌥D muestran guías y un clic marca la medida en la captura",
        measureUnitLabel: "Unidad",
        pointerColorHint: "Tab copia este color, ⇧Tab el color del texto cercano",
        averageColorLabel: "Color medio",
        contrastLabel: "Contraste",
        contrastHelp: "Contraste del color más distinto de la selección sobre el fondo, como relación WCAG 2 y APCA Lc",
        fitToContent: "Ajustar al contenido"
    )

    static let sk = ScreenshotInspectorStrings(
        toolRuler: "Pravítko",
        measureHint: "Šípky zmerajú medzeru pod ukazovateľom, ⌥S a ⌥D zobrazia vodiace čiary, kliknutie vyznačí mieru na snímke",
        measureUnitLabel: "Jednotka",
        pointerColorHint: "Tab skopíruje túto farbu, ⇧Tab farbu blízkeho textu",
        averageColorLabel: "Priemerná farba",
        contrastLabel: "Kontrast",
        contrastHelp: "Kontrast najvýraznejšej farby výberu voči pozadiu ako pomer WCAG 2 a APCA Lc",
        fitToContent: "Prispôsobiť obsahu"
    )

    static let de = ScreenshotInspectorStrings(
        toolRuler: "Lineal",
        measureHint: "Pfeiltasten messen den Abstand unter dem Zeiger, ⌥S und ⌥D zeigen Hilfslinien, ein Klick setzt das Maß aufs Bild",
        measureUnitLabel: "Einheit",
        pointerColorHint: "Tab kopiert diese Farbe, ⇧Tab die Farbe des Texts in der Nähe",
        averageColorLabel: "Durchschnittsfarbe",
        contrastLabel: "Kontrast",
        contrastHelp: "Kontrast der markantesten Farbe der Auswahl zum Hintergrund als WCAG-2-Verhältnis und APCA Lc",
        fitToContent: "An Inhalt anpassen"
    )

    static let fr = ScreenshotInspectorStrings(
        toolRuler: "Règle",
        measureHint: "Les flèches mesurent l’espace sous le pointeur, ⌥S et ⌥D affichent des repères, un clic inscrit la mesure sur la capture",
        measureUnitLabel: "Unité",
        pointerColorHint: "Tab copie cette couleur, ⇧Tab celle du texte voisin",
        averageColorLabel: "Couleur moyenne",
        contrastLabel: "Contraste",
        contrastHelp: "Contraste de la couleur la plus distincte de la sélection sur son fond, en rapport WCAG 2 et APCA Lc",
        fitToContent: "Ajuster au contenu"
    )

    static let it = ScreenshotInspectorStrings(
        toolRuler: "Righello",
        measureHint: "Le frecce misurano lo spazio sotto il puntatore, ⌥S e ⌥D mostrano le guide, un clic riporta la misura sulla cattura",
        measureUnitLabel: "Unità",
        pointerColorHint: "Tab copia questo colore, ⇧Tab il colore del testo vicino",
        averageColorLabel: "Colore medio",
        contrastLabel: "Contrasto",
        contrastHelp: "Contrasto del colore più distinto della selezione sullo sfondo, come rapporto WCAG 2 e APCA Lc",
        fitToContent: "Adatta al contenuto"
    )

    static let ja = ScreenshotInspectorStrings(
        toolRuler: "定規",
        measureHint: "矢印キーでポインタ下の間隔を測定、⌥S と ⌥D でガイドを表示、クリックで寸法を画像に書き込みます",
        measureUnitLabel: "単位",
        pointerColorHint: "Tab でこの色を、⇧Tab で近くの文字色をコピー",
        averageColorLabel: "平均色",
        contrastLabel: "コントラスト",
        contrastHelp: "選択範囲で最も目立つ色と背景のコントラスト（WCAG 2 の比率と APCA Lc）",
        fitToContent: "内容に合わせる"
    )

    static let ko = ScreenshotInspectorStrings(
        toolRuler: "눈금자",
        measureHint: "화살표 키로 포인터 아래 간격을 재고, ⌥S와 ⌥D로 안내선을 표시하며, 클릭하면 치수를 이미지에 남깁니다",
        measureUnitLabel: "단위",
        pointerColorHint: "Tab은 이 색상을, ⇧Tab은 근처 텍스트 색상을 복사합니다",
        averageColorLabel: "평균 색상",
        contrastLabel: "대비",
        contrastHelp: "선택 영역에서 가장 두드러진 색상과 배경의 대비(WCAG 2 비율 및 APCA Lc)",
        fitToContent: "내용에 맞추기"
    )

    static let zhHans = ScreenshotInspectorStrings(
        toolRuler: "标尺",
        measureHint: "方向键测量指针下方的间距，⌥S 和 ⌥D 显示参考线，点按可将尺寸标注到图片上",
        measureUnitLabel: "单位",
        pointerColorHint: "Tab 拷贝此颜色，⇧Tab 拷贝附近文字的颜色",
        averageColorLabel: "平均颜色",
        contrastLabel: "对比度",
        contrastHelp: "所选区域中最突出的颜色与背景的对比度（WCAG 2 比值和 APCA Lc）",
        fitToContent: "适合内容"
    )

    static let zhTW = ScreenshotInspectorStrings(
        toolRuler: "尺規",
        measureHint: "方向鍵測量指標下方的間距，⌥S 和 ⌥D 顯示參考線，按一下可將尺寸標註到圖片上",
        measureUnitLabel: "單位",
        pointerColorHint: "Tab 拷貝此顏色，⇧Tab 拷貝附近文字的顏色",
        averageColorLabel: "平均顏色",
        contrastLabel: "對比",
        contrastHelp: "所選範圍中最突出的顏色與背景的對比（WCAG 2 比值與 APCA Lc）",
        fitToContent: "符合內容"
    )

    static let zhHK = ScreenshotInspectorStrings(
        toolRuler: "尺規",
        measureHint: "方向鍵量度指標下方的間距，⌥S 和 ⌥D 顯示參考線，按一下可將尺寸標註到圖片上",
        measureUnitLabel: "單位",
        pointerColorHint: "Tab 拷貝此顏色，⇧Tab 拷貝附近文字的顏色",
        averageColorLabel: "平均顏色",
        contrastLabel: "對比",
        contrastHelp: "所選範圍中最突出的顏色與背景的對比（WCAG 2 比值與 APCA Lc）",
        fitToContent: "符合內容"
    )

    static let uk = ScreenshotInspectorStrings(
        toolRuler: "Лінійка",
        measureHint: "Стрілки вимірюють проміжок під вказівником, ⌥S і ⌥D показують напрямні, клацання наносить розмір на знімок",
        measureUnitLabel: "Одиниці",
        pointerColorHint: "Tab копіює цей колір, ⇧Tab колір тексту поруч",
        averageColorLabel: "Середній колір",
        contrastLabel: "Контраст",
        contrastHelp: "Контраст найпомітнішого кольору виділення з тлом: співвідношення WCAG 2 і APCA Lc",
        fitToContent: "Підігнати до вмісту"
    )
}
