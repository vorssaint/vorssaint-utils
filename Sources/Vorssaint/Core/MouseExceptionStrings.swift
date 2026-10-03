// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseExceptionStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let captionSmoothScroll: String
    let captionLinearScroll: String
    let captionScrollDirection: String
    let captionNavigation: String
    let captionButtonShortcuts: String
    let captionMiddleClick: String
    let captionFocusFollowsMouse: String
    let captionSuperKey: String
    let captionFnLock: String
    let captionSwitcherPause: String
    let pausedSuperKey: String

    func caption(for scope: MouseExceptionScope) -> String {
        switch scope {
        case .smoothScroll: return captionSmoothScroll
        case .linearScroll: return captionLinearScroll
        case .scrollDirection: return captionScrollDirection
        case .focusFollowsMouse: return captionFocusFollowsMouse
        case .navigation: return captionNavigation
        case .buttonShortcuts: return captionButtonShortcuts
        case .middleClick: return captionMiddleClick
        case .superKey: return captionSuperKey
        case .fnLock: return captionFnLock
        case .switcherPause: return captionSwitcherPause
        }
    }
}

extension FeatureStrings {
    static func mouseExceptions(_ language: AppLanguage) -> MouseExceptionStrings {
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

extension MouseExceptionStrings {
    static let enUS = MouseExceptionStrings(
        listTitle: "Apps to leave alone",
        addButton: "Add an app…",
        removeButton: "Remove",
        captionSmoothScroll: "The wheel keeps its plain steps in these apps, for apps that read it their own way, like 3D and design tools.",
        captionLinearScroll: "The wheel keeps the pace macOS gives it in these apps, for games and 3D tools that count the notches themselves.",
        captionScrollDirection: "The wheel keeps the direction macOS gives it in these apps.",
        captionNavigation: "The side buttons keep doing whatever these apps already do with them.",
        captionButtonShortcuts: "Your extra mouse buttons stay quiet in these apps, and the press reaches them instead.",
        captionMiddleClick: "A three finger click stays a normal click in these apps.",
        captionFocusFollowsMouse: "Hovering does not change focus or raise a window in these apps.",
        captionSuperKey: "While any of these apps is open, even in the background, Super Key pauses and the chosen key works normally.",
        captionFnLock: "In these apps the F1–F12 keys switch to the behavior the system’s checkbox does not give them: real function keys where the system gives media actions, and media actions where the system gives function keys.",
        captionSwitcherPause: "While any of these apps is in front, the app switcher hands its shortcut back, so a remote desktop or KVM receives it instead.",
        pausedSuperKey: "Paused while a selected app is open"
    )

    static let ptBR = MouseExceptionStrings(
        listTitle: "Apps para não mexer",
        addButton: "Adicionar app…",
        removeButton: "Remover",
        captionSmoothScroll: "Nestes apps a roda continua com os passos normais, para apps que leem a roda do jeito deles, como ferramentas de 3D e design.",
        captionLinearScroll: "Nestes apps a roda mantém o ritmo que o macOS dá a ela, para jogos e ferramentas de 3D que contam os passos por conta própria.",
        captionScrollDirection: "Nestes apps a roda mantém o sentido que o macOS dá a ela.",
        captionNavigation: "Nestes apps os botões laterais continuam fazendo o que eles já fazem.",
        captionButtonShortcuts: "Nestes apps seus botões extras ficam quietos e o clique chega no app.",
        captionMiddleClick: "Nestes apps o clique de três dedos continua um clique normal.",
        captionFocusFollowsMouse: "Nestes apps passar o mouse não muda o foco nem traz a janela para frente.",
        captionSuperKey: "Enquanto algum destes apps estiver aberto, mesmo em segundo plano, a Super Key pausa e a tecla escolhida funciona normalmente.",
        captionFnLock: "Nestes apps as teclas F1–F12 trocam para o comportamento que a caixa do sistema não lhes dá: teclas de função reais onde o sistema dá ações de mídia, e ações de mídia onde o sistema dá teclas de função.",
        captionSwitcherPause: "Enquanto algum destes apps estiver em primeiro plano, o alternador de apps devolve o atalho, para que uma área de trabalho remota ou KVM o receba.",
        pausedSuperKey: "Pausada enquanto um app selecionado está aberto"
    )

    static let tr = MouseExceptionStrings(
        listTitle: "Dokunulmayacak uygulamalar",
        addButton: "Uygulama ekle…",
        removeButton: "Kaldır",
        captionSmoothScroll: "Bu uygulamalarda tekerlek normal adımlarında kalır; tekerleği kendine göre okuyan 3B ve tasarım araçları için.",
        captionLinearScroll: "Bu uygulamalarda tekerlek macOS’un verdiği hızda kalır; adımları kendisi sayan oyunlar ve 3B araçları için.",
        captionScrollDirection: "Bu uygulamalarda tekerlek macOS’un verdiği yönde kalır.",
        captionNavigation: "Bu uygulamalarda yan düğmeler zaten yaptıkları işi yapmayı sürdürür.",
        captionButtonShortcuts: "Bu uygulamalarda ekstra düğmeleriniz sessiz kalır ve basma uygulamaya ulaşır.",
        captionMiddleClick: "Bu uygulamalarda üç parmak tıklaması normal tıklama olarak kalır.",
        captionFocusFollowsMouse: "Bu uygulamalarda imleci bekletmek odağı değiştirmez veya pencereyi öne getirmez.",
        captionSuperKey: "Bu uygulamalardan biri arka planda bile açıkken Super Key duraklatılır ve seçilen tuş normal çalışır.",
        captionFnLock: "Bu uygulamalarda F1–F12 tuşları sistemin onlara vermediği davranışa geçer: sistemin medya eylemleri verdiği yerde gerçek işlev tuşları, sistemin işlev tuşları verdiği yerde medya eylemleri.",
        captionSwitcherPause: "Bu uygulamalardan biri önde olduğu sürece uygulama değiştirici kısayolu geri verir, böylece uzak masaüstü veya KVM onu alır.",
        pausedSuperKey: "Seçili bir uygulama açıkken duraklatıldı"
    )

    static let ru = MouseExceptionStrings(
        listTitle: "Приложения без вмешательства",
        addButton: "Добавить приложение…",
        removeButton: "Удалить",
        captionSmoothScroll: "В этих приложениях колесо крутится обычными шагами: для тех, кто читает его по-своему, например 3D-редакторов и графических программ.",
        captionLinearScroll: "В этих приложениях колесо крутится с той скоростью, которую даёт macOS: для игр и 3D-редакторов, которые сами считают щелчки.",
        captionScrollDirection: "В этих приложениях колесо сохраняет направление, которое даёт macOS.",
        captionNavigation: "В этих приложениях боковые кнопки продолжают делать то, что уже делают.",
        captionButtonShortcuts: "В этих приложениях ваши дополнительные кнопки молчат, а нажатие доходит до приложения.",
        captionMiddleClick: "В этих приложениях щелчок тремя пальцами остаётся обычным щелчком.",
        captionFocusFollowsMouse: "В этих приложениях наведение не меняет фокус и не выводит окно на передний план.",
        captionSuperKey: "Пока любое из этих приложений открыто, даже в фоне, Super Key приостановлена, а выбранная клавиша работает как обычно.",
        captionFnLock: "В этих приложениях клавиши F1–F12 переключаются на поведение, которое не даёт системная галочка: настоящие функциональные клавиши там, где система даёт медиадействия, и медиадействия там, где система даёт функциональные клавиши.",
        captionSwitcherPause: "Пока одно из этих приложений на переднем плане, переключатель приложений отдаёт свой ярлык обратно, чтобы удалённый рабочий стол или KVM получил его.",
        pausedSuperKey: "Приостановлено, пока открыто выбранное приложение"
    )

    static let es = MouseExceptionStrings(
        listTitle: "Apps que no se tocan",
        addButton: "Añadir app…",
        removeButton: "Quitar",
        captionSmoothScroll: "En estas apps la rueda mantiene sus pasos normales, para las que la leen a su manera, como las de 3D y diseño.",
        captionLinearScroll: "En estas apps la rueda mantiene el ritmo que le da macOS, para juegos y herramientas 3D que cuentan los pasos por su cuenta.",
        captionScrollDirection: "En estas apps la rueda mantiene el sentido que le da macOS.",
        captionNavigation: "En estas apps los botones laterales siguen haciendo lo que ya hacen.",
        captionButtonShortcuts: "En estas apps tus botones extra se quedan callados y la pulsación llega a la app.",
        captionMiddleClick: "En estas apps el clic con tres dedos sigue siendo un clic normal.",
        captionFocusFollowsMouse: "En estas apps pasar el puntero no cambia el foco ni trae la ventana al frente.",
        captionSuperKey: "Mientras alguna de estas apps esté abierta, incluso en segundo plano, Super Key se pausa y la tecla elegida funciona normalmente.",
        captionFnLock: "En estas apps las teclas F1–F12 cambian al comportamiento que la casilla del sistema no les da: teclas de función reales donde el sistema da acciones de medios, y acciones de medios donde el sistema da teclas de función.",
        captionSwitcherPause: "Mientras alguna de estas apps esté en primer plano, el conmutador de apps devuelve su atajo, para que un escritorio remoto o KVM lo reciba.",
        pausedSuperKey: "En pausa mientras una app seleccionada esté abierta"
    )

    static let sk = MouseExceptionStrings(
        listTitle: "Apky, do ktorých nezasahovať",
        addButton: "Pridať aplikáciu…",
        removeButton: "Odstrániť",
        captionSmoothScroll: "V týchto aplikáciách si koliesko zachová svoje bežné kroky, pre aplikácie, ktoré ho spracúvajú po svojom, napríklad nástroje na 3D a dizajn.",
        captionLinearScroll: "V týchto aplikáciách si koliesko zachová tempo, ktoré mu dáva macOS, pre hry a 3D nástroje, ktoré si kroky počítajú samy.",
        captionScrollDirection: "V týchto aplikáciách si koliesko zachová smer, ktorý mu dáva macOS.",
        captionNavigation: "Bočné tlačidlá v týchto aplikáciách naďalej robia to, čo s nimi aplikácia už robí.",
        captionButtonShortcuts: "Vaše ďalšie tlačidlá myši v týchto aplikáciách mlčia a stlačenie namiesto toho dostane aplikácia.",
        captionMiddleClick: "Kliknutie tromi prstami zostáva v týchto aplikáciách bežným kliknutím.",
        captionFocusFollowsMouse: "Prejdenie kurzorom nad oknom v týchto aplikáciách nemení fokus ani ho nezobrazí navrchu.",
        captionSuperKey: "Kým je otvorená ktorákoľvek z týchto aplikácií, aj na pozadí, Super kláves sa pozastaví a vybraný kláves funguje normálne.",
        captionFnLock: "V týchto aplikáciách sa klávesy F1–F12 prepnú na správanie, ktoré im systémový prepínač nedáva: skutočné funkčné klávesy tam, kde systém dáva multimediálne akcie, a multimediálne akcie tam, kde systém dáva funkčné klávesy.",
        captionSwitcherPause: "Kým je jedna z týchto aplikácií v popredí, prepínač aplikácií vráti svoju skratku, aby ju dostala vzdialená plocha alebo KVM.",
        pausedSuperKey: "Pozastavené, kým je otvorená vybraná aplikácia"
    )

    static let de = MouseExceptionStrings(
        listTitle: "Apps, die unberührt bleiben",
        addButton: "App hinzufügen…",
        removeButton: "Entfernen",
        captionSmoothScroll: "In diesen Apps behält das Rad seine normalen Schritte, für Apps, die es selbst auswerten, etwa 3D- und Design-Werkzeuge.",
        captionLinearScroll: "In diesen Apps behält das Rad das Tempo, das macOS ihm gibt, für Spiele und 3D-Werkzeuge, die die Rastschritte selbst zählen.",
        captionScrollDirection: "In diesen Apps behält das Rad die Richtung, die macOS ihm gibt.",
        captionNavigation: "In diesen Apps tun die Seitentasten weiter, was sie dort schon tun.",
        captionButtonShortcuts: "In diesen Apps bleiben deine Zusatztasten still und der Druck erreicht die App.",
        captionMiddleClick: "In diesen Apps bleibt ein Klick mit drei Fingern ein normaler Klick.",
        captionFocusFollowsMouse: "In diesen Apps ändert ein Verweilen des Zeigers weder den Fokus noch die Fensterreihenfolge.",
        captionSuperKey: "Solange eine dieser Apps geöffnet ist, auch im Hintergrund, pausiert Super Key und die gewählte Taste funktioniert normal.",
        captionFnLock: "In diesen Apps wechseln F1–F12 zu dem Verhalten, das das Systemhäkchen nicht gibt: echte Funktionstasten, wo das System Medienaktionen gibt, und Medienaktionen, wo das System Funktionstasten gibt.",
        captionSwitcherPause: "Solange eine dieser Apps im Vordergrund ist, gibt der App-Umschalter seinen Kurzbefehl zurück, damit ein Remote-Desktop oder KVM ihn erhält.",
        pausedSuperKey: "Pausiert, solange eine ausgewählte App geöffnet ist"
    )

    static let fr = MouseExceptionStrings(
        listTitle: "Apps à ne pas toucher",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        captionSmoothScroll: "Dans ces apps la molette garde ses crans normaux, pour celles qui la lisent à leur façon, comme les outils 3D et de design.",
        captionLinearScroll: "Dans ces apps la molette garde le rythme que macOS lui donne, pour les jeux et les outils 3D qui comptent eux-mêmes les crans.",
        captionScrollDirection: "Dans ces apps la molette garde le sens que macOS lui donne.",
        captionNavigation: "Dans ces apps les boutons latéraux continuent de faire ce qu’ils y font déjà.",
        captionButtonShortcuts: "Dans ces apps vos boutons supplémentaires se taisent et l’appui atteint l’app.",
        captionMiddleClick: "Dans ces apps un clic à trois doigts reste un clic normal.",
        captionFocusFollowsMouse: "Dans ces apps le survol ne change pas le focus et ne place pas la fenêtre au premier plan.",
        captionSuperKey: "Tant qu’une de ces apps est ouverte, même en arrière-plan, Super Key est en pause et la touche choisie fonctionne normalement.",
        captionFnLock: "Dans ces apps les touches F1–F12 basculent vers le comportement que la case du système ne leur donne pas\u{00A0}: de vraies touches de fonction là où le système donne des actions média, et des actions média là où le système donne des touches de fonction.",
        captionSwitcherPause: "Tant qu’une de ces apps est au premier plan, le sélecteur d’apps rend son raccourci, pour qu’un bureau distant ou un KVM le reçoive.",
        pausedSuperKey: "En pause tant qu’une app sélectionnée est ouverte"
    )

    static let it = MouseExceptionStrings(
        listTitle: "App da non toccare",
        addButton: "Aggiungi app…",
        removeButton: "Rimuovi",
        captionSmoothScroll: "In queste app la rotellina mantiene i suoi scatti normali, per quelle che la leggono a modo loro, come gli strumenti 3D e di design.",
        captionLinearScroll: "In queste app la rotellina mantiene il ritmo che le dà macOS, per i giochi e gli strumenti 3D che contano gli scatti da soli.",
        captionScrollDirection: "In queste app la rotellina mantiene il verso che le dà macOS.",
        captionNavigation: "In queste app i pulsanti laterali continuano a fare quello che già fanno.",
        captionButtonShortcuts: "In queste app i tuoi pulsanti extra restano zitti e la pressione arriva all’app.",
        captionMiddleClick: "In queste app un clic con tre dita resta un clic normale.",
        captionFocusFollowsMouse: "In queste app il passaggio del puntatore non cambia il focus né porta avanti la finestra.",
        captionSuperKey: "Finché una di queste app è aperta, anche in background, Super Key è in pausa e il tasto scelto funziona normalmente.",
        captionFnLock: "In queste app i tasti F1–F12 passano al comportamento che la casella di sistema non dà loro: veri tasti funzione dove il sistema dà azioni multimediali, e azioni multimediali dove il sistema dà tasti funzione.",
        captionSwitcherPause: "Finché una di queste app è in primo piano, il selettore app restituisce la sua scorciatoia, così un desktop remoto o KVM la riceve.",
        pausedSuperKey: "In pausa mentre un’app selezionata è aperta"
    )

    static let ja = MouseExceptionStrings(
        listTitle: "そのままにするApp",
        addButton: "Appを追加…",
        removeButton: "削除",
        captionSmoothScroll: "これらのAppではホイールが元の刻みのままになります。3Dやデザインのツールのように、ホイールを独自に読むApp向けです。",
        captionLinearScroll: "これらのAppではホイールの速さがmacOSのままになります。目盛りを自分で数えるゲームや3Dツール向けです。",
        captionScrollDirection: "これらのAppではホイールの向きがmacOSのままになります。",
        captionNavigation: "これらのAppでは横のボタンが元々の働きを続けます。",
        captionButtonShortcuts: "これらのAppでは拡張ボタンが働かず、押した操作がAppに届きます。",
        captionMiddleClick: "これらのAppでは3本指のクリックが普通のクリックのままです。",
        captionFocusFollowsMouse: "これらのAppではポインタを止めてもフォーカスやウインドウの前後関係は変わりません。",
        captionSuperKey: "これらのAppのいずれかが開いている間は、バックグラウンドでもSuper Keyが一時停止し、選択したキーは通常どおり動作します。",
        captionFnLock: "これらのAppではF1–F12キーがシステムのチェックボックスが与えない動作に切り替わります。システムがメディア操作を与える場合は本来のファンクションキーに、システムがファンクションキーを与える場合はメディア操作に切り替わります。",
        captionSwitcherPause: "これらのAppのいずれかが最前面にある間、Appスイッチャーはショートカットを返し、リモートデスクトップやKVMがそれを受け取ります。",
        pausedSuperKey: "選択したAppが開いている間は一時停止中"
    )

    static let ko = MouseExceptionStrings(
        listTitle: "건드리지 않을 앱",
        addButton: "앱 추가…",
        removeButton: "제거",
        captionSmoothScroll: "이 앱들에서는 휠이 원래 단계 그대로 움직입니다. 3D나 디자인 도구처럼 휠을 자기 방식으로 읽는 앱을 위한 것입니다.",
        captionLinearScroll: "이 앱들에서는 휠 속도가 macOS가 주는 그대로 유지됩니다. 칸 수를 직접 세는 게임이나 3D 도구를 위한 것입니다.",
        captionScrollDirection: "이 앱들에서는 휠 방향이 macOS가 주는 그대로 유지됩니다.",
        captionNavigation: "이 앱들에서는 측면 버튼이 원래 하던 일을 계속합니다.",
        captionButtonShortcuts: "이 앱들에서는 추가 버튼이 조용히 있고 누름이 앱에 전달됩니다.",
        captionMiddleClick: "이 앱들에서는 세 손가락 클릭이 보통 클릭으로 남습니다.",
        captionFocusFollowsMouse: "이 앱들에서는 포인터를 올려 두어도 포커스나 윈도우 순서가 바뀌지 않습니다.",
        captionSuperKey: "이 앱 중 하나라도 열려 있으면 백그라운드에서도 Super Key가 일시 정지되고 선택한 키가 정상적으로 작동합니다.",
        captionFnLock: "이 앱들에서 F1–F12 키가 시스템 체크박스가 주지 않는 동작으로 전환됩니다. 시스템이 미디어 동작을 주는 곳에서는 진짜 기능 키로, 시스템이 기능 키를 주는 곳에서는 미디어 동작으로 바뀝니다.",
        captionSwitcherPause: "이 앱 중 하나라도 맨앞에 있는 동안 App 스위처가 자신의 단축키를 돌려주어 원격 데스크톱이나 KVM이 받습니다.",
        pausedSuperKey: "선택한 앱이 열려 있는 동안 일시 정지됨"
    )

    static let zhHans = MouseExceptionStrings(
        listTitle: "不干预的 App",
        addButton: "添加 App…",
        removeButton: "移除",
        captionSmoothScroll: "在这些 App 里滚轮保持原本的档位，适合自己解读滚轮的 App，比如 3D 和设计工具。",
        captionLinearScroll: "在这些 App 里滚轮保持 macOS 给它的速度，适合自己计算格数的游戏和 3D 工具。",
        captionScrollDirection: "在这些 App 里滚轮保持 macOS 给它的方向。",
        captionNavigation: "在这些 App 里侧键继续做它们本来做的事。",
        captionButtonShortcuts: "在这些 App 里额外按键保持安静，按下会传给 App。",
        captionMiddleClick: "在这些 App 里三指点按仍是普通点按。",
        captionFocusFollowsMouse: "在这些 App 里悬停不会改变焦点，也不会将窗口置于前方。",
        captionSuperKey: "这些 App 中任意一个打开时，即使在后台，Super Key 也会暂停，所选按键恢复正常功能。",
        captionFnLock: "在这些 App 里，F1–F12 键切换到系统复选框未给出的行为：系统给媒体操作的地方变为真正的功能键，系统给功能键的地方变为媒体操作。",
        captionSwitcherPause: "在这些 App 中任意一个处于最前台时，App 切换器会交还其快捷键，让远程桌面或 KVM 接收。",
        pausedSuperKey: "所选 App 打开期间已暂停"
    )

    static let zhTW = MouseExceptionStrings(
        listTitle: "不干預的 App",
        addButton: "加入 App…",
        removeButton: "移除",
        captionSmoothScroll: "在這些 App 裡滾輪保持原本的段落，適合自己解讀滾輪的 App，例如 3D 和設計工具。",
        captionLinearScroll: "在這些 App 裡滾輪保持 macOS 給它的速度，適合自己計算格數的遊戲和 3D 工具。",
        captionScrollDirection: "在這些 App 裡滾輪保持 macOS 給它的方向。",
        captionNavigation: "在這些 App 裡側鍵繼續做它們原本做的事。",
        captionButtonShortcuts: "在這些 App 裡額外按鍵保持安靜，按下會傳給 App。",
        captionMiddleClick: "在這些 App 裡三指點按仍是普通點按。",
        captionFocusFollowsMouse: "在這些 App 裡停留指標不會改變焦點，也不會將視窗移到最前方。",
        captionSuperKey: "這些 App 中任一個開啟時，即使在背景執行，Super Key 也會暫停，所選按鍵恢復正常功能。",
        captionFnLock: "在這些 App 裡，F1–F12 鍵切換到系統勾選框未給出的行為：系統給媒體操作的地方變為真正的功能鍵，系統給功能鍵的地方變為媒體操作。",
        captionSwitcherPause: "在這些 App 中任一個在最前方面時，App 切換器會交還其快捷鍵，讓遠端桌面或 KVM 接收。",
        pausedSuperKey: "所選 App 開啟期間已暫停"
    )

    static let zhHK = MouseExceptionStrings(
        listTitle: "不干預的 App",
        addButton: "加入 App…",
        removeButton: "移除",
        captionSmoothScroll: "在這些 App 裡滾輪保持原本的段落，適合自己解讀滾輪的 App，例如 3D 和設計工具。",
        captionLinearScroll: "在這些 App 裡滾輪保持 macOS 給它的速度，適合自己計算格數的遊戲和 3D 工具。",
        captionScrollDirection: "在這些 App 裡滾輪保持 macOS 給它的方向。",
        captionNavigation: "在這些 App 裡側鍵繼續做它們原本做的事。",
        captionButtonShortcuts: "在這些 App 裡額外按鍵保持安靜，按下會傳給 App。",
        captionMiddleClick: "在這些 App 裡三指點按仍是普通點按。",
        captionFocusFollowsMouse: "在這些 App 裡停留指標不會改變焦點，也不會將視窗移到最前方。",
        captionSuperKey: "這些 App 中任何一個開啟時，即使在背景執行，Super Key 也會暫停，所選按鍵恢復正常功能。",
        captionFnLock: "喺呢啲 App 裡面，F1–F12 鍵切換到系統剔選框無畀到嘅行為：系統畀媒體操作嘅地方變為真正嘅功能鍵，系統畀功能鍵嘅地方變為媒體操作。",
        captionSwitcherPause: "呢啲 App 中任何一個喺最前面嗰陣，App 切換器會交還佢嘅快捷鍵，令遠端桌面或 KVM 接收。",
        pausedSuperKey: "所選 App 開啟期間已暫停"
    )
    static let uk = MouseExceptionStrings(
        listTitle: "Програми, яких не чіпати",
        addButton: "Додати програму…",
        removeButton: "Видалити",
        captionSmoothScroll: "Колесо зберігає свої звичайні кроки в цих програмах, для програм, які читають його по-своєму, як 3D-інструменти та дизайнерські програми.",
        captionLinearScroll: "Колесо зберігає темп, який дає macOS, у цих програмах, для ігор і 3D-інструментів, що самі рахують клаци.",
        captionScrollDirection: "Колесо зберігає напрямок, який дає macOS, у цих програмах.",
        captionNavigation: "Бокові кнопки продовжують робити те, що ці програми вже з ними роблять.",
        captionButtonShortcuts: "Ваші додаткові кнопки миші мовчать у цих програмах, а натискання доходить до них.",
        captionMiddleClick: "Клац трьома пальцями залишається звичайним клацом у цих програмах.",
        captionFocusFollowsMouse: "Наведення не змінює фокус та не піднімає вікно в цих програмах.",
        captionSuperKey: "Коли будь-яка з цих програм відкрита, навіть у фоновому режимі, Super Key призупиняється, і вибрана клавіша відновлює свою звичайну функцію.",
        captionFnLock: "У цих програмах клавіші F1–F12 перемикаються на поведінку, яку не дає системна галочка: справжні функціональні клавіші там, де система дає медіадії, і медіадії там, де система дає функціональні клавіші.",
        captionSwitcherPause: "Поки одна з цих програм на передньому плані, перемикач програм віддає свій ярлик, щоб віддалена стільниця або KVM його отримала.",
        pausedSuperKey: "Призупинено, поки відкрита вибрана програма"
    )
}
