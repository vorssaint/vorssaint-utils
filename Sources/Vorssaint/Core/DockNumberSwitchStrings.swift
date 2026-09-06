// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DockNumberSwitchStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let needsAccessibility: String
    let unavailableShortcuts: String
    let narrowSuperKey: String
}

extension FeatureStrings {
    static func dockNumberSwitch(_ language: AppLanguage) -> DockNumberSwitchStrings {
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

extension DockNumberSwitchStrings {
    static let enUS = DockNumberSwitchStrings(
        pageTitle: "Dock number keys",
        hubDescription: "Jump to a Dock app with the super key and its number.",
        enableToggle: "Activate a Dock app with the super key and its number",
        enableCaption: "With the super key on, press it with 1 to 9 to activate the app in that Dock position. Finder is 1.",
        needsAccessibility: "Reading the Dock order needs Accessibility.",
        unavailableShortcuts: "Warning: the super key with %@ is already used by macOS or another app, so those numbers may not work. Consider adding more modifiers to the super key.",
        narrowSuperKey: "Inactive: your super key uses a single modifier, so the number keys would be ⌘1–⌘9 or ⌃1–⌃9 — combinations macOS and browsers already use. Add another modifier to the super key to turn this on."
    )

    static let ptBR = DockNumberSwitchStrings(
        pageTitle: "Teclas numéricas do Dock",
        hubDescription: "Abra um app do Dock com a tecla super e o número dele.",
        enableToggle: "Ativar um app do Dock com a tecla super e o número dele",
        enableCaption: "Com a tecla super ativa, pressione-a com 1 a 9 para ativar o app naquela posição do Dock. O Finder é o 1.",
        needsAccessibility: "Ler a ordem do Dock requer Acessibilidade.",
        unavailableShortcuts: "Aviso: a tecla super com %@ já é usada pelo macOS ou por outro app, então esses números podem não funcionar. Considere adicionar mais modificadores à tecla super.",
        narrowSuperKey: "Inativo: sua tecla super usa um só modificador, então as teclas numéricas seriam ⌘1–⌘9 ou ⌃1–⌃9 — combinações que o macOS e os navegadores já usam. Adicione outro modificador à tecla super para ativar."
    )

    static let tr = DockNumberSwitchStrings(
        pageTitle: "Dock sayı tuşları",
        hubDescription: "Süper tuş ve numarasıyla bir Dock uygulamasına geçin.",
        enableToggle: "Süper tuş ve numarasıyla bir Dock uygulamasını etkinleştir",
        enableCaption: "Süper tuş açıkken, o Dock konumundaki uygulamayı etkinleştirmek için 1–9 ile birlikte basın. Finder 1’dir.",
        needsAccessibility: "Dock sırasını okumak için Erişilebilirlik gerekir.",
        unavailableShortcuts: "Uyarı: %@ ile süper tuş macOS ya da başka bir uygulama tarafından zaten kullanılıyor, bu yüzden bu numaralar çalışmayabilir. Süper tuşa daha fazla değiştirici eklemeyi düşünün.",
        narrowSuperKey: "Etkin değil: süper tuşunuz tek bir değiştirici kullanıyor, bu yüzden sayı tuşları ⌘1–⌘9 veya ⌃1–⌃9 olurdu — macOS ve tarayıcıların zaten kullandığı kombinasyonlar. Etkinleştirmek için süper tuşa başka bir değiştirici ekleyin."
    )

    static let ru = DockNumberSwitchStrings(
        pageTitle: "Цифровые клавиши Dock",
        hubDescription: "Переход к приложению в Dock с помощью суперклавиши и его номера.",
        enableToggle: "Открывать приложение из Dock суперклавишей и его номером",
        enableCaption: "Когда суперклавиша включена, нажмите её с 1–9, чтобы открыть приложение на этой позиции в Dock. Finder — это 1.",
        needsAccessibility: "Для чтения порядка Dock нужен Универсальный доступ.",
        unavailableShortcuts: "Предупреждение: суперклавишу с %@ уже использует macOS или другое приложение, поэтому эти номера могут не работать. Попробуйте добавить больше модификаторов к суперклавише.",
        narrowSuperKey: "Неактивно: ваша суперклавиша использует один модификатор, поэтому цифровые клавиши стали бы ⌘1–⌘9 или ⌃1–⌃9 — сочетания, которые уже используют macOS и браузеры. Добавьте ещё один модификатор к суперклавише, чтобы включить."
    )

    static let es = DockNumberSwitchStrings(
        pageTitle: "Teclas numéricas del Dock",
        hubDescription: "Ve a una app del Dock con la tecla súper y su número.",
        enableToggle: "Activar una app del Dock con la tecla súper y su número",
        enableCaption: "Con la tecla súper activada, púlsala con 1 a 9 para activar la app en esa posición del Dock. Finder es la 1.",
        needsAccessibility: "Leer el orden del Dock requiere Accesibilidad.",
        unavailableShortcuts: "Aviso: la tecla súper con %@ ya la usa macOS u otra app, por lo que esos números podrían no funcionar. Considera añadir más modificadores a la tecla súper.",
        narrowSuperKey: "Inactivo: tu tecla súper usa un solo modificador, así que las teclas numéricas serían ⌘1–⌘9 o ⌃1–⌃9 — combinaciones que macOS y los navegadores ya usan. Añade otro modificador a la tecla súper para activarlo."
    )

    static let de = DockNumberSwitchStrings(
        pageTitle: "Dock-Zifferntasten",
        hubDescription: "Mit der Supertaste und ihrer Nummer zu einer Dock-App springen.",
        enableToggle: "Eine Dock-App mit der Supertaste und ihrer Nummer aktivieren",
        enableCaption: "Wenn die Supertaste aktiv ist, drücke sie mit 1 bis 9, um die App an dieser Dock-Position zu aktivieren. Finder ist 1.",
        needsAccessibility: "Zum Lesen der Dock-Reihenfolge sind Bedienungshilfen nötig.",
        unavailableShortcuts: "Warnung: Die Supertaste mit %@ wird bereits von macOS oder einer anderen App genutzt, daher funktionieren diese Nummern möglicherweise nicht. Füge der Supertaste mehr Modifikatoren hinzu.",
        narrowSuperKey: "Inaktiv: Deine Supertaste nutzt nur einen Modifikator, daher wären die Zifferntasten ⌘1–⌘9 oder ⌃1–⌃9 — Kombinationen, die macOS und Browser bereits verwenden. Füge der Supertaste einen weiteren Modifikator hinzu, um dies zu aktivieren."
    )

    static let fr = DockNumberSwitchStrings(
        pageTitle: "Touches numériques du Dock",
        hubDescription: "Accédez à une app du Dock avec la touche super et son numéro.",
        enableToggle: "Activer une app du Dock avec la touche super et son numéro",
        enableCaption: "Quand la touche super est activée, appuyez dessus avec 1 à 9 pour activer l’app à cette position du Dock. Le Finder est 1.",
        needsAccessibility: "Lire l’ordre du Dock nécessite l’Accessibilité.",
        unavailableShortcuts: "Avertissement : la touche super avec %@ est déjà utilisée par macOS ou une autre app ; ces numéros peuvent donc ne pas fonctionner. Ajoutez d’autres modificateurs à la touche super.",
        narrowSuperKey: "Inactif : votre touche super n’utilise qu’un modificateur, donc les touches numériques seraient ⌘1–⌘9 ou ⌃1–⌃9 — des combinaisons que macOS et les navigateurs utilisent déjà. Ajoutez un autre modificateur à la touche super pour l’activer."
    )

    static let it = DockNumberSwitchStrings(
        pageTitle: "Tasti numerici del Dock",
        hubDescription: "Passa a un’app del Dock con il tasto super e il suo numero.",
        enableToggle: "Attiva un’app del Dock con il tasto super e il suo numero",
        enableCaption: "Con il tasto super attivo, premilo con 1–9 per attivare l’app in quella posizione del Dock. Il Finder è 1.",
        needsAccessibility: "Leggere l’ordine del Dock richiede l’Accessibilità.",
        unavailableShortcuts: "Avviso: il tasto super con %@ è già usato da macOS o da un’altra app, quindi questi numeri potrebbero non funzionare. Valuta di aggiungere altri modificatori al tasto super.",
        narrowSuperKey: "Inattivo: il tuo tasto super usa un solo modificatore, quindi i tasti numerici sarebbero ⌘1–⌘9 o ⌃1–⌃9 — combinazioni che macOS e i browser usano già. Aggiungi un altro modificatore al tasto super per attivarlo."
    )

    static let ja = DockNumberSwitchStrings(
        pageTitle: "Dock 番号キー",
        hubDescription: "スーパーキーと番号で Dock のアプリに切り替えます。",
        enableToggle: "スーパーキーと番号で Dock のアプリを起動する",
        enableCaption: "スーパーキーがオンのとき、1〜9 と一緒に押すと、その Dock の位置にあるアプリが起動します。Finder は 1 です。",
        needsAccessibility: "Dock の並び順を読み取るにはアクセシビリティが必要です。",
        unavailableShortcuts: "警告: スーパーキーと %@ の組み合わせは macOS または別のアプリがすでに使用しているため、これらの番号は動作しないことがあります。スーパーキーに修飾キーを追加することを検討してください。",
        narrowSuperKey: "無効: スーパーキーが修飾キー 1 つのため、数字キーが ⌘1–⌘9 または ⌃1–⌃9 になり、macOS やブラウザーがすでに使っている組み合わせと重なります。有効にするにはスーパーキーに修飾キーを追加してください。"
    )

    static let ko = DockNumberSwitchStrings(
        pageTitle: "Dock 숫자 키",
        hubDescription: "슈퍼 키와 숫자로 Dock 앱으로 전환합니다.",
        enableToggle: "슈퍼 키와 숫자로 Dock 앱 활성화",
        enableCaption: "슈퍼 키가 켜져 있을 때 1~9와 함께 누르면 해당 Dock 위치의 앱이 활성화됩니다. Finder가 1입니다.",
        needsAccessibility: "Dock 순서를 읽으려면 손쉬운 사용 권한이 필요합니다.",
        unavailableShortcuts: "경고: %@ 숫자와 슈퍼 키 조합을 macOS나 다른 앱이 이미 사용 중이라 해당 숫자가 작동하지 않을 수 있습니다. 슈퍼 키에 보조 키를 더 추가해 보세요.",
        narrowSuperKey: "비활성: 슈퍼 키가 보조 키 하나만 사용해 숫자 키가 ⌘1–⌘9 또는 ⌃1–⌃9가 되며, macOS와 브라우저가 이미 쓰는 조합과 겹칩니다. 사용하려면 슈퍼 키에 보조 키를 하나 더 추가하세요."
    )

    static let zhHans = DockNumberSwitchStrings(
        pageTitle: "Dock 数字键",
        hubDescription: "用超级键加数字切换到 Dock 中的应用。",
        enableToggle: "用超级键加数字激活 Dock 中的应用",
        enableCaption: "开启超级键后，与 1 到 9 一起按下即可激活该 Dock 位置的应用。访达是 1。",
        needsAccessibility: "读取 Dock 顺序需要辅助功能权限。",
        unavailableShortcuts: "警告：超级键与 %@ 的组合已被 macOS 或其他应用占用，因此这些数字可能无法使用。可以考虑为超级键添加更多修饰键。",
        narrowSuperKey: "未启用：你的超级键只用一个修饰键，数字键会变成 ⌘1–⌘9 或 ⌃1–⌃9，与 macOS 和浏览器已使用的组合冲突。为超级键再添加一个修饰键即可启用。"
    )

    static let zhTW = DockNumberSwitchStrings(
        pageTitle: "Dock 數字鍵",
        hubDescription: "用超級鍵加數字切換到 Dock 中的 App。",
        enableToggle: "用超級鍵加數字啟用 Dock 中的 App",
        enableCaption: "開啟超級鍵後，與 1 至 9 一起按下即可啟用該 Dock 位置的 App。Finder 是 1。",
        needsAccessibility: "讀取 Dock 順序需要輔助使用權限。",
        unavailableShortcuts: "警告：超級鍵與 %@ 的組合已被 macOS 或其他 App 佔用，因此這些數字可能無法使用。可以考慮為超級鍵加入更多修飾鍵。",
        narrowSuperKey: "未啟用：你的超級鍵只用一個修飾鍵，數字鍵會變成 ⌘1–⌘9 或 ⌃1–⌃9，與 macOS 和瀏覽器已使用的組合衝突。為超級鍵再加入一個修飾鍵即可啟用。"
    )

    static let zhHK = DockNumberSwitchStrings(
        pageTitle: "Dock 數字鍵",
        hubDescription: "用超級鍵加數字切換到 Dock 中的 App。",
        enableToggle: "用超級鍵加數字啟用 Dock 中的 App",
        enableCaption: "開啟超級鍵後，與 1 至 9 一起按下即可啟用該 Dock 位置的 App。Finder 是 1。",
        needsAccessibility: "讀取 Dock 順序需要輔助使用權限。",
        unavailableShortcuts: "警告：超級鍵與 %@ 的組合已被 macOS 或其他 App 佔用，因此這些數字可能無法使用。可以考慮為超級鍵加入更多修飾鍵。",
        narrowSuperKey: "未啟用：你的超級鍵只用一個修飾鍵，數字鍵會變成 ⌘1–⌘9 或 ⌃1–⌃9，與 macOS 和瀏覽器已使用的組合衝突。為超級鍵再加入一個修飾鍵即可啟用。"
    )
}
