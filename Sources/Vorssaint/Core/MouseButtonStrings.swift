// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseButtonFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enableLabel: String
    let enableCaption: String
    let addButton: String
    let captureWaiting: String
    let captureCancel: String
    let captureBlind: String
    let captureUnsupported: String
    let captureWheel: String
    let captureExists: String
    let captureHint: String
    let backButtonName: String
    let forwardButtonName: String
    let otherButtonFormat: String      // "Button %d"
    let setShortcutButton: String
    let removeButton: String
    let emptyCaption: String
    let rowWheelNote: String
    let manageButton: String
    let panelCaption: String
    let sideWheelLeftName: String
    let sideWheelRightName: String
}

extension FeatureStrings {
    static func mouseButtons(_ language: AppLanguage) -> MouseButtonFeatureStrings {
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

extension MouseButtonFeatureStrings {
    static let enUS = MouseButtonFeatureStrings(
        pageTitle: "Mouse button shortcuts",
        hubDescription: "Extra buttons and side-wheel directions press a key combination you choose.",
        enableLabel: "Use extra buttons as shortcuts",
        enableCaption: "Each extra button or side-wheel direction can press a key combination for you. While it has a shortcut, it stops doing what it did before.",
        addButton: "Add a button or side wheel",
        captureWaiting: "Now press an extra button or move the side wheel.",
        captureCancel: "Cancel",
        captureBlind: "Vorssaint cannot watch the mouse right now.",
        captureUnsupported: "That input cannot take a shortcut. Use an extra button or a side-wheel direction.",
        captureWheel: "That button already opens the radial menu. Pick another one, or free it there first.",
        captureExists: "That button or direction is already on the list below.",
        captureHint: "If nothing happens, your mouse's own software may already be using that control.",
        backButtonName: "Back side button",
        forwardButtonName: "Forward side button",
        otherButtonFormat: "Button %d",
        setShortcutButton: "Set shortcut",
        removeButton: "Remove",
        emptyCaption: "No shortcuts yet. Add a button or side-wheel direction.",
        rowWheelNote: "This button opens the radial menu now, so the shortcut waits.",
        manageButton: "Set up…",
        panelCaption: "Extra buttons and side-wheel directions press key combinations you choose.",
        sideWheelLeftName: "Side wheel left",
        sideWheelRightName: "Side wheel right"
    )

    static let ptBR = MouseButtonFeatureStrings(
        pageTitle: "Atalhos nos botões do mouse",
        hubDescription: "Botões extras e os sentidos da roda lateral apertam uma combinação de teclas que você escolher.",
        enableLabel: "Usar botões extras como atalhos",
        enableCaption: "Cada botão extra ou sentido da roda lateral pode apertar uma combinação de teclas por você. Enquanto tem um atalho, deixa de fazer o que fazia antes.",
        addButton: "Adicionar botão ou roda lateral",
        captureWaiting: "Agora aperte um botão extra ou mova a roda lateral.",
        captureCancel: "Cancelar",
        captureBlind: "O Vorssaint não consegue observar o mouse agora.",
        captureUnsupported: "Esse controle não pode receber atalho. Use um botão extra ou um sentido da roda lateral.",
        captureWheel: "Esse botão já abre o menu radial. Escolha outro, ou libere ele lá primeiro.",
        captureExists: "Esse botão ou sentido já está na lista abaixo.",
        captureHint: "Se nada acontecer, o software do próprio mouse pode já estar usando esse controle.",
        backButtonName: "Botão lateral de voltar",
        forwardButtonName: "Botão lateral de avançar",
        otherButtonFormat: "Botão %d",
        setShortcutButton: "Definir atalho",
        removeButton: "Remover",
        emptyCaption: "Nenhum atalho ainda. Adicione um botão ou sentido da roda lateral.",
        rowWheelNote: "Esse botão abre o menu radial agora, então o atalho fica esperando.",
        manageButton: "Configurar…",
        panelCaption: "Botões extras e os sentidos da roda lateral apertam combinações de teclas que você escolher.",
        sideWheelLeftName: "Roda lateral para a esquerda",
        sideWheelRightName: "Roda lateral para a direita"
    )

    static let tr = MouseButtonFeatureStrings(
        pageTitle: "Fare düğmesi kısayolları",
        hubDescription: "Ekstra fare düğmeleri ve yan teker yönleri seçtiğiniz bir tuş birleşimine basar.",
        enableLabel: "Ekstra düğmeleri kısayol olarak kullan",
        enableCaption: "Her ekstra düğme veya yan teker yönü sizin yerinize bir tuş birleşimine basabilir. Kısayolu varken önceki işlevini yapmayı bırakır.",
        addButton: "Düğme veya yan teker ekle",
        captureWaiting: "Şimdi ek bir düğmeye basın veya yan tekeri hareket ettirin.",
        captureCancel: "Vazgeç",
        captureBlind: "Vorssaint şu anda fareyi izleyemiyor.",
        captureUnsupported: "Bu girişe kısayol verilemez. Ek bir düğme veya yan teker yönü kullanın.",
        captureWheel: "Bu düğme zaten dairesel menüyü açıyor. Başka bir düğme seçin veya önce orada serbest bırakın.",
        captureExists: "Bu düğme veya yön zaten aşağıdaki listede.",
        captureHint: "Hiçbir şey olmuyorsa farenin kendi yazılımı bu denetimi kullanıyor olabilir.",
        backButtonName: "Geri yan düğmesi",
        forwardButtonName: "İleri yan düğmesi",
        otherButtonFormat: "Düğme %d",
        setShortcutButton: "Kısayol belirle",
        removeButton: "Kaldır",
        emptyCaption: "Henüz kısayol yok. Bir düğme veya yan teker yönü ekleyin.",
        rowWheelNote: "Bu düğme şu anda dairesel menüyü açıyor, kısayol bekliyor.",
        manageButton: "Ayarla…",
        panelCaption: "Ekstra düğmeler ve yan teker yönleri seçtiğiniz tuş birleşimlerine basar.",
        sideWheelLeftName: "Yan teker sola",
        sideWheelRightName: "Yan teker sağa"
    )

    static let ru = MouseButtonFeatureStrings(
        pageTitle: "Сочетания на кнопках мыши",
        hubDescription: "Дополнительные кнопки и направления бокового колёсика нажимают выбранное вами сочетание клавиш.",
        enableLabel: "Использовать дополнительные кнопки как сочетания",
        enableCaption: "Каждая дополнительная кнопка или направление бокового колёсика может нажимать сочетание клавиш за вас. Пока у него есть сочетание, прежнее действие не выполняется.",
        addButton: "Добавить кнопку или боковое колёсико",
        captureWaiting: "Теперь нажмите дополнительную кнопку или прокрутите боковое колёсико.",
        captureCancel: "Отменить",
        captureBlind: "Vorssaint сейчас не может отслеживать мышь.",
        captureUnsupported: "Этому элементу нельзя назначить сочетание. Используйте дополнительную кнопку или направление бокового колёсика.",
        captureWheel: "Эта кнопка уже открывает радиальное меню. Выберите другую или сначала освободите её там.",
        captureExists: "Эта кнопка или направление уже есть в списке ниже.",
        captureHint: "Если ничего не происходит, этот элемент уже может использоваться программой мыши.",
        backButtonName: "Боковая кнопка «Назад»",
        forwardButtonName: "Боковая кнопка «Вперёд»",
        otherButtonFormat: "Кнопка %d",
        setShortcutButton: "Задать сочетание",
        removeButton: "Удалить",
        emptyCaption: "Сочетаний пока нет. Добавьте кнопку или направление бокового колёсика.",
        rowWheelNote: "Эта кнопка сейчас открывает радиальное меню, поэтому сочетание ждёт.",
        manageButton: "Настроить…",
        panelCaption: "Дополнительные кнопки и направления бокового колёсика нажимают выбранные вами сочетания клавиш.",
        sideWheelLeftName: "Боковое колёсико влево",
        sideWheelRightName: "Боковое колёсико вправо"
    )

    static let es = MouseButtonFeatureStrings(
        pageTitle: "Atajos en los botones del ratón",
        hubDescription: "Los botones extra y las direcciones de la rueda lateral pulsan una combinación de teclas que tú eliges.",
        enableLabel: "Usar botones extra como atajos",
        enableCaption: "Cada botón extra o dirección de la rueda lateral puede pulsar una combinación de teclas por ti. Mientras tiene un atajo, deja de hacer lo que hacía antes.",
        addButton: "Añadir botón o rueda lateral",
        captureWaiting: "Ahora pulsa un botón extra o mueve la rueda lateral.",
        captureCancel: "Cancelar",
        captureBlind: "Vorssaint no puede observar el ratón ahora mismo.",
        captureUnsupported: "Esa entrada no puede recibir un atajo. Usa un botón extra o una dirección de la rueda lateral.",
        captureWheel: "Ese botón ya abre el menú radial. Elige otro, o libéralo allí primero.",
        captureExists: "Ese botón o dirección ya está en la lista de abajo.",
        captureHint: "Si no pasa nada, puede que el software del propio ratón ya use ese control.",
        backButtonName: "Botón lateral de retroceso",
        forwardButtonName: "Botón lateral de avance",
        otherButtonFormat: "Botón %d",
        setShortcutButton: "Definir atajo",
        removeButton: "Eliminar",
        emptyCaption: "Aún no hay atajos. Añade un botón o una dirección de la rueda lateral.",
        rowWheelNote: "Ese botón abre el menú radial ahora, así que el atajo queda en espera.",
        manageButton: "Configurar…",
        panelCaption: "Los botones extra y las direcciones de la rueda lateral pulsan combinaciones de teclas que tú eliges.",
        sideWheelLeftName: "Rueda lateral a la izquierda",
        sideWheelRightName: "Rueda lateral a la derecha"
    )

    static let de = MouseButtonFeatureStrings(
        pageTitle: "Kurzbefehle auf Maustasten",
        hubDescription: "Zusätzliche Maustasten und Richtungen des seitlichen Rads drücken einen Tastaturkurzbefehl deiner Wahl.",
        enableLabel: "Zusatztasten als Kurzbefehle verwenden",
        enableCaption: "Jede zusätzliche Maustaste oder Richtung des seitlichen Rads kann einen Tastaturkurzbefehl für dich drücken. Solange sie einen Kurzbefehl hat, gilt ihre bisherige Funktion nicht.",
        addButton: "Taste oder seitliches Rad hinzufügen",
        captureWaiting: "Drücke jetzt eine Zusatztaste oder bewege das seitliche Rad.",
        captureCancel: "Abbrechen",
        captureBlind: "Vorssaint kann die Maus gerade nicht beobachten.",
        captureUnsupported: "Diese Eingabe kann keinen Kurzbefehl bekommen. Verwende eine Zusatztaste oder eine Richtung des seitlichen Rads.",
        captureWheel: "Diese Taste öffnet bereits das Radialmenü. Wähle eine andere oder gib sie dort zuerst frei.",
        captureExists: "Diese Taste oder Richtung steht schon in der Liste unten.",
        captureHint: "Wenn nichts passiert, verwendet vielleicht die Software der Maus diese Steuerung bereits.",
        backButtonName: "Seitliche Zurück-Taste",
        forwardButtonName: "Seitliche Vorwärts-Taste",
        otherButtonFormat: "Taste %d",
        setShortcutButton: "Kurzbefehl festlegen",
        removeButton: "Entfernen",
        emptyCaption: "Noch keine Kurzbefehle. Füge eine Taste oder Richtung des seitlichen Rads hinzu.",
        rowWheelNote: "Diese Taste öffnet gerade das Radialmenü, der Kurzbefehl wartet daher.",
        manageButton: "Einrichten…",
        panelCaption: "Zusätzliche Maustasten und Richtungen des seitlichen Rads drücken Tastaturkurzbefehle deiner Wahl.",
        sideWheelLeftName: "Seitliches Rad nach links",
        sideWheelRightName: "Seitliches Rad nach rechts"
    )

    static let fr = MouseButtonFeatureStrings(
        pageTitle: "Raccourcis sur les boutons de la souris",
        hubDescription: "Les boutons supplémentaires et les directions de la molette latérale appuient sur une combinaison de touches de votre choix.",
        enableLabel: "Utiliser les boutons supplémentaires comme raccourcis",
        enableCaption: "Chaque bouton supplémentaire ou direction de la molette latérale peut appuyer sur une combinaison de touches pour vous. Tant qu'un raccourci lui est attribué, son ancienne action est suspendue.",
        addButton: "Ajouter un bouton ou la molette latérale",
        captureWaiting: "Appuyez sur un bouton supplémentaire ou tournez la molette latérale.",
        captureCancel: "Annuler",
        captureBlind: "Vorssaint ne peut pas observer la souris pour le moment.",
        captureUnsupported: "Cette commande ne peut pas recevoir de raccourci. Utilisez un bouton supplémentaire ou une direction de la molette latérale.",
        captureWheel: "Ce bouton ouvre déjà le menu radial. Choisissez-en un autre, ou libérez-le là-bas d'abord.",
        captureExists: "Ce bouton ou cette direction est déjà dans la liste ci-dessous.",
        captureHint: "Si rien ne se passe, le logiciel de la souris utilise peut-être déjà cette commande.",
        backButtonName: "Bouton latéral précédent",
        forwardButtonName: "Bouton latéral suivant",
        otherButtonFormat: "Bouton %d",
        setShortcutButton: "Définir le raccourci",
        removeButton: "Supprimer",
        emptyCaption: "Aucun raccourci pour l'instant. Ajoutez un bouton ou une direction de la molette latérale.",
        rowWheelNote: "Ce bouton ouvre le menu radial en ce moment, le raccourci attend donc.",
        manageButton: "Configurer…",
        panelCaption: "Les boutons supplémentaires et les directions de la molette latérale appuient sur des combinaisons de touches de votre choix.",
        sideWheelLeftName: "Molette latérale vers la gauche",
        sideWheelRightName: "Molette latérale vers la droite"
    )

    static let it = MouseButtonFeatureStrings(
        pageTitle: "Abbreviazioni sui pulsanti del mouse",
        hubDescription: "I pulsanti extra e le direzioni della rotella laterale premono una combinazione di tasti a tua scelta.",
        enableLabel: "Usa i pulsanti extra come abbreviazioni",
        enableCaption: "Ogni pulsante extra o direzione della rotella laterale può premere una combinazione di tasti per te. Finché ha un'abbreviazione, la sua azione precedente resta sospesa.",
        addButton: "Aggiungi pulsante o rotella laterale",
        captureWaiting: "Ora premi un pulsante extra o muovi la rotella laterale.",
        captureCancel: "Annulla",
        captureBlind: "Vorssaint al momento non riesce a osservare il mouse.",
        captureUnsupported: "Questo comando non può ricevere un'abbreviazione. Usa un pulsante extra o una direzione della rotella laterale.",
        captureWheel: "Quel pulsante apre già il menu radiale. Scegline un altro, oppure liberalo prima lì.",
        captureExists: "Quel pulsante o quella direzione è già nell'elenco qui sotto.",
        captureHint: "Se non succede nulla, il software del mouse potrebbe già usare quel comando.",
        backButtonName: "Pulsante laterale indietro",
        forwardButtonName: "Pulsante laterale avanti",
        otherButtonFormat: "Pulsante %d",
        setShortcutButton: "Imposta abbreviazione",
        removeButton: "Rimuovi",
        emptyCaption: "Ancora nessuna abbreviazione. Aggiungi un pulsante o una direzione della rotella laterale.",
        rowWheelNote: "Questo pulsante ora apre il menu radiale, quindi l'abbreviazione resta in attesa.",
        manageButton: "Configura…",
        panelCaption: "I pulsanti extra e le direzioni della rotella laterale premono combinazioni di tasti a tua scelta.",
        sideWheelLeftName: "Rotella laterale a sinistra",
        sideWheelRightName: "Rotella laterale a destra"
    )

    static let ja = MouseButtonFeatureStrings(
        pageTitle: "マウスボタンのショートカット",
        hubDescription: "マウスの拡張ボタンとサイドホイールの左右に、選んだキーの組み合わせを割り当てられます。",
        enableLabel: "拡張ボタンをショートカットとして使う",
        enableCaption: "拡張ボタンやサイドホイールの左右に、キーの組み合わせを割り当てられます。ショートカットを割り当てている間、元の動作は行われません。",
        addButton: "ボタンまたはサイドホイールを追加",
        captureWaiting: "拡張ボタンを押すか、サイドホイールを動かしてください。",
        captureCancel: "キャンセル",
        captureBlind: "Vorssaintは今マウスを監視できません。",
        captureUnsupported: "この入力にはショートカットを割り当てられません。拡張ボタンかサイドホイールの左右を使ってください。",
        captureWheel: "そのボタンはすでにラジアルメニューを開きます。別のボタンを選ぶか、先にそちらで解除してください。",
        captureExists: "そのボタンまたは方向はすでに下のリストにあります。",
        captureHint: "何も起きない場合は、マウス自体のソフトウェアがその操作を使っているかもしれません。",
        backButtonName: "サイドの「戻る」ボタン",
        forwardButtonName: "サイドの「進む」ボタン",
        otherButtonFormat: "ボタン %d",
        setShortcutButton: "ショートカットを設定",
        removeButton: "削除",
        emptyCaption: "まだショートカットがありません。ボタンまたはサイドホイールの方向を追加してください。",
        rowWheelNote: "このボタンは今ラジアルメニューを開くため、ショートカットは待機中です。",
        manageButton: "設定…",
        panelCaption: "拡張ボタンとサイドホイールの左右が、選んだキーの組み合わせを押します。",
        sideWheelLeftName: "サイドホイールを左へ",
        sideWheelRightName: "サイドホイールを右へ"
    )

    static let ko = MouseButtonFeatureStrings(
        pageTitle: "마우스 버튼 단축키",
        hubDescription: "마우스의 추가 버튼과 측면 휠 방향이 선택한 키 조합을 눌러 줍니다.",
        enableLabel: "추가 버튼을 단축키로 사용",
        enableCaption: "추가 버튼이나 측면 휠 방향마다 키 조합을 대신 누르게 할 수 있습니다. 단축키가 있는 동안 원래 동작은 하지 않습니다.",
        addButton: "버튼 또는 측면 휠 추가",
        captureWaiting: "이제 추가 버튼을 누르거나 측면 휠을 움직이세요.",
        captureCancel: "취소",
        captureBlind: "Vorssaint가 지금은 마우스를 지켜볼 수 없습니다.",
        captureUnsupported: "이 입력에는 단축키를 지정할 수 없습니다. 추가 버튼이나 측면 휠 방향을 사용하세요.",
        captureWheel: "그 버튼은 이미 방사형 메뉴를 엽니다. 다른 버튼을 고르거나 먼저 거기서 해제하세요.",
        captureExists: "그 버튼이나 방향은 이미 아래 목록에 있습니다.",
        captureHint: "아무 일도 없다면 마우스 자체 소프트웨어가 이미 그 조작을 사용 중일 수 있습니다.",
        backButtonName: "뒤로 가기 측면 버튼",
        forwardButtonName: "앞으로 가기 측면 버튼",
        otherButtonFormat: "버튼 %d",
        setShortcutButton: "단축키 설정",
        removeButton: "제거",
        emptyCaption: "아직 단축키가 없습니다. 버튼이나 측면 휠 방향을 추가하세요.",
        rowWheelNote: "이 버튼은 지금 방사형 메뉴를 열기 때문에 단축키는 대기합니다.",
        manageButton: "설정…",
        panelCaption: "추가 버튼과 측면 휠 방향이 선택한 키 조합을 누릅니다.",
        sideWheelLeftName: "측면 휠 왼쪽",
        sideWheelRightName: "측면 휠 오른쪽"
    )

    static let zhHans = MouseButtonFeatureStrings(
        pageTitle: "鼠标按键快捷键",
        hubDescription: "鼠标的额外按键和侧滚轮方向会按下你选择的按键组合。",
        enableLabel: "将额外按键用作快捷键",
        enableCaption: "每个额外按键或侧滚轮方向都可以替你按下一组按键。设有快捷键期间，它不再执行原来的功能。",
        addButton: "添加按键或侧滚轮",
        captureWaiting: "现在请按下额外按键或转动侧滚轮。",
        captureCancel: "取消",
        captureBlind: "Vorssaint 目前无法监视鼠标。",
        captureUnsupported: "该输入无法设置快捷键。请使用额外按键或侧滚轮方向。",
        captureWheel: "该按键已用于打开径向菜单。请换一个，或先在那里释放它。",
        captureExists: "该按键或方向已在下方列表中。",
        captureHint: "如果没有任何反应，可能是鼠标自带的软件已在使用该操作。",
        backButtonName: "侧面后退键",
        forwardButtonName: "侧面前进键",
        otherButtonFormat: "按键 %d",
        setShortcutButton: "设置快捷键",
        removeButton: "移除",
        emptyCaption: "还没有快捷键。请添加按键或侧滚轮方向。",
        rowWheelNote: "该按键目前用于打开径向菜单，快捷键暂不生效。",
        manageButton: "设置…",
        panelCaption: "额外按键和侧滚轮方向会按下你选择的按键组合。",
        sideWheelLeftName: "侧滚轮向左",
        sideWheelRightName: "侧滚轮向右"
    )

    static let zhTW = MouseButtonFeatureStrings(
        pageTitle: "滑鼠按鍵快速鍵",
        hubDescription: "滑鼠的額外按鍵和側滾輪方向會按下你選擇的按鍵組合。",
        enableLabel: "將額外按鍵用作快速鍵",
        enableCaption: "每個額外按鍵或側滾輪方向都可以替你按下一組按鍵。設有快速鍵期間，它不再執行原本的功能。",
        addButton: "加入按鍵或側滾輪",
        captureWaiting: "現在請按下額外按鍵或轉動側滾輪。",
        captureCancel: "取消",
        captureBlind: "Vorssaint 目前無法監看滑鼠。",
        captureUnsupported: "此操作無法設定快速鍵。請使用額外按鍵或側滾輪方向。",
        captureWheel: "該按鍵已用於打開放射狀選單。請換一個，或先在那裡釋放它。",
        captureExists: "該按鍵或方向已在下方列表中。",
        captureHint: "如果沒有任何反應，可能是滑鼠本身的軟體已在使用此操作。",
        backButtonName: "側面上一頁鍵",
        forwardButtonName: "側面下一頁鍵",
        otherButtonFormat: "按鍵 %d",
        setShortcutButton: "設定快速鍵",
        removeButton: "移除",
        emptyCaption: "還沒有快速鍵。請加入按鍵或側滾輪方向。",
        rowWheelNote: "該按鍵目前用於打開放射狀選單，快速鍵暫不生效。",
        manageButton: "設定…",
        panelCaption: "額外按鍵和側滾輪方向會按下你選擇的按鍵組合。",
        sideWheelLeftName: "側滾輪向左",
        sideWheelRightName: "側滾輪向右"
    )

    static let zhHK = MouseButtonFeatureStrings(
        pageTitle: "滑鼠按鍵快捷鍵",
        hubDescription: "滑鼠的額外按鍵和側滾輪方向會按下你選擇的按鍵組合。",
        enableLabel: "將額外按鍵用作快捷鍵",
        enableCaption: "每個額外按鍵或側滾輪方向都可以替你按下一組按鍵。設有快捷鍵期間，它不再執行原本的功能。",
        addButton: "加入按鍵或側滾輪",
        captureWaiting: "現在請按下額外按鍵或轉動側滾輪。",
        captureCancel: "取消",
        captureBlind: "Vorssaint 目前無法監看滑鼠。",
        captureUnsupported: "此操作無法設定快捷鍵。請使用額外按鍵或側滾輪方向。",
        captureWheel: "該按鍵已用於打開放射狀選單。請換一個，或先在那裡釋放它。",
        captureExists: "該按鍵或方向已在下方列表中。",
        captureHint: "如果沒有任何反應，可能是滑鼠本身的軟體已在使用此操作。",
        backButtonName: "側面上一頁鍵",
        forwardButtonName: "側面下一頁鍵",
        otherButtonFormat: "按鍵 %d",
        setShortcutButton: "設定快捷鍵",
        removeButton: "移除",
        emptyCaption: "還沒有快捷鍵。請加入按鍵或側滾輪方向。",
        rowWheelNote: "該按鍵目前用於打開放射狀選單，快捷鍵暫不生效。",
        manageButton: "設定…",
        panelCaption: "額外按鍵和側滾輪方向會按下你選擇的按鍵組合。",
        sideWheelLeftName: "側滾輪向左",
        sideWheelRightName: "側滾輪向右"
    )
}
