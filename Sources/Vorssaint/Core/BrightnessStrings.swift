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
    let displayOff: String
    let turnOffDisplay: String
    let turnOnDisplay: String
    let lastDisplayCaption: String
    let switchUnavailable: String
    let switchFailed: String
    let keysToggle: String
    let keysCaption: String
    let osdToggle: String
    let osdCaption: String
    let keyboardLight: String
    let keyboardLightCaption: String
    let volumeToggle: String
    let volumeCaption: String
    let volumeLabel: String
    let mute: String
    let unmute: String
    let volumeKeysToggle: String
    let volumeKeysCaption: String
    let allDisplays: String
    let combinedToggle: String
    let combinedCaption: String
    let syncToggle: String
    let syncCaption: String
    let turnOnHDR: String
    let turnOffHDR: String
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
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension BrightnessFeatureStrings {
    static let enUS = BrightnessFeatureStrings(
        pageTitle: "Displays",
        hubDescription: "Brightness and power controls for every display",
        enable: "Control displays",
        enableCaption: "Brightness and on or off controls for the built-in screen and external monitors, here and in the menu bar panel.",
        externalCaption: "External monitors are adjusted through the same protocol as their own buttons. When the connection cannot carry it, as with HDMI adapters, the slider dims the picture instead, so brightness control works either way.",
        noDisplays: "No display found.",
        displayOff: "Off",
        turnOffDisplay: "Turn off display",
        turnOnDisplay: "Turn on display",
        lastDisplayCaption: "At least one display must stay on.",
        switchUnavailable: "Display switching is unavailable on this Mac.",
        switchFailed: "Could not change this display.",
        keysToggle: "Brightness keys follow the pointer",
        keysCaption: "The keyboard brightness keys change the display under the pointer.",
        osdToggle: "Show brightness when adjusting",
        osdCaption: "Shows the brightness percentage when you use the brightness keys or sliders.",
        keyboardLight: "Keyboard light",
        keyboardLightCaption: "Turns the keyboard backlight on or off.",
        volumeToggle: "Monitor speakers",
        volumeCaption: "Monitors with speakers of their own get a volume slider here, over the same channel their buttons use. Displays with no speakers never show one.",
        volumeLabel: "Volume",
        mute: "Mute",
        unmute: "Unmute",
        volumeKeysToggle: "Volume keys reach monitor speakers",
        volumeKeysCaption: "While the sound comes out of a monitor, the keyboard volume keys move that monitor instead of a level macOS cannot change.",
        allDisplays: "All displays",
        combinedToggle: "One slider for every display",
        combinedCaption: "Adds a slider that moves every display at once, keeping the differences between them.",
        syncToggle: "External displays follow the built-in screen",
        syncCaption: "When the built-in screen changes brightness, by hand or by ambient light, external monitors move with it.",
        turnOnHDR: "Turn on HDR",
        turnOffHDR: "Turn off HDR"
    )

    static let ptBR = BrightnessFeatureStrings(
        pageTitle: "Telas",
        hubDescription: "Brilho e controles para ligar ou desligar cada tela",
        enable: "Controlar telas",
        enableCaption: "Controles de brilho e de ligar ou desligar para a tela do Mac e monitores externos, aqui e no painel da barra de menus.",
        externalCaption: "Monitores externos são ajustados pelo mesmo protocolo dos botões do próprio monitor. Quando a conexão não transmite esse protocolo, como em adaptadores HDMI, o controle escurece a imagem, então o ajuste funciona de qualquer forma.",
        noDisplays: "Nenhuma tela encontrada.",
        displayOff: "Desligada",
        turnOffDisplay: "Desligar tela",
        turnOnDisplay: "Ligar tela",
        lastDisplayCaption: "Pelo menos uma tela deve continuar ligada.",
        switchUnavailable: "Não é possível ligar ou desligar telas neste Mac.",
        switchFailed: "Não foi possível alterar esta tela.",
        keysToggle: "Teclas de brilho seguem o ponteiro",
        keysCaption: "As teclas de brilho do teclado mudam a tela onde o ponteiro está.",
        osdToggle: "Mostrar brilho ao ajustar",
        osdCaption: "Mostra a porcentagem de brilho ao usar as teclas ou os controles de brilho.",
        keyboardLight: "Luz do teclado",
        keyboardLightCaption: "Liga ou desliga a luz do teclado.",
        volumeToggle: "Alto-falantes do monitor",
        volumeCaption: "Monitores com alto-falantes próprios ganham aqui um controle de volume, pelo mesmo canal que os botões deles usam. Telas sem alto-falantes nunca mostram um.",
        volumeLabel: "Volume",
        mute: "Silenciar",
        unmute: "Ativar o som",
        volumeKeysToggle: "Teclas de volume alcançam os alto-falantes do monitor",
        volumeKeysCaption: "Enquanto o som sai por um monitor, as teclas de volume do teclado ajustam esse monitor em vez de um nível que o macOS não consegue mudar.",
        allDisplays: "Todas as telas",
        combinedToggle: "Um controle para todas as telas",
        combinedCaption: "Adiciona um controle que move todas as telas de uma vez, mantendo as diferenças entre elas.",
        syncToggle: "Telas externas seguem a tela do Mac",
        syncCaption: "Quando a tela do Mac muda de brilho, manualmente ou pela luz do ambiente, os monitores externos acompanham.",
        turnOnHDR: "Ativar HDR",
        turnOffHDR: "Desativar HDR"
    )

    static let tr = BrightnessFeatureStrings(
        pageTitle: "Ekranlar",
        hubDescription: "Tüm ekranlar için parlaklık ve güç denetimleri",
        enable: "Ekranları denetle",
        enableCaption: "Yerleşik ekran ve harici monitörler için parlaklık ve açma kapatma denetimleri, burada ve menü çubuğu panelinde.",
        externalCaption: "Harici monitörler, kendi düğmelerinin kullandığı protokolle ayarlanır. Bağlantı bu protokolü taşıyamadığında, örneğin HDMI adaptörlerinde, kaydırıcı bunun yerine görüntüyü karartır; parlaklık denetimi her durumda çalışır.",
        noDisplays: "Ekran bulunamadı.",
        displayOff: "Kapalı",
        turnOffDisplay: "Ekranı kapat",
        turnOnDisplay: "Ekranı aç",
        lastDisplayCaption: "En az bir ekran açık kalmalıdır.",
        switchUnavailable: "Bu Mac'te ekran açma ve kapatma kullanılamıyor.",
        switchFailed: "Bu ekran değiştirilemedi.",
        keysToggle: "Parlaklık tuşları imleci izler",
        keysCaption: "Klavyedeki parlaklık tuşları imlecin bulunduğu ekranı değiştirir.",
        osdToggle: "Parlaklık ayarlanırken göster",
        osdCaption: "Parlaklık tuşlarını veya kaydırıcıları kullandığınızda parlaklık yüzdesini gösterir.",
        keyboardLight: "Klavye ışığı",
        keyboardLightCaption: "Klavye ışığını açar veya kapatır.",
        volumeToggle: "Monitör hoparlörleri",
        volumeCaption: "Kendi hoparlörü olan monitörler burada bir ses kaydırıcısı alır, düğmelerinin kullandığı kanal üzerinden. Hoparlörü olmayan ekranlarda hiç görünmez.",
        volumeLabel: "Ses düzeyi",
        mute: "Sesi kapat",
        unmute: "Sesi aç",
        volumeKeysToggle: "Ses tuşları monitör hoparlörlerine ulaşır",
        volumeKeysCaption: "Ses bir monitörden çıkarken, klavyedeki ses tuşları macOS'un değiştiremediği bir düzey yerine o monitörü ayarlar.",
        allDisplays: "Tüm ekranlar",
        combinedToggle: "Tüm ekranlar için tek kaydırıcı",
        combinedCaption: "Tüm ekranları aynı anda hareket ettiren, aralarındaki farkları koruyan bir kaydırıcı ekler.",
        syncToggle: "Harici ekranlar yerleşik ekranı izler",
        syncCaption: "Yerleşik ekranın parlaklığı elle veya ortam ışığıyla değiştiğinde, harici monitörler de onunla birlikte değişir.",
        turnOnHDR: "HDR'yi aç",
        turnOffHDR: "HDR'yi kapat"
    )

    static let ru = BrightnessFeatureStrings(
        pageTitle: "Экраны",
        hubDescription: "Яркость и включение всех экранов",
        enable: "Управлять экранами",
        enableCaption: "Настройки яркости и включения встроенного экрана и внешних мониторов здесь и в панели строки меню.",
        externalCaption: "Внешние мониторы настраиваются тем же протоколом, что и их собственные кнопки. Если соединение не передаёт этот протокол, например через адаптеры HDMI, ползунок затемняет изображение, так что регулировка работает в любом случае.",
        noDisplays: "Экраны не найдены.",
        displayOff: "Выключен",
        turnOffDisplay: "Выключить экран",
        turnOnDisplay: "Включить экран",
        lastDisplayCaption: "Хотя бы один экран должен оставаться включённым.",
        switchUnavailable: "Управление включением экранов недоступно на этом Mac.",
        switchFailed: "Не удалось изменить состояние экрана.",
        keysToggle: "Клавиши яркости следуют за указателем",
        keysCaption: "Клавиши яркости на клавиатуре меняют экран, на котором находится указатель.",
        osdToggle: "Показывать яркость при регулировке",
        osdCaption: "Показывает яркость в процентах при использовании клавиш или ползунков яркости.",
        keyboardLight: "Подсветка клавиатуры",
        keyboardLightCaption: "Включает или выключает подсветку клавиатуры.",
        volumeToggle: "Динамики монитора",
        volumeCaption: "Мониторы с собственными динамиками получают здесь ползунок громкости, по тому же каналу, что и их кнопки. У экранов без динамиков он не появляется.",
        volumeLabel: "Громкость",
        mute: "Выключить звук",
        unmute: "Включить звук",
        volumeKeysToggle: "Клавиши громкости управляют динамиками монитора",
        volumeKeysCaption: "Пока звук идёт через монитор, клавиши громкости меняют именно его уровень, а не тот, который macOS изменить не может.",
        allDisplays: "Все экраны",
        combinedToggle: "Один ползунок для всех экранов",
        combinedCaption: "Добавляет ползунок, который двигает все экраны сразу, сохраняя разницу между ними.",
        syncToggle: "Внешние экраны следуют за встроенным",
        syncCaption: "Когда яркость встроенного экрана меняется вручную или по внешнему освещению, внешние мониторы меняются вместе с ним.",
        turnOnHDR: "Включить HDR",
        turnOffHDR: "Выключить HDR"
    )

    static let es = BrightnessFeatureStrings(
        pageTitle: "Pantallas",
        hubDescription: "Brillo y encendido para todas las pantallas",
        enable: "Controlar las pantallas",
        enableCaption: "Controles de brillo y encendido para la pantalla integrada y los monitores externos, aquí y en el panel de la barra de menús.",
        externalCaption: "Los monitores externos se ajustan con el mismo protocolo que sus propios botones. Cuando la conexión no transmite ese protocolo, como con adaptadores HDMI, el control oscurece la imagen, así que el ajuste funciona igualmente.",
        noDisplays: "No se encontró ninguna pantalla.",
        displayOff: "Apagada",
        turnOffDisplay: "Apagar pantalla",
        turnOnDisplay: "Encender pantalla",
        lastDisplayCaption: "Al menos una pantalla debe permanecer encendida.",
        switchUnavailable: "El encendido de pantallas no está disponible en este Mac.",
        switchFailed: "No se pudo cambiar esta pantalla.",
        keysToggle: "Las teclas de brillo siguen al puntero",
        keysCaption: "Las teclas de brillo del teclado cambian la pantalla donde está el puntero.",
        osdToggle: "Mostrar el brillo al ajustarlo",
        osdCaption: "Muestra el porcentaje de brillo al usar las teclas o los controles de brillo.",
        keyboardLight: "Luz del teclado",
        keyboardLightCaption: "Enciende o apaga la luz del teclado.",
        volumeToggle: "Altavoces del monitor",
        volumeCaption: "Los monitores con altavoces propios reciben aquí un control de volumen, por el mismo canal que usan sus botones. Las pantallas sin altavoces no muestran ninguno.",
        volumeLabel: "Volumen",
        mute: "Silenciar",
        unmute: "Activar el sonido",
        volumeKeysToggle: "Las teclas de volumen llegan a los altavoces del monitor",
        volumeKeysCaption: "Mientras el sonido sale por un monitor, las teclas de volumen del teclado ajustan ese monitor en lugar de un nivel que macOS no puede cambiar.",
        allDisplays: "Todas las pantallas",
        combinedToggle: "Un control para todas las pantallas",
        combinedCaption: "Añade un control que mueve todas las pantallas a la vez y mantiene las diferencias entre ellas.",
        syncToggle: "Las pantallas externas siguen a la integrada",
        syncCaption: "Cuando la pantalla integrada cambia de brillo, a mano o por la luz del entorno, los monitores externos la acompañan.",
        turnOnHDR: "Activar HDR",
        turnOffHDR: "Desactivar HDR"
    )

    static let de = BrightnessFeatureStrings(
        pageTitle: "Displays",
        hubDescription: "Helligkeit und Ein oder Aus für alle Displays",
        enable: "Displays steuern",
        enableCaption: "Regler für Helligkeit und Ein oder Aus für das eingebaute Display und externe Monitore, hier und im Menüleistenpanel.",
        externalCaption: "Externe Monitore werden über dasselbe Protokoll wie ihre eigenen Tasten eingestellt. Trägt die Verbindung es nicht, etwa bei HDMI-Adaptern, dunkelt der Regler stattdessen das Bild ab, sodass die Helligkeit in jedem Fall steuerbar bleibt.",
        noDisplays: "Kein Display gefunden.",
        displayOff: "Aus",
        turnOffDisplay: "Display ausschalten",
        turnOnDisplay: "Display einschalten",
        lastDisplayCaption: "Mindestens ein Display muss eingeschaltet bleiben.",
        switchUnavailable: "Die Displaysteuerung ist auf diesem Mac nicht verfügbar.",
        switchFailed: "Dieses Display konnte nicht geändert werden.",
        keysToggle: "Helligkeitstasten folgen dem Zeiger",
        keysCaption: "Die Helligkeitstasten der Tastatur ändern das Display, auf dem der Zeiger steht.",
        osdToggle: "Helligkeit beim Anpassen anzeigen",
        osdCaption: "Zeigt den Helligkeitswert in Prozent bei Verwendung der Helligkeitstasten oder Regler.",
        keyboardLight: "Tastaturbeleuchtung",
        keyboardLightCaption: "Schaltet die Tastaturbeleuchtung ein oder aus.",
        volumeToggle: "Monitorlautsprecher",
        volumeCaption: "Monitore mit eigenen Lautsprechern bekommen hier einen Lautstärkeregler, über denselben Kanal wie ihre eigenen Tasten. Displays ohne Lautsprecher zeigen keinen.",
        volumeLabel: "Lautstärke",
        mute: "Stummschalten",
        unmute: "Ton einschalten",
        volumeKeysToggle: "Lautstärketasten erreichen die Monitorlautsprecher",
        volumeKeysCaption: "Solange der Ton aus einem Monitor kommt, regeln die Lautstärketasten diesen Monitor statt eines Pegels, den macOS nicht ändern kann.",
        allDisplays: "Alle Displays",
        combinedToggle: "Ein Regler für alle Displays",
        combinedCaption: "Fügt einen Regler hinzu, der alle Displays zugleich bewegt und ihre Unterschiede beibehält.",
        syncToggle: "Externe Displays folgen dem eingebauten",
        syncCaption: "Ändert das eingebaute Display seine Helligkeit, von Hand oder durch das Umgebungslicht, ziehen externe Monitore mit.",
        turnOnHDR: "HDR einschalten",
        turnOffHDR: "HDR ausschalten"
    )

    static let fr = BrightnessFeatureStrings(
        pageTitle: "Écrans",
        hubDescription: "Luminosité et alimentation de tous les écrans",
        enable: "Contrôler les écrans",
        enableCaption: "Contrôles de luminosité et d'alimentation pour l'écran intégré et les moniteurs externes, ici et dans le panneau de la barre des menus.",
        externalCaption: "Les moniteurs externes sont réglés par le même protocole que leurs propres boutons. Quand la connexion ne le transmet pas, comme avec les adaptateurs HDMI, le curseur assombrit l'image, le réglage fonctionne donc dans tous les cas.",
        noDisplays: "Aucun écran détecté.",
        displayOff: "Éteint",
        turnOffDisplay: "Éteindre l'écran",
        turnOnDisplay: "Allumer l'écran",
        lastDisplayCaption: "Au moins un écran doit rester allumé.",
        switchUnavailable: "Le contrôle d'alimentation des écrans n'est pas disponible sur ce Mac.",
        switchFailed: "Impossible de modifier cet écran.",
        keysToggle: "Les touches de luminosité suivent le pointeur",
        keysCaption: "Les touches de luminosité du clavier règlent l'écran où se trouve le pointeur.",
        osdToggle: "Afficher la luminosité pendant le réglage",
        osdCaption: "Affiche le pourcentage de luminosité avec les touches ou les curseurs de luminosité.",
        keyboardLight: "Éclairage du clavier",
        keyboardLightCaption: "Allume ou éteint l’éclairage du clavier.",
        volumeToggle: "Haut-parleurs du moniteur",
        volumeCaption: "Les moniteurs dotés de haut-parleurs reçoivent ici un curseur de volume, par le même canal que leurs propres boutons. Les écrans sans haut-parleurs n'en affichent aucun.",
        volumeLabel: "Volume",
        mute: "Couper le son",
        unmute: "Rétablir le son",
        volumeKeysToggle: "Les touches de volume atteignent les haut-parleurs du moniteur",
        volumeKeysCaption: "Tant que le son sort d'un moniteur, les touches de volume règlent ce moniteur au lieu d'un niveau que macOS ne peut pas changer.",
        allDisplays: "Tous les écrans",
        combinedToggle: "Un seul curseur pour tous les écrans",
        combinedCaption: "Ajoute un curseur qui déplace tous les écrans à la fois en conservant leurs écarts.",
        syncToggle: "Les écrans externes suivent l'écran intégré",
        syncCaption: "Quand la luminosité de l'écran intégré change, à la main ou selon la lumière ambiante, les moniteurs externes suivent.",
        turnOnHDR: "Activer le HDR",
        turnOffHDR: "Désactiver le HDR"
    )

    static let it = BrightnessFeatureStrings(
        pageTitle: "Schermi",
        hubDescription: "Luminosità e accensione per tutti gli schermi",
        enable: "Controlla gli schermi",
        enableCaption: "Controlli di luminosità e accensione per lo schermo integrato e i monitor esterni, qui e nel pannello della barra dei menu.",
        externalCaption: "I monitor esterni vengono regolati con lo stesso protocollo dei loro pulsanti. Quando il collegamento non lo trasmette, come con gli adattatori HDMI, il cursore scurisce l'immagine, quindi la regolazione funziona comunque.",
        noDisplays: "Nessuno schermo trovato.",
        displayOff: "Spento",
        turnOffDisplay: "Spegni schermo",
        turnOnDisplay: "Accendi schermo",
        lastDisplayCaption: "Almeno uno schermo deve rimanere acceso.",
        switchUnavailable: "Il controllo di accensione degli schermi non è disponibile su questo Mac.",
        switchFailed: "Non è stato possibile modificare questo schermo.",
        keysToggle: "I tasti di luminosità seguono il puntatore",
        keysCaption: "I tasti di luminosità della tastiera regolano lo schermo dove si trova il puntatore.",
        osdToggle: "Mostra la luminosità durante la regolazione",
        osdCaption: "Mostra la percentuale di luminosità quando usi i tasti o i cursori della luminosità.",
        keyboardLight: "Illuminazione tastiera",
        keyboardLightCaption: "Accende o spegne l’illuminazione della tastiera.",
        volumeToggle: "Altoparlanti del monitor",
        volumeCaption: "I monitor con altoparlanti propri ricevono qui un cursore del volume, sullo stesso canale usato dai loro pulsanti. Gli schermi senza altoparlanti non ne mostrano nessuno.",
        volumeLabel: "Volume",
        mute: "Silenzia",
        unmute: "Riattiva l'audio",
        volumeKeysToggle: "I tasti volume raggiungono gli altoparlanti del monitor",
        volumeKeysCaption: "Finché l'audio esce da un monitor, i tasti volume regolano quel monitor invece di un livello che macOS non può cambiare.",
        allDisplays: "Tutti gli schermi",
        combinedToggle: "Un cursore per tutti gli schermi",
        combinedCaption: "Aggiunge un cursore che muove tutti gli schermi insieme, mantenendo le differenze fra loro.",
        syncToggle: "Gli schermi esterni seguono quello integrato",
        syncCaption: "Quando lo schermo integrato cambia luminosità, a mano o per la luce dell'ambiente, i monitor esterni lo seguono.",
        turnOnHDR: "Attiva HDR",
        turnOffHDR: "Disattiva HDR"
    )

    static let ja = BrightnessFeatureStrings(
        pageTitle: "ディスプレイ",
        hubDescription: "すべてのディスプレイの明るさと電源を操作",
        enable: "ディスプレイを操作",
        enableCaption: "内蔵ディスプレイと外部モニタの明るさと電源を、こことメニューバーパネルで操作します。",
        externalCaption: "外部モニタは本体のボタンと同じプロトコルで調整します。HDMI変換アダプタなどでこのプロトコルが通らない場合は、スライダが代わりに画面を暗くするため、どの接続でも輝度を調整できます。",
        noDisplays: "ディスプレイが見つかりません。",
        displayOff: "オフ",
        turnOffDisplay: "ディスプレイの電源を切る",
        turnOnDisplay: "ディスプレイの電源を入れる",
        lastDisplayCaption: "少なくとも1台のディスプレイをオンのままにしてください。",
        switchUnavailable: "このMacではディスプレイの切り替えを利用できません。",
        switchFailed: "このディスプレイを切り替えられませんでした。",
        keysToggle: "輝度キーはポインタに従う",
        keysCaption: "キーボードの輝度キーが、ポインタのあるディスプレイを調整します。",
        osdToggle: "明るさの調整時に表示",
        osdCaption: "輝度キーまたはスライダを使うと、明るさをパーセントで表示します。",
        keyboardLight: "キーボードのバックライト",
        keyboardLightCaption: "キーボードのバックライトをオンまたはオフにします。",
        volumeToggle: "モニタのスピーカー",
        volumeCaption: "スピーカーを内蔵したモニタには、本体のボタンと同じチャンネルで音量スライダが表示されます。スピーカーのないディスプレイには表示されません。",
        volumeLabel: "音量",
        mute: "消音",
        unmute: "消音を解除",
        volumeKeysToggle: "音量キーでモニタのスピーカーを操作",
        volumeKeysCaption: "音がモニタから出ている間、キーボードの音量キーは macOS が変更できない値ではなく、そのモニタを調整します。",
        allDisplays: "すべてのディスプレイ",
        combinedToggle: "すべてのディスプレイをまとめて操作",
        combinedCaption: "すべてのディスプレイを一度に動かすスライダを追加します。ディスプレイ間の差はそのまま保たれます。",
        syncToggle: "外部ディスプレイを内蔵画面に合わせる",
        syncCaption: "内蔵画面の明るさが手動または周囲の明るさで変わると、外部モニタもそれに合わせて変わります。",
        turnOnHDR: "HDRをオンにする",
        turnOffHDR: "HDRをオフにする"
    )

    static let ko = BrightnessFeatureStrings(
        pageTitle: "디스플레이",
        hubDescription: "모든 디스플레이의 밝기와 전원 제어",
        enable: "디스플레이 제어",
        enableCaption: "내장 화면과 외부 모니터의 밝기와 전원을 여기와 메뉴 막대 패널에서 제어합니다.",
        externalCaption: "외부 모니터는 자체 버튼과 동일한 프로토콜로 조절됩니다. HDMI 어댑터처럼 연결이 이 프로토콜을 지원하지 않으면 슬라이더가 대신 화면을 어둡게 하므로 어느 경우든 밝기를 조절할 수 있습니다.",
        noDisplays: "디스플레이를 찾을 수 없습니다.",
        displayOff: "꺼짐",
        turnOffDisplay: "디스플레이 끄기",
        turnOnDisplay: "디스플레이 켜기",
        lastDisplayCaption: "최소 한 대의 디스플레이는 켜져 있어야 합니다.",
        switchUnavailable: "이 Mac에서는 디스플레이 전원 제어를 사용할 수 없습니다.",
        switchFailed: "이 디스플레이를 변경할 수 없습니다.",
        keysToggle: "밝기 키가 포인터를 따라감",
        keysCaption: "키보드의 밝기 키로 포인터가 있는 디스플레이를 조절합니다.",
        osdToggle: "밝기 조절 시 표시",
        osdCaption: "밝기 키나 슬라이더를 사용할 때 밝기를 백분율로 표시합니다.",
        keyboardLight: "키보드 백라이트",
        keyboardLightCaption: "키보드 백라이트를 켜거나 끕니다.",
        volumeToggle: "모니터 스피커",
        volumeCaption: "자체 스피커가 있는 모니터에는 버튼과 동일한 채널로 음량 슬라이더가 표시됩니다. 스피커가 없는 디스플레이에는 표시되지 않습니다.",
        volumeLabel: "음량",
        mute: "음소거",
        unmute: "음소거 해제",
        volumeKeysToggle: "음량 키로 모니터 스피커 조절",
        volumeKeysCaption: "소리가 모니터에서 나오는 동안, 키보드 음량 키는 macOS가 바꿀 수 없는 값 대신 해당 모니터를 조절합니다.",
        allDisplays: "모든 디스플레이",
        combinedToggle: "모든 디스플레이를 한 슬라이더로",
        combinedCaption: "모든 디스플레이를 한 번에 움직이는 슬라이더를 추가하며, 디스플레이 사이의 차이는 그대로 유지합니다.",
        syncToggle: "외부 디스플레이가 내장 화면을 따름",
        syncCaption: "내장 화면의 밝기가 직접 또는 주변 밝기에 따라 바뀌면 외부 모니터도 함께 바뀝니다.",
        turnOnHDR: "HDR 켜기",
        turnOffHDR: "HDR 끄기"
    )

    static let zhHans = BrightnessFeatureStrings(
        pageTitle: "显示器",
        hubDescription: "控制所有显示器的亮度和开关",
        enable: "控制显示器",
        enableCaption: "内置屏幕和外接显示器的亮度与开关控制，显示在这里和菜单栏面板中。",
        externalCaption: "外接显示器通过与其自身按键相同的协议调节。当连接无法传输该协议时（例如 HDMI 转接器），滑块会改为调暗画面，因此亮度调节始终可用。",
        noDisplays: "未找到显示器。",
        displayOff: "已关闭",
        turnOffDisplay: "关闭显示器",
        turnOnDisplay: "打开显示器",
        lastDisplayCaption: "至少要保留一台显示器开启。",
        switchUnavailable: "此 Mac 不支持显示器开关。",
        switchFailed: "无法更改这台显示器。",
        keysToggle: "亮度键跟随指针",
        keysCaption: "键盘上的亮度键调节指针所在的显示器。",
        osdToggle: "调节亮度时显示",
        osdCaption: "使用亮度键或滑块时显示亮度百分比。",
        keyboardLight: "键盘背光",
        keyboardLightCaption: "打开或关闭键盘背光。",
        volumeToggle: "显示器扬声器",
        volumeCaption: "自带扬声器的显示器会在这里获得音量滑块，通过与其按键相同的通道调节。没有扬声器的显示器不会显示滑块。",
        volumeLabel: "音量",
        mute: "静音",
        unmute: "取消静音",
        volumeKeysToggle: "音量键控制显示器扬声器",
        volumeKeysCaption: "当声音从显示器发出时，键盘上的音量键调节该显示器，而不是 macOS 无法改变的音量。",
        allDisplays: "所有显示器",
        combinedToggle: "用一个滑块控制所有显示器",
        combinedCaption: "添加一个同时调节所有显示器的滑块，并保留它们之间的差异。",
        syncToggle: "外接显示器跟随内置屏幕",
        syncCaption: "当内置屏幕的亮度手动或随环境光改变时，外接显示器随之改变。",
        turnOnHDR: "打开 HDR",
        turnOffHDR: "关闭 HDR"
    )

    static let zhTW = BrightnessFeatureStrings(
        pageTitle: "顯示器",
        hubDescription: "控制所有顯示器的亮度和開關",
        enable: "控制顯示器",
        enableCaption: "內建螢幕和外接顯示器的亮度與開關控制，顯示在這裡和選單列面板中。",
        externalCaption: "外接顯示器透過與其本身按鍵相同的協定調整。當連接無法傳輸該協定時（例如 HDMI 轉接器），滑桿會改為調暗畫面，因此亮度調整始終可用。",
        noDisplays: "找不到顯示器。",
        displayOff: "已關閉",
        turnOffDisplay: "關閉顯示器",
        turnOnDisplay: "開啟顯示器",
        lastDisplayCaption: "至少要保留一台顯示器開啟。",
        switchUnavailable: "此 Mac 不支援顯示器開關。",
        switchFailed: "無法更改這台顯示器。",
        keysToggle: "亮度鍵跟隨指標",
        keysCaption: "鍵盤上的亮度鍵調整指標所在的顯示器。",
        osdToggle: "調整亮度時顯示",
        osdCaption: "使用亮度鍵或滑桿時顯示亮度百分比。",
        keyboardLight: "鍵盤背光",
        keyboardLightCaption: "開啟或關閉鍵盤背光。",
        volumeToggle: "顯示器揚聲器",
        volumeCaption: "內建揚聲器的顯示器會在這裡出現音量滑桿，透過與其按鍵相同的通道調整。沒有揚聲器的顯示器不會顯示滑桿。",
        volumeLabel: "音量",
        mute: "靜音",
        unmute: "取消靜音",
        volumeKeysToggle: "音量鍵控制顯示器揚聲器",
        volumeKeysCaption: "當聲音從顯示器傳出時，鍵盤上的音量鍵會調整該顯示器，而不是 macOS 無法改變的音量。",
        allDisplays: "所有顯示器",
        combinedToggle: "用一個滑桿控制所有顯示器",
        combinedCaption: "新增一個同時調整所有顯示器的滑桿，並保留它們之間的差異。",
        syncToggle: "外接顯示器跟隨內建螢幕",
        syncCaption: "當內建螢幕的亮度手動或隨環境光改變時，外接顯示器隨之改變。",
        turnOnHDR: "開啟 HDR",
        turnOffHDR: "關閉 HDR"
    )

    static let zhHK = BrightnessFeatureStrings(
        pageTitle: "顯示器",
        hubDescription: "控制所有顯示器的亮度和開關",
        enable: "控制顯示器",
        enableCaption: "內置螢幕和外接顯示器的亮度與開關控制，顯示在這裏和選單列面板中。",
        externalCaption: "外接顯示器透過與其本身按鍵相同的協定調整。當連接無法傳輸該協定時（例如 HDMI 轉接器），滑桿會改為調暗畫面，因此亮度調整始終可用。",
        noDisplays: "找不到顯示器。",
        displayOff: "已關閉",
        turnOffDisplay: "關閉顯示器",
        turnOnDisplay: "開啟顯示器",
        lastDisplayCaption: "至少要保留一台顯示器開啟。",
        switchUnavailable: "此 Mac 不支援顯示器開關。",
        switchFailed: "無法更改這部顯示器。",
        keysToggle: "亮度鍵跟隨指標",
        keysCaption: "鍵盤上的亮度鍵調整指標所在的顯示器。",
        osdToggle: "調整亮度時顯示",
        osdCaption: "使用亮度鍵或滑桿時顯示亮度百分比。",
        keyboardLight: "鍵盤背光",
        keyboardLightCaption: "開啟或關閉鍵盤背光。",
        volumeToggle: "顯示器揚聲器",
        volumeCaption: "內置揚聲器的顯示器會在這裏出現音量滑桿，透過與其按鍵相同的通道調整。沒有揚聲器的顯示器不會顯示滑桿。",
        volumeLabel: "音量",
        mute: "靜音",
        unmute: "取消靜音",
        volumeKeysToggle: "音量鍵控制顯示器揚聲器",
        volumeKeysCaption: "當聲音從顯示器傳出時，鍵盤上的音量鍵會調整該顯示器，而不是 macOS 無法改變的音量。",
        allDisplays: "所有顯示器",
        combinedToggle: "用一個滑桿控制所有顯示器",
        combinedCaption: "新增一個同時調整所有顯示器的滑桿，並保留它們之間的差異。",
        syncToggle: "外接顯示器跟隨內置螢幕",
        syncCaption: "當內置螢幕的亮度手動或隨環境光改變時，外接顯示器隨之改變。",
        turnOnHDR: "開啟 HDR",
        turnOffHDR: "關閉 HDR"
    )
}
