// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct MissionControlActionsStrings {
    let title: String
    let pageDescription: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let rightClick: String
    let middleClick: String
    let keyboardShortcuts: String
    let keyboardShortcutsCaption: String
    let help: String
    let actionNone: String
    let actionCloseWindow: String
    let actionMinimizeWindow: String
    let actionTerminateApp: String
    let actionHideApp: String
}

extension FeatureStrings {
    static func missionControlActions(_ language: AppLanguage) -> MissionControlActionsStrings {
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

extension MissionControlActionsStrings {
    static let enUS = Self(
        title: "Mission Control", pageDescription: "Control the window under the pointer.",
        hubDescription: "Close or minimize windows, quit or hide apps in Mission Control",
        enable: "Window actions",
        enableCaption: "Adds right click, middle click, and ⌘W/Q/H/M to Mission Control.",
        rightClick: "Right click", middleClick: "Middle click",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Acts on the window under the pointer.",
        help: "Actions affect only the window under the pointer; arrow keys and Return are unchanged. The feature stays off with Stage Manager, full screen, unknown overviews, or when Mission Control shows windows from only one app. Quit is a normal request, so unsaved documents can still ask to save.",
        actionNone: "Nothing", actionCloseWindow: "Close window",
        actionMinimizeWindow: "Minimize window", actionTerminateApp: "Quit app",
        actionHideApp: "Hide app"
    )

    static let de = Self(
        title: "Mission Control", pageDescription: "Steuere das Fenster unter dem Zeiger.",
        hubDescription: "Fenster in Mission Control schließen oder im Dock ablegen, Apps beenden oder ausblenden",
        enable: "Fensteraktionen",
        enableCaption: "Belegt Rechts- und Mittelklick sowie ⌘W/Q/H/M in Mission Control.",
        rightClick: "Rechtsklick", middleClick: "Mittelklick",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Wirkt auf das Fenster unter dem Zeiger.",
        help: "Aktionen gelten nur für das Fenster unter dem Zeiger; Pfeiltasten und Eingabetaste bleiben unverändert. Bei aktivem Stage Manager, im Vollbild, in unbekannten Übersichten oder wenn Mission Control nur Fenster einer App zeigt, greift die Funktion nicht. „App beenden“ beendet regulär und lässt Sicherungsdialoge offen.",
        actionNone: "Nichts", actionCloseWindow: "Fenster schließen",
        actionMinimizeWindow: "Im Dock ablegen", actionTerminateApp: "App beenden",
        actionHideApp: "App ausblenden"
    )

    static let ptBR = Self(
        title: "Mission Control", pageDescription: "Controle a janela sob o ponteiro.",
        hubDescription: "Feche ou minimize janelas e encerre ou oculte apps no Mission Control",
        enable: "Ações de janela",
        enableCaption: "Adiciona clique direito, clique do meio e ⌘W/Q/H/M ao Mission Control.",
        rightClick: "Clique direito", middleClick: "Clique do meio",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Age na janela sob o ponteiro.",
        help: "As ações afetam apenas a janela sob o ponteiro; as setas e a tecla de retorno não mudam. O recurso não atua com o Stage Manager, em tela cheia, em visões não reconhecidas ou quando o Mission Control mostra janelas de apenas um app. Encerrar é um pedido normal; documentos não salvos ainda podem pedir para salvar.",
        actionNone: "Nada", actionCloseWindow: "Fechar janela",
        actionMinimizeWindow: "Minimizar janela", actionTerminateApp: "Encerrar app",
        actionHideApp: "Ocultar app"
    )

    static let tr = Self(
        title: "Mission Control", pageDescription: "İşaretçinin altındaki pencereyi denetleyin.",
        hubDescription: "Mission Control’da pencereleri kapatın veya küçültün, uygulamalardan çıkın veya onları gizleyin",
        enable: "Pencere işlemleri",
        enableCaption: "Mission Control’a sağ tıklama, orta tıklama ve ⌘W/Q/H/M ekler.",
        rightClick: "Sağ tıklama", middleClick: "Orta tıklama",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "İşaretçinin altındaki pencereye uygulanır.",
        help: "İşlemler yalnızca işaretçinin altındaki pencereyi etkiler; ok tuşları ve giriş tuşu değişmez. Stage Manager açıkken, tam ekranda, tanınmayan genel görünümlerde veya Mission Control yalnızca bir uygulamanın pencerelerini gösterdiğinde özellik çalışmaz. Çıkış normal bir istektir; kaydedilmemiş belgeler yine kaydetmeyi sorabilir.",
        actionNone: "Hiçbir şey", actionCloseWindow: "Pencereyi kapat",
        actionMinimizeWindow: "Pencereyi küçült", actionTerminateApp: "Uygulamadan çık",
        actionHideApp: "Uygulamayı gizle"
    )

    static let ru = Self(
        title: "Mission Control", pageDescription: "Управляйте окном под указателем.",
        hubDescription: "Закрывайте и сворачивайте окна, завершайте или скрывайте приложения в Mission Control",
        enable: "Действия с окнами",
        enableCaption: "Добавляет в Mission Control правый и средний щелчки, а также ⌘W/Q/H/M.",
        rightClick: "Щелчок правой кнопкой", middleClick: "Щелчок средней кнопкой",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Действует на окно под указателем.",
        help: "Действия затрагивают только окно под указателем; клавиши со стрелками и ввода не меняются. Функция не работает со Stage Manager, в полноэкранном режиме, в неизвестных обзорах или когда Mission Control показывает окна только одного приложения. Завершение является обычным запросом, поэтому несохранённый документ может запросить сохранение.",
        actionNone: "Ничего", actionCloseWindow: "Закрыть окно",
        actionMinimizeWindow: "Свернуть окно", actionTerminateApp: "Завершить приложение",
        actionHideApp: "Скрыть приложение"
    )

    static let es = Self(
        title: "Mission Control", pageDescription: "Controla la ventana bajo el puntero.",
        hubDescription: "Cierra o minimiza ventanas y sal u oculta apps en Mission Control",
        enable: "Acciones de ventana",
        enableCaption: "Añade clic derecho, clic central y ⌘W/Q/H/M a Mission Control.",
        rightClick: "Clic derecho", middleClick: "Clic central",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Actúa sobre la ventana bajo el puntero.",
        help: "Las acciones solo afectan a la ventana bajo el puntero; las flechas y la tecla Intro no cambian. La función no actúa con Stage Manager, a pantalla completa, en vistas no reconocidas o cuando Mission Control muestra ventanas de una sola app. Salir es una petición normal; los documentos sin guardar aún pueden pedir guardarse.",
        actionNone: "Nada", actionCloseWindow: "Cerrar ventana",
        actionMinimizeWindow: "Minimizar ventana", actionTerminateApp: "Salir de la app",
        actionHideApp: "Ocultar app"
    )

    static let sk = Self(
        title: "Mission Control", pageDescription: "Ovládajte okno pod ukazovateľom.",
        hubDescription: "Zatvárajte a minimalizujte okná alebo ukončujte a skrývajte aplikácie v Mission Control",
        enable: "Akcie okien",
        enableCaption: "Pridá do Mission Control pravé a stredné kliknutie a ⌘W/Q/H/M.",
        rightClick: "Pravé kliknutie", middleClick: "Stredné kliknutie",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Pôsobí na okno pod ukazovateľom.",
        help: "Akcie ovplyvnia iba okno pod ukazovateľom; šípky a kláves potvrdenia sa nemenia. Funkcia nezasahuje pri Stage Manageri, na celej obrazovke, v nerozpoznaných prehľadoch ani vtedy, keď Mission Control zobrazuje okná iba jednej aplikácie. Ukončenie je bežná žiadosť, takže neuložené dokumenty môžu požiadať o uloženie.",
        actionNone: "Nič", actionCloseWindow: "Zatvoriť okno",
        actionMinimizeWindow: "Minimalizovať okno", actionTerminateApp: "Ukončiť aplikáciu",
        actionHideApp: "Skryť aplikáciu"
    )

    static let fr = Self(
        title: "Mission Control", pageDescription: "Contrôlez la fenêtre sous le pointeur.",
        hubDescription: "Fermez ou réduisez une fenêtre, quittez ou masquez une app dans Mission Control",
        enable: "Actions de fenêtre",
        enableCaption: "Ajoute le clic droit, le clic du milieu et ⌘W/Q/H/M à Mission Control.",
        rightClick: "Clic droit", middleClick: "Clic du milieu",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Agit sur la fenêtre sous le pointeur.",
        help: "Les actions touchent uniquement la fenêtre sous le pointeur ; les flèches et la touche Entrée ne changent pas. La fonction reste inactive avec Stage Manager, en plein écran, dans les vues non reconnues ou lorsque Mission Control n’affiche que les fenêtres d’une seule app. Quitter reste une demande normale : un document non enregistré peut encore proposer de l’être.",
        actionNone: "Rien", actionCloseWindow: "Fermer la fenêtre",
        actionMinimizeWindow: "Réduire la fenêtre", actionTerminateApp: "Quitter l’app",
        actionHideApp: "Masquer l’app"
    )

    static let it = Self(
        title: "Mission Control", pageDescription: "Controlla la finestra sotto il puntatore.",
        hubDescription: "Chiudi o contrai finestre, esci o nascondi app in Mission Control",
        enable: "Azioni finestra",
        enableCaption: "Aggiunge clic destro, clic centrale e ⌘W/Q/H/M a Mission Control.",
        rightClick: "Clic destro", middleClick: "Clic centrale",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Agisce sulla finestra sotto il puntatore.",
        help: "Le azioni riguardano solo la finestra sotto il puntatore; frecce e tasto Invio non cambiano. La funzione non interviene con Stage Manager, a schermo intero, nelle viste non riconosciute o quando Mission Control mostra le finestre di una sola app. Uscire è una richiesta normale: i documenti non salvati possono ancora chiedere il salvataggio.",
        actionNone: "Niente", actionCloseWindow: "Chiudi finestra",
        actionMinimizeWindow: "Contrai finestra", actionTerminateApp: "Esci dall’app",
        actionHideApp: "Nascondi app"
    )

    static let ja = Self(
        title: "Mission Control", pageDescription: "ポインタの下にあるウインドウを操作します。",
        hubDescription: "Mission Control でウインドウを閉じる／しまう、アプリを終了／非表示にする",
        enable: "ウインドウ操作",
        enableCaption: "Mission Control に右クリック、中クリック、⌘W/Q/H/M を追加します。",
        rightClick: "右クリック", middleClick: "中クリック",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "ポインタの下のウインドウに作用します。",
        help: "操作対象はポインタの下のウインドウだけで、矢印キーと確定キーは変わりません。Stage Manager、フルスクリーン、判別できない一覧、または1つのアプリのウインドウだけを表示する Mission Control では機能しません。終了は通常の要求なので、未保存の書類は保存を確認できます。",
        actionNone: "何もしない", actionCloseWindow: "ウインドウを閉じる",
        actionMinimizeWindow: "ウインドウをしまう", actionTerminateApp: "アプリを終了",
        actionHideApp: "アプリを非表示"
    )

    static let ko = Self(
        title: "Mission Control", pageDescription: "포인터 아래의 윈도우를 조작합니다.",
        hubDescription: "Mission Control에서 윈도우를 닫거나 축소하고 앱을 종료하거나 가리기",
        enable: "윈도우 동작",
        enableCaption: "Mission Control에 오른쪽 클릭, 가운데 클릭, ⌘W/Q/H/M을 추가합니다.",
        rightClick: "오른쪽 클릭", middleClick: "가운데 클릭",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "포인터 아래의 윈도우에 적용됩니다.",
        help: "동작은 포인터 아래의 윈도우에만 적용되며 화살표 키와 입력 키는 변하지 않습니다. Stage Manager, 전체 화면, 인식하지 못한 개요 또는 한 앱의 윈도우만 표시하는 Mission Control에서는 기능이 작동하지 않습니다. 종료는 일반 요청이므로 저장하지 않은 문서는 저장 여부를 물을 수 있습니다.",
        actionNone: "아무것도 안 함", actionCloseWindow: "윈도우 닫기",
        actionMinimizeWindow: "윈도우 축소", actionTerminateApp: "앱 종료",
        actionHideApp: "앱 가리기"
    )

    static let uk = Self(
        title: "Mission Control", pageDescription: "Керуйте вікном під вказівником.",
        hubDescription: "Закривайте й згортайте вікна, завершуйте або приховуйте програми в Mission Control",
        enable: "Дії з вікнами",
        enableCaption: "Додає в Mission Control клацання правою й середньою кнопками та ⌘W/Q/H/M.",
        rightClick: "Клацання правою кнопкою", middleClick: "Клацання середньою кнопкою",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "Діє на вікно під вказівником.",
        help: "Дії впливають лише на вікно під вказівником; клавіші зі стрілками та введення не змінюються. Функція не діє зі Stage Manager, у повноекранному режимі, у нерозпізнаних оглядах або коли Mission Control показує вікна лише однієї програми. Завершення є звичайним запитом, тому незбережений документ може запропонувати збереження.",
        actionNone: "Нічого", actionCloseWindow: "Закрити вікно",
        actionMinimizeWindow: "Згорнути вікно", actionTerminateApp: "Завершити програму",
        actionHideApp: "Приховати програму"
    )

    static let zhHans = Self(
        title: "调度中心", pageDescription: "操作指针下方的窗口。",
        hubDescription: "在调度中心关闭或最小化窗口，以及退出或隐藏 App",
        enable: "窗口操作",
        enableCaption: "为调度中心添加右键、中键和 ⌘W/Q/H/M。",
        rightClick: "右键点按", middleClick: "中键点按",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "作用于指针下方的窗口。",
        help: "操作只影响指针下方的窗口；方向键和回车键保持不变。启用台前调度、全屏、无法识别的概览，或调度中心只显示一个 App 的窗口时，此功能不会介入。退出是普通请求，未存储的文稿仍可询问是否存储。",
        actionNone: "无操作", actionCloseWindow: "关闭窗口",
        actionMinimizeWindow: "最小化窗口", actionTerminateApp: "退出 App",
        actionHideApp: "隐藏 App"
    )

    static let zhTW = Self(
        title: "指揮中心", pageDescription: "操作指標下方的視窗。",
        hubDescription: "在指揮中心關閉或縮小視窗，以及結束或隱藏 App",
        enable: "視窗動作",
        enableCaption: "為指揮中心加入右鍵、中鍵和 ⌘W/Q/H/M。",
        rightClick: "右鍵點按", middleClick: "中鍵點按",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "作用於指標下方的視窗。",
        help: "動作只影響指標下方的視窗；方向鍵和換行鍵保持不變。啟用「幕前調度」、全螢幕、無法辨識的概覽，或指揮中心只顯示一個 App 的視窗時，此功能不會介入。結束是一般要求，未儲存的文件仍可詢問是否儲存。",
        actionNone: "不執行", actionCloseWindow: "關閉視窗",
        actionMinimizeWindow: "縮小視窗", actionTerminateApp: "結束 App",
        actionHideApp: "隱藏 App"
    )

    static let zhHK = Self(
        title: "指揮中心", pageDescription: "操作指標下方的視窗。",
        hubDescription: "在指揮中心關閉或縮小視窗，以及結束或隱藏 App",
        enable: "視窗動作",
        enableCaption: "為指揮中心加入右鍵、中鍵和 ⌘W/Q/H/M。",
        rightClick: "右鍵點按", middleClick: "中鍵點按",
        keyboardShortcuts: "⌘W/Q/H/M",
        keyboardShortcutsCaption: "作用於指標下方的視窗。",
        help: "動作只影響指標下方的視窗；方向鍵和換行鍵保持不變。啟用「幕前管理」、全螢幕、無法辨識的概覽，或指揮中心只顯示一個 App 的視窗時，此功能不會介入。結束是一般要求，未儲存的文件仍可詢問是否儲存。",
        actionNone: "不執行", actionCloseWindow: "關閉視窗",
        actionMinimizeWindow: "縮小視窗", actionTerminateApp: "結束 App",
        actionHideApp: "隱藏 App"
    )
}
