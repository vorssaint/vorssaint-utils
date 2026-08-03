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
    let panelCaption: String
    let manageButton: String
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
        hubDescription: "Holds Shift, Control, Option and Command while you hold Caps Lock.",
        enableToggle: "Use Caps Lock as the super key",
        enableCaption: "Hold it and press any key. The four modifier keys go along, so your shortcuts stay out of every other app's way.",
        capsLockKey: "Caps Lock",
        holdHint: "Hold",
        soloSection: "A tap on its own",
        soloCaption: "What a quick tap does when no other key is pressed.",
        soloNothing: "Nothing",
        soloCapsLock: "Turn capitals on and off",
        soloEscape: "Press Escape",
        activeNow: "Working now",
        panelCaption: "Caps Lock holds Shift, Control, Option and Command.",
        manageButton: "Set up…"
    )

    static let ptBR = SuperKeyStrings(
        pageTitle: "Tecla super",
        hubDescription: "Segura Shift, Control, Option e Command enquanto você segura o Caps Lock.",
        enableToggle: "Usar o Caps Lock como tecla super",
        enableCaption: "Segure e aperte qualquer tecla. Os quatro modificadores vão junto, então seus atalhos não esbarram em nenhum app.",
        capsLockKey: "Caps Lock",
        holdHint: "Segure",
        soloSection: "Um toque sozinho",
        soloCaption: "O que um toque rápido faz quando nenhuma outra tecla é apertada.",
        soloNothing: "Nada",
        soloCapsLock: "Liga e desliga as maiúsculas",
        soloEscape: "Aperta Escape",
        activeNow: "Funcionando agora",
        panelCaption: "O Caps Lock segura Shift, Control, Option e Command.",
        manageButton: "Configurar…"
    )

    static let tr = SuperKeyStrings(
        pageTitle: "Süper tuş",
        hubDescription: "Caps Lock tuşunu basılı tuttuğunuz sürece Shift, Control, Option ve Command basılı kalır.",
        enableToggle: "Caps Lock süper tuş olsun",
        enableCaption: "Basılı tutun ve herhangi bir tuşa basın. Dört değiştirici tuş da gider, böylece kısayollarınız başka uygulamalarla çakışmaz.",
        capsLockKey: "Caps Lock",
        holdHint: "Basılı tutun",
        soloSection: "Tek başına dokunuş",
        soloCaption: "Başka tuşa basılmadan yapılan hızlı dokunuş ne yapsın.",
        soloNothing: "Hiçbir şey",
        soloCapsLock: "Büyük harfi açar kapatır",
        soloEscape: "Escape tuşuna basar",
        activeNow: "Şu anda çalışıyor",
        panelCaption: "Caps Lock, Shift, Control, Option ve Command tuşlarını basılı tutar.",
        manageButton: "Ayarla…"
    )

    static let ru = SuperKeyStrings(
        pageTitle: "Суперклавиша",
        hubDescription: "Удерживает Shift, Control, Option и Command, пока вы держите Caps Lock.",
        enableToggle: "Использовать Caps Lock как суперклавишу",
        enableCaption: "Удерживайте её и нажмите любую клавишу. Все четыре модификатора идут вместе, поэтому ваши сочетания не спорят с другими приложениями.",
        capsLockKey: "Caps Lock",
        holdHint: "Удерживайте",
        soloSection: "Одиночное нажатие",
        soloCaption: "Что делает быстрое нажатие, если других клавиш не было.",
        soloNothing: "Ничего",
        soloCapsLock: "Включает и выключает заглавные",
        soloEscape: "Нажимает Escape",
        activeNow: "Работает",
        panelCaption: "Caps Lock удерживает Shift, Control, Option и Command.",
        manageButton: "Настроить…"
    )

    static let es = SuperKeyStrings(
        pageTitle: "Tecla súper",
        hubDescription: "Mantiene Shift, Control, Option y Command mientras mantienes Bloq Mayús.",
        enableToggle: "Usar Bloq Mayús como tecla súper",
        enableCaption: "Mantenla pulsada y pulsa cualquier tecla. Los cuatro modificadores van juntos, así tus atajos no chocan con los de ninguna app.",
        capsLockKey: "Bloq Mayús",
        holdHint: "Mantén",
        soloSection: "Un toque suelto",
        soloCaption: "Qué hace un toque rápido cuando no se pulsa ninguna otra tecla.",
        soloNothing: "Nada",
        soloCapsLock: "Activa y desactiva las mayúsculas",
        soloEscape: "Pulsa Escape",
        activeNow: "Funcionando ahora",
        panelCaption: "Bloq Mayús mantiene Shift, Control, Option y Command.",
        manageButton: "Configurar…"
    )

    static let de = SuperKeyStrings(
        pageTitle: "Supertaste",
        hubDescription: "Hält Shift, Control, Option und Command, solange du die Feststelltaste hältst.",
        enableToggle: "Feststelltaste als Supertaste verwenden",
        enableCaption: "Halte sie und drücke eine beliebige Taste. Alle vier Sondertasten kommen mit, damit deine Kurzbefehle keiner App in die Quere kommen.",
        capsLockKey: "Feststelltaste",
        holdHint: "Halten",
        soloSection: "Ein einzelner Tastendruck",
        soloCaption: "Was ein kurzer Druck bewirkt, wenn keine andere Taste dabei ist.",
        soloNothing: "Nichts",
        soloCapsLock: "Großbuchstaben ein und aus",
        soloEscape: "Drückt Escape",
        activeNow: "Läuft gerade",
        panelCaption: "Die Feststelltaste hält Shift, Control, Option und Command.",
        manageButton: "Einrichten…"
    )

    static let fr = SuperKeyStrings(
        pageTitle: "Touche super",
        hubDescription: "Maintient Shift, Control, Option et Command tant que vous maintenez Verr. Maj.",
        enableToggle: "Utiliser Verr. Maj comme touche super",
        enableCaption: "Maintenez-la et appuyez sur n'importe quelle touche. Les quatre modificateurs suivent, vos raccourcis ne gênent donc aucune app.",
        capsLockKey: "Verr. Maj",
        holdHint: "Maintenez",
        soloSection: "Un appui seul",
        soloCaption: "Ce que fait un appui rapide quand aucune autre touche n'est pressée.",
        soloNothing: "Rien",
        soloCapsLock: "Active et désactive les majuscules",
        soloEscape: "Appuie sur Échap",
        activeNow: "Actif maintenant",
        panelCaption: "Verr. Maj maintient Shift, Control, Option et Command.",
        manageButton: "Configurer…"
    )

    static let it = SuperKeyStrings(
        pageTitle: "Tasto super",
        hubDescription: "Tiene premuti Shift, Control, Option e Command mentre tieni premuto Blocco Maiuscole.",
        enableToggle: "Usa Blocco Maiuscole come tasto super",
        enableCaption: "Tienilo premuto e premi un tasto qualsiasi. I quattro modificatori vanno insieme, così le tue scorciatoie non danno fastidio a nessuna app.",
        capsLockKey: "Blocco Maiuscole",
        holdHint: "Tieni premuto",
        soloSection: "Un tocco da solo",
        soloCaption: "Cosa fa un tocco veloce quando non premi nessun altro tasto.",
        soloNothing: "Niente",
        soloCapsLock: "Attiva e disattiva le maiuscole",
        soloEscape: "Preme Escape",
        activeNow: "Attivo ora",
        panelCaption: "Blocco Maiuscole tiene premuti Shift, Control, Option e Command.",
        manageButton: "Configura…"
    )

    static let ja = SuperKeyStrings(
        pageTitle: "スーパーキー",
        hubDescription: "Caps Lock を押している間、Shift、Control、Option、Command を押した状態にします。",
        enableToggle: "Caps Lock をスーパーキーとして使う",
        enableCaption: "押したまま好きなキーを押してください。4つの修飾キーが一緒に付くので、ほかのアプリのショートカットとぶつかりません。",
        capsLockKey: "Caps Lock",
        holdHint: "押したまま",
        soloSection: "単独で押したとき",
        soloCaption: "ほかのキーを押さずに軽く押したときの動作です。",
        soloNothing: "何もしない",
        soloCapsLock: "大文字を切り替える",
        soloEscape: "Escape を押す",
        activeNow: "動作中",
        panelCaption: "Caps Lock が Shift、Control、Option、Command を押した状態にします。",
        manageButton: "設定…"
    )

    static let ko = SuperKeyStrings(
        pageTitle: "슈퍼 키",
        hubDescription: "Caps Lock을 누르고 있는 동안 Shift, Control, Option, Command를 함께 누릅니다.",
        enableToggle: "Caps Lock을 슈퍼 키로 사용",
        enableCaption: "누른 채로 아무 키나 누르세요. 네 개의 조합 키가 함께 가므로 단축키가 다른 앱과 겹치지 않습니다.",
        capsLockKey: "Caps Lock",
        holdHint: "누른 채로",
        soloSection: "혼자 눌렀을 때",
        soloCaption: "다른 키 없이 가볍게 눌렀을 때의 동작입니다.",
        soloNothing: "아무 동작 없음",
        soloCapsLock: "대문자 켜고 끄기",
        soloEscape: "Escape 누르기",
        activeNow: "지금 작동 중",
        panelCaption: "Caps Lock이 Shift, Control, Option, Command를 누른 상태로 만듭니다.",
        manageButton: "설정…"
    )

    static let zhHans = SuperKeyStrings(
        pageTitle: "超级键",
        hubDescription: "按住大写锁定键时，同时按住 Shift、Control、Option 和 Command。",
        enableToggle: "把大写锁定键当作超级键",
        enableCaption: "按住它再按任意键，四个修饰键会一起附上，你的快捷键就不会和别的 App 撞车。",
        capsLockKey: "大写锁定",
        holdHint: "按住",
        soloSection: "单独轻按",
        soloCaption: "没有按下其他键时，轻按一下会做什么。",
        soloNothing: "什么都不做",
        soloCapsLock: "开关大写",
        soloEscape: "按下 Escape",
        activeNow: "正在运行",
        panelCaption: "大写锁定键会按住 Shift、Control、Option 和 Command。",
        manageButton: "设置…"
    )

    static let zhTW = SuperKeyStrings(
        pageTitle: "超級鍵",
        hubDescription: "按住大寫鎖定鍵時，同時按住 Shift、Control、Option 和 Command。",
        enableToggle: "把大寫鎖定鍵當作超級鍵",
        enableCaption: "按住它再按任何鍵，四個修飾鍵會一起附上，你的快速鍵就不會和其他 App 打架。",
        capsLockKey: "大寫鎖定",
        holdHint: "按住",
        soloSection: "單獨輕按",
        soloCaption: "沒有按下其他鍵時，輕按一下會做什麼。",
        soloNothing: "什麼都不做",
        soloCapsLock: "開關大寫",
        soloEscape: "按下 Escape",
        activeNow: "正在運作",
        panelCaption: "大寫鎖定鍵會按住 Shift、Control、Option 和 Command。",
        manageButton: "設定…"
    )

    static let zhHK = SuperKeyStrings(
        pageTitle: "超級鍵",
        hubDescription: "按住大寫鎖定鍵時，同時按住 Shift、Control、Option 和 Command。",
        enableToggle: "把大寫鎖定鍵當作超級鍵",
        enableCaption: "按住佢再撳任何鍵，四個修飾鍵會一齊附上，你嘅快速鍵就唔會同其他 App 撞。",
        capsLockKey: "大寫鎖定",
        holdHint: "按住",
        soloSection: "單獨輕撳",
        soloCaption: "無撳其他鍵嘅時候，輕撳一下會做乜。",
        soloNothing: "咩都唔做",
        soloCapsLock: "開關大寫",
        soloEscape: "撳 Escape",
        activeNow: "正在運作",
        panelCaption: "大寫鎖定鍵會按住 Shift、Control、Option 和 Command。",
        manageButton: "設定…"
    )
}
