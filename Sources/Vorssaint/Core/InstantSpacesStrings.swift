// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct InstantSpacesStrings {
    let title: String
    let description: String
    let keyboard: String
    let keyboardCaption: String
    let trackpad: String
    let trackpadCaption: String
    let compatibility: String
    let unavailable: String
}

extension FeatureStrings {
    static func instantSpaces(_ language: AppLanguage) -> InstantSpacesStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .de: return .de
        case .fr: return .fr
        case .es: return .es
        case .sk: return .sk
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension InstantSpacesStrings {
    static let sk = InstantSpacesStrings(
        title: "Okamžité prepínanie plôch",
        description: "Prepínajte medzi plochami bez animácie posúvania.",
        keyboard: "Okamžité prepínanie plôch klávesnicou",
        keyboardCaption: "Používa zapnuté skratky plôch zo Systémových nastavení. Skratky na plochy na inom displeji si zachovajú pôvodné správanie.",
        trackpad: "Okamžité prepínanie potiahnutím na trackpade",
        trackpadCaption: "Použite nastavené potiahnutie tromi alebo štyrmi prstami. Pred zdvihnutím prstov zmeňte smer a prepnete späť.",
        compatibility: "Vyžaduje macOS 15–27. Mission Control a presúvanie okien si zachovajú pôvodné správanie.",
        unavailable: "Nepodarilo sa spustiť sledovanie vstupu. Skontrolujte prístup k Prístupnosti a potom funkciu vypnite a znova zapnite."
    )

    static let uk = InstantSpacesStrings(
        title: "Миттєве перемикання просторів",
        description: "Перемикайте робочі столи без анімації зсуву.",
        keyboard: "Миттєве перемикання клавіатурою",
        keyboardCaption: "Використовує ввімкнені клавіатурні скорочення просторів із Системних параметрів. Скорочення для робочих столів на іншому дисплеї зберігають звичайну поведінку.",
        trackpad: "Миттєве перемикання жестом трекпеда",
        trackpadCaption: "Використовуйте налаштований жест трьома або чотирма пальцями. Змініть напрямок, не піднімаючи пальців, щоб повернутися назад.",
        compatibility: "Потрібна macOS 15–27. Mission Control і перетягування вікон зберігають звичайну поведінку.",
        unavailable: "Не вдалося запустити відстеження введення. Перевірте дозвіл Доступності, потім вимкніть і знову ввімкніть функцію."
    )

    static let enUS = InstantSpacesStrings(
        title: "Instant Spaces",
        description: "Switch desktops without the sliding animation.",
        keyboard: "Instant Space switch",
        keyboardCaption: "Uses the enabled Space shortcuts from System Settings. Shortcuts to desktops on another display keep their native behavior.",
        trackpad: "Instant trackpad swipe",
        trackpadCaption: "Use your configured three- or four-finger swipe. Reverse direction before lifting your fingers to switch back.",
        compatibility: "Requires macOS 15–27. Mission Control and window dragging keep their native behavior.",
        unavailable: "The input listener could not start. Check Accessibility access, then turn the feature off and on."
    )

    static let ptBR = InstantSpacesStrings(
        title: "Spaces instantâneos",
        description: "Alterne entre mesas sem a animação de deslizamento.",
        keyboard: "Troca instantânea de mesa",
        keyboardCaption: "Usa os atalhos de Spaces ativados nos Ajustes do Sistema. Atalhos para mesas em outra tela mantêm o comportamento nativo.",
        trackpad: "Deslize instantâneo no trackpad",
        trackpadCaption: "Use o gesto configurado de três ou quatro dedos. Inverta a direção antes de levantar os dedos para voltar.",
        compatibility: "Requer macOS 15–27. Mission Control e arrastar janelas mantêm o comportamento nativo.",
        unavailable: "Não foi possível iniciar a captura de entrada. Verifique o acesso à Acessibilidade e desative e reative o recurso."
    )

    static let de = InstantSpacesStrings(
        title: "Sofortige Spaces",
        description: "Wechsle Schreibtische ohne Schiebeanimation.",
        keyboard: "Sofortiger Schreibtischwechsel",
        keyboardCaption: "Verwendet die aktivierten Spaces-Kurzbefehle aus den Systemeinstellungen. Kurzbefehle zu Schreibtischen auf anderen Displays behalten ihr natives Verhalten.",
        trackpad: "Sofortiges Trackpad-Wischen",
        trackpadCaption: "Verwende die eingestellte Wischgeste mit drei oder vier Fingern. Kehre die Richtung vor dem Anheben der Finger um, um zurückzuwechseln.",
        compatibility: "Erfordert macOS 15–27. Mission Control und das Ziehen von Fenstern behalten ihr natives Verhalten.",
        unavailable: "Die Eingabeüberwachung konnte nicht starten. Prüfe den Bedienungshilfenzugriff und schalte die Funktion aus und wieder ein."
    )

    static let fr = InstantSpacesStrings(
        title: "Spaces instantanés",
        description: "Changez de bureau sans animation de glissement.",
        keyboard: "Changement de bureau instantané",
        keyboardCaption: "Utilise les raccourcis Spaces activés dans Réglages Système. Les raccourcis vers les bureaux d’un autre écran conservent leur comportement natif.",
        trackpad: "Balayage instantané du trackpad",
        trackpadCaption: "Utilisez le balayage configuré à trois ou quatre doigts. Inversez le mouvement avant de lever les doigts pour revenir.",
        compatibility: "Nécessite macOS 15–27. Mission Control et le déplacement des fenêtres conservent leur comportement natif.",
        unavailable: "L’écoute des entrées n’a pas pu démarrer. Vérifiez l’accès à Accessibilité, puis désactivez et réactivez la fonction."
    )

    static let es = InstantSpacesStrings(
        title: "Spaces instantáneos",
        description: "Cambia de escritorio sin la animación de deslizamiento.",
        keyboard: "Cambio de escritorio instantáneo",
        keyboardCaption: "Usa los atajos de Spaces activados en Ajustes del Sistema. Los atajos a escritorios de otra pantalla conservan su comportamiento nativo.",
        trackpad: "Deslizamiento instantáneo del trackpad",
        trackpadCaption: "Usa el gesto configurado de tres o cuatro dedos. Invierte la dirección antes de levantar los dedos para volver.",
        compatibility: "Requiere macOS 15–27. Mission Control y el arrastre de ventanas conservan su comportamiento nativo.",
        unavailable: "No se pudo iniciar la captura de entrada. Comprueba el acceso a Accesibilidad y desactiva y vuelve a activar la función."
    )

    static let it = InstantSpacesStrings(
        title: "Spaces istantanei",
        description: "Cambia scrivania senza l’animazione di scorrimento.",
        keyboard: "Cambio scrivania istantaneo",
        keyboardCaption: "Usa le abbreviazioni Spaces abilitate in Impostazioni di Sistema. Quelle per le scrivanie su altri schermi mantengono il comportamento nativo.",
        trackpad: "Scorrimento istantaneo sul trackpad",
        trackpadCaption: "Usa il gesto configurato con tre o quattro dita. Inverti la direzione prima di sollevare le dita per tornare indietro.",
        compatibility: "Richiede macOS 15–27. Mission Control e il trascinamento delle finestre mantengono il comportamento nativo.",
        unavailable: "Impossibile avviare il rilevamento degli input. Controlla l’accesso ad Accessibilità, poi disattiva e riattiva la funzione."
    )

    static let ru = InstantSpacesStrings(
        title: "Мгновенные Spaces",
        description: "Переключайте рабочие столы без анимации сдвига.",
        keyboard: "Мгновенная смена рабочего стола",
        keyboardCaption: "Использует включённые сочетания Spaces из Системных настроек. Переходы к рабочим столам на другом дисплее работают как обычно.",
        trackpad: "Мгновенный смах на трекпаде",
        trackpadCaption: "Используйте настроенный жест тремя или четырьмя пальцами. Измените направление до отрыва пальцев, чтобы вернуться.",
        compatibility: "Требуется macOS 15–27. Mission Control и перетаскивание окон работают как обычно.",
        unavailable: "Не удалось начать отслеживание ввода. Проверьте доступ к Универсальному доступу, затем выключите и включите функцию."
    )

    static let tr = InstantSpacesStrings(
        title: "Anında Spaces",
        description: "Kaydırma animasyonu olmadan masaüstleri arasında geçiş yapın.",
        keyboard: "Anında masaüstü geçişi",
        keyboardCaption: "Sistem Ayarları’nda etkinleştirilen Spaces kestirmelerini kullanır. Başka bir ekrandaki masaüstlerine giden kestirmeler yerel davranışını korur.",
        trackpad: "Anında izleme dörtgeni kaydırması",
        trackpadCaption: "Ayarladığınız üç veya dört parmak hareketini kullanın. Geri dönmek için parmaklarınızı kaldırmadan yönü tersine çevirin.",
        compatibility: "macOS 15–27 gerektirir. Mission Control ve pencere sürükleme yerel davranışını korur.",
        unavailable: "Girdi dinleyicisi başlatılamadı. Erişilebilirlik iznini kontrol edip özelliği kapatın ve yeniden açın."
    )

    static let ja = InstantSpacesStrings(
        title: "瞬時のSpaces切り替え",
        description: "スライドアニメーションなしでデスクトップを切り替えます。",
        keyboard: "デスクトップを瞬時に切り替える",
        keyboardCaption: "システム設定で有効なSpacesのショートカットを使います。別のディスプレイへの切り替えは通常どおり動作します。",
        trackpad: "トラックパッドで瞬時に切り替える",
        trackpadCaption: "設定済みの3本指または4本指のスワイプを使います。指を離す前に逆方向へ動かすと戻ります。",
        compatibility: "macOS 15〜27が必要です。Mission Controlとウインドウのドラッグは通常どおり動作します。",
        unavailable: "入力の監視を開始できませんでした。アクセシビリティの許可を確認し、機能をオフにしてから再度オンにしてください。"
    )

    static let ko = InstantSpacesStrings(
        title: "즉시 Spaces 전환",
        description: "슬라이드 애니메이션 없이 데스크탑을 전환합니다.",
        keyboard: "즉시 데스크탑 전환",
        keyboardCaption: "시스템 설정에서 활성화한 Spaces 단축키를 사용합니다. 다른 디스플레이의 데스크탑으로 이동하는 단축키는 기본 동작을 유지합니다.",
        trackpad: "즉시 트랙패드 쓸어넘기기",
        trackpadCaption: "설정한 세 손가락 또는 네 손가락 제스처를 사용합니다. 손가락을 떼기 전에 방향을 바꾸면 돌아갑니다.",
        compatibility: "macOS 15–27이 필요합니다. Mission Control과 윈도우 드래그는 기본 동작을 유지합니다.",
        unavailable: "입력 감시를 시작할 수 없습니다. 손쉬운 사용 권한을 확인한 뒤 기능을 껐다 켜세요."
    )

    static let zhHans = InstantSpacesStrings(
        title: "即时切换空间",
        description: "切换桌面时不显示滑动动画。",
        keyboard: "即时切换桌面",
        keyboardCaption: "使用系统设置中已启用的空间快捷键。切换到其他显示器桌面的快捷键保留系统原有行为。",
        trackpad: "即时触控板轻扫",
        trackpadCaption: "使用已设置的三指或四指轻扫。抬起手指前反向滑动即可返回。",
        compatibility: "需要 macOS 15–27。调度中心和拖移窗口保留系统原有行为。",
        unavailable: "无法启动输入监听。请检查辅助功能权限，然后关闭并重新开启此功能。"
    )

    static let zhTW = InstantSpacesStrings(
        title: "即時切換空間",
        description: "切換桌面時不顯示滑動動畫。",
        keyboard: "即時切換桌面",
        keyboardCaption: "使用系統設定中已啟用的空間快捷鍵。切換至其他顯示器桌面的快捷鍵保留系統原有行為。",
        trackpad: "即時觸控式軌跡板滑動",
        trackpadCaption: "使用已設定的三指或四指滑動。在抬起手指前反向滑動即可返回。",
        compatibility: "需要 macOS 15–27。指揮中心和拖移視窗保留系統原有行為。",
        unavailable: "無法啟動輸入監聽。請檢查輔助使用權限，然後關閉並重新開啟此功能。"
    )

    static let zhHK = InstantSpacesStrings(
        title: "即時切換空間",
        description: "切換桌面時不顯示滑動動畫。",
        keyboard: "即時切換桌面",
        keyboardCaption: "使用系統設定中已啟用的空間快捷鍵。切換至其他顯示器桌面的快捷鍵保留系統原有行為。",
        trackpad: "即時觸控式軌跡板滑動",
        trackpadCaption: "使用已設定的三指或四指滑動。在抬起手指前反向滑動即可返回。",
        compatibility: "需要 macOS 15–27。指揮中心和拖移視窗保留系統原有行為。",
        unavailable: "無法啟動輸入監聽。請檢查輔助使用權限，然後關閉並重新開啟此功能。"
    )
}
