// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the keyboard typer, which types text as key presses
/// where pasting is blocked.
struct KeyboardTyperFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let placeholder: String
    let delayLabel: String
    let msUnit: String
    let send: String
    let stopped: String
    let needsAccessibility: String
    let systemLayout: String
    let layoutsTitle: String
    let layoutsCaption: String
    let searchLayouts: String
    let favorite: String
    let unfavorite: String
    /// The delayed Send's tooltip, with the seconds it waits.
    let sendDelayedFormat: String
    /// The delayed Send's own label: the seconds, kept short for the footer.
    let secondsFormat: String
    let countdownTitle: String
    let countdownCaption: String
    let snippetsTitle: String
    let snippetNamePlaceholder: String
    let saveSnippet: String
    let deleteSnippet: String
    let snippetsEmpty: String
    let snippetsSaveFailed: String
    let methodTitle: String
    let methodCharacters: String
    let methodKeyPositions: String
    /// Sending characters, a refusal naming what the layout cannot type.
    let missingCharactersFormat: String
}

extension FeatureStrings {
    static func keyboardTyper(_ language: AppLanguage) -> KeyboardTyperFeatureStrings {
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

extension KeyboardTyperFeatureStrings {
    static let enUS = KeyboardTyperFeatureStrings(
        pageTitle: "Keyboard typer",
        hubDescription: "Types text as key presses where pasting is blocked, like a remote desktop",
        panelCaption: "Type text into a remote desktop key by key",
        openButton: "Open typer",
        placeholder: "Text to type. Send hides this window and types it into the app behind it. Esc stops.",
        delayLabel: "Delay",
        msUnit: "ms",
        send: "Send",
        stopped: "Typing stopped",
        needsAccessibility: "Typing needs Accessibility access",
        systemLayout: "System layout",
        layoutsTitle: "Destination layouts",
        layoutsCaption: "Star the layouts your remote computers use. Starred layouts appear next to Send, and the keys are pressed as that layout places them.",
        searchLayouts: "Search layouts",
        favorite: "Add to favorites",
        unfavorite: "Remove from favorites",
        sendDelayedFormat: "Send in %d seconds: click into the window that should receive the text meanwhile",
        secondsFormat: "%d s",
        countdownTitle: "Delayed Send",
        countdownCaption: "The second Send button hides the typer and waits this long before typing, so you can click into a window that lost focus. Esc cancels.",
        snippetsTitle: "Snippets",
        snippetNamePlaceholder: "Name (optional)",
        saveSnippet: "Save the text as a snippet",
        deleteSnippet: "Delete",
        snippetsEmpty: "Saved texts appear here. Click one to put it back in the text.",
        snippetsSaveFailed: "Snippets could not be saved",
        methodTitle: "Typing method",
        methodCharacters: "Characters (web consoles, VNC)",
        methodKeyPositions: "Key positions (remote desktop apps)",
        missingCharactersFormat: "This layout has no key for %@. Nothing was typed."
    )

    static let ptBR = KeyboardTyperFeatureStrings(
        pageTitle: "Digitador de teclado",
        hubDescription: "Digita texto como teclas pressionadas onde colar é bloqueado, como numa área de trabalho remota",
        panelCaption: "Digite texto numa área de trabalho remota, tecla por tecla",
        openButton: "Abrir digitador",
        placeholder: "Texto a digitar. Enviar oculta esta janela e o digita no app por trás dela. Esc interrompe.",
        delayLabel: "Atraso",
        msUnit: "ms",
        send: "Enviar",
        stopped: "Digitação interrompida",
        needsAccessibility: "Digitar requer acesso de Acessibilidade",
        systemLayout: "Layout do sistema",
        layoutsTitle: "Layouts de destino",
        layoutsCaption: "Marque com estrela os layouts dos seus computadores remotos. Eles aparecem ao lado de Enviar, e as teclas são pressionadas como esse layout as posiciona.",
        searchLayouts: "Buscar layouts",
        favorite: "Adicionar aos favoritos",
        unfavorite: "Remover dos favoritos",
        sendDelayedFormat: "Enviar em %d segundos: enquanto isso, clique na janela que deve receber o texto",
        secondsFormat: "%d s",
        countdownTitle: "Envio atrasado",
        countdownCaption: "O segundo botão Enviar oculta o digitador e espera esse tempo antes de digitar, para você clicar numa janela que perdeu o foco. Esc cancela.",
        snippetsTitle: "Trechos",
        snippetNamePlaceholder: "Nome (opcional)",
        saveSnippet: "Salvar o texto como trecho",
        deleteSnippet: "Apagar",
        snippetsEmpty: "Os textos salvos aparecem aqui. Clique em um para colocá-lo de volta no texto.",
        snippetsSaveFailed: "Não foi possível salvar os trechos",
        methodTitle: "Método de digitação",
        methodCharacters: "Caracteres (consoles web, VNC)",
        methodKeyPositions: "Posições das teclas (apps de área de trabalho remota)",
        missingCharactersFormat: "Este layout não tem tecla para %@. Nada foi digitado."
    )

    static let tr = KeyboardTyperFeatureStrings(
        pageTitle: "Klavye yazıcı",
        hubDescription: "Yapıştırmanın engellendiği yerlerde, örneğin uzak masaüstünde, metni tuş basışlarıyla yazar",
        panelCaption: "Uzak masaüstüne metni tuş tuş yazın",
        openButton: "Yazıcıyı aç",
        placeholder: "Yazılacak metin. Gönder bu pencereyi gizler ve metni arkasındaki uygulamaya yazar. Esc durdurur.",
        delayLabel: "Gecikme",
        msUnit: "ms",
        send: "Gönder",
        stopped: "Yazma durduruldu",
        needsAccessibility: "Yazmak için Erişilebilirlik izni gerekir",
        systemLayout: "Sistem düzeni",
        layoutsTitle: "Hedef düzenler",
        layoutsCaption: "Uzak bilgisayarlarınızın kullandığı düzenleri yıldızlayın. Yıldızlı düzenler Gönder’in yanında görünür ve tuşlar o düzenin yerleşimine göre basılır.",
        searchLayouts: "Düzen ara",
        favorite: "Favorilere ekle",
        unfavorite: "Favorilerden çıkar",
        sendDelayedFormat: "%d saniye sonra gönder: bu sırada metni alacak pencereye tıklayın",
        secondsFormat: "%d sn",
        countdownTitle: "Gecikmeli gönderme",
        countdownCaption: "İkinci Gönder düğmesi yazıcıyı gizler ve yazmadan önce bu kadar bekler; böylece odağını kaybeden bir pencereye tıklayabilirsiniz. Esc iptal eder.",
        snippetsTitle: "Parçacıklar",
        snippetNamePlaceholder: "Ad (isteğe bağlı)",
        saveSnippet: "Metni parçacık olarak kaydet",
        deleteSnippet: "Sil",
        snippetsEmpty: "Kaydedilen metinler burada görünür. Birine tıklayarak metne geri koyun.",
        snippetsSaveFailed: "Parçacıklar kaydedilemedi",
        methodTitle: "Yazma yöntemi",
        methodCharacters: "Karakterler (web konsolları, VNC)",
        methodKeyPositions: "Tuş konumları (uzak masaüstü uygulamaları)",
        missingCharactersFormat: "Bu düzende %@ için tuş yok. Hiçbir şey yazılmadı."
    )

    static let ru = KeyboardTyperFeatureStrings(
        pageTitle: "Клавиатурный ввод",
        hubDescription: "Набирает текст нажатиями клавиш там, где вставка запрещена, например в удалённом рабочем столе",
        panelCaption: "Наберите текст в удалённом рабочем столе по клавише",
        openButton: "Открыть ввод",
        placeholder: "Текст для набора. «Отправить» скрывает это окно и набирает текст в приложении за ним. Esc останавливает.",
        delayLabel: "Задержка",
        msUnit: "мс",
        send: "Отправить",
        stopped: "Набор остановлен",
        needsAccessibility: "Для набора нужен доступ к Универсальному доступу",
        systemLayout: "Системная раскладка",
        layoutsTitle: "Раскладки получателя",
        layoutsCaption: "Отметьте звездой раскладки удалённых компьютеров. Они появятся рядом с кнопкой «Отправить», а клавиши будут нажиматься так, как их располагает эта раскладка.",
        searchLayouts: "Поиск раскладок",
        favorite: "Добавить в избранное",
        unfavorite: "Удалить из избранного",
        sendDelayedFormat: "Отправить через %d с: тем временем щёлкните в окне, которое должно получить текст",
        secondsFormat: "%d с",
        countdownTitle: "Отложенная отправка",
        countdownCaption: "Вторая кнопка «Отправить» скрывает окно ввода и ждёт столько перед набором, чтобы вы успели щёлкнуть в окне, потерявшем фокус. Esc отменяет.",
        snippetsTitle: "Фрагменты",
        snippetNamePlaceholder: "Название (необязательно)",
        saveSnippet: "Сохранить текст как фрагмент",
        deleteSnippet: "Удалить",
        snippetsEmpty: "Здесь появятся сохранённые тексты. Щёлкните, чтобы вернуть текст в поле.",
        snippetsSaveFailed: "Не удалось сохранить фрагменты",
        methodTitle: "Способ ввода",
        methodCharacters: "Символы (веб-консоли, VNC)",
        methodKeyPositions: "Положения клавиш (приложения удалённого рабочего стола)",
        missingCharactersFormat: "В этой раскладке нет клавиши для %@. Ничего не набрано."
    )

    static let es = KeyboardTyperFeatureStrings(
        pageTitle: "Mecanógrafo de teclado",
        hubDescription: "Escribe texto como pulsaciones de teclas donde pegar está bloqueado, como en un escritorio remoto",
        panelCaption: "Escribe texto en un escritorio remoto tecla a tecla",
        openButton: "Abrir mecanógrafo",
        placeholder: "Texto que escribir. Enviar oculta esta ventana y lo escribe en la app de detrás. Esc lo detiene.",
        delayLabel: "Retardo",
        msUnit: "ms",
        send: "Enviar",
        stopped: "Escritura detenida",
        needsAccessibility: "Escribir requiere acceso de Accesibilidad",
        systemLayout: "Distribución del sistema",
        layoutsTitle: "Distribuciones de destino",
        layoutsCaption: "Marca con una estrella las distribuciones de tus ordenadores remotos. Aparecen junto a Enviar, y las teclas se pulsan como esa distribución las coloca.",
        searchLayouts: "Buscar distribuciones",
        favorite: "Añadir a favoritos",
        unfavorite: "Quitar de favoritos",
        sendDelayedFormat: "Enviar en %d segundos: mientras tanto, haz clic en la ventana que debe recibir el texto",
        secondsFormat: "%d s",
        countdownTitle: "Envío diferido",
        countdownCaption: "El segundo botón Enviar oculta el mecanógrafo y espera este tiempo antes de escribir, para que hagas clic en una ventana que perdió el foco. Esc cancela.",
        snippetsTitle: "Fragmentos",
        snippetNamePlaceholder: "Nombre (opcional)",
        saveSnippet: "Guardar el texto como fragmento",
        deleteSnippet: "Eliminar",
        snippetsEmpty: "Los textos guardados aparecen aquí. Haz clic en uno para volver a ponerlo en el texto.",
        snippetsSaveFailed: "No se pudieron guardar los fragmentos",
        methodTitle: "Método de escritura",
        methodCharacters: "Caracteres (consolas web, VNC)",
        methodKeyPositions: "Posiciones de teclas (apps de escritorio remoto)",
        missingCharactersFormat: "Esta distribución no tiene tecla para %@. No se escribió nada."
    )

    static let sk = KeyboardTyperFeatureStrings(
        pageTitle: "Klávesnicový písač",
        hubDescription: "Píše text stlačeniami kláves tam, kde je vkladanie zablokované, napríklad vo vzdialenej ploche",
        panelCaption: "Napíšte text do vzdialenej plochy kláves po klávese",
        openButton: "Otvoriť písač",
        placeholder: "Text na napísanie. Odoslať skryje toto okno a napíše ho do aplikácie za ním. Esc zastaví.",
        delayLabel: "Oneskorenie",
        msUnit: "ms",
        send: "Odoslať",
        stopped: "Písanie zastavené",
        needsAccessibility: "Písanie vyžaduje prístup Prístupnosti",
        systemLayout: "Systémové rozloženie",
        layoutsTitle: "Cieľové rozloženia",
        layoutsCaption: "Označte hviezdičkou rozloženia vzdialených počítačov. Zobrazia sa vedľa tlačidla Odoslať a klávesy sa stláčajú podľa toho, ako ich toto rozloženie umiestňuje.",
        searchLayouts: "Hľadať rozloženia",
        favorite: "Pridať medzi obľúbené",
        unfavorite: "Odstrániť z obľúbených",
        sendDelayedFormat: "Odoslať o %d s: medzitým kliknite do okna, ktoré má text dostať",
        secondsFormat: "%d s",
        countdownTitle: "Oneskorené odoslanie",
        countdownCaption: "Druhé tlačidlo Odoslať skryje písač a pred písaním počká tento čas, aby ste mohli kliknúť do okna, ktoré stratilo fokus. Esc zruší.",
        snippetsTitle: "Úryvky",
        snippetNamePlaceholder: "Názov (voliteľný)",
        saveSnippet: "Uložiť text ako úryvok",
        deleteSnippet: "Vymazať",
        snippetsEmpty: "Uložené texty sa zobrazia tu. Kliknutím ho vrátite do textu.",
        snippetsSaveFailed: "Úryvky sa nepodarilo uložiť",
        methodTitle: "Spôsob písania",
        methodCharacters: "Znaky (webové konzoly, VNC)",
        methodKeyPositions: "Polohy kláves (aplikácie vzdialenej plochy)",
        missingCharactersFormat: "Toto rozloženie nemá kláves pre %@. Nič sa nenapísalo."
    )

    static let de = KeyboardTyperFeatureStrings(
        pageTitle: "Tastatur-Tipper",
        hubDescription: "Tippt Text als Tastendrücke, wo Einfügen gesperrt ist, etwa in einem Remote-Desktop",
        panelCaption: "Text Taste für Taste in einen Remote-Desktop tippen",
        openButton: "Tipper öffnen",
        placeholder: "Zu tippender Text. Senden blendet dieses Fenster aus und tippt ihn in die App dahinter. Esc stoppt.",
        delayLabel: "Verzögerung",
        msUnit: "ms",
        send: "Senden",
        stopped: "Tippen gestoppt",
        needsAccessibility: "Tippen braucht Zugriff auf Bedienungshilfen",
        systemLayout: "Systemlayout",
        layoutsTitle: "Ziel-Layouts",
        layoutsCaption: "Markiere die Layouts deiner Remote-Computer mit einem Stern. Sie erscheinen neben Senden, und die Tasten werden so gedrückt, wie dieses Layout sie anordnet.",
        searchLayouts: "Layouts suchen",
        favorite: "Zu Favoriten hinzufügen",
        unfavorite: "Aus Favoriten entfernen",
        sendDelayedFormat: "In %d Sekunden senden: Klicke inzwischen in das Fenster, das den Text erhalten soll",
        secondsFormat: "%d s",
        countdownTitle: "Verzögertes Senden",
        countdownCaption: "Die zweite Senden-Taste blendet den Tipper aus und wartet so lange vor dem Tippen, damit du in ein Fenster klicken kannst, das den Fokus verloren hat. Esc bricht ab.",
        snippetsTitle: "Textbausteine",
        snippetNamePlaceholder: "Name (optional)",
        saveSnippet: "Text als Baustein sichern",
        deleteSnippet: "Löschen",
        snippetsEmpty: "Gesicherte Texte erscheinen hier. Klicke auf einen, um ihn zurück in den Text zu holen.",
        snippetsSaveFailed: "Textbausteine konnten nicht gesichert werden",
        methodTitle: "Tippmethode",
        methodCharacters: "Zeichen (Web-Konsolen, VNC)",
        methodKeyPositions: "Tastenpositionen (Remote-Desktop-Apps)",
        missingCharactersFormat: "Dieses Layout hat keine Taste für %@. Es wurde nichts getippt."
    )

    static let fr = KeyboardTyperFeatureStrings(
        pageTitle: "Saisie clavier",
        hubDescription: "Tape du texte touche par touche là où coller est bloqué, comme dans un bureau à distance",
        panelCaption: "Tapez du texte dans un bureau à distance, touche par touche",
        openButton: "Ouvrir la saisie",
        placeholder: "Texte à taper. Envoyer masque cette fenêtre et le tape dans l’app derrière. Échap arrête.",
        delayLabel: "Délai",
        msUnit: "ms",
        send: "Envoyer",
        stopped: "Saisie arrêtée",
        needsAccessibility: "La saisie nécessite l’accès Accessibilité",
        systemLayout: "Disposition du système",
        layoutsTitle: "Dispositions de destination",
        layoutsCaption: "Ajoutez une étoile aux dispositions de vos ordinateurs distants. Elles apparaissent à côté d’Envoyer, et les touches sont pressées selon cette disposition.",
        searchLayouts: "Rechercher une disposition",
        favorite: "Ajouter aux favoris",
        unfavorite: "Retirer des favoris",
        sendDelayedFormat: "Envoyer dans %d secondes : cliquez entre-temps dans la fenêtre qui doit recevoir le texte",
        secondsFormat: "%d s",
        countdownTitle: "Envoi différé",
        countdownCaption: "Le second bouton Envoyer masque la saisie et attend ce délai avant de taper, pour que vous cliquiez dans une fenêtre qui a perdu le focus. Échap annule.",
        snippetsTitle: "Extraits",
        snippetNamePlaceholder: "Nom (facultatif)",
        saveSnippet: "Enregistrer le texte comme extrait",
        deleteSnippet: "Supprimer",
        snippetsEmpty: "Les textes enregistrés apparaissent ici. Cliquez sur l’un d’eux pour le remettre dans le texte.",
        snippetsSaveFailed: "Impossible d’enregistrer les extraits",
        methodTitle: "Méthode de saisie",
        methodCharacters: "Caractères (consoles web, VNC)",
        methodKeyPositions: "Positions des touches (apps de bureau à distance)",
        missingCharactersFormat: "Cette disposition n’a pas de touche pour %@. Rien n’a été tapé."
    )

    static let it = KeyboardTyperFeatureStrings(
        pageTitle: "Digitatore da tastiera",
        hubDescription: "Digita il testo come pressioni di tasti dove incollare è bloccato, come in un desktop remoto",
        panelCaption: "Digita testo in un desktop remoto tasto per tasto",
        openButton: "Apri digitatore",
        placeholder: "Testo da digitare. Invia nasconde questa finestra e lo digita nell’app dietro. Esc interrompe.",
        delayLabel: "Ritardo",
        msUnit: "ms",
        send: "Invia",
        stopped: "Digitazione interrotta",
        needsAccessibility: "Per digitare serve l’accesso ad Accessibilità",
        systemLayout: "Layout di sistema",
        layoutsTitle: "Layout di destinazione",
        layoutsCaption: "Aggiungi una stella ai layout dei tuoi computer remoti. Compaiono accanto a Invia, e i tasti vengono premuti come li dispone quel layout.",
        searchLayouts: "Cerca layout",
        favorite: "Aggiungi ai preferiti",
        unfavorite: "Rimuovi dai preferiti",
        sendDelayedFormat: "Invia tra %d secondi: nel frattempo fai clic nella finestra che deve ricevere il testo",
        secondsFormat: "%d s",
        countdownTitle: "Invio ritardato",
        countdownCaption: "Il secondo pulsante Invia nasconde il digitatore e attende questo tempo prima di digitare, così puoi fare clic in una finestra che ha perso il focus. Esc annulla.",
        snippetsTitle: "Frammenti",
        snippetNamePlaceholder: "Nome (facoltativo)",
        saveSnippet: "Salva il testo come frammento",
        deleteSnippet: "Elimina",
        snippetsEmpty: "I testi salvati compaiono qui. Fai clic su uno per rimetterlo nel testo.",
        snippetsSaveFailed: "Impossibile salvare i frammenti",
        methodTitle: "Metodo di digitazione",
        methodCharacters: "Caratteri (console web, VNC)",
        methodKeyPositions: "Posizioni dei tasti (app di desktop remoto)",
        missingCharactersFormat: "Questo layout non ha un tasto per %@. Non è stato digitato nulla."
    )

    static let ja = KeyboardTyperFeatureStrings(
        pageTitle: "キーボード入力",
        hubDescription: "リモートデスクトップなどペーストできない場所に、テキストをキー入力として送ります",
        panelCaption: "リモートデスクトップに1キーずつ入力",
        openButton: "入力を開く",
        placeholder: "入力するテキスト。送信するとこのウインドウが隠れ、背後のアプリに入力します。Escで停止。",
        delayLabel: "間隔",
        msUnit: "ms",
        send: "送信",
        stopped: "入力を停止しました",
        needsAccessibility: "入力にはアクセシビリティへのアクセスが必要です",
        systemLayout: "システムの配列",
        layoutsTitle: "送信先の配列",
        layoutsCaption: "リモートコンピュータで使う配列に星を付けます。星付きの配列は送信ボタンの横に表示され、その配列のキー位置で入力します。",
        searchLayouts: "配列を検索",
        favorite: "お気に入りに追加",
        unfavorite: "お気に入りから削除",
        sendDelayedFormat: "%d秒後に送信：その間に、テキストを受け取るウインドウをクリックしてください",
        secondsFormat: "%d秒",
        countdownTitle: "遅延送信",
        countdownCaption: "2つ目の送信ボタンは入力ウインドウを隠し、入力の前にこの時間だけ待ちます。フォーカスを失ったウインドウをクリックできます。Escで取り消し。",
        snippetsTitle: "スニペット",
        snippetNamePlaceholder: "名前（省略可）",
        saveSnippet: "テキストをスニペットとして保存",
        deleteSnippet: "削除",
        snippetsEmpty: "保存したテキストがここに表示されます。クリックするとテキストに戻せます。",
        snippetsSaveFailed: "スニペットを保存できませんでした",
        methodTitle: "入力方式",
        methodCharacters: "文字（Webコンソール、VNC）",
        methodKeyPositions: "キーの位置（リモートデスクトップApp）",
        missingCharactersFormat: "この配列には %@ のキーがありません。何も入力していません。"
    )

    static let ko = KeyboardTyperFeatureStrings(
        pageTitle: "키보드 입력기",
        hubDescription: "원격 데스크톱처럼 붙여넣기가 막힌 곳에 텍스트를 키 입력으로 보냅니다",
        panelCaption: "원격 데스크톱에 한 키씩 텍스트 입력",
        openButton: "입력기 열기",
        placeholder: "입력할 텍스트. 보내기를 누르면 이 창이 숨겨지고 뒤에 있는 앱에 입력합니다. Esc로 중지.",
        delayLabel: "지연",
        msUnit: "ms",
        send: "보내기",
        stopped: "입력이 중지됨",
        needsAccessibility: "입력하려면 손쉬운 사용 접근 권한이 필요합니다",
        systemLayout: "시스템 자판",
        layoutsTitle: "대상 자판",
        layoutsCaption: "원격 컴퓨터에서 쓰는 자판에 별표를 하세요. 별표한 자판은 보내기 옆에 나타나며, 해당 자판의 키 위치대로 입력합니다.",
        searchLayouts: "자판 검색",
        favorite: "즐겨찾기에 추가",
        unfavorite: "즐겨찾기에서 제거",
        sendDelayedFormat: "%d초 후 보내기: 그동안 텍스트를 받을 창을 클릭하세요",
        secondsFormat: "%d초",
        countdownTitle: "지연 보내기",
        countdownCaption: "두 번째 보내기 버튼은 입력기를 숨기고 입력하기 전에 이만큼 기다리므로, 포커스를 잃은 창을 클릭할 수 있습니다. Esc로 취소.",
        snippetsTitle: "스니펫",
        snippetNamePlaceholder: "이름(선택 사항)",
        saveSnippet: "텍스트를 스니펫으로 저장",
        deleteSnippet: "삭제",
        snippetsEmpty: "저장한 텍스트가 여기에 나타납니다. 클릭하면 텍스트로 다시 가져옵니다.",
        snippetsSaveFailed: "스니펫을 저장할 수 없습니다",
        methodTitle: "입력 방식",
        methodCharacters: "문자(웹 콘솔, VNC)",
        methodKeyPositions: "키 위치(원격 데스크톱 앱)",
        missingCharactersFormat: "이 자판에는 %@ 키가 없습니다. 아무것도 입력하지 않았습니다."
    )

    static let zhHans = KeyboardTyperFeatureStrings(
        pageTitle: "键盘输入器",
        hubDescription: "在无法粘贴的地方（如远程桌面）以按键方式输入文本",
        panelCaption: "逐键向远程桌面输入文本",
        openButton: "打开输入器",
        placeholder: "要输入的文本。点按“发送”会隐藏此窗口，并输入到其后的 App 中。按 Esc 停止。",
        delayLabel: "间隔",
        msUnit: "毫秒",
        send: "发送",
        stopped: "已停止输入",
        needsAccessibility: "输入需要辅助功能权限",
        systemLayout: "系统键盘布局",
        layoutsTitle: "目标键盘布局",
        layoutsCaption: "为远程电脑使用的键盘布局加星标。加星标的布局会显示在“发送”旁，并按该布局的键位按键。",
        searchLayouts: "搜索键盘布局",
        favorite: "添加到个人收藏",
        unfavorite: "从个人收藏中移除",
        sendDelayedFormat: "%d 秒后发送：在此期间点按要接收文本的窗口",
        secondsFormat: "%d 秒",
        countdownTitle: "延迟发送",
        countdownCaption: "第二个“发送”按钮会隐藏输入器，并在输入前等待这段时间，方便你点按失去焦点的窗口。按 Esc 取消。",
        snippetsTitle: "片段",
        snippetNamePlaceholder: "名称（可选）",
        saveSnippet: "将文本存储为片段",
        deleteSnippet: "删除",
        snippetsEmpty: "存储的文本会显示在这里。点按一个即可放回文本中。",
        snippetsSaveFailed: "无法存储片段",
        methodTitle: "输入方式",
        methodCharacters: "字符（网页控制台、VNC）",
        methodKeyPositions: "按键位置（远程桌面 App）",
        missingCharactersFormat: "此键盘布局没有 %@ 的按键。未输入任何内容。"
    )

    static let zhTW = KeyboardTyperFeatureStrings(
        pageTitle: "鍵盤輸入器",
        hubDescription: "在無法貼上的地方（如遠端桌面）以按鍵方式輸入文字",
        panelCaption: "逐鍵向遠端桌面輸入文字",
        openButton: "打開輸入器",
        placeholder: "要輸入的文字。按下「傳送」會隱藏此視窗，並輸入到其後的 App 中。按 Esc 停止。",
        delayLabel: "間隔",
        msUnit: "毫秒",
        send: "傳送",
        stopped: "已停止輸入",
        needsAccessibility: "輸入需要輔助使用權限",
        systemLayout: "系統鍵盤配置",
        layoutsTitle: "目標鍵盤配置",
        layoutsCaption: "為遠端電腦使用的鍵盤配置加上星號。加上星號的配置會顯示在「傳送」旁，並依該配置的鍵位按鍵。",
        searchLayouts: "搜尋鍵盤配置",
        favorite: "加入喜好項目",
        unfavorite: "從喜好項目中移除",
        sendDelayedFormat: "%d 秒後傳送：在此期間按一下要接收文字的視窗",
        secondsFormat: "%d 秒",
        countdownTitle: "延遲傳送",
        countdownCaption: "第二個「傳送」按鈕會隱藏輸入器，並在輸入前等待這段時間，方便你按一下失去焦點的視窗。按 Esc 取消。",
        snippetsTitle: "片段",
        snippetNamePlaceholder: "名稱（可選）",
        saveSnippet: "將文字儲存為片段",
        deleteSnippet: "刪除",
        snippetsEmpty: "儲存的文字會顯示在這裡。按一下即可放回文字中。",
        snippetsSaveFailed: "無法儲存片段",
        methodTitle: "輸入方式",
        methodCharacters: "字元（網頁主控台、VNC）",
        methodKeyPositions: "按鍵位置（遠端桌面 App）",
        missingCharactersFormat: "此鍵盤配置沒有 %@ 的按鍵。未輸入任何內容。"
    )

    static let zhHK = KeyboardTyperFeatureStrings(
        pageTitle: "鍵盤輸入器",
        hubDescription: "喺唔可以貼上嘅地方（例如遠端桌面）以按鍵方式輸入文字",
        panelCaption: "逐個鍵向遠端桌面輸入文字",
        openButton: "打開輸入器",
        placeholder: "要輸入嘅文字。按「傳送」會隱藏呢個視窗，並輸入到後面嘅 App。按 Esc 停止。",
        delayLabel: "間隔",
        msUnit: "毫秒",
        send: "傳送",
        stopped: "已停止輸入",
        needsAccessibility: "輸入需要輔助使用權限",
        systemLayout: "系統鍵盤配置",
        layoutsTitle: "目標鍵盤配置",
        layoutsCaption: "為遠端電腦用嘅鍵盤配置加星號。加咗星號嘅配置會喺「傳送」旁邊出現，並按該配置嘅鍵位按鍵。",
        searchLayouts: "搜尋鍵盤配置",
        favorite: "加入喜好項目",
        unfavorite: "從喜好項目中移除",
        sendDelayedFormat: "%d 秒後傳送：期間請撳一下要收文字嘅視窗",
        secondsFormat: "%d 秒",
        countdownTitle: "延遲傳送",
        countdownCaption: "第二個「傳送」按鈕會隱藏輸入器，喺輸入之前等呢段時間，等你可以撳返失去焦點嘅視窗。按 Esc 取消。",
        snippetsTitle: "片段",
        snippetNamePlaceholder: "名稱（可選）",
        saveSnippet: "將文字儲存為片段",
        deleteSnippet: "刪除",
        snippetsEmpty: "儲存咗嘅文字會喺度出現。撳一下就可以放返入文字。",
        snippetsSaveFailed: "儲存唔到片段",
        methodTitle: "輸入方式",
        methodCharacters: "字元（網頁主控台、VNC）",
        methodKeyPositions: "按鍵位置（遠端桌面 App）",
        missingCharactersFormat: "呢個鍵盤配置冇 %@ 嘅按鍵。冇輸入任何嘢。"
    )

    static let uk = KeyboardTyperFeatureStrings(
        pageTitle: "Клавіатурне введення",
        hubDescription: "Набирає текст натисканнями клавіш там, де вставлення заблоковано, наприклад у віддаленому робочому столі",
        panelCaption: "Наберіть текст у віддаленому робочому столі клавіша за клавішею",
        openButton: "Відкрити введення",
        placeholder: "Текст для набору. «Надіслати» ховає це вікно й набирає текст у програмі за ним. Esc зупиняє.",
        delayLabel: "Затримка",
        msUnit: "мс",
        send: "Надіслати",
        stopped: "Набір зупинено",
        needsAccessibility: "Для набору потрібен доступ до Універсального доступу",
        systemLayout: "Системна розкладка",
        layoutsTitle: "Розкладки отримувача",
        layoutsCaption: "Позначте зірочкою розкладки віддалених комп’ютерів. Вони з’являться поруч із кнопкою «Надіслати», а клавіші натискатимуться так, як їх розміщує ця розкладка.",
        searchLayouts: "Пошук розкладок",
        favorite: "Додати до вибраного",
        unfavorite: "Вилучити з вибраного",
        sendDelayedFormat: "Надіслати через %d с: тим часом клацніть у вікні, яке має отримати текст",
        secondsFormat: "%d с",
        countdownTitle: "Відкладене надсилання",
        countdownCaption: "Друга кнопка «Надіслати» ховає вікно введення й чекає стільки перед набором, щоб ви встигли клацнути у вікні, яке втратило фокус. Esc скасовує.",
        snippetsTitle: "Фрагменти",
        snippetNamePlaceholder: "Назва (необов’язково)",
        saveSnippet: "Зберегти текст як фрагмент",
        deleteSnippet: "Видалити",
        snippetsEmpty: "Тут з’являться збережені тексти. Клацніть, щоб повернути текст у поле.",
        snippetsSaveFailed: "Не вдалося зберегти фрагменти",
        methodTitle: "Спосіб введення",
        methodCharacters: "Символи (вебконсолі, VNC)",
        methodKeyPositions: "Положення клавіш (програми віддаленого робочого столу)",
        missingCharactersFormat: "У цій розкладці немає клавіші для %@. Нічого не набрано."
    )
}
