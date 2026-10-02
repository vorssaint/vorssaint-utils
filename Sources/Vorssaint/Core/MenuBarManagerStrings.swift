// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarManagerFeatureStrings {
    let title: String
    let hubDescription: String
    let enableCaption: String
    let howTo: String
    let arrowHint: String
    let rehideLabel: String
    let rehideNever: String
    let rehideSecondsFormat: String
    let ownIconWarning: String
    let arrowWarning: String
    let overflowNote: String
    let dividerTooltip: String
    let hideTooltip: String
    let showTooltip: String
}

extension FeatureStrings {
    static func menuBarManager(_ language: AppLanguage) -> MenuBarManagerFeatureStrings {
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

extension MenuBarManagerFeatureStrings {
    static let enUS = MenuBarManagerFeatureStrings(
        title: "Hide Menu Bar Icons",
        hubDescription: "Tuck the menu bar icons you rarely use behind a divider and reveal them with one click",
        enableCaption: "Adds a divider next to the Vorssaint icon.",
        howTo: "Hold Command and drag icons to the left of the divider to hide them, or to its right to keep them visible.",
        arrowHint: "Click the arrow to reveal or hide them.",
        rehideLabel: "Hide again after",
        rehideNever: "Never",
        rehideSecondsFormat: "%d seconds",
        ownIconWarning: "The Vorssaint icon is left of the divider. Hold Command and drag it to the right of the divider so it is never hidden.",
        arrowWarning: "The arrow is left of the divider. Hold Command and drag it to the right of the divider so it is never hidden.",
        overflowNote: "Click the system « to show hidden icons in place, next to the others. Click the divider to hide them again.",
        dividerTooltip: "Icons left of this divider are hidden",
        hideTooltip: "Hide menu bar icons",
        showTooltip: "Show hidden menu bar icons")
    static let ptBR = MenuBarManagerFeatureStrings(
        title: "Ocultar ícones da barra de menus",
        hubDescription: "Guarde atrás de um divisor os ícones da barra de menus que você pouco usa e mostre-os com um clique",
        enableCaption: "Adiciona um divisor ao lado do ícone do Vorssaint.",
        howTo: "Segure Command e arraste os ícones para a esquerda do divisor para ocultá-los, ou para a direita para mantê-los visíveis.",
        arrowHint: "Clique na seta para mostrá-los ou ocultá-los.",
        rehideLabel: "Ocultar novamente após",
        rehideNever: "Nunca",
        rehideSecondsFormat: "%d segundos",
        ownIconWarning: "O ícone do Vorssaint está à esquerda do divisor. Segure Command e arraste-o para a direita do divisor para que nunca fique oculto.",
        arrowWarning: "A seta está à esquerda do divisor. Segure Command e arraste-a para a direita do divisor para que nunca fique oculta.",
        overflowNote: "Clique no « do sistema para mostrar os ícones ocultos no lugar, ao lado dos outros. Clique no divisor para ocultá-los de novo.",
        dividerTooltip: "Os ícones à esquerda deste divisor ficam ocultos",
        hideTooltip: "Ocultar ícones da barra de menus",
        showTooltip: "Mostrar ícones ocultos da barra de menus")
    static let tr = MenuBarManagerFeatureStrings(
        title: "Menü Çubuğu Simgelerini Gizle",
        hubDescription: "Nadiren kullandığınız menü çubuğu simgelerini bir ayırıcının arkasına saklayın ve tek tıkla gösterin",
        enableCaption: "Vorssaint simgesinin yanına bir ayırıcı ekler.",
        howTo: "Simgeleri gizlemek için Command tuşunu basılı tutup ayırıcının soluna, görünür tutmak için sağına sürükleyin.",
        arrowHint: "Göstermek veya gizlemek için oka tıklayın.",
        rehideLabel: "Şu süreden sonra yeniden gizle",
        rehideNever: "Asla",
        rehideSecondsFormat: "%d saniye",
        ownIconWarning: "Vorssaint simgesi ayırıcının solunda. Hiç gizlenmemesi için Command tuşunu basılı tutup ayırıcının sağına sürükleyin.",
        arrowWarning: "Ok ayırıcının solunda. Hiç gizlenmemesi için Command tuşunu basılı tutup ayırıcının sağına sürükleyin.",
        overflowNote: "Gizli simgeleri diğerlerinin yanında, yerinde göstermek için sistemin « düğmesine tıklayın. Yeniden gizlemek için ayırıcıya tıklayın.",
        dividerTooltip: "Bu ayırıcının solundaki simgeler gizlenir",
        hideTooltip: "Menü çubuğu simgelerini gizle",
        showTooltip: "Gizli menü çubuğu simgelerini göster")
    static let ru = MenuBarManagerFeatureStrings(
        title: "Скрытие значков строки меню",
        hubDescription: "Прячьте редко используемые значки строки меню за разделителем и показывайте их одним щелчком",
        enableCaption: "Добавляет разделитель рядом со значком Vorssaint.",
        howTo: "Удерживая Command, перетащите значки левее разделителя, чтобы скрыть их, или правее, чтобы оставить видимыми.",
        arrowHint: "Щёлкните стрелку, чтобы показать или скрыть их.",
        rehideLabel: "Снова скрывать через",
        rehideNever: "Никогда",
        rehideSecondsFormat: "%d с",
        ownIconWarning: "Значок Vorssaint находится левее разделителя. Удерживая Command, перетащите его правее разделителя, чтобы он никогда не скрывался.",
        arrowWarning: "Стрелка находится левее разделителя. Удерживая Command, перетащите её правее разделителя, чтобы она никогда не скрывалась.",
        overflowNote: "Щёлкните системную кнопку «, чтобы показать скрытые значки на их месте, рядом с остальными. Щёлкните разделитель, чтобы снова скрыть их.",
        dividerTooltip: "Значки левее этого разделителя скрыты",
        hideTooltip: "Скрыть значки строки меню",
        showTooltip: "Показать скрытые значки строки меню")
    static let es = MenuBarManagerFeatureStrings(
        title: "Ocultar iconos de la barra de menús",
        hubDescription: "Guarda tras un divisor los iconos de la barra de menús que apenas usas y muéstralos con un clic",
        enableCaption: "Añade un divisor junto al icono de Vorssaint.",
        howTo: "Mantén pulsada Comando y arrastra los iconos a la izquierda del divisor para ocultarlos, o a su derecha para mantenerlos visibles.",
        arrowHint: "Haz clic en la flecha para mostrarlos u ocultarlos.",
        rehideLabel: "Volver a ocultar tras",
        rehideNever: "Nunca",
        rehideSecondsFormat: "%d segundos",
        ownIconWarning: "El icono de Vorssaint está a la izquierda del divisor. Mantén pulsada Comando y arrástralo a la derecha del divisor para que nunca se oculte.",
        arrowWarning: "La flecha está a la izquierda del divisor. Mantén pulsada Comando y arrástrala a la derecha del divisor para que nunca se oculte.",
        overflowNote: "Haz clic en el « del sistema para mostrar los iconos ocultos en su sitio, junto a los demás. Haz clic en el divisor para volver a ocultarlos.",
        dividerTooltip: "Los iconos a la izquierda de este divisor están ocultos",
        hideTooltip: "Ocultar iconos de la barra de menús",
        showTooltip: "Mostrar iconos ocultos de la barra de menús")
    static let sk = MenuBarManagerFeatureStrings(
        title: "Skryť ikony na lište menu",
        hubDescription: "Schovajte ikony na lište menu, ktoré používate zriedka, za oddeľovač a zobrazte ich jedným kliknutím",
        enableCaption: "Pridá oddeľovač vedľa ikony Vorssaint.",
        howTo: "Podržte Command a presuňte ikony naľavo od oddeľovača, aby sa skryli, alebo napravo, aby zostali viditeľné.",
        arrowHint: "Kliknutím na šípku ich zobrazíte alebo skryjete.",
        rehideLabel: "Znova skryť po",
        rehideNever: "Nikdy",
        rehideSecondsFormat: "%d s",
        ownIconWarning: "Ikona Vorssaint je naľavo od oddeľovača. Podržte Command a presuňte ju napravo od oddeľovača, aby sa nikdy neskryla.",
        arrowWarning: "Šípka je naľavo od oddeľovača. Podržte Command a presuňte ju napravo od oddeľovača, aby sa nikdy neskryla.",
        overflowNote: "Kliknutím na systémové « zobrazíte skryté ikony na ich mieste, vedľa ostatných. Kliknutím na oddeľovač ich znova skryjete.",
        dividerTooltip: "Ikony naľavo od tohto oddeľovača sú skryté",
        hideTooltip: "Skryť ikony na lište menu",
        showTooltip: "Zobraziť skryté ikony na lište menu")
    static let de = MenuBarManagerFeatureStrings(
        title: "Menüleistensymbole ausblenden",
        hubDescription: "Selten genutzte Menüleistensymbole hinter einem Trenner verstecken und mit einem Klick einblenden",
        enableCaption: "Fügt neben dem Vorssaint-Symbol einen Trenner hinzu.",
        howTo: "Halte die Befehlstaste gedrückt und ziehe Symbole links neben den Trenner, um sie auszublenden, oder rechts daneben, damit sie sichtbar bleiben.",
        arrowHint: "Klicke auf den Pfeil, um sie ein- oder auszublenden.",
        rehideLabel: "Wieder ausblenden nach",
        rehideNever: "Nie",
        rehideSecondsFormat: "%d Sekunden",
        ownIconWarning: "Das Vorssaint-Symbol liegt links vom Trenner. Halte die Befehlstaste gedrückt und ziehe es rechts neben den Trenner, damit es nie ausgeblendet wird.",
        arrowWarning: "Der Pfeil liegt links vom Trenner. Halte die Befehlstaste gedrückt und ziehe ihn rechts neben den Trenner, damit er nie ausgeblendet wird.",
        overflowNote: "Klicke auf das « des Systems, um ausgeblendete Symbole an ihrem Platz neben den anderen zu zeigen. Klicke auf den Trenner, um sie wieder auszublenden.",
        dividerTooltip: "Symbole links von diesem Trenner sind ausgeblendet",
        hideTooltip: "Menüleistensymbole ausblenden",
        showTooltip: "Ausgeblendete Menüleistensymbole einblenden")
    static let fr = MenuBarManagerFeatureStrings(
        title: "Masquer les icônes de la barre des menus",
        hubDescription: "Rangez derrière un séparateur les icônes de la barre des menus que vous utilisez peu et affichez-les d’un clic",
        enableCaption: "Ajoute un séparateur à côté de l’icône Vorssaint.",
        howTo: "Maintenez Commande et faites glisser les icônes à gauche du séparateur pour les masquer, ou à sa droite pour les garder visibles.",
        arrowHint: "Cliquez sur la flèche pour les afficher ou les masquer.",
        rehideLabel: "Masquer de nouveau après",
        rehideNever: "Jamais",
        rehideSecondsFormat: "%d secondes",
        ownIconWarning: "L’icône Vorssaint est à gauche du séparateur. Maintenez Commande et faites-la glisser à droite du séparateur pour qu’elle ne soit jamais masquée.",
        arrowWarning: "La flèche est à gauche du séparateur. Maintenez Commande et faites-la glisser à droite du séparateur pour qu’elle ne soit jamais masquée.",
        overflowNote: "Cliquez sur le «, affiché par le système, pour montrer les icônes masquées à leur place, à côté des autres. Cliquez sur le séparateur pour les masquer de nouveau.",
        dividerTooltip: "Les icônes à gauche de ce séparateur sont masquées",
        hideTooltip: "Masquer les icônes de la barre des menus",
        showTooltip: "Afficher les icônes masquées de la barre des menus")
    static let it = MenuBarManagerFeatureStrings(
        title: "Nascondi icone della barra dei menu",
        hubDescription: "Metti dietro un separatore le icone della barra dei menu che usi di rado e mostrale con un clic",
        enableCaption: "Aggiunge un separatore accanto all’icona di Vorssaint.",
        howTo: "Tieni premuto Comando e trascina le icone a sinistra del separatore per nasconderle, o alla sua destra per tenerle visibili.",
        arrowHint: "Fai clic sulla freccia per mostrarle o nasconderle.",
        rehideLabel: "Nascondi di nuovo dopo",
        rehideNever: "Mai",
        rehideSecondsFormat: "%d secondi",
        ownIconWarning: "L’icona di Vorssaint è a sinistra del separatore. Tieni premuto Comando e trascinala a destra del separatore, così non viene mai nascosta.",
        arrowWarning: "La freccia è a sinistra del separatore. Tieni premuto Comando e trascinala a destra del separatore, così non viene mai nascosta.",
        overflowNote: "Fai clic sul « di sistema per mostrare le icone nascoste al loro posto, accanto alle altre. Fai clic sul separatore per nasconderle di nuovo.",
        dividerTooltip: "Le icone a sinistra di questo separatore sono nascoste",
        hideTooltip: "Nascondi icone della barra dei menu",
        showTooltip: "Mostra le icone nascoste della barra dei menu")
    static let ja = MenuBarManagerFeatureStrings(
        title: "メニューバーアイコンを隠す",
        hubDescription: "あまり使わないメニューバーのアイコンを区切りの後ろにしまい、クリック一つで表示します",
        enableCaption: "Vorssaintのアイコンの隣に区切りを追加します。",
        howTo: "Commandキーを押したまま、隠したいアイコンを区切りの左へ、表示したままにするアイコンを右へドラッグします。",
        arrowHint: "矢印をクリックすると表示・非表示を切り替えます。",
        rehideLabel: "再び隠すまでの時間",
        rehideNever: "しない",
        rehideSecondsFormat: "%d秒",
        ownIconWarning: "Vorssaintのアイコンが区切りの左にあります。隠れないように、Commandキーを押したまま区切りの右へドラッグしてください。",
        arrowWarning: "矢印が区切りの左にあります。隠れないように、Commandキーを押したまま区切りの右へドラッグしてください。",
        overflowNote: "システムの « をクリックすると、隠したアイコンが他のアイコンの隣の元の位置に表示されます。区切りをクリックすると再び隠れます。",
        dividerTooltip: "この区切りより左のアイコンは隠れます",
        hideTooltip: "メニューバーアイコンを隠す",
        showTooltip: "隠したメニューバーアイコンを表示")
    static let ko = MenuBarManagerFeatureStrings(
        title: "메뉴 막대 아이콘 숨기기",
        hubDescription: "자주 쓰지 않는 메뉴 막대 아이콘을 구분선 뒤에 숨기고 한 번의 클릭으로 표시합니다",
        enableCaption: "Vorssaint 아이콘 옆에 구분선을 추가합니다.",
        howTo: "Command 키를 누른 채 아이콘을 구분선 왼쪽으로 드래그하면 숨겨지고, 오른쪽으로 드래그하면 계속 보입니다.",
        arrowHint: "화살표를 클릭해 표시하거나 숨깁니다.",
        rehideLabel: "다시 숨기기까지",
        rehideNever: "안 함",
        rehideSecondsFormat: "%d초",
        ownIconWarning: "Vorssaint 아이콘이 구분선 왼쪽에 있습니다. 숨겨지지 않도록 Command 키를 누른 채 구분선 오른쪽으로 드래그하세요.",
        arrowWarning: "화살표가 구분선 왼쪽에 있습니다. 숨겨지지 않도록 Command 키를 누른 채 구분선 오른쪽으로 드래그하세요.",
        overflowNote: "시스템 « 을 클릭하면 숨긴 아이콘이 다른 아이콘 옆 제자리에 표시됩니다. 구분선을 클릭하면 다시 숨겨집니다.",
        dividerTooltip: "이 구분선 왼쪽의 아이콘은 숨겨집니다",
        hideTooltip: "메뉴 막대 아이콘 숨기기",
        showTooltip: "숨긴 메뉴 막대 아이콘 표시")
    static let uk = MenuBarManagerFeatureStrings(
        title: "Приховування значків рядка меню",
        hubDescription: "Ховайте рідко вживані значки рядка меню за роздільником і показуйте їх одним клацанням",
        enableCaption: "Додає роздільник поруч зі значком Vorssaint.",
        howTo: "Утримуючи Command, перетягніть значки ліворуч від роздільника, щоб приховати їх, або праворуч, щоб залишити видимими.",
        arrowHint: "Клацніть стрілку, щоб показати або приховати їх.",
        rehideLabel: "Знову приховувати через",
        rehideNever: "Ніколи",
        rehideSecondsFormat: "%d с",
        ownIconWarning: "Значок Vorssaint розташований ліворуч від роздільника. Утримуючи Command, перетягніть його праворуч від роздільника, щоб він ніколи не приховувався.",
        arrowWarning: "Стрілка розташована ліворуч від роздільника. Утримуючи Command, перетягніть її праворуч від роздільника, щоб вона ніколи не приховувалася.",
        overflowNote: "Клацніть системну кнопку «, щоб показати приховані значки на їхньому місці, поруч з іншими. Клацніть роздільник, щоб знову приховати їх.",
        dividerTooltip: "Значки ліворуч від цього роздільника приховано",
        hideTooltip: "Приховати значки рядка меню",
        showTooltip: "Показати приховані значки рядка меню")
    static let zhHans = MenuBarManagerFeatureStrings(
        title: "隐藏菜单栏图标",
        hubDescription: "将不常用的菜单栏图标收到分隔线后面，点按一下即可显示",
        enableCaption: "在 Vorssaint 图标旁添加一条分隔线。",
        howTo: "按住 Command 键将图标拖到分隔线左侧即可隐藏，拖到右侧则保持显示。",
        arrowHint: "点按箭头可显示或隐藏它们。",
        rehideLabel: "自动重新隐藏",
        rehideNever: "从不",
        rehideSecondsFormat: "%d 秒后",
        ownIconWarning: "Vorssaint 图标位于分隔线左侧。请按住 Command 键将它拖到分隔线右侧，以免被隐藏。",
        arrowWarning: "箭头位于分隔线左侧。请按住 Command 键将它拖到分隔线右侧，以免被隐藏。",
        overflowNote: "点按系统的 « 即可在原位置显示隐藏的图标，紧挨其他图标。点按分隔线可再次隐藏。",
        dividerTooltip: "此分隔线左侧的图标已隐藏",
        hideTooltip: "隐藏菜单栏图标",
        showTooltip: "显示隐藏的菜单栏图标")
    static let zhTW = MenuBarManagerFeatureStrings(
        title: "隱藏選單列圖像",
        hubDescription: "將不常用的選單列圖像收到分隔線後方，按一下即可顯示",
        enableCaption: "在 Vorssaint 圖像旁加入一條分隔線。",
        howTo: "按住 Command 鍵將圖像拖到分隔線左側即可隱藏，拖到右側則保持顯示。",
        arrowHint: "按一下箭頭可顯示或隱藏它們。",
        rehideLabel: "自動重新隱藏",
        rehideNever: "永不",
        rehideSecondsFormat: "%d 秒後",
        ownIconWarning: "Vorssaint 圖像位於分隔線左側。請按住 Command 鍵將它拖到分隔線右側，以免被隱藏。",
        arrowWarning: "箭頭位於分隔線左側。請按住 Command 鍵將它拖到分隔線右側，以免被隱藏。",
        overflowNote: "按一下系統的 « 即可在原位置顯示隱藏的圖像，緊鄰其他圖像。按一下分隔線可再次隱藏。",
        dividerTooltip: "此分隔線左側的圖像已隱藏",
        hideTooltip: "隱藏選單列圖像",
        showTooltip: "顯示隱藏的選單列圖像")
    static let zhHK = MenuBarManagerFeatureStrings(
        title: "隱藏選單列圖示",
        hubDescription: "將不常用的選單列圖示收到分隔線後面，按一下即可顯示",
        enableCaption: "在 Vorssaint 圖示旁加入一條分隔線。",
        howTo: "按住 Command 鍵將圖示拖到分隔線左邊即可隱藏，拖到右邊則保持顯示。",
        arrowHint: "按一下箭嘴可顯示或隱藏它們。",
        rehideLabel: "自動重新隱藏",
        rehideNever: "永不",
        rehideSecondsFormat: "%d 秒後",
        ownIconWarning: "Vorssaint 圖示位於分隔線左邊。請按住 Command 鍵將它拖到分隔線右邊，以免被隱藏。",
        arrowWarning: "箭嘴位於分隔線左邊。請按住 Command 鍵將它拖到分隔線右邊，以免被隱藏。",
        overflowNote: "按一下系統的 « 即可在原位置顯示隱藏的圖示，緊貼其他圖示。按一下分隔線可再次隱藏。",
        dividerTooltip: "此分隔線左邊的圖示已隱藏",
        hideTooltip: "隱藏選單列圖示",
        showTooltip: "顯示隱藏的選單列圖示")
}
