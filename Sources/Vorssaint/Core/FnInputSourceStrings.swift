// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for switching input sources with a tap of Fn/🌐. Same contract as
/// the other FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct FnInputSourceStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let keyboardNote: String
    let activeNow: String
    let tapRefused: String
    let systemSection: String
    let systemNothing: String
    let systemOther: String
    let openKeyboardSettings: String
}

extension FeatureStrings {
    static func fnInputSource(_ language: AppLanguage) -> FnInputSourceStrings {
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

extension FnInputSourceStrings {
    static let enUS = FnInputSourceStrings(
        pageTitle: "Fn input source",
        hubDescription: "Tap Fn/🌐 on its own to switch to the next input source, with no picker and no wait.",
        enableToggle: "Switch input sources with a tap of Fn",
        enableCaption: "A quick tap of Fn/🌐 by itself selects the next enabled input source, in the order macOS lists them. Holding Fn, or using it with another key, a click or a modifier, keeps its usual action.",
        keyboardNote: "Keyboards that handle Fn on their own, like many non-Apple keyboards, send no Fn press to switch on.",
        activeNow: "Working now",
        tapRefused: "macOS would not let Vorssaint watch the keyboard. Turn Vorssaint off and on in System Settings › Privacy & Security › Accessibility, then switch this on again.",
        systemSection: "The 🌐 key in macOS",
        systemNothing: "macOS is set to do nothing when 🌐 is pressed, so only Vorssaint acts on the tap.",
        systemOther: "In System Settings › Keyboard, set the 🌐 key to Do Nothing. Otherwise macOS acts on the same tap too: it switches a second time or opens Emoji & Symbols or Dictation.",
        openKeyboardSettings: "Open Keyboard Settings"
    )

    static let ptBR = FnInputSourceStrings(
        pageTitle: "Fonte de entrada no Fn",
        hubDescription: "Toque só no Fn/🌐 para trocar para a próxima fonte de entrada, sem seletor e sem espera.",
        enableToggle: "Trocar a fonte de entrada com um toque no Fn",
        enableCaption: "Um toque rápido só no Fn/🌐 seleciona a próxima fonte de entrada ativada, na ordem em que o macOS as lista. Segurar o Fn, ou usá-lo com outra tecla, um clique ou um modificador, mantém a ação de sempre.",
        keyboardNote: "Teclados que tratam o Fn por conta própria, como muitos teclados que não são da Apple, não enviam o toque no Fn para a troca.",
        activeNow: "Funcionando agora",
        tapRefused: "O macOS não deixou o Vorssaint observar o teclado. Desligue e ligue o Vorssaint em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade e ligue isto de novo.",
        systemSection: "A tecla 🌐 no macOS",
        systemNothing: "O macOS está configurado para não fazer nada ao pressionar 🌐, então só o Vorssaint responde ao toque.",
        systemOther: "Em Ajustes do Sistema › Teclado, defina a tecla 🌐 como Não Fazer Nada. Senão o macOS também responde ao mesmo toque: troca uma segunda vez ou abre Emojis e Símbolos ou o Ditado.",
        openKeyboardSettings: "Abrir Ajustes de Teclado"
    )

    static let tr = FnInputSourceStrings(
        pageTitle: "Fn ile giriş kaynağı",
        hubDescription: "Bir sonraki giriş kaynağına geçmek için yalnızca Fn/🌐 tuşuna dokunun; seçici ve bekleme yok.",
        enableToggle: "Fn’ye dokunarak giriş kaynağını değiştir",
        enableCaption: "Yalnızca Fn/🌐 tuşuna kısa bir dokunuş, etkin giriş kaynaklarından sıradakini macOS’in listelediği sırayla seçer. Fn’yi basılı tutmak ya da başka bir tuş, tıklama veya değiştirici tuşla kullanmak olağan işlevini korur.",
        keyboardNote: "Apple dışındaki birçok klavye gibi Fn’yi kendi içinde işleyen klavyeler, geçiş için Fn basışı göndermez.",
        activeNow: "Şu anda çalışıyor",
        tapRefused: "macOS, Vorssaint’in klavyeyi izlemesine izin vermedi. Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik bölümünde Vorssaint’i kapatıp açın, sonra bunu tekrar açın.",
        systemSection: "macOS’te 🌐 tuşu",
        systemNothing: "macOS, 🌐 tuşuna basıldığında hiçbir şey yapmayacak şekilde ayarlı; dokunuşa yalnızca Vorssaint yanıt verir.",
        systemOther: "Sistem Ayarları › Klavye bölümünde 🌐 tuşunu Hiçbir Şey Yapma olarak ayarlayın. Aksi hâlde macOS da aynı dokunuşa yanıt verir: ikinci kez geçiş yapar ya da Emoji ve Simgeler’i veya Dikte’yi açar.",
        openKeyboardSettings: "Klavye Ayarlarını Aç"
    )

    static let ru = FnInputSourceStrings(
        pageTitle: "Источник ввода по Fn",
        hubDescription: "Короткое нажатие одной клавиши Fn/🌐 переключает на следующий источник ввода без окна выбора и без задержки.",
        enableToggle: "Переключать источник ввода нажатием Fn",
        enableCaption: "Короткое нажатие одной Fn/🌐 выбирает следующий включённый источник ввода в том порядке, в каком их перечисляет macOS. Если удерживать Fn или нажать её вместе с другой клавишей, щелчком или модификатором, она работает как обычно.",
        keyboardNote: "Клавиатуры, которые обрабатывают Fn сами, как многие клавиатуры не от Apple, не передают нажатие Fn для переключения.",
        activeNow: "Работает",
        tapRefused: "macOS не разрешил Vorssaint следить за клавиатурой. Выключите и снова включите Vorssaint в Системных настройках › Конфиденциальность и безопасность › Универсальный доступ и включите это снова.",
        systemSection: "Клавиша 🌐 в macOS",
        systemNothing: "В macOS для клавиши 🌐 выбрано «Ничего не делать», поэтому на нажатие отвечает только Vorssaint.",
        systemOther: "В Системных настройках › Клавиатура выберите для клавиши 🌐 «Ничего не делать». Иначе macOS тоже ответит на это нажатие: переключит источник второй раз или откроет «Эмодзи и символы» либо диктовку.",
        openKeyboardSettings: "Открыть настройки клавиатуры"
    )

    static let es = FnInputSourceStrings(
        pageTitle: "Fuente de entrada con Fn",
        hubDescription: "Toca solo Fn/🌐 para pasar a la siguiente fuente de entrada, sin selector y sin espera.",
        enableToggle: "Cambiar la fuente de entrada con un toque de Fn",
        enableCaption: "Un toque rápido solo de Fn/🌐 selecciona la siguiente fuente de entrada activada, en el orden en que macOS las muestra. Mantener Fn, o usarla con otra tecla, un clic o un modificador, conserva su acción habitual.",
        keyboardNote: "Los teclados que gestionan Fn por su cuenta, como muchos que no son de Apple, no envían la pulsación de Fn para el cambio.",
        activeNow: "Funcionando ahora",
        tapRefused: "macOS no dejó que Vorssaint vigilara el teclado. Desactiva y vuelve a activar Vorssaint en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad y activa esto de nuevo.",
        systemSection: "La tecla 🌐 en macOS",
        systemNothing: "macOS está configurado para no hacer nada al pulsar 🌐, así que solo Vorssaint responde al toque.",
        systemOther: "En Ajustes del Sistema › Teclado, configura la tecla 🌐 en No hacer nada. Si no, macOS también responde al mismo toque: cambia una segunda vez o abre Emojis y símbolos o el Dictado.",
        openKeyboardSettings: "Abrir ajustes de Teclado"
    )

    static let sk = FnInputSourceStrings(
        pageTitle: "Zdroj vstupu cez Fn",
        hubDescription: "Ťuknutím len na Fn/🌐 prepnete na ďalší zdroj vstupu, bez výberu a bez čakania.",
        enableToggle: "Prepínať zdroj vstupu ťuknutím na Fn",
        enableCaption: "Krátke ťuknutie len na Fn/🌐 vyberie ďalší zapnutý zdroj vstupu v poradí, v akom ich uvádza macOS. Podržanie Fn alebo jej použitie s iným klávesom, kliknutím či modifikátorom zachová jej bežnú akciu.",
        keyboardNote: "Klávesnice, ktoré Fn spracúvajú samy, ako mnohé klávesnice od iných výrobcov ako Apple, nepošlú stlačenie Fn na prepnutie.",
        activeNow: "Momentálne aktívne",
        tapRefused: "macOS nedovolil Vorssaintu sledovať klávesnicu. Vorssaint vypnite a zapnite v Systémových nastaveniach › Súkromie a bezpečnosť › Prístupnosť a potom túto voľbu znova zapnite.",
        systemSection: "Kláves 🌐 v macOS",
        systemNothing: "macOS je nastavený tak, aby pri stlačení 🌐 nerobil nič, takže na ťuknutie reaguje iba Vorssaint.",
        systemOther: "V Systémových nastaveniach › Klávesnica nastavte kláves 🌐 na Nerobiť nič. Inak na to isté ťuknutie zareaguje aj macOS: prepne druhýkrát alebo otvorí Emoji a symboly či Diktovanie.",
        openKeyboardSettings: "Otvoriť nastavenia klávesnice"
    )

    static let de = FnInputSourceStrings(
        pageTitle: "Eingabequelle mit Fn",
        hubDescription: "Tippe nur auf Fn/🌐, um zur nächsten Eingabequelle zu wechseln – ohne Auswahl und ohne Warten.",
        enableToggle: "Eingabequelle mit einem Tippen auf Fn wechseln",
        enableCaption: "Ein kurzes Tippen nur auf Fn/🌐 wählt die nächste aktivierte Eingabequelle, in der Reihenfolge, in der macOS sie auflistet. Hältst du Fn oder nutzt du sie mit einer anderen Taste, einem Klick oder einer Sondertaste, behält sie ihre übliche Funktion.",
        keyboardNote: "Tastaturen, die Fn selbst verarbeiten, wie viele Tastaturen anderer Hersteller als Apple, senden keinen Fn-Druck zum Wechseln.",
        activeNow: "Läuft gerade",
        tapRefused: "macOS hat Vorssaint nicht erlaubt, die Tastatur zu beobachten. Schalte Vorssaint unter Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen aus und wieder ein und schalte dies dann wieder ein.",
        systemSection: "Die 🌐-Taste in macOS",
        systemNothing: "macOS ist so eingestellt, dass beim Drücken von 🌐 nichts passiert, also reagiert nur Vorssaint auf das Tippen.",
        systemOther: "Stelle unter Systemeinstellungen › Tastatur die 🌐-Taste auf Keine Aktion. Sonst reagiert auch macOS auf dasselbe Tippen: Es wechselt ein zweites Mal oder öffnet Emoji & Symbole oder das Diktat.",
        openKeyboardSettings: "Tastatur-Einstellungen öffnen"
    )

    static let fr = FnInputSourceStrings(
        pageTitle: "Source d’entrée avec Fn",
        hubDescription: "Touchez Fn/🌐 seule pour passer à la source d’entrée suivante, sans sélecteur ni attente.",
        enableToggle: "Changer de source d’entrée d’une touche sur Fn",
        enableCaption: "Une brève pression sur Fn/🌐 seule sélectionne la source d’entrée activée suivante, dans l’ordre où macOS les présente. Maintenir Fn, ou l’utiliser avec une autre touche, un clic ou une touche de modification, conserve son action habituelle.",
        keyboardNote: "Les claviers qui gèrent Fn eux-mêmes, comme beaucoup de claviers non Apple, n’envoient aucune pression de Fn pour le changement.",
        activeNow: "Actif maintenant",
        tapRefused: "macOS n’a pas autorisé Vorssaint à surveiller le clavier. Désactivez puis réactivez Vorssaint dans Réglages Système › Confidentialité et sécurité › Accessibilité, puis réactivez ceci.",
        systemSection: "La touche 🌐 dans macOS",
        systemNothing: "macOS est réglé pour ne rien faire lorsque l’on appuie sur 🌐\u{00A0}: seul Vorssaint répond à la pression.",
        systemOther: "Dans Réglages Système › Clavier, réglez la touche 🌐 sur Ne rien faire. Sinon macOS répond aussi à la même pression\u{00A0}: il change une seconde fois ou ouvre Emoji et symboles ou la Dictée.",
        openKeyboardSettings: "Ouvrir les réglages Clavier"
    )

    static let it = FnInputSourceStrings(
        pageTitle: "Sorgente di input con Fn",
        hubDescription: "Tocca solo Fn/🌐 per passare alla sorgente di input successiva, senza selettore e senza attese.",
        enableToggle: "Cambia sorgente di input con un tocco di Fn",
        enableCaption: "Un tocco rapido solo su Fn/🌐 seleziona la successiva sorgente di input attiva, nell’ordine in cui macOS le elenca. Tenere premuto Fn, o usarlo con un altro tasto, un clic o un modificatore, mantiene la sua azione abituale.",
        keyboardNote: "Le tastiere che gestiscono Fn da sole, come molte tastiere non Apple, non inviano la pressione di Fn per il cambio.",
        activeNow: "Attivo ora",
        tapRefused: "macOS non ha permesso a Vorssaint di osservare la tastiera. Disattiva e riattiva Vorssaint in Impostazioni di Sistema › Privacy e sicurezza › Accessibilità, poi riattiva questa funzione.",
        systemSection: "Il tasto 🌐 in macOS",
        systemNothing: "macOS è impostato per non fare nulla quando premi 🌐, quindi al tocco risponde solo Vorssaint.",
        systemOther: "In Impostazioni di Sistema › Tastiera, imposta il tasto 🌐 su Non fare nulla. Altrimenti anche macOS risponde allo stesso tocco: cambia una seconda volta o apre Emoji e simboli o la Dettatura.",
        openKeyboardSettings: "Apri impostazioni Tastiera"
    )

    static let ja = FnInputSourceStrings(
        pageTitle: "Fn で入力ソース",
        hubDescription: "Fn/🌐 だけを軽く押すと、選択画面も待ち時間もなく次の入力ソースに切り替わります。",
        enableToggle: "Fn を軽く押して入力ソースを切り替える",
        enableCaption: "Fn/🌐 だけを短く押すと、macOS の一覧の順に次の有効な入力ソースが選ばれます。Fn を押し続けたり、ほかのキー、クリック、修飾キーと組み合わせたりした場合は、いつもの動作のままです。",
        keyboardNote: "Apple 以外の多くのキーボードのように Fn を本体で処理するキーボードでは、切り替えに使う Fn の押下が送られません。",
        activeNow: "動作中",
        tapRefused: "macOS が Vorssaint にキーボードの監視を許可しませんでした。システム設定 › プライバシーとセキュリティ › アクセシビリティで Vorssaint をオフにしてからオンに戻し、もう一度オンにしてください。",
        systemSection: "macOS の 🌐 キー",
        systemNothing: "macOS は 🌐 を押しても何もしない設定なので、押下に応えるのは Vorssaint だけです。",
        systemOther: "システム設定 › キーボードで 🌐 キーを「何もしない」に設定してください。そうしないと macOS も同じ押下に応え、もう一度切り替えたり、絵文字と記号や音声入力を開いたりします。",
        openKeyboardSettings: "キーボード設定を開く"
    )

    static let ko = FnInputSourceStrings(
        pageTitle: "Fn으로 입력 소스 전환",
        hubDescription: "Fn/🌐만 가볍게 누르면 선택 창이나 대기 없이 다음 입력 소스로 전환됩니다.",
        enableToggle: "Fn을 가볍게 눌러 입력 소스 전환",
        enableCaption: "Fn/🌐만 짧게 누르면 macOS 목록 순서대로 다음으로 활성화된 입력 소스가 선택됩니다. Fn을 길게 누르거나 다른 키, 클릭 또는 보조 키와 함께 쓰면 원래 동작이 그대로 유지됩니다.",
        keyboardNote: "Apple이 아닌 많은 키보드처럼 Fn을 자체적으로 처리하는 키보드는 전환에 쓸 Fn 입력을 보내지 않습니다.",
        activeNow: "지금 작동 중",
        tapRefused: "macOS가 Vorssaint의 키보드 감시를 허용하지 않았습니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 Vorssaint를 껐다가 다시 켠 뒤 이 기능을 켜세요.",
        systemSection: "macOS의 🌐 키",
        systemNothing: "macOS에서 🌐를 눌러도 아무 동작도 하지 않도록 설정되어 있어 Vorssaint만 입력에 반응합니다.",
        systemOther: "시스템 설정 › 키보드에서 🌐 키를 ‘아무 것도 안 함’으로 설정하세요. 그렇지 않으면 macOS도 같은 입력에 반응하여 한 번 더 전환하거나 이모티콘 및 기호 또는 받아쓰기를 엽니다.",
        openKeyboardSettings: "키보드 설정 열기"
    )

    static let zhHans = FnInputSourceStrings(
        pageTitle: "用 Fn 切换输入法",
        hubDescription: "单独轻按 Fn/🌐 即可切换到下一个输入法，没有选择框，也无需等待。",
        enableToggle: "轻按 Fn 切换输入法",
        enableCaption: "单独快速轻按 Fn/🌐，会按 macOS 列出的顺序选择下一个已启用的输入法。按住 Fn，或与其他按键、点按或修饰键一起使用时，保持原有操作。",
        keyboardNote: "自行处理 Fn 的键盘（例如许多非 Apple 键盘）不会发出可用于切换的 Fn 按键。",
        activeNow: "正在运行",
        tapRefused: "macOS 不允许 Vorssaint 监听键盘。请在系统设置 › 隐私与安全性 › 辅助功能中关闭再打开 Vorssaint，然后重新打开此功能。",
        systemSection: "macOS 中的 🌐 键",
        systemNothing: "macOS 已设为按下 🌐 时不执行任何操作，因此只有 Vorssaint 会响应轻按。",
        systemOther: "请在系统设置 › 键盘中将 🌐 键设为“不执行任何操作”。否则 macOS 也会响应同一次轻按：再切换一次，或打开表情与符号或听写。",
        openKeyboardSettings: "打开键盘设置"
    )

    static let zhTW = FnInputSourceStrings(
        pageTitle: "用 Fn 切換輸入法",
        hubDescription: "單獨輕按 Fn/🌐 即可切換到下一個輸入法，沒有選擇框，也不必等待。",
        enableToggle: "輕按 Fn 切換輸入法",
        enableCaption: "單獨快速輕按 Fn/🌐，會依 macOS 列出的順序選擇下一個已啟用的輸入法。按住 Fn，或與其他按鍵、點按或修飾鍵一起使用時，保持原本的操作。",
        keyboardNote: "自行處理 Fn 的鍵盤（例如許多非 Apple 鍵盤）不會送出可用於切換的 Fn 按鍵。",
        activeNow: "正在運作",
        tapRefused: "macOS 不允許 Vorssaint 監聽鍵盤。請在系統設定 › 隱私權與安全性 › 輔助使用中關閉再開啟 Vorssaint，然後重新開啟此功能。",
        systemSection: "macOS 中的 🌐 鍵",
        systemNothing: "macOS 已設為按下 🌐 時不執行任何動作，因此只有 Vorssaint 會回應輕按。",
        systemOther: "請在系統設定 › 鍵盤中將 🌐 鍵設為「不執行任何動作」。否則 macOS 也會回應同一次輕按：再切換一次，或打開表情符號與符號或聽寫。",
        openKeyboardSettings: "打開鍵盤設定"
    )

    static let zhHK = FnInputSourceStrings(
        pageTitle: "用 Fn 切換輸入法",
        hubDescription: "單獨輕按 Fn/🌐 就可以切換到下一個輸入法，冇選擇框，亦唔使等。",
        enableToggle: "輕按 Fn 切換輸入法",
        enableCaption: "單獨快速輕按 Fn/🌐，會按 macOS 列出嘅次序揀下一個已啟用嘅輸入法。撳住 Fn，或者同其他按鍵、點按或者修飾鍵一齊用嘅時候，會保持原本嘅操作。",
        keyboardNote: "自己處理 Fn 嘅鍵盤（例如好多非 Apple 鍵盤）唔會送出可以用嚟切換嘅 Fn 按鍵。",
        activeNow: "正在運作",
        tapRefused: "macOS 唔俾 Vorssaint 監聽鍵盤。請喺系統設定 › 隱私權與安全性 › 輔助使用入面關閉再開啟 Vorssaint，然後重新開啟呢個功能。",
        systemSection: "macOS 入面嘅 🌐 鍵",
        systemNothing: "macOS 已經設定咗撳 🌐 嘅時候唔做任何嘢，所以只有 Vorssaint 會回應輕按。",
        systemOther: "請喺系統設定 › 鍵盤將 🌐 鍵設為「不執行任何動作」。如果唔係，macOS 都會回應同一下輕按：再切換多次，或者打開表情符號與符號或者聽寫。",
        openKeyboardSettings: "打開鍵盤設定"
    )

    static let uk = FnInputSourceStrings(
        pageTitle: "Джерело вводу через Fn",
        hubDescription: "Коротке натискання лише Fn/🌐 перемикає на наступне джерело вводу без вікна вибору й без затримки.",
        enableToggle: "Перемикати джерело вводу натисканням Fn",
        enableCaption: "Коротке натискання лише Fn/🌐 вибирає наступне ввімкнене джерело вводу в тому порядку, у якому їх перелічує macOS. Якщо утримувати Fn або натиснути її разом з іншою клавішею, клацанням чи модифікатором, вона працює як зазвичай.",
        keyboardNote: "Клавіатури, які обробляють Fn самі, як багато клавіатур не від Apple, не передають натискання Fn для перемикання.",
        activeNow: "Зараз працює",
        tapRefused: "macOS не дозволила Vorssaint стежити за клавіатурою. Вимкніть і знову ввімкніть Vorssaint у розділі «Системні параметри › Приватність і безпека › Доступність», а потім знову ввімкніть цю функцію.",
        systemSection: "Клавіша 🌐 у macOS",
        systemNothing: "У macOS для клавіші 🌐 вибрано «Нічого не робити», тож на натискання відповідає лише Vorssaint.",
        systemOther: "У розділі «Системні параметри › Клавіатура» виберіть для клавіші 🌐 «Нічого не робити». Інакше macOS теж відповість на це натискання: перемкне джерело вдруге або відкриє «Емодзі та символи» чи диктування.",
        openKeyboardSettings: "Відкрити параметри клавіатури"
    )
}
