// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct NotchLowBatteryStrings {
    let title: String
    let caption: String
    let threshold: String
    let early: String
    let earlyCaption: String
    let earlyThreshold: String
    let menuBar: String

    static func localized(_ language: AppLanguage) -> NotchLowBatteryStrings {
        switch language {
        case .enUS:
            return .init(title: "Turn red when low", caption: "Shows the charge in red at or below this level while on battery.",
                         threshold: "Red level", early: "Turn amber first",
                         earlyCaption: "Shows the charge in amber at or below a higher level, as an early warning.",
                         earlyThreshold: "Amber level", menuBar: "Also in the menu bar")
        case .ptBR:
            return .init(title: "Ficar vermelho com pouca bateria", caption: "Mostra a carga em vermelho neste nível ou abaixo dele enquanto estiver na bateria.",
                         threshold: "Nível vermelho", early: "Ficar âmbar antes",
                         earlyCaption: "Mostra a carga em âmbar em um nível mais alto ou abaixo dele, como um primeiro aviso.",
                         earlyThreshold: "Nível âmbar", menuBar: "Também na barra de menus")
        case .tr:
            return .init(title: "Azaldığında kırmızı yap", caption: "Pilde çalışırken şarjı bu seviyede veya altında kırmızı gösterir.",
                         threshold: "Kırmızı seviye", early: "Önce kehribar yap",
                         earlyCaption: "Erken uyarı olarak şarjı daha yüksek bir seviyede veya altında kehribar gösterir.",
                         earlyThreshold: "Kehribar seviye", menuBar: "Menü çubuğunda da")
        case .ru:
            return .init(title: "Красный при низком заряде", caption: "Показывает заряд красным на этом уровне или ниже при работе от батареи.",
                         threshold: "Красный уровень", early: "Сначала янтарный",
                         earlyCaption: "Показывает заряд янтарным на более высоком уровне или ниже, как раннее предупреждение.",
                         earlyThreshold: "Янтарный уровень", menuBar: "Также в строке меню")
        case .es:
            return .init(title: "Poner en rojo con poca batería", caption: "Muestra la carga en rojo en este nivel o por debajo mientras usa la batería.",
                         threshold: "Nivel rojo", early: "Poner en ámbar antes",
                         earlyCaption: "Muestra la carga en ámbar en un nivel más alto o por debajo, como primer aviso.",
                         earlyThreshold: "Nivel ámbar", menuBar: "También en la barra de menús")
        case .sk:
            return .init(title: "Sčervenať pri nízkej batérii", caption: "Pri napájaní z batérie zobrazí nabitie červenou na tejto úrovni alebo pod ňou.",
                         threshold: "Červená úroveň", early: "Najprv jantárová",
                         earlyCaption: "Ako včasné upozornenie zobrazí nabitie jantárovou na vyššej úrovni alebo pod ňou.",
                         earlyThreshold: "Jantárová úroveň", menuBar: "Aj na lište ponúk")
        case .de:
            return .init(title: "Bei niedrigem Akku rot färben", caption: "Zeigt die Ladung im Akkubetrieb ab dieser Stufe und darunter in Rot.",
                         threshold: "Rote Stufe", early: "Zuerst bernsteinfarben",
                         earlyCaption: "Zeigt die Ladung als frühe Warnung ab einer höheren Stufe und darunter in Bernstein.",
                         earlyThreshold: "Bernsteinstufe", menuBar: "Auch in der Menüleiste")
        case .fr:
            return .init(title: "Passer en rouge si faible", caption: "Affiche la charge en rouge à ce niveau ou en dessous lorsque le Mac est sur batterie.",
                         threshold: "Niveau rouge", early: "Passer d’abord en ambre",
                         earlyCaption: "Affiche la charge en ambre à un niveau plus élevé ou en dessous, comme premier avertissement.",
                         earlyThreshold: "Niveau ambre", menuBar: "Aussi dans la barre des menus")
        case .it:
            return .init(title: "Diventa rosso quando è scarica", caption: "Mostra la carica in rosso a questo livello o al di sotto quando il Mac è a batteria.",
                         threshold: "Livello rosso", early: "Prima ambra",
                         earlyCaption: "Mostra la carica in ambra a un livello più alto o al di sotto, come primo avviso.",
                         earlyThreshold: "Livello ambra", menuBar: "Anche nella barra dei menu")
        case .ja:
            return .init(title: "残量が少ないときに赤く表示", caption: "バッテリー駆動中、残量がこのレベル以下になると赤で表示します。",
                         threshold: "赤のレベル", early: "先に黄色で表示",
                         earlyCaption: "早めの警告として、より高いレベル以下になると黄色で表示します。",
                         earlyThreshold: "黄色のレベル", menuBar: "メニューバーにも表示")
        case .ko:
            return .init(title: "배터리가 부족하면 빨간색으로 표시", caption: "배터리로 작동하는 동안 충전량이 이 수준 이하가 되면 빨간색으로 표시합니다.",
                         threshold: "빨간색 수준", early: "먼저 주황색으로 표시",
                         earlyCaption: "조기 경고로, 더 높은 수준 이하가 되면 충전량을 주황색으로 표시합니다.",
                         earlyThreshold: "주황색 수준", menuBar: "메뉴 막대에도 표시")
        case .uk:
            return .init(title: "Червоний при низькому заряді", caption: "Показує заряд червоним на цьому рівні або нижче під час роботи від батареї.",
                         threshold: "Червоний рівень", early: "Спершу бурштиновий",
                         earlyCaption: "Показує заряд бурштиновим на вищому рівні або нижче як раннє попередження.",
                         earlyThreshold: "Бурштиновий рівень", menuBar: "Також у рядку меню")
        case .zhHans:
            return .init(title: "电量低时显示为红色", caption: "使用电池时，电量达到或低于此水平会显示为红色。",
                         threshold: "红色电量", early: "先显示为琥珀色",
                         earlyCaption: "作为提前警告，电量达到或低于更高水平时显示为琥珀色。",
                         earlyThreshold: "琥珀色电量", menuBar: "也在菜单栏中显示")
        case .zhTW:
            return .init(title: "電量低時顯示為紅色", caption: "使用電池時，電量達到或低於此程度會顯示為紅色。",
                         threshold: "紅色電量", early: "先顯示為琥珀色",
                         earlyCaption: "作為提前警告，電量達到或低於較高程度時顯示為琥珀色。",
                         earlyThreshold: "琥珀色電量", menuBar: "也在選單列中顯示")
        case .zhHK:
            return .init(title: "電量低時顯示為紅色", caption: "使用電池時，電量達到或低於此水平會顯示為紅色。",
                         threshold: "紅色電量", early: "先顯示為琥珀色",
                         earlyCaption: "作為提前警告，電量達到或低於較高水平時顯示為琥珀色。",
                         earlyThreshold: "琥珀色電量", menuBar: "亦在選單列中顯示")
        }
    }
}
