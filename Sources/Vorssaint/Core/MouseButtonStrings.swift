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
        hubDescription: "Extra mouse buttons press a key combination you choose.",
        enableLabel: "Use extra buttons as shortcuts",
        enableCaption: "Each extra button on your mouse can press a key combination for you. While a button has a shortcut, it stops doing what it did before.",
        addButton: "Add a mouse button",
        captureWaiting: "Now click the mouse button you want to use.",
        captureCancel: "Cancel",
        captureBlind: "Vorssaint cannot watch the mouse right now.",
        captureUnsupported: "That button cannot take a shortcut. Only the extra buttons, like the side pair, can.",
        captureWheel: "That button already opens the radial menu. Pick another one, or free it there first.",
        captureExists: "That button is already on the list below.",
        captureHint: "If nothing happens when you press it, the mouse's own software may have taken that button.",
        backButtonName: "Back side button",
        forwardButtonName: "Forward side button",
        otherButtonFormat: "Button %d",
        setShortcutButton: "Set shortcut",
        removeButton: "Remove",
        emptyCaption: "No buttons yet. Add one and give it a key combination.",
        rowWheelNote: "This button opens the radial menu now, so the shortcut waits.",
        manageButton: "Set up…",
        panelCaption: "Extra mouse buttons press key combinations you choose."
    )

    static let ptBR = MouseButtonFeatureStrings(
        pageTitle: "Atalhos nos botões do mouse",
        hubDescription: "Os botões extras do mouse apertam uma combinação de teclas que você escolher.",
        enableLabel: "Usar botões extras como atalhos",
        enableCaption: "Cada botão extra do mouse pode apertar uma combinação de teclas por você. Enquanto um botão tem atalho, ele deixa de fazer o que fazia antes.",
        addButton: "Adicionar botão do mouse",
        captureWaiting: "Agora clique o botão do mouse que você quer usar.",
        captureCancel: "Cancelar",
        captureBlind: "O Vorssaint não consegue observar o mouse agora.",
        captureUnsupported: "Esse botão não pode receber atalho. Só os botões extras, como o par lateral, podem.",
        captureWheel: "Esse botão já abre o menu radial. Escolha outro, ou libere ele lá primeiro.",
        captureExists: "Esse botão já está na lista abaixo.",
        captureHint: "Se nada acontecer ao apertar, o software do próprio mouse pode ter tomado esse botão.",
        backButtonName: "Botão lateral de voltar",
        forwardButtonName: "Botão lateral de avançar",
        otherButtonFormat: "Botão %d",
        setShortcutButton: "Definir atalho",
        removeButton: "Remover",
        emptyCaption: "Nenhum botão ainda. Adicione um e dê a ele uma combinação de teclas.",
        rowWheelNote: "Esse botão abre o menu radial agora, então o atalho fica esperando.",
        manageButton: "Configurar…",
        panelCaption: "Botões extras do mouse apertam combinações de teclas que você escolher."
    )

    static let tr = MouseButtonFeatureStrings(
        pageTitle: "Fare düğmesi kısayolları",
        hubDescription: "Ekstra fare düğmeleri seçtiğiniz bir tuş birleşimine basar.",
        enableLabel: "Ekstra düğmeleri kısayol olarak kullan",
        enableCaption: "Farenizdeki her ekstra düğme sizin yerinize bir tuş birleşimine basabilir. Bir düğmede kısayol varken önceki işlevini yapmayı bırakır.",
        addButton: "Fare düğmesi ekle",
        captureWaiting: "Şimdi kullanmak istediğiniz fare düğmesine tıklayın.",
        captureCancel: "Vazgeç",
        captureBlind: "Vorssaint şu anda fareyi izleyemiyor.",
        captureUnsupported: "Bu düğmeye kısayol verilemez. Yalnızca yan çift gibi ekstra düğmelere verilebilir.",
        captureWheel: "Bu düğme zaten dairesel menüyü açıyor. Başka bir düğme seçin veya önce orada serbest bırakın.",
        captureExists: "Bu düğme zaten aşağıdaki listede.",
        captureHint: "Bastığınızda hiçbir şey olmuyorsa farenin kendi yazılımı o düğmeyi almış olabilir.",
        backButtonName: "Geri yan düğmesi",
        forwardButtonName: "İleri yan düğmesi",
        otherButtonFormat: "Düğme %d",
        setShortcutButton: "Kısayol belirle",
        removeButton: "Kaldır",
        emptyCaption: "Henüz düğme yok. Bir tane ekleyin ve ona bir tuş birleşimi verin.",
        rowWheelNote: "Bu düğme şu anda dairesel menüyü açıyor, kısayol bekliyor.",
        manageButton: "Ayarla…",
        panelCaption: "Ekstra fare düğmeleri seçtiğiniz tuş birleşimlerine basar."
    )

    static let ru = MouseButtonFeatureStrings(
        pageTitle: "Сочетания на кнопках мыши",
        hubDescription: "Дополнительные кнопки мыши нажимают выбранное вами сочетание клавиш.",
        enableLabel: "Использовать дополнительные кнопки как сочетания",
        enableCaption: "Каждая дополнительная кнопка мыши может нажимать сочетание клавиш за вас. Пока на кнопке есть сочетание, она перестаёт делать то, что делала раньше.",
        addButton: "Добавить кнопку мыши",
        captureWaiting: "Теперь нажмите кнопку мыши, которую хотите использовать.",
        captureCancel: "Отменить",
        captureBlind: "Vorssaint сейчас не может отслеживать мышь.",
        captureUnsupported: "Этой кнопке нельзя назначить сочетание. Подходят только дополнительные кнопки, например боковая пара.",
        captureWheel: "Эта кнопка уже открывает радиальное меню. Выберите другую или сначала освободите её там.",
        captureExists: "Эта кнопка уже есть в списке ниже.",
        captureHint: "Если при нажатии ничего не происходит, кнопку могло забрать собственное ПО мыши.",
        backButtonName: "Боковая кнопка «Назад»",
        forwardButtonName: "Боковая кнопка «Вперёд»",
        otherButtonFormat: "Кнопка %d",
        setShortcutButton: "Задать сочетание",
        removeButton: "Удалить",
        emptyCaption: "Кнопок пока нет. Добавьте одну и назначьте ей сочетание клавиш.",
        rowWheelNote: "Эта кнопка сейчас открывает радиальное меню, поэтому сочетание ждёт.",
        manageButton: "Настроить…",
        panelCaption: "Дополнительные кнопки мыши нажимают выбранные вами сочетания клавиш."
    )

    static let es = MouseButtonFeatureStrings(
        pageTitle: "Atajos en los botones del ratón",
        hubDescription: "Los botones extra del ratón pulsan una combinación de teclas que tú eliges.",
        enableLabel: "Usar botones extra como atajos",
        enableCaption: "Cada botón extra del ratón puede pulsar una combinación de teclas por ti. Mientras un botón tiene un atajo, deja de hacer lo que hacía antes.",
        addButton: "Añadir botón del ratón",
        captureWaiting: "Ahora haz clic con el botón del ratón que quieres usar.",
        captureCancel: "Cancelar",
        captureBlind: "Vorssaint no puede observar el ratón ahora mismo.",
        captureUnsupported: "Ese botón no puede recibir un atajo. Solo los botones extra, como el par lateral, pueden.",
        captureWheel: "Ese botón ya abre el menú radial. Elige otro, o libéralo allí primero.",
        captureExists: "Ese botón ya está en la lista de abajo.",
        captureHint: "Si no pasa nada al pulsarlo, puede que el software del propio ratón se haya quedado con ese botón.",
        backButtonName: "Botón lateral de retroceso",
        forwardButtonName: "Botón lateral de avance",
        otherButtonFormat: "Botón %d",
        setShortcutButton: "Definir atajo",
        removeButton: "Eliminar",
        emptyCaption: "Aún no hay botones. Añade uno y dale una combinación de teclas.",
        rowWheelNote: "Ese botón abre el menú radial ahora, así que el atajo queda en espera.",
        manageButton: "Configurar…",
        panelCaption: "Los botones extra del ratón pulsan combinaciones de teclas que tú eliges."
    )

    static let de = MouseButtonFeatureStrings(
        pageTitle: "Kurzbefehle auf Maustasten",
        hubDescription: "Zusätzliche Maustasten drücken einen Tastaturkurzbefehl deiner Wahl.",
        enableLabel: "Zusatztasten als Kurzbefehle verwenden",
        enableCaption: "Jede zusätzliche Maustaste kann einen Tastaturkurzbefehl für dich drücken. Solange eine Taste einen Kurzbefehl hat, tut sie nicht mehr das, was sie vorher tat.",
        addButton: "Maustaste hinzufügen",
        captureWaiting: "Klicke jetzt mit der Maustaste, die du verwenden möchtest.",
        captureCancel: "Abbrechen",
        captureBlind: "Vorssaint kann die Maus gerade nicht beobachten.",
        captureUnsupported: "Diese Taste kann keinen Kurzbefehl bekommen. Nur die Zusatztasten, wie das seitliche Paar, können das.",
        captureWheel: "Diese Taste öffnet bereits das Radialmenü. Wähle eine andere oder gib sie dort zuerst frei.",
        captureExists: "Diese Taste steht schon in der Liste unten.",
        captureHint: "Wenn beim Drücken nichts passiert, hat vielleicht die Software der Maus selbst diese Taste übernommen.",
        backButtonName: "Seitliche Zurück-Taste",
        forwardButtonName: "Seitliche Vorwärts-Taste",
        otherButtonFormat: "Taste %d",
        setShortcutButton: "Kurzbefehl festlegen",
        removeButton: "Entfernen",
        emptyCaption: "Noch keine Tasten. Füge eine hinzu und gib ihr einen Tastaturkurzbefehl.",
        rowWheelNote: "Diese Taste öffnet gerade das Radialmenü, der Kurzbefehl wartet daher.",
        manageButton: "Einrichten…",
        panelCaption: "Zusätzliche Maustasten drücken Tastaturkurzbefehle deiner Wahl."
    )

    static let fr = MouseButtonFeatureStrings(
        pageTitle: "Raccourcis sur les boutons de la souris",
        hubDescription: "Les boutons supplémentaires de la souris appuient sur une combinaison de touches de votre choix.",
        enableLabel: "Utiliser les boutons supplémentaires comme raccourcis",
        enableCaption: "Chaque bouton supplémentaire de la souris peut appuyer sur une combinaison de touches pour vous. Tant qu'un bouton a un raccourci, il cesse de faire ce qu'il faisait avant.",
        addButton: "Ajouter un bouton de souris",
        captureWaiting: "Cliquez maintenant avec le bouton de la souris que vous voulez utiliser.",
        captureCancel: "Annuler",
        captureBlind: "Vorssaint ne peut pas observer la souris pour le moment.",
        captureUnsupported: "Ce bouton ne peut pas recevoir de raccourci. Seuls les boutons supplémentaires, comme la paire latérale, le peuvent.",
        captureWheel: "Ce bouton ouvre déjà le menu radial. Choisissez-en un autre, ou libérez-le là-bas d'abord.",
        captureExists: "Ce bouton est déjà dans la liste ci-dessous.",
        captureHint: "Si rien ne se passe quand vous appuyez, le logiciel de la souris a peut-être pris ce bouton.",
        backButtonName: "Bouton latéral précédent",
        forwardButtonName: "Bouton latéral suivant",
        otherButtonFormat: "Bouton %d",
        setShortcutButton: "Définir le raccourci",
        removeButton: "Supprimer",
        emptyCaption: "Aucun bouton pour l'instant. Ajoutez-en un et donnez-lui une combinaison de touches.",
        rowWheelNote: "Ce bouton ouvre le menu radial en ce moment, le raccourci attend donc.",
        manageButton: "Configurer…",
        panelCaption: "Les boutons supplémentaires de la souris appuient sur des combinaisons de touches de votre choix."
    )

    static let it = MouseButtonFeatureStrings(
        pageTitle: "Abbreviazioni sui pulsanti del mouse",
        hubDescription: "I pulsanti extra del mouse premono una combinazione di tasti a tua scelta.",
        enableLabel: "Usa i pulsanti extra come abbreviazioni",
        enableCaption: "Ogni pulsante extra del mouse può premere una combinazione di tasti per te. Finché un pulsante ha un'abbreviazione, smette di fare quello che faceva prima.",
        addButton: "Aggiungi pulsante del mouse",
        captureWaiting: "Ora fai clic con il pulsante del mouse che vuoi usare.",
        captureCancel: "Annulla",
        captureBlind: "Vorssaint al momento non riesce a osservare il mouse.",
        captureUnsupported: "Quel pulsante non può ricevere un'abbreviazione. Solo i pulsanti extra, come la coppia laterale, possono.",
        captureWheel: "Quel pulsante apre già il menu radiale. Scegline un altro, oppure liberalo prima lì.",
        captureExists: "Quel pulsante è già nell'elenco qui sotto.",
        captureHint: "Se non succede nulla quando lo premi, il software del mouse potrebbe aver preso quel pulsante.",
        backButtonName: "Pulsante laterale indietro",
        forwardButtonName: "Pulsante laterale avanti",
        otherButtonFormat: "Pulsante %d",
        setShortcutButton: "Imposta abbreviazione",
        removeButton: "Rimuovi",
        emptyCaption: "Ancora nessun pulsante. Aggiungine uno e assegnagli una combinazione di tasti.",
        rowWheelNote: "Questo pulsante ora apre il menu radiale, quindi l'abbreviazione resta in attesa.",
        manageButton: "Configura…",
        panelCaption: "I pulsanti extra del mouse premono combinazioni di tasti a tua scelta."
    )

    static let ja = MouseButtonFeatureStrings(
        pageTitle: "マウスボタンのショートカット",
        hubDescription: "マウスの拡張ボタンが、選んだキーの組み合わせを押します。",
        enableLabel: "拡張ボタンをショートカットとして使う",
        enableCaption: "マウスの拡張ボタンごとに、キーの組み合わせを押させることができます。ショートカットを割り当てている間、そのボタンは元の動作をしなくなります。",
        addButton: "マウスボタンを追加",
        captureWaiting: "使いたいマウスボタンをクリックしてください。",
        captureCancel: "キャンセル",
        captureBlind: "Vorssaintは今マウスを監視できません。",
        captureUnsupported: "そのボタンにはショートカットを割り当てられません。サイドのペアなどの拡張ボタンだけが使えます。",
        captureWheel: "そのボタンはすでにラジアルメニューを開きます。別のボタンを選ぶか、先にそちらで解除してください。",
        captureExists: "そのボタンはすでに下のリストにあります。",
        captureHint: "押しても何も起きない場合は、マウス自体のソフトウェアがそのボタンを使っているかもしれません。",
        backButtonName: "サイドの「戻る」ボタン",
        forwardButtonName: "サイドの「進む」ボタン",
        otherButtonFormat: "ボタン %d",
        setShortcutButton: "ショートカットを設定",
        removeButton: "削除",
        emptyCaption: "まだボタンがありません。追加して、キーの組み合わせを割り当ててください。",
        rowWheelNote: "このボタンは今ラジアルメニューを開くため、ショートカットは待機中です。",
        manageButton: "設定…",
        panelCaption: "マウスの拡張ボタンが、選んだキーの組み合わせを押します。"
    )

    static let ko = MouseButtonFeatureStrings(
        pageTitle: "마우스 버튼 단축키",
        hubDescription: "마우스의 추가 버튼이 선택한 키 조합을 눌러 줍니다.",
        enableLabel: "추가 버튼을 단축키로 사용",
        enableCaption: "마우스의 추가 버튼마다 키 조합을 대신 누르게 할 수 있습니다. 버튼에 단축키가 있는 동안 그 버튼은 원래 하던 동작을 하지 않습니다.",
        addButton: "마우스 버튼 추가",
        captureWaiting: "이제 사용할 마우스 버튼을 클릭하세요.",
        captureCancel: "취소",
        captureBlind: "Vorssaint가 지금은 마우스를 지켜볼 수 없습니다.",
        captureUnsupported: "그 버튼에는 단축키를 줄 수 없습니다. 측면 한 쌍 같은 추가 버튼만 가능합니다.",
        captureWheel: "그 버튼은 이미 방사형 메뉴를 엽니다. 다른 버튼을 고르거나 먼저 거기서 해제하세요.",
        captureExists: "그 버튼은 이미 아래 목록에 있습니다.",
        captureHint: "눌러도 아무 일도 없다면 마우스 자체 소프트웨어가 그 버튼을 가져갔을 수 있습니다.",
        backButtonName: "뒤로 가기 측면 버튼",
        forwardButtonName: "앞으로 가기 측면 버튼",
        otherButtonFormat: "버튼 %d",
        setShortcutButton: "단축키 설정",
        removeButton: "제거",
        emptyCaption: "아직 버튼이 없습니다. 하나 추가하고 키 조합을 지정하세요.",
        rowWheelNote: "이 버튼은 지금 방사형 메뉴를 열기 때문에 단축키는 대기합니다.",
        manageButton: "설정…",
        panelCaption: "마우스의 추가 버튼이 선택한 키 조합을 누릅니다."
    )

    static let zhHans = MouseButtonFeatureStrings(
        pageTitle: "鼠标按键快捷键",
        hubDescription: "鼠标的额外按键会按下你选择的按键组合。",
        enableLabel: "将额外按键用作快捷键",
        enableCaption: "鼠标的每个额外按键都可以替你按下一组按键。按键设有快捷键期间，它不再执行原来的功能。",
        addButton: "添加鼠标按键",
        captureWaiting: "现在请点按你想使用的鼠标按键。",
        captureCancel: "取消",
        captureBlind: "Vorssaint 目前无法监视鼠标。",
        captureUnsupported: "该按键无法设置快捷键。只有侧面成对按键这样的额外按键才可以。",
        captureWheel: "该按键已用于打开径向菜单。请换一个，或先在那里释放它。",
        captureExists: "该按键已在下方列表中。",
        captureHint: "如果按下后没有任何反应，可能是鼠标自带的软件占用了该按键。",
        backButtonName: "侧面后退键",
        forwardButtonName: "侧面前进键",
        otherButtonFormat: "按键 %d",
        setShortcutButton: "设置快捷键",
        removeButton: "移除",
        emptyCaption: "还没有按键。添加一个并给它一组按键组合。",
        rowWheelNote: "该按键目前用于打开径向菜单，快捷键暂不生效。",
        manageButton: "设置…",
        panelCaption: "鼠标的额外按键会按下你选择的按键组合。"
    )

    static let zhTW = MouseButtonFeatureStrings(
        pageTitle: "滑鼠按鍵快速鍵",
        hubDescription: "滑鼠的額外按鍵會按下你選擇的按鍵組合。",
        enableLabel: "將額外按鍵用作快速鍵",
        enableCaption: "滑鼠的每個額外按鍵都可以替你按下一組按鍵。按鍵設有快速鍵期間，它不再執行原本的功能。",
        addButton: "加入滑鼠按鍵",
        captureWaiting: "現在請按一下你想使用的滑鼠按鍵。",
        captureCancel: "取消",
        captureBlind: "Vorssaint 目前無法監看滑鼠。",
        captureUnsupported: "該按鍵無法設定快速鍵。只有側面成對按鍵這類額外按鍵才可以。",
        captureWheel: "該按鍵已用於打開放射狀選單。請換一個，或先在那裡釋放它。",
        captureExists: "該按鍵已在下方列表中。",
        captureHint: "如果按下後沒有任何反應，可能是滑鼠本身的軟體佔用了該按鍵。",
        backButtonName: "側面上一頁鍵",
        forwardButtonName: "側面下一頁鍵",
        otherButtonFormat: "按鍵 %d",
        setShortcutButton: "設定快速鍵",
        removeButton: "移除",
        emptyCaption: "還沒有按鍵。加入一個並給它一組按鍵組合。",
        rowWheelNote: "該按鍵目前用於打開放射狀選單，快速鍵暫不生效。",
        manageButton: "設定…",
        panelCaption: "滑鼠的額外按鍵會按下你選擇的按鍵組合。"
    )

    static let zhHK = MouseButtonFeatureStrings(
        pageTitle: "滑鼠按鍵快捷鍵",
        hubDescription: "滑鼠的額外按鍵會按下你選擇的按鍵組合。",
        enableLabel: "將額外按鍵用作快捷鍵",
        enableCaption: "滑鼠的每個額外按鍵都可以替你按下一組按鍵。按鍵設有快捷鍵期間，它不再執行原本的功能。",
        addButton: "加入滑鼠按鍵",
        captureWaiting: "現在請按一下你想使用的滑鼠按鍵。",
        captureCancel: "取消",
        captureBlind: "Vorssaint 目前無法監看滑鼠。",
        captureUnsupported: "該按鍵無法設定快捷鍵。只有側面成對按鍵這類額外按鍵才可以。",
        captureWheel: "該按鍵已用於打開放射狀選單。請換一個，或先在那裡釋放它。",
        captureExists: "該按鍵已在下方列表中。",
        captureHint: "如果按下後沒有任何反應，可能是滑鼠本身的軟體佔用了該按鍵。",
        backButtonName: "側面上一頁鍵",
        forwardButtonName: "側面下一頁鍵",
        otherButtonFormat: "按鍵 %d",
        setShortcutButton: "設定快捷鍵",
        removeButton: "移除",
        emptyCaption: "還沒有按鍵。加入一個並給它一組按鍵組合。",
        rowWheelNote: "該按鍵目前用於打開放射狀選單，快捷鍵暫不生效。",
        manageButton: "設定…",
        panelCaption: "滑鼠的額外按鍵會按下你選擇的按鍵組合。"
    )
}
