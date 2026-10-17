// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Text for trackpad gestures: the Features hub entry, the Mouse settings
/// card, gesture and navigation names, and why a gesture or action is taken.
struct TrackpadGestureStrings {
    let title: String
    let hubDescription: String
    let enableLabel: String
    let enableCaption: String
    let threeFingers: String
    let fourFingers: String
    let fiveFingers: String
    let kindTap: String
    let kindSwipeLeft: String
    let kindSwipeRight: String
    let kindSwipeUp: String
    let kindSwipeDown: String
    let kindPinchIn: String
    let kindPinchOut: String
    let actionLabel: String
    let noAction: String
    let otherAction: String
    let navigationSection: String
    let spaceLeft: String
    let spaceRight: String
    let missionControl: String
    let appExpose: String
    let ownedByMiddleClick: String
    let ownedByRadialMenu: String
    let claimedMoreGestures: String
    let claimedLookUp: String
    let claimedThreeFingerDrag: String
    let unavailableFeature: String
    let unavailableTarget: String
    let unavailableShortcut: String
    let openFeatures: String
}

extension FeatureStrings {
    static func trackpadGestures(_ language: AppLanguage) -> TrackpadGestureStrings {
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

extension TrackpadGestureStrings {
    static let enUS = TrackpadGestureStrings(
        title: "Trackpad gestures",
        hubDescription: "Map three, four and five finger taps, swipes and pinches to shortcuts, Spaces, window layouts and Vorssaint tools.",
        enableLabel: "Run actions from trackpad gestures",
        enableCaption: "Taps, swipes and pinches with three to five fingers run the action you choose. A gesture macOS already uses still does what macOS does, so pick a free one or turn the system gesture off.",
        threeFingers: "Three fingers",
        fourFingers: "Four fingers",
        fiveFingers: "Five fingers",
        kindTap: "Tap",
        kindSwipeLeft: "Swipe left",
        kindSwipeRight: "Swipe right",
        kindSwipeUp: "Swipe up",
        kindSwipeDown: "Swipe down",
        kindPinchIn: "Pinch",
        kindPinchOut: "Spread",
        actionLabel: "Action",
        noAction: "No action",
        otherAction: "Other action",
        navigationSection: "Spaces and overviews",
        spaceLeft: "Previous Space",
        spaceRight: "Next Space",
        missionControl: "Mission Control",
        appExpose: "App Exposé",
        ownedByMiddleClick: "This tap is the middle click’s tap. Change it under Trackpad middle click.",
        ownedByRadialMenu: "This tap opens the radial menu. Change it in the radial menu settings.",
        claimedMoreGestures: "macOS also uses this gesture. To use it here, turn it off in System Settings, Trackpad, More Gestures.",
        claimedLookUp: "macOS looks things up with this tap. To use it here, turn off Look up with three fingers in System Settings, Trackpad, Point & Click.",
        claimedThreeFingerDrag: "Three-finger drag uses every three-finger gesture. To use them here, choose another dragging style in System Settings, Accessibility, Pointer Control, Trackpad Options.",
        unavailableFeature: "This action needs a feature that is not installed or is turned off.",
        unavailableTarget: "The app or file chosen for this gesture is no longer there.",
        unavailableShortcut: "The macOS keyboard shortcut for this is turned off in System Settings, Keyboard, Keyboard Shortcuts, Mission Control.",
        openFeatures: "Open Features"
    )

    static let ptBR = TrackpadGestureStrings(
        title: "Gestos do trackpad",
        hubDescription: "Associe toques, deslizes e pinçadas com três, quatro e cinco dedos a atalhos, Espaços, disposições de janelas e ferramentas do Vorssaint.",
        enableLabel: "Executar ações com gestos do trackpad",
        enableCaption: "Toques, deslizes e pinçadas com três a cinco dedos executam a ação que você escolher. Um gesto que o macOS já usa continua fazendo o que o macOS faz, então escolha um livre ou desative o gesto do sistema.",
        threeFingers: "Três dedos",
        fourFingers: "Quatro dedos",
        fiveFingers: "Cinco dedos",
        kindTap: "Toque",
        kindSwipeLeft: "Deslizar para a esquerda",
        kindSwipeRight: "Deslizar para a direita",
        kindSwipeUp: "Deslizar para cima",
        kindSwipeDown: "Deslizar para baixo",
        kindPinchIn: "Pinçar",
        kindPinchOut: "Afastar",
        actionLabel: "Ação",
        noAction: "Nenhuma ação",
        otherAction: "Outra ação",
        navigationSection: "Espaços e visões gerais",
        spaceLeft: "Espaço anterior",
        spaceRight: "Próximo Espaço",
        missionControl: "Mission Control",
        appExpose: "Exposé do app",
        ownedByMiddleClick: "Este toque é o toque do botão do meio. Altere em Botão do meio no trackpad.",
        ownedByRadialMenu: "Este toque abre o menu radial. Altere nos ajustes do menu radial.",
        claimedMoreGestures: "O macOS também usa este gesto. Para usá-lo aqui, desative-o em Ajustes do Sistema, Trackpad, Mais Gestos.",
        claimedLookUp: "O macOS busca coisas com este toque. Para usá-lo aqui, desative Buscar com três dedos em Ajustes do Sistema, Trackpad, Cursor e Clique.",
        claimedThreeFingerDrag: "O arrastar com três dedos usa todos os gestos de três dedos. Para usá-los aqui, escolha outro estilo de arrasto em Ajustes do Sistema, Acessibilidade, Controle do Cursor, Opções do Trackpad.",
        unavailableFeature: "Esta ação precisa de um recurso que não está instalado ou está desativado.",
        unavailableTarget: "O app ou arquivo escolhido para este gesto não existe mais.",
        unavailableShortcut: "O atalho de teclado do macOS para isso está desativado em Ajustes do Sistema, Teclado, Atalhos de Teclado, Mission Control.",
        openFeatures: "Abrir Recursos"
    )

    static let tr = TrackpadGestureStrings(
        title: "Trackpad hareketleri",
        hubDescription: "Üç, dört ve beş parmakla dokunma, kaydırma ve sıkıştırma hareketlerini kısayollara, Alanlara, pencere düzenlerine ve Vorssaint araçlarına bağlayın.",
        enableLabel: "Trackpad hareketleriyle eylem çalıştır",
        enableCaption: "Üç ila beş parmakla dokunma, kaydırma ve sıkıştırma hareketleri seçtiğiniz eylemi çalıştırır. macOS’un zaten kullandığı bir hareket yine macOS’un yaptığını yapar; bu yüzden boşta olanı seçin veya sistem hareketini kapatın.",
        threeFingers: "Üç parmak",
        fourFingers: "Dört parmak",
        fiveFingers: "Beş parmak",
        kindTap: "Dokunma",
        kindSwipeLeft: "Sola kaydır",
        kindSwipeRight: "Sağa kaydır",
        kindSwipeUp: "Yukarı kaydır",
        kindSwipeDown: "Aşağı kaydır",
        kindPinchIn: "Sıkıştır",
        kindPinchOut: "Aç",
        actionLabel: "Eylem",
        noAction: "Eylem yok",
        otherAction: "Başka eylem",
        navigationSection: "Alanlar ve genel görünümler",
        spaceLeft: "Önceki Alan",
        spaceRight: "Sonraki Alan",
        missionControl: "Mission Control",
        appExpose: "Uygulama Exposé’si",
        ownedByMiddleClick: "Bu dokunma orta tıklamanın dokunmasıdır. İzleme dörtgeniyle orta tıklama bölümünden değiştirin.",
        ownedByRadialMenu: "Bu dokunma dairesel menüyü açar. Dairesel menü ayarlarından değiştirin.",
        claimedMoreGestures: "macOS bu hareketi de kullanıyor. Burada kullanmak için Sistem Ayarları’nda İzleme Dörtgeni, Daha Fazla Hareket bölümünden kapatın.",
        claimedLookUp: "macOS bu dokunmayla bir şeyleri araştırır. Burada kullanmak için Sistem Ayarları’nda İzleme Dörtgeni, İşaret Etme ve Tıklama bölümünden üç parmakla araştırmayı kapatın.",
        claimedThreeFingerDrag: "Üç parmakla sürükleme, üç parmaklı tüm hareketleri kullanır. Bunları burada kullanmak için Sistem Ayarları’nda Erişilebilirlik, İmleç Denetimi, İzleme Dörtgeni Seçenekleri bölümünden başka bir sürükleme stili seçin.",
        unavailableFeature: "Bu eylem, yüklü olmayan veya kapalı olan bir özellik gerektiriyor.",
        unavailableTarget: "Bu hareket için seçilen uygulama ya da dosya artık yok.",
        unavailableShortcut: "Bunun macOS klavye kısayolu Sistem Ayarları’nda Klavye, Klavye Kestirmeleri, Mission Control bölümünde kapalı.",
        openFeatures: "Özellikler’i aç"
    )

    static let ru = TrackpadGestureStrings(
        title: "Жесты трекпада",
        hubDescription: "Назначайте касания, смахивания и сведения тремя, четырьмя и пятью пальцами на сочетания клавиш, рабочие столы, раскладки окон и инструменты Vorssaint.",
        enableLabel: "Запускать действия жестами трекпада",
        enableCaption: "Касания, смахивания и сведения тремя–пятью пальцами запускают выбранное вами действие. Жест, который уже использует macOS, по-прежнему делает то, что задумано в macOS, поэтому выберите свободный или отключите системный жест.",
        threeFingers: "Три пальца",
        fourFingers: "Четыре пальца",
        fiveFingers: "Пять пальцев",
        kindTap: "Касание",
        kindSwipeLeft: "Смахивание влево",
        kindSwipeRight: "Смахивание вправо",
        kindSwipeUp: "Смахивание вверх",
        kindSwipeDown: "Смахивание вниз",
        kindPinchIn: "Сведение",
        kindPinchOut: "Разведение",
        actionLabel: "Действие",
        noAction: "Нет действия",
        otherAction: "Другое действие",
        navigationSection: "Рабочие столы и обзоры",
        spaceLeft: "Предыдущий рабочий стол",
        spaceRight: "Следующий рабочий стол",
        missionControl: "Mission Control",
        appExpose: "Exposé приложения",
        ownedByMiddleClick: "Это касание принадлежит средней кнопке. Измените его в разделе Средняя кнопка на трекпаде.",
        ownedByRadialMenu: "Это касание открывает радиальное меню. Измените его в настройках радиального меню.",
        claimedMoreGestures: "macOS тоже использует этот жест. Чтобы использовать его здесь, отключите его в Системных настройках, Трекпад, Другие жесты.",
        claimedLookUp: "macOS выполняет поиск по этому касанию. Чтобы использовать его здесь, отключите поиск тремя пальцами в Системных настройках, Трекпад, Выбор и нажатие.",
        claimedThreeFingerDrag: "Перетягивание тремя пальцами занимает все жесты тремя пальцами. Чтобы использовать их здесь, выберите другой способ перетягивания в Системных настройках, Универсальный доступ, Управление указателем, Параметры трекпада.",
        unavailableFeature: "Для этого действия нужна функция, которая не установлена или отключена.",
        unavailableTarget: "Приложение или файл, выбранные для этого жеста, больше не найдены.",
        unavailableShortcut: "Сочетание клавиш macOS для этого отключено в Системных настройках, Клавиатура, Сочетания клавиш, Mission Control.",
        openFeatures: "Открыть функции"
    )

    static let es = TrackpadGestureStrings(
        title: "Gestos del trackpad",
        hubDescription: "Asigna toques, deslizamientos y pellizcos con tres, cuatro y cinco dedos a atajos, Espacios, disposiciones de ventanas y herramientas de Vorssaint.",
        enableLabel: "Ejecutar acciones con gestos del trackpad",
        enableCaption: "Los toques, deslizamientos y pellizcos con tres a cinco dedos ejecutan la acción que elijas. Un gesto que macOS ya usa sigue haciendo lo que hace macOS, así que elige uno libre o desactiva el gesto del sistema.",
        threeFingers: "Tres dedos",
        fourFingers: "Cuatro dedos",
        fiveFingers: "Cinco dedos",
        kindTap: "Toque",
        kindSwipeLeft: "Deslizar a la izquierda",
        kindSwipeRight: "Deslizar a la derecha",
        kindSwipeUp: "Deslizar hacia arriba",
        kindSwipeDown: "Deslizar hacia abajo",
        kindPinchIn: "Pellizcar",
        kindPinchOut: "Separar",
        actionLabel: "Acción",
        noAction: "Sin acción",
        otherAction: "Otra acción",
        navigationSection: "Espacios y vistas generales",
        spaceLeft: "Espacio anterior",
        spaceRight: "Espacio siguiente",
        missionControl: "Mission Control",
        appExpose: "Exposé de apps",
        ownedByMiddleClick: "Este toque es el del clic central. Cámbialo en Clic central en el trackpad.",
        ownedByRadialMenu: "Este toque abre el menú radial. Cámbialo en los ajustes del menú radial.",
        claimedMoreGestures: "macOS también usa este gesto. Para usarlo aquí, desactívalo en Ajustes del Sistema, Trackpad, Más gestos.",
        claimedLookUp: "macOS consulta cosas con este toque. Para usarlo aquí, desactiva Consultar con tres dedos en Ajustes del Sistema, Trackpad, Señalar y hacer clic.",
        claimedThreeFingerDrag: "El arrastre con tres dedos usa todos los gestos de tres dedos. Para usarlos aquí, elige otro estilo de arrastre en Ajustes del Sistema, Accesibilidad, Control del puntero, Opciones del trackpad.",
        unavailableFeature: "Esta acción necesita una función que no está instalada o está desactivada.",
        unavailableTarget: "La app o el archivo elegido para este gesto ya no está.",
        unavailableShortcut: "El atajo de teclado de macOS para esto está desactivado en Ajustes del Sistema, Teclado, Atajos de teclado, Mission Control.",
        openFeatures: "Abrir Funciones"
    )

    static let sk = TrackpadGestureStrings(
        title: "Gestá trackpadu",
        hubDescription: "Priraďte ťuknutia, potiahnutia a stiahnutia tromi, štyrmi a piatimi prstami ku skratkám, plochám, rozloženiam okien a nástrojom Vorssaint.",
        enableLabel: "Spúšťať akcie gestami trackpadu",
        enableCaption: "Ťuknutia, potiahnutia a stiahnutia tromi až piatimi prstami spustia akciu, ktorú zvolíte. Gesto, ktoré macOS už používa, naďalej robí to, čo robí macOS, preto vyberte voľné alebo vypnite systémové gesto.",
        threeFingers: "Tri prsty",
        fourFingers: "Štyri prsty",
        fiveFingers: "Päť prstov",
        kindTap: "Ťuknutie",
        kindSwipeLeft: "Potiahnutie doľava",
        kindSwipeRight: "Potiahnutie doprava",
        kindSwipeUp: "Potiahnutie nahor",
        kindSwipeDown: "Potiahnutie nadol",
        kindPinchIn: "Stiahnutie",
        kindPinchOut: "Roztiahnutie",
        actionLabel: "Akcia",
        noAction: "Žiadna akcia",
        otherAction: "Iná akcia",
        navigationSection: "Plochy a prehľady",
        spaceLeft: "Predchádzajúca plocha",
        spaceRight: "Ďalšia plocha",
        missionControl: "Mission Control",
        appExpose: "Exposé aplikácie",
        ownedByMiddleClick: "Toto ťuknutie patrí strednému kliknutiu. Zmeníte ho v časti Stredné kliknutie na trackpade.",
        ownedByRadialMenu: "Toto ťuknutie otvára radiálne menu. Zmeníte ho v nastaveniach radiálneho menu.",
        claimedMoreGestures: "macOS používa toto gesto tiež. Ak ho chcete použiť tu, vypnite ho v Systémových nastaveniach v časti Trackpad, Ďalšie gestá.",
        claimedLookUp: "macOS týmto ťuknutím vyhľadáva. Ak ho chcete použiť tu, vypnite Vyhľadať tromi prstami v Systémových nastaveniach v časti Trackpad, Označiť a\u{00A0}kliknúť.",
        claimedThreeFingerDrag: "Ťahanie tromi prstami používa všetky gestá tromi prstami. Ak ich chcete použiť tu, vyberte iný štýl ťahania v Systémových nastaveniach v časti Prístupnosť, Ovládanie kurzora, Možnosti trackpadu.",
        unavailableFeature: "Táto akcia potrebuje funkciu, ktorá nie je nainštalovaná alebo je vypnutá.",
        unavailableTarget: "Aplikácia alebo súbor zvolený pre toto gesto už neexistuje.",
        unavailableShortcut: "Klávesová skratka macOS pre toto je vypnutá v Systémových nastaveniach v časti Klávesnica, Klávesové skratky, Mission Control.",
        openFeatures: "Otvoriť Funkcie"
    )

    static let de = TrackpadGestureStrings(
        title: "Trackpad-Gesten",
        hubDescription: "Ordne Tipp-, Wisch- und Zoombewegungen mit drei, vier und fünf Fingern Kurzbefehlen, Spaces, Fensteranordnungen und Vorssaint-Werkzeugen zu.",
        enableLabel: "Aktionen per Trackpad-Geste ausführen",
        enableCaption: "Tippen, Wischen und Zusammenziehen mit drei bis fünf Fingern führt die gewählte Aktion aus. Eine Geste, die macOS bereits nutzt, tut weiterhin, was macOS vorsieht, wähle also eine freie oder schalte die Systemgeste aus.",
        threeFingers: "Drei Finger",
        fourFingers: "Vier Finger",
        fiveFingers: "Fünf Finger",
        kindTap: "Tippen",
        kindSwipeLeft: "Nach links wischen",
        kindSwipeRight: "Nach rechts wischen",
        kindSwipeUp: "Nach oben wischen",
        kindSwipeDown: "Nach unten wischen",
        kindPinchIn: "Zusammenziehen",
        kindPinchOut: "Auseinanderziehen",
        actionLabel: "Aktion",
        noAction: "Keine Aktion",
        otherAction: "Andere Aktion",
        navigationSection: "Spaces und Übersichten",
        spaceLeft: "Vorheriger Space",
        spaceRight: "Nächster Space",
        missionControl: "Mission Control",
        appExpose: "App-Exposé",
        ownedByMiddleClick: "Dieses Tippen gehört dem Mittelklick. Ändere es unter Mittelklick per Trackpad.",
        ownedByRadialMenu: "Dieses Tippen öffnet das Radialmenü. Ändere es in den Einstellungen des Radialmenüs.",
        claimedMoreGestures: "macOS nutzt diese Geste ebenfalls. Um sie hier zu verwenden, schalte sie in den Systemeinstellungen unter Trackpad, Weitere Gesten aus.",
        claimedLookUp: "macOS schlägt mit diesem Tippen etwas nach. Um es hier zu verwenden, schalte Nachschlagen mit drei Fingern in den Systemeinstellungen unter Trackpad, Zeigen und Klicken aus.",
        claimedThreeFingerDrag: "Das Ziehen mit drei Fingern belegt jede Dreifingergeste. Um sie hier zu nutzen, wähle in den Systemeinstellungen unter Bedienungshilfen, Zeigersteuerung, Trackpad-Optionen eine andere Ziehart.",
        unavailableFeature: "Diese Aktion braucht eine Funktion, die nicht installiert oder ausgeschaltet ist.",
        unavailableTarget: "Die für diese Geste gewählte App oder Datei ist nicht mehr vorhanden.",
        unavailableShortcut: "Der macOS-Tastaturkurzbefehl dafür ist in den Systemeinstellungen unter Tastatur, Tastaturkurzbefehle, Mission Control ausgeschaltet.",
        openFeatures: "Funktionen öffnen"
    )

    static let fr = TrackpadGestureStrings(
        title: "Gestes du trackpad",
        hubDescription: "Associez les tapotements, balayages et pincements à trois, quatre et cinq doigts à des raccourcis, des espaces, des dispositions de fenêtres et des outils Vorssaint.",
        enableLabel: "Exécuter des actions avec les gestes du trackpad",
        enableCaption: "Les tapotements, balayages et pincements avec trois à cinq doigts exécutent l’action que vous choisissez. Un geste que macOS utilise déjà fait toujours ce que fait macOS, choisissez-en donc un libre ou désactivez le geste système.",
        threeFingers: "Trois doigts",
        fourFingers: "Quatre doigts",
        fiveFingers: "Cinq doigts",
        kindTap: "Tapotement",
        kindSwipeLeft: "Balayer vers la gauche",
        kindSwipeRight: "Balayer vers la droite",
        kindSwipeUp: "Balayer vers le haut",
        kindSwipeDown: "Balayer vers le bas",
        kindPinchIn: "Pincer",
        kindPinchOut: "Écarter",
        actionLabel: "Action",
        noAction: "Aucune action",
        otherAction: "Autre action",
        navigationSection: "Espaces et vues d’ensemble",
        spaceLeft: "Espace précédent",
        spaceRight: "Espace suivant",
        missionControl: "Mission Control",
        appExpose: "App Exposé",
        ownedByMiddleClick: "Ce tapotement est celui du clic du milieu. Modifiez-le dans Clic du milieu au trackpad.",
        ownedByRadialMenu: "Ce tapotement ouvre le menu radial. Modifiez-le dans les réglages du menu radial.",
        claimedMoreGestures: "macOS utilise aussi ce geste. Pour l’utiliser ici, désactivez-le dans Réglages Système, Trackpad, Gestes supplémentaires.",
        claimedLookUp: "macOS effectue une recherche avec ce tapotement. Pour l’utiliser ici, désactivez Recherche avec trois doigts dans Réglages Système, Trackpad, Pointer et cliquer.",
        claimedThreeFingerDrag: "Le glissement à trois doigts utilise tous les gestes à trois doigts. Pour les utiliser ici, choisissez un autre style de glissement dans Réglages Système, Accessibilité, Contrôle du pointeur, Options du trackpad.",
        unavailableFeature: "Cette action nécessite une fonction qui n’est pas installée ou qui est désactivée.",
        unavailableTarget: "L’app ou le fichier choisi pour ce geste n’existe plus.",
        unavailableShortcut: "Le raccourci clavier macOS correspondant est désactivé dans Réglages Système, Clavier, Raccourcis clavier, Mission Control.",
        openFeatures: "Ouvrir Fonctionnalités"
    )

    static let it = TrackpadGestureStrings(
        title: "Gesti del trackpad",
        hubDescription: "Associa tocchi, scorrimenti e pizzichi con tre, quattro e cinque dita a scorciatoie, Spazi, disposizioni delle finestre e strumenti Vorssaint.",
        enableLabel: "Esegui azioni con i gesti del trackpad",
        enableCaption: "Tocchi, scorrimenti e pizzichi con tre-cinque dita eseguono l’azione che scegli. Un gesto che macOS usa già continua a fare ciò che fa macOS, quindi scegline uno libero o disattiva il gesto di sistema.",
        threeFingers: "Tre dita",
        fourFingers: "Quattro dita",
        fiveFingers: "Cinque dita",
        kindTap: "Tocco",
        kindSwipeLeft: "Scorri a sinistra",
        kindSwipeRight: "Scorri a destra",
        kindSwipeUp: "Scorri in alto",
        kindSwipeDown: "Scorri in basso",
        kindPinchIn: "Pizzica",
        kindPinchOut: "Allarga",
        actionLabel: "Azione",
        noAction: "Nessuna azione",
        otherAction: "Altra azione",
        navigationSection: "Spazi e panoramiche",
        spaceLeft: "Spazio precedente",
        spaceRight: "Spazio successivo",
        missionControl: "Mission Control",
        appExpose: "Exposé app",
        ownedByMiddleClick: "Questo tocco è quello del clic centrale. Cambialo in Clic centrale da trackpad.",
        ownedByRadialMenu: "Questo tocco apre il menu radiale. Cambialo nelle impostazioni del menu radiale.",
        claimedMoreGestures: "macOS usa anche questo gesto. Per usarlo qui, disattivalo in Impostazioni di Sistema, Trackpad, Altre azioni.",
        claimedLookUp: "macOS cerca le cose con questo tocco. Per usarlo qui, disattiva Cerca con tre dita in Impostazioni di Sistema, Trackpad, Punta e fai clic.",
        claimedThreeFingerDrag: "Il trascinamento a tre dita usa ogni gesto a tre dita. Per usarli qui, scegli un altro stile di trascinamento in Impostazioni di Sistema, Accessibilità, Controllo puntatore, Opzioni trackpad.",
        unavailableFeature: "Questa azione richiede una funzione che non è installata o è disattivata.",
        unavailableTarget: "L’app o il file scelto per questo gesto non c’è più.",
        unavailableShortcut: "L’abbreviazione da tastiera di macOS per questo è disattivata in Impostazioni di Sistema, Tastiera, Scorciatoie da tastiera, Mission Control.",
        openFeatures: "Apri Funzioni"
    )

    static let ja = TrackpadGestureStrings(
        title: "トラックパッドのジェスチャ",
        hubDescription: "3本指、4本指、5本指のタップ、スワイプ、ピンチを、ショートカット、スペース、ウインドウレイアウト、Vorssaintのツールに割り当てます。",
        enableLabel: "トラックパッドのジェスチャでアクションを実行",
        enableCaption: "3〜5本指のタップ、スワイプ、ピンチで、選んだアクションを実行します。macOSがすでに使っているジェスチャは今までどおりmacOSの動作をするため、空いているものを選ぶか、システムのジェスチャをオフにしてください。",
        threeFingers: "3本指",
        fourFingers: "4本指",
        fiveFingers: "5本指",
        kindTap: "タップ",
        kindSwipeLeft: "左にスワイプ",
        kindSwipeRight: "右にスワイプ",
        kindSwipeUp: "上にスワイプ",
        kindSwipeDown: "下にスワイプ",
        kindPinchIn: "ピンチイン",
        kindPinchOut: "ピンチアウト",
        actionLabel: "アクション",
        noAction: "アクションなし",
        otherAction: "その他のアクション",
        navigationSection: "スペースと概要",
        spaceLeft: "前のスペース",
        spaceRight: "次のスペース",
        missionControl: "Mission Control",
        appExpose: "App Exposé",
        ownedByMiddleClick: "このタップは中クリックのタップです。トラックパッドの中クリックで変更してください。",
        ownedByRadialMenu: "このタップはラジアルメニューを開きます。ラジアルメニューの設定で変更してください。",
        claimedMoreGestures: "macOSもこのジェスチャを使っています。ここで使うには、システム設定、トラックパッド、その他のジェスチャでオフにしてください。",
        claimedLookUp: "macOSはこのタップで調べます。ここで使うには、システム設定、トラックパッド、ポイントとクリックで、3本指で調べるをオフにしてください。",
        claimedThreeFingerDrag: "3本指のドラッグはすべての3本指ジェスチャを使います。ここで使うには、システム設定、アクセシビリティ、ポインタコントロール、トラックパッドオプションで、別のドラッグ方法を選んでください。",
        unavailableFeature: "このアクションには、インストールされていないか、オフになっている機能が必要です。",
        unavailableTarget: "このジェスチャに選んだAppまたはファイルが見つかりません。",
        unavailableShortcut: "これに対応するmacOSのキーボードショートカットは、システム設定、キーボード、キーボードショートカット、Mission Controlでオフになっています。",
        openFeatures: "機能を開く"
    )

    static let ko = TrackpadGestureStrings(
        title: "트랙패드 제스처",
        hubDescription: "세 손가락, 네 손가락, 다섯 손가락 탭, 쓸기, 오므리기를 단축키, 스페이스, 윈도우 레이아웃, Vorssaint 도구에 연결합니다.",
        enableLabel: "트랙패드 제스처로 동작 실행",
        enableCaption: "세~다섯 손가락 탭, 쓸기, 오므리기로 선택한 동작을 실행합니다. macOS가 이미 사용하는 제스처는 계속 macOS 동작을 하므로, 비어 있는 제스처를 고르거나 시스템 제스처를 끄세요.",
        threeFingers: "세 손가락",
        fourFingers: "네 손가락",
        fiveFingers: "다섯 손가락",
        kindTap: "탭",
        kindSwipeLeft: "왼쪽으로 쓸기",
        kindSwipeRight: "오른쪽으로 쓸기",
        kindSwipeUp: "위로 쓸기",
        kindSwipeDown: "아래로 쓸기",
        kindPinchIn: "오므리기",
        kindPinchOut: "벌리기",
        actionLabel: "동작",
        noAction: "동작 없음",
        otherAction: "다른 동작",
        navigationSection: "스페이스 및 개요",
        spaceLeft: "이전 스페이스",
        spaceRight: "다음 스페이스",
        missionControl: "미션 컨트롤",
        appExpose: "앱 엑스포제",
        ownedByMiddleClick: "이 탭은 가운데 클릭의 탭입니다. 트랙패드 가운데 클릭에서 변경하세요.",
        ownedByRadialMenu: "이 탭은 방사형 메뉴를 엽니다. 방사형 메뉴 설정에서 변경하세요.",
        claimedMoreGestures: "macOS도 이 제스처를 사용합니다. 여기서 사용하려면 시스템 설정, 트랙패드, 추가 제스처에서 끄세요.",
        claimedLookUp: "macOS는 이 탭으로 찾아봅니다. 여기서 사용하려면 시스템 설정, 트랙패드, 포인트 및 클릭에서 세 손가락으로 찾아보기를 끄세요.",
        claimedThreeFingerDrag: "세 손가락 드래그는 모든 세 손가락 제스처를 사용합니다. 여기서 사용하려면 시스템 설정, 손쉬운 사용, 포인터 제어, 트랙패드 옵션에서 다른 드래그 방식을 선택하세요.",
        unavailableFeature: "이 동작에는 설치되어 있지 않거나 꺼져 있는 기능이 필요합니다.",
        unavailableTarget: "이 제스처에 선택한 앱이나 파일이 더 이상 없습니다.",
        unavailableShortcut: "이에 해당하는 macOS 키보드 단축키가 시스템 설정, 키보드, 키보드 단축키, Mission Control에서 꺼져 있습니다.",
        openFeatures: "기능 열기"
    )

    static let uk = TrackpadGestureStrings(
        title: "Жести трекпеда",
        hubDescription: "Призначайте дотики, змахи та зведення трьома, чотирма й п’ятьма пальцями на скорочення, Space, розкладки вікон та інструменти Vorssaint.",
        enableLabel: "Запускати дії жестами трекпеда",
        enableCaption: "Дотики, змахи та зведення трьома–п’ятьма пальцями запускають вибрану вами дію. Жест, який macOS уже використовує, і далі робить те, що передбачено в macOS, тож виберіть вільний або вимкніть системний жест.",
        threeFingers: "Три пальці",
        fourFingers: "Чотири пальці",
        fiveFingers: "П’ять пальців",
        kindTap: "Дотик",
        kindSwipeLeft: "Змах уліво",
        kindSwipeRight: "Змах управо",
        kindSwipeUp: "Змах угору",
        kindSwipeDown: "Змах униз",
        kindPinchIn: "Зведення",
        kindPinchOut: "Розведення",
        actionLabel: "Дія",
        noAction: "Немає дії",
        otherAction: "Інша дія",
        navigationSection: "Space та огляди",
        spaceLeft: "Попередній Space",
        spaceRight: "Наступний Space",
        missionControl: "Mission Control",
        appExpose: "App Exposé",
        ownedByMiddleClick: "Цей дотик належить середній кнопці. Змініть його в розділі Середня кнопка на трекпеді.",
        ownedByRadialMenu: "Цей дотик відкриває радіальне меню. Змініть його в параметрах радіального меню.",
        claimedMoreGestures: "macOS також використовує цей жест. Щоб користуватися ним тут, вимкніть його в Системних параметрах, Трекпед, Інші жести.",
        claimedLookUp: "macOS шукає за цим дотиком. Щоб користуватися ним тут, вимкніть пошук трьома пальцями в Системних параметрах, Трекпед, Наведення і клацання.",
        claimedThreeFingerDrag: "Перетягування трьома пальцями використовує всі жести трьома пальцями. Щоб користуватися ними тут, виберіть інший стиль перетягування в Системних параметрах, Доступність, Керування вказівником, Параметри трекпеда.",
        unavailableFeature: "Для цієї дії потрібна функція, яка не встановлена або вимкнена.",
        unavailableTarget: "Програми або файлу, вибраних для цього жесту, більше немає.",
        unavailableShortcut: "Клавіатурне скорочення macOS для цього вимкнене в Системних параметрах, Клавіатура, Клавіатурні скорочення, Mission Control.",
        openFeatures: "Відкрити Функції"
    )

    static let zhHans = TrackpadGestureStrings(
        title: "触控板手势",
        hubDescription: "将三指、四指和五指的轻点、轻扫和捏合映射到快捷键、桌面、窗口布局和 Vorssaint 工具。",
        enableLabel: "用触控板手势执行操作",
        enableCaption: "用三到五根手指轻点、轻扫和捏合，会执行你选择的操作。macOS 已在使用的手势仍会执行 macOS 的功能，所以请选择空闲的手势，或关闭系统手势。",
        threeFingers: "三指",
        fourFingers: "四指",
        fiveFingers: "五指",
        kindTap: "轻点",
        kindSwipeLeft: "向左轻扫",
        kindSwipeRight: "向右轻扫",
        kindSwipeUp: "向上轻扫",
        kindSwipeDown: "向下轻扫",
        kindPinchIn: "捏合",
        kindPinchOut: "张开",
        actionLabel: "操作",
        noAction: "无操作",
        otherAction: "其他操作",
        navigationSection: "桌面与概览",
        spaceLeft: "上一个桌面",
        spaceRight: "下一个桌面",
        missionControl: "调度中心",
        appExpose: "应用程序窗口",
        ownedByMiddleClick: "这个轻点属于中键点按。请在触控板中键点按中更改。",
        ownedByRadialMenu: "这个轻点会打开径向菜单。请在径向菜单设置中更改。",
        claimedMoreGestures: "macOS 也在使用这个手势。要在这里使用，请在系统设置、触控板、更多手势中将其关闭。",
        claimedLookUp: "macOS 用这个轻点来查询。要在这里使用，请在系统设置、触控板、光标与点按中关闭用三指轻点查询。",
        claimedThreeFingerDrag: "三指拖移会占用所有三指手势。要在这里使用它们，请在系统设置、辅助功能、指针控制、触控板选项中选择其他拖移方式。",
        unavailableFeature: "此操作需要一项尚未安装或已关闭的功能。",
        unavailableTarget: "为此手势选择的 App 或文件已不存在。",
        unavailableShortcut: "对应的 macOS 键盘快捷键已在系统设置、键盘、键盘快捷键、调度中心中关闭。",
        openFeatures: "打开功能"
    )

    static let zhTW = TrackpadGestureStrings(
        title: "觸控式軌跡板手勢",
        hubDescription: "將三指、四指和五指的輕點、輕掃和捏合對應到快速鍵、桌面、視窗配置和 Vorssaint 工具。",
        enableLabel: "用觸控式軌跡板手勢執行動作",
        enableCaption: "用三到五根手指輕點、輕掃和捏合，會執行你選擇的動作。macOS 已在使用的手勢仍會執行 macOS 的功能，所以請選擇空閒的手勢，或關閉系統手勢。",
        threeFingers: "三指",
        fourFingers: "四指",
        fiveFingers: "五指",
        kindTap: "輕點",
        kindSwipeLeft: "向左輕掃",
        kindSwipeRight: "向右輕掃",
        kindSwipeUp: "向上輕掃",
        kindSwipeDown: "向下輕掃",
        kindPinchIn: "捏合",
        kindPinchOut: "張開",
        actionLabel: "動作",
        noAction: "無動作",
        otherAction: "其他動作",
        navigationSection: "桌面與概覽",
        spaceLeft: "上一個桌面",
        spaceRight: "下一個桌面",
        missionControl: "指揮中心",
        appExpose: "App Exposé",
        ownedByMiddleClick: "這個輕點屬於中鍵點按。請在觸控式軌跡板中鍵點按中更改。",
        ownedByRadialMenu: "這個輕點會開啟放射狀選單。請在放射狀選單設定中更改。",
        claimedMoreGestures: "macOS 也在使用這個手勢。要在這裡使用，請在系統設定、觸控式軌跡板、更多手勢中將其關閉。",
        claimedLookUp: "macOS 用這個輕點來查詢。要在這裡使用，請在系統設定、觸控式軌跡板、點按中關閉用三指輕點查詢。",
        claimedThreeFingerDrag: "三指拖移會佔用所有三指手勢。要在這裡使用它們，請在系統設定、輔助使用、指標控制、觸控式軌跡板選項中選擇其他拖移方式。",
        unavailableFeature: "此動作需要一項尚未安裝或已關閉的功能。",
        unavailableTarget: "為此手勢選擇的 App 或檔案已不存在。",
        unavailableShortcut: "對應的 macOS 鍵盤快速鍵已在系統設定、鍵盤、鍵盤快速鍵、指揮中心中關閉。",
        openFeatures: "開啟功能"
    )

    static let zhHK = TrackpadGestureStrings(
        title: "觸控板手勢",
        hubDescription: "將三指、四指和五指的輕點、輕掃和捏合對應到快捷鍵、桌面、視窗配置和 Vorssaint 工具。",
        enableLabel: "用觸控板手勢執行動作",
        enableCaption: "用三到五根手指輕點、輕掃和捏合，會執行你選擇的動作。macOS 已在使用的手勢仍會執行 macOS 的功能，所以請選擇空閒的手勢，或關閉系統手勢。",
        threeFingers: "三指",
        fourFingers: "四指",
        fiveFingers: "五指",
        kindTap: "輕點",
        kindSwipeLeft: "向左輕掃",
        kindSwipeRight: "向右輕掃",
        kindSwipeUp: "向上輕掃",
        kindSwipeDown: "向下輕掃",
        kindPinchIn: "捏合",
        kindPinchOut: "張開",
        actionLabel: "動作",
        noAction: "無動作",
        otherAction: "其他動作",
        navigationSection: "桌面與概覽",
        spaceLeft: "上一個桌面",
        spaceRight: "下一個桌面",
        missionControl: "指揮中心",
        appExpose: "App Exposé",
        ownedByMiddleClick: "這個輕點屬於中鍵點按。請在觸控板中鍵點按中更改。",
        ownedByRadialMenu: "這個輕點會開啟放射狀選單。請在放射狀選單設定中更改。",
        claimedMoreGestures: "macOS 也在使用這個手勢。要在這裡使用，請在系統設定、觸控板、更多手勢中將其關閉。",
        claimedLookUp: "macOS 用這個輕點來查詢。要在這裡使用，請在系統設定、觸控板、點按中關閉用三指輕點查詢。",
        claimedThreeFingerDrag: "三指拖移會佔用所有三指手勢。要在這裡使用它們，請在系統設定、輔助使用、指標控制、觸控板選項中選擇其他拖移方式。",
        unavailableFeature: "此動作需要一項尚未安裝或已關閉的功能。",
        unavailableTarget: "為此手勢選擇的 App 或檔案已不存在。",
        unavailableShortcut: "對應的 macOS 鍵盤快捷鍵已在系統設定、鍵盤、鍵盤快捷鍵、指揮中心中關閉。",
        openFeatures: "開啟功能"
    )
}
