// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SuperKeyStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let modifierKeysNote: String
    let sourceKey: String
    let capsLockKey: String
    let rightKeyFormat: String
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
    let mappingForeignMapping: String
    let mappingSystemRefused: String

    /// What to show when the key mapping was refused. Every refusal names one
    /// thing to change; none of them is visible in the key itself.
    func mappingFailure(_ failure: SuperKeyMappingFailure) -> String {
        switch failure {
        case .foreignMapping: return mappingForeignMapping
        case .systemRefused: return mappingSystemRefused
        }
    }
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
    func sourceLabel(_ source: SuperKeySource) -> String {
        guard let symbol = source.symbol else { return capsLockKey }
        return String(format: rightKeyFormat, symbol)
    }

    static let enUS = SuperKeyStrings(
        pageTitle: "Super key",
        hubDescription: "Turns one key into the modifier combination you choose.",
        enableToggle: "Use this key as the super key",
        enableCaption: "Hold it and press any key. Choose one or more modifiers below.",
        modifierKeysNote: "Keep this key set to its default action in System Settings › Keyboard › Modifier Keys.",
        sourceKey: "Key to hold",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "Right %@",
        holdHint: "Hold",
        soloSection: "A tap on its own",
        soloCaption: "What a quick tap does when no other key is pressed.",
        soloNothing: "Nothing",
        soloCapsLock: "Turn capitals on and off",
        soloEscape: "Press Escape",
        activeNow: "Working now",
        panelCaptionFormat: "%1$@ holds %2$@.",
        manageButton: "Set up…",
        soloInputSource: "Switch input source; hold for Caps Lock",
        mappingForeignMapping: "Another app's key mapping uses the selected key. Remove it in that app: quitting it is not enough.",
        mappingSystemRefused: "macOS refused the key mapping. Reconnect the keyboard or restart the Mac, then switch this on again."
    )

    static let ptBR = SuperKeyStrings(
        pageTitle: "Tecla super",
        hubDescription: "Transforma uma tecla na combinação de modificadores que você escolher.",
        enableToggle: "Usar esta tecla como tecla super",
        enableCaption: "Segure e aperte qualquer tecla. Escolha um ou mais modificadores abaixo.",
        modifierKeysNote: "Mantenha esta tecla com a ação padrão em Ajustes do Sistema › Teclado › Teclas Modificadoras.",
        sourceKey: "Tecla para segurar",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "Direita %@",
        holdHint: "Segure",
        soloSection: "Um toque sozinho",
        soloCaption: "O que um toque rápido faz quando nenhuma outra tecla é apertada.",
        soloNothing: "Nada",
        soloCapsLock: "Liga e desliga as maiúsculas",
        soloEscape: "Aperta Escape",
        activeNow: "Funcionando agora",
        panelCaptionFormat: "%1$@ segura %2$@.",
        manageButton: "Configurar…",
        soloInputSource: "Trocar fonte de entrada; segure para Caps Lock",
        mappingForeignMapping: "O mapeamento de outro app usa a tecla selecionada. Remova-o naquele app: sair dele não basta.",
        mappingSystemRefused: "O macOS recusou o mapeamento de teclas. Reconecte o teclado ou reinicie o Mac e ligue isto de novo."
    )

    static let tr = SuperKeyStrings(
        pageTitle: "Süper tuş",
        hubDescription: "Bir tuşu seçtiğiniz değiştirici tuş birleşimine dönüştürür.",
        enableToggle: "Bu tuşu süper tuş olarak kullan",
        enableCaption: "Basılı tutup herhangi bir tuşa basın. Aşağıdan bir veya daha fazla değiştirici seçin.",
        modifierKeysNote: "Bu tuşu Sistem Ayarları › Klavye › Niteleme Tuşları bölümünde varsayılan eyleminde bırakın.",
        sourceKey: "Basılı tutulacak tuş",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "Sağ %@",
        holdHint: "Basılı tutun",
        soloSection: "Tek başına dokunuş",
        soloCaption: "Başka tuşa basılmadan yapılan hızlı dokunuş ne yapsın.",
        soloNothing: "Hiçbir şey",
        soloCapsLock: "Büyük harfi açar kapatır",
        soloEscape: "Escape tuşuna basar",
        activeNow: "Şu anda çalışıyor",
        panelCaptionFormat: "%1$@ %2$@ tuşlarını basılı tutar.",
        manageButton: "Ayarla…",
        soloInputSource: "Giriş kaynağını değiştir; Caps Lock için basılı tut",
        mappingForeignMapping: "Başka bir uygulamanın tuş eşlemesi seçili tuşu kullanıyor. Eşlemeyi o uygulamada kaldırın: çıkmak yetmez.",
        mappingSystemRefused: "macOS tuş eşlemesini kabul etmedi. Klavyeyi yeniden bağlayın veya Mac’i yeniden başlatın, sonra bunu tekrar açın."
    )

    static let ru = SuperKeyStrings(
        pageTitle: "Суперклавиша",
        hubDescription: "Превращает одну клавишу в выбранное сочетание клавиш-модификаторов.",
        enableToggle: "Использовать эту клавишу как суперклавишу",
        enableCaption: "Удерживайте её и нажмите любую клавишу. Выберите ниже один или несколько модификаторов.",
        modifierKeysNote: "Оставьте для этой клавиши действие по умолчанию в Системных настройках › Клавиатура › Клавиши-модификаторы.",
        sourceKey: "Клавиша для удержания",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "Правая %@",
        holdHint: "Удерживайте",
        soloSection: "Одиночное нажатие",
        soloCaption: "Что делает быстрое нажатие, если других клавиш не было.",
        soloNothing: "Ничего",
        soloCapsLock: "Включает и выключает заглавные",
        soloEscape: "Нажимает Escape",
        activeNow: "Работает",
        panelCaptionFormat: "%1$@ удерживает %2$@.",
        manageButton: "Настроить…",
        soloInputSource: "Сменить источник ввода; удерживать для Caps Lock",
        mappingForeignMapping: "Другая программа переназначила выбранную клавишу. Удалите назначение в той программе: завершить её недостаточно.",
        mappingSystemRefused: "macOS отклонил переназначение клавиш. Переподключите клавиатуру или перезапустите Mac и включите это снова."
    )

    static let es = SuperKeyStrings(
        pageTitle: "Tecla súper",
        hubDescription: "Convierte una tecla en la combinación de modificadores que elijas.",
        enableToggle: "Usar esta tecla como tecla súper",
        enableCaption: "Mantenla pulsada y pulsa cualquier tecla. Elige uno o más modificadores abajo.",
        modifierKeysNote: "Mantén esta tecla con su acción predeterminada en Ajustes del Sistema › Teclado › Teclas de modificación.",
        sourceKey: "Tecla que mantener pulsada",
        capsLockKey: "Bloq Mayús",
        rightKeyFormat: "Derecha %@",
        holdHint: "Mantén",
        soloSection: "Un toque suelto",
        soloCaption: "Qué hace un toque rápido cuando no se pulsa ninguna otra tecla.",
        soloNothing: "Nada",
        soloCapsLock: "Activa y desactiva las mayúsculas",
        soloEscape: "Pulsa Escape",
        activeNow: "Funcionando ahora",
        panelCaptionFormat: "%1$@ mantiene %2$@.",
        manageButton: "Configurar…",
        soloInputSource: "Cambiar fuente de entrada; mantener para Bloq Mayús",
        mappingForeignMapping: "La reasignación de otra app usa la tecla seleccionada. Elimínala en esa app: salir de ella no basta.",
        mappingSystemRefused: "macOS rechazó la reasignación de teclas. Vuelve a conectar el teclado o reinicia el Mac y activa esto de nuevo."
    )

    static let de = SuperKeyStrings(
        pageTitle: "Supertaste",
        hubDescription: "Macht eine Taste zu deiner gewählten Sondertastenkombination.",
        enableToggle: "Diese Taste als Supertaste verwenden",
        enableCaption: "Halte sie und drücke eine beliebige Taste. Wähle unten eine oder mehrere Sondertasten.",
        modifierKeysNote: "Lass für diese Taste unter Systemeinstellungen › Tastatur › Sondertasten die Standardaktion eingestellt.",
        sourceKey: "Zu haltende Taste",
        capsLockKey: "Feststelltaste",
        rightKeyFormat: "Rechte %@",
        holdHint: "Halten",
        soloSection: "Ein einzelner Tastendruck",
        soloCaption: "Was ein kurzer Druck bewirkt, wenn keine andere Taste dabei ist.",
        soloNothing: "Nichts",
        soloCapsLock: "Großbuchstaben ein und aus",
        soloEscape: "Drückt Escape",
        activeNow: "Läuft gerade",
        panelCaptionFormat: "%1$@ hält %2$@.",
        manageButton: "Einrichten…",
        soloInputSource: "Eingabequelle wechseln; für Feststelltaste halten",
        mappingForeignMapping: "Die Tastenbelegung einer anderen App verwendet die ausgewählte Taste. Entferne sie in dieser App: Beenden reicht nicht.",
        mappingSystemRefused: "macOS hat die Tastenbelegung abgelehnt. Schließe die Tastatur neu an oder starte den Mac neu und schalte dies wieder ein."
    )

    static let fr = SuperKeyStrings(
        pageTitle: "Touche super",
        hubDescription: "Transforme une touche en la combinaison de modificateurs de votre choix.",
        enableToggle: "Utiliser cette touche comme touche Super",
        enableCaption: "Maintenez-la et appuyez sur n'importe quelle touche. Choisissez un ou plusieurs modificateurs ci-dessous.",
        modifierKeysNote: "Conservez l’action par défaut de cette touche dans Réglages Système › Clavier › Touches de modification.",
        sourceKey: "Touche à maintenir",
        capsLockKey: "Verr. Maj",
        rightKeyFormat: "%@ droite",
        holdHint: "Maintenez",
        soloSection: "Un appui seul",
        soloCaption: "Ce que fait un appui rapide quand aucune autre touche n'est pressée.",
        soloNothing: "Rien",
        soloCapsLock: "Active et désactive les majuscules",
        soloEscape: "Appuie sur Échap",
        activeNow: "Actif maintenant",
        panelCaptionFormat: "%1$@ maintient %2$@.",
        manageButton: "Configurer…",
        soloInputSource: "Changer de source d’entrée ; maintenir pour Verr. Maj",
        mappingForeignMapping: "Le remappage d’une autre app utilise la touche sélectionnée. Supprimez-le dans cette app : la quitter ne suffit pas.",
        mappingSystemRefused: "macOS a refusé le remappage. Rebranchez le clavier ou redémarrez le Mac, puis réactivez ceci."
    )

    static let it = SuperKeyStrings(
        pageTitle: "Tasto super",
        hubDescription: "Trasforma un tasto nella combinazione di modificatori che scegli.",
        enableToggle: "Usa questo tasto come tasto Super",
        enableCaption: "Tienilo premuto e premi un tasto qualsiasi. Scegli uno o più modificatori qui sotto.",
        modifierKeysNote: "Mantieni l’azione predefinita per questo tasto in Impostazioni di Sistema › Tastiera › Tasti modificatori.",
        sourceKey: "Tasto da tenere premuto",
        capsLockKey: "Blocco Maiuscole",
        rightKeyFormat: "%@ destro",
        holdHint: "Tieni premuto",
        soloSection: "Un tocco da solo",
        soloCaption: "Cosa fa un tocco veloce quando non premi nessun altro tasto.",
        soloNothing: "Niente",
        soloCapsLock: "Attiva e disattiva le maiuscole",
        soloEscape: "Preme Escape",
        activeNow: "Attivo ora",
        panelCaptionFormat: "%1$@ tiene premuti %2$@.",
        manageButton: "Configura…",
        soloInputSource: "Cambia sorgente di input; tieni premuto per Blocco Maiuscole",
        mappingForeignMapping: "La rimappatura di un’altra app usa il tasto selezionato. Rimuovila in quell’app: chiuderla non basta.",
        mappingSystemRefused: "macOS ha rifiutato la rimappatura. Ricollega la tastiera o riavvia il Mac, poi riattiva questa funzione."
    )

    static let ja = SuperKeyStrings(
        pageTitle: "スーパーキー",
        hubDescription: "1つのキーを選んだ修飾キーの組み合わせに変えます。",
        enableToggle: "このキーをスーパーキーとして使う",
        enableCaption: "押したまま好きなキーを押してください。下から1つ以上の修飾キーを選びます。",
        modifierKeysNote: "システム設定 › キーボード › 修飾キーで、このキーをデフォルトの動作にしてください。",
        sourceKey: "長押しするキー",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "右%@",
        holdHint: "押したまま",
        soloSection: "単独で押したとき",
        soloCaption: "ほかのキーを押さずに軽く押したときの動作です。",
        soloNothing: "何もしない",
        soloCapsLock: "大文字を切り替える",
        soloEscape: "Escape を押す",
        activeNow: "動作中",
        panelCaptionFormat: "%1$@ が %2$@ を押した状態にします。",
        manageButton: "設定…",
        soloInputSource: "入力ソースを切り替え（長押しで Caps Lock）",
        mappingForeignMapping: "他のアプリのキー割り当てが選択したキーを使っています。そのアプリで割り当てを削除してください。終了するだけでは残ります。",
        mappingSystemRefused: "macOS がキー割り当てを受け付けませんでした。キーボードを接続し直すか Mac を再起動してから、もう一度オンにしてください。"
    )

    static let ko = SuperKeyStrings(
        pageTitle: "슈퍼 키",
        hubDescription: "키 하나를 선택한 조합 키 묶음으로 바꿉니다.",
        enableToggle: "이 키를 슈퍼 키로 사용",
        enableCaption: "누른 채로 아무 키나 누르세요. 아래에서 조합 키를 하나 이상 선택하세요.",
        modifierKeysNote: "시스템 설정 › 키보드 › 보조 키에서 이 키를 기본 동작으로 유지하세요.",
        sourceKey: "길게 누를 키",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "오른쪽 %@",
        holdHint: "누른 채로",
        soloSection: "혼자 눌렀을 때",
        soloCaption: "다른 키 없이 가볍게 눌렀을 때의 동작입니다.",
        soloNothing: "아무 동작 없음",
        soloCapsLock: "대문자 켜고 끄기",
        soloEscape: "Escape 누르기",
        activeNow: "지금 작동 중",
        panelCaptionFormat: "%1$@이(가) %2$@를 누른 상태로 만듭니다.",
        manageButton: "설정…",
        soloInputSource: "입력 소스 전환(길게 눌러 Caps Lock)",
        mappingForeignMapping: "다른 앱의 키 매핑이 선택한 키를 사용하고 있습니다. 그 앱에서 매핑을 지우세요. 종료만으로는 사라지지 않습니다.",
        mappingSystemRefused: "macOS가 키 매핑을 거부했습니다. 키보드를 다시 연결하거나 Mac을 재시동한 뒤 이 기능을 켜세요."
    )

    static let zhHans = SuperKeyStrings(
        pageTitle: "超级键",
        hubDescription: "把一个按键变成你选择的修饰键组合。",
        enableToggle: "将此键用作超级键",
        enableCaption: "按住它再按任意键。请在下方选择一个或多个修饰键。",
        modifierKeysNote: "请在系统设置 › 键盘 › 修饰键中将此按键保留为默认操作。",
        sourceKey: "要按住的按键",
        capsLockKey: "大写锁定",
        rightKeyFormat: "右侧%@",
        holdHint: "按住",
        soloSection: "单独轻按",
        soloCaption: "没有按下其他键时，轻按一下会做什么。",
        soloNothing: "什么都不做",
        soloCapsLock: "开关大写",
        soloEscape: "按下 Escape",
        activeNow: "正在运行",
        panelCaptionFormat: "%1$@会按住 %2$@。",
        manageButton: "设置…",
        soloInputSource: "切换输入法；长按开关大写锁定",
        mappingForeignMapping: "另一个 App 的按键映射使用了所选按键。请在那个 App 里删除映射：仅退出它并不够。",
        mappingSystemRefused: "macOS 拒绝了按键映射。请重新连接键盘或重启 Mac，然后重新打开此功能。"
    )

    static let zhTW = SuperKeyStrings(
        pageTitle: "超級鍵",
        hubDescription: "把一個按鍵變成你選擇的修飾鍵組合。",
        enableToggle: "將此鍵用作 Super 鍵",
        enableCaption: "按住它再按任何鍵。請在下方選擇一個或多個修飾鍵。",
        modifierKeysNote: "請在系統設定 › 鍵盤 › 輔助按鍵中將此按鍵保留為預設動作。",
        sourceKey: "要按住的按鍵",
        capsLockKey: "大寫鎖定",
        rightKeyFormat: "右側%@",
        holdHint: "按住",
        soloSection: "單獨輕按",
        soloCaption: "沒有按下其他鍵時，輕按一下會做什麼。",
        soloNothing: "什麼都不做",
        soloCapsLock: "開關大寫",
        soloEscape: "按下 Escape",
        activeNow: "正在運作",
        panelCaptionFormat: "%1$@會按住 %2$@。",
        manageButton: "設定…",
        soloInputSource: "切換輸入法；長按切換大寫鎖定",
        mappingForeignMapping: "另一個 App 的按鍵對應使用了所選按鍵。請在那個 App 裡移除對應：只結束它並不夠。",
        mappingSystemRefused: "macOS 拒絕了按鍵對應。請重新連接鍵盤或重新啟動 Mac，然後重新開啟此功能。"
    )

    static let zhHK = SuperKeyStrings(
        pageTitle: "超級鍵",
        hubDescription: "將一個按鍵變成你揀嘅修飾鍵組合。",
        enableToggle: "將此鍵用作 Super 鍵",
        enableCaption: "按住佢再撳任何鍵。喺下面揀一個或多個修飾鍵。",
        modifierKeysNote: "請喺系統設定 › 鍵盤 › 輔助按鍵入面將呢個按鍵保留為預設動作。",
        sourceKey: "要按住嘅按鍵",
        capsLockKey: "大寫鎖定",
        rightKeyFormat: "右側%@",
        holdHint: "按住",
        soloSection: "單獨輕撳",
        soloCaption: "無撳其他鍵嘅時候，輕撳一下會做乜。",
        soloNothing: "咩都唔做",
        soloCapsLock: "開關大寫",
        soloEscape: "撳 Escape",
        activeNow: "正在運作",
        panelCaptionFormat: "%1$@會按住 %2$@。",
        manageButton: "設定…",
        soloInputSource: "切換輸入法；長撳切換大寫鎖定",
        mappingForeignMapping: "另一個 App 嘅按鍵對應用咗所選按鍵。請喺嗰個 App 度移除對應：淨係結束佢唔夠。",
        mappingSystemRefused: "macOS 拒絕咗按鍵對應。請重新接駁鍵盤或者重新啟動 Mac，然後重新開啟呢個功能。"
    )
}
