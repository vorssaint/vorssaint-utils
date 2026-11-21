// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AutoFullscreenStrings {
    let name: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let activeNow: String
    let howTitle: String
    let stepWindow: String
    let stepWait: String
    let predictableNote: String
    let builtInDisplayOnly: String
    let builtInDisplayOnlyCaption: String
    let exceptionsTitle: String
    let exceptionsEmpty: String
    let exceptionsCaption: String
    let addApp: String
    let removeApp: String
}

extension FeatureStrings {
    static func autoFullscreen(_ language: AppLanguage) -> AutoFullscreenStrings {
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

extension AutoFullscreenStrings {
    static let enUS = AutoFullscreenStrings(
        name: "Full screen on launch",
        hubDescription: "Open apps in full screen when they launch",
        enable: "Open apps in full screen",
        enableCaption: "When an app launches, its first window enters macOS full screen.",
        activeNow: "Watching for app launches",
        howTitle: "How it works",
        stepWindow: "When an app opens its first window, Vorssaint asks macOS to put that window in full screen, in a Space of its own.",
        stepWait: "Apps that are slow to open get up to 15 seconds for their window to appear. Apps opened in the background or hidden, and windows that can’t enter full screen, are left alone.",
        predictableNote: "Only the first window after launch is affected. Leave full screen as usual and the app stays that way.",
        builtInDisplayOnly: "Only on the built-in display",
        builtInDisplayOnlyCaption: "Skips apps that launch while an external display is connected, including with the lid closed. Turn this off on a Mac without a built-in display.",
        exceptionsTitle: "Exceptions",
        exceptionsEmpty: "No exceptions yet.",
        exceptionsCaption: "Apps on this list open the way they normally do.",
        addApp: "Add an app…",
        removeApp: "Remove"
    )

    static let ptBR = AutoFullscreenStrings(
        name: "Tela cheia ao abrir",
        hubDescription: "Abre os apps em tela cheia ao iniciar",
        enable: "Abrir apps em tela cheia",
        enableCaption: "Quando um app abre, a primeira janela entra na tela cheia do macOS.",
        activeNow: "Observando a abertura de apps",
        howTitle: "Como funciona",
        stepWindow: "Quando um app abre a primeira janela, o Vorssaint pede ao macOS para colocá-la em tela cheia, em um Espaço próprio.",
        stepWait: "Apps que demoram a abrir têm até 15 segundos para mostrar a janela. Apps abertos em segundo plano ou ocultos, e janelas que não entram em tela cheia, ficam como estão.",
        predictableNote: "Só a primeira janela depois de abrir é afetada. Saia da tela cheia normalmente e o app continua assim.",
        builtInDisplayOnly: "Somente na tela integrada",
        builtInDisplayOnlyCaption: "Ignora apps abertos enquanto uma tela externa está conectada, inclusive com a tampa fechada. Desative em um Mac sem tela integrada.",
        exceptionsTitle: "Exceções",
        exceptionsEmpty: "Nenhuma exceção ainda.",
        exceptionsCaption: "Os apps desta lista abrem do jeito de sempre.",
        addApp: "Adicionar app…",
        removeApp: "Remover"
    )

    static let tr = AutoFullscreenStrings(
        name: "Açılışta tam ekran",
        hubDescription: "Uygulamaları açılırken tam ekranda başlatır",
        enable: "Uygulamaları tam ekranda aç",
        enableCaption: "Bir uygulama açıldığında ilk penceresi macOS tam ekranına geçer.",
        activeNow: "Uygulama açılışları izleniyor",
        howTitle: "Nasıl çalışır",
        stepWindow: "Bir uygulama ilk penceresini açtığında Vorssaint, macOS’ten bu pencereyi kendi Alanı’nda tam ekrana almasını ister.",
        stepWait: "Geç açılan uygulamaların penceresi için 15 saniyeye kadar beklenir. Arka planda veya gizli açılan uygulamalara ve tam ekrana geçemeyen pencerelere dokunulmaz.",
        predictableNote: "Yalnızca açılıştan sonraki ilk pencere etkilenir. Tam ekrandan her zamanki gibi çıkın, uygulama öyle kalır.",
        builtInDisplayOnly: "Yalnızca dahili ekranda",
        builtInDisplayOnlyCaption: "Harici ekran bağlıyken, kapak kapalıyken de dahil, açılan uygulamaları atlar. Dahili ekranı olmayan bir Mac’te bunu kapatın.",
        exceptionsTitle: "İstisnalar",
        exceptionsEmpty: "Henüz istisna yok.",
        exceptionsCaption: "Bu listedeki uygulamalar her zamanki gibi açılır.",
        addApp: "Uygulama ekle…",
        removeApp: "Kaldır"
    )

    static let ru = AutoFullscreenStrings(
        name: "Полный экран при запуске",
        hubDescription: "Открывает приложения в полноэкранном режиме при запуске",
        enable: "Открывать приложения на весь экран",
        enableCaption: "При запуске приложения его первое окно переходит в полноэкранный режим macOS.",
        activeNow: "Отслеживает запуск приложений",
        howTitle: "Как это работает",
        stepWindow: "Когда приложение открывает первое окно, Vorssaint просит macOS развернуть его на весь экран в отдельном пространстве.",
        stepWait: "Медленно запускающимся приложениям даётся до 15 секунд на появление окна. Приложения, запущенные в фоне или скрытыми, и окна без полноэкранного режима не затрагиваются.",
        predictableNote: "Затрагивается только первое окно после запуска. Выйдите из полноэкранного режима как обычно, и приложение так и останется.",
        builtInDisplayOnly: "Только на встроенном дисплее",
        builtInDisplayOnlyCaption: "Пропускает приложения, запущенные при подключённом внешнем дисплее, в том числе с закрытой крышкой. Выключите на Mac без встроенного дисплея.",
        exceptionsTitle: "Исключения",
        exceptionsEmpty: "Исключений пока нет.",
        exceptionsCaption: "Приложения из этого списка открываются как обычно.",
        addApp: "Добавить приложение…",
        removeApp: "Удалить"
    )

    static let es = AutoFullscreenStrings(
        name: "Pantalla completa al abrir",
        hubDescription: "Abre las apps en pantalla completa al iniciarse",
        enable: "Abrir apps en pantalla completa",
        enableCaption: "Cuando se abre una app, su primera ventana pasa a pantalla completa de macOS.",
        activeNow: "Atento a las apps que se abren",
        howTitle: "Cómo funciona",
        stepWindow: "Cuando una app abre su primera ventana, Vorssaint pide a macOS que la ponga en pantalla completa, en un Espacio propio.",
        stepWait: "Las apps que tardan en abrirse tienen hasta 15 segundos para mostrar su ventana. Las apps abiertas en segundo plano u ocultas, y las ventanas que no admiten pantalla completa, no se tocan.",
        predictableNote: "Solo afecta a la primera ventana tras abrir la app. Sal de pantalla completa como siempre y la app se queda así.",
        builtInDisplayOnly: "Solo en la pantalla integrada",
        builtInDisplayOnlyCaption: "Omite las apps que se abren con una pantalla externa conectada, también con la tapa cerrada. Desactívalo en un Mac sin pantalla integrada.",
        exceptionsTitle: "Excepciones",
        exceptionsEmpty: "Todavía no hay excepciones.",
        exceptionsCaption: "Las apps de esta lista se abren como siempre.",
        addApp: "Añadir app…",
        removeApp: "Eliminar"
    )

    static let sk = AutoFullscreenStrings(
        name: "Celá obrazovka pri spustení",
        hubDescription: "Otvára aplikácie pri spustení na celej obrazovke",
        enable: "Otvárať aplikácie na celej obrazovke",
        enableCaption: "Keď sa aplikácia spustí, jej prvé okno prejde do režimu celej obrazovky macOS.",
        activeNow: "Sleduje spúšťanie aplikácií",
        howTitle: "Ako to funguje",
        stepWindow: "Keď aplikácia otvorí prvé okno, Vorssaint požiada macOS, aby ho zobrazil na celej obrazovke vo vlastnej ploche.",
        stepWait: "Pomaly sa otvárajúce aplikácie majú na zobrazenie okna až 15 sekúnd. Aplikácie spustené na pozadí alebo skryté a okná, ktoré nemôžu prejsť na celú obrazovku, zostanú bez zmeny.",
        predictableNote: "Týka sa to iba prvého okna po spustení. Celú obrazovku ukončite ako zvyčajne a aplikácia tak zostane.",
        builtInDisplayOnly: "Iba na vstavanom displeji",
        builtInDisplayOnlyCaption: "Preskočí aplikácie spustené, keď je pripojený externý displej, aj so zatvoreným vekom. Na Macu bez vstavaného displeja túto voľbu vypnite.",
        exceptionsTitle: "Výnimky",
        exceptionsEmpty: "Zatiaľ žiadne výnimky.",
        exceptionsCaption: "Aplikácie v tomto zozname sa otvárajú ako zvyčajne.",
        addApp: "Pridať aplikáciu…",
        removeApp: "Odstrániť"
    )

    static let de = AutoFullscreenStrings(
        name: "Vollbild beim Start",
        hubDescription: "Öffnet Apps beim Start im Vollbildmodus",
        enable: "Apps im Vollbild öffnen",
        enableCaption: "Wenn eine App startet, wechselt ihr erstes Fenster in den Vollbildmodus von macOS.",
        activeNow: "Achtet auf startende Apps",
        howTitle: "So funktioniert’s",
        stepWindow: "Öffnet eine App ihr erstes Fenster, bittet Vorssaint macOS, dieses Fenster im Vollbild in einem eigenen Space zu zeigen.",
        stepWait: "Langsam startende Apps haben bis zu 15 Sekunden Zeit, ihr Fenster zu zeigen. Im Hintergrund oder ausgeblendet gestartete Apps und Fenster ohne Vollbildmodus bleiben unverändert.",
        predictableNote: "Nur das erste Fenster nach dem Start ist betroffen. Beende das Vollbild wie gewohnt, dann bleibt die App so.",
        builtInDisplayOnly: "Nur auf dem integrierten Display",
        builtInDisplayOnlyCaption: "Überspringt Apps, die starten, während ein externes Display angeschlossen ist, auch bei geschlossenem Deckel. Auf einem Mac ohne integriertes Display ausschalten.",
        exceptionsTitle: "Ausnahmen",
        exceptionsEmpty: "Noch keine Ausnahmen.",
        exceptionsCaption: "Apps auf dieser Liste öffnen sich wie gewohnt.",
        addApp: "App hinzufügen …",
        removeApp: "Entfernen"
    )

    static let fr = AutoFullscreenStrings(
        name: "Plein écran à l’ouverture",
        hubDescription: "Ouvre les apps en plein écran à leur lancement",
        enable: "Ouvrir les apps en plein écran",
        enableCaption: "Au lancement d’une app, sa première fenêtre passe en plein écran macOS.",
        activeNow: "Surveille le lancement des apps",
        howTitle: "Fonctionnement",
        stepWindow: "Quand une app ouvre sa première fenêtre, Vorssaint demande à macOS de la passer en plein écran, dans un Space dédié.",
        stepWait: "Les apps lentes à s’ouvrir ont jusqu’à 15 secondes pour afficher leur fenêtre. Les apps lancées en arrière-plan ou masquées, et les fenêtres sans plein écran, ne sont pas touchées.",
        predictableNote: "Seule la première fenêtre après le lancement est concernée. Quittez le plein écran comme d’habitude et l’app reste ainsi.",
        builtInDisplayOnly: "Uniquement sur l’écran intégré",
        builtInDisplayOnlyCaption: "Ignore les apps lancées lorsqu’un écran externe est connecté, y compris capot fermé. Désactivez cette option sur un Mac sans écran intégré.",
        exceptionsTitle: "Exceptions",
        exceptionsEmpty: "Aucune exception pour l’instant.",
        exceptionsCaption: "Les apps de cette liste s’ouvrent normalement.",
        addApp: "Ajouter une app…",
        removeApp: "Supprimer"
    )

    static let it = AutoFullscreenStrings(
        name: "Schermo intero all’avvio",
        hubDescription: "Apre le app a schermo intero all’avvio",
        enable: "Apri le app a schermo intero",
        enableCaption: "All’avvio di un’app, la sua prima finestra passa a schermo intero di macOS.",
        activeNow: "In attesa dell’avvio delle app",
        howTitle: "Come funziona",
        stepWindow: "Quando un’app apre la prima finestra, Vorssaint chiede a macOS di metterla a schermo intero, in uno Spazio dedicato.",
        stepWait: "Le app lente ad aprirsi hanno fino a 15 secondi per mostrare la finestra. Le app avviate in background o nascoste, e le finestre senza schermo intero, restano come sono.",
        predictableNote: "Riguarda solo la prima finestra dopo l’avvio. Esci dallo schermo intero come sempre e l’app resta così.",
        builtInDisplayOnly: "Solo sul display integrato",
        builtInDisplayOnlyCaption: "Salta le app avviate mentre è collegato un display esterno, anche a coperchio chiuso. Disattivalo su un Mac senza display integrato.",
        exceptionsTitle: "Eccezioni",
        exceptionsEmpty: "Ancora nessuna eccezione.",
        exceptionsCaption: "Le app in questo elenco si aprono come al solito.",
        addApp: "Aggiungi app…",
        removeApp: "Rimuovi"
    )

    static let ja = AutoFullscreenStrings(
        name: "起動時にフルスクリーン",
        hubDescription: "App を起動時にフルスクリーンで開く",
        enable: "App をフルスクリーンで開く",
        enableCaption: "App を起動すると、最初のウインドウが macOS のフルスクリーンになります。",
        activeNow: "App の起動を監視中",
        howTitle: "仕組み",
        stepWindow: "App が最初のウインドウを開くと、Vorssaint は macOS にそのウインドウを専用の操作スペースでフルスクリーンにするよう依頼します。",
        stepWait: "起動に時間がかかる App は、ウインドウが表示されるまで最大 15 秒待ちます。バックグラウンドや非表示で起動した App、フルスクリーンにできないウインドウはそのままです。",
        predictableNote: "対象は起動後の最初のウインドウだけです。いつもどおりフルスクリーンを解除すれば、その App はそのままになります。",
        builtInDisplayOnly: "内蔵ディスプレイのみ",
        builtInDisplayOnlyCaption: "外部ディスプレイの接続中（蓋を閉じた状態を含む）に起動した App は対象外です。内蔵ディスプレイのない Mac ではオフにしてください。",
        exceptionsTitle: "例外",
        exceptionsEmpty: "例外はまだありません。",
        exceptionsCaption: "このリストの App は通常どおり開きます。",
        addApp: "App を追加…",
        removeApp: "削除"
    )

    static let ko = AutoFullscreenStrings(
        name: "실행 시 전체 화면",
        hubDescription: "앱을 실행할 때 전체 화면으로 열기",
        enable: "앱을 전체 화면으로 열기",
        enableCaption: "앱을 실행하면 첫 번째 윈도우가 macOS 전체 화면으로 전환됩니다.",
        activeNow: "앱 실행을 감지하는 중",
        howTitle: "작동 방식",
        stepWindow: "앱이 첫 번째 윈도우를 열면 Vorssaint가 macOS에 해당 윈도우를 별도의 데스크탑 공간에서 전체 화면으로 전환하도록 요청합니다.",
        stepWait: "느리게 열리는 앱은 윈도우가 나타날 때까지 최대 15초를 기다립니다. 백그라운드에서 또는 가려진 채로 실행된 앱과 전체 화면을 지원하지 않는 윈도우는 그대로 둡니다.",
        predictableNote: "실행 후 첫 번째 윈도우에만 적용됩니다. 평소처럼 전체 화면을 종료하면 앱은 그 상태로 유지됩니다.",
        builtInDisplayOnly: "내장 디스플레이에서만",
        builtInDisplayOnlyCaption: "외장 디스플레이가 연결된 상태(덮개를 닫은 경우 포함)에서 실행된 앱은 건너뜁니다. 내장 디스플레이가 없는 Mac에서는 끄십시오.",
        exceptionsTitle: "예외",
        exceptionsEmpty: "아직 예외가 없습니다.",
        exceptionsCaption: "이 목록의 앱은 평소처럼 열립니다.",
        addApp: "앱 추가…",
        removeApp: "제거"
    )

    static let uk = AutoFullscreenStrings(
        name: "Повний екран під час запуску",
        hubDescription: "Відкривати програми на весь екран під час запуску",
        enable: "Відкривати програми на весь екран",
        enableCaption: "Під час запуску програми її перше вікно переходить у повноекранний режим macOS.",
        activeNow: "Стежить за запуском програм",
        howTitle: "Як це працює",
        stepWindow: "Коли програма відкриває перше вікно, Vorssaint просить macOS розгорнути його на весь екран в окремому просторі.",
        stepWait: "Програмам, які довго відкриваються, дається до 15 секунд на появу вікна. Програми, запущені у фоні або прихованими, і вікна без повноекранного режиму залишаються як є.",
        predictableNote: "Стосується лише першого вікна після запуску. Вийдіть із повноекранного режиму як зазвичай, і програма так і залишиться.",
        builtInDisplayOnly: "Лише на вбудованому дисплеї",
        builtInDisplayOnlyCaption: "Пропускає програми, запущені з підключеним зовнішнім дисплеєм, зокрема із закритою кришкою. Вимкніть на Mac без вбудованого дисплея.",
        exceptionsTitle: "Винятки",
        exceptionsEmpty: "Винятків поки немає.",
        exceptionsCaption: "Програми з цього списку відкриваються як зазвичай.",
        addApp: "Додати програму…",
        removeApp: "Вилучити"
    )

    static let zhHans = AutoFullscreenStrings(
        name: "启动时全屏",
        hubDescription: "App 启动时以全屏打开",
        enable: "以全屏打开 App",
        enableCaption: "App 启动时，其第一个窗口会进入 macOS 全屏。",
        activeNow: "正在留意 App 启动",
        howTitle: "工作方式",
        stepWindow: "App 打开第一个窗口时，Vorssaint 会请求 macOS 将该窗口在独立的空间中全屏显示。",
        stepWait: "打开较慢的 App 最多有 15 秒时间显示窗口。在后台或以隐藏方式启动的 App，以及无法全屏的窗口保持不变。",
        predictableNote: "只影响启动后的第一个窗口。照常退出全屏后，App 会保持该状态。",
        builtInDisplayOnly: "仅在内建显示器上",
        builtInDisplayOnlyCaption: "连接外接显示器时（包括合上机盖）启动的 App 会被跳过。在没有内建显示器的 Mac 上请关闭此选项。",
        exceptionsTitle: "例外",
        exceptionsEmpty: "暂无例外。",
        exceptionsCaption: "此列表中的 App 按常规方式打开。",
        addApp: "添加 App…",
        removeApp: "移除"
    )

    static let zhTW = AutoFullscreenStrings(
        name: "啟動時全螢幕",
        hubDescription: "App 啟動時以全螢幕開啟",
        enable: "以全螢幕開啟 App",
        enableCaption: "App 啟動時，其第一個視窗會進入 macOS 全螢幕。",
        activeNow: "正在留意 App 啟動",
        howTitle: "運作方式",
        stepWindow: "App 開啟第一個視窗時，Vorssaint 會請 macOS 將該視窗在獨立的空間中以全螢幕顯示。",
        stepWait: "開啟較慢的 App 最多有 15 秒時間顯示視窗。在背景或以隱藏方式啟動的 App，以及無法全螢幕的視窗維持不變。",
        predictableNote: "只影響啟動後的第一個視窗。照常結束全螢幕後，App 會維持該狀態。",
        builtInDisplayOnly: "僅在內建顯示器上",
        builtInDisplayOnlyCaption: "連接外接顯示器時（包括闔上螢幕）啟動的 App 會略過。在沒有內建顯示器的 Mac 上請關閉此選項。",
        exceptionsTitle: "例外",
        exceptionsEmpty: "目前沒有例外。",
        exceptionsCaption: "此列表中的 App 會照常開啟。",
        addApp: "加入 App…",
        removeApp: "移除"
    )

    static let zhHK = AutoFullscreenStrings(
        name: "啟動時全螢幕",
        hubDescription: "App 啟動時以全螢幕開啟",
        enable: "以全螢幕開啟 App",
        enableCaption: "App 啟動時，其第一個視窗會進入 macOS 全螢幕。",
        activeNow: "正在留意 App 啟動",
        howTitle: "運作方式",
        stepWindow: "App 開啟第一個視窗時，Vorssaint 會要求 macOS 將該視窗在獨立的空間中以全螢幕顯示。",
        stepWait: "開啟較慢的 App 最多有 15 秒時間顯示視窗。在背景或以隱藏方式啟動的 App，以及無法全螢幕的視窗保持不變。",
        predictableNote: "只影響啟動後的第一個視窗。照常結束全螢幕後，App 會保持該狀態。",
        builtInDisplayOnly: "只限內置顯示器",
        builtInDisplayOnlyCaption: "連接外置顯示器時（包括合上機蓋）啟動的 App 會略過。在沒有內置顯示器的 Mac 上請關閉此選項。",
        exceptionsTitle: "例外",
        exceptionsEmpty: "暫時沒有例外。",
        exceptionsCaption: "此列表中的 App 會照常開啟。",
        addApp: "加入 App…",
        removeApp: "移除"
    )
}
