// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct GlobeKeyStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let prerequisiteNote: String
    let openKeyboardSettingsButton: String
    let gestureSection: String
    let gestureCaption: String
    let singlePressLabel: String
    let doublePressLabel: String
    let triplePressLabel: String
    let longPressLabel: String
    let actionNothing: String
    let actionOpenSettings: String
    let sourcePickerLabel: String
    let activeNow: String
    let tapRefused: String
}

extension FeatureStrings {
    static func globeKey(_ language: AppLanguage) -> GlobeKeyStrings {
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

extension GlobeKeyStrings {
    static let enUS = GlobeKeyStrings(
        pageTitle: "Language switcher",
        hubDescription: "The 🌐 key goes straight to the language you need, without cycling through layouts: one press for the first language, two for the second, three for the third.",
        enableToggle: "Switch languages with the 🌐 key",
        enableCaption: "One, two or three presses switch to the language you pick below; a long press opens the keyboard settings.",
        prerequisiteNote: "Set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard, or macOS switches the input source as well.",
        openKeyboardSettingsButton: "Open Keyboard settings",
        gestureSection: "Gestures",
        gestureCaption: "A single press lands about a third of a second after you release the key, while the system waits to see whether another press follows. Using the Globe key with another key (Globe+arrow, Globe+brightness) does nothing.",
        singlePressLabel: "Single press",
        doublePressLabel: "Double press",
        triplePressLabel: "Triple press",
        longPressLabel: "Long press",
        actionNothing: "Nothing",
        actionOpenSettings: "Open keyboard settings",
        sourcePickerLabel: "Input source",
        activeNow: "Working now",
        tapRefused: "macOS would not let Vorssaint watch the keyboard. Turn Vorssaint off and on in System Settings › Privacy & Security › Accessibility, then switch this on again."
    )

    static let ptBR = GlobeKeyStrings(
        pageTitle: "Troca de idioma",
        hubDescription: "A tecla 🌐 vai direto ao idioma de que você precisa, sem ciclar entre layouts: um toque para o primeiro idioma, dois para o segundo, três para o terceiro.",
        enableToggle: "Trocar idiomas com a tecla 🌐",
        enableCaption: "Um, dois ou três toques mudam para o idioma escolhido abaixo; um toque longo abre os ajustes do teclado.",
        prerequisiteNote: "Defina “Tecla 🌐” como “Não fazer nada” em Ajustes do Sistema › Teclado, senão o macOS também troca a fonte de entrada.",
        openKeyboardSettingsButton: "Abrir ajustes do Teclado",
        gestureSection: "Gestos",
        gestureCaption: "Um toque chega cerca de um terço de segundo depois que você solta a tecla, enquanto o sistema espera ver se outro toque vem. Usar a tecla Globe com outra tecla (Globe+seta, Globe+brilho) não faz nada.",
        singlePressLabel: "Toque único",
        doublePressLabel: "Toque duplo",
        triplePressLabel: "Toque triplo",
        longPressLabel: "Toque longo",
        actionNothing: "Nada",
        actionOpenSettings: "Abrir ajustes do teclado",
        sourcePickerLabel: "Fonte de entrada",
        activeNow: "Funcionando agora",
        tapRefused: "O macOS não deixou o Vorssaint observar o teclado. Desative e ative o Vorssaint em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade e ligue isto novamente."
    )

    static let tr = GlobeKeyStrings(
        pageTitle: "Dil değiştirme",
        hubDescription: "🌐 tuşu sizi istediğiniz dile doğrudan götürür, düzenler arasında döngü yapmaz: birinci dil için tek, ikinci için çift, üçüncü için üç basış.",
        enableToggle: "Dilleri 🌐 tuşuyla değiştir",
        enableCaption: "Bir, iki veya üç basış aşağıda seçtiğiniz dile geçer; uzun basış klavye ayarlarını açar.",
        prerequisiteNote: "Sistem Ayarları › Klavye’de “🌐 tuşu” için “Hiçbir şey yapma” seçin, yoksa macOS da giriş kaynağını değiştirir.",
        openKeyboardSettingsButton: "Klavye ayarlarını aç",
        gestureSection: "Hareketler",
        gestureCaption: "Tek basış, sistem başka bir basışın gelip gelmeyeceğini beklerken tuşu bıraktıktan yaklaşık üçte bir saniye sonra işler. Globe tuşunu başka bir tuşla kullanmak (Globe+ok, Globe+parlaklık) hiçbir şey yapmaz.",
        singlePressLabel: "Tek basış",
        doublePressLabel: "Çift basış",
        triplePressLabel: "Üçlü basış",
        longPressLabel: "Uzun basış",
        actionNothing: "Hiçbir şey",
        actionOpenSettings: "Klavye ayarlarını aç",
        sourcePickerLabel: "Giriş kaynağı",
        activeNow: "Şu anda çalışıyor",
        tapRefused: "macOS, Vorssaint’in klavyeyi izlemesine izin vermedi. Vorssaint’i Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik bölümünde kapatıp açın ve bunu yeniden etkinleştirin."
    )

    static let ru = GlobeKeyStrings(
        pageTitle: "Смена языка",
        hubDescription: "Клавиша 🌐 ведёт на нужный язык сразу, без циклического перебора раскладок: одно нажатие — первый язык, два — второй, три — третий.",
        enableToggle: "Переключать языки клавишей 🌐",
        enableCaption: "Одно, два или три нажатия включают выбранный ниже язык; долгое нажатие открывает настройки клавиатуры.",
        prerequisiteNote: "Выберите «Ничего не делать» для «Нажатие клавиши 🌐» в Системных настройках › Клавиатура, иначе macOS будет переключать раскладку сама.",
        openKeyboardSettingsButton: "Открыть настройки клавиатуры",
        gestureSection: "Жесты",
        gestureCaption: "Одиночное нажатие срабатывает примерно через треть секунды после отпускания клавиши: система ждёт, не последует ли ещё одно. Сочетания Globe с другой клавишей (Globe+стрелка, Globe+яркость) ничего не делают.",
        singlePressLabel: "Одно нажатие",
        doublePressLabel: "Двойное нажатие",
        triplePressLabel: "Тройное нажатие",
        longPressLabel: "Долгое нажатие",
        actionNothing: "Ничего",
        actionOpenSettings: "Открыть настройки клавиатуры",
        sourcePickerLabel: "Источник ввода",
        activeNow: "Работает",
        tapRefused: "macOS не разрешил Vorssaint следить за клавиатурой. Выключите и снова включите Vorssaint в Системных настройках › Конфиденциальность и безопасность › Универсальный доступ и включите это снова."
    )

    static let es = GlobeKeyStrings(
        pageTitle: "Cambio de idioma",
        hubDescription: "La tecla 🌐 lleva directamente al idioma que necesitas, sin ciclar entre distribuciones: una pulsación para el primer idioma, dos para el segundo, tres para el tercero.",
        enableToggle: "Cambiar idiomas con la tecla 🌐",
        enableCaption: "Una, dos o tres pulsaciones cambian al idioma que elijas abajo; una pulsación larga abre los ajustes del teclado.",
        prerequisiteNote: "Define «Pulsar tecla 🌐» como «No hacer nada» en Ajustes del Sistema › Teclado, o macOS también cambiará la fuente de entrada.",
        openKeyboardSettingsButton: "Abrir ajustes de Teclado",
        gestureSection: "Gestos",
        gestureCaption: "Una pulsación única llega aproximadamente un tercio de segundo después de soltar la tecla, mientras el sistema espera ver si sigue otra. Usar la tecla Globe con otra tecla (Globe+flecha, Globe+brillo) no hace nada.",
        singlePressLabel: "Pulsación única",
        doublePressLabel: "Pulsación doble",
        triplePressLabel: "Pulsación triple",
        longPressLabel: "Pulsación larga",
        actionNothing: "Nada",
        actionOpenSettings: "Abrir ajustes del teclado",
        sourcePickerLabel: "Fuente de entrada",
        activeNow: "Funcionando",
        tapRefused: "macOS no permitió a Vorssaint observar el teclado. Desactiva y reactiva Vorssaint en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad y vuelve a activar esto."
    )

    static let sk = GlobeKeyStrings(
        pageTitle: "Zmena jazyka",
        hubDescription: "Klávesa 🌐 vedie priamo na jazyk, ktorý potrebujete, bez cyklického prepinania rozložení: jedno stlačenie pre prvý jazyk, dve pre druhý, tri pre tretí.",
        enableToggle: "Prepínať jazyky klávesou 🌐",
        enableCaption: "Jedno, dve alebo tri stlačenia prepnú na jazyk zvolený nižšie; dlhé stlačenie otvorí nastavenia klávesnice.",
        prerequisiteNote: "Nastavte „Stlačenie klávesy 🌐“ na „Nerobiť nič“ v Systémových nastaveniach › Klávesnica, inak macOS prepnú zdroj vstupu tiež.",
        openKeyboardSettingsButton: "Otvoriť nastavenia klávesnice",
        gestureSection: "Gestá",
        gestureCaption: "Jedno stlačenie sa prejaví približne tretinu sekundy po uvoľnení klávesy, kým systém čaká, či príde ďalšie. Použitie klávesy Globe s inou klávesou (Globe+šípka, Globe+jas) nespraví nič.",
        singlePressLabel: "Jedno stlačenie",
        doublePressLabel: "Dvojité stlačenie",
        triplePressLabel: "Trojité stlačenie",
        longPressLabel: "Dlhé stlačenie",
        actionNothing: "Nič",
        actionOpenSettings: "Otvoriť nastavenia klávesnice",
        sourcePickerLabel: "Zdroj vstupu",
        activeNow: "Pracuje",
        tapRefused: "macOS nepovolil Vorssaint sledovať klávesnicu. Vypnite a znova zapnite Vorssaint v Systémových nastaveniach › Súkromie a zabezpečenie › Prístupnosť a zapnite to znova."
    )

    static let de = GlobeKeyStrings(
        pageTitle: "Sprachwechsel",
        hubDescription: "Die 🌐-Taste bringt dich direkt zur Sprache, die du brauchst, ohne die Layouts der Reihe nach zu durchlaufen: ein Druck für die erste Sprache, zwei für die zweite, drei für die dritte.",
        enableToggle: "Sprachen mit der 🌐-Taste wechseln",
        enableCaption: "Ein, zwei oder drei Drucke wechseln zur unten gewählten Sprache; ein langer Druck öffnet die Tastatureinstellungen.",
        prerequisiteNote: "Stelle „Drücken der 🌐-Taste“ in Systemeinstellungen › Tastatur auf „Nichts unternehmen“, sonst wechselt macOS die Eingabequelle ebenfalls.",
        openKeyboardSettingsButton: "Tastatureinstellungen öffnen",
        gestureSection: "Gesten",
        gestureCaption: "Ein einzelner Druck kommt etwa ein Drittel einer Sekunde nach dem Loslassen, während das System abwartet, ob ein weiterer folgt. Die Globe-Taste zusammen mit einer anderen Taste (Globe+Pfeil, Globe+Helligkeit) tut nichts.",
        singlePressLabel: "Einfacher Druck",
        doublePressLabel: "Doppelter Druck",
        triplePressLabel: "Dreifacher Druck",
        longPressLabel: "Langer Druck",
        actionNothing: "Nichts",
        actionOpenSettings: "Tastatureinstellungen öffnen",
        sourcePickerLabel: "Eingabequelle",
        activeNow: "Aktiv",
        tapRefused: "macOS hat nicht zugelassen, dass Vorssaint die Tastatur beobachtet. Schalte Vorssaint in Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen aus und wieder ein und aktiviere dies erneut."
    )

    static let fr = GlobeKeyStrings(
        pageTitle: "Changement de langue",
        hubDescription: "La touche 🌐 mène directement à la langue qu’il vous faut, sans passer les dispositions en revue\u{00A0}: une pression pour la première langue, deux pour la deuxième, trois pour la troisième.",
        enableToggle: "Changer de langue avec la touche 🌐",
        enableCaption: "Une, deux ou trois pressions activent la langue choisie ci-dessous\u{00A0}; une pression longue ouvre les réglages du clavier.",
        prerequisiteNote: "Dans Réglages Système › Clavier, réglez l’action de la touche 🌐 sur Ne rien faire, sinon macOS change aussi la source d’entrée.",
        openKeyboardSettingsButton: "Ouvrir les réglages Clavier",
        gestureSection: "Gestes",
        gestureCaption: "Une pression unique arrive environ un tiers de seconde après le relâchement, le temps que le système vérifie si une autre suit. Utiliser la touche Globe avec une autre touche (Globe+flèche, Globe+luminosité) ne fait rien.",
        singlePressLabel: "Pression unique",
        doublePressLabel: "Double pression",
        triplePressLabel: "Triple pression",
        longPressLabel: "Pression longue",
        actionNothing: "Rien",
        actionOpenSettings: "Ouvrir les réglages du clavier",
        sourcePickerLabel: "Source d’entrée",
        activeNow: "Actif",
        tapRefused: "macOS n’a pas autorisé Vorssaint à surveiller le clavier. Désactivez puis réactivez Vorssaint dans Réglages Système › Confidentialité et sécurité › Accessibilité, puis réactivez ceci."
    )

    static let it = GlobeKeyStrings(
        pageTitle: "Cambio lingua",
        hubDescription: "Il tasto 🌐 porta direttamente alla lingua che ti serve, senza scorrere i layout in ciclo: una pressione per la prima lingua, due per la seconda, tre per la terza.",
        enableToggle: "Cambia lingua con il tasto 🌐",
        enableCaption: "Una, due o tre pressioni attivano la lingua scelta sotto; una pressione lunga apre le impostazioni della tastiera.",
        prerequisiteNote: "Imposta «Premi il tasto 🌐» su «Non fare nulla» in Impostazioni di Sistema › Tastiera, altrimenti macOS cambia anche lui la sorgente di input.",
        openKeyboardSettingsButton: "Apri impostazioni Tastiera",
        gestureSection: "Gesti",
        gestureCaption: "Una singola pressione arriva circa un terzo di secondo dopo aver rilasciato il tasto, mentre il sistema aspetta di vedere se ne segue un’altra. Usare il tasto Globe con un altro tasto (Globe+freccia, Globe+luminosità) non fa nulla.",
        singlePressLabel: "Pressione singola",
        doublePressLabel: "Pressione doppia",
        triplePressLabel: "Pressione tripla",
        longPressLabel: "Pressione lunga",
        actionNothing: "Niente",
        actionOpenSettings: "Apri impostazioni tastiera",
        sourcePickerLabel: "Sorgente di input",
        activeNow: "Attivo",
        tapRefused: "macOS non ha permesso a Vorssaint di osservare la tastiera. Disattiva e riattiva Vorssaint in Impostazioni di Sistema › Privacy e sicurezza › Accessibilità, poi riattiva questa funzione."
    )

    static let ja = GlobeKeyStrings(
        pageTitle: "言語切り替え",
        hubDescription: "🌐キーは必要な言語へ直接切り替えます。レイアウトを順番に巡ることはありません。1回で1番目の言語、2回で2番目、3回で3番目へ。",
        enableToggle: "🌐キーで言語を切り替える",
        enableCaption: "1回・2回・3回の押下で、下で選んだ言語に切り替わります。長押しではキーボード設定を開きます。",
        prerequisiteNote: "システム設定 › キーボードで「🌐キーを押すとき」を「何もしない」に設定しないと、macOSも入力ソースを切り替えてしまいます。",
        openKeyboardSettingsButton: "キーボード設定を開く",
        gestureSection: "ジェスチャー",
        gestureCaption: "シングルプレスは、次の押下があるかシステムが待つ間、キーを放してから約3分の1秒後に確定します。Globeキーを他のキーと組み合わせても (Globe+矢印、Globe+輝度) 何もしません。",
        singlePressLabel: "1回押し",
        doublePressLabel: "2回押し",
        triplePressLabel: "3回押し",
        longPressLabel: "長押し",
        actionNothing: "何もしない",
        actionOpenSettings: "キーボード設定を開く",
        sourcePickerLabel: "入力ソース",
        activeNow: "動作中",
        tapRefused: "macOSがVorssaintによるキーボードの監視を許可しませんでした。システム設定 › プライバシーとセキュリティ › アクセシビリティでVorssaintを一度オフにしてからオンにし、もう一度有効にしてください。"
    )

    static let ko = GlobeKeyStrings(
        pageTitle: "언어 전환",
        hubDescription: "🌐 키는 필요한 언어로 곧장 전환하며 입력 소스를 순환하지 않습니다. 한 번 누르면 첫 번째 언어, 두 번은 두 번째, 세 번은 세 번째입니다.",
        enableToggle: "🌐 키로 언어 전환",
        enableCaption: "한 번, 두 번, 세 번 누르면 아래에서 고른 언어로 전환되고, 길게 누르면 키보드 설정을 엽니다.",
        prerequisiteNote: "시스템 설정 › 키보드에서 ‘🌐 키 누르기’를 ‘동작 없음’으로 설정하세요. 그러지 않으면 macOS도 입력 소스를 함께 바꿉니다.",
        openKeyboardSettingsButton: "키보드 설정 열기",
        gestureSection: "제스처",
        gestureCaption: "한 번 누르기는 시스템이 다음 누름을 기다리는 동안, 키를 뗀 후 약 3분의 1초 뒤에 확정됩니다. Globe 키를 다른 키와 함께 사용하면 (Globe+화살표, Globe+밝기) 아무 동작도 하지 않습니다.",
        singlePressLabel: "한 번 누름",
        doublePressLabel: "두 번 누름",
        triplePressLabel: "세 번 누름",
        longPressLabel: "길게 누름",
        actionNothing: "없음",
        actionOpenSettings: "키보드 설정 열기",
        sourcePickerLabel: "입력 소스",
        activeNow: "동작 중",
        tapRefused: "macOS가 Vorssaint의 키보드 관찰을 허용하지 않았습니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 Vorssaint를 끄고 다시 켠 뒤 이 기능을 다시 켜세요."
    )

    static let uk = GlobeKeyStrings(
        pageTitle: "Зміна мови",
        hubDescription: "Клавіша 🌐 веде прямо до потрібної мови, без циклічного перебирання розкладок: одне натискання — перша мова, два — друга, три — третя.",
        enableToggle: "Перемикати мови клавішею 🌐",
        enableCaption: "Одне, два або три натискання вмикають обрану нижче мову; довге натискання відкриває налаштування клавіатури.",
        prerequisiteNote: "Установіть «Натискання клавіші 🌐» на «Не робити нічого» в Системних налаштуваннях › Клавіатура, інакше macOS також перемикатиме джерело введення.",
        openKeyboardSettingsButton: "Відкрити налаштування клавіатури",
        gestureSection: "Жести",
        gestureCaption: "Одиночне натискання спрацьовує приблизно через третину секунди після відпускання клавіші: система чекає, чи не буде ще одного. Поєднання Globe з іншою клавішею (Globe+стрілка, Globe+яскравість) нічого не робить.",
        singlePressLabel: "Одне натискання",
        doublePressLabel: "Подвійне натискання",
        triplePressLabel: "Потрійне натискання",
        longPressLabel: "Довге натискання",
        actionNothing: "Нічого",
        actionOpenSettings: "Відкрити налаштування клавіатури",
        sourcePickerLabel: "Джерело введення",
        activeNow: "Працює",
        tapRefused: "macOS не дозволив Vorssaint стежити за клавіатурою. Вимкніть і знову увімкніть Vorssaint у Системних налаштуваннях › Конфіденційність і безпека › Універсальний доступ і увімкніть це знову."
    )

    static let zhHans = GlobeKeyStrings(
        pageTitle: "切换语言",
        hubDescription: "🌐 键直接切换到所需语言，无需循环切换输入方式：按一下是第一个语言，两下是第二个，三下是第三个。",
        enableToggle: "用 🌐 键切换语言",
        enableCaption: "按一下、两下或三下会切换到下方选择的语言；长按则打开键盘设置。",
        prerequisiteNote: "请在系统设置 › 键盘中将“按下 🌐 键”设为“无操作”，否则 macOS 也会自行切换输入方式。",
        openKeyboardSettingsButton: "打开键盘设置",
        gestureSection: "手势",
        gestureCaption: "单次按键会在松开键后约三分之一秒才生效，因为系统要等待是否有下一次按键。将 Globe 键与其他键同用 (Globe+方向键、Globe+亮度) 不会触发任何操作。",
        singlePressLabel: "按一下",
        doublePressLabel: "按两下",
        triplePressLabel: "按三下",
        longPressLabel: "长按",
        actionNothing: "无操作",
        actionOpenSettings: "打开键盘设置",
        sourcePickerLabel: "输入方式",
        activeNow: "正在运行",
        tapRefused: "macOS 未允许 Vorssaint 监视键盘。请在系统设置 › 隐私与安全性 › 辅助功能中关闭再打开 Vorssaint，然后重新启用此功能。"
    )

    static let zhTW = GlobeKeyStrings(
        pageTitle: "切換語言",
        hubDescription: "🌐 鍵直接切換到所需語言，無需循環切換輸入方式：按一下是第一個語言，兩下是第二個，三下是第三個。",
        enableToggle: "用 🌐 鍵切換語言",
        enableCaption: "按一下、兩下或三下會切換到下方選擇的語言；長按則開啟鍵盤設定。",
        prerequisiteNote: "請在系統設定 › 鍵盤中將「按下 🌐 鍵」設為「無動作」，否則 macOS 也會自行切換輸入方式。",
        openKeyboardSettingsButton: "打開鍵盤設定",
        gestureSection: "手勢",
        gestureCaption: "單次按鍵會在放開鍵後約三分之一秒才生效，因為系統要等待是否還有下一次按鍵。將 Globe 鍵與其他鍵併用 (Globe+方向鍵、Globe+亮度) 不會觸發任何動作。",
        singlePressLabel: "按一下",
        doublePressLabel: "按兩下",
        triplePressLabel: "按三下",
        longPressLabel: "長按",
        actionNothing: "無動作",
        actionOpenSettings: "開啟鍵盤設定",
        sourcePickerLabel: "輸入方式",
        activeNow: "執行中",
        tapRefused: "macOS 未允許 Vorssaint 監看鍵盤。請在系統設定 › 隱私權與安全性 › 輔助使用中關閉再開啟 Vorssaint，然後重新啟用此功能。"
    )

    static let zhHK = GlobeKeyStrings(
        pageTitle: "切換語言",
        hubDescription: "🌐 鍵直接切換到所需語言，唔使逐個輸入方式咁循環切換：撳一下係第一個語言，兩下係第二個，三下係第三個。",
        enableToggle: "用 🌐 鍵切換語言",
        enableCaption: "撳一下、兩下或三下會切換到下方揀選嘅語言；長撳就開啟鍵盤設定。",
        prerequisiteNote: "請喺系統設定 › 鍵盤度將「撳 🌐 鍵」設為「無動作」，否則 macOS 都會自行切換輸入方式。",
        openKeyboardSettingsButton: "開啟鍵盤設定",
        gestureSection: "手勢",
        gestureCaption: "單次按鍵會喺放開鍵之後大約三分之一秒先生效，因為系統要等埋仲有冇下一次按鍵。將 Globe 鍵同其他鍵一齊用 (Globe+方向鍵、Globe+亮度) 唔會觸發任何動作。",
        singlePressLabel: "撳一下",
        doublePressLabel: "撳兩下",
        triplePressLabel: "撳三下",
        longPressLabel: "長撳",
        actionNothing: "無動作",
        actionOpenSettings: "開啟鍵盤設定",
        sourcePickerLabel: "輸入方式",
        activeNow: "運行中",
        tapRefused: "macOS 未允許 Vorssaint 監看鍵盤。請喺系統設定 › 私隱與保安 › 輔助使用度關閉再開啟 Vorssaint，然後重新啟用此功能。"
    )
}
