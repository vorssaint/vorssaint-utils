// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for Fast Reader, the RSVP-style panel that flashes the
/// current text selection one chunk at a time so the eyes never have to move.
struct FastReaderFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let serviceMenuItem: String
    let openButton: String
    let speedTitle: String
    let speedCaption: String
    let chunkTitle: String
    let chunkCaption: String
    let focusPointTitle: String
    let focusPointCaption: String
    let punctuationPauseTitle: String
    let punctuationPauseCaption: String
    let longWordScalingTitle: String
    let longWordScalingCaption: String
    let surfaceTitle: String
    let surfaceFloating: String
    let surfaceNotch: String
    let shortcutTitle: String
    let playAction: String
    let pauseAction: String
    let restartAction: String
    let closeHint: String
    let finishedCaption: String
    let progressFormat: String
    let noSelection: String
    let emptySelection: String
    let truncatedFormat: String
    let accessibilityNeeded: String
}

extension FeatureStrings {
    static func fastReader(_ language: AppLanguage) -> FastReaderFeatureStrings {
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

extension FastReaderFeatureStrings {
    static let enUS = FastReaderFeatureStrings(
        pageTitle: "Fast Reader",
        hubDescription: "Read selected text one flash at a time",
        panelCaption: "Read a selection without moving your eyes",
        serviceMenuItem: "Read with Fast Reader",
        openButton: "Read the selection",
        speedTitle: "Speed",
        speedCaption: "Words a minute. Start lower than feels natural and raise it as you go.",
        chunkTitle: "Words at a time",
        chunkCaption: "More words a flash reads faster, and asks more of you.",
        focusPointTitle: "Mark the focus letter",
        focusPointCaption: "Colors one letter of each word and lines it up, so your eyes stay where they are.",
        punctuationPauseTitle: "Pause at punctuation",
        punctuationPauseCaption: "Holds a little longer on commas and rather longer at the end of a sentence.",
        longWordScalingTitle: "Slow down on long words",
        longWordScalingCaption: "Gives a long word more time than a short one.",
        surfaceTitle: "Show it",
        surfaceFloating: "In a floating window",
        surfaceNotch: "Around the camera",
        shortcutTitle: "Shortcut",
        playAction: "Play",
        pauseAction: "Pause",
        restartAction: "Start over",
        closeHint: "Esc closes",
        finishedCaption: "Finished",
        progressFormat: "%1$d of %2$d",
        noSelection: "Select some text and try again",
        emptySelection: "There were no words to read in that selection",
        truncatedFormat: "Only the first %d characters were taken",
        accessibilityNeeded: "The shortcut needs Accessibility to see what you have selected. The Services menu works without it."
    )

    static let ptBR = FastReaderFeatureStrings(
        pageTitle: "Leitor Rápido",
        hubDescription: "Lê o texto selecionado em lampejos, um bloco por vez",
        panelCaption: "Leia uma seleção sem mover os olhos",
        serviceMenuItem: "Ler com o Leitor Rápido",
        openButton: "Ler a seleção",
        speedTitle: "Velocidade",
        speedCaption: "Palavras por minuto. Comece mais devagar do que parece natural e aumente aos poucos.",
        chunkTitle: "Palavras por vez",
        chunkCaption: "Quanto mais palavras por lampejo, mais rápida a leitura, e mais ela exige de você.",
        focusPointTitle: "Marcar a letra de foco",
        focusPointCaption: "Colore uma letra de cada palavra e a alinha, para que seus olhos fiquem parados.",
        punctuationPauseTitle: "Pausar na pontuação",
        punctuationPauseCaption: "Detém-se um pouco mais nas vírgulas e bem mais no fim de uma frase.",
        longWordScalingTitle: "Ir mais devagar em palavras longas",
        longWordScalingCaption: "Dá mais tempo a uma palavra longa do que a uma curta.",
        surfaceTitle: "Mostrar em",
        surfaceFloating: "Uma janela flutuante",
        surfaceNotch: "Ao redor da câmera",
        shortcutTitle: "Atalho",
        playAction: "Reproduzir",
        pauseAction: "Pausar",
        restartAction: "Recomeçar",
        closeHint: "Esc fecha",
        finishedCaption: "Concluído",
        progressFormat: "%1$d de %2$d",
        noSelection: "Selecione algum texto e tente novamente",
        emptySelection: "Não havia palavras para ler nessa seleção",
        truncatedFormat: "Foram usados apenas os primeiros %d caracteres",
        accessibilityNeeded: "O atalho precisa de Acessibilidade para ver o que você selecionou. O menu Serviços funciona sem ela."
    )

    static let tr = FastReaderFeatureStrings(
        pageTitle: "Hızlı Okuyucu",
        hubDescription: "Seçili metni tek seferde bir öbek göstererek okur",
        panelCaption: "Gözlerinizi oynatmadan bir seçimi okuyun",
        serviceMenuItem: "Hızlı Okuyucu ile oku",
        openButton: "Seçimi oku",
        speedTitle: "Hız",
        speedCaption: "Dakikadaki kelime sayısı. Doğal gelenden daha düşük başlayıp zamanla artırın.",
        chunkTitle: "Bir seferde kelime sayısı",
        chunkCaption: "Bir öbekte daha çok kelime daha hızlı okutur, ama sizden daha fazlasını ister.",
        focusPointTitle: "Odak harfini işaretle",
        focusPointCaption: "Her kelimenin bir harfini renklendirip hizalar, böylece gözünüz yerinde kalır.",
        punctuationPauseTitle: "Noktalama işaretlerinde duraklat",
        punctuationPauseCaption: "Virgüllerde biraz, cümle sonlarında daha uzun bekler.",
        longWordScalingTitle: "Uzun kelimelerde yavaşla",
        longWordScalingCaption: "Uzun bir kelimeye kısadan daha fazla süre tanır.",
        surfaceTitle: "Gösterim yeri",
        surfaceFloating: "Yüzen bir pencerede",
        surfaceNotch: "Kameranın çevresinde",
        shortcutTitle: "Kısayol",
        playAction: "Oynat",
        pauseAction: "Duraklat",
        restartAction: "Baştan başlat",
        closeHint: "Esc kapatır",
        finishedCaption: "Tamamlandı",
        progressFormat: "%1$d / %2$d",
        noSelection: "Bir metin seçip yeniden deneyin",
        emptySelection: "Bu seçimde okunacak kelime yoktu",
        truncatedFormat: "Yalnızca ilk %d karakter alındı",
        accessibilityNeeded: "Kısayolun seçtiğinizi görebilmesi için Erişilebilirlik izni gerekir. Servisler menüsü izin olmadan da çalışır."
    )

    static let ru = FastReaderFeatureStrings(
        pageTitle: "Быстрое чтение",
        hubDescription: "Показывает выделенный текст вспышками, блок за блоком",
        panelCaption: "Читайте выделенный текст, не двигая глазами",
        serviceMenuItem: "Читать в режиме быстрого чтения",
        openButton: "Прочитать выделенное",
        speedTitle: "Скорость",
        speedCaption: "Слов в минуту. Начните медленнее, чем кажется естественным, и постепенно увеличивайте.",
        chunkTitle: "Слов за раз",
        chunkCaption: "Больше слов во вспышке ускоряет чтение, но и усложняет восприятие.",
        focusPointTitle: "Выделять опорную букву",
        focusPointCaption: "Подсвечивает одну букву каждого слова и выравнивает её, чтобы взгляд оставался на месте.",
        punctuationPauseTitle: "Пауза на знаках препинания",
        punctuationPauseCaption: "Задерживается чуть дольше на запятой и заметно дольше в конце предложения.",
        longWordScalingTitle: "Замедляться на длинных словах",
        longWordScalingCaption: "Даёт длинному слову больше времени, чем короткому.",
        surfaceTitle: "Показывать",
        surfaceFloating: "В плавающем окне",
        surfaceNotch: "Вокруг камеры",
        shortcutTitle: "Сочетание клавиш",
        playAction: "Воспроизвести",
        pauseAction: "Пауза",
        restartAction: "Начать заново",
        closeHint: "Esc закрывает",
        finishedCaption: "Готово",
        progressFormat: "%1$d из %2$d",
        noSelection: "Выделите текст и попробуйте снова",
        emptySelection: "В этом выделении не нашлось слов для чтения",
        truncatedFormat: "Взяты только первые %d символов",
        accessibilityNeeded: "Для сочетания клавиш нужен доступ «Универсальные возможности», чтобы видеть выделенный текст. Меню «Службы» работает и без него."
    )

    static let es = FastReaderFeatureStrings(
        pageTitle: "Lector Rápido",
        hubDescription: "Muestra el texto seleccionado en destellos, un bloque a la vez",
        panelCaption: "Lee una selección sin mover los ojos",
        serviceMenuItem: "Leer con el Lector Rápido",
        openButton: "Leer la selección",
        speedTitle: "Velocidad",
        speedCaption: "Palabras por minuto. Empieza más despacio de lo que parece natural y ve subiendo.",
        chunkTitle: "Palabras a la vez",
        chunkCaption: "Cuantas más palabras por destello, más rápida es la lectura y más te exige.",
        focusPointTitle: "Marcar la letra de enfoque",
        focusPointCaption: "Colorea una letra de cada palabra y la alinea, para que tus ojos no se muevan.",
        punctuationPauseTitle: "Pausar en la puntuación",
        punctuationPauseCaption: "Se detiene un poco más en las comas y bastante más al final de una frase.",
        longWordScalingTitle: "Ir más despacio en palabras largas",
        longWordScalingCaption: "Da más tiempo a una palabra larga que a una corta.",
        surfaceTitle: "Mostrarlo",
        surfaceFloating: "En una ventana flotante",
        surfaceNotch: "Alrededor de la cámara",
        shortcutTitle: "Atajo",
        playAction: "Reproducir",
        pauseAction: "Pausar",
        restartAction: "Empezar de nuevo",
        closeHint: "Esc cierra",
        finishedCaption: "Terminado",
        progressFormat: "%1$d de %2$d",
        noSelection: "Selecciona algún texto e inténtalo de nuevo",
        emptySelection: "No había palabras que leer en esa selección",
        truncatedFormat: "Solo se tomaron los primeros %d caracteres",
        accessibilityNeeded: "El atajo necesita Accesibilidad para ver lo que has seleccionado. El menú Servicios funciona sin ella."
    )

    static let sk = FastReaderFeatureStrings(
        pageTitle: "Rýchle čítanie",
        hubDescription: "Číta označený text záblesk po záblesku",
        panelCaption: "Čítajte označený text bez pohybu očí",
        serviceMenuItem: "Čítať pomocou Rýchleho čítania",
        openButton: "Prečítať označený text",
        speedTitle: "Rýchlosť",
        speedCaption: "Slová za minútu. Začnite pomalšie, ako sa zdá prirodzené, a postupne pridávajte.",
        chunkTitle: "Slov naraz",
        chunkCaption: "Viac slov v jednom záblesku číta rýchlejšie, ale vyžaduje viac pozornosti.",
        focusPointTitle: "Zvýrazniť oporné písmeno",
        focusPointCaption: "Zafarbí jedno písmeno každého slova a zarovná ho, aby oči zostali na mieste.",
        punctuationPauseTitle: "Pozastaviť pri interpunkcii",
        punctuationPauseCaption: "Pri čiarke sa zdrží o niečo dlhšie a na konci vety ešte dlhšie.",
        longWordScalingTitle: "Spomaliť pri dlhých slovách",
        longWordScalingCaption: "Dlhému slovu dá viac času než krátkemu.",
        surfaceTitle: "Zobraziť",
        surfaceFloating: "V plávajúcom okne",
        surfaceNotch: "Okolo kamery",
        shortcutTitle: "Klávesová skratka",
        playAction: "Prehrať",
        pauseAction: "Pozastaviť",
        restartAction: "Začať odznova",
        closeHint: "Esc zatvorí",
        finishedCaption: "Hotovo",
        progressFormat: "%1$d z %2$d",
        noSelection: "Označte nejaký text a skúste to znova",
        emptySelection: "V označenom texte neboli žiadne slová na čítanie",
        truncatedFormat: "Použilo sa iba prvých %d znakov",
        accessibilityNeeded: "Skratka potrebuje Prístupnosť, aby videla, čo ste označili. Ponuka Služby funguje aj bez nej."
    )

    static let de = FastReaderFeatureStrings(
        pageTitle: "Schnelllesen",
        hubDescription: "Zeigt den markierten Text blitzweise an, ein Block nach dem anderen",
        panelCaption: "Lies eine Auswahl, ohne die Augen zu bewegen",
        serviceMenuItem: "Mit Schnelllesen lesen",
        openButton: "Auswahl lesen",
        speedTitle: "Geschwindigkeit",
        speedCaption: "Wörter pro Minute. Fang langsamer an, als sich natürlich anfühlt, und steigere dich mit der Zeit.",
        chunkTitle: "Wörter auf einmal",
        chunkCaption: "Mehr Wörter pro Blitz lesen sich schneller, verlangen dir aber auch mehr ab.",
        focusPointTitle: "Fokusbuchstaben markieren",
        focusPointCaption: "Färbt einen Buchstaben jedes Worts ein und richtet ihn aus, damit deine Augen an derselben Stelle bleiben.",
        punctuationPauseTitle: "Bei Satzzeichen pausieren",
        punctuationPauseCaption: "Hält bei Kommas etwas länger und am Satzende deutlich länger.",
        longWordScalingTitle: "Bei langen Wörtern langsamer werden",
        longWordScalingCaption: "Gibt einem langen Wort mehr Zeit als einem kurzen.",
        surfaceTitle: "Anzeigen",
        surfaceFloating: "In einem schwebenden Fenster",
        surfaceNotch: "Rund um die Kamera",
        shortcutTitle: "Tastenkombination",
        playAction: "Abspielen",
        pauseAction: "Pause",
        restartAction: "Von vorn beginnen",
        closeHint: "Esc schließt",
        finishedCaption: "Fertig",
        progressFormat: "%1$d von %2$d",
        noSelection: "Markiere Text und versuche es erneut",
        emptySelection: "In dieser Auswahl gab es keine Wörter zu lesen",
        truncatedFormat: "Es wurden nur die ersten %d Zeichen übernommen",
        accessibilityNeeded: "Die Tastenkombination braucht die Bedienungshilfen, um deine Auswahl zu sehen. Das Dienste-Menü funktioniert auch ohne sie."
    )

    static let fr = FastReaderFeatureStrings(
        pageTitle: "Lecture rapide",
        hubDescription: "Affiche le texte sélectionné par éclairs, un bloc à la fois",
        panelCaption: "Lisez une sélection sans bouger les yeux",
        serviceMenuItem: "Lire avec Lecture rapide",
        openButton: "Lire la sélection",
        speedTitle: "Vitesse",
        speedCaption: "Mots par minute. Commencez plus lentement que ce qui semble naturel, puis augmentez peu à peu.",
        chunkTitle: "Mots à la fois",
        chunkCaption: "Plus de mots par éclair lit plus vite, et demande plus d’attention.",
        focusPointTitle: "Repérer la lettre de fixation",
        focusPointCaption: "Colore une lettre de chaque mot et l’aligne, pour que vos yeux restent immobiles.",
        punctuationPauseTitle: "Marquer une pause à la ponctuation",
        punctuationPauseCaption: "S’attarde un peu plus sur les virgules et bien plus à la fin d’une phrase.",
        longWordScalingTitle: "Ralentir sur les mots longs",
        longWordScalingCaption: "Laisse plus de temps à un mot long qu’à un mot court.",
        surfaceTitle: "Afficher dans",
        surfaceFloating: "Une fenêtre flottante",
        surfaceNotch: "Autour de la caméra",
        shortcutTitle: "Raccourci",
        playAction: "Lire",
        pauseAction: "Pause",
        restartAction: "Recommencer",
        closeHint: "Échap ferme",
        finishedCaption: "Terminé",
        progressFormat: "%1$d sur %2$d",
        noSelection: "Sélectionnez du texte et réessayez",
        emptySelection: "Il n’y avait aucun mot à lire dans cette sélection",
        truncatedFormat: "Seuls les %d premiers caractères ont été pris",
        accessibilityNeeded: "Le raccourci a besoin de l’accès Accessibilité pour voir ce que vous avez sélectionné. Le menu Services fonctionne sans lui."
    )

    static let it = FastReaderFeatureStrings(
        pageTitle: "Lettura Rapida",
        hubDescription: "Mostra il testo selezionato a lampi, un blocco alla volta",
        panelCaption: "Leggi una selezione senza muovere gli occhi",
        serviceMenuItem: "Leggi con Lettura Rapida",
        openButton: "Leggi la selezione",
        speedTitle: "Velocità",
        speedCaption: "Parole al minuto. Inizia più piano di quanto sembri naturale e aumenta col tempo.",
        chunkTitle: "Parole alla volta",
        chunkCaption: "Più parole per lampo leggono più in fretta, ma chiedono di più a te.",
        focusPointTitle: "Segna la lettera di fuoco",
        focusPointCaption: "Colora una lettera di ogni parola e la allinea, così i tuoi occhi restano fermi.",
        punctuationPauseTitle: "Pausa sulla punteggiatura",
        punctuationPauseCaption: "Si sofferma un po’ di più sulle virgole e molto di più a fine frase.",
        longWordScalingTitle: "Rallenta sulle parole lunghe",
        longWordScalingCaption: "Dà più tempo a una parola lunga che a una corta.",
        surfaceTitle: "Mostrala",
        surfaceFloating: "In una finestra fluttuante",
        surfaceNotch: "Intorno alla fotocamera",
        shortcutTitle: "Scorciatoia",
        playAction: "Riproduci",
        pauseAction: "Pausa",
        restartAction: "Ricomincia",
        closeHint: "Esc chiude",
        finishedCaption: "Finito",
        progressFormat: "%1$d di %2$d",
        noSelection: "Seleziona del testo e riprova",
        emptySelection: "In quella selezione non c’erano parole da leggere",
        truncatedFormat: "Sono stati presi solo i primi %d caratteri",
        accessibilityNeeded: "La scorciatoia richiede l’Accessibilità per vedere cosa hai selezionato. Il menu Servizi funziona anche senza."
    )

    static let ja = FastReaderFeatureStrings(
        pageTitle: "高速リーダー",
        hubDescription: "選択したテキストを一かたまりずつ点滅表示で読む",
        panelCaption: "目を動かさずに選択した範囲を読む",
        serviceMenuItem: "高速リーダーで読む",
        openButton: "選択範囲を読む",
        speedTitle: "速度",
        speedCaption: "1分あたりの単語数。自然に感じるより遅めから始めて、少しずつ上げてください。",
        chunkTitle: "一度に表示する単語数",
        chunkCaption: "多く表示するほど速く読めますが、その分集中力が必要です。",
        focusPointTitle: "注視文字を強調する",
        focusPointCaption: "各単語の1文字に色を付けて位置をそろえ、視線が動かないようにします。",
        punctuationPauseTitle: "句読点で間を置く",
        punctuationPauseCaption: "読点で少し、文末ではさらに長く止まります。",
        longWordScalingTitle: "長い単語では速度を落とす",
        longWordScalingCaption: "長い単語には短い単語より多くの時間を割きます。",
        surfaceTitle: "表示方法",
        surfaceFloating: "フローティングウインドウ",
        surfaceNotch: "カメラの周囲",
        shortcutTitle: "ショートカット",
        playAction: "再生",
        pauseAction: "一時停止",
        restartAction: "最初からやり直す",
        closeHint: "Escで閉じる",
        finishedCaption: "終了しました",
        progressFormat: "%2$d 個中 %1$d 個目",
        noSelection: "テキストを選択してからもう一度お試しください",
        emptySelection: "その選択範囲には読める単語がありませんでした",
        truncatedFormat: "最初の%d文字のみを使用しました",
        accessibilityNeeded: "ショートカットで選択内容を認識するには「アクセシビリティ」の許可が必要です。「サービス」メニューは許可がなくても使えます。"
    )

    static let ko = FastReaderFeatureStrings(
        pageTitle: "빠른 읽기",
        hubDescription: "선택한 텍스트를 한 번에 한 덩어리씩 깜빡이며 읽어줍니다",
        panelCaption: "눈을 움직이지 않고 선택한 텍스트를 읽으세요",
        serviceMenuItem: "빠른 읽기로 읽기",
        openButton: "선택 항목 읽기",
        speedTitle: "속도",
        speedCaption: "분당 단어 수입니다. 자연스럽게 느껴지는 것보다 낮게 시작해서 점점 올려 보세요.",
        chunkTitle: "한 번에 표시할 단어 수",
        chunkCaption: "한 번에 더 많은 단어를 표시하면 더 빨리 읽히지만, 그만큼 집중이 필요합니다.",
        focusPointTitle: "초점 글자 표시",
        focusPointCaption: "각 단어의 한 글자에 색을 입혀 정렬하므로 시선이 한자리에 머물게 됩니다.",
        punctuationPauseTitle: "문장 부호에서 멈추기",
        punctuationPauseCaption: "쉼표에서는 잠시, 문장이 끝날 때는 더 오래 멈춥니다.",
        longWordScalingTitle: "긴 단어에서 느려지기",
        longWordScalingCaption: "짧은 단어보다 긴 단어에 더 많은 시간을 줍니다.",
        surfaceTitle: "표시 위치",
        surfaceFloating: "떠 있는 창",
        surfaceNotch: "카메라 주변",
        shortcutTitle: "단축키",
        playAction: "재생",
        pauseAction: "일시 정지",
        restartAction: "처음부터 다시",
        closeHint: "Esc로 닫기",
        finishedCaption: "완료",
        progressFormat: "%2$d개 중 %1$d번째",
        noSelection: "텍스트를 선택한 뒤 다시 시도하세요",
        emptySelection: "선택한 부분에 읽을 단어가 없었습니다",
        truncatedFormat: "처음 %d자만 가져왔습니다",
        accessibilityNeeded: "단축키가 선택 항목을 확인하려면 손쉬운 사용 권한이 필요합니다. 서비스 메뉴는 이 권한 없이도 작동합니다."
    )

    static let zhHans = FastReaderFeatureStrings(
        pageTitle: "速读器",
        hubDescription: "以闪现方式逐块显示选中的文字",
        panelCaption: "无需移动视线即可阅读所选内容",
        serviceMenuItem: "用速读器阅读",
        openButton: "阅读所选内容",
        speedTitle: "速度",
        speedCaption: "每分钟的单词数。先从比感觉自然更慢的速度开始，再逐步提高。",
        chunkTitle: "每次显示的单词数",
        chunkCaption: "每次闪现的单词越多读得越快，但对你的要求也越高。",
        focusPointTitle: "标出焦点字母",
        focusPointCaption: "为每个单词的一个字母上色并对齐，让你的视线保持不动。",
        punctuationPauseTitle: "在标点处停顿",
        punctuationPauseCaption: "在逗号处稍作停顿，在句末停顿更久。",
        longWordScalingTitle: "长单词放慢速度",
        longWordScalingCaption: "给长单词比短单词更多的时间。",
        surfaceTitle: "显示位置",
        surfaceFloating: "浮动窗口",
        surfaceNotch: "摄像头周围",
        shortcutTitle: "快捷键",
        playAction: "播放",
        pauseAction: "暂停",
        restartAction: "重新开始",
        closeHint: "按 Esc 关闭",
        finishedCaption: "已完成",
        progressFormat: "第 %1$d 个，共 %2$d 个",
        noSelection: "请选中一些文字后重试",
        emptySelection: "所选内容中没有可读的单词",
        truncatedFormat: "仅取用了前 %d 个字符",
        accessibilityNeeded: "快捷键需要辅助功能权限才能看到你选中的内容。服务菜单无需该权限即可使用。"
    )

    static let zhTW = FastReaderFeatureStrings(
        pageTitle: "快速閱讀器",
        hubDescription: "以閃現方式逐塊顯示選取的文字",
        panelCaption: "不必移動視線即可閱讀所選內容",
        serviceMenuItem: "用快速閱讀器閱讀",
        openButton: "閱讀所選內容",
        speedTitle: "速度",
        speedCaption: "每分鐘的字詞數。先從比感覺自然更慢的速度開始，再逐步提高。",
        chunkTitle: "每次顯示的字詞數",
        chunkCaption: "每次閃現的字詞越多讀得越快，但對你的要求也越高。",
        focusPointTitle: "標出焦點字母",
        focusPointCaption: "為每個字詞的一個字母上色並對齊，讓你的視線保持不動。",
        punctuationPauseTitle: "在標點處停頓",
        punctuationPauseCaption: "在逗號處稍作停頓，在句末停頓更久。",
        longWordScalingTitle: "長字詞放慢速度",
        longWordScalingCaption: "給長字詞比短字詞更多的時間。",
        surfaceTitle: "顯示位置",
        surfaceFloating: "浮動視窗",
        surfaceNotch: "攝影機周圍",
        shortcutTitle: "快速鍵",
        playAction: "播放",
        pauseAction: "暫停",
        restartAction: "重新開始",
        closeHint: "按 Esc 關閉",
        finishedCaption: "已完成",
        progressFormat: "第 %1$d 個，共 %2$d 個",
        noSelection: "請選取一些文字後再試一次",
        emptySelection: "所選內容中沒有可讀的字詞",
        truncatedFormat: "僅取用了前 %d 個字元",
        accessibilityNeeded: "快速鍵需要輔助使用權限才能看到你選取的內容。服務選單不需要該權限即可使用。"
    )

    static let zhHK = FastReaderFeatureStrings(
        pageTitle: "快速閱讀器",
        hubDescription: "以閃現方式逐塊顯示選取的文字",
        panelCaption: "不必移動視線即可閱讀所選內容",
        serviceMenuItem: "用快速閱讀器閱讀",
        openButton: "閱讀所選內容",
        speedTitle: "速度",
        speedCaption: "每分鐘的字詞數。先從比感覺自然更慢的速度開始，再逐步提高。",
        chunkTitle: "每次顯示的字詞數",
        chunkCaption: "每次閃現的字詞越多讀得越快，但對你的要求也越高。",
        focusPointTitle: "標出焦點字母",
        focusPointCaption: "為每個字詞的一個字母上色並對齊，讓你的視線保持不動。",
        punctuationPauseTitle: "在標點處停頓",
        punctuationPauseCaption: "喺逗號處稍作停頓，句末停頓更耐。",
        longWordScalingTitle: "長字詞放慢速度",
        longWordScalingCaption: "俾長字詞比短字詞更多時間。",
        surfaceTitle: "顯示位置",
        surfaceFloating: "浮動視窗",
        surfaceNotch: "鏡頭周圍",
        shortcutTitle: "快速鍵",
        playAction: "播放",
        pauseAction: "暫停",
        restartAction: "重新開始",
        closeHint: "按 Esc 關閉",
        finishedCaption: "已完成",
        progressFormat: "第 %1$d 個，共 %2$d 個",
        noSelection: "請選取一些文字後再試一次",
        emptySelection: "所選內容中冇可讀嘅字詞",
        truncatedFormat: "只取用咗頭 %d 個字元",
        accessibilityNeeded: "快速鍵需要輔助功能權限先可以睇到你選取嘅內容。服務選單唔需要呢個權限都可以用。"
    )

    static let uk = FastReaderFeatureStrings(
        pageTitle: "Швидке читання",
        hubDescription: "Показує виділений текст спалахами, блок за блоком",
        panelCaption: "Читайте виділений текст, не рухаючи очима",
        serviceMenuItem: "Читати в режимі швидкого читання",
        openButton: "Прочитати виділене",
        speedTitle: "Швидкість",
        speedCaption: "Слів за хвилину. Почніть повільніше, ніж здається природним, і поступово збільшуйте.",
        chunkTitle: "Слів за раз",
        chunkCaption: "Більше слів у спалаху прискорює читання, але вимагає більше уваги.",
        focusPointTitle: "Виділяти опорну літеру",
        focusPointCaption: "Підсвічує одну літеру кожного слова й вирівнює її, щоб погляд залишався на місці.",
        punctuationPauseTitle: "Пауза на розділових знаках",
        punctuationPauseCaption: "Затримується трохи довше на комі й помітно довше в кінці речення.",
        longWordScalingTitle: "Сповільнюватися на довгих словах",
        longWordScalingCaption: "Дає довгому слову більше часу, ніж короткому.",
        surfaceTitle: "Показувати",
        surfaceFloating: "У плаваючому вікні",
        surfaceNotch: "Навколо камери",
        shortcutTitle: "Клавіатурне скорочення",
        playAction: "Відтворити",
        pauseAction: "Пауза",
        restartAction: "Почати спочатку",
        closeHint: "Esc закриває",
        finishedCaption: "Готово",
        progressFormat: "%1$d з %2$d",
        noSelection: "Виділіть текст і спробуйте ще раз",
        emptySelection: "У цьому виділенні немає слів для читання",
        truncatedFormat: "Взято лише перші %d символів",
        accessibilityNeeded: "Клавіатурному скороченню потрібен дозвіл «Доступність», щоб бачити виділений текст. Меню «Служби» працює і без нього."
    )
}
