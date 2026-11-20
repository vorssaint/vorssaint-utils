// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the KeyCastr-style keystroke overlay.
struct KeystrokeOverlayStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let activeNow: String
    let styleLabel: String
    let styleSvelte: String
    let styleKeycaps: String
    let modeLabel: String
    let modeAllKeys: String
    let modeShortcutsOnly: String
    let modeCaption: String
    let positionLabel: String
    let positionBottomCenter: String
    let positionBottomLeft: String
    let positionBottomRight: String
    let positionTopCenter: String
    let positionTopLeft: String
    let positionTopRight: String
    let dragPositionCaption: String
    let resetPositionButton: String
    let sizeLabel: String
    let sizeSmall: String
    let sizeMedium: String
    let sizeLarge: String
    let durationLabel: String
    let durationSecondsFormat: String
    let showInCapturesToggle: String
    let showInCapturesCaption: String
    let previewButton: String
    let privacyNote: String

    func styleName(_ style: KeystrokeOverlayStyle) -> String {
        switch style {
        case .svelte: return styleSvelte
        case .keycaps: return styleKeycaps
        }
    }

    func positionName(_ position: KeystrokeOverlayPosition) -> String {
        switch position {
        case .bottomCenter: return positionBottomCenter
        case .bottomLeft: return positionBottomLeft
        case .bottomRight: return positionBottomRight
        case .topCenter: return positionTopCenter
        case .topLeft: return positionTopLeft
        case .topRight: return positionTopRight
        }
    }

    func sizeName(_ size: KeystrokeOverlaySize) -> String {
        switch size {
        case .small: return sizeSmall
        case .medium: return sizeMedium
        case .large: return sizeLarge
        }
    }
}

