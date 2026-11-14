// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AlwaysOnTopStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let shortcut: String
    let reveal: String
    let revealClick: String
    let revealHover: String
    let revealCaption: String
    let border: String
    let borderNone: String
    let borderThin: String
    let borderMedium: String
    let borderThick: String
    let borderColor: String
    let borderColorAccent: String
    let indicatorNote: String
    let excludedTitle: String
    let excludedList: String
    let addApp: String
    let removeApp: String
    let excludedCaption: String
    /// %@ is the app name.
    let pinned: String
    /// %@ is the app name.
    let unpinned: String
    /// %@ is the app name.
    let excluded: String
    let noWindow: String
    let needsAccessibility: String
    let needsScreenRecording: String
    /// %@ is the app name.
    let notForward: String
    let captureStalled: String
}

extension FeatureStrings {
    static func alwaysOnTop(_ language: AppLanguage) -> AlwaysOnTopStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension AlwaysOnTopStrings {
    static let enUS = AlwaysOnTopStrings(
        title: "Always On Top",
        hubDescription: "Keep a window of another app in view above other windows.",
        enable: "Pin windows on top",
        enableCaption: "Press the shortcut in a window to keep it in view above other apps, and press it again to unpin. Pins end when you quit Vorssaint or turn this off.",
        shortcut: "Pin or unpin the front window",
        reveal: "Reveal a pin",
        revealClick: "On click",
        revealHover: "On hover",
        revealCaption: "While other windows cover a pinned window, Vorssaint shows a live picture of it. Click the picture, or rest the pointer on it, to bring the real window forward. A hover only peeks: move away without clicking or typing and you are back where you were.",
        border: "Border",
        borderNone: "None",
        borderThin: "Thin",
        borderMedium: "Medium",
        borderThick: "Thick",
        borderColor: "Border color",
        borderColorAccent: "Use accent color",
        indicatorNote: "While a pinned window is covered, macOS shows the purple screen recording indicator in the menu bar. The picture stays on this Mac and is never saved.",
        excludedTitle: "Never pin",
        excludedList: "Never pin windows of these apps",
        addApp: "Add an app…",
        removeApp: "Remove",
        excludedCaption: "The shortcut does nothing while one of these apps is in front.",
        pinned: "Pinned %@",
        unpinned: "Unpinned %@",
        excluded: "%@ is on the Never pin list",
        noWindow: "No window to pin",
        needsAccessibility: "Pinning needs Accessibility",
        needsScreenRecording: "Pinning needs Screen Recording",
        notForward: "%@ didn’t come forward. Click to try again.",
        captureStalled: "Screen capture isn’t responding. Log out and back in to fix it.")

    static let ptBR = AlwaysOnTopStrings(
        title: "Sempre no topo",
        hubDescription: "Mantenha uma janela de outro app à vista acima das outras janelas.",
        enable: "Fixar janelas no topo",
        enableCaption: "Pressione o atalho em uma janela para mantê-la à vista acima dos outros apps e pressione de novo para soltar. As janelas fixadas são soltas ao sair do Vorssaint ou ao desativar isto.",
        shortcut: "Fixar ou soltar a janela da frente",
        reveal: "Revelar uma janela fixada",
        revealClick: "Ao clicar",
        revealHover: "Ao passar o ponteiro",
        revealCaption: "Enquanto outras janelas cobrem uma janela fixada, o Vorssaint mostra uma imagem ao vivo dela. Clique na imagem, ou deixe o ponteiro sobre ela, para trazer a janela real para a frente. Passar o ponteiro é só uma espiada: afaste-se sem clicar nem digitar e você volta para onde estava.",
        border: "Borda",
        borderNone: "Nenhuma",
        borderThin: "Fina",
        borderMedium: "Média",
        borderThick: "Grossa",
        borderColor: "Cor da borda",
        borderColorAccent: "Usar cor de destaque",
        indicatorNote: "Enquanto uma janela fixada está coberta, o macOS mostra o indicador roxo de gravação de tela na barra de menus. A imagem fica neste Mac e nunca é salva.",
        excludedTitle: "Nunca fixar",
        excludedList: "Nunca fixar janelas destes apps",
        addApp: "Adicionar app…",
        removeApp: "Remover",
        excludedCaption: "O atalho não faz nada enquanto um destes apps está na frente.",
        pinned: "%@ fixado",
        unpinned: "%@ solto",
        excluded: "%@ está na lista Nunca fixar",
        noWindow: "Nenhuma janela para fixar",
        needsAccessibility: "Fixar janelas requer Acessibilidade",
        needsScreenRecording: "Fixar janelas requer Gravação de Tela",
        notForward: "%@ não veio para a frente. Clique para tentar de novo.",
        captureStalled: "A captura de tela não está respondendo. Encerre a sessão e entre de novo para corrigir.")

    static let tr = AlwaysOnTopStrings(
        title: "Her Zaman Üstte",
        hubDescription: "Başka bir uygulamanın penceresini diğer pencerelerin üstünde görünür tutun.",
        enable: "Pencereleri üstte sabitle",
        enableCaption: "Bir pencereyi diğer uygulamaların üstünde görünür tutmak için kısayola basın, sabitlemeyi kaldırmak için yeniden basın. Vorssaint’ten çıktığınızda veya bunu kapattığınızda sabitlemeler kalkar.",
        shortcut: "Öndeki pencereyi sabitle veya kaldır",
        reveal: "Sabitlenmiş pencereyi göster",
        revealClick: "Tıklayınca",
        revealHover: "Üzerine gelince",
        revealCaption: "Sabitlenmiş bir pencerenin üstünü başka pencereler kapattığında Vorssaint onun canlı görüntüsünü gösterir. Gerçek pencereyi öne getirmek için görüntüye tıklayın veya imleci üzerinde bekletin. Üzerine gelmek yalnızca göz atmaktır: tıklamadan veya yazmadan uzaklaşırsanız kaldığınız yere dönersiniz.",
        border: "Kenarlık",
        borderNone: "Yok",
        borderThin: "İnce",
        borderMedium: "Orta",
        borderThick: "Kalın",
        borderColor: "Kenarlık rengi",
        borderColorAccent: "Vurgu rengini kullan",
        indicatorNote: "Sabitlenmiş bir pencerenin üstü kapalıyken macOS menü çubuğunda mor ekran kaydı göstergesini gösterir. Görüntü bu Mac’te kalır ve asla kaydedilmez.",
        excludedTitle: "Asla sabitleme",
        excludedList: "Bu uygulamaların pencerelerini asla sabitleme",
        addApp: "Uygulama ekle…",
        removeApp: "Kaldır",
        excludedCaption: "Bu uygulamalardan biri öndeyken kısayol hiçbir şey yapmaz.",
        pinned: "%@ sabitlendi",
        unpinned: "%@ sabitlemesi kaldırıldı",
        excluded: "%@ Asla sabitleme listesinde",
        noWindow: "Sabitlenecek pencere yok",
        needsAccessibility: "Sabitleme için Erişilebilirlik gerekir",
        needsScreenRecording: "Sabitleme için Ekran Kaydı gerekir",
        notForward: "%@ öne gelmedi. Yeniden denemek için tıklayın.",
        captureStalled: "Ekran yakalama yanıt vermiyor. Düzeltmek için oturumu kapatıp yeniden açın.")

    static let ru = AlwaysOnTopStrings(
        title: "Поверх всех окон",
        hubDescription: "Держите окно другого приложения на виду поверх остальных окон.",
        enable: "Закреплять окна поверх",
        enableCaption: "Нажмите сочетание клавиш в окне, чтобы держать его на виду поверх других приложений, и нажмите ещё раз, чтобы открепить. Закрепления снимаются, когда вы выходите из Vorssaint или выключаете эту функцию.",
        shortcut: "Закрепить или открепить переднее окно",
        reveal: "Показ закреплённого окна",
        revealClick: "По щелчку",
        revealHover: "При наведении",
        revealCaption: "Пока другие окна закрывают закреплённое окно, Vorssaint показывает его живое изображение. Щёлкните по изображению или задержите на нём указатель, чтобы вывести настоящее окно вперёд. Наведение лишь позволяет заглянуть: уведите указатель, ничего не нажав и не напечатав, и вы вернётесь туда, где были.",
        border: "Рамка",
        borderNone: "Нет",
        borderThin: "Тонкая",
        borderMedium: "Средняя",
        borderThick: "Толстая",
        borderColor: "Цвет рамки",
        borderColorAccent: "Использовать акцентный цвет",
        indicatorNote: "Пока закреплённое окно закрыто, macOS показывает в строке меню фиолетовый индикатор записи экрана. Изображение остаётся на этом Mac и никогда не сохраняется.",
        excludedTitle: "Никогда не закреплять",
        excludedList: "Никогда не закреплять окна этих приложений",
        addApp: "Добавить приложение…",
        removeApp: "Удалить",
        excludedCaption: "Сочетание клавиш ничего не делает, пока одно из этих приложений на переднем плане.",
        pinned: "%@ закреплено",
        unpinned: "%@ откреплено",
        excluded: "%@ в списке «Никогда не закреплять»",
        noWindow: "Нет окна для закрепления",
        needsAccessibility: "Для закрепления нужен Универсальный доступ",
        needsScreenRecording: "Для закрепления нужна Запись экрана",
        notForward: "%@ не вышло вперёд. Щёлкните, чтобы попробовать снова.",
        captureStalled: "Захват экрана не отвечает. Чтобы исправить это, выйдите из системы и войдите снова.")

    static let es = AlwaysOnTopStrings(
        title: "Siempre encima",
        hubDescription: "Mantén una ventana de otra app a la vista por encima de las demás ventanas.",
        enable: "Fijar ventanas encima",
        enableCaption: "Pulsa el atajo en una ventana para mantenerla a la vista por encima de otras apps y vuelve a pulsarlo para soltarla. Las ventanas fijadas se sueltan al salir de Vorssaint o al desactivar esto.",
        shortcut: "Fijar o soltar la ventana del frente",
        reveal: "Mostrar una ventana fijada",
        revealClick: "Al hacer clic",
        revealHover: "Al pasar el puntero",
        revealCaption: "Mientras otras ventanas cubren una ventana fijada, Vorssaint muestra una imagen en directo de ella. Haz clic en la imagen, o deja el puntero sobre ella, para traer la ventana real al frente. Pasar el puntero solo echa un vistazo: apártate sin hacer clic ni escribir y vuelves a donde estabas.",
        border: "Borde",
        borderNone: "Ninguno",
        borderThin: "Fino",
        borderMedium: "Medio",
        borderThick: "Grueso",
        borderColor: "Color del borde",
        borderColorAccent: "Usar color de acento",
        indicatorNote: "Mientras una ventana fijada está cubierta, macOS muestra el indicador morado de grabación de pantalla en la barra de menús. La imagen se queda en este Mac y nunca se guarda.",
        excludedTitle: "No fijar nunca",
        excludedList: "No fijar nunca ventanas de estas apps",
        addApp: "Añadir app…",
        removeApp: "Quitar",
        excludedCaption: "El atajo no hace nada mientras una de estas apps está al frente.",
        pinned: "%@ fijada",
        unpinned: "%@ soltada",
        excluded: "%@ está en la lista No fijar nunca",
        noWindow: "No hay ninguna ventana que fijar",
        needsAccessibility: "Fijar ventanas requiere Accesibilidad",
        needsScreenRecording: "Fijar ventanas requiere Grabación de pantalla",
        notForward: "%@ no pasó al frente. Haz clic para volver a intentarlo.",
        captureStalled: "La captura de pantalla no responde. Cierra la sesión y vuelve a entrar para solucionarlo.")

    static let sk = AlwaysOnTopStrings(
        title: "Vždy navrchu",
        hubDescription: "Majte okno inej aplikácie na očiach nad ostatnými oknami.",
        enable: "Pripínať okná navrch",
        enableCaption: "Stlačením skratky v okne ho necháte na očiach nad ostatnými aplikáciami, ďalším stlačením ho odopnete. Pripnutia sa zrušia, keď ukončíte Vorssaint alebo toto vypnete.",
        shortcut: "Pripnúť alebo odopnúť okno v popredí",
        reveal: "Zobrazenie pripnutého okna",
        revealClick: "Po kliknutí",
        revealHover: "Pri podržaní ukazovateľa",
        revealCaption: "Kým pripnuté okno zakrývajú iné okná, Vorssaint ukazuje jeho živý obraz. Kliknite na obraz alebo naň položte ukazovateľ a skutočné okno sa presunie dopredu. Podržanie ukazovateľa je len nahliadnutie: odíďte bez kliknutia či písania a vrátite sa tam, kde ste boli.",
        border: "Okraj",
        borderNone: "Žiadny",
        borderThin: "Tenký",
        borderMedium: "Stredný",
        borderThick: "Hrubý",
        borderColor: "Farba okraja",
        borderColorAccent: "Použiť farbu zvýraznenia",
        indicatorNote: "Kým je pripnuté okno zakryté, macOS v lište ponuky ukazuje fialový indikátor nahrávania obrazovky. Obraz zostáva v tomto Macu a nikdy sa neukladá.",
        excludedTitle: "Nikdy nepripínať",
        excludedList: "Nikdy nepripínať okná týchto aplikácií",
        addApp: "Pridať aplikáciu…",
        removeApp: "Odstrániť",
        excludedCaption: "Skratka nerobí nič, kým je jedna z týchto aplikácií v popredí.",
        pinned: "%@ pripnuté",
        unpinned: "%@ odopnuté",
        excluded: "%@ je v zozname Nikdy nepripínať",
        noWindow: "Žiadne okno na pripnutie",
        needsAccessibility: "Pripínanie vyžaduje Prístupnosť",
        needsScreenRecording: "Pripínanie vyžaduje Nahrávanie obrazovky",
        notForward: "%@ sa nepresunulo dopredu. Kliknutím to skúste znova.",
        captureStalled: "Snímanie obrazovky neodpovedá. Odhláste sa a znova sa prihláste.")

    static let de = AlwaysOnTopStrings(
        title: "Immer im Vordergrund",
        hubDescription: "Halte ein Fenster einer anderen App über den anderen Fenstern im Blick.",
        enable: "Fenster im Vordergrund anheften",
        enableCaption: "Drücke den Kurzbefehl in einem Fenster, um es über anderen Apps im Blick zu behalten, und drücke ihn erneut zum Lösen. Angeheftete Fenster werden gelöst, wenn du Vorssaint beendest oder dies ausschaltest.",
        shortcut: "Vorderstes Fenster anheften oder lösen",
        reveal: "Angeheftetes Fenster zeigen",
        revealClick: "Bei Klick",
        revealHover: "Beim Darüberfahren",
        revealCaption: "Solange andere Fenster ein angeheftetes Fenster verdecken, zeigt Vorssaint ein Livebild davon. Klicke auf das Bild oder lass den Zeiger darauf ruhen, um das echte Fenster nach vorne zu holen. Darüberfahren ist nur ein kurzer Blick: Bewege den Zeiger weg, ohne zu klicken oder zu tippen, und du bist wieder dort, wo du warst.",
        border: "Rahmen",
        borderNone: "Keiner",
        borderThin: "Dünn",
        borderMedium: "Mittel",
        borderThick: "Dick",
        borderColor: "Rahmenfarbe",
        borderColorAccent: "Akzentfarbe verwenden",
        indicatorNote: "Solange ein angeheftetes Fenster verdeckt ist, zeigt macOS in der Menüleiste die violette Anzeige für Bildschirmaufnahme. Das Bild bleibt auf diesem Mac und wird nie gespeichert.",
        excludedTitle: "Nie anheften",
        excludedList: "Fenster dieser Apps nie anheften",
        addApp: "App hinzufügen…",
        removeApp: "Entfernen",
        excludedCaption: "Der Kurzbefehl tut nichts, solange eine dieser Apps vorne ist.",
        pinned: "%@ angeheftet",
        unpinned: "%@ gelöst",
        excluded: "%@ steht auf der Liste „Nie anheften“",
        noWindow: "Kein Fenster zum Anheften",
        needsAccessibility: "Anheften erfordert Bedienungshilfen",
        needsScreenRecording: "Anheften erfordert Bildschirmaufnahme",
        notForward: "%@ kam nicht nach vorne. Klicke, um es erneut zu versuchen.",
        captureStalled: "Die Bildschirmaufnahme reagiert nicht. Melde dich ab und wieder an, um das zu beheben.")

    static let fr = AlwaysOnTopStrings(
        title: "Toujours au premier plan",
        hubDescription: "Gardez une fenêtre d’une autre app en vue au-dessus des autres fenêtres.",
        enable: "Épingler des fenêtres au premier plan",
        enableCaption: "Appuyez sur le raccourci dans une fenêtre pour la garder en vue au-dessus des autres apps, et appuyez à nouveau pour la détacher. Les épingles disparaissent quand vous quittez Vorssaint ou désactivez ceci.",
        shortcut: "Épingler ou détacher la fenêtre au premier plan",
        reveal: "Afficher une fenêtre épinglée",
        revealClick: "Au clic",
        revealHover: "Au survol",
        revealCaption: "Tant que d’autres fenêtres couvrent une fenêtre épinglée, Vorssaint en affiche une image en direct. Cliquez sur l’image, ou laissez le pointeur dessus, pour ramener la vraie fenêtre au premier plan. Le survol n’est qu’un coup d’œil\u{00A0}: éloignez-vous sans cliquer ni taper et vous revenez où vous étiez.",
        border: "Bordure",
        borderNone: "Aucune",
        borderThin: "Fine",
        borderMedium: "Moyenne",
        borderThick: "Épaisse",
        borderColor: "Couleur de la bordure",
        borderColorAccent: "Utiliser la couleur d’accentuation",
        indicatorNote: "Tant qu’une fenêtre épinglée est couverte, macOS affiche l’indicateur violet d’enregistrement de l’écran dans la barre des menus. L’image reste sur ce Mac et n’est jamais enregistrée.",
        excludedTitle: "Ne jamais épingler",
        excludedList: "Ne jamais épingler les fenêtres de ces apps",
        addApp: "Ajouter une app…",
        removeApp: "Retirer",
        excludedCaption: "Le raccourci ne fait rien tant que l’une de ces apps est au premier plan.",
        pinned: "%@ épinglée",
        unpinned: "%@ détachée",
        excluded: "%@ figure dans la liste Ne jamais épingler",
        noWindow: "Aucune fenêtre à épingler",
        needsAccessibility: "L’épinglage nécessite Accessibilité",
        needsScreenRecording: "L’épinglage nécessite Enregistrement de l’écran",
        notForward: "%@ n’est pas passée au premier plan. Cliquez pour réessayer.",
        captureStalled: "La capture d’écran ne répond pas. Fermez la session puis rouvrez-la pour corriger cela.")

    static let it = AlwaysOnTopStrings(
        title: "Sempre in primo piano",
        hubDescription: "Tieni una finestra di un’altra app in vista sopra le altre finestre.",
        enable: "Fissa finestre in primo piano",
        enableCaption: "Premi l’abbreviazione in una finestra per tenerla in vista sopra le altre app, e premila di nuovo per sbloccarla. Le finestre fissate si sbloccano quando esci da Vorssaint o disattivi questa funzione.",
        shortcut: "Fissa o sblocca la finestra in primo piano",
        reveal: "Mostra una finestra fissata",
        revealClick: "Al clic",
        revealHover: "Al passaggio del puntatore",
        revealCaption: "Mentre altre finestre coprono una finestra fissata, Vorssaint ne mostra un’immagine dal vivo. Fai clic sull’immagine, o lascia il puntatore sopra, per portare avanti la finestra reale. Il passaggio del puntatore è solo un’occhiata: allontanati senza fare clic né digitare e torni dov’eri.",
        border: "Bordo",
        borderNone: "Nessuno",
        borderThin: "Sottile",
        borderMedium: "Medio",
        borderThick: "Spesso",
        borderColor: "Colore del bordo",
        borderColorAccent: "Usa il colore di accento",
        indicatorNote: "Mentre una finestra fissata è coperta, macOS mostra l’indicatore viola di registrazione dello schermo nella barra dei menu. L’immagine resta su questo Mac e non viene mai salvata.",
        excludedTitle: "Non fissare mai",
        excludedList: "Non fissare mai le finestre di queste app",
        addApp: "Aggiungi app…",
        removeApp: "Rimuovi",
        excludedCaption: "L’abbreviazione non fa nulla mentre una di queste app è in primo piano.",
        pinned: "%@ fissata",
        unpinned: "%@ sbloccata",
        excluded: "%@ è nella lista Non fissare mai",
        noWindow: "Nessuna finestra da fissare",
        needsAccessibility: "Per fissare serve Accessibilità",
        needsScreenRecording: "Per fissare serve Registrazione schermo",
        notForward: "%@ non è venuta avanti. Fai clic per riprovare.",
        captureStalled: "La cattura dello schermo non risponde. Esci e accedi di nuovo per risolvere.")

    static let ja = AlwaysOnTopStrings(
        title: "常に手前に表示",
        hubDescription: "ほかのAppのウインドウを、ほかのウインドウより手前に見えたままにします。",
        enable: "ウインドウを手前に固定",
        enableCaption: "ウインドウでショートカットを押すと、ほかのAppより手前に見えたままになります。もう一度押すと固定を解除します。Vorssaintを終了するか、この機能をオフにすると固定は解除されます。",
        shortcut: "最前面のウインドウを固定または解除",
        reveal: "固定したウインドウを表示",
        revealClick: "クリック時",
        revealHover: "ポインタを重ねたとき",
        revealCaption: "固定したウインドウがほかのウインドウに隠れている間、Vorssaintはそのライブ映像を表示します。映像をクリックするか、ポインタを重ねたままにすると、実際のウインドウが手前に来ます。ポインタを重ねるのはのぞき見だけです。クリックや入力をせずに離れると、元の状態に戻ります。",
        border: "枠線",
        borderNone: "なし",
        borderThin: "細い",
        borderMedium: "標準",
        borderThick: "太い",
        borderColor: "枠線の色",
        borderColorAccent: "アクセントカラーを使用",
        indicatorNote: "固定したウインドウが隠れている間、macOSはメニューバーに紫色の画面収録インジケータを表示します。映像はこのMacの中だけにあり、保存されることはありません。",
        excludedTitle: "固定しない",
        excludedList: "これらのAppのウインドウは固定しない",
        addApp: "Appを追加…",
        removeApp: "削除",
        excludedCaption: "これらのAppが前面にある間、ショートカットは何もしません。",
        pinned: "%@を固定しました",
        unpinned: "%@の固定を解除しました",
        excluded: "%@は「固定しない」リストにあります",
        noWindow: "固定するウインドウがありません",
        needsAccessibility: "固定にはアクセシビリティが必要です",
        needsScreenRecording: "固定には画面収録が必要です",
        notForward: "%@が手前に来ませんでした。クリックしてもう一度試してください。",
        captureStalled: "画面の取り込みが応答していません。ログアウトしてもう一度ログインすると直ります。")

    static let ko = AlwaysOnTopStrings(
        title: "항상 위에",
        hubDescription: "다른 앱의 윈도우를 다른 윈도우보다 위에 보이게 유지합니다.",
        enable: "윈도우를 위에 고정",
        enableCaption: "윈도우에서 단축키를 누르면 다른 앱보다 위에 보이게 유지되고, 다시 누르면 고정이 해제됩니다. Vorssaint를 종료하거나 이 기능을 끄면 고정이 해제됩니다.",
        shortcut: "맨 앞 윈도우 고정 또는 해제",
        reveal: "고정된 윈도우 보기",
        revealClick: "클릭할 때",
        revealHover: "포인터를 올릴 때",
        revealCaption: "다른 윈도우가 고정된 윈도우를 가리는 동안 Vorssaint는 그 윈도우의 실시간 화면을 보여 줍니다. 화면을 클릭하거나 포인터를 올려 두면 실제 윈도우가 앞으로 나옵니다. 포인터를 올리는 것은 잠깐 보기일 뿐입니다. 클릭하거나 입력하지 않고 벗어나면 원래 자리로 돌아갑니다.",
        border: "테두리",
        borderNone: "없음",
        borderThin: "얇게",
        borderMedium: "보통",
        borderThick: "두껍게",
        borderColor: "테두리 색상",
        borderColorAccent: "강조 색상 사용",
        indicatorNote: "고정된 윈도우가 가려져 있는 동안 macOS는 메뉴 막대에 보라색 화면 녹화 표시를 보여 줍니다. 화면은 이 Mac에만 남고 저장되지 않습니다.",
        excludedTitle: "고정하지 않기",
        excludedList: "이 앱의 윈도우는 고정하지 않기",
        addApp: "앱 추가…",
        removeApp: "제거",
        excludedCaption: "이 앱 중 하나가 앞에 있는 동안에는 단축키가 아무 동작도 하지 않습니다.",
        pinned: "%@ 고정됨",
        unpinned: "%@ 고정 해제됨",
        excluded: "%@ 앱은 고정하지 않기 목록에 있습니다",
        noWindow: "고정할 윈도우가 없습니다",
        needsAccessibility: "고정하려면 손쉬운 사용이 필요합니다",
        needsScreenRecording: "고정하려면 화면 녹화가 필요합니다",
        notForward: "%@ 윈도우가 앞으로 나오지 않았습니다. 다시 시도하려면 클릭하십시오.",
        captureStalled: "화면 캡처가 응답하지 않습니다. 로그아웃했다가 다시 로그인하면 해결됩니다.")

    static let uk = AlwaysOnTopStrings(
        title: "Поверх усіх вікон",
        hubDescription: "Тримайте вікно іншої програми на виду поверх інших вікон.",
        enable: "Закріплювати вікна поверх",
        enableCaption: "Натисніть сполучення клавіш у вікні, щоб тримати його на виду поверх інших програм, і натисніть ще раз, щоб відкріпити. Закріплення знімаються, коли ви виходите з Vorssaint або вимикаєте цю функцію.",
        shortcut: "Закріпити або відкріпити переднє вікно",
        reveal: "Показ закріпленого вікна",
        revealClick: "За клацанням",
        revealHover: "При наведенні",
        revealCaption: "Поки інші вікна закривають закріплене вікно, Vorssaint показує його живе зображення. Клацніть зображення або затримайте на ньому вказівник, щоб вивести справжнє вікно вперед. Наведення лише дає зазирнути: відведіть вказівник, нічого не клацнувши й не надрукувавши, і ви повернетеся туди, де були.",
        border: "Рамка",
        borderNone: "Немає",
        borderThin: "Тонка",
        borderMedium: "Середня",
        borderThick: "Товста",
        borderColor: "Колір рамки",
        borderColorAccent: "Використовувати акцентний колір",
        indicatorNote: "Поки закріплене вікно закрите, macOS показує на смузі меню фіолетовий індикатор запису екрана. Зображення залишається на цьому Mac і ніколи не зберігається.",
        excludedTitle: "Ніколи не закріплювати",
        excludedList: "Ніколи не закріплювати вікна цих програм",
        addApp: "Додати програму…",
        removeApp: "Видалити",
        excludedCaption: "Сполучення клавіш нічого не робить, поки одна з цих програм на передньому плані.",
        pinned: "%@ закріплено",
        unpinned: "%@ відкріплено",
        excluded: "%@ у списку «Ніколи не закріплювати»",
        noWindow: "Немає вікна для закріплення",
        needsAccessibility: "Для закріплення потрібна Доступність",
        needsScreenRecording: "Для закріплення потрібен Запис екрана",
        notForward: "%@ не вийшло вперед. Клацніть, щоб спробувати знову.",
        captureStalled: "Захоплення екрана не відповідає. Щоб виправити це, вийдіть із системи й увійдіть знову.")

    static let zhHans = AlwaysOnTopStrings(
        title: "始终置顶",
        hubDescription: "让其他 App 的窗口始终显示在其他窗口之上。",
        enable: "将窗口置顶",
        enableCaption: "在窗口中按下快捷键，即可让它显示在其他 App 之上；再按一次取消置顶。退出 Vorssaint 或关闭此功能时，置顶会取消。",
        shortcut: "置顶或取消置顶最前面的窗口",
        reveal: "显示置顶的窗口",
        revealClick: "点按时",
        revealHover: "悬停时",
        revealCaption: "当其他窗口遮住置顶的窗口时，Vorssaint 会显示它的实时画面。点按画面，或将指针停在画面上，即可将真实窗口移到前面。悬停只是看一眼：不点按也不输入就移开，你会回到原来的位置。",
        border: "边框",
        borderNone: "无",
        borderThin: "细",
        borderMedium: "中",
        borderThick: "粗",
        borderColor: "边框颜色",
        borderColorAccent: "使用强调色",
        indicatorNote: "置顶的窗口被遮住时，macOS 会在菜单栏中显示紫色的屏幕录制指示器。画面只留在这台 Mac 上，从不保存。",
        excludedTitle: "从不置顶",
        excludedList: "从不置顶这些 App 的窗口",
        addApp: "添加 App…",
        removeApp: "移除",
        excludedCaption: "当这些 App 之一在最前面时，快捷键不起作用。",
        pinned: "已置顶 %@",
        unpinned: "已取消置顶 %@",
        excluded: "%@ 在“从不置顶”列表中",
        noWindow: "没有可置顶的窗口",
        needsAccessibility: "置顶需要辅助功能权限",
        needsScreenRecording: "置顶需要屏幕录制权限",
        notForward: "%@ 未能移到前面。点按以重试。",
        captureStalled: "屏幕捕获没有响应。退出登录后重新登录即可修复。")

    static let zhTW = AlwaysOnTopStrings(
        title: "永遠置頂",
        hubDescription: "讓其他 App 的視窗一直顯示在其他視窗之上。",
        enable: "將視窗置頂",
        enableCaption: "在視窗中按下快速鍵，即可讓它顯示在其他 App 之上；再按一次即取消置頂。結束 Vorssaint 或關閉此功能時，置頂會取消。",
        shortcut: "置頂或取消置頂最前方的視窗",
        reveal: "顯示置頂的視窗",
        revealClick: "按一下時",
        revealHover: "停留時",
        revealCaption: "當其他視窗擋住置頂的視窗時，Vorssaint 會顯示它的即時畫面。按一下畫面，或將指標停在畫面上，即可將真正的視窗移到前方。停留只是看一眼：不按也不輸入就移開，你會回到原本的位置。",
        border: "邊框",
        borderNone: "無",
        borderThin: "細",
        borderMedium: "中",
        borderThick: "粗",
        borderColor: "邊框顏色",
        borderColorAccent: "使用強調色",
        indicatorNote: "置頂的視窗被擋住時，macOS 會在選單列中顯示紫色的螢幕錄製指示器。畫面只留在這部 Mac 上，絕不儲存。",
        excludedTitle: "永不置頂",
        excludedList: "永不置頂這些 App 的視窗",
        addApp: "加入 App…",
        removeApp: "移除",
        excludedCaption: "當這些 App 之一在最前方時，快速鍵不會有作用。",
        pinned: "已置頂 %@",
        unpinned: "已取消置頂 %@",
        excluded: "%@ 在「永不置頂」列表中",
        noWindow: "沒有可置頂的視窗",
        needsAccessibility: "置頂需要輔助使用權限",
        needsScreenRecording: "置頂需要螢幕錄製權限",
        notForward: "%@ 沒有移到前方。按一下以重試。",
        captureStalled: "螢幕擷取沒有回應。登出後再重新登入即可修正。")

    static let zhHK = AlwaysOnTopStrings(
        title: "永遠置頂",
        hubDescription: "讓其他 App 的視窗一直顯示在其他視窗之上。",
        enable: "將視窗置頂",
        enableCaption: "在視窗中按下快速鍵，即可讓它顯示在其他 App 之上；再按一次即取消置頂。結束 Vorssaint 或關閉此功能時，置頂會取消。",
        shortcut: "置頂或取消置頂最前方的視窗",
        reveal: "顯示置頂的視窗",
        revealClick: "按一下時",
        revealHover: "停留時",
        revealCaption: "當其他視窗擋住置頂的視窗時，Vorssaint 會顯示它的即時畫面。按一下畫面，或將指標停在畫面上，即可將真正的視窗移到前方。停留只是看一眼：不按也不輸入就移開，你會回到原本的位置。",
        border: "邊框",
        borderNone: "無",
        borderThin: "細",
        borderMedium: "中",
        borderThick: "粗",
        borderColor: "邊框顏色",
        borderColorAccent: "使用強調色",
        indicatorNote: "置頂的視窗被擋住時，macOS 會在選單列中顯示紫色的螢幕錄製指示器。畫面只留在這部 Mac 上，絕不儲存。",
        excludedTitle: "永不置頂",
        excludedList: "永不置頂這些 App 的視窗",
        addApp: "加入 App…",
        removeApp: "移除",
        excludedCaption: "當這些 App 之一在最前方時，快速鍵不會有作用。",
        pinned: "已置頂 %@",
        unpinned: "已取消置頂 %@",
        excluded: "%@ 在「永不置頂」列表中",
        noWindow: "沒有可置頂的視窗",
        needsAccessibility: "置頂需要輔助使用權限",
        needsScreenRecording: "置頂需要螢幕錄製權限",
        notForward: "%@ 沒有移到前方。按一下以重試。",
        captureStalled: "螢幕擷取沒有回應。登出後再重新登入即可修正。")
}
