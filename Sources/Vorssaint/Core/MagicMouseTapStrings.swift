// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MagicMouseTapStrings {
    let title: String
    let caption: String
    let smartZoomNote: String
}

extension FeatureStrings {
    static func magicMouseTap(_ language: AppLanguage) -> MagicMouseTapStrings {
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

extension MagicMouseTapStrings {
    static let enUS = MagicMouseTapStrings(
        title: "Magic Mouse tap to click",
        caption: "A light one-finger tap on a Magic Mouse clicks the side it lands on, as pressing it would. Follows the Secondary click setting in System Settings.",
        smartZoomNote: "Smart zoom is on for the Magic Mouse, so a double tap also zooms in apps that support it. It can be turned off in System Settings › Mouse."
    )

    static let ptBR = MagicMouseTapStrings(
        title: "Tocar para clicar no Magic Mouse",
        caption: "Um toque leve com um dedo no Magic Mouse clica no lado onde cai, como se você o pressionasse. Segue o ajuste de Clique secundário nos Ajustes do Sistema.",
        smartZoomNote: "O zoom inteligente está ativado no Magic Mouse, então um toque duplo também amplia nos apps compatíveis. Ele pode ser desativado em Ajustes do Sistema › Mouse."
    )

    static let tr = MagicMouseTapStrings(
        title: "Magic Mouse’ta dokunarak tıklama",
        caption: "Magic Mouse’a tek parmakla hafifçe dokunmak, bastırmış gibi dokunulan taraftan tıklar. Sistem Ayarları’ndaki İkincil tıklama ayarını izler.",
        smartZoomNote: "Magic Mouse için akıllı büyütme açık; bu yüzden çift dokunma, destekleyen uygulamalarda büyütme de yapar. Sistem Ayarları › Fare bölümünden kapatılabilir."
    )

    static let ru = MagicMouseTapStrings(
        title: "Касание для клика на Magic Mouse",
        caption: "Лёгкое касание одним пальцем по Magic Mouse нажимает ту сторону, куда пришлось, как при нажатии. Учитывает настройку «Вторичный клик» в Системных настройках.",
        smartZoomNote: "Для Magic Mouse включено смарт-масштабирование, поэтому двойное касание также увеличивает масштаб в поддерживающих приложениях. Его можно выключить в Системных настройках › Мышь."
    )

    static let es = MagicMouseTapStrings(
        title: "Tocar para hacer clic en el Magic Mouse",
        caption: "Un toque ligero con un dedo en el Magic Mouse hace clic en el lado donde cae, como si lo presionaras. Respeta el ajuste de Clic secundario de Configuración del Sistema.",
        smartZoomNote: "El zoom inteligente está activado en el Magic Mouse, así que un doble toque también amplía en las apps compatibles. Puedes desactivarlo en Configuración del Sistema › Ratón."
    )

    static let sk = MagicMouseTapStrings(
        title: "Ťuknutie na kliknutie na Magic Mouse",
        caption: "Ľahké ťuknutie jedným prstom na Magic Mouse klikne na strane, kam dopadne, ako keby ste ju stlačili. Riadi sa nastavením Sekundárne kliknutie v Systémových nastaveniach.",
        smartZoomNote: "Inteligentné zväčšenie je pre Magic Mouse zapnuté, takže dvojité ťuknutie v podporovaných apkách aj zväčšuje. Dá sa vypnúť v Systémových nastaveniach › Myš."
    )

    static let de = MagicMouseTapStrings(
        title: "Tippen zum Klicken auf der Magic Mouse",
        caption: "Ein leichtes Tippen mit einem Finger auf die Magic Mouse klickt auf der Seite, auf der es landet, wie ein Drücken. Folgt der Einstellung „Sekundärklick“ in den Systemeinstellungen.",
        smartZoomNote: "Intelligentes Zoomen ist für die Magic Mouse aktiv, daher zoomt doppeltes Tippen in unterstützten Apps zusätzlich. Es lässt sich unter Systemeinstellungen › Maus ausschalten."
    )

    static let fr = MagicMouseTapStrings(
        title: "Toucher pour cliquer sur la Magic Mouse",
        caption: "Un toucher léger d’un doigt sur la Magic Mouse clique du côté où il tombe, comme une pression. Suit le réglage Clic secondaire des Réglages Système.",
        smartZoomNote: "Le zoom intelligent est activé pour la Magic Mouse : un double toucher zoome aussi dans les apps compatibles. Il peut être désactivé dans Réglages Système › Souris."
    )

    static let it = MagicMouseTapStrings(
        title: "Tocca per fare clic sul Magic Mouse",
        caption: "Un tocco leggero con un dito sul Magic Mouse fa clic sul lato in cui cade, come premendolo. Segue l’impostazione Clic secondario di Impostazioni di Sistema.",
        smartZoomNote: "Lo zoom smart è attivo per il Magic Mouse, quindi un doppio tocco ingrandisce anche nelle app che lo supportano. Si può disattivare in Impostazioni di Sistema › Mouse."
    )

    static let ja = MagicMouseTapStrings(
        title: "Magic Mouseのタップでクリック",
        caption: "Magic Mouseを1本指で軽くタップすると、押したときと同じように触れた側でクリックします。システム設定の「副ボタンのクリック」に従います。",
        smartZoomNote: "Magic Mouseでスマートズームがオンのため、ダブルタップすると対応アプリでズームもします。システム設定 › マウスでオフにできます。"
    )

    static let ko = MagicMouseTapStrings(
        title: "Magic Mouse 탭하여 클릭하기",
        caption: "Magic Mouse를 한 손가락으로 가볍게 탭하면 누른 것처럼 닿은 쪽이 클릭됩니다. 시스템 설정의 보조 클릭 설정을 따릅니다.",
        smartZoomNote: "Magic Mouse의 스마트 확대/축소가 켜져 있어, 두 번 탭하면 지원하는 앱에서 확대도 됩니다. 시스템 설정 › 마우스에서 끌 수 있습니다."
    )

    static let zhHans = MagicMouseTapStrings(
        title: "妙控鼠标轻点来点按",
        caption: "用一根手指轻点妙控鼠标，会像按下一样点按所触碰的那一侧。遵循系统设置中的“辅助点按”设置。",
        smartZoomNote: "妙控鼠标已开启智能缩放，因此连按两下也会在支持的 App 中缩放。可在“系统设置 › 鼠标”中关闭。"
    )

    static let zhTW = MagicMouseTapStrings(
        title: "巧控滑鼠點一下來按一下",
        caption: "用一指輕點巧控滑鼠，會像按下一樣按一下所碰觸的那一側。遵循系統設定中的「次要按鈕」設定。",
        smartZoomNote: "巧控滑鼠已開啟智慧型縮放，因此點兩下也會在支援的 App 中縮放。可在「系統設定 › 滑鼠」中關閉。"
    )

    static let zhHK = MagicMouseTapStrings(
        title: "巧控滑鼠點一下來按一下",
        caption: "用一指輕點巧控滑鼠，會像按下一樣按一下所觸碰的那一邊。遵循系統設定中的「次要按鈕」設定。",
        smartZoomNote: "巧控滑鼠已開啟智慧型縮放，因此點兩下亦會在支援的 App 中縮放。可在「系統設定 › 滑鼠」中關閉。"
    )

    static let uk = MagicMouseTapStrings(
        title: "Дотик для кліку на Magic Mouse",
        caption: "Легкий дотик одним пальцем до Magic Mouse натискає той бік, куди припав, як під час натискання. Враховує налаштування «Вторинний клік» у Системних параметрах.",
        smartZoomNote: "Для Magic Mouse увімкнено розумне масштабування, тож подвійний дотик також масштабує в застосунках, що це підтримують. Його можна вимкнути в Системних параметрах › Миша."
    )
}
