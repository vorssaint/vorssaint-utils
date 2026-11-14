// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarAppearanceStrings {
    let batteryPercentage: String
    let label: String
    let values: String
    let bars: String
    let caption: String
    let customize: String
    let normalColor: String
    let mediumColor: String
    let highColor: String
    let mediumFrom: String
    let highFrom: String
}

extension FeatureStrings {
    static func menuBarAppearance(_ language: AppLanguage) -> MenuBarAppearanceStrings {
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

extension MenuBarAppearanceStrings {
    static let enUS = MenuBarAppearanceStrings(
        batteryPercentage: "Show battery percentage",
        label: "Usage display",
        values: "Values",
        bars: "Bars",
        caption: "Bars apply to CPU, GPU, memory and disk usage. Other readings stay numeric.",
        customize: "Bar colors and limits",
        normalColor: "Normal color",
        mediumColor: "Medium color",
        highColor: "High color",
        mediumFrom: "Medium from",
        highFrom: "High from"
    )

    static let ptBR = MenuBarAppearanceStrings(
        batteryPercentage: "Mostrar porcentagem da bateria",
        label: "Exibição de uso",
        values: "Valores",
        bars: "Barras",
        caption: "As barras mostram o uso de CPU, GPU, memória e disco. As outras leituras continuam numéricas.",
        customize: "Cores e limites das barras",
        normalColor: "Cor normal",
        mediumColor: "Cor média",
        highColor: "Cor alta",
        mediumFrom: "Médio a partir de",
        highFrom: "Alto a partir de"
    )

    static let tr = MenuBarAppearanceStrings(
        batteryPercentage: "Pil yüzdesini göster",
        label: "Kullanım görünümü",
        values: "Değerler",
        bars: "Çubuklar",
        caption: "Çubuklar CPU, GPU, bellek ve disk kullanımını gösterir. Diğer ölçümler sayısal kalır.",
        customize: "Çubuk renkleri ve sınırları",
        normalColor: "Normal renk",
        mediumColor: "Orta renk",
        highColor: "Yüksek renk",
        mediumFrom: "Orta başlangıcı",
        highFrom: "Yüksek başlangıcı"
    )

    static let ru = MenuBarAppearanceStrings(
        batteryPercentage: "Показывать процент заряда батареи",
        label: "Отображение нагрузки",
        values: "Значения",
        bars: "Шкалы",
        caption: "Шкалы показывают загрузку CPU, GPU, памяти и диска. Остальные показатели остаются числовыми.",
        customize: "Цвета и пороги шкал",
        normalColor: "Обычный цвет",
        mediumColor: "Средний цвет",
        highColor: "Высокий цвет",
        mediumFrom: "Средний от",
        highFrom: "Высокий от"
    )

    static let es = MenuBarAppearanceStrings(
        batteryPercentage: "Mostrar porcentaje de batería",
        label: "Vista de uso",
        values: "Valores",
        bars: "Barras",
        caption: "Las barras muestran el uso de CPU, GPU, memoria y disco. Las demás lecturas siguen siendo numéricas.",
        customize: "Colores y límites de las barras",
        normalColor: "Color normal",
        mediumColor: "Color medio",
        highColor: "Color alto",
        mediumFrom: "Medio desde",
        highFrom: "Alto desde"
    )

    static let sk = MenuBarAppearanceStrings(
        batteryPercentage: "Zobraziť percento batérie",
        label: "Zobrazenie vyťaženia",
        values: "Hodnoty",
        bars: "Pruhy",
        caption: "Pruhy platia pre vyťaženie CPU, GPU, pamäte a disku. Ostatné hodnoty zostávajú číselné.",
        customize: "Farby a limity pruhov",
        normalColor: "Bežná farba",
        mediumColor: "Stredná farba",
        highColor: "Vysoká farba",
        mediumFrom: "Stredná od",
        highFrom: "Vysoká od"
    )

    static let de = MenuBarAppearanceStrings(
        batteryPercentage: "Batterieprozentsatz anzeigen",
        label: "Auslastungsanzeige",
        values: "Werte",
        bars: "Balken",
        caption: "Balken zeigen die Auslastung von CPU, GPU, Speicher und Festplatte. Andere Messwerte bleiben numerisch.",
        customize: "Balkenfarben und Grenzwerte",
        normalColor: "Normale Farbe",
        mediumColor: "Mittlere Farbe",
        highColor: "Hohe Farbe",
        mediumFrom: "Mittel ab",
        highFrom: "Hoch ab"
    )

    static let fr = MenuBarAppearanceStrings(
        batteryPercentage: "Afficher le pourcentage de batterie",
        label: "Affichage de l’utilisation",
        values: "Valeurs",
        bars: "Barres",
        caption: "Les barres indiquent l’utilisation du CPU, du GPU, de la mémoire et du disque. Les autres mesures restent numériques.",
        customize: "Couleurs et seuils des barres",
        normalColor: "Couleur normale",
        mediumColor: "Couleur moyenne",
        highColor: "Couleur élevée",
        mediumFrom: "Moyen à partir de",
        highFrom: "Élevé à partir de"
    )

    static let it = MenuBarAppearanceStrings(
        batteryPercentage: "Mostra percentuale batteria",
        label: "Visualizzazione utilizzo",
        values: "Valori",
        bars: "Barre",
        caption: "Le barre mostrano l’utilizzo di CPU, GPU, memoria e disco. Le altre letture restano numeriche.",
        customize: "Colori e soglie delle barre",
        normalColor: "Colore normale",
        mediumColor: "Colore medio",
        highColor: "Colore alto",
        mediumFrom: "Medio da",
        highFrom: "Alto da"
    )

    static let ja = MenuBarAppearanceStrings(
        batteryPercentage: "バッテリー残量の割合を表示",
        label: "使用率の表示",
        values: "数値",
        bars: "バー",
        caption: "CPU、GPU、メモリ、ディスクの使用率をバーで表示します。その他の測定値は数値のままです。",
        customize: "バーの色としきい値",
        normalColor: "通常の色",
        mediumColor: "中程度の色",
        highColor: "高負荷の色",
        mediumFrom: "中程度の開始",
        highFrom: "高負荷の開始"
    )

    static let ko = MenuBarAppearanceStrings(
        batteryPercentage: "배터리 잔량 백분율 표시",
        label: "사용량 표시",
        values: "값",
        bars: "막대",
        caption: "CPU, GPU, 메모리 및 디스크 사용량을 막대로 표시합니다. 다른 측정값은 숫자로 유지됩니다.",
        customize: "막대 색상 및 기준",
        normalColor: "보통 색상",
        mediumColor: "중간 색상",
        highColor: "높음 색상",
        mediumFrom: "중간 시작",
        highFrom: "높음 시작"
    )

    static let zhHans = MenuBarAppearanceStrings(
        batteryPercentage: "显示电池百分比",
        label: "使用率显示",
        values: "数值",
        bars: "条形",
        caption: "CPU、GPU、内存和磁盘使用率以条形显示。其他读数保持数字显示。",
        customize: "条形颜色和阈值",
        normalColor: "正常颜色",
        mediumColor: "中等颜色",
        highColor: "高负载颜色",
        mediumFrom: "中等起点",
        highFrom: "高负载起点"
    )

    static let zhTW = MenuBarAppearanceStrings(
        batteryPercentage: "顯示電池百分比",
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        caption: "CPU、GPU、記憶體和磁碟使用率以長條顯示。其他讀數維持數字顯示。",
        customize: "長條顏色和門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )

    static let zhHK = MenuBarAppearanceStrings(
        batteryPercentage: "顯示電池百分比",
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        caption: "CPU、GPU、記憶體及磁碟使用率以長條顯示。其他讀數維持數字顯示。",
        customize: "長條顏色及門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )
    static let uk = MenuBarAppearanceStrings(
        batteryPercentage: "Показувати відсоток заряду батареї",
        label: "Відображення використання",
        values: "Значення",
        bars: "Смуги",
        caption: "Смуги застосовуються до використання CPU, GPU, пам’яті та диска. Інші показники залишаються числовими.",
        customize: "Кольори та ліміти смуг",
        normalColor: "Звичайний колір",
        mediumColor: "Середній колір",
        highColor: "Високий колір",
        mediumFrom: "Середній від",
        highFrom: "Високий від"
    )
}
