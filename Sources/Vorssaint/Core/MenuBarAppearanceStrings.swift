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
        label: "Usage display",
        values: "Values",
        bars: "Bars",
        caption: "Bars apply to CPU, GPU, memory and disk usage, and to the battery if you choose it on its tile. The battery uses the same colors the other way round: the medium color below 40%, the high color below 20%, and green while plugged in. Other readings stay numeric.",
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
        caption: "As barras mostram o uso de CPU, GPU, memória e disco, e a bateria se você escolher no cartão dela. A bateria usa as mesmas cores ao contrário: a cor média abaixo de 40%, a cor alta abaixo de 20% e verde quando conectada. As outras leituras continuam numéricas.",
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
        caption: "Çubuklar CPU, GPU, bellek ve disk kullanımını, kartında seçerseniz pili de gösterir. Pil aynı renkleri ters yönde kullanır: %40’ın altında orta renk, %20’nin altında yüksek renk, prize takılıyken yeşil. Diğer ölçümler sayısal kalır.",
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
        caption: "Шкалы показывают загрузку CPU, GPU, памяти и диска, а также батарею, если выбрать это в её карточке. Батарея использует те же цвета в обратном порядке: средний цвет ниже 40%, высокий цвет ниже 20% и зелёный при подключении к сети. Остальные показатели остаются числовыми.",
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
        caption: "Las barras muestran el uso de CPU, GPU, memoria y disco, y la batería si lo eliges en su tarjeta. La batería usa los mismos colores al revés: el color medio por debajo del 40 %, el color alto por debajo del 20 % y verde mientras está conectada. Las demás lecturas siguen siendo numéricas.",
        customize: "Colores y límites de las barras",
        normalColor: "Color normal",
        mediumColor: "Color medio",
        highColor: "Color alto",
        mediumFrom: "Medio desde",
        highFrom: "Alto desde"
    )

    static let sk = MenuBarAppearanceStrings(
        label: "Zobrazenie vyťaženia",
        values: "Hodnoty",
        bars: "Pruhy",
        caption: "Pruhy platia pre vyťaženie CPU, GPU, pamäte a disku a pre batériu, ak to zvolíte na jej karte. Batéria používa tie isté farby naopak: strednú farbu pod 40 %, vysokú farbu pod 20 % a po pripojení k napájaniu zelenú. Ostatné hodnoty zostávajú číselné.",
        customize: "Farby a limity pruhov",
        normalColor: "Bežná farba",
        mediumColor: "Stredná farba",
        highColor: "Vysoká farba",
        mediumFrom: "Stredná od",
        highFrom: "Vysoká od"
    )

    static let de = MenuBarAppearanceStrings(
        label: "Auslastungsanzeige",
        values: "Werte",
        bars: "Balken",
        caption: "Balken zeigen die Auslastung von CPU, GPU, Speicher und Festplatte und die Batterie, wenn du das in ihrer Karte wählst. Die Batterie nutzt dieselben Farben umgekehrt: unter 40 % die mittlere Farbe, unter 20 % die hohe Farbe und am Netzteil Grün. Andere Messwerte bleiben numerisch.",
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
        caption: "Les barres indiquent l’utilisation du CPU, du GPU, de la mémoire et du disque, et la batterie si vous le choisissez sur sa carte. La batterie utilise les mêmes couleurs à l’inverse : la couleur moyenne sous 40 %, la couleur élevée sous 20 % et le vert une fois branchée. Les autres mesures restent numériques.",
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
        caption: "Le barre mostrano l’utilizzo di CPU, GPU, memoria e disco, e la batteria se lo scegli nella sua scheda. La batteria usa gli stessi colori al contrario: il colore medio sotto il 40%, il colore alto sotto il 20% e il verde quando è collegata. Le altre letture restano numeriche.",
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
        caption: "CPU、GPU、メモリ、ディスクの使用率をバーで表示します。カードで選ぶとバッテリーもバーになります。バッテリーは同じ色を逆の向きで使い、40% 未満で中程度の色、20% 未満で高負荷の色、電源接続中は緑になります。その他の測定値は数値のままです。",
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
        caption: "CPU, GPU, 메모리 및 디스크 사용량을 막대로 표시하며, 카드에서 선택하면 배터리도 표시합니다. 배터리는 같은 색상을 반대로 사용해 40% 미만이면 중간 색상, 20% 미만이면 높음 색상, 전원 연결 시 녹색이 됩니다. 다른 측정값은 숫자로 유지됩니다.",
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
        caption: "CPU、GPU、内存和磁盘使用率以条形显示；在电池卡片中选择后，电池也会以条形显示。电池以相反方式使用相同颜色：低于 40% 时为中等颜色，低于 20% 时为高负载颜色，接通电源时为绿色。其他读数保持数字显示。",
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
        caption: "CPU、GPU、記憶體和磁碟使用率以長條顯示；在電池卡片中選擇後，電池也會以長條顯示。電池以相反方式使用相同顏色：低於 40% 時為中等顏色，低於 20% 時為高負載顏色，接上電源時為綠色。其他讀數維持數字顯示。",
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
        caption: "CPU、GPU、記憶體及磁碟使用率以長條顯示；在電池卡片中選擇後，電池亦會以長條顯示。電池以相反方式使用相同顏色：低於 40% 時為中等顏色，低於 20% 時為高負載顏色，接上電源時為綠色。其他讀數維持數字顯示。",
        customize: "長條顏色及門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )
    static let uk = MenuBarAppearanceStrings(
        label: "Відображення використання",
        values: "Значення",
        bars: "Смуги",
        caption: "Смуги застосовуються до використання CPU, GPU, пам’яті та диска, а також до акумулятора, якщо вибрати це в його картці. Акумулятор використовує ті самі кольори навпаки: середній колір нижче 40%, високий колір нижче 20% і зелений під час живлення від мережі. Інші показники залишаються числовими.",
        customize: "Кольори та ліміти смуг",
        normalColor: "Звичайний колір",
        mediumColor: "Середній колір",
        highColor: "Високий колір",
        mediumFrom: "Середній від",
        highFrom: "Високий від"
    )
}
