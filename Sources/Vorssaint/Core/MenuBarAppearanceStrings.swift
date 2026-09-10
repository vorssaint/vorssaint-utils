// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarAppearanceStrings {
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
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension MenuBarAppearanceStrings {
    static let enUS = MenuBarAppearanceStrings(
        label: "Usage display",
        values: "Values",
        bars: "Bars",
        caption: "CPU, GPU, memory, disk usage, battery and accessory batteries can each show values or bars. Other readings stay numeric.",
        customize: "Bar colors and limits",
        normalColor: "Normal color",
        mediumColor: "Medium color",
        highColor: "High color",
        mediumFrom: "Medium from",
        highFrom: "High from"
    )

    static let ptBR = MenuBarAppearanceStrings(
        label: "Exibição de uso",
        values: "Valores",
        bars: "Barras",
        caption: "CPU, GPU, memória, disco, bateria e baterias de acessórios podem mostrar valores ou barras cada um. As outras leituras continuam numéricas.",
        customize: "Cores e limites das barras",
        normalColor: "Cor normal",
        mediumColor: "Cor média",
        highColor: "Cor alta",
        mediumFrom: "Médio a partir de",
        highFrom: "Alto a partir de"
    )

    static let tr = MenuBarAppearanceStrings(
        label: "Kullanım görünümü",
        values: "Değerler",
        bars: "Çubuklar",
        caption: "CPU, GPU, bellek, disk kullanımı, batarya ve aksesuar bataryaları ayrı ayrı değer veya çubuk olarak gösterilebilir. Diğer ölçümler sayısal kalır.",
        customize: "Çubuk renkleri ve sınırları",
        normalColor: "Normal renk",
        mediumColor: "Orta renk",
        highColor: "Yüksek renk",
        mediumFrom: "Orta başlangıcı",
        highFrom: "Yüksek başlangıcı"
    )

    static let ru = MenuBarAppearanceStrings(
        label: "Отображение нагрузки",
        values: "Значения",
        bars: "Шкалы",
        caption: "Загрузку CPU, GPU, памяти, диска, заряд батареи и заряд аксессуаров можно показывать значениями или шкалами по отдельности. Остальные показатели остаются числовыми.",
        customize: "Цвета и пороги шкал",
        normalColor: "Обычный цвет",
        mediumColor: "Средний цвет",
        highColor: "Высокий цвет",
        mediumFrom: "Средний от",
        highFrom: "Высокий от"
    )

    static let es = MenuBarAppearanceStrings(
        label: "Vista de uso",
        values: "Valores",
        bars: "Barras",
        caption: "El uso de CPU, GPU, memoria y disco, la batería y las baterías de accesorios pueden mostrarse como valores o barras en cada uno. Las demás lecturas siguen siendo numéricas.",
        customize: "Colores y límites de las barras",
        normalColor: "Color normal",
        mediumColor: "Color medio",
        highColor: "Color alto",
        mediumFrom: "Medio desde",
        highFrom: "Alto desde"
    )

    static let de = MenuBarAppearanceStrings(
        label: "Auslastungsanzeige",
        values: "Werte",
        bars: "Balken",
        caption: "CPU-, GPU-, Speicher- und Festplattenauslastung sowie Akku und Zubehörakkus können jeweils als Werte oder Balken angezeigt werden. Andere Messwerte bleiben numerisch.",
        customize: "Balkenfarben und Grenzwerte",
        normalColor: "Normale Farbe",
        mediumColor: "Mittlere Farbe",
        highColor: "Hohe Farbe",
        mediumFrom: "Mittel ab",
        highFrom: "Hoch ab"
    )

    static let fr = MenuBarAppearanceStrings(
        label: "Affichage de l’utilisation",
        values: "Valeurs",
        bars: "Barres",
        caption: "L’utilisation du CPU, du GPU, de la mémoire et du disque, la batterie et les batteries d’accessoires peuvent s’afficher en valeurs ou en barres pour chacun. Les autres mesures restent numériques.",
        customize: "Couleurs et seuils des barres",
        normalColor: "Couleur normale",
        mediumColor: "Couleur moyenne",
        highColor: "Couleur élevée",
        mediumFrom: "Moyen à partir de",
        highFrom: "Élevé à partir de"
    )

    static let it = MenuBarAppearanceStrings(
        label: "Visualizzazione utilizzo",
        values: "Valori",
        bars: "Barre",
        caption: "L’utilizzo di CPU, GPU, memoria e disco, la batteria e le batterie degli accessori possono essere mostrati come valori o barre per ciascuno. Le altre letture restano numeriche.",
        customize: "Colori e soglie delle barre",
        normalColor: "Colore normale",
        mediumColor: "Colore medio",
        highColor: "Colore alto",
        mediumFrom: "Medio da",
        highFrom: "Alto da"
    )

    static let ja = MenuBarAppearanceStrings(
        label: "使用率の表示",
        values: "数値",
        bars: "バー",
        caption: "CPU、GPU、メモリ、ディスクの使用率、バッテリー、周辺機器のバッテリーはそれぞれ数値またはバーで表示できます。その他の測定値は数値のままです。",
        customize: "バーの色としきい値",
        normalColor: "通常の色",
        mediumColor: "中程度の色",
        highColor: "高負荷の色",
        mediumFrom: "中程度の開始",
        highFrom: "高負荷の開始"
    )

    static let ko = MenuBarAppearanceStrings(
        label: "사용량 표시",
        values: "값",
        bars: "막대",
        caption: "CPU, GPU, 메모리, 디스크 사용량, 배터리 및 액세서리 배터리는 항목마다 값 또는 막대로 표시할 수 있습니다. 다른 측정값은 숫자로 유지됩니다.",
        customize: "막대 색상 및 기준",
        normalColor: "보통 색상",
        mediumColor: "중간 색상",
        highColor: "높음 색상",
        mediumFrom: "중간 시작",
        highFrom: "높음 시작"
    )

    static let zhHans = MenuBarAppearanceStrings(
        label: "使用率显示",
        values: "数值",
        bars: "条形",
        caption: "CPU、GPU、内存、磁盘使用率以及电池和配件电量可分别显示为数值或条形。其他读数保持数字显示。",
        customize: "条形颜色和阈值",
        normalColor: "正常颜色",
        mediumColor: "中等颜色",
        highColor: "高负载颜色",
        mediumFrom: "中等起点",
        highFrom: "高负载起点"
    )

    static let zhTW = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        caption: "CPU、GPU、記憶體、磁碟使用率以及電池和配件電量可分別顯示為數值或長條。其他讀數維持數字顯示。",
        customize: "長條顏色和門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )

    static let zhHK = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        caption: "CPU、GPU、記憶體、磁碟使用率以及電池和配件電量可分別顯示為數值或長條。其他讀數維持數字顯示。",
        customize: "長條顏色及門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )
}
