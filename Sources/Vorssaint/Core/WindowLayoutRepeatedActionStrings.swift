// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct WindowLayoutRepeatedActionStrings {
    let title: String
    let caption: String
    let cycleHalfOneThirdOneSixth: String
    let cycleHalfTwoThirdsOneThird: String
    let cycleHalfOneThirdTwoThirds: String
    let cycleHalfTwoThirds: String
    let cycleHalfOneThird: String
    let cycleAcrossDisplays: String
    let acrossDisplays: String
    let disabled: String

    static func localized(_ language: AppLanguage) -> WindowLayoutRepeatedActionStrings {
        switch language {
        case .enUS:
            return .init(
                title: "Repeated commands",
                caption: "Action when pressing the same layout shortcut or button repeatedly.",
                cycleHalfOneThirdOneSixth: "Cycle 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Cycle 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Cycle 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Cycle 1/2, 2/3",
                cycleHalfOneThird: "Cycle 1/2, 1/3",
                cycleAcrossDisplays: "Cycle sizes and across displays",
                acrossDisplays: "Move across displays",
                disabled: "Disabled"
            )
        case .ptBR:
            return .init(
                title: "Comandos repetidos",
                caption: "Ação ao usar o mesmo atalho ou botão de layout repetidamente.",
                cycleHalfOneThirdOneSixth: "Alternar 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Alternar 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Alternar 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Alternar 1/2, 2/3",
                cycleHalfOneThird: "Alternar 1/2, 1/3",
                cycleAcrossDisplays: "Alternar tamanhos e entre telas",
                acrossDisplays: "Mover entre telas",
                disabled: "Desativado"
            )
        case .tr:
            return .init(
                title: "Yinelenen komutlar",
                caption: "Aynı düzen kestirmesi veya düğmesi art arda kullanıldığında yapılacak işlem.",
                cycleHalfOneThirdOneSixth: "Döngü: 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Döngü: 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Döngü: 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Döngü: 1/2, 2/3",
                cycleHalfOneThird: "Döngü: 1/2, 1/3",
                cycleAcrossDisplays: "Boyutlar ve ekranlar arasında döngü",
                acrossDisplays: "Ekranlar arasında taşı",
                disabled: "Devre dışı"
            )
        case .ru:
            return .init(
                title: "Повторные команды",
                caption: "Действие при повторном нажатии того же сочетания или кнопки разметки.",
                cycleHalfOneThirdOneSixth: "Переключать 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Переключать 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Переключать 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Переключать 1/2, 2/3",
                cycleHalfOneThird: "Переключать 1/2, 1/3",
                cycleAcrossDisplays: "Переключать размеры и между экранами",
                acrossDisplays: "Перемещать между экранами",
                disabled: "Выключено"
            )
        case .es:
            return .init(
                title: "Comandos repetidos",
                caption: "Acción al pulsar repetidamente el mismo atajo o botón de diseño.",
                cycleHalfOneThirdOneSixth: "Alternar 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Alternar 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Alternar 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Alternar 1/2, 2/3",
                cycleHalfOneThird: "Alternar 1/2, 1/3",
                cycleAcrossDisplays: "Alternar tamaños y entre pantallas",
                acrossDisplays: "Mover entre pantallas",
                disabled: "Desactivado"
            )
        case .de:
            return .init(
                title: "Wiederholte Befehle",
                caption: "Aktion beim wiederholten Ausführen desselben Tastaturkürzels oder Buttons.",
                cycleHalfOneThirdOneSixth: "Wechseln: 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Wechseln: 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Wechseln: 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Wechseln: 1/2, 2/3",
                cycleHalfOneThird: "Wechseln: 1/2, 1/3",
                cycleAcrossDisplays: "Größen und Monitore durchwechseln",
                acrossDisplays: "Über Monitore verschieben",
                disabled: "Deaktiviert"
            )
        case .fr:
            return .init(
                title: "Commandes répétées",
                caption: "Action lors de l’utilisation répétée du même raccourci ou bouton.",
                cycleHalfOneThirdOneSixth: "Alterner 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Alterner 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Alterner 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Alterner 1/2, 2/3",
                cycleHalfOneThird: "Alterner 1/2, 1/3",
                cycleAcrossDisplays: "Alterner tailles et écrans",
                acrossDisplays: "Déplacer d’un écran à l’autre",
                disabled: "Désactivé"
            )
        case .it:
            return .init(
                title: "Comandi ripetuti",
                caption: "Azione eseguita premendo ripetutamente la stessa scorciatoia o pulsante.",
                cycleHalfOneThirdOneSixth: "Alterna 1/2, 1/3, 1/6",
                cycleHalfTwoThirdsOneThird: "Alterna 1/2, 2/3, 1/3",
                cycleHalfOneThirdTwoThirds: "Alterna 1/2, 1/3, 2/3",
                cycleHalfTwoThirds: "Alterna 1/2, 2/3",
                cycleHalfOneThird: "Alterna 1/2, 1/3",
                cycleAcrossDisplays: "Alterna dimensioni e monitor",
                acrossDisplays: "Sposta tra monitor",
                disabled: "Disattivato"
            )
        case .ja:
            return .init(
                title: "連続コマンド",
                caption: "同じショートカットやボタンを連続で押したときの動作。",
                cycleHalfOneThirdOneSixth: "1/2、1/3、1/6 を順に切り替え",
                cycleHalfTwoThirdsOneThird: "1/2、2/3、1/3 を順に切り替え",
                cycleHalfOneThirdTwoThirds: "1/2、1/3、2/3 を順に切り替え",
                cycleHalfTwoThirds: "1/2、2/3 を順に切り替え",
                cycleHalfOneThird: "1/2、1/3 を順に切り替え",
                cycleAcrossDisplays: "サイズとディスプレイを順に切り替え",
                acrossDisplays: "ディスプレイ間を移動",
                disabled: "無効"
            )
        case .ko:
            return .init(
                title: "반복 명령",
                caption: "동일한 배치 단축키나 버튼을 반복해서 누를 때 동작입니다.",
                cycleHalfOneThirdOneSixth: "1/2, 1/3, 1/6 순환",
                cycleHalfTwoThirdsOneThird: "1/2, 2/3, 1/3 순환",
                cycleHalfOneThirdTwoThirds: "1/2, 1/3, 2/3 순환",
                cycleHalfTwoThirds: "1/2, 2/3 순환",
                cycleHalfOneThird: "1/2, 1/3 순환",
                cycleAcrossDisplays: "크기 및 디스플레이 간 순환",
                acrossDisplays: "디스플레이 간 이동",
                disabled: "비활성화"
            )
        case .zhHans:
            return .init(
                title: "重复命令",
                caption: "重复按下同一布局快捷键或按钮时的操作。",
                cycleHalfOneThirdOneSixth: "循环 1/2、1/3、1/6",
                cycleHalfTwoThirdsOneThird: "循环 1/2、2/3、1/3",
                cycleHalfOneThirdTwoThirds: "循环 1/2、1/3、2/3",
                cycleHalfTwoThirds: "循环 1/2、2/3",
                cycleHalfOneThird: "循环 1/2、1/3",
                cycleAcrossDisplays: "循环尺寸并在显示器间移动",
                acrossDisplays: "在显示器间移动",
                disabled: "停用"
            )
        case .zhTW:
            return .init(
                title: "重複指令",
                caption: "重複按下同一配置快速鍵或按鈕時的操作。",
                cycleHalfOneThirdOneSixth: "循環 1/2、1/3、1/6",
                cycleHalfTwoThirdsOneThird: "循環 1/2、2/3、1/3",
                cycleHalfOneThirdTwoThirds: "循環 1/2、1/3、2/3",
                cycleHalfTwoThirds: "循環 1/2、2/3",
                cycleHalfOneThird: "循環 1/2、1/3",
                cycleAcrossDisplays: "循環尺寸並在顯示器間移動",
                acrossDisplays: "在顯示器間移動",
                disabled: "停用"
            )
        case .zhHK:
            return .init(
                title: "重複指令",
                caption: "重複按下同一配置快捷鍵或按鈕時的操作。",
                cycleHalfOneThirdOneSixth: "循環 1/2、1/3、1/6",
                cycleHalfTwoThirdsOneThird: "循環 1/2、2/3、1/3",
                cycleHalfOneThirdTwoThirds: "循環 1/2、1/3、2/3",
                cycleHalfTwoThirds: "循環 1/2、2/3",
                cycleHalfOneThird: "循環 1/2、1/3",
                cycleAcrossDisplays: "循環尺寸並在顯示器間移動",
                acrossDisplays: "在顯示器間移動",
                disabled: "停用"
            )
        }
    }
}
