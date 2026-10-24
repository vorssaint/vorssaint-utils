// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for keeping the Dock on one display. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct DockDisplayLockStrings {
    let title: String
    let hubDescription: String
    let enableCaption: String
    let displayPicker: String
    let mainDisplay: String
    let builtInDisplay: String
    let disconnectedDisplay: String
    let fallbackNote: String
    let dockLocationFormat: String
    let moveButton: String
    let returnsToggle: String
    let returnsCaption: String
    let singleDisplay: String
    let spacesOff: String
}

extension FeatureStrings {
    static func dockDisplayLock(_ language: AppLanguage) -> DockDisplayLockStrings {
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

extension DockDisplayLockStrings {
    static let enUS = DockDisplayLockStrings(
        title: "Keep the Dock on one display",
        hubDescription: "Stops the Dock from moving to another display when the pointer presses on that display’s edge.",
        enableCaption: "The pointer still goes everywhere. Only the press against another display’s Dock edge, which macOS reads as a request to move the Dock, is held back, for drags as well as moves.",
        displayPicker: "Display",
        mainDisplay: "Main display",
        builtInDisplay: "Built-in display",
        disconnectedDisplay: "Chosen display (not connected)",
        fallbackNote: "While the chosen display is not connected, the Dock stays on the main display.",
        dockLocationFormat: "The Dock is on %@.",
        moveButton: "Move the Dock there",
        returnsToggle: "Bring the Dock back after sleep and display changes",
        returnsCaption: "macOS puts the Dock on the main display after sleep. With this on, the pointer briefly presses on the chosen display’s Dock edge to call it back, only while the Mac is unlocked.",
        singleDisplay: "Only one display is connected, so the Dock has nowhere else to go.",
        spacesOff: "\u{201C}Displays have separate Spaces\u{201D} is off, so macOS does not move the Dock between displays on its own."
    )

    static let ptBR = DockDisplayLockStrings(
        title: "Manter o Dock em uma tela",
        hubDescription: "Impede que o Dock vá para outra tela quando o ponteiro pressiona a borda dessa tela.",
        enableCaption: "O ponteiro continua indo a qualquer lugar. Só a pressão contra a borda do Dock de outra tela, que o macOS entende como pedido para mover o Dock, é retida, tanto ao arrastar quanto ao mover.",
        displayPicker: "Tela",
        mainDisplay: "Tela principal",
        builtInDisplay: "Tela integrada",
        disconnectedDisplay: "Tela escolhida (não conectada)",
        fallbackNote: "Enquanto a tela escolhida não estiver conectada, o Dock fica na tela principal.",
        dockLocationFormat: "O Dock está em %@.",
        moveButton: "Mover o Dock para lá",
        returnsToggle: "Trazer o Dock de volta após repouso e mudanças de tela",
        returnsCaption: "O macOS coloca o Dock na tela principal após o repouso. Com isto ligado, o ponteiro pressiona por um instante a borda do Dock da tela escolhida para trazê-lo de volta, só com o Mac desbloqueado.",
        singleDisplay: "Só uma tela está conectada, então o Dock não tem para onde ir.",
        spacesOff: "\u{201C}As telas têm Espaços separados\u{201D} está desligado, então o macOS não move o Dock entre telas por conta própria."
    )

    static let tr = DockDisplayLockStrings(
        title: "Dock’u tek ekranda tut",
        hubDescription: "İşaretçi başka bir ekranın kenarına bastırdığında Dock’un o ekrana geçmesini engeller.",
        enableCaption: "İşaretçi her yere gitmeye devam eder. Yalnızca macOS’in Dock’u taşıma isteği olarak okuduğu, başka bir ekranın Dock kenarına bastırma engellenir; sürüklerken de taşırken de.",
        displayPicker: "Ekran",
        mainDisplay: "Ana ekran",
        builtInDisplay: "Dahili ekran",
        disconnectedDisplay: "Seçilen ekran (bağlı değil)",
        fallbackNote: "Seçilen ekran bağlı değilken Dock ana ekranda kalır.",
        dockLocationFormat: "Dock şu ekranda: %@.",
        moveButton: "Dock’u oraya taşı",
        returnsToggle: "Uyku ve ekran değişikliklerinden sonra Dock’u geri getir",
        returnsCaption: "macOS uykudan sonra Dock’u ana ekrana koyar. Bu açıkken işaretçi, Dock’u geri çağırmak için seçilen ekranın Dock kenarına kısa bir an bastırır; yalnızca Mac’in kilidi açıkken.",
        singleDisplay: "Yalnızca bir ekran bağlı, bu yüzden Dock’un gidebileceği başka bir yer yok.",
        spacesOff: "\u{201C}Ekranların ayrı Spaces alanları var\u{201D} kapalı, bu yüzden macOS Dock’u ekranlar arasında kendiliğinden taşımaz."
    )

    static let ru = DockDisplayLockStrings(
        title: "Держать Dock на одном дисплее",
        hubDescription: "Не даёт Dock переехать на другой дисплей, когда указатель упирается в его край.",
        enableCaption: "Указатель по-прежнему ходит куда угодно. Сдерживается только упор в край Dock на другом дисплее, который macOS считает просьбой перенести Dock, и при перетаскивании, и при обычном движении.",
        displayPicker: "Дисплей",
        mainDisplay: "Основной дисплей",
        builtInDisplay: "Встроенный дисплей",
        disconnectedDisplay: "Выбранный дисплей (не подключён)",
        fallbackNote: "Пока выбранный дисплей не подключён, Dock остаётся на основном дисплее.",
        dockLocationFormat: "Dock сейчас на дисплее %@.",
        moveButton: "Перенести Dock туда",
        returnsToggle: "Возвращать Dock после сна и смены дисплеев",
        returnsCaption: "После сна macOS ставит Dock на основной дисплей. Когда это включено, указатель на мгновение упирается в край Dock на выбранном дисплее, чтобы вернуть его, и только когда Mac разблокирован.",
        singleDisplay: "Подключён только один дисплей, так что Dock некуда переезжать.",
        spacesOff: "Параметр «Мониторы с отдельными пространствами Spaces» выключен, поэтому macOS сам не переносит Dock между дисплеями."
    )

    static let es = DockDisplayLockStrings(
        title: "Mantener el Dock en una pantalla",
        hubDescription: "Evita que el Dock pase a otra pantalla cuando el puntero presiona el borde de esa pantalla.",
        enableCaption: "El puntero sigue llegando a todas partes. Solo se retiene la presión contra el borde del Dock de otra pantalla, que macOS entiende como una petición para mover el Dock, al arrastrar y al mover.",
        displayPicker: "Pantalla",
        mainDisplay: "Pantalla principal",
        builtInDisplay: "Pantalla integrada",
        disconnectedDisplay: "Pantalla elegida (no conectada)",
        fallbackNote: "Mientras la pantalla elegida no esté conectada, el Dock se queda en la pantalla principal.",
        dockLocationFormat: "El Dock está en %@.",
        moveButton: "Mover el Dock allí",
        returnsToggle: "Devolver el Dock tras el reposo y los cambios de pantalla",
        returnsCaption: "macOS pone el Dock en la pantalla principal tras el reposo. Con esto activado, el puntero presiona un instante el borde del Dock de la pantalla elegida para traerlo de vuelta, solo con el Mac desbloqueado.",
        singleDisplay: "Solo hay una pantalla conectada, así que el Dock no tiene adónde ir.",
        spacesOff: "\u{201C}Las pantallas tienen espacios independientes\u{201D} está desactivado, así que macOS no mueve el Dock entre pantallas por su cuenta."
    )

    static let sk = DockDisplayLockStrings(
        title: "Držať Dock na jednom displeji",
        hubDescription: "Zabráni, aby sa Dock presunul na iný displej, keď ukazovateľ zatlačí na jeho okraj.",
        enableCaption: "Ukazovateľ sa naďalej dostane všade. Zadrží sa iba zatlačenie na okraj Docku iného displeja, ktoré macOS chápe ako žiadosť o presun Docku, pri ťahaní aj pri pohybe.",
        displayPicker: "Displej",
        mainDisplay: "Hlavný displej",
        builtInDisplay: "Vstavaný displej",
        disconnectedDisplay: "Vybraný displej (nepripojený)",
        fallbackNote: "Kým vybraný displej nie je pripojený, Dock zostane na hlavnom displeji.",
        dockLocationFormat: "Dock je na displeji %@.",
        moveButton: "Presunúť Dock tam",
        returnsToggle: "Vrátiť Dock po spánku a zmene displejov",
        returnsCaption: "Po spánku macOS presunie Dock na hlavný displej. Keď je toto zapnuté, ukazovateľ na okamih zatlačí na okraj Docku vybraného displeja, aby ho vrátil, iba keď je Mac odomknutý.",
        singleDisplay: "Pripojený je iba jeden displej, takže Dock sa nemá kam presunúť.",
        spacesOff: "Voľba \u{201E}Displeje majú samostatné plochy Spaces\u{201C} je vypnutá, takže macOS Dock medzi displejmi sám nepresúva."
    )

    static let de = DockDisplayLockStrings(
        title: "Dock auf einem Display halten",
        hubDescription: "Verhindert, dass das Dock auf ein anderes Display wechselt, wenn der Zeiger gegen dessen Rand drückt.",
        enableCaption: "Der Zeiger kommt weiterhin überallhin. Nur das Drücken gegen den Dock-Rand eines anderen Displays, das macOS als Wunsch liest, das Dock zu verschieben, wird zurückgehalten, beim Ziehen wie beim Bewegen.",
        displayPicker: "Display",
        mainDisplay: "Hauptdisplay",
        builtInDisplay: "Integriertes Display",
        disconnectedDisplay: "Gewähltes Display (nicht verbunden)",
        fallbackNote: "Solange das gewählte Display nicht verbunden ist, bleibt das Dock auf dem Hauptdisplay.",
        dockLocationFormat: "Das Dock ist auf %@.",
        moveButton: "Dock dorthin bewegen",
        returnsToggle: "Dock nach dem Ruhezustand und Display-Änderungen zurückholen",
        returnsCaption: "Nach dem Ruhezustand setzt macOS das Dock auf das Hauptdisplay. Ist dies an, drückt der Zeiger kurz gegen den Dock-Rand des gewählten Displays, um es zurückzuholen, nur während der Mac entsperrt ist.",
        singleDisplay: "Es ist nur ein Display verbunden, das Dock kann also nirgendwo anders hin.",
        spacesOff: "\u{201E}Monitore verwenden verschiedene Spaces\u{201C} ist aus, daher verschiebt macOS das Dock nicht von selbst zwischen Displays."
    )

    static let fr = DockDisplayLockStrings(
        title: "Garder le Dock sur un écran",
        hubDescription: "Empêche le Dock de passer sur un autre écran quand le pointeur appuie sur le bord de cet écran.",
        enableCaption: "Le pointeur va toujours partout. Seule la pression contre le bord du Dock d’un autre écran, que macOS interprète comme une demande de déplacer le Dock, est retenue, en glissant comme en déplaçant.",
        displayPicker: "Écran",
        mainDisplay: "Écran principal",
        builtInDisplay: "Écran intégré",
        disconnectedDisplay: "Écran choisi (non connecté)",
        fallbackNote: "Tant que l’écran choisi n’est pas connecté, le Dock reste sur l’écran principal.",
        dockLocationFormat: "Le Dock est sur %@.",
        moveButton: "Y déplacer le Dock",
        returnsToggle: "Ramener le Dock après la suspension et les changements d’écran",
        returnsCaption: "Après la suspension, macOS place le Dock sur l’écran principal. Avec cette option, le pointeur appuie un instant sur le bord du Dock de l’écran choisi pour le rappeler, seulement quand le Mac est déverrouillé.",
        singleDisplay: "Un seul écran est connecté, le Dock n’a donc nulle part où aller.",
        spacesOff: "«\u{00A0}Les écrans disposent d’espaces distincts\u{00A0}» est désactivé, donc macOS ne déplace pas le Dock d’un écran à l’autre de lui-même."
    )

    static let it = DockDisplayLockStrings(
        title: "Tieni il Dock su un solo schermo",
        hubDescription: "Impedisce al Dock di passare a un altro schermo quando il puntatore preme sul bordo di quello schermo.",
        enableCaption: "Il puntatore continua ad arrivare ovunque. Viene trattenuta solo la pressione contro il bordo del Dock di un altro schermo, che macOS legge come richiesta di spostare il Dock, sia trascinando sia muovendo.",
        displayPicker: "Schermo",
        mainDisplay: "Schermo principale",
        builtInDisplay: "Schermo integrato",
        disconnectedDisplay: "Schermo scelto (non collegato)",
        fallbackNote: "Finché lo schermo scelto non è collegato, il Dock resta sullo schermo principale.",
        dockLocationFormat: "Il Dock è su %@.",
        moveButton: "Sposta lì il Dock",
        returnsToggle: "Riporta il Dock dopo lo stop e i cambi di schermo",
        returnsCaption: "Dopo lo stop macOS mette il Dock sullo schermo principale. Con questa opzione il puntatore preme per un istante sul bordo del Dock dello schermo scelto per richiamarlo, solo con il Mac sbloccato.",
        singleDisplay: "È collegato un solo schermo, quindi il Dock non ha altro posto dove andare.",
        spacesOff: "\u{201C}Gli schermi hanno spazi separati\u{201D} è disattivato, quindi macOS non sposta da solo il Dock tra gli schermi."
    )

    static let ja = DockDisplayLockStrings(
        title: "Dock を 1 台のディスプレイに固定",
        hubDescription: "ポインタがほかのディスプレイの端を押しても、Dock がそのディスプレイに移らないようにします。",
        enableCaption: "ポインタはこれまでどおりどこへでも動かせます。macOS が Dock を移す合図と受け取る、ほかのディスプレイの Dock の端への押し込みだけを、移動中もドラッグ中も止めます。",
        displayPicker: "ディスプレイ",
        mainDisplay: "メインディスプレイ",
        builtInDisplay: "内蔵ディスプレイ",
        disconnectedDisplay: "選択したディスプレイ（未接続）",
        fallbackNote: "選択したディスプレイが接続されていない間、Dock はメインディスプレイにとどまります。",
        dockLocationFormat: "Dock は %@ にあります。",
        moveButton: "Dock をそこへ移動",
        returnsToggle: "スリープやディスプレイの変更後に Dock を戻す",
        returnsCaption: "スリープ後、macOS は Dock をメインディスプレイに置きます。オンにすると、Mac のロックが解除されているときだけ、ポインタが選択したディスプレイの Dock の端を一瞬押して Dock を呼び戻します。",
        singleDisplay: "接続されているディスプレイは 1 台だけなので、Dock の移動先はありません。",
        spacesOff: "「ディスプレイごとに個別の操作スペース」がオフなので、macOS が Dock をディスプレイ間で自動的に移すことはありません。"
    )

    static let ko = DockDisplayLockStrings(
        title: "Dock을 한 디스플레이에 고정",
        hubDescription: "포인터가 다른 디스플레이의 가장자리를 밀어도 Dock이 그 디스플레이로 옮겨 가지 않게 합니다.",
        enableCaption: "포인터는 여전히 어디로든 갈 수 있습니다. macOS가 Dock 이동 요청으로 읽는, 다른 디스플레이의 Dock 가장자리를 미는 동작만 이동할 때와 드래그할 때 모두 막습니다.",
        displayPicker: "디스플레이",
        mainDisplay: "주 디스플레이",
        builtInDisplay: "내장 디스플레이",
        disconnectedDisplay: "선택한 디스플레이(연결되지 않음)",
        fallbackNote: "선택한 디스플레이가 연결되지 않은 동안에는 Dock이 주 디스플레이에 머뭅니다.",
        dockLocationFormat: "Dock이 %@에 있습니다.",
        moveButton: "Dock을 그곳으로 이동",
        returnsToggle: "잠자기 및 디스플레이 변경 후 Dock 되돌리기",
        returnsCaption: "잠자기 후 macOS는 Dock을 주 디스플레이에 둡니다. 이 옵션을 켜면 Mac 잠금이 해제된 동안에만 포인터가 선택한 디스플레이의 Dock 가장자리를 잠깐 밀어 Dock을 다시 불러옵니다.",
        singleDisplay: "연결된 디스플레이가 하나뿐이라 Dock이 옮겨 갈 곳이 없습니다.",
        spacesOff: "‘디스플레이마다 개별 Spaces 사용’이 꺼져 있어 macOS가 Dock을 디스플레이 사이에서 스스로 옮기지 않습니다."
    )

    static let zhHans = DockDisplayLockStrings(
        title: "将程序坞保留在一个显示器上",
        hubDescription: "指针抵住其他显示器的边缘时，阻止程序坞移到那个显示器。",
        enableCaption: "指针仍可去任何地方。只有抵住其他显示器程序坞边缘的动作会被拦下，macOS 会把这个动作当作移动程序坞的请求；移动和拖移时都一样。",
        displayPicker: "显示器",
        mainDisplay: "主显示器",
        builtInDisplay: "内建显示器",
        disconnectedDisplay: "所选显示器（未连接）",
        fallbackNote: "所选显示器未连接期间，程序坞会留在主显示器上。",
        dockLocationFormat: "程序坞位于 %@。",
        moveButton: "将程序坞移到那里",
        returnsToggle: "睡眠和显示器变化后将程序坞移回",
        returnsCaption: "睡眠后 macOS 会把程序坞放到主显示器上。打开此项后，仅在 Mac 已解锁时，指针会短暂抵住所选显示器的程序坞边缘，把程序坞叫回来。",
        singleDisplay: "只连接了一个显示器，程序坞没有其他地方可去。",
        spacesOff: "“显示器具有单独的空间”已关闭，因此 macOS 不会自行在显示器之间移动程序坞。"
    )

    static let zhTW = DockDisplayLockStrings(
        title: "將 Dock 保留在一個顯示器上",
        hubDescription: "指標抵住其他顯示器的邊緣時，避免 Dock 移到那個顯示器。",
        enableCaption: "指標仍可移到任何地方。只有抵住其他顯示器 Dock 邊緣的動作會被攔下，macOS 會把這個動作當作移動 Dock 的要求；移動和拖移時都一樣。",
        displayPicker: "顯示器",
        mainDisplay: "主顯示器",
        builtInDisplay: "內建顯示器",
        disconnectedDisplay: "所選顯示器（未連接）",
        fallbackNote: "所選顯示器未連接期間，Dock 會留在主顯示器上。",
        dockLocationFormat: "Dock 位於 %@。",
        moveButton: "將 Dock 移到那裡",
        returnsToggle: "睡眠和顯示器變更後將 Dock 移回",
        returnsCaption: "睡眠後 macOS 會把 Dock 放到主顯示器上。開啟此項後，僅在 Mac 已解鎖時，指標會短暫抵住所選顯示器的 Dock 邊緣，把 Dock 叫回來。",
        singleDisplay: "只連接了一個顯示器，Dock 沒有其他地方可去。",
        spacesOff: "「顯示器有個別的空間」已關閉，因此 macOS 不會自行在顯示器之間移動 Dock。"
    )

    static let zhHK = DockDisplayLockStrings(
        title: "將 Dock 留喺一個顯示器",
        hubDescription: "指標頂住其他顯示器嘅邊緣時，唔俾 Dock 移去嗰個顯示器。",
        enableCaption: "指標仍然可以去任何地方。只有頂住其他顯示器 Dock 邊緣嘅動作會被攔低，macOS 會當呢個動作係要求移動 Dock；移動同拖移時都一樣。",
        displayPicker: "顯示器",
        mainDisplay: "主顯示器",
        builtInDisplay: "內置顯示器",
        disconnectedDisplay: "所揀顯示器（未連接）",
        fallbackNote: "所揀嘅顯示器未連接期間，Dock 會留喺主顯示器。",
        dockLocationFormat: "Dock 喺 %@。",
        moveButton: "將 Dock 移去嗰度",
        returnsToggle: "睡眠同顯示器變動之後將 Dock 移返",
        returnsCaption: "睡眠之後 macOS 會將 Dock 放喺主顯示器。開咗呢項之後，只會喺 Mac 已解鎖時，指標會短暫頂住所揀顯示器嘅 Dock 邊緣，將 Dock 叫返嚟。",
        singleDisplay: "只連接咗一個顯示器，Dock 冇其他地方可以去。",
        spacesOff: "「顯示器有個別的空間」已經關閉，所以 macOS 唔會自己喺顯示器之間移動 Dock。"
    )

    static let uk = DockDisplayLockStrings(
        title: "Тримати Dock на одному дисплеї",
        hubDescription: "Не дає Dock переїхати на інший дисплей, коли вказівник упирається в його край.",
        enableCaption: "Вказівник, як і раніше, рухається куди завгодно. Стримується лише упор у край Dock на іншому дисплеї, який macOS вважає проханням перенести Dock, і під час перетягування, і під час звичайного руху.",
        displayPicker: "Дисплей",
        mainDisplay: "Основний дисплей",
        builtInDisplay: "Вбудований дисплей",
        disconnectedDisplay: "Вибраний дисплей (не під’єднано)",
        fallbackNote: "Поки вибраний дисплей не під’єднано, Dock залишається на основному дисплеї.",
        dockLocationFormat: "Dock зараз на дисплеї %@.",
        moveButton: "Перенести Dock туди",
        returnsToggle: "Повертати Dock після сну та зміни дисплеїв",
        returnsCaption: "Після сну macOS ставить Dock на основний дисплей. Коли це ввімкнено, вказівник на мить упирається в край Dock на вибраному дисплеї, щоб повернути його, і лише коли Mac розблоковано.",
        singleDisplay: "Під’єднано лише один дисплей, тож Dock нікуди переїжджати.",
        spacesOff: "Параметр «Монітори з окремими просторами Spaces» вимкнено, тому macOS сам не переносить Dock між дисплеями."
    )
}
