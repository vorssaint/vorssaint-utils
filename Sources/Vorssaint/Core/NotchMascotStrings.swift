// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchMascotStrings {
    let title: String
    let hint: String
    let visits: String
    let visitsHint: String
    let style: String
    let minimal: String
    let robot: String
    let shape: String
    let ball: String
    let egg: String
    let squircle: String
    let pill: String
    let color: String
    let pearl: String
    let mint: String
    let peach: String
    let lilac: String
    let lemon: String
    let rose: String
    let commandBar: String
    let commandBarHint: String
    let opensAs: String
    let droplet: String
    let openIsland: String
    /// The Settings preview, for VoiceOver, and what clicking it does.
    let preview: String
    let previewHint: String
    /// Which side of the camera it rests on.
    let side: String
    let left: String
    let right: String
    /// How often it strolls through the island.
    let frequency: String
    let rare: String
    let normal: String
    let frequent: String
    let sky: String
    /// One line for the Features page.
    let hubDescription: String
    let appearance: String
    let behavior: String
    /// Whether it comes out to react to what happens.
    let reactions: String
    let reactionsHint: String
    /// Whether it hides in the island once nothing happens for a while.
    let hidesWhenIdle: String
    let hidesWhenIdleHint: String
    /// The Settings button that has it say hello in the island now.
    let sayHi: String
    let sayHiHint: String
    /// The moments the Settings preview can act out.
    let momentsTitle: String
    let visitMoment: String
    let timerStarted: String
    let downloadFailed: String
    let unlocked: String
    /// How to pet it, and that it dozes off.
    let petTip: String
    /// Said on its page while the Dynamic Island is off.
    let livesInIsland: String
    /// More words a search finds its page by.
    let keywords: String

    func style(_ style: NotchMascotStyle) -> String {
        style == .robot ? robot : minimal
    }

    func shape(_ shape: NotchMascotShape) -> String {
        switch shape {
        case .ball: return ball
        case .egg: return egg
        case .squircle: return squircle
        case .pill: return pill
        }
    }

    func palette(_ palette: NotchMascotPalette) -> String {
        switch palette {
        case .pearl: return pearl
        case .mint: return mint
        case .peach: return peach
        case .lilac: return lilac
        case .lemon: return lemon
        case .rose: return rose
        case .sky: return sky
        }
    }

    func commandBarStyle(_ style: NotchCommandBarStyle) -> String {
        style == .island ? openIsland : droplet
    }

    func side(_ side: NotchMascotSide) -> String {
        side == .right ? right : left
    }

    /// A moment's name. Those the island already names elsewhere say it the
    /// same way here.
    func moment(_ moment: NotchMascotMoment, language: AppLanguage) -> String {
        switch moment {
        case .visit: return visitMoment
        case .timerStarted: return timerStarted
        case .timeIsUp: return FeatureStrings.notchActivities(language).finished
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .agents: return FeatureStrings.notchAgents(language).title
        case .eventStarts: return FeatureStrings.notchCalendar(language).ongoing
        case .downloadFinished: return FeatureStrings.notchFiles(language).completed
        case .downloadFailed: return downloadFailed
        case .screenshot: return FeatureStrings.screenshot(language).pageTitle
        case .micMuted: return Strings.localized(language).micMutedHUD
        case .keepAwake: return Strings.localized(language).keepAwakeTitle
        case .charging: return FeatureStrings.notch(language).charging
        case .lowBattery: return FeatureStrings.notch(language).lowBattery
        case .unlocked: return unlocked
        }
    }

    /// What a search finds its page by, besides its name.
    var searchKeywords: [String] {
        [hint, visits, reactions, hidesWhenIdle, style, robot, shape, color, side, frequency, commandBar, keywords]
    }

    func frequency(_ frequency: NotchMascotVisitFrequency) -> String {
        switch frequency {
        case .rare: return rare
        case .normal: return normal
        case .frequent: return frequent
        }
    }
}