extension FeatureStrings {
    static func keystrokeOverlay(_ language: AppLanguage) -> KeystrokeOverlayStrings {
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

extension KeystrokeOverlayStrings {
    static let enUS = KeystrokeOverlayStrings(
        pageTitle: "Keystroke overlay",
        hubDescription: "Displays pressed keys and shortcuts on screen for demos and recordings",
        enableToggle: "Show keystrokes on screen",
        enableCaption: "Floats a non-intrusive keystroke indicator whenever you type or press a shortcut.",
        activeNow: "Showing keystrokes",
        styleLabel: "Theme",
        styleSvelte: "Svelte",
        styleKeycaps: "Keycaps",
        modeLabel: "Keys to show",
        modeAllKeys: "All keys",
        modeShortcutsOnly: "Shortcuts only",
        modeCaption: "Shortcuts only ignores ordinary typing and shows combinations with ⌘, ⌥, ⌃ or function keys.",
        positionLabel: "Screen position",
        positionBottomCenter: "Bottom center",
        positionBottomLeft: "Bottom left",
        positionBottomRight: "Bottom right",
        positionTopCenter: "Top center",
        positionTopLeft: "Top left",
        positionTopRight: "Top right",
        dragPositionCaption: "Drag the overlay directly on screen to place it in any custom spot.",
        resetPositionButton: "Reset custom position",
        sizeLabel: "Overlay size",
        sizeSmall: "Small",
        sizeMedium: "Medium",
        sizeLarge: "Large",
        durationLabel: "Fade-out delay",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "Show in screen recordings and screenshots",
        showInCapturesCaption: "When off, the overlay stays visible to you but is hidden from screen recordings, screenshots and screen sharing.",
        previewButton: "Test overlay",
        privacyNote: "Pauses automatically in password fields when macOS Secure Input is active."
    )

    static let ptBR = KeystrokeOverlayStrings(
        pageTitle: "Exibição de teclas",
        hubDescription: "Mostra as teclas e atalhos pressionados na tela para demonstrações e gravações",
        enableToggle: "Mostrar teclas na tela",
        enableCaption: "Exibe um indicador flutuante discreto sempre que você digita ou usa um atalho.",
        activeNow: "Mostrando teclas",
        styleLabel: "Tema",
        styleSvelte: "Svelte",
        styleKeycaps: "Teclas",
        modeLabel: "Teclas exibidas",
        modeAllKeys: "Todas as teclas",
        modeShortcutsOnly: "Apenas atalhos",
        modeCaption: "Apenas atalhos ignora a digitação comum e mostra combinações com ⌘, ⌥, ⌃ ou teclas de função.",
        positionLabel: "Posição na tela",
        positionBottomCenter: "Inferior central",
        positionBottomLeft: "Inferior esquerdo",
        positionBottomRight: "Inferior direito",
        positionTopCenter: "Superior central",
        positionTopLeft: "Superior esquerdo",
        positionTopRight: "Superior direito",
        dragPositionCaption: "Arraste o indicador diretamente na tela para posicioná-lo onde preferir.",
        resetPositionButton: "Redefinir posição personalizada",
        sizeLabel: "Tamanho do indicador",
        sizeSmall: "Pequeno",
        sizeMedium: "Médio",
        sizeLarge: "Grande",
        durationLabel: "Tempo na tela",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "Mostrar em gravações e capturas de tela",
        showInCapturesCaption: "Quando desativado, o indicador continua visível para você, mas fica oculto em gravações, capturas e compartilhamento de tela.",
        previewButton: "Testar indicador",
        privacyNote: "Pausa automaticamente em campos de senha quando a Entrada Segura do macOS está ativa."
    )

    static let tr = KeystrokeOverlayStrings(
        pageTitle: "Tuş vuruşu göstergesi",
        hubDescription: "Sunumlar ve kayıtlar için basılan tuşları ve kısayolları ekranda gösterir",
        enableToggle: "Tuş vuruşlarını ekranda göster",
        enableCaption: "Yazarken veya bir kısayola bastığınızda ekranda yüzen bir tuş göstergesi belirir.",
        activeNow: "Tuşlar gösteriliyor",
        styleLabel: "Tema",
        styleSvelte: "Svelte",
        styleKeycaps: "Tuş başlıkları",
        modeLabel: "Gösterilecek tuşlar",
        modeAllKeys: "Tüm tuşlar",
        modeShortcutsOnly: "Yalnızca kısayollar",
        modeCaption: "Yalnızca kısayollar normal yazımı yok sayar ve ⌘, ⌥, ⌃ veya işlev tuşlu kombinasyonları gösterir.",
        positionLabel: "Ekran konumu",
        positionBottomCenter: "Alt orta",
        positionBottomLeft: "Alt sol",
        positionBottomRight: "Alt sağ",
        positionTopCenter: "Üst orta",
        positionTopLeft: "Üst sol",
        positionTopRight: "Üst sağ",
        dragPositionCaption: "Özel bir konuma yerleştirmek için göstergeyi doğrudan ekranda sürükleyin.",
        resetPositionButton: "Özel konumu sıfırla",
        sizeLabel: "Gösterge boyutu",
        sizeSmall: "Küçük",
        sizeMedium: "Orta",
        sizeLarge: "Büyük",
        durationLabel: "Kaybolma süresi",
        durationSecondsFormat: "%.1f sn",
        showInCapturesToggle: "Ekran kayıtlarında ve ekran görüntülerinde göster",
        showInCapturesCaption: "Kapalıyken gösterge sizin için görünür kalır ancak ekran kayıtlarından, ekran görüntülerinden ve ekran paylaşımından gizlenir.",
        previewButton: "Göstergeyi dene",
        privacyNote: "macOS Güvenli Giriş etkinken parola alanlarında otomatik olarak duraklatılır."
    )

    static let ru = KeystrokeOverlayStrings(
        pageTitle: "Отображение клавиш",
        hubDescription: "Показывает нажатые клавиши и сочетания на экране для демонстраций и записей",
        enableToggle: "Показывать нажатия клавиш на экране",
        enableCaption: "Отображает плавающую панель с клавишами при вводе текста или нажатии сочетаний.",
        activeNow: "Клавиши отображаются",
        styleLabel: "Тема",
        styleSvelte: "Svelte",
        styleKeycaps: "Клавиши",
        modeLabel: "Какие клавиши показывать",
        modeAllKeys: "Все клавиши",
        modeShortcutsOnly: "Только сочетания",
        modeCaption: "В режиме «Только сочетания» обычный набор скрыт и видны только комбинации с ⌘, ⌥, ⌃ или функциональными клавишами.",
        positionLabel: "Положение на экране",
        positionBottomCenter: "Внизу по центру",
        positionBottomLeft: "Внизу слева",
        positionBottomRight: "Внизу справа",
        positionTopCenter: "Вверху по центру",
        positionTopLeft: "Вверху слева",
        positionTopRight: "Вверху справа",
        dragPositionCaption: "Перетащите панель прямо на экране, чтобы разместить её в любом удобном месте.",
        resetPositionButton: "Сбросить своё положение",
        sizeLabel: "Размер панели",
        sizeSmall: "Маленький",
        sizeMedium: "Средний",
        sizeLarge: "Большой",
        durationLabel: "Задержка скрытия",
        durationSecondsFormat: "%.1f с",
        showInCapturesToggle: "Показывать на записях и снимках экрана",
        showInCapturesCaption: "Когда выключено, панель видна вам, но скрыта в записях экрана, снимках и демонстрации экрана.",
        previewButton: "Проверить панель",
        privacyNote: "Автоматически приостанавливается в полях ввода пароля при активном защищённом вводе macOS."
    )

    static let es = KeystrokeOverlayStrings(
        pageTitle: "Visualizador de teclas",
        hubDescription: "Muestra las teclas y atajos pulsados en pantalla para demostraciones y grabaciones",
        enableToggle: "Mostrar pulsaciones en pantalla",
        enableCaption: "Muestra una cápsula flotante con las teclas cada vez que escribes o pulsas un atajo.",
        activeNow: "Mostrando pulsaciones",
        styleLabel: "Tema",
        styleSvelte: "Svelte",
        styleKeycaps: "Teclas",
        modeLabel: "Teclas que mostrar",
        modeAllKeys: "Todas las teclas",
        modeShortcutsOnly: "Solo atajos",
        modeCaption: "Solo atajos omite la escritura normal y muestra combinaciones con ⌘, ⌥, ⌃ o teclas de función.",
        positionLabel: "Posición en pantalla",
        positionBottomCenter: "Abajo en el centro",
        positionBottomLeft: "Abajo a la izquierda",
        positionBottomRight: "Abajo a la derecha",
        positionTopCenter: "Arriba en el centro",
        positionTopLeft: "Arriba a la izquierda",
        positionTopRight: "Arriba a la derecha",
        dragPositionCaption: "Arrastra el indicador directamente en la pantalla para colocarlo en cualquier lugar.",
        resetPositionButton: "Restablecer posición personalizada",
        sizeLabel: "Tamaño del indicador",
        sizeSmall: "Pequeño",
        sizeMedium: "Mediano",
        sizeLarge: "Grande",
        durationLabel: "Tiempo en pantalla",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "Mostrar en grabaciones y capturas de pantalla",
        showInCapturesCaption: "Al desactivarlo, el indicador sigue visible para ti pero queda oculto en grabaciones, capturas y pantalla compartida.",
        previewButton: "Probar indicador",
        privacyNote: "Se pausa automáticamente en los campos de contraseña cuando la entrada segura de macOS está activa."
    )

    static let sk = KeystrokeOverlayStrings(
        pageTitle: "Zobrazenie klávesov",
        hubDescription: "Zobrazuje stlačené klávesy a skratky na obrazovke pri ukážkach a nahrávaní",
        enableToggle: "Zobrazovať stlačené klávesy na obrazovke",
        enableCaption: "Pri písaní alebo stlačení skratky zobrazí plávajúci indikátor klávesov.",
        activeNow: "Zobrazujú sa klávesy",
        styleLabel: "Motív",
        styleSvelte: "Svelte",
        styleKeycaps: "Klávesy",
        modeLabel: "Zobrazované klávesy",
        modeAllKeys: "Všetky klávesy",
        modeShortcutsOnly: "Iba skratky",
        modeCaption: "Režim Iba skratky ignoruje bežné písanie a zobrazuje kombinácie s ⌘, ⌥, ⌃ alebo funkčnými klávesmi.",
        positionLabel: "Poloha na obrazovke",
        positionBottomCenter: "Dole v strede",
        positionBottomLeft: "Dole vľavo",
        positionBottomRight: "Dole vpravo",
        positionTopCenter: "Hore v strede",
        positionTopLeft: "Hore vľavo",
        positionTopRight: "Hore vpravo",
        dragPositionCaption: "Potiahnite indikátor priamo na obrazovke a umiestnite ho na ľubovoľné miesto.",
        resetPositionButton: "Obnoviť vlastnú polohu",
        sizeLabel: "Veľkosť indikátora",
        sizeSmall: "Malá",
        sizeMedium: "Stredná",
        sizeLarge: "Veľká",
        durationLabel: "Čas zobrazenia",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "Zobrazovať na nahrávkach a snímkach obrazovky",
        showInCapturesCaption: "Keď je vypnuté, indikátor zostane viditeľný pre vás, ale bude skrytý v nahrávkach, snímkach a pri zdieľaní obrazovky.",
        previewButton: "Vyskúšať indikátor",
        privacyNote: "Automaticky sa pozastaví v poliach pre heslo, keď je aktívny zabezpečený vstup macOS."
    )

    static let de = KeystrokeOverlayStrings(
        pageTitle: "Tastatureinblendung",
        hubDescription: "Zeigt gedrückte Tasten und Kurzbefehle bei Demos und Aufnahmen auf dem Bildschirm an",
        enableToggle: "Tastenanschläge auf dem Bildschirm anzeigen",
        enableCaption: "Blendet beim Tippen oder Drücken eines Kurzbefehls eine dezente schwebende Tastenanzeige ein.",
        activeNow: "Tastenanschläge werden angezeigt",
        styleLabel: "Darstellung",
        styleSvelte: "Svelte",
        styleKeycaps: "Tastenkappen",
        modeLabel: "Angezeigte Tasten",
        modeAllKeys: "Alle Tasten",
        modeShortcutsOnly: "Nur Kurzbefehle",
        modeCaption: "„Nur Kurzbefehle“ blendet normales Tippen aus und zeigt Kombinationen mit ⌘, ⌥, ⌃ oder Funktionstasten.",
        positionLabel: "Bildschirmposition",
        positionBottomCenter: "Unten Mitte",
        positionBottomLeft: "Unten links",
        positionBottomRight: "Unten rechts",
        positionTopCenter: "Oben Mitte",
        positionTopLeft: "Oben links",
        positionTopRight: "Oben rechts",
        dragPositionCaption: "Ziehen Sie die Einblendung direkt auf dem Bildschirm an eine beliebige Position.",
        resetPositionButton: "Eigene Position zurücksetzen",
        sizeLabel: "Anzeigegröße",
        sizeSmall: "Klein",
        sizeMedium: "Mittel",
        sizeLarge: "Groß",
        durationLabel: "Ausblendverzögerung",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "In Bildschirmaufnahmen und Screenshots anzeigen",
        showInCapturesCaption: "Wenn deaktiviert, bleibt die Einblendung für Sie sichtbar, wird aber in Aufnahmen, Screenshots und bei der Bildschirmfreigabe ausgeblendet.",
        previewButton: "Einblendung testen",
        privacyNote: "Pausiert automatisch in Passwortfeldern, solange die sichere Eingabe von macOS aktiv ist."
    )

    static let fr = KeystrokeOverlayStrings(
        pageTitle: "Affichage des touches",
        hubDescription: "Affiche les touches et raccourcis pressés à l’écran pour les démos et enregistrements",
        enableToggle: "Afficher les touches à l’écran",
        enableCaption: "Affiche une capsule flottante discrète lorsque vous tapez ou utilisez un raccourci.",
        activeNow: "Affichage des touches actif",
        styleLabel: "Thème",
        styleSvelte: "Svelte",
        styleKeycaps: "Touches",
        modeLabel: "Touches à afficher",
        modeAllKeys: "Toutes les touches",
        modeShortcutsOnly: "Raccourcis uniquement",
        modeCaption: "Raccourcis uniquement ignore la frappe ordinaire et affiche les combinaisons avec ⌘, ⌥, ⌃ ou les touches de fonction.",
        positionLabel: "Position à l’écran",
        positionBottomCenter: "En bas au centre",
        positionBottomLeft: "En bas à gauche",
        positionBottomRight: "En bas à droite",
        positionTopCenter: "En haut au centre",
        positionTopLeft: "En haut à gauche",
        positionTopRight: "En haut à droite",
        dragPositionCaption: "Faites glisser l’indicateur directement sur l’écran pour le placer où vous voulez.",
        resetPositionButton: "Réinitialiser la position personnalisée",
        sizeLabel: "Taille de l’indicateur",
        sizeSmall: "Petit",
        sizeMedium: "Moyen",
        sizeLarge: "Grand",
        durationLabel: "Délai de disparition",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "Afficher dans les enregistrements et captures d’écran",
        showInCapturesCaption: "Une fois désactivé, l’indicateur reste visible pour vous mais est masqué des enregistrements, captures et partages d’écran.",
        previewButton: "Tester l’affichage",
        privacyNote: "Se met automatiquement en pause dans les champs de mot de passe lorsque la saisie sécurisée de macOS est active."
    )

    static let it = KeystrokeOverlayStrings(
        pageTitle: "Visualizzatore tasti",
        hubDescription: "Mostra sullo schermo i tasti e le abbreviazioni premuti per demo e registrazioni",
        enableToggle: "Mostra i tasti premuti sullo schermo",
        enableCaption: "Mostra un indicatore flottante discreto ogni volta che digiti o premi un’abbreviazione.",
        activeNow: "Visualizzazione tasti attiva",
        styleLabel: "Tema",
        styleSvelte: "Svelte",
        styleKeycaps: "Tasti",
        modeLabel: "Tasti da mostrare",
        modeAllKeys: "Tutti i tasti",
        modeShortcutsOnly: "Solo abbreviazioni",
        modeCaption: "Solo abbreviazioni ignora la digitazione normale e mostra le combinazioni con ⌘, ⌥, ⌃ o i tasti funzione.",
        positionLabel: "Posizione sullo schermo",
        positionBottomCenter: "In basso al centro",
        positionBottomLeft: "In basso a sinistra",
        positionBottomRight: "In basso a destra",
        positionTopCenter: "In alto al centro",
        positionTopLeft: "In alto a sinistra",
        positionTopRight: "In alto a destra",
        dragPositionCaption: "Trascina l’indicatore direttamente sullo schermo per posizionarlo dove preferisci.",
        resetPositionButton: "Reimposta posizione personalizzata",
        sizeLabel: "Dimensione indicatore",
        sizeSmall: "Piccolo",
        sizeMedium: "Medio",
        sizeLarge: "Grande",
        durationLabel: "Ritardo di scomparsa",
        durationSecondsFormat: "%.1f s",
        showInCapturesToggle: "Mostra nelle registrazioni e negli screenshot",
        showInCapturesCaption: "Quando disattivato, l’indicatore resta visibile per te ma viene nascosto in registrazioni, screenshot e condivisione schermo.",
        previewButton: "Prova indicatore",
        privacyNote: "Si mette automaticamente in pausa nei campi password quando l’input sicuro di macOS è attivo."
    )

    static let ja = KeystrokeOverlayStrings(
        pageTitle: "キー入力オーバーレイ",
        hubDescription: "デモや画面収録向けに押したキーやショートカットを画面上に表示します",
        enableToggle: "キー入力を画面に表示",
        enableCaption: "入力やショートカット操作のたびに、邪魔にならないフローティングピルを表示します。",
        activeNow: "キー入力を表示中",
        styleLabel: "テーマ",
        styleSvelte: "Svelte",
        styleKeycaps: "キーキャップ",
        modeLabel: "表示するキー",
        modeAllKeys: "すべてのキー",
        modeShortcutsOnly: "ショートカットのみ",
        modeCaption: "「ショートカットのみ」では通常の文字入力を省き、⌘・⌥・⌃ やファンクションキーとの組み合わせだけを表示します。",
        positionLabel: "表示位置",
        positionBottomCenter: "下部中央",
        positionBottomLeft: "左下",
        positionBottomRight: "右下",
        positionTopCenter: "上部中央",
        positionTopLeft: "左上",
        positionTopRight: "右上",
        dragPositionCaption: "画面上のオーバーレイを直接ドラッグして、好きな位置に配置できます。",
        resetPositionButton: "カスタム位置をリセット",
        sizeLabel: "表示サイズ",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        durationLabel: "消えるまでの時間",
        durationSecondsFormat: "%.1f秒",
        showInCapturesToggle: "画面収録とスクリーンショットに表示",
        showInCapturesCaption: "オフにすると自分には表示されたまま、画面収録・スクリーンショット・画面共有からは非表示になります。",
        previewButton: "テスト表示",
        privacyNote: "macOSのセキュア入力が有効なパスワード欄では自動的に一時停止します。"
    )

    static let ko = KeystrokeOverlayStrings(
        pageTitle: "키 입력 오버레이",
        hubDescription: "데모 및 화면 기록을 위해 누른 키와 단축키를 화면에 표시합니다",
        enableToggle: "화면에 키 입력 표시",
        enableCaption: "타이핑하거나 단축키를 누를 때마다 방해되지 않는 플로팅 키캡을 표시합니다.",
        activeNow: "키 입력 표시 중",
        styleLabel: "테마",
        styleSvelte: "Svelte",
        styleKeycaps: "키캡",
        modeLabel: "표시할 키",
        modeAllKeys: "모든 키",
        modeShortcutsOnly: "단축키만",
        modeCaption: "단축키만 모드는 일반 타이핑을 제외하고 ⌘, ⌥, ⌃ 또는 기능 키 조합만 표시합니다.",
        positionLabel: "화면 위치",
        positionBottomCenter: "하단 가운데",
        positionBottomLeft: "왼쪽 하단",
        positionBottomRight: "오른쪽 하단",
        positionTopCenter: "상단 가운데",
        positionTopLeft: "왼쪽 상단",
        positionTopRight: "오른쪽 상단",
        dragPositionCaption: "화면에서 오버레이를 직접 드래그하여 원하는 위치에 놓을 수 있습니다.",
        resetPositionButton: "사용자 지정 위치 재설정",
        sizeLabel: "오버레이 크기",
        sizeSmall: "작게",
        sizeMedium: "보통",
        sizeLarge: "크게",
        durationLabel: "사라짐 지연 시간",
        durationSecondsFormat: "%.1f초",
        showInCapturesToggle: "화면 기록 및 스크린샷에 표시",
        showInCapturesCaption: "끄면 본인 화면에는 계속 보이지만 화면 기록, 스크린샷 및 화면 공유에서는 숨겨집니다.",
        previewButton: "오버레이 테스트",
        privacyNote: "macOS 보안 입력이 활성화된 암호 입력란에서는 자동으로 일시 정지됩니다."
    )

    static let zhHans = KeystrokeOverlayStrings(
        pageTitle: "按键显示",
        hubDescription: "在屏幕上显示按下的按键和快捷键，适合演示与录屏",
        enableToggle: "在屏幕上显示按键",
        enableCaption: "打字或按下快捷键时，在屏幕上浮动显示简洁的键帽提示。",
        activeNow: "正在显示按键",
        styleLabel: "主题样式",
        styleSvelte: "Svelte",
        styleKeycaps: "键帽",
        modeLabel: "显示内容",
        modeAllKeys: "所有按键",
        modeShortcutsOnly: "仅快捷键",
        modeCaption: "“仅快捷键”会忽略普通打字，只显示包含 ⌘、⌥、⌃ 或功能键的组合。",
        positionLabel: "屏幕位置",
        positionBottomCenter: "底部居中",
        positionBottomLeft: "左下角",
        positionBottomRight: "右下角",
        positionTopCenter: "顶部居中",
        positionTopLeft: "左上角",
        positionTopRight: "右上角",
        dragPositionCaption: "可直接在屏幕上拖动悬浮窗，将其放置在任意自定义位置。",
        resetPositionButton: "重置自定义位置",
        sizeLabel: "显示尺寸",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        durationLabel: "淡出延迟",
        durationSecondsFormat: "%.1f 秒",
        showInCapturesToggle: "在录屏和截图中显示",
        showInCapturesCaption: "关闭后悬浮窗仍对你可见，但会在录屏、截图和屏幕共享中隐藏。",
        previewButton: "测试显示",
        privacyNote: "当 macOS 安全输入处于启用状态（如密码输入框）时会自动暂停。"
    )

    static let zhTW = KeystrokeOverlayStrings(
        pageTitle: "按鍵顯示",
        hubDescription: "在畫面上顯示按下的按鍵與快速鍵，適合展示與螢幕錄製",
        enableToggle: "在畫面上顯示按鍵",
        enableCaption: "輸入文字或按下快速鍵時，在畫面上浮動顯示簡潔的鍵帽提示。",
        activeNow: "正在顯示按鍵",
        styleLabel: "主題樣式",
        styleSvelte: "Svelte",
        styleKeycaps: "鍵帽",
        modeLabel: "顯示內容",
        modeAllKeys: "所有按鍵",
        modeShortcutsOnly: "僅快速鍵",
        modeCaption: "「僅快速鍵」會忽略一般打字，只顯示包含 ⌘、⌥、⌃ 或功能鍵的組合。",
        positionLabel: "畫面位置",
        positionBottomCenter: "底部置中",
        positionBottomLeft: "左下角",
        positionBottomRight: "右下角",
        positionTopCenter: "頂部置中",
        positionTopLeft: "左上角",
        positionTopRight: "右上角",
        dragPositionCaption: "可直接在畫面上拖曳浮動視窗，將其放置在任意自訂位置。",
        resetPositionButton: "重設自訂位置",
        sizeLabel: "顯示大小",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        durationLabel: "淡出延遲",
        durationSecondsFormat: "%.1f 秒",
        showInCapturesToggle: "在螢幕錄製與截圖中顯示",
        showInCapturesCaption: "關閉後浮動視窗仍對你可見，但會在螢幕錄製、截圖與螢幕共享中隱藏。",
        previewButton: "測試顯示",
        privacyNote: "當 macOS 安全輸入啟用時（例如密碼欄位），會自動暫停顯示。"
    )

    static let zhHK = KeystrokeOverlayStrings(
        pageTitle: "按鍵顯示",
        hubDescription: "喺畫面上顯示按下嘅按鍵同快捷鍵，適合示範同螢幕錄影",
        enableToggle: "喺畫面上顯示按鍵",
        enableCaption: "輸入文字或按下快捷鍵時，喺畫面上浮動顯示簡潔嘅鍵帽提示。",
        activeNow: "正在顯示按鍵",
        styleLabel: "主題樣式",
        styleSvelte: "Svelte",
        styleKeycaps: "鍵帽",
        modeLabel: "顯示內容",
        modeAllKeys: "所有按鍵",
        modeShortcutsOnly: "僅快捷鍵",
        modeCaption: "「僅快捷鍵」會忽略一般打字，只顯示包含 ⌘、⌥、⌃ 或功能鍵嘅組合。",
        positionLabel: "畫面位置",
        positionBottomCenter: "底部置中",
        positionBottomLeft: "左下角",
        positionBottomRight: "右下角",
        positionTopCenter: "頂部置中",
        positionTopLeft: "左上角",
        positionTopRight: "右上角",
        dragPositionCaption: "可以直接喺畫面上拖曳浮動視窗，擺放喺任何自訂位置。",
        resetPositionButton: "重設自訂位置",
        sizeLabel: "顯示大小",
        sizeSmall: "小",
        sizeMedium: "中",
        sizeLarge: "大",
        durationLabel: "淡出延遲",
        durationSecondsFormat: "%.1f 秒",
        showInCapturesToggle: "喺螢幕錄影同截圖中顯示",
        showInCapturesCaption: "關閉後浮動視窗依然對你可見，但會喺螢幕錄影、截圖同螢幕共享中隱藏。",
        previewButton: "測試顯示",
        privacyNote: "當 macOS 安全輸入啟用時（例如密碼欄），會自動暫停顯示。"
    )

    static let uk = KeystrokeOverlayStrings(
        pageTitle: "Відображення клавіш",
        hubDescription: "Показує натиснуті клавіші та скорочення на екрані для демонстрацій і записів",
        enableToggle: "Показувати натискання клавіш на екрані",
        enableCaption: "Показує компактну плаваючу панель із клавішами під час набору тексту або натискання скорочень.",
        activeNow: "Клавіші відображаються",
        styleLabel: "Тема",
        styleSvelte: "Svelte",
        styleKeycaps: "Клавіші",
        modeLabel: "Які клавіші показувати",
        modeAllKeys: "Усі клавіші",
        modeShortcutsOnly: "Лише скорочення",
        modeCaption: "Режим «Лише скорочення» пропускає звичайний набір і показує комбінації з ⌘, ⌥, ⌃ або функціональними клавішами.",
        positionLabel: "Позиція на екрані",
        positionBottomCenter: "Унизу по центру",
        positionBottomLeft: "Унизу ліворуч",
        positionBottomRight: "Унизу праворуч",
        positionTopCenter: "Угорі по центру",
        positionTopLeft: "Угорі ліворуч",
        positionTopRight: "Угорі праворуч",
        dragPositionCaption: "Перетягніть панель безпосередньо на екрані, щоб розмістити її в будь-якому місці.",
        resetPositionButton: "Скинути власну позицію",
        sizeLabel: "Розмір панелі",
        sizeSmall: "Малий",
        sizeMedium: "Середній",
        sizeLarge: "Великий",
        durationLabel: "Затримка зникнення",
        durationSecondsFormat: "%.1f с",
        showInCapturesToggle: "Показувати на записах і знімках екрана",
        showInCapturesCaption: "Якщо вимкнено, панель залишається видимою для вас, але приховується на записах, знімках і під час демонстрації екрана.",
        previewButton: "Перевірити панель",
        privacyNote: "Автоматично призупиняється в полях пароля, коли активне безпечне введення macOS."
    )
}
