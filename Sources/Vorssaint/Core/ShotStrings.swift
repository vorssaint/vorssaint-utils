// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screenshot tool's overlay and settings that the
/// shared screenshot strings do not already carry.
struct ShotStrings {
    let summary: String
    let intro: String
    let fullScreenCaption: String
    let systemTitle: String
    let systemOn: String
    let systemOff: String
    let systemOpen: String
    let saving: String
    let defaultFolder: String
    let folderReset: String
    let folderCaption: String
    let exampleFormat: String
    let patternCaption: String
    let jpegQuality: String
    let behavior: String
    let autoCopy: String
    let notify: String
    let keepSelection: String
    let magnifier: String
    let print: String
    let openInPreview: String
    let sizeHintFormat: String
    let textSizeHintFormat: String
    let saveFailed: String
    let saveTitle: String
}

extension FeatureStrings {
    static func shot(_ language: AppLanguage) -> ShotStrings {
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

extension ShotStrings {
    static let enUS = ShotStrings(
        summary: "Select an area, draw on it, then copy, save or print it",
        intro: "The screen freezes, you drag to select an area, then draw on it and copy, save or print it. ⌘A or a double click selects the whole display, Esc cancels. Screenshots never leave this Mac.",
        fullScreenCaption: "Saves every display straight to the default folder, without selecting an area.",
        systemTitle: "macOS screenshot shortcuts",
        systemOn: "macOS still answers its own screenshot shortcuts (⇧⌘3, ⇧⌘4, ⇧⌘5). To leave screenshots to Vorssaint, turn them off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots. Vorssaint doesn’t change them for you.",
        systemOff: "The macOS screenshot shortcuts are off.",
        systemOpen: "Open Keyboard settings",
        saving: "Saving",
        defaultFolder: "Pictures/Screenshots (default)",
        folderReset: "Use Pictures/Screenshots",
        folderCaption: "Whole-screen saves go here. The save dialog opens in the folder you last saved to.",
        exampleFormat: "Example: %@",
        patternCaption: "{…} holds a date format such as {yyyy-MM-dd HH.mm.ss}; {n} is a running number.",
        jpegQuality: "JPEG quality",
        behavior: "Behavior",
        autoCopy: "Also copy to the clipboard when saving or printing",
        notify: "Show a confirmation after copying and saving",
        keepSelection: "Keep the selected area’s position",
        magnifier: "Show the magnifier while selecting",
        print: "Print",
        openInPreview: "Open in Preview",
        sizeHintFormat: "Size %d",
        textSizeHintFormat: "Text size %d",
        saveFailed: "The screenshot could not be saved",
        saveTitle: "Save screenshot"
    )

    static let ptBR = ShotStrings(
        summary: "Selecione uma área, desenhe nela e depois copie, salve ou imprima",
        intro: "A tela congela, você arrasta para selecionar uma área, desenha nela e depois copia, salva ou imprime. ⌘A ou um clique duplo seleciona a tela inteira, Esc cancela. As capturas nunca saem deste Mac.",
        fullScreenCaption: "Salva todas as telas direto na pasta padrão, sem selecionar uma área.",
        systemTitle: "Atalhos de captura do macOS",
        systemOn: "O macOS ainda responde aos próprios atalhos de captura (⇧⌘3, ⇧⌘4, ⇧⌘5). Para deixar as capturas com o Vorssaint, desative-os em Ajustes do Sistema › Teclado › Atalhos de Teclado › Capturas de Tela. O Vorssaint não os altera por você.",
        systemOff: "Os atalhos de captura do macOS estão desativados.",
        systemOpen: "Abrir ajustes de Teclado",
        saving: "Salvamento",
        defaultFolder: "Imagens/Screenshots (padrão)",
        folderReset: "Usar Imagens/Screenshots",
        folderCaption: "As capturas da tela inteira vão para cá. A janela de salvar abre na última pasta usada.",
        exampleFormat: "Exemplo: %@",
        patternCaption: "{…} contém um formato de data, como {yyyy-MM-dd HH.mm.ss}; {n} é um número sequencial.",
        jpegQuality: "Qualidade do JPEG",
        behavior: "Comportamento",
        autoCopy: "Também copiar para a área de transferência ao salvar ou imprimir",
        notify: "Mostrar uma confirmação depois de copiar e salvar",
        keepSelection: "Manter a posição da área selecionada",
        magnifier: "Mostrar a lupa durante a seleção",
        print: "Imprimir",
        openInPreview: "Abrir na Pré-Visualização",
        sizeHintFormat: "Tamanho %d",
        textSizeHintFormat: "Tamanho do texto %d",
        saveFailed: "Não foi possível salvar a captura",
        saveTitle: "Salvar captura de tela"
    )

    static let tr = ShotStrings(
        summary: "Bir alan seçin, üzerine çizin, sonra kopyalayın, kaydedin veya yazdırın",
        intro: "Ekran donar, bir alan seçmek için sürüklersiniz, üzerine çizer ve kopyalar, kaydeder veya yazdırırsınız. ⌘A veya çift tıklama tüm ekranı seçer, Esc iptal eder. Ekran görüntüleri bu Mac’ten asla çıkmaz.",
        fullScreenCaption: "Alan seçmeden tüm ekranları doğrudan varsayılan klasöre kaydeder.",
        systemTitle: "macOS ekran görüntüsü kısayolları",
        systemOn: "macOS kendi ekran görüntüsü kısayollarına hâlâ yanıt veriyor (⇧⌘3, ⇧⌘4, ⇧⌘5). Ekran görüntülerini Vorssaint’e bırakmak için bunları Sistem Ayarları › Klavye › Klavye Kestirmeleri › Ekran Resimleri bölümünden kapatın. Vorssaint bunları sizin yerinize değiştirmez.",
        systemOff: "macOS ekran görüntüsü kısayolları kapalı.",
        systemOpen: "Klavye ayarlarını aç",
        saving: "Kaydetme",
        defaultFolder: "Resimler/Screenshots (varsayılan)",
        folderReset: "Resimler/Screenshots kullan",
        folderCaption: "Tam ekran kayıtları buraya gider. Kaydetme penceresi son kaydettiğiniz klasörde açılır.",
        exampleFormat: "Örnek: %@",
        patternCaption: "{…} içinde {yyyy-MM-dd HH.mm.ss} gibi bir tarih biçimi bulunur; {n} artan bir sayıdır.",
        jpegQuality: "JPEG kalitesi",
        behavior: "Davranış",
        autoCopy: "Kaydederken veya yazdırırken panoya da kopyala",
        notify: "Kopyalama ve kaydetmeden sonra onay göster",
        keepSelection: "Seçili alanın konumunu koru",
        magnifier: "Seçim sırasında büyüteci göster",
        print: "Yazdır",
        openInPreview: "Önizleme’de aç",
        sizeHintFormat: "Boyut %d",
        textSizeHintFormat: "Metin boyutu %d",
        saveFailed: "Ekran görüntüsü kaydedilemedi",
        saveTitle: "Ekran görüntüsünü kaydet"
    )

    static let ru = ShotStrings(
        summary: "Выделите область, нарисуйте на ней, затем скопируйте, сохраните или распечатайте",
        intro: "Экран замирает, вы выделяете область, рисуете на ней, а затем копируете, сохраняете или печатаете. ⌘A или двойной щелчок выбирает весь экран, Esc отменяет. Снимки никогда не покидают этот Mac.",
        fullScreenCaption: "Сохраняет все экраны сразу в папку по умолчанию, без выбора области.",
        systemTitle: "Сочетания клавиш macOS для снимков экрана",
        systemOn: "macOS по-прежнему отвечает на собственные сочетания для снимков экрана (⇧⌘3, ⇧⌘4, ⇧⌘5). Чтобы оставить снимки Vorssaint, отключите их в «Системные настройки» › «Клавиатура» › «Сочетания клавиш» › «Снимки экрана». Vorssaint не меняет их за вас.",
        systemOff: "Сочетания клавиш macOS для снимков экрана отключены.",
        systemOpen: "Открыть настройки клавиатуры",
        saving: "Сохранение",
        defaultFolder: "Изображения/Screenshots (по умолчанию)",
        folderReset: "Использовать Изображения/Screenshots",
        folderCaption: "Снимки всего экрана сохраняются сюда. Окно сохранения открывается в папке, куда вы сохраняли в последний раз.",
        exampleFormat: "Пример: %@",
        patternCaption: "{…} содержит формат даты, например {yyyy-MM-dd HH.mm.ss}; {n} обозначает порядковый номер.",
        jpegQuality: "Качество JPEG",
        behavior: "Поведение",
        autoCopy: "Также копировать в буфер обмена при сохранении и печати",
        notify: "Показывать подтверждение после копирования и сохранения",
        keepSelection: "Запоминать положение выделенной области",
        magnifier: "Показывать лупу при выделении",
        print: "Печать",
        openInPreview: "Открыть в «Просмотре»",
        sizeHintFormat: "Размер %d",
        textSizeHintFormat: "Размер текста %d",
        saveFailed: "Не удалось сохранить снимок экрана",
        saveTitle: "Сохранить снимок экрана"
    )

    static let es = ShotStrings(
        summary: "Selecciona un área, dibuja sobre ella y luego cópiala, guárdala o imprímela",
        intro: "La pantalla se congela, arrastras para seleccionar un área, dibujas sobre ella y luego la copias, guardas o imprimes. ⌘A o un doble clic selecciona toda la pantalla, Esc cancela. Las capturas nunca salen de este Mac.",
        fullScreenCaption: "Guarda todas las pantallas directamente en la carpeta predeterminada, sin seleccionar un área.",
        systemTitle: "Atajos de captura de macOS",
        systemOn: "macOS sigue respondiendo a sus propios atajos de captura (⇧⌘3, ⇧⌘4, ⇧⌘5). Para dejar las capturas a Vorssaint, desactívalos en Ajustes del Sistema › Teclado › Funciones rápidas de teclado › Capturas de pantalla. Vorssaint no los cambia por ti.",
        systemOff: "Los atajos de captura de macOS están desactivados.",
        systemOpen: "Abrir ajustes de Teclado",
        saving: "Guardado",
        defaultFolder: "Imágenes/Screenshots (predeterminada)",
        folderReset: "Usar Imágenes/Screenshots",
        folderCaption: "Las capturas de pantalla completa van aquí. El diálogo de guardado se abre en la última carpeta usada.",
        exampleFormat: "Ejemplo: %@",
        patternCaption: "{…} contiene un formato de fecha como {yyyy-MM-dd HH.mm.ss}; {n} es un número consecutivo.",
        jpegQuality: "Calidad de JPEG",
        behavior: "Comportamiento",
        autoCopy: "Copiar también al portapapeles al guardar o imprimir",
        notify: "Mostrar una confirmación después de copiar y guardar",
        keepSelection: "Mantener la posición del área seleccionada",
        magnifier: "Mostrar la lupa al seleccionar",
        print: "Imprimir",
        openInPreview: "Abrir en Vista Previa",
        sizeHintFormat: "Tamaño %d",
        textSizeHintFormat: "Tamaño del texto %d",
        saveFailed: "No se pudo guardar la captura",
        saveTitle: "Guardar captura de pantalla"
    )

    static let sk = ShotStrings(
        summary: "Vyberte oblasť, kreslite na ňu a potom ju skopírujte, uložte alebo vytlačte",
        intro: "Obrazovka zamrzne, ťahaním vyberiete oblasť, kreslíte na ňu a potom ju skopírujete, uložíte alebo vytlačíte. ⌘A alebo dvojité kliknutie vyberie celý displej, Esc zruší. Snímky nikdy neopustia tento Mac.",
        fullScreenCaption: "Uloží všetky displeje priamo do predvoleného priečinka bez výberu oblasti.",
        systemTitle: "Skratky snímok obrazovky v macOS",
        systemOn: "macOS stále reaguje na vlastné skratky snímok obrazovky (⇧⌘3, ⇧⌘4, ⇧⌘5). Ak chcete snímky prenechať aplikácii Vorssaint, vypnite ich v Systémové nastavenia › Klávesnica › Klávesové skratky › Snímky obrazovky. Vorssaint ich za vás nemení.",
        systemOff: "Skratky snímok obrazovky v macOS sú vypnuté.",
        systemOpen: "Otvoriť nastavenia klávesnice",
        saving: "Ukladanie",
        defaultFolder: "Obrázky/Screenshots (predvolené)",
        folderReset: "Použiť Obrázky/Screenshots",
        folderCaption: "Sem sa ukladajú snímky celej obrazovky. Dialóg uloženia sa otvorí v priečinku, kam ste ukladali naposledy.",
        exampleFormat: "Príklad: %@",
        patternCaption: "{…} obsahuje formát dátumu, napríklad {yyyy-MM-dd HH.mm.ss}; {n} je poradové číslo.",
        jpegQuality: "Kvalita JPEG",
        behavior: "Správanie",
        autoCopy: "Pri ukladaní alebo tlači skopírovať aj do schránky",
        notify: "Zobraziť potvrdenie po skopírovaní a uložení",
        keepSelection: "Zachovať polohu vybranej oblasti",
        magnifier: "Zobraziť lupu počas výberu",
        print: "Tlačiť",
        openInPreview: "Otvoriť v Náhľade",
        sizeHintFormat: "Veľkosť %d",
        textSizeHintFormat: "Veľkosť textu %d",
        saveFailed: "Snímku obrazovky sa nepodarilo uložiť",
        saveTitle: "Uložiť snímku obrazovky"
    )

    static let de = ShotStrings(
        summary: "Bereich auswählen, darauf zeichnen, dann kopieren, sichern oder drucken",
        intro: "Der Bildschirm friert ein, du ziehst einen Bereich auf, zeichnest darauf und kopierst, sicherst oder druckst ihn. ⌘A oder ein Doppelklick wählt den ganzen Bildschirm, Esc bricht ab. Bildschirmfotos verlassen diesen Mac nie.",
        fullScreenCaption: "Sichert alle Bildschirme direkt im Standardordner, ohne einen Bereich auszuwählen.",
        systemTitle: "macOS-Kurzbefehle für Bildschirmfotos",
        systemOn: "macOS reagiert weiterhin auf seine eigenen Kurzbefehle für Bildschirmfotos (⇧⌘3, ⇧⌘4, ⇧⌘5). Um Bildschirmfotos Vorssaint zu überlassen, deaktiviere sie in Systemeinstellungen › Tastatur › Tastaturkurzbefehle › Bildschirmfotos. Vorssaint ändert sie nicht für dich.",
        systemOff: "Die macOS-Kurzbefehle für Bildschirmfotos sind deaktiviert.",
        systemOpen: "Tastatureinstellungen öffnen",
        saving: "Sichern",
        defaultFolder: "Bilder/Screenshots (Standard)",
        folderReset: "Bilder/Screenshots verwenden",
        folderCaption: "Hier landen Aufnahmen des ganzen Bildschirms. Der Sichern-Dialog öffnet sich im zuletzt verwendeten Ordner.",
        exampleFormat: "Beispiel: %@",
        patternCaption: "{…} enthält ein Datumsformat wie {yyyy-MM-dd HH.mm.ss}; {n} ist eine fortlaufende Nummer.",
        jpegQuality: "JPEG-Qualität",
        behavior: "Verhalten",
        autoCopy: "Beim Sichern oder Drucken auch in die Zwischenablage kopieren",
        notify: "Nach dem Kopieren und Sichern eine Bestätigung anzeigen",
        keepSelection: "Position des ausgewählten Bereichs beibehalten",
        magnifier: "Lupe beim Auswählen anzeigen",
        print: "Drucken",
        openInPreview: "In Vorschau öffnen",
        sizeHintFormat: "Größe %d",
        textSizeHintFormat: "Textgröße %d",
        saveFailed: "Das Bildschirmfoto konnte nicht gesichert werden",
        saveTitle: "Bildschirmfoto sichern"
    )

    static let fr = ShotStrings(
        summary: "Sélectionnez une zone, dessinez dessus, puis copiez, enregistrez ou imprimez",
        intro: "L’écran se fige, vous faites glisser pour sélectionner une zone, vous dessinez dessus, puis vous la copiez, l’enregistrez ou l’imprimez. ⌘A ou un double-clic sélectionne tout l’écran, Échap annule. Les captures ne quittent jamais ce Mac.",
        fullScreenCaption: "Enregistre tous les écrans directement dans le dossier par défaut, sans sélectionner de zone.",
        systemTitle: "Raccourcis de capture de macOS",
        systemOn: "macOS répond toujours à ses propres raccourcis de capture (⇧⌘3, ⇧⌘4, ⇧⌘5). Pour laisser les captures à Vorssaint, désactivez-les dans Réglages Système › Clavier › Raccourcis clavier › Captures d’écran. Vorssaint ne les modifie pas à votre place.",
        systemOff: "Les raccourcis de capture de macOS sont désactivés.",
        systemOpen: "Ouvrir les réglages Clavier",
        saving: "Enregistrement",
        defaultFolder: "Images/Screenshots (par défaut)",
        folderReset: "Utiliser Images/Screenshots",
        folderCaption: "Les captures de l’écran entier vont ici. La fenêtre d’enregistrement s’ouvre dans le dernier dossier utilisé.",
        exampleFormat: "Exemple\u{00A0}: %@",
        patternCaption: "{…} contient un format de date comme {yyyy-MM-dd HH.mm.ss}\u{00A0}; {n} est un numéro croissant.",
        jpegQuality: "Qualité JPEG",
        behavior: "Comportement",
        autoCopy: "Copier aussi dans le presse-papiers lors de l’enregistrement ou de l’impression",
        notify: "Afficher une confirmation après la copie et l’enregistrement",
        keepSelection: "Conserver la position de la zone sélectionnée",
        magnifier: "Afficher la loupe pendant la sélection",
        print: "Imprimer",
        openInPreview: "Ouvrir dans Aperçu",
        sizeHintFormat: "Taille %d",
        textSizeHintFormat: "Taille du texte %d",
        saveFailed: "Impossible d’enregistrer la capture",
        saveTitle: "Enregistrer la capture d’écran"
    )

    static let it = ShotStrings(
        summary: "Seleziona un’area, disegnaci sopra, poi copiala, salvala o stampala",
        intro: "Lo schermo si blocca, trascini per selezionare un’area, ci disegni sopra e poi la copi, la salvi o la stampi. ⌘A o un doppio clic seleziona l’intero schermo, Esc annulla. Le istantanee non lasciano mai questo Mac.",
        fullScreenCaption: "Salva tutti gli schermi direttamente nella cartella predefinita, senza selezionare un’area.",
        systemTitle: "Abbreviazioni di macOS per le istantanee",
        systemOn: "macOS risponde ancora alle proprie abbreviazioni per le istantanee (⇧⌘3, ⇧⌘4, ⇧⌘5). Per lasciare le istantanee a Vorssaint, disattivale in Impostazioni di Sistema › Tastiera › Abbreviazioni da tastiera › Istantanee schermo. Vorssaint non le modifica al posto tuo.",
        systemOff: "Le abbreviazioni di macOS per le istantanee sono disattivate.",
        systemOpen: "Apri impostazioni Tastiera",
        saving: "Salvataggio",
        defaultFolder: "Immagini/Screenshots (predefinita)",
        folderReset: "Usa Immagini/Screenshots",
        folderCaption: "Le istantanee dell’intero schermo finiscono qui. La finestra di salvataggio si apre nell’ultima cartella usata.",
        exampleFormat: "Esempio: %@",
        patternCaption: "{…} contiene un formato di data come {yyyy-MM-dd HH.mm.ss}; {n} è un numero progressivo.",
        jpegQuality: "Qualità JPEG",
        behavior: "Comportamento",
        autoCopy: "Copia anche negli appunti quando salvi o stampi",
        notify: "Mostra una conferma dopo aver copiato e salvato",
        keepSelection: "Mantieni la posizione dell’area selezionata",
        magnifier: "Mostra la lente durante la selezione",
        print: "Stampa",
        openInPreview: "Apri in Anteprima",
        sizeHintFormat: "Dimensione %d",
        textSizeHintFormat: "Dimensione testo %d",
        saveFailed: "Impossibile salvare l’istantanea",
        saveTitle: "Salva istantanea"
    )

    static let ja = ShotStrings(
        summary: "範囲を選択して書き込み、コピー、保存、プリントできます",
        intro: "画面が静止し、ドラッグで範囲を選択して書き込み、コピー、保存、プリントできます。⌘Aまたはダブルクリックでディスプレイ全体を選択し、Escでキャンセルします。スクリーンショットがこのMacの外に出ることはありません。",
        fullScreenCaption: "範囲を選択せずに、すべてのディスプレイをデフォルトのフォルダに直接保存します。",
        systemTitle: "macOSのスクリーンショットのショートカット",
        systemOn: "macOSは自身のスクリーンショットのショートカット（⇧⌘3、⇧⌘4、⇧⌘5）にも反応します。スクリーンショットをVorssaintに任せるには、システム設定 › キーボード › キーボードショートカット › スクリーンショットでオフにしてください。Vorssaintが代わりに変更することはありません。",
        systemOff: "macOSのスクリーンショットのショートカットはオフです。",
        systemOpen: "キーボード設定を開く",
        saving: "保存",
        defaultFolder: "ピクチャ/Screenshots（デフォルト）",
        folderReset: "ピクチャ/Screenshotsを使用",
        folderCaption: "画面全体の保存先です。保存ダイアログは最後に保存したフォルダで開きます。",
        exampleFormat: "例: %@",
        patternCaption: "{…}には{yyyy-MM-dd HH.mm.ss}のような日付書式を入れます。{n}は連番です。",
        jpegQuality: "JPEGの品質",
        behavior: "動作",
        autoCopy: "保存またはプリントするときにクリップボードにもコピー",
        notify: "コピーと保存の後に確認を表示",
        keepSelection: "選択範囲の位置を保持",
        magnifier: "選択中に拡大鏡を表示",
        print: "プリント",
        openInPreview: "プレビューで開く",
        sizeHintFormat: "サイズ %d",
        textSizeHintFormat: "文字サイズ %d",
        saveFailed: "スクリーンショットを保存できませんでした",
        saveTitle: "スクリーンショットを保存"
    )

    static let ko = ShotStrings(
        summary: "영역을 선택해 그린 다음 복사, 저장 또는 프린트합니다",
        intro: "화면이 멈추면 드래그하여 영역을 선택하고 그 위에 그린 다음 복사, 저장 또는 프린트합니다. ⌘A 또는 이중 클릭으로 디스플레이 전체를 선택하고 Esc로 취소합니다. 스크린샷은 이 Mac을 벗어나지 않습니다.",
        fullScreenCaption: "영역을 선택하지 않고 모든 디스플레이를 기본 폴더에 바로 저장합니다.",
        systemTitle: "macOS 스크린샷 단축키",
        systemOn: "macOS가 여전히 자체 스크린샷 단축키(⇧⌘3, ⇧⌘4, ⇧⌘5)에 반응합니다. 스크린샷을 Vorssaint에 맡기려면 시스템 설정 › 키보드 › 키보드 단축키 › 스크린샷에서 끄십시오. Vorssaint가 대신 변경하지 않습니다.",
        systemOff: "macOS 스크린샷 단축키가 꺼져 있습니다.",
        systemOpen: "키보드 설정 열기",
        saving: "저장",
        defaultFolder: "그림/Screenshots(기본값)",
        folderReset: "그림/Screenshots 사용",
        folderCaption: "전체 화면 저장은 여기에 저장됩니다. 저장 대화상자는 마지막으로 저장한 폴더에서 열립니다.",
        exampleFormat: "예: %@",
        patternCaption: "{…}에는 {yyyy-MM-dd HH.mm.ss} 같은 날짜 형식이 들어갑니다. {n}은 일련번호입니다.",
        jpegQuality: "JPEG 품질",
        behavior: "동작",
        autoCopy: "저장하거나 프린트할 때 클립보드에도 복사",
        notify: "복사 및 저장 후 확인 표시",
        keepSelection: "선택한 영역의 위치 유지",
        magnifier: "선택하는 동안 확대경 표시",
        print: "프린트",
        openInPreview: "미리보기에서 열기",
        sizeHintFormat: "크기 %d",
        textSizeHintFormat: "텍스트 크기 %d",
        saveFailed: "스크린샷을 저장할 수 없습니다",
        saveTitle: "스크린샷 저장"
    )

    static let zhHans = ShotStrings(
        summary: "选择一个区域，在上面绘制，然后拷贝、存储或打印",
        intro: "屏幕会冻结，拖移选择一个区域，在上面绘制，然后拷贝、存储或打印。⌘A 或双击可选择整个显示器，Esc 取消。截屏绝不会离开这台 Mac。",
        fullScreenCaption: "无需选择区域，直接将所有显示器存储到默认文件夹。",
        systemTitle: "macOS 截屏快捷键",
        systemOn: "macOS 仍会响应自己的截屏快捷键（⇧⌘3、⇧⌘4、⇧⌘5）。要将截屏交给 Vorssaint，请在“系统设置”›“键盘”›“键盘快捷键”›“截屏”中关闭它们。Vorssaint 不会替你更改。",
        systemOff: "macOS 截屏快捷键已关闭。",
        systemOpen: "打开键盘设置",
        saving: "存储",
        defaultFolder: "图片/Screenshots（默认）",
        folderReset: "使用 图片/Screenshots",
        folderCaption: "全屏截图存储在这里。存储对话框会在上次存储的文件夹中打开。",
        exampleFormat: "示例：%@",
        patternCaption: "{…} 中是日期格式，例如 {yyyy-MM-dd HH.mm.ss}；{n} 是递增的编号。",
        jpegQuality: "JPEG 质量",
        behavior: "行为",
        autoCopy: "存储或打印时也拷贝到剪贴板",
        notify: "拷贝和存储后显示确认",
        keepSelection: "保留所选区域的位置",
        magnifier: "选择时显示放大镜",
        print: "打印",
        openInPreview: "在“预览”中打开",
        sizeHintFormat: "大小 %d",
        textSizeHintFormat: "文字大小 %d",
        saveFailed: "无法存储截屏",
        saveTitle: "存储截屏"
    )

    static let zhTW = ShotStrings(
        summary: "選取一個區域，在上面繪圖，然後拷貝、儲存或列印",
        intro: "螢幕會凍結，拖移選取一個區域，在上面繪圖，然後拷貝、儲存或列印。⌘A 或按兩下可選取整個顯示器，Esc 取消。截圖絕不會離開這部 Mac。",
        fullScreenCaption: "不需選取區域，直接將所有顯示器儲存到預設檔案夾。",
        systemTitle: "macOS 截圖快速鍵",
        systemOn: "macOS 仍會回應自己的截圖快速鍵（⇧⌘3、⇧⌘4、⇧⌘5）。若要將截圖交給 Vorssaint，請在「系統設定」›「鍵盤」›「鍵盤快速鍵」›「截圖」中關閉它們。Vorssaint 不會替你更改。",
        systemOff: "macOS 截圖快速鍵已關閉。",
        systemOpen: "打開鍵盤設定",
        saving: "儲存",
        defaultFolder: "圖片/Screenshots（預設）",
        folderReset: "使用 圖片/Screenshots",
        folderCaption: "全螢幕截圖會儲存在這裡。儲存對話框會在上次儲存的檔案夾中打開。",
        exampleFormat: "範例：%@",
        patternCaption: "{…} 中是日期格式，例如 {yyyy-MM-dd HH.mm.ss}；{n} 是遞增的編號。",
        jpegQuality: "JPEG 品質",
        behavior: "行為",
        autoCopy: "儲存或列印時也拷貝到剪貼板",
        notify: "拷貝和儲存後顯示確認",
        keepSelection: "保留所選區域的位置",
        magnifier: "選取時顯示放大鏡",
        print: "列印",
        openInPreview: "在「預覽程式」中打開",
        sizeHintFormat: "大小 %d",
        textSizeHintFormat: "文字大小 %d",
        saveFailed: "無法儲存截圖",
        saveTitle: "儲存截圖"
    )

    static let zhHK = ShotStrings(
        summary: "選取一個範圍，在上面繪圖，然後拷貝、儲存或列印",
        intro: "螢幕會凍結，拖移選取一個範圍，在上面繪圖，然後拷貝、儲存或列印。⌘A 或按兩下可選取整個顯示器，Esc 取消。截圖絕不會離開這部 Mac。",
        fullScreenCaption: "無須選取範圍，直接將所有顯示器儲存到預設資料夾。",
        systemTitle: "macOS 截圖快捷鍵",
        systemOn: "macOS 仍會回應自己的截圖快捷鍵（⇧⌘3、⇧⌘4、⇧⌘5）。如要將截圖交給 Vorssaint，請在「系統設定」›「鍵盤」›「鍵盤快捷鍵」›「截圖」中關閉它們。Vorssaint 不會替你更改。",
        systemOff: "macOS 截圖快捷鍵已關閉。",
        systemOpen: "開啟鍵盤設定",
        saving: "儲存",
        defaultFolder: "圖片/Screenshots（預設）",
        folderReset: "使用 圖片/Screenshots",
        folderCaption: "全螢幕截圖會儲存在這裡。儲存對話框會在上次儲存的資料夾中開啟。",
        exampleFormat: "例子：%@",
        patternCaption: "{…} 中是日期格式，例如 {yyyy-MM-dd HH.mm.ss}；{n} 是遞增的編號。",
        jpegQuality: "JPEG 質素",
        behavior: "行為",
        autoCopy: "儲存或列印時也拷貝到剪貼板",
        notify: "拷貝和儲存後顯示確認",
        keepSelection: "保留所選範圍的位置",
        magnifier: "選取時顯示放大鏡",
        print: "列印",
        openInPreview: "在「預覽程式」中開啟",
        sizeHintFormat: "大小 %d",
        textSizeHintFormat: "文字大小 %d",
        saveFailed: "無法儲存截圖",
        saveTitle: "儲存截圖"
    )

    static let uk = ShotStrings(
        summary: "Виділіть область, намалюйте на ній, а потім скопіюйте, збережіть або надрукуйте",
        intro: "Екран завмирає, ви перетягуєте, щоб виділити область, малюєте на ній, а потім копіюєте, зберігаєте або друкуєте. ⌘A або подвійне клацання вибирає весь дисплей, Esc скасовує. Знімки ніколи не залишають цей Mac.",
        fullScreenCaption: "Зберігає всі дисплеї одразу до типової папки, без вибору області.",
        systemTitle: "Сполучення клавіш macOS для знімків екрана",
        systemOn: "macOS досі відповідає на власні сполучення клавіш для знімків екрана (⇧⌘3, ⇧⌘4, ⇧⌘5). Щоб залишити знімки Vorssaint, вимкніть їх у «Системні параметри» › «Клавіатура» › «Клавіатурні скорочення» › «Знімки екрана». Vorssaint не змінює їх за вас.",
        systemOff: "Сполучення клавіш macOS для знімків екрана вимкнено.",
        systemOpen: "Відкрити параметри клавіатури",
        saving: "Збереження",
        defaultFolder: "Зображення/Screenshots (типово)",
        folderReset: "Використовувати Зображення/Screenshots",
        folderCaption: "Знімки всього екрана зберігаються сюди. Вікно збереження відкривається в папці, куди ви зберігали востаннє.",
        exampleFormat: "Приклад: %@",
        patternCaption: "{…} містить формат дати, наприклад {yyyy-MM-dd HH.mm.ss}; {n} позначає порядковий номер.",
        jpegQuality: "Якість JPEG",
        behavior: "Поведінка",
        autoCopy: "Також копіювати в буфер обміну під час збереження або друку",
        notify: "Показувати підтвердження після копіювання та збереження",
        keepSelection: "Зберігати положення виділеної області",
        magnifier: "Показувати лупу під час виділення",
        print: "Друк",
        openInPreview: "Відкрити в Оглядачі",
        sizeHintFormat: "Розмір %d",
        textSizeHintFormat: "Розмір тексту %d",
        saveFailed: "Не вдалося зберегти знімок екрана",
        saveTitle: "Зберегти знімок екрана"
    )
}
