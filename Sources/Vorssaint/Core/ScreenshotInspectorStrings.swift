// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screenshot editor's measuring and inspection tools.
struct ScreenshotInspectorStrings {
    let toolRuler: String
    let toolMagnifier: String
    let measureHint: String
    let measureUnitLabel: String
    let magnificationLabel: String
    let pointerColorHint: String
    let averageColorLabel: String
    let contrastLabel: String
    let contrastHelp: String
    let fitToContent: String
    let resizeTitle: String
    let resizeWidth: String
    let resizeHeight: String
    let resizeApply: String
    let resizeCaption: String
    let overlayOpacityLabel: String
    let comparisonGIF: String
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
        toolMagnifier: "Magnifier",
        measureHint: "Arrow keys measure the gap under the pointer, ⌥S and ⌥D show guides, a click marks it on the capture",
        measureUnitLabel: "Unit",
        magnificationLabel: "Magnification",
        pointerColorHint: "Tab copies this color, ⇧Tab the nearby text color",
        averageColorLabel: "Average color",
        contrastLabel: "Contrast",
        contrastHelp: "Contrast of the selection’s most distinct color on its background, as a WCAG 2 ratio and APCA Lc",
        fitToContent: "Fit to content",
        resizeTitle: "Image size",
        resizeWidth: "Width",
        resizeHeight: "Height",
        resizeApply: "Resize",
        resizeCaption: "Marks become part of the picture. Undo brings them back.",
        overlayOpacityLabel: "Opacity",
        comparisonGIF: "Save before and after GIF"
    )

    static let ptBR = ScreenshotInspectorStrings(
        toolRuler: "Régua",
        toolMagnifier: "Lupa",
        measureHint: "As setas medem o espaço sob o ponteiro, ⌥S e ⌥D mostram guias, um clique marca a medida na captura",
        measureUnitLabel: "Unidade",
        magnificationLabel: "Ampliação",
        pointerColorHint: "Tab copia esta cor, ⇧Tab a cor do texto próximo",
        averageColorLabel: "Cor média",
        contrastLabel: "Contraste",
        contrastHelp: "Contraste da cor mais distinta da seleção sobre o fundo, como razão WCAG 2 e APCA Lc",
        fitToContent: "Ajustar ao conteúdo",
        resizeTitle: "Tamanho da imagem",
        resizeWidth: "Largura",
        resizeHeight: "Altura",
        resizeApply: "Redimensionar",
        resizeCaption: "As marcações passam a fazer parte da imagem. Desfazer as traz de volta.",
        overlayOpacityLabel: "Opacidade",
        comparisonGIF: "Salvar GIF de antes e depois"
    )

    static let tr = ScreenshotInspectorStrings(
        toolRuler: "Cetvel",
        toolMagnifier: "Büyüteç",
        measureHint: "Ok tuşları imlecin altındaki boşluğu ölçer, ⌥S ve ⌥D kılavuz gösterir, tıklayınca ölçü görsele eklenir",
        measureUnitLabel: "Birim",
        magnificationLabel: "Büyütme",
        pointerColorHint: "Tab bu rengi, ⇧Tab yakındaki metnin rengini kopyalar",
        averageColorLabel: "Ortalama renk",
        contrastLabel: "Kontrast",
        contrastHelp: "Seçimdeki en belirgin rengin arka plana karşı kontrastı, WCAG 2 oranı ve APCA Lc olarak",
        fitToContent: "İçeriğe sığdır",
        resizeTitle: "Görsel boyutu",
        resizeWidth: "Genişlik",
        resizeHeight: "Yükseklik",
        resizeApply: "Boyutlandır",
        resizeCaption: "Notlar görselin parçası olur. Geri al onları geri getirir.",
        overlayOpacityLabel: "Opaklık",
        comparisonGIF: "Önce ve sonra GIF’ini kaydet"
    )

    static let ru = ScreenshotInspectorStrings(
        toolRuler: "Линейка",
        toolMagnifier: "Лупа",
        measureHint: "Стрелки измеряют промежуток под указателем, ⌥S и ⌥D показывают направляющие, щелчок наносит размер на снимок",
        measureUnitLabel: "Единицы",
        magnificationLabel: "Увеличение",
        pointerColorHint: "Tab копирует этот цвет, ⇧Tab цвет текста рядом",
        averageColorLabel: "Средний цвет",
        contrastLabel: "Контраст",
        contrastHelp: "Контраст самого заметного цвета выделения с фоном: отношение WCAG 2 и APCA Lc",
        fitToContent: "Подогнать к содержимому",
        resizeTitle: "Размер изображения",
        resizeWidth: "Ширина",
        resizeHeight: "Высота",
        resizeApply: "Изменить размер",
        resizeCaption: "Пометки станут частью изображения. Отмена вернёт их.",
        overlayOpacityLabel: "Непрозрачность",
        comparisonGIF: "Сохранить GIF до и после"
    )

    static let es = ScreenshotInspectorStrings(
        toolRuler: "Regla",
        toolMagnifier: "Lupa",
        measureHint: "Las flechas miden el espacio bajo el puntero, ⌥S y ⌥D muestran guías y un clic marca la medida en la captura",
        measureUnitLabel: "Unidad",
        magnificationLabel: "Aumento",
        pointerColorHint: "Tab copia este color, ⇧Tab el color del texto cercano",
        averageColorLabel: "Color medio",
        contrastLabel: "Contraste",
        contrastHelp: "Contraste del color más distinto de la selección sobre el fondo, como relación WCAG 2 y APCA Lc",
        fitToContent: "Ajustar al contenido",
        resizeTitle: "Tamaño de la imagen",
        resizeWidth: "Ancho",
        resizeHeight: "Alto",
        resizeApply: "Redimensionar",
        resizeCaption: "Las marcas pasan a formar parte de la imagen. Deshacer las recupera.",
        overlayOpacityLabel: "Opacidad",
        comparisonGIF: "Guardar GIF de antes y después"
    )

    static let sk = ScreenshotInspectorStrings(
        toolRuler: "Pravítko",
        toolMagnifier: "Lupa",
        measureHint: "Šípky zmerajú medzeru pod ukazovateľom, ⌥S a ⌥D zobrazia vodiace čiary, kliknutie vyznačí mieru na snímke",
        measureUnitLabel: "Jednotka",
        magnificationLabel: "Zväčšenie",
        pointerColorHint: "Tab skopíruje túto farbu, ⇧Tab farbu blízkeho textu",
        averageColorLabel: "Priemerná farba",
        contrastLabel: "Kontrast",
        contrastHelp: "Kontrast najvýraznejšej farby výberu voči pozadiu ako pomer WCAG 2 a APCA Lc",
        fitToContent: "Prispôsobiť obsahu",
        resizeTitle: "Veľkosť obrázka",
        resizeWidth: "Šírka",
        resizeHeight: "Výška",
        resizeApply: "Zmeniť veľkosť",
        resizeCaption: "Značky sa stanú súčasťou obrázka. Späť ich vráti.",
        overlayOpacityLabel: "Nepriehľadnosť",
        comparisonGIF: "Uložiť GIF pred a po"
    )

    static let de = ScreenshotInspectorStrings(
        toolRuler: "Lineal",
        toolMagnifier: "Lupe",
        measureHint: "Pfeiltasten messen den Abstand unter dem Zeiger, ⌥S und ⌥D zeigen Hilfslinien, ein Klick setzt das Maß aufs Bild",
        measureUnitLabel: "Einheit",
        magnificationLabel: "Vergrößerung",
        pointerColorHint: "Tab kopiert diese Farbe, ⇧Tab die Farbe des Texts in der Nähe",
        averageColorLabel: "Durchschnittsfarbe",
        contrastLabel: "Kontrast",
        contrastHelp: "Kontrast der markantesten Farbe der Auswahl zum Hintergrund als WCAG-2-Verhältnis und APCA Lc",
        fitToContent: "An Inhalt anpassen",
        resizeTitle: "Bildgröße",
        resizeWidth: "Breite",
        resizeHeight: "Höhe",
        resizeApply: "Größe ändern",
        resizeCaption: "Markierungen werden Teil des Bilds. Widerrufen holt sie zurück.",
        overlayOpacityLabel: "Deckkraft",
        comparisonGIF: "Vorher-nachher-GIF sichern"
    )

    static let fr = ScreenshotInspectorStrings(
        toolRuler: "Règle",
        toolMagnifier: "Loupe",
        measureHint: "Les flèches mesurent l’espace sous le pointeur, ⌥S et ⌥D affichent des repères, un clic inscrit la mesure sur la capture",
        measureUnitLabel: "Unité",
        magnificationLabel: "Grossissement",
        pointerColorHint: "Tab copie cette couleur, ⇧Tab celle du texte voisin",
        averageColorLabel: "Couleur moyenne",
        contrastLabel: "Contraste",
        contrastHelp: "Contraste de la couleur la plus distincte de la sélection sur son fond, en rapport WCAG 2 et APCA Lc",
        fitToContent: "Ajuster au contenu",
        resizeTitle: "Taille de l’image",
        resizeWidth: "Largeur",
        resizeHeight: "Hauteur",
        resizeApply: "Redimensionner",
        resizeCaption: "Les annotations font partie de l’image. Annuler les rétablit.",
        overlayOpacityLabel: "Opacité",
        comparisonGIF: "Enregistrer un GIF avant et après"
    )

    static let it = ScreenshotInspectorStrings(
        toolRuler: "Righello",
        toolMagnifier: "Lente",
        measureHint: "Le frecce misurano lo spazio sotto il puntatore, ⌥S e ⌥D mostrano le guide, un clic riporta la misura sulla cattura",
        measureUnitLabel: "Unità",
        magnificationLabel: "Ingrandimento",
        pointerColorHint: "Tab copia questo colore, ⇧Tab il colore del testo vicino",
        averageColorLabel: "Colore medio",
        contrastLabel: "Contrasto",
        contrastHelp: "Contrasto del colore più distinto della selezione sullo sfondo, come rapporto WCAG 2 e APCA Lc",
        fitToContent: "Adatta al contenuto",
        resizeTitle: "Dimensioni immagine",
        resizeWidth: "Larghezza",
        resizeHeight: "Altezza",
        resizeApply: "Ridimensiona",
        resizeCaption: "Le annotazioni diventano parte dell’immagine. Annulla le riporta indietro.",
        overlayOpacityLabel: "Opacità",
        comparisonGIF: "Salva GIF prima e dopo"
    )

    static let ja = ScreenshotInspectorStrings(
        toolRuler: "定規",
        toolMagnifier: "拡大鏡",
        measureHint: "矢印キーでポインタ下の間隔を測定、⌥S と ⌥D でガイドを表示、クリックで寸法を画像に書き込みます",
        measureUnitLabel: "単位",
        magnificationLabel: "倍率",
        pointerColorHint: "Tab でこの色を、⇧Tab で近くの文字色をコピー",
        averageColorLabel: "平均色",
        contrastLabel: "コントラスト",
        contrastHelp: "選択範囲で最も目立つ色と背景のコントラスト（WCAG 2 の比率と APCA Lc）",
        fitToContent: "内容に合わせる",
        resizeTitle: "画像サイズ",
        resizeWidth: "幅",
        resizeHeight: "高さ",
        resizeApply: "サイズを変更",
        resizeCaption: "注釈は画像の一部になります。取り消すと元に戻ります。",
        overlayOpacityLabel: "不透明度",
        comparisonGIF: "ビフォーアフター GIF を保存"
    )

    static let ko = ScreenshotInspectorStrings(
        toolRuler: "눈금자",
        toolMagnifier: "돋보기",
        measureHint: "화살표 키로 포인터 아래 간격을 재고, ⌥S와 ⌥D로 안내선을 표시하며, 클릭하면 치수를 이미지에 남깁니다",
        measureUnitLabel: "단위",
        magnificationLabel: "배율",
        pointerColorHint: "Tab은 이 색상을, ⇧Tab은 근처 텍스트 색상을 복사합니다",
        averageColorLabel: "평균 색상",
        contrastLabel: "대비",
        contrastHelp: "선택 영역에서 가장 두드러진 색상과 배경의 대비(WCAG 2 비율 및 APCA Lc)",
        fitToContent: "내용에 맞추기",
        resizeTitle: "이미지 크기",
        resizeWidth: "너비",
        resizeHeight: "높이",
        resizeApply: "크기 조절",
        resizeCaption: "주석이 이미지의 일부가 됩니다. 실행 취소하면 되돌아옵니다.",
        overlayOpacityLabel: "불투명도",
        comparisonGIF: "전후 비교 GIF 저장"
    )

    static let zhHans = ScreenshotInspectorStrings(
        toolRuler: "标尺",
        toolMagnifier: "放大镜",
        measureHint: "方向键测量指针下方的间距，⌥S 和 ⌥D 显示参考线，点按可将尺寸标注到图片上",
        measureUnitLabel: "单位",
        magnificationLabel: "放大倍数",
        pointerColorHint: "Tab 拷贝此颜色，⇧Tab 拷贝附近文字的颜色",
        averageColorLabel: "平均颜色",
        contrastLabel: "对比度",
        contrastHelp: "所选区域中最突出的颜色与背景的对比度（WCAG 2 比值和 APCA Lc）",
        fitToContent: "适合内容",
        resizeTitle: "图片大小",
        resizeWidth: "宽度",
        resizeHeight: "高度",
        resizeApply: "调整大小",
        resizeCaption: "标注将合并到图片中。撤销可恢复。",
        overlayOpacityLabel: "不透明度",
        comparisonGIF: "存储前后对比 GIF"
    )

    static let zhTW = ScreenshotInspectorStrings(
        toolRuler: "尺規",
        toolMagnifier: "放大鏡",
        measureHint: "方向鍵測量指標下方的間距，⌥S 和 ⌥D 顯示參考線，按一下可將尺寸標註到圖片上",
        measureUnitLabel: "單位",
        magnificationLabel: "放大倍率",
        pointerColorHint: "Tab 拷貝此顏色，⇧Tab 拷貝附近文字的顏色",
        averageColorLabel: "平均顏色",
        contrastLabel: "對比",
        contrastHelp: "所選範圍中最突出的顏色與背景的對比（WCAG 2 比值與 APCA Lc）",
        fitToContent: "符合內容",
        resizeTitle: "圖片大小",
        resizeWidth: "寬度",
        resizeHeight: "高度",
        resizeApply: "調整大小",
        resizeCaption: "標註會合併到圖片中。還原可將其恢復。",
        overlayOpacityLabel: "不透明度",
        comparisonGIF: "儲存前後對比 GIF"
    )

    static let zhHK = ScreenshotInspectorStrings(
        toolRuler: "尺規",
        toolMagnifier: "放大鏡",
        measureHint: "方向鍵量度指標下方的間距，⌥S 和 ⌥D 顯示參考線，按一下可將尺寸標註到圖片上",
        measureUnitLabel: "單位",
        magnificationLabel: "放大倍率",
        pointerColorHint: "Tab 拷貝此顏色，⇧Tab 拷貝附近文字的顏色",
        averageColorLabel: "平均顏色",
        contrastLabel: "對比",
        contrastHelp: "所選範圍中最突出的顏色與背景的對比（WCAG 2 比值與 APCA Lc）",
        fitToContent: "符合內容",
        resizeTitle: "圖片大小",
        resizeWidth: "闊度",
        resizeHeight: "高度",
        resizeApply: "調整大小",
        resizeCaption: "標註會合併到圖片中。還原可將其恢復。",
        overlayOpacityLabel: "不透明度",
        comparisonGIF: "儲存前後對比 GIF"
    )

    static let uk = ScreenshotInspectorStrings(
        toolRuler: "Лінійка",
        toolMagnifier: "Лупа",
        measureHint: "Стрілки вимірюють проміжок під вказівником, ⌥S і ⌥D показують напрямні, клацання наносить розмір на знімок",
        measureUnitLabel: "Одиниці",
        magnificationLabel: "Збільшення",
        pointerColorHint: "Tab копіює цей колір, ⇧Tab колір тексту поруч",
        averageColorLabel: "Середній колір",
        contrastLabel: "Контраст",
        contrastHelp: "Контраст найпомітнішого кольору виділення з тлом: співвідношення WCAG 2 і APCA Lc",
        fitToContent: "Підігнати до вмісту",
        resizeTitle: "Розмір зображення",
        resizeWidth: "Ширина",
        resizeHeight: "Висота",
        resizeApply: "Змінити розмір",
        resizeCaption: "Позначки стануть частиною зображення. Скасування поверне їх.",
        overlayOpacityLabel: "Непрозорість",
        comparisonGIF: "Зберегти GIF до і після"
    )
}
