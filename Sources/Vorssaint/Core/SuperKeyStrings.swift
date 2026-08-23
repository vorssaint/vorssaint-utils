// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SuperKeyStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let capsLockKey: String
    let holdHint: String
    let soloSection: String
    let soloCaption: String
    let soloNothing: String
    let soloCapsLock: String
    let soloEscape: String
    let activeNow: String
    let panelCaptionFormat: String
    let manageButton: String
    let soloInputSource: String
}

extension FeatureStrings {
    static func superKey(_ language: AppLanguage) -> SuperKeyStrings {
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

extension SuperKeyStrings {
    static let enUS = SuperKeyStrings(
        pageTitle: "Super key",
        hubDescription: "Turns Caps Lock into the modifier combination you choose.",
        enableToggle: "Use Caps Lock as the super key",
        enableCaption: "Hold it and press any key. Choose one or more modifiers below.",
        capsLockKey: "Caps Lock",
        holdHint: "Hold",
        soloSection: "A tap on its own",
        soloCaption: "What a quick tap does when no other key is pressed.",
        soloNothing: "Nothing",
        soloCapsLock: "Turn capitals on and off",
        soloEscape: "Press Escape",
        activeNow: "Working now",
        panelCaptionFormat: "Caps Lock holds %@.",
        manageButton: "Set up…",
        soloInputSource: "Switch input source; hold for Caps Lock"
    )

    static let ptBR = SuperKeyStrings(
        pageTitle: "Tecla super",
        hubDescription: "Transforma o Caps Lock na combinação de modificadores que você escolher.",
        enableToggle: "Usar o Caps Lock como tecla super",
        enableCaption: "Segure e aperte qualquer tecla. Escolha um ou mais modificadores abaixo.",
        capsLockKey: "Caps Lock",
        holdHint: "Segure",
        soloSection: "Um toque sozinho",
        soloCaption: "O que um toque rápido faz quando nenhuma outra tecla é apertada.",
        soloNothing: "Nada",
        soloCapsLock: "Liga e desliga as maiúsculas",
        soloEscape: "Aperta Escape",
        activeNow: "Funcionando agora",
        panelCaptionFormat: "O Caps Lock segura %@.",
        manageButton: "Configurar…",
        soloInputSource: "Trocar fonte de entrada; segure para Caps Lock"
    )

    static let tr = SuperKeyStrings(
        pageTitle: "Süper tuş",
        hubDescription: "Caps Lock'u seçtiğiniz değiştirici tuş birleşimine dönüştürür.",
        enableToggle: "Caps Lock süper tuş olsun",
        enableCaption: "Basılı tutup herhangi bir tuşa basın. Aşağıdan bir veya daha fazla değiştirici seçin.",
        capsLockKey: "Caps Lock",
        holdHint: "Basılı tutun",
        soloSection: "Tek başına dokunuş",
        soloCaption: "Başka tuşa basılmadan yapılan hızlı dokunuş ne yapsın.",
        soloNothing: "Hiçbir şey",
        soloCapsLock: "Büyük harfi açar kapatır",
        soloEscape: "Escape tuşuna basar",
        activeNow: "Şu anda çalışıyor",
        panelCaptionFormat: "Caps Lock %@ tuşlarını basılı tutar.",
        manageButton: "Ayarla…",
        soloInputSource: "Giriş kaynağını değiştir; Caps Lock için basılı tut"
    )

    static let ru = SuperKeyStrings(
        pageTitle: "Суперклавиша",
        hubDescription: "Превращает Caps Lock в выбранное сочетание клавиш-модификаторов.",
        enableToggle: "Использовать Caps Lock как суперклавишу",
        enableCaption: "Удерживайте её и нажмите любую клавишу. Выберите ниже один или несколько модификаторов.",
        capsLockKey: "Caps Lock",
        holdHint: "Удерживайте",
        soloSection: "Одиночное нажатие",
        soloCaption: "Что делает быстрое нажатие, если других клавиш не было.",
        soloNothing: "Ничего",
        soloCapsLock: "Включает и выключает заглавные",
        soloEscape: "Нажимает Escape",
        activeNow: "Работает",
        panelCaptionFormat: "Caps Lock удерживает %@.",
        manageButton: "Настроить…",
        soloInputSource: "Сменить источник ввода; удерживать для Caps Lock"
    )

    static let es = SuperKeyStrings(
        pageTitle: "Tecla súper",
        hubDescription: "Convierte Bloq Mayús en la combinación de modificadores que elijas.",
        enableToggle: "Usar Bloq Mayús como tecla súper",
        enableCaption: "Mantenla pulsada y pulsa cualquier tecla. Elige uno o más modificadores abajo.",
        capsLockKey: "Bloq Mayús",
        holdHint: "Mantén",
        soloSection: "Un toque suelto",
        soloCaption: "Qué hace un toque rápido cuando no se pulsa ninguna otra tecla.",
        soloNothing: "Nada",
        soloCapsLock: "Activa y desactiva las mayúsculas",
        soloEscape: "Pulsa Escape",
        activeNow: "Funcionando ahora",
        panelCaptionFormat: "Bloq Mayús mantiene %@.",
        manageButton: "Configurar…",
        soloInputSource: "Cambiar fuente de entrada; mantener para Bloq Mayús"
    )

    static let de = SuperKeyStrings(
        pageTitle: "Supertaste",
        hubDescription: "Macht die Feststelltaste zu deiner gewählten Sondertastenkombination.",
        enableToggle: "Feststelltaste als Supertaste verwenden",
        enableCaption: "Halte sie und drücke eine beliebige Taste. Wähle unten eine oder mehrere Sondertasten.",
        capsLockKey: "Feststelltaste",
        holdHint: "Halten",
        soloSection: "Ein einzelner Tastendruck",
        soloCaption: "Was ein kurzer Druck bewirkt, wenn keine andere Taste dabei ist.",
        soloNothing: "Nichts",
        soloCapsLock: "Großbuchstaben ein und aus",
        soloEscape: "Drückt Escape",
        activeNow: "Läuft gerade",
        panelCaptionFormat: "Die Feststelltaste hält %@.",
        manageButton: "Einrichten…",
        soloInputSource: "Eingabequelle wechseln; für Feststelltaste halten"
    )

    static let fr = SuperKeyStrings(
        pageTitle: "Touche super",
        hubDescription: "Transforme Verr. Maj en la combinaison de modificateurs de votre choix.",
        enableToggle: "Utiliser Verr. Maj comme touche super",
        enableCaption: "Maintenez-la et appuyez sur n'importe quelle touche. Choisissez un ou plusieurs modificateurs ci-dessous.",
        capsLockKey: "Verr. Maj",
        holdHint: "Maintenez",
        soloSection: "Un appui seul",
        soloCaption: "Ce que fait un appui rapide quand aucune autre touche n'est pressée.",
        soloNothing: "Rien",
        soloCapsLock: "Active et désactive les majuscules",
        soloEscape: "Appuie sur Échap",
        activeNow: "Actif maintenant",
        panelCaptionFormat: "Verr. Maj maintient %@.",
        manageButton: "Configurer…",
        soloInputSource: "Changer de source d’entrée ; maintenir pour Verr. Maj"
    )

    static let it = SuperKeyStrings(
        pageTitle: "Tasto super",
        hubDescription: "Trasforma Blocco Maiuscole nella combinazione di modificatori che scegli.",
        enableToggle: "Usa Blocco Maiuscole come tasto super",
        enableCaption: "Tienilo premuto e premi un tasto qualsiasi. Scegli uno o più modificatori qui sotto.",
        capsLockKey: "Blocco Maiuscole",
        holdHint: "Tieni premuto",
        soloSection: "Un tocco da solo",
        soloCaption: "Cosa fa un tocco veloce quando non premi nessun altro tasto.",
        soloNothing: "Niente",
        soloCapsLock: "Attiva e disattiva le maiuscole",
        soloEscape: "Preme Escape",
        activeNow: "Attivo ora",
        panelCaptionFormat: "Blocco Maiuscole tiene premuti %@.",
        manageButton: "Configura…",
        soloInputSource: "Cambia sorgente di input; tieni premuto per Blocco Maiuscole"
    )

    static let ja = SuperKeyStrings(
        pageTitle: "スーパーキー",
        hubDescription: "Caps Lock を選んだ修飾キーの組み合わせに変えます。",
        enableToggle: "Caps Lock をスーパーキーとして使う",
        enableCaption: "押したまま好きなキーを押してください。下から1つ以上の修飾キーを選びます。",
        capsLockKey: "Caps Lock",
        holdHint: "押したまま",
        soloSection: "単独で押したとき",
        soloCaption: "ほかのキーを押さずに軽く押したときの動作です。",
        soloNothing: "何もしない",
        soloCapsLock: "大文字を切り替える",
        soloEscape: "Escape を押す",
        activeNow: "動作中",
        panelCaptionFormat: "Caps Lock が %@ を押した状態にします。",
        manageButton: "設定…",
        soloInputSource: "入力ソースを切り替え（長押しで Caps Lock）"
    )

    static let ko = SuperKeyStrings(
        pageTitle: "슈퍼 키",
        hubDescription: "Caps Lock을 선택한 조합 키 묶음으로 바꿉니다.",
        enableToggle: "Caps Lock을 슈퍼 키로 사용",
        enableCaption: "누른 채로 아무 키나 누르세요. 아래에서 조합 키를 하나 이상 선택하세요.",
        capsLockKey: "Caps Lock",
        holdHint: "누른 채로",
        soloSection: "혼자 눌렀을 때",
        soloCaption: "다른 키 없이 가볍게 눌렀을 때의 동작입니다.",
        soloNothing: "아무 동작 없음",
        soloCapsLock: "대문자 켜고 끄기",
        soloEscape: "Escape 누르기",
        activeNow: "지금 작동 중",
        panelCaptionFormat: "Caps Lock이 %@를 누른 상태로 만듭니다.",
        manageButton: "설정…",
        soloInputSource: "입력 소스 전환(길게 눌러 Caps Lock)"
    )

    static let zhHans = SuperKeyStrings(
        pageTitle: "超级键",
        hubDescription: "把大写锁定键变成你选择的修饰键组合。",
        enableToggle: "把大写锁定键当作超级键",
        enableCaption: "按住它再按任意键。请在下方选择一个或多个修饰键。",
        capsLockKey: "大写锁定",
        holdHint: "按住",
        soloSection: "单独轻按",
        soloCaption: "没有按下其他键时，轻按一下会做什么。",
        soloNothing: "什么都不做",
        soloCapsLock: "开关大写",
        soloEscape: "按下 Escape",
        activeNow: "正在运行",
        panelCaptionFormat: "大写锁定键会按住 %@。",
        manageButton: "设置…",
        soloInputSource: "切换输入法；长按开关大写锁定"
    )

    static let zhTW = SuperKeyStrings(
        pageTitle: "超級鍵",
        hubDescription: "把大寫鎖定鍵變成你選擇的修飾鍵組合。",
        enableToggle: "把大寫鎖定鍵當作超級鍵",
        enableCaption: "按住它再按任何鍵。請在下方選擇一個或多個修飾鍵。",
        capsLockKey: "大寫鎖定",
        holdHint: "按住",
        soloSection: "單獨輕按",
        soloCaption: "沒有按下其他鍵時，輕按一下會做什麼。",
        soloNothing: "什麼都不做",
        soloCapsLock: "開關大寫",
        soloEscape: "按下 Escape",
        activeNow: "正在運作",
        panelCaptionFormat: "大寫鎖定鍵會按住 %@。",
        manageButton: "設定…",
        soloInputSource: "切換輸入法；長按切換大寫鎖定"
    )

    static let zhHK = SuperKeyStrings(
        pageTitle: "超級鍵",
        hubDescription: "將大寫鎖定鍵變成你揀嘅修飾鍵組合。",
        enableToggle: "把大寫鎖定鍵當作超級鍵",
        enableCaption: "按住佢再撳任何鍵。喺下面揀一個或多個修飾鍵。",
        capsLockKey: "大寫鎖定",
        holdHint: "按住",
        soloSection: "單獨輕撳",
        soloCaption: "無撳其他鍵嘅時候，輕撳一下會做乜。",
        soloNothing: "咩都唔做",
        soloCapsLock: "開關大寫",
        soloEscape: "撳 Escape",
        activeNow: "正在運作",
        panelCaptionFormat: "大寫鎖定鍵會按住 %@。",
        manageButton: "設定…",
        soloInputSource: "切換輸入法；長撳切換大寫鎖定"
    )
}