extension FeatureStrings {
    static func notchMascot(_ language: AppLanguage) -> NotchMascotStrings {
        switch language {
        case .enUS: return NotchMascotStrings(
            title: "Companion",
            hint: "A little friend who lives in the Dynamic Island. It rests there when nothing else is showing, and comes out over music and activities to say hello and react to what happens.",
            visits: "Appear now and then",
            visitsHint: "Every few minutes it passes through the island with a short animation.",
            style: "Style", minimal: "Minimal", robot: "Robot",
            shape: "Shape", ball: "Ball", egg: "Egg", squircle: "Rounded square", pill: "Pill",
            color: "Color", pearl: "Pearl", mint: "Mint", peach: "Peach", lilac: "Lilac", lemon: "Lemon", rose: "Rose",
            commandBar: "Command Bar in the island",
            commandBarHint: "With the shortcut, the Command Bar comes out of the island with the companion as its face. It reacts while you search.",
            opensAs: "Opens as", droplet: "Drop", openIsland: "Open island",
            preview: "Companion preview", previewHint: "Click to see it react.",
            side: "Side of the camera", left: "Left", right: "Right",
            frequency: "How often", rare: "Rarely", normal: "Sometimes", frequent: "Often",
            sky: "Sky",
            hubDescription: "A little friend in the Dynamic Island who says hello now and then and reacts to what happens on your Mac.",
            appearance: "Appearance", behavior: "Behavior",
            reactions: "React to what happens",
            reactionsHint: "It comes out to react to music, timers, downloads, screenshots, the microphone, Keep awake and more.",
            hidesWhenIdle: "Hide when idle",
            hidesWhenIdleHint: "After half a minute with nothing going on, it hops into the island and the island goes back to its usual size. Visits and reactions still bring it out.",
            sayHi: "Say Hi", sayHiHint: "Plays a visit in the Dynamic Island now.",
            momentsTitle: "See how it reacts",
            visitMoment: "A visit", timerStarted: "Timer started", downloadFailed: "Download failed", unlocked: "Mac unlocked",
            petTip: "Rest the pointer on it to pet it. Left alone, it dozes off until you come back.",
            livesInIsland: "The companion lives in the Dynamic Island.",
            keywords: "mascot pet buddy character")
        case .ptBR: return NotchMascotStrings(
            title: "Companheiro",
            hint: "Um amiguinho que mora no Dynamic Island. Descansa ali quando não há mais nada aparecendo e sai por cima de músicas e atividades para dar oi e reagir ao que acontece.",
            visits: "Aparecer de vez em quando",
            visitsHint: "A cada poucos minutos ele passa pela ilha com uma animação curta.",
            style: "Estilo", minimal: "Minimalista", robot: "Robô",
            shape: "Forma", ball: "Bolinha", egg: "Ovo", squircle: "Quadrado arredondado", pill: "Pílula",
            color: "Cor", pearl: "Pérola", mint: "Menta", peach: "Pêssego", lilac: "Lilás", lemon: "Limão", rose: "Rosa",
            commandBar: "Barra de comando na ilha",
            commandBarHint: "Com o atalho, a Barra de comando sai da ilha com o companheiro como ícone. Ele reage enquanto você pesquisa.",
            opensAs: "Abre como", droplet: "Gota", openIsland: "Ilha aberta",
            preview: "Prévia do companheiro", previewHint: "Clique para ver ele reagir.",
            side: "Lado da câmera", left: "Esquerda", right: "Direita",
            frequency: "Frequência", rare: "Rara", normal: "Normal", frequent: "Frequente",
            sky: "Céu",
            hubDescription: "Um amiguinho no Dynamic Island que dá oi de vez em quando e reage ao que acontece no seu Mac.",
            appearance: "Aparência", behavior: "Comportamento",
            reactions: "Reagir ao que acontece",
            reactionsHint: "Ele aparece para reagir a músicas, temporizadores, downloads, capturas de tela, ao microfone, ao Manter acordado e mais.",
            hidesWhenIdle: "Esconder quando ocioso",
            hidesWhenIdleHint: "Depois de meio minuto sem nada acontecendo, ele pula para dentro da ilha e a ilha volta ao tamanho normal. Ele ainda sai para visitas e reações.",
            sayHi: "Dar oi", sayHiHint: "Mostra uma visita no Dynamic Island agora.",
            momentsTitle: "Veja como ele reage",
            visitMoment: "Uma visita", timerStarted: "Temporizador iniciado", downloadFailed: "Falha no download", unlocked: "Mac desbloqueado",
            petTip: "Deixe o ponteiro parado sobre ele para fazer carinho. Sozinho, ele cochila até você voltar.",
            livesInIsland: "O companheiro mora no Dynamic Island.",
            keywords: "mascote bichinho amigo personagem")
        case .es: return NotchMascotStrings(
            title: "Compañero",
            hint: "Un amiguito que vive en el Dynamic Island. Descansa allí cuando no se muestra nada más y sale sobre la música y las actividades para saludar y reaccionar a lo que pasa.",
            visits: "Aparecer de vez en cuando",
            visitsHint: "Cada pocos minutos pasa por la isla con una animación corta.",
            style: "Estilo", minimal: "Minimalista", robot: "Robot",
            shape: "Forma", ball: "Bolita", egg: "Huevo", squircle: "Cuadrado redondeado", pill: "Píldora",
            color: "Color", pearl: "Perla", mint: "Menta", peach: "Melocotón", lilac: "Lila", lemon: "Limón", rose: "Rosa",
            commandBar: "Barra de comandos en la isla",
            commandBarHint: "Con el atajo, la Barra de comandos sale de la isla con el compañero como icono. Reacciona mientras buscas.",
            opensAs: "Se abre como", droplet: "Gota", openIsland: "Isla abierta",
            preview: "Vista previa del compañero", previewHint: "Haz clic para verlo reaccionar.",
            side: "Lado de la cámara", left: "Izquierda", right: "Derecha",
            frequency: "Frecuencia", rare: "Rara", normal: "Normal", frequent: "Frecuente",
            sky: "Cielo",
            hubDescription: "Un amiguito en el Dynamic Island que saluda de vez en cuando y reacciona a lo que pasa en tu Mac.",
            appearance: "Apariencia", behavior: "Comportamiento",
            reactions: "Reaccionar a lo que pasa",
            reactionsHint: "Sale para reaccionar a la música, temporizadores, descargas, capturas de pantalla, el micrófono, Mantener activo y más.",
            hidesWhenIdle: "Ocultar si está inactivo",
            hidesWhenIdleHint: "Tras medio minuto sin que pase nada, salta dentro de la isla y la isla vuelve a su tamaño normal. Sigue saliendo para las visitas y las reacciones.",
            sayHi: "Saludar", sayHiHint: "Muestra una visita en el Dynamic Island ahora.",
            momentsTitle: "Mira cómo reacciona",
            visitMoment: "Una visita", timerStarted: "Temporizador iniciado", downloadFailed: "Error en la descarga", unlocked: "Mac desbloqueado",
            petTip: "Deja el puntero quieto sobre él para acariciarlo. Si lo dejas solo, se duerme hasta que vuelvas.",
            livesInIsland: "El compañero vive en el Dynamic Island.",
            keywords: "mascota amiguito personaje")
        case .sk: return NotchMascotStrings(
            title: "Spoločník",
            hint: "Malý kamarát, ktorý býva v Dynamic Island. Odpočíva tam, keď sa nič iné nezobrazuje, a ponad hudbu a aktivity sa ukáže, aby pozdravil a zareagoval na to, čo sa deje.",
            visits: "Občas sa ukázať",
            visitsHint: "Každých pár minút prejde ostrovom s krátkou animáciou.",
            style: "Štýl", minimal: "Minimalistický", robot: "Robot",
            shape: "Tvar", ball: "Guľôčka", egg: "Vajíčko", squircle: "Zaoblený štvorec", pill: "Pilulka",
            color: "Farba", pearl: "Perleťová", mint: "Mätová", peach: "Broskyňová", lilac: "Orgovánová", lemon: "Citrónová", rose: "Ružová",
            commandBar: "Príkazová lišta na ostrove",
            commandBarHint: "Po stlačení skratky vyjde príkazová lišta z ostrova so spoločníkom ako tvárou. Reaguje, kým hľadáte.",
            opensAs: "Otvorí sa ako", droplet: "Kvapka", openIsland: "Otvorený ostrov",
            preview: "Ukážka spoločníka", previewHint: "Kliknutím uvidíte, ako reaguje.",
            side: "Strana kamery", left: "Vľavo", right: "Vpravo",
            frequency: "Ako často", rare: "Zriedka", normal: "Občas", frequent: "Často",
            sky: "Nebeská",
            hubDescription: "Malý kamarát v Dynamic Island, ktorý občas pozdraví a reaguje na to, čo sa deje na vašom Macu.",
            appearance: "Vzhľad", behavior: "Správanie",
            reactions: "Reagovať na to, čo sa deje",
            reactionsHint: "Ukáže sa, aby zareagoval na hudbu, časovače, sťahovanie, snímky obrazovky, mikrofón, Bdelý režim a ďalšie.",
            hidesWhenIdle: "Skryť pri nečinnosti",
            hidesWhenIdleHint: "Keď sa pol minúty nič nedeje, skočí do ostrova a ostrov sa vráti na bežnú veľkosť. Na návštevy a reakcie stále vyjde von.",
            sayHi: "Pozdraviť", sayHiHint: "Hneď zahrá návštevu v Dynamic Island.",
            momentsTitle: "Pozrite, ako reaguje",
            visitMoment: "Návšteva", timerStarted: "Časovač spustený", downloadFailed: "Sťahovanie zlyhalo", unlocked: "Mac odomknutý",
            petTip: "Nechajte na ňom chvíľu ukazovateľ a pohladkáte ho. Keď je sám, zdriemne si, kým sa nevrátite.",
            livesInIsland: "Spoločník býva v Dynamic Island.",
            keywords: "maskot zvieratko kamarát postavička")
        case .de: return NotchMascotStrings(
            title: "Begleiter",
            hint: "Ein kleiner Freund, der im Dynamic Island wohnt. Er ruht dort, wenn sonst nichts angezeigt wird, und kommt über Musik und Aktivitäten hervor, um Hallo zu sagen und auf das Geschehen zu reagieren.",
            visits: "Ab und zu vorbeischauen",
            visitsHint: "Alle paar Minuten läuft er mit einer kurzen Animation durch die Insel.",
            style: "Stil", minimal: "Minimal", robot: "Roboter",
            shape: "Form", ball: "Kugel", egg: "Ei", squircle: "Abgerundetes Quadrat", pill: "Pille",
            color: "Farbe", pearl: "Perle", mint: "Minze", peach: "Pfirsich", lilac: "Flieder", lemon: "Zitrone", rose: "Rosa",
            commandBar: "Befehlsleiste in der Insel",
            commandBarHint: "Mit dem Kurzbefehl kommt die Befehlsleiste aus der Insel, mit dem Begleiter als Gesicht. Er reagiert, während du suchst.",
            opensAs: "Öffnet als", droplet: "Tropfen", openIsland: "Geöffnete Insel",
            preview: "Vorschau des Begleiters", previewHint: "Klicken, um ihn reagieren zu sehen.",
            side: "Seite der Kamera", left: "Links", right: "Rechts",
            frequency: "Wie oft", rare: "Selten", normal: "Manchmal", frequent: "Oft",
            sky: "Himmel",
            hubDescription: "Ein kleiner Freund im Dynamic Island, der ab und zu Hallo sagt und auf das reagiert, was auf deinem Mac passiert.",
            appearance: "Aussehen", behavior: "Verhalten",
            reactions: "Auf das Geschehen reagieren",
            reactionsHint: "Er kommt hervor, um auf Musik, Timer, Downloads, Bildschirmfotos, das Mikrofon, Wachhalten und mehr zu reagieren.",
            hidesWhenIdle: "Bei Inaktivität verstecken",
            hidesWhenIdleHint: "Passiert eine halbe Minute lang nichts, hüpft er in die Insel, und die Insel hat wieder ihre normale Größe. Für Besuche und Reaktionen kommt er weiterhin hervor.",
            sayHi: "Hallo sagen", sayHiHint: "Spielt jetzt einen Besuch im Dynamic Island ab.",
            momentsTitle: "So reagiert er",
            visitMoment: "Ein Besuch", timerStarted: "Timer gestartet", downloadFailed: "Download fehlgeschlagen", unlocked: "Mac entsperrt",
            petTip: "Lass den Zeiger kurz auf ihm ruhen, um ihn zu streicheln. Allein döst er ein, bis du zurückkommst.",
            livesInIsland: "Der Begleiter wohnt im Dynamic Island.",
            keywords: "Maskottchen Haustier Kumpel Figur")
        case .fr: return NotchMascotStrings(
            title: "Compagnon",
            hint: "Un petit ami qui vit dans le Dynamic Island. Il s’y repose quand rien d’autre n’est affiché, et sort par-dessus la musique et les activités pour dire bonjour et réagir à ce qui se passe.",
            visits: "Passer de temps en temps",
            visitsHint: "Toutes les quelques minutes, il traverse l’île avec une courte animation.",
            style: "Style", minimal: "Minimaliste", robot: "Robot",
            shape: "Forme", ball: "Boule", egg: "Œuf", squircle: "Carré arrondi", pill: "Pilule",
            color: "Couleur", pearl: "Perle", mint: "Menthe", peach: "Pêche", lilac: "Lilas", lemon: "Citron", rose: "Rose",
            commandBar: "Barre de commande dans l’île",
            commandBarHint: "Avec le raccourci, la Barre de commande sort de l’île avec le compagnon comme visage. Il réagit pendant que vous cherchez.",
            opensAs: "S’ouvre en", droplet: "Goutte", openIsland: "Île ouverte",
            preview: "Aperçu du compagnon", previewHint: "Cliquez pour le voir réagir.",
            side: "Côté de la caméra", left: "Gauche", right: "Droite",
            frequency: "Fréquence", rare: "Rare", normal: "Normale", frequent: "Fréquente",
            sky: "Ciel",
            hubDescription: "Un petit ami dans le Dynamic Island qui dit bonjour de temps en temps et réagit à ce qui se passe sur votre Mac.",
            appearance: "Apparence", behavior: "Comportement",
            reactions: "Réagir à ce qui se passe",
            reactionsHint: "Il sort pour réagir à la musique, aux minuteurs, aux téléchargements, aux captures d’écran, au micro, à Garder éveillé et plus encore.",
            hidesWhenIdle: "Se cacher en cas d’inactivité",
            hidesWhenIdleHint: "Après une demi-minute sans activité, il saute dans l’île, qui reprend sa taille habituelle. Il en ressort toujours pour ses visites et ses réactions.",
            sayHi: "Dire bonjour", sayHiHint: "Joue une visite dans le Dynamic Island maintenant.",
            momentsTitle: "Voyez comment il réagit",
            visitMoment: "Une visite", timerStarted: "Minuteur lancé", downloadFailed: "Échec du téléchargement", unlocked: "Mac déverrouillé",
            petTip: "Laissez le pointeur posé sur lui pour le caresser. Seul, il s’assoupit jusqu’à votre retour.",
            livesInIsland: "Le compagnon vit dans le Dynamic Island.",
            keywords: "mascotte animal copain personnage")
        case .it: return NotchMascotStrings(
            title: "Compagno",
            hint: "Un piccolo amico che vive nel Dynamic Island. Riposa lì quando non viene mostrato nient’altro ed esce sopra musica e attività per salutare e reagire a ciò che succede.",
            visits: "Comparire ogni tanto",
            visitsHint: "Ogni pochi minuti attraversa l’isola con una breve animazione.",
            style: "Stile", minimal: "Minimale", robot: "Robot",
            shape: "Forma", ball: "Pallina", egg: "Uovo", squircle: "Quadrato arrotondato", pill: "Pillola",
            color: "Colore", pearl: "Perla", mint: "Menta", peach: "Pesca", lilac: "Lilla", lemon: "Limone", rose: "Rosa",
            commandBar: "Barra dei comandi nell’isola",
            commandBarHint: "Con la scorciatoia, la Barra dei comandi esce dall’isola con il compagno come volto. Reagisce mentre cerchi.",
            opensAs: "Si apre come", droplet: "Goccia", openIsland: "Isola aperta",
            preview: "Anteprima del compagno", previewHint: "Fai clic per vederlo reagire.",
            side: "Lato della fotocamera", left: "Sinistra", right: "Destra",
            frequency: "Frequenza", rare: "Rara", normal: "Normale", frequent: "Frequente",
            sky: "Cielo",
            hubDescription: "Un piccolo amico nel Dynamic Island che ogni tanto saluta e reagisce a ciò che succede sul tuo Mac.",
            appearance: "Aspetto", behavior: "Comportamento",
            reactions: "Reagire a ciò che succede",
            reactionsHint: "Esce per reagire a musica, timer, download, istantanee dello schermo, al microfono, a Mantieni attivo e altro.",
            hidesWhenIdle: "Nascondersi quando inattivo",
            hidesWhenIdleHint: "Dopo mezzo minuto senza che succeda nulla, salta dentro l’isola, che torna alla sua dimensione normale. Esce ancora per le visite e le reazioni.",
            sayHi: "Saluta", sayHiHint: "Mostra subito una visita nel Dynamic Island.",
            momentsTitle: "Guarda come reagisce",
            visitMoment: "Una visita", timerStarted: "Timer avviato", downloadFailed: "Download non riuscito", unlocked: "Mac sbloccato",
            petTip: "Lascia il puntatore fermo su di lui per accarezzarlo. Da solo, si appisola finché non torni.",
            livesInIsland: "Il compagno vive nel Dynamic Island.",
            keywords: "mascotte animaletto amico personaggio")
        case .ru: return NotchMascotStrings(
            title: "Компаньон",
            hint: "Маленький друг, который живёт в Dynamic Island. Он отдыхает там, когда больше ничего не показано, и выходит поверх музыки и активностей, чтобы поздороваться и отреагировать на происходящее.",
            visits: "Появляться время от времени",
            visitsHint: "Раз в несколько минут он пробегает по острову с короткой анимацией.",
            style: "Стиль", minimal: "Минимализм", robot: "Робот",
            shape: "Форма", ball: "Шарик", egg: "Яйцо", squircle: "Скруглённый квадрат", pill: "Пилюля",
            color: "Цвет", pearl: "Жемчуг", mint: "Мята", peach: "Персик", lilac: "Сирень", lemon: "Лимон", rose: "Роза",
            commandBar: "Командная панель на острове",
            commandBarHint: "По сочетанию клавиш Командная панель выходит из острова, а компаньон становится её лицом. Он реагирует, пока вы ищете.",
            opensAs: "Открывается как", droplet: "Капля", openIsland: "Открытый остров",
            preview: "Предпросмотр компаньона", previewHint: "Нажмите, чтобы увидеть его реакцию.",
            side: "Сторона камеры", left: "Слева", right: "Справа",
            frequency: "Как часто", rare: "Редко", normal: "Иногда", frequent: "Часто",
            sky: "Небо",
            hubDescription: "Маленький друг в Dynamic Island, который иногда здоровается и реагирует на то, что происходит на вашем Mac.",
            appearance: "Внешний вид", behavior: "Поведение",
            reactions: "Реагировать на происходящее",
            reactionsHint: "Он выходит, чтобы отреагировать на музыку, таймеры, загрузки, снимки экрана, микрофон, режим «Не давать Mac уснуть» и не только.",
            hidesWhenIdle: "Прятаться при бездействии",
            hidesWhenIdleHint: "Если полминуты ничего не происходит, он прыгает внутрь острова, и остров возвращается к обычному размеру. Для визитов и реакций он по-прежнему выходит.",
            sayHi: "Поздороваться", sayHiHint: "Сразу показывает визит в Dynamic Island.",
            momentsTitle: "Посмотрите, как он реагирует",
            visitMoment: "Визит", timerStarted: "Таймер запущен", downloadFailed: "Загрузка не удалась", unlocked: "Mac разблокирован",
            petTip: "Задержите на нём указатель, чтобы погладить. Оставшись один, он дремлет, пока вы не вернётесь.",
            livesInIsland: "Компаньон живёт в Dynamic Island.",
            keywords: "маскот питомец приятель персонаж")
        case .tr: return NotchMascotStrings(
            title: "Arkadaş",
            hint: "Dynamic Island’da yaşayan küçük bir dost. Başka bir şey görünmediğinde orada dinlenir, merhaba demek ve olanlara tepki vermek için müziğin ve etkinliklerin üzerine çıkar.",
            visits: "Arada bir görün",
            visitsHint: "Birkaç dakikada bir kısa bir animasyonla adadan geçer.",
            style: "Stil", minimal: "Sade", robot: "Robot",
            shape: "Şekil", ball: "Top", egg: "Yumurta", squircle: "Yuvarlak kare", pill: "Hap",
            color: "Renk", pearl: "İnci", mint: "Nane", peach: "Şeftali", lilac: "Leylak", lemon: "Limon", rose: "Gül",
            commandBar: "Komut çubuğu adada",
            commandBarHint: "Kısayolla Komut çubuğu adadan çıkar ve arkadaş onun yüzü olur. Siz ararken tepki verir.",
            opensAs: "Açılış biçimi", droplet: "Damla", openIsland: "Açık ada",
            preview: "Arkadaş önizlemesi", previewHint: "Tepkisini görmek için tıklayın.",
            side: "Kameranın tarafı", left: "Sol", right: "Sağ",
            frequency: "Sıklık", rare: "Seyrek", normal: "Normal", frequent: "Sık",
            sky: "Gök",
            hubDescription: "Dynamic Island’da arada bir merhaba diyen ve Mac’inizde olanlara tepki veren küçük bir dost.",
            appearance: "Görünüm", behavior: "Davranış",
            reactions: "Olanlara tepki ver",
            reactionsHint: "Müziğe, zamanlayıcılara, indirmelere, ekran görüntülerine, mikrofona, Uyanık tut’a ve daha fazlasına tepki vermek için çıkar.",
            hidesWhenIdle: "Boştayken saklan",
            hidesWhenIdleHint: "Yarım dakika boyunca hiçbir şey olmazsa adanın içine atlar ve ada normal boyutuna döner. Ziyaretler ve tepkiler için yine dışarı çıkar.",
            sayHi: "Merhaba de", sayHiHint: "Dynamic Island’da hemen bir ziyaret oynatır.",
            momentsTitle: "Nasıl tepki verdiğini görün",
            visitMoment: "Bir ziyaret", timerStarted: "Zamanlayıcı başladı", downloadFailed: "İndirme başarısız", unlocked: "Mac’in kilidi açıldı",
            petTip: "Sevmek için imleci bir an üzerinde tutun. Yalnız kalınca siz dönene kadar uyuklar.",
            livesInIsland: "Arkadaş Dynamic Island’da yaşar.",
            keywords: "maskot evcil dost karakter")
        case .ja: return NotchMascotStrings(
            title: "コンパニオン",
            hint: "Dynamic Island に住む小さな友だちです。ほかに何も表示されていないときはそこで休み、音楽やアクティビティの上にも出てきて、あいさつしたり出来事に反応したりします。",
            visits: "ときどき現れる",
            visitsHint: "数分ごとに、短いアニメーションでアイランドを通り抜けます。",
            style: "スタイル", minimal: "ミニマル", robot: "ロボット",
            shape: "形", ball: "まる", egg: "たまご", squircle: "角丸の四角", pill: "カプセル",
            color: "色", pearl: "パール", mint: "ミント", peach: "ピーチ", lilac: "ライラック", lemon: "レモン", rose: "ローズ",
            commandBar: "アイランドのコマンドバー",
            commandBarHint: "ショートカットでコマンドバーがアイランドから現れ、コンパニオンがその顔になります。検索中は反応します。",
            opensAs: "開き方", droplet: "しずく", openIsland: "開いたアイランド",
            preview: "コンパニオンのプレビュー", previewHint: "クリックすると反応が見られます。",
            side: "カメラのどちら側", left: "左", right: "右",
            frequency: "頻度", rare: "少なめ", normal: "ふつう", frequent: "多め",
            sky: "スカイ",
            hubDescription: "Dynamic Island に住む小さな友だち。ときどきあいさつし、Mac で起きたことに反応します。",
            appearance: "外観", behavior: "動作",
            reactions: "出来事に反応する",
            reactionsHint: "音楽、タイマー、ダウンロード、スクリーンショット、マイク、スリープ防止などに反応して出てきます。",
            hidesWhenIdle: "何もないときは隠れる",
            hidesWhenIdleHint: "30秒間何も起きないと、アイランドの中へ飛び込み、アイランドは元の大きさに戻ります。訪問や反応のときは引き続き出てきます。",
            sayHi: "あいさつ", sayHiHint: "Dynamic Island で今すぐ訪問を再生します。",
            momentsTitle: "反応を見てみる",
            visitMoment: "訪問", timerStarted: "タイマー開始", downloadFailed: "ダウンロード失敗", unlocked: "Mac のロック解除",
            petTip: "ポインタをしばらく乗せるとなでられます。ひとりにすると、戻ってくるまでうたた寝します。",
            livesInIsland: "コンパニオンは Dynamic Island に住んでいます。",
            keywords: "マスコット ペット 相棒 キャラクター")
        case .ko: return NotchMascotStrings(
            title: "컴패니언",
            hint: "Dynamic Island에 사는 작은 친구입니다. 다른 것이 표시되지 않을 때는 그곳에서 쉬고, 음악과 활동 위로도 나와 인사하고 일어난 일에 반응합니다.",
            visits: "가끔 나타나기",
            visitsHint: "몇 분마다 짧은 애니메이션으로 아일랜드를 지나갑니다.",
            style: "스타일", minimal: "미니멀", robot: "로봇",
            shape: "모양", ball: "공", egg: "달걀", squircle: "둥근 사각형", pill: "알약",
            color: "색상", pearl: "펄", mint: "민트", peach: "피치", lilac: "라일락", lemon: "레몬", rose: "로즈",
            commandBar: "아일랜드의 명령 막대",
            commandBarHint: "단축키를 누르면 명령 막대가 아일랜드에서 나오고 컴패니언이 그 얼굴이 됩니다. 검색하는 동안 반응합니다.",
            opensAs: "열리는 방식", droplet: "물방울", openIsland: "열린 아일랜드",
            preview: "컴패니언 미리 보기", previewHint: "클릭하면 반응을 볼 수 있습니다.",
            side: "카메라 옆 위치", left: "왼쪽", right: "오른쪽",
            frequency: "빈도", rare: "가끔", normal: "보통", frequent: "자주",
            sky: "스카이",
            hubDescription: "가끔 인사하고 Mac에서 일어나는 일에 반응하는 Dynamic Island의 작은 친구입니다.",
            appearance: "외관", behavior: "동작",
            reactions: "일어나는 일에 반응",
            reactionsHint: "음악, 타이머, 다운로드, 스크린샷, 마이크, 절전 방지 등에 반응하러 나옵니다.",
            hidesWhenIdle: "유휴 시 숨기기",
            hidesWhenIdleHint: "30초 동안 아무 일도 없으면 아일랜드 안으로 뛰어들고, 아일랜드는 원래 크기로 돌아갑니다. 방문하거나 반응할 때는 계속 나옵니다.",
            sayHi: "인사하기", sayHiHint: "Dynamic Island에서 지금 방문을 재생합니다.",
            momentsTitle: "반응 살펴보기",
            visitMoment: "방문", timerStarted: "타이머 시작", downloadFailed: "다운로드 실패", unlocked: "Mac 잠금 해제",
            petTip: "포인터를 잠시 올려 두면 쓰다듬을 수 있습니다. 혼자 두면 돌아올 때까지 꾸벅꾸벅 좁니다.",
            livesInIsland: "컴패니언은 Dynamic Island에 삽니다.",
            keywords: "마스코트 펫 친구 캐릭터")
        case .zhHans: return NotchMascotStrings(
            title: "小伙伴",
            hint: "住在Dynamic Island里的小伙伴。没有其他内容显示时，它就在那里休息，也会出现在音乐和活动上方打招呼，并对发生的事做出反应。",
            visits: "偶尔出现",
            visitsHint: "每隔几分钟，它会以简短的动画从岛上经过。",
            style: "风格", minimal: "极简", robot: "机器人",
            shape: "形状", ball: "圆球", egg: "鸡蛋", squircle: "圆角方形", pill: "药丸",
            color: "颜色", pearl: "珍珠", mint: "薄荷", peach: "蜜桃", lilac: "丁香", lemon: "柠檬", rose: "玫瑰",
            commandBar: "在岛中使用命令栏",
            commandBarHint: "按下快捷键，命令栏会从岛中出现，小伙伴就是它的脸。你搜索时它会做出反应。",
            opensAs: "打开方式", droplet: "水滴", openIsland: "展开的岛",
            preview: "小伙伴预览", previewHint: "点击查看它的反应。",
            side: "在摄像头哪一侧", left: "左侧", right: "右侧",
            frequency: "频率", rare: "偶尔", normal: "适中", frequent: "经常",
            sky: "天空",
            hubDescription: "Dynamic Island里的小伙伴，会不时打个招呼，并对 Mac 上发生的事做出反应。",
            appearance: "外观", behavior: "行为",
            reactions: "对发生的事做出反应",
            reactionsHint: "它会出来对音乐、计时器、下载、截屏、麦克风、保持唤醒等做出反应。",
            hidesWhenIdle: "空闲时隐藏",
            hidesWhenIdleHint: "半分钟内没有任何动静时，它会跳进岛里，岛也恢复原来的大小。来访和做出反应时，它仍会出来。",
            sayHi: "打个招呼", sayHiHint: "立即在Dynamic Island中播放一次来访。",
            momentsTitle: "看看它的反应",
            visitMoment: "来访", timerStarted: "计时器已开始", downloadFailed: "下载失败", unlocked: "Mac 已解锁",
            petTip: "把指针在它身上停留片刻就能摸摸它。独自待着时，它会打盹，直到你回来。",
            livesInIsland: "小伙伴住在Dynamic Island里。",
            keywords: "吉祥物 宠物 伙伴 角色")
        case .zhTW: return NotchMascotStrings(
            title: "小夥伴",
            hint: "住在Dynamic Island裡的小夥伴。沒有其他內容顯示時，它就在那裡休息，也會出現在音樂和活動上方打招呼，並對發生的事做出反應。",
            visits: "偶爾出現",
            visitsHint: "每隔幾分鐘，它會以簡短的動畫從動態島經過。",
            style: "風格", minimal: "極簡", robot: "機器人",
            shape: "形狀", ball: "圓球", egg: "雞蛋", squircle: "圓角方形", pill: "藥丸",
            color: "顏色", pearl: "珍珠", mint: "薄荷", peach: "蜜桃", lilac: "丁香", lemon: "檸檬", rose: "玫瑰",
            commandBar: "在動態島中使用指令列",
            commandBarHint: "按下快速鍵，指令列會從動態島出現，小夥伴就是它的臉。你搜尋時它會做出反應。",
            opensAs: "開啟方式", droplet: "水滴", openIsland: "展開的動態島",
            preview: "小夥伴預覽", previewHint: "按一下即可查看它的反應。",
            side: "在相機哪一側", left: "左側", right: "右側",
            frequency: "頻率", rare: "偶爾", normal: "適中", frequent: "經常",
            sky: "天空",
            hubDescription: "Dynamic Island裡的小夥伴，會不時打招呼，並對 Mac 上發生的事做出反應。",
            appearance: "外觀", behavior: "行為",
            reactions: "對發生的事做出反應",
            reactionsHint: "它會出來對音樂、計時器、下載、截圖、麥克風、保持喚醒等做出反應。",
            hidesWhenIdle: "閒置時隱藏",
            hidesWhenIdleHint: "半分鐘內沒有任何動靜時，它會跳進動態島裡，動態島也恢復原本的大小。來訪和做出反應時，它仍會出來。",
            sayHi: "打個招呼", sayHiHint: "立即在Dynamic Island中播放一次來訪。",
            momentsTitle: "看看它的反應",
            visitMoment: "來訪", timerStarted: "計時器已開始", downloadFailed: "下載失敗", unlocked: "Mac 已解鎖",
            petTip: "把指標在它身上停留片刻就能摸摸它。獨自待著時，它會打盹，直到你回來。",
            livesInIsland: "小夥伴住在Dynamic Island裡。",
            keywords: "吉祥物 寵物 夥伴 角色")
        case .zhHK: return NotchMascotStrings(
            title: "小夥伴",
            hint: "住在Dynamic Island裡的小夥伴。沒有其他內容顯示時，它就在那裡休息，也會出現在音樂和活動上方打招呼，並對發生的事作出反應。",
            visits: "間中出現",
            visitsHint: "每隔幾分鐘，它會以簡短的動畫從動態島經過。",
            style: "風格", minimal: "極簡", robot: "機械人",
            shape: "形狀", ball: "圓球", egg: "雞蛋", squircle: "圓角方形", pill: "藥丸",
            color: "顏色", pearl: "珍珠", mint: "薄荷", peach: "蜜桃", lilac: "丁香", lemon: "檸檬", rose: "玫瑰",
            commandBar: "在動態島中使用指令列",
            commandBarHint: "按下快捷鍵，指令列會從動態島出現，小夥伴就是它的臉。你搜尋時它會作出反應。",
            opensAs: "開啟方式", droplet: "水滴", openIsland: "展開的動態島",
            preview: "小夥伴預覽", previewHint: "按一下即可查看它的反應。",
            side: "在相機哪一側", left: "左側", right: "右側",
            frequency: "頻率", rare: "偶爾", normal: "適中", frequent: "經常",
            sky: "天空",
            hubDescription: "Dynamic Island裡的小夥伴，會不時打招呼，並對 Mac 上發生的事作出反應。",
            appearance: "外觀", behavior: "行為",
            reactions: "對發生的事作出反應",
            reactionsHint: "它會出來對音樂、計時器、下載、截圖、麥克風、保持喚醒等作出反應。",
            hidesWhenIdle: "閒置時隱藏",
            hidesWhenIdleHint: "半分鐘內沒有任何動靜時，它會跳進動態島裡，動態島也回復原本的大小。來訪和作出反應時，它仍會出來。",
            sayHi: "打個招呼", sayHiHint: "立即在Dynamic Island中播放一次來訪。",
            momentsTitle: "看看它的反應",
            visitMoment: "來訪", timerStarted: "計時器已開始", downloadFailed: "下載失敗", unlocked: "Mac 已解鎖",
            petTip: "把指標在它身上停留片刻就能摸摸它。獨自待著時，它會打盹，直到你回來。",
            livesInIsland: "小夥伴住在Dynamic Island裡。",
            keywords: "吉祥物 寵物 夥伴 角色")
        case .uk: return NotchMascotStrings(
            title: "Компаньйон",
            hint: "Маленький друг, який живе в Dynamic Island. Він відпочиває там, коли більше нічого не показано, і виходить поверх музики й активностей, щоб привітатися та відреагувати на те, що відбувається.",
            visits: "З’являтися час від часу",
            visitsHint: "Раз на кілька хвилин він пробігає острівцем із короткою анімацією.",
            style: "Стиль", minimal: "Мінімалізм", robot: "Робот",
            shape: "Форма", ball: "Кулька", egg: "Яйце", squircle: "Заокруглений квадрат", pill: "Пігулка",
            color: "Колір", pearl: "Перлина", mint: "М’ята", peach: "Персик", lilac: "Бузок", lemon: "Лимон", rose: "Троянда",
            commandBar: "Панель команд в острівці",
            commandBarHint: "За поєднанням клавіш Панель команд виходить з острівця, а компаньйон стає її обличчям. Він реагує, поки ви шукаєте.",
            opensAs: "Відкривається як", droplet: "Крапля", openIsland: "Відкритий острівець",
            preview: "Попередній перегляд компаньйона", previewHint: "Натисніть, щоб побачити його реакцію.",
            side: "Сторона камери", left: "Ліворуч", right: "Праворуч",
            frequency: "Як часто", rare: "Рідко", normal: "Іноді", frequent: "Часто",
            sky: "Небо",
            hubDescription: "Маленький друг у Dynamic Island, який час від часу вітається й реагує на те, що відбувається на вашому Mac.",
            appearance: "Вигляд", behavior: "Поведінка",
            reactions: "Реагувати на те, що відбувається",
            reactionsHint: "Він виходить, щоб відреагувати на музику, таймери, завантаження, знімки екрана, мікрофон, режим «Не давати Mac заснути» та інше.",
            hidesWhenIdle: "Ховатися під час бездіяльності",
            hidesWhenIdleHint: "Якщо пів хвилини нічого не відбувається, він стрибає всередину острівця, і острівець повертається до звичайного розміру. Для візитів і реакцій він і далі виходить.",
            sayHi: "Привітатися", sayHiHint: "Одразу показує візит у Dynamic Island.",
            momentsTitle: "Подивіться, як він реагує",
            visitMoment: "Візит", timerStarted: "Таймер запущено", downloadFailed: "Не вдалося завантажити", unlocked: "Mac розблоковано",
            petTip: "Затримайте на ньому вказівник, щоб погладити. Залишившись сам, він дрімає, доки ви не повернетеся.",
            livesInIsland: "Компаньйон живе в Dynamic Island.",
            keywords: "маскот улюбленець приятель персонаж")
        }
    }
}
