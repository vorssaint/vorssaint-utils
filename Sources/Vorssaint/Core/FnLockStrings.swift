// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FnLockStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let appsTitle: String
    let appsCaption: String
    let activeNow: String
    let pausedNote: String
    let testSection: String
    let testEmpty: String
    let testClear: String
}

extension FeatureStrings {
    static func fnLock(_ language: AppLanguage) -> FnLockStrings {
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

extension FnLockStrings {
    static let enUS = FnLockStrings(
        pageTitle: "Per-app function keys",
        hubDescription: "Use F1–F12 as function keys in some apps and as media keys in others.",
        enableToggle: "Switch the function row per app",
        enableCaption: "Add the apps that should get the opposite of the system’s F-key setting. The keys flip the moment you switch to one of them.",
        appsTitle: "Flip the keys in these apps",
        appsCaption: "In these apps, F1–F12 switch to the behavior the system’s checkbox does not give them.",
        activeNow: "Engaged for the app in front",
        pausedNote: "Outside the listed apps the keys follow the system’s checkbox.",
        testSection: "Key test",
        testEmpty: "Switch to one of the listed apps and press its function keys: each translation lands here, with the key it became.",
        testClear: "Clear",
    )

    static let ptBR = FnLockStrings(
        pageTitle: "Teclas de função por app",
        hubDescription: "Use F1–F12 como teclas de função em alguns apps e como teclas de mídia em outros.",
        enableToggle: "Trocar a fileira de funções por app",
        enableCaption: "Adicione os apps que devem ter o oposto da configuração de teclas F do sistema. As teletas trocam ao trocar para um deles.",
        appsTitle: "Trocar as teclas nestes apps",
        appsCaption: "Nestes apps, F1–F12 trocam para o comportamento que a caixa do sistema não lhes dá.",
        activeNow: "Ativo para o app em primeiro plano",
        pausedNote: "Fora dos apps listados, as teclas seguem a caixa do sistema.",
        testSection: "Teste de teclas",
        testEmpty: "Abra um dos apps listados e pressione suas teclas de função: cada tradução aparece aqui, com a tecla em que virou.",
        testClear: "Limpar",
    )

    static let tr = FnLockStrings(
        pageTitle: "Uygulama başına işlev tuşları",
        hubDescription: "Bazı uygulamalarda F1–F12’yi işlev tuşu, diğerlerinde medya tuşu olarak kullanın.",
        enableToggle: "İşlev satırını uygulamaya göre değiştir",
        enableCaption: "Sistemin F tuşu ayarının tersini alacak uygulamaları ekleyin. Tuşlar, birine geçtiğiniz anda döner.",
        appsTitle: "Bu uygulamalarda tuşları ters çevir",
        appsCaption: "Bu uygulamalarda F1–F12, sistemin onlara vermediği davranışa geçer.",
        activeNow: "Öndeki uygulama için etkin",
        pausedNote: "Listedeki uygulamaların dışında tuşlar sistem ayarını izler.",
        testSection: "Tuş testi",
        testEmpty: "Listedeki uygulamalardan birine geçin ve işlev tuşlarına basın: her çeviri, dönüştüğü tuşla birlikte buraya düşer.",
        testClear: "Temizle",
    )

    static let ru = FnLockStrings(
        pageTitle: "Функциональные клавиши по приложениям",
        hubDescription: "Используйте F1–F12 как функциональные клавиши в одних приложениях и как медиаклавиши в других.",
        enableToggle: "Переключать ряд F-клавиш по приложениям",
        enableCaption: "Добавьте приложения, которые должны получить противоположное системной настройке F-клавиш. Клавиши переключаются в момент перехода к одному из них.",
        appsTitle: "Перевернуть клавиши в этих приложениях",
        appsCaption: "В этих приложениях F1–F12 переключаются на поведение, которое не даёт системная галочка.",
        activeNow: "Активно для приложения на переднем плане",
        pausedNote: "Вне приложений из списка клавиши работают так, как задает системная галочка.",
        testSection: "Проверка клавиш",
        testEmpty: "Перейдите в одно из приложений из списка и нажмите его функциональные клавиши: каждая замена появится здесь вместе с клавишей, в которую она превратилась.",
        testClear: "Очистить",
    )

    static let es = FnLockStrings(
        pageTitle: "Teclas de función por app",
        hubDescription: "Usa F1–F12 como teclas de función en algunas apps y como teclas de medios en otras.",
        enableToggle: "Cambiar la fila de funciones por app",
        enableCaption: "Añade las apps que deben recibir lo opuesto al ajuste de teclas F del sistema. Las teclas cambian al cambiar a una de ellas.",
        appsTitle: "Invertir las teclas en estas apps",
        appsCaption: "En estas apps, F1–F12 cambian al comportamiento que la casilla del sistema no les da.",
        activeNow: "Activo para la app en primer plano",
        pausedNote: "Fuera de las apps de la lista, las teclas siguen la casilla del sistema.",
        testSection: "Prueba de teclas",
        testEmpty: "Cambia a una de las apps de la lista y pulsa sus teclas de función: cada traducción aparece aquí con la tecla en que se convirtió.",
        testClear: "Limpiar",
    )

    static let sk = FnLockStrings(
        pageTitle: "Funkčné klávesy podľa aplikácie",
        hubDescription: "Používajte F1–F12 ako funkčné klávesy v niektorých aplikáciách a ako mediálne klávesy v iných.",
        enableToggle: "Prepínať rad F klávesov podľa aplikácie",
        enableCaption: "Pridajte aplikácie, ktoré majú dostať opak systémového nastavenia F klávesov. Klávesy sa prepnú v momente prepnutia na jednu z nich.",
        appsTitle: "Obrátiť klávesy v týchto aplikáciách",
        appsCaption: "V týchto aplikáciách sa F1–F12 prepnú na správanie, ktoré im systémový prepínač nedáva.",
        activeNow: "Aktívne pre aplikáciu v popredí",
        pausedNote: "Mimo aplikácií v zozname klávesy nasledujú systémový prepínač.",
        testSection: "Test klávesov",
        testEmpty: "Prepnite sa do jednej z aplikácií v zozname a stlačte jej funkčné klávesy: každý preklad sa objaví tu spolu s klávesom, na ktorý sa zmenil.",
        testClear: "Vymazať",
    )

    static let de = FnLockStrings(
        pageTitle: "Funktionstasten pro App",
        hubDescription: "F1–F12 als Funktionstasten in einigen Apps und als Medientasten in anderen nutzen.",
        enableToggle: "F-Tasten-Reihe pro App umschalten",
        enableCaption: "Füge die Apps hinzu, die das Gegenteil der F-Tasten-Einstellung des Systems bekommen sollen. Die Tasten schlagen im Moment des Wechsels zu einer von ihnen um.",
        appsTitle: "Die Tasten in diesen Apps umkehren",
        appsCaption: "In diesen Apps wechseln F1–F12 zu dem Verhalten, das das Systemhäkchen nicht gibt.",
        activeNow: "Aktiv für die App im Vordergrund",
        pausedNote: "Außerhalb der gelisteten Apps folgen die Tasten dem Systemhäkchen.",
        testSection: "Tastentest",
        testEmpty: "Wechsle in eine der gelisteten Apps und drücke ihre Funktionstasten: Jede Umsetzung landet hier mit der Taste, die daraus wurde.",
        testClear: "Leeren",
    )

    static let fr = FnLockStrings(
        pageTitle: "Touches de fonction par app",
        hubDescription: "Utiliser F1–F12 comme touches de fonction dans certaines apps et comme touches média dans d’autres.",
        enableToggle: "Basculer la rangée de touches F par app",
        enableCaption: "Ajoutez les apps qui doivent recevoir l’inverse du réglage des touches F du système. Les touches basculent dès que vous passez à l’une d’elles.",
        appsTitle: "Inverser les touches dans ces apps",
        appsCaption: "Dans ces apps, F1–F12 basculent vers le comportement que la case du système ne leur donne pas.",
        activeNow: "Actif pour l’app au premier plan",
        pausedNote: "Hors des apps de la liste, les touches suivent la case du système.",
        testSection: "Test des touches",
        testEmpty: "Passez à l’une des apps de la liste et appuyez sur ses touches de fonction\u{00A0}: chaque traduction apparaît ici, avec la touche qu’elle est devenue.",
        testClear: "Effacer",
    )

    static let it = FnLockStrings(
        pageTitle: "Tasti funzione per app",
        hubDescription: "Usa F1–F12 come tasti funzione in alcune app e come tasti multimediali in altre.",
        enableToggle: "Cambiare la fila di tasti F per app",
        enableCaption: "Aggiungi le app che devono ricevere il contrario dell’impostazione dei tasti F del sistema. I tasti cambiano quando passi a una di esse.",
        appsTitle: "Inverti i tasti in queste app",
        appsCaption: "In queste app, F1–F12 passano al comportamento che la casella di sistema non dà loro.",
        activeNow: "Attivo per l’app in primo piano",
        pausedNote: "Fuori dalle app in elenco, i tasti seguono la casella di sistema.",
        testSection: "Prova tasti",
        testEmpty: "Passa a una delle app in elenco e premi i suoi tasti funzione: ogni traduzione appare qui, con il tasto in cui si è trasformata.",
        testClear: "Svuota",
    )

    static let ja = FnLockStrings(
        pageTitle: "Appごとのファンクションキー",
        hubDescription: "一部のAppでF1–F12をファンクションキーとして、別のAppではメディアキーとして使います。",
        enableToggle: "ファンクションキー列をAppごとに切り替える",
        enableCaption: "システムのFキー設定と逆の動作にするAppを追加します。いずれかに切り替えるとキーが即座に切り替わります。",
        appsTitle: "これらのAppでキーを反転",
        appsCaption: "これらのAppでは、F1–F12がシステムのチェックボックスが与えない動作に切り替わります。",
        activeNow: "最前面のAppに対して有効",
        pausedNote: "リストしたApp以外では、キーはシステムのチェックボックスに従います。",
        testSection: "キーテスト",
        testEmpty: "リストしたAppのいずれかに切り替えて機能キーを押すと、変換のたびに、なったキーとともにここに表示されます。",
        testClear: "クリア",
    )

    static let ko = FnLockStrings(
        pageTitle: "앱별 기능 키",
        hubDescription: "일부 앱에서 F1–F12를 기능 키로, 다른 앱에서는 미디어 키로 사용합니다.",
        enableToggle: "F 키 행을 앱별로 전환",
        enableCaption: "시스템 F 키 설정의 반대를 받을 앱을 추가합니다. 그중 하나로 전환하면 키가 즉시 바뀝니다.",
        appsTitle: "이 앱에서 키 반전",
        appsCaption: "이 앱들에서 F1–F12가 시스템 체크박스가 주지 않는 동작으로 전환됩니다.",
        activeNow: "맨앞 앱에 대해 활성화됨",
        pausedNote: "나열된 앱 외부에서는 키가 시스템 체크박스를 따릅니다.",
        testSection: "키 테스트",
        testEmpty: "나열된 앱 중 하나로 전환해 기능 키를 누르면 변환될 때마다 어떤 키가 되었는지와 함께 여기에 표시됩니다.",
        testClear: "지우기",
    )

    static let zhHans = FnLockStrings(
        pageTitle: "按 App 切换功能键",
        hubDescription: "在一些 App 里把 F1–F12 作为功能键，在另一些里作为媒体键。",
        enableToggle: "按 App 切换功能键行",
        enableCaption: "添加需要与系统 F 键设置相反行为的 App。切换到其中任意一个时按键立即翻转。",
        appsTitle: "在这些 App 里翻转按键",
        appsCaption: "在这些 App 里，F1–F12 切换到系统复选框未给出的行为。",
        activeNow: "已对最前台 App 生效",
        pausedNote: "在列表中的 App 之外，按键遵循系统复选框的设置。",
        testSection: "键位测试",
        testEmpty: "切换到列表中的 App 并按功能键：每次翻译都会连同变成的键显示在这里。",
        testClear: "清除",
    )

    static let zhTW = FnLockStrings(
        pageTitle: "依 App 切換功能鍵",
        hubDescription: "在一些 App 裡把 F1–F12 作為功能鍵，在另一些裡作為媒體鍵。",
        enableToggle: "依 App 切換功能鍵列",
        enableCaption: "加入需要與系統 F 鍵設定相反行為的 App。切換到其中任一個時按鍵立即翻轉。",
        appsTitle: "在這些 App 裡翻轉按鍵",
        appsCaption: "在這些 App 裡，F1–F12 切換到系統勾選框未給出的行為。",
        activeNow: "已對最前方面 App 生效",
        pausedNote: "在列表中的 App 之外，按鍵遵循系統勾選框的設定。",
        testSection: "鍵位測試",
        testEmpty: "切換到列表中的 App 並按功能鍵：每次翻譯都會連同變成的鍵顯示在這裡。",
        testClear: "清除",
    )

    static let zhHK = FnLockStrings(
        pageTitle: "按 App 切換功能鍵",
        hubDescription: "喺一部份 App 將 F1–F12 作為功能作為功能鍵，喺其他度作為媒體鍵。",
        enableToggle: "按 App 切換功能鍵列",
        enableCaption: "加入需要同系統 F 鍵設定相反行為嘅 App。切換到其中任何一個嗰陣按鍵即刻翻轉。",
        appsTitle: "喺呢啲 App 裡面翻轉按鍵",
        appsCaption: "喺呢啲 App 裡面，F1–F12 切換到系統剔選框無畀到嘅行為。",
        activeNow: "已對最前面 App 生效",
        pausedNote: "喺列表中嘅 App 以外，按鍵跟系統剔選框嘅設定。",
        testSection: "鍵位測試",
        testEmpty: "切換到列表中嘅 App 並撳功能鍵：每次翻譯都會連同變成嘅鍵顯示喺呢度。",
        testClear: "清除",
    )

    static let uk = FnLockStrings(
        pageTitle: "Функціональні клавіші за програмами",
        hubDescription: "Використовуйте F1–F12 як функціональні клавіші в одних програмах і як медіаклавіші в інших.",
        enableToggle: "Перемикати ряд F-клавіш за програмами",
        enableCaption: "Додайте програми, які повинні отримати протилежне системному налаштуванню F-клавіш. Клавіші перемикаються в момент переходу до однієї з них.",
        appsTitle: "Перевернути клавіші в цих програмах",
        appsCaption: "У цих програмах F1–F12 перемикаються на поведінку, яку не дає системна галочка.",
        activeNow: "Активно для програми на передньому плані",
        pausedNote: "Поза програмами зі списку клавіші працюють так, як задає системна галочка.",
        testSection: "Перевірка клавіш",
        testEmpty: "Перейдіть до однієї з програм у списку та натисніть її функціональні клавіші: кожна заміна з’явиться тут разом із клавішею, у яку вона перетворилася.",
        testClear: "Очистити",
    )
}
