// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the display brightness feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct BrightnessFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let externalCaption: String
    let noDisplays: String
    let keysToggle: String
    let keysCaption: String
}

extension FeatureStrings {
    static func brightness(_ language: AppLanguage) -> BrightnessFeatureStrings {
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
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension BrightnessFeatureStrings {
    static let enUS = BrightnessFeatureStrings(
        pageTitle: "Screen brightness",
        hubDescription: "Brightness sliders for every display",
        enable: "Control display brightness",
        enableCaption: "Sliders for the built-in screen and external monitors, here and in the menu bar panel.",
        externalCaption: "External monitors are adjusted through the same protocol as their own buttons. When the connection cannot carry it, as with HDMI adapters, the slider dims the picture instead, so brightness control works either way.",
        noDisplays: "No adjustable display found.",
        keysToggle: "Brightness keys follow the pointer",
        keysCaption: "The keyboard brightness keys change the display under the pointer."
    )

    static let ptBR = BrightnessFeatureStrings(
        pageTitle: "Brilho da tela",
        hubDescription: "Controle de brilho para todas as telas",
        enable: "Controlar o brilho das telas",
        enableCaption: "Controles para a tela do Mac e monitores externos, aqui e no painel da barra de menus.",
        externalCaption: "Monitores externos são ajustados pelo mesmo protocolo dos botões do próprio monitor. Quando a conexão não transmite esse protocolo, como em adaptadores HDMI, o controle escurece a imagem, então o ajuste funciona de qualquer forma.",
        noDisplays: "Nenhuma tela ajustável encontrada.",
        keysToggle: "Teclas de brilho seguem o ponteiro",
        keysCaption: "As teclas de brilho do teclado mudam a tela onde o ponteiro está."
    )

    static let tr = BrightnessFeatureStrings(
        pageTitle: "Ekran parlaklığı",
        hubDescription: "Tüm ekranlar için parlaklık denetimi",
        enable: "Ekran parlaklığını denetle",
        enableCaption: "Yerleşik ekran ve harici monitörler için kaydırıcılar, burada ve menü çubuğu panelinde.",
        externalCaption: "Harici monitörler, kendi düğmelerinin kullandığı protokolle ayarlanır. Bağlantı bu protokolü taşıyamadığında, örneğin HDMI adaptörlerinde, kaydırıcı bunun yerine görüntüyü karartır; parlaklık denetimi her durumda çalışır.",
        noDisplays: "Ayarlanabilir ekran bulunamadı.",
        keysToggle: "Parlaklık tuşları imleci izler",
        keysCaption: "Klavyedeki parlaklık tuşları imlecin bulunduğu ekranı değiştirir."
    )

    static let ru = BrightnessFeatureStrings(
        pageTitle: "Яркость экрана",
        hubDescription: "Регулировка яркости всех экранов",
        enable: "Управлять яркостью экранов",
        enableCaption: "Ползунки для встроенного экрана и внешних мониторов, здесь и в панели строки меню.",
        externalCaption: "Внешние мониторы настраиваются тем же протоколом, что и их собственные кнопки. Если соединение не передаёт этот протокол, например через адаптеры HDMI, ползунок затемняет изображение, так что регулировка работает в любом случае.",
        noDisplays: "Настраиваемый экран не найден.",
        keysToggle: "Клавиши яркости следуют за указателем",
        keysCaption: "Клавиши яркости на клавиатуре меняют экран, на котором находится указатель."
    )

    static let es = BrightnessFeatureStrings(
        pageTitle: "Brillo de la pantalla",
        hubDescription: "Control de brillo para todas las pantallas",
        enable: "Controlar el brillo de las pantallas",
        enableCaption: "Controles para la pantalla integrada y los monitores externos, aquí y en el panel de la barra de menús.",
        externalCaption: "Los monitores externos se ajustan con el mismo protocolo que sus propios botones. Cuando la conexión no transmite ese protocolo, como con adaptadores HDMI, el control oscurece la imagen, así que el ajuste funciona igualmente.",
        noDisplays: "No se encontró ninguna pantalla ajustable.",
        keysToggle: "Las teclas de brillo siguen al puntero",
        keysCaption: "Las teclas de brillo del teclado cambian la pantalla donde está el puntero."
    )

    static let de = BrightnessFeatureStrings(
        pageTitle: "Bildschirmhelligkeit",
        hubDescription: "Helligkeitsregler für alle Displays",
        enable: "Displayhelligkeit steuern",
        enableCaption: "Regler für das eingebaute Display und externe Monitore, hier und im Menüleistenpanel.",
        externalCaption: "Externe Monitore werden über dasselbe Protokoll wie ihre eigenen Tasten eingestellt. Trägt die Verbindung es nicht, etwa bei HDMI-Adaptern, dunkelt der Regler stattdessen das Bild ab, sodass die Helligkeit in jedem Fall steuerbar bleibt.",
        noDisplays: "Kein einstellbares Display gefunden.",
        keysToggle: "Helligkeitstasten folgen dem Zeiger",
        keysCaption: "Die Helligkeitstasten der Tastatur ändern das Display, auf dem der Zeiger steht."
    )

    static let fr = BrightnessFeatureStrings(
        pageTitle: "Luminosité de l'écran",
        hubDescription: "Réglage de la luminosité de tous les écrans",
        enable: "Contrôler la luminosité des écrans",
        enableCaption: "Curseurs pour l'écran intégré et les moniteurs externes, ici et dans le panneau de la barre des menus.",
        externalCaption: "Les moniteurs externes sont réglés par le même protocole que leurs propres boutons. Quand la connexion ne le transmet pas, comme avec les adaptateurs HDMI, le curseur assombrit l'image, le réglage fonctionne donc dans tous les cas.",
        noDisplays: "Aucun écran réglable trouvé.",
        keysToggle: "Les touches de luminosité suivent le pointeur",
        keysCaption: "Les touches de luminosité du clavier règlent l'écran où se trouve le pointeur."
    )

    static let it = BrightnessFeatureStrings(
        pageTitle: "Luminosità dello schermo",
        hubDescription: "Regolazione della luminosità di tutti gli schermi",
        enable: "Controlla la luminosità degli schermi",
        enableCaption: "Cursori per lo schermo integrato e i monitor esterni, qui e nel pannello della barra dei menu.",
        externalCaption: "I monitor esterni vengono regolati con lo stesso protocollo dei loro pulsanti. Quando il collegamento non lo trasmette, come con gli adattatori HDMI, il cursore scurisce l'immagine, quindi la regolazione funziona comunque.",
        noDisplays: "Nessuno schermo regolabile trovato.",
        keysToggle: "I tasti di luminosità seguono il puntatore",
        keysCaption: "I tasti di luminosità della tastiera regolano lo schermo dove si trova il puntatore."
    )

    static let ja = BrightnessFeatureStrings(
        pageTitle: "画面の輝度",
        hubDescription: "すべてのディスプレイの輝度を調整",
        enable: "ディスプレイの輝度を調整",
        enableCaption: "内蔵ディスプレイと外部モニタのスライダを、こことメニューバーパネルに表示します。",
        externalCaption: "外部モニタは本体のボタンと同じプロトコルで調整します。HDMI変換アダプタなどでこのプロトコルが通らない場合は、スライダが代わりに画面を暗くするため、どの接続でも輝度を調整できます。",
        noDisplays: "調整できるディスプレイが見つかりません。",
        keysToggle: "輝度キーはポインタに従う",
        keysCaption: "キーボードの輝度キーが、ポインタのあるディスプレイを調整します。"
    )

    static let zhHans = BrightnessFeatureStrings(
        pageTitle: "屏幕亮度",
        hubDescription: "为所有显示器调节亮度",
        enable: "控制显示器亮度",
        enableCaption: "内置屏幕和外接显示器的亮度滑块，显示在这里和菜单栏面板中。",
        externalCaption: "外接显示器通过与其自身按键相同的协议调节。当连接无法传输该协议时（例如 HDMI 转接器），滑块会改为调暗画面，因此亮度调节始终可用。",
        noDisplays: "未找到可调节的显示器。",
        keysToggle: "亮度键跟随指针",
        keysCaption: "键盘上的亮度键调节指针所在的显示器。"
    )

    static let zhTW = BrightnessFeatureStrings(
        pageTitle: "螢幕亮度",
        hubDescription: "調整所有顯示器的亮度",
        enable: "控制顯示器亮度",
        enableCaption: "內建螢幕和外接顯示器的亮度滑桿，顯示在這裡和選單列面板中。",
        externalCaption: "外接顯示器透過與其本身按鍵相同的協定調整。當連接無法傳輸該協定時（例如 HDMI 轉接器），滑桿會改為調暗畫面，因此亮度調整始終可用。",
        noDisplays: "找不到可調整的顯示器。",
        keysToggle: "亮度鍵跟隨指標",
        keysCaption: "鍵盤上的亮度鍵調整指標所在的顯示器。"
    )

    static let zhHK = BrightnessFeatureStrings(
        pageTitle: "螢幕亮度",
        hubDescription: "調整所有顯示器的亮度",
        enable: "控制顯示器亮度",
        enableCaption: "內置螢幕和外接顯示器的亮度滑桿，顯示在這裏和選單列面板中。",
        externalCaption: "外接顯示器透過與其本身按鍵相同的協定調整。當連接無法傳輸該協定時（例如 HDMI 轉接器），滑桿會改為調暗畫面，因此亮度調整始終可用。",
        noDisplays: "找不到可調整的顯示器。",
        keysToggle: "亮度鍵跟隨指標",
        keysCaption: "鍵盤上的亮度鍵調整指標所在的顯示器。"
    )
}
