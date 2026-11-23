// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the rows paste as plain text grows once its master toggle is
/// on. Separate from the global `Strings` struct so a per-feature catalog
/// stays its own small file.
struct PastePlainStrings {
    /// The shortcut row and the Command Bar entry: the hotkey restores and
    /// pastes the formatting the automatic strip took out.
    let pasteWithFormatting: String
    /// The Command Bar action that strips the current clipboard on demand.
    let clearFormatting: String
    let cleanInvisibleToggle: String
    let cleanInvisibleCaption: String
    let trimWhitespaceToggle: String
    let trimWhitespaceCaption: String
    let cleanLinksToggle: String
    let cleanLinksCaption: String
    let excludedListTitle: String
    let excludedAddButton: String
    let excludedRemoveButton: String
    let excludedCaption: String
}

extension FeatureStrings {
    static func pastePlain(_ language: AppLanguage) -> PastePlainStrings {
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

extension PastePlainStrings {
    static let enUS = PastePlainStrings(
        pasteWithFormatting: "Paste with original formatting",
        clearFormatting: "Clear formatting now",
        cleanInvisibleToggle: "Remove invisible characters",
        cleanInvisibleCaption: "Takes zero-width spaces, word joiners, soft hyphens and AI watermark marks out of the plain text.",
        trimWhitespaceToggle: "Trim leading and trailing whitespace",
        trimWhitespaceCaption: "Drops the spaces and line breaks at the start and end of the copied text.",
        cleanLinksToggle: "Remove tracking parameters from links",
        cleanLinksCaption: "Applies the same tracking-parameter cleanup to a copy that is a single link.",
        excludedListTitle: "Apps to skip",
        excludedAddButton: "Add an app…",
        excludedRemoveButton: "Remove",
        excludedCaption: "Copies from these apps keep their formatting. Nothing is ever stripped from files, images, PDFs or password managers."
    )

    static let ptBR = PastePlainStrings(
        pasteWithFormatting: "Colar com a formatação original",
        clearFormatting: "Limpar formatação agora",
        cleanInvisibleToggle: "Remover caracteres invisíveis",
        cleanInvisibleCaption: "Tira do texto puro os espaços de largura zero, separadores de palavra, hífens opcionais e marcas d’água de IA.",
        trimWhitespaceToggle: "Cortar espaços no início e no fim",
        trimWhitespaceCaption: "Descarta os espaços e quebras de linha no começo e no fim do texto copiado.",
        cleanLinksToggle: "Remover parâmetros de rastreamento dos links",
        cleanLinksCaption: "Aplica a mesma limpeza de rastreamento a uma cópia que seja um único link.",
        excludedListTitle: "Apps para pular",
        excludedAddButton: "Adicionar app…",
        excludedRemoveButton: "Remover",
        excludedCaption: "Cópias desses apps mantêm a formatação. Nada é removido de arquivos, imagens, PDFs ou gerenciadores de senhas."
    )

    static let tr = PastePlainStrings(
        pasteWithFormatting: "Orijinal biçimlendirmeyle yapıştır",
        clearFormatting: "Biçimlendirmeyi şimdi temizle",
        cleanInvisibleToggle: "Görünmez karakterleri kaldır",
        cleanInvisibleCaption: "Düz metinden sıfır genişlikli boşlukları, sözcük birleştiricileri, isteğe bağlı tireleri ve yapay zekâ filigranlarını kaldırır.",
        trimWhitespaceToggle: "Baştaki ve sondaki boşlukları kırp",
        trimWhitespaceCaption: "Kopyalanan metnin başındaki ve sonundaki boşluk ve satır sonlarını atar.",
        cleanLinksToggle: "Bağlantılardan izleme parametrelerini kaldır",
        cleanLinksCaption: "Tek bir bağlantı olan kopyalara aynı izleme parametresi temizliğini uygular.",
        excludedListTitle: "Atlanacak uygulamalar",
        excludedAddButton: "Uygulama ekle…",
        excludedRemoveButton: "Kaldır",
        excludedCaption: "Bu uygulamalardan kopyalananlar biçimlendirmesini korur. Dosyalardan, görsellerden, PDF’lerden ve parola yöneticilerinden hiçbir şey ayıklanmaz."
    )

    static let ru = PastePlainStrings(
        pasteWithFormatting: "Вставить с исходным форматированием",
        clearFormatting: "Убрать форматирование сейчас",
        cleanInvisibleToggle: "Удалять невидимые символы",
        cleanInvisibleCaption: "Убирает из простого текста нулевые пробелы, соединители слов, мягкие переносы и водяные знаки ИИ.",
        trimWhitespaceToggle: "Обрезать пробелы в начале и в конце",
        trimWhitespaceCaption: "Убирает пробелы и переводы строк в начале и в конце скопированного текста.",
        cleanLinksToggle: "Удалять трекинг-параметры из ссылок",
        cleanLinksCaption: "Применяет ту же очистку от трекинга к копии, которая является единственной ссылкой.",
        excludedListTitle: "Приложения без изменений",
        excludedAddButton: "Добавить приложение…",
        excludedRemoveButton: "Удалить",
        excludedCaption: "Копии из этих приложений сохраняют форматирование. Файлы, изображения, PDF и менеджеры паролей никогда не затрагиваются."
    )

    static let es = PastePlainStrings(
        pasteWithFormatting: "Pegar con el formato original",
        clearFormatting: "Quitar el formato ahora",
        cleanInvisibleToggle: "Eliminar caracteres invisibles",
        cleanInvisibleCaption: "Quita del texto sin formato los espacios de ancho cero, los separadores de palabras, los guiones opcionales y las marcas de agua de IA.",
        trimWhitespaceToggle: "Recortar espacios al principio y al final",
        trimWhitespaceCaption: "Descarta los espacios y saltos de línea del principio y del final del texto copiado.",
        cleanLinksToggle: "Eliminar parámetros de rastreo de los enlaces",
        cleanLinksCaption: "Aplica la misma limpieza de rastreo a una copia que sea un único enlace.",
        excludedListTitle: "Apps que se saltan",
        excludedAddButton: "Añadir app…",
        excludedRemoveButton: "Quitar",
        excludedCaption: "Las copias de estas apps conservan su formato. Nunca se quita nada de archivos, imágenes, PDF ni gestores de contraseñas."
    )

    static let sk = PastePlainStrings(
        pasteWithFormatting: "Prilepiť s pôvodným formátovaním",
        clearFormatting: "Odstrániť formátovanie",
        cleanInvisibleToggle: "Odstraňovať neviditeľné znaky",
        cleanInvisibleCaption: "Z čistého textu odstraňuje znaky s nulovou šírkou, spájače slov, mäkké delenia a vodoznaky AI.",
        trimWhitespaceToggle: "Orezať medzery na začiatku a konci",
        trimWhitespaceCaption: "Odstráni medzery a konce riadkov na začiatku a konci skopírovaného textu.",
        cleanLinksToggle: "Odstraňovať sledovacie parametre z odkazov",
        cleanLinksCaption: "Na kópiu, ktorá je jediným odkazom, použije rovnaké čistenie sledovacích parametrov.",
        excludedListTitle: "Apky, ktoré preskočiť",
        excludedAddButton: "Pridať aplikáciu…",
        excludedRemoveButton: "Odstrániť",
        excludedCaption: "Kópie z týchto apiek si ponechajú formátovanie. Zo súborov, obrázkov, PDF a správcov hesiel sa nič neodstraňuje."
    )

    static let de = PastePlainStrings(
        pasteWithFormatting: "Mit ursprünglicher Formatierung einsetzen",
        clearFormatting: "Formatierung jetzt entfernen",
        cleanInvisibleToggle: "Unsichtbare Zeichen entfernen",
        cleanInvisibleCaption: "Nimmt aus dem reinen Text Nullbreiten-Leerzeichen, Wortverbinder, weiche Trennstriche und KI-Wasserzeichen heraus.",
        trimWhitespaceToggle: "Leerzeichen am Anfang und Ende entfernen",
        trimWhitespaceCaption: "Entfernt Leerzeichen und Zeilenumbrüche am Anfang und Ende des kopierten Texts.",
        cleanLinksToggle: "Tracking-Parameter aus Links entfernen",
        cleanLinksCaption: "Wendet dieselbe Tracking-Bereinigung auf eine Kopie an, die aus einem einzelnen Link besteht.",
        excludedListTitle: "Apps, die übersprungen werden",
        excludedAddButton: "App hinzufügen…",
        excludedRemoveButton: "Entfernen",
        excludedCaption: "Kopien aus diesen Apps behalten ihre Formatierung. Von Dateien, Bildern, PDFs und Passwortmanagern wird nie etwas entfernt."
    )

    static let fr = PastePlainStrings(
        pasteWithFormatting: "Coller avec la mise en forme d’origine",
        clearFormatting: "Effacer la mise en forme maintenant",
        cleanInvisibleToggle: "Supprimer les caractères invisibles",
        cleanInvisibleCaption: "Retire du texte brut les espaces de largeur nulle, les joncteurs de mots, les traits d’union conditionnels et les filigranes d’IA.",
        trimWhitespaceToggle: "Supprimer les espaces en début et fin",
        trimWhitespaceCaption: "Retire les espaces et sauts de ligne au début et à la fin du texte copié.",
        cleanLinksToggle: "Supprimer les paramètres de suivi des liens",
        cleanLinksCaption: "Applique le même nettoyage de suivi à une copie formée d’un seul lien.",
        excludedListTitle: "Apps à ignorer",
        excludedAddButton: "Ajouter une app…",
        excludedRemoveButton: "Retirer",
        excludedCaption: "Les copies de ces apps gardent leur mise en forme. Rien n’est jamais retiré des fichiers, images, PDF ou gestionnaires de mots de passe."
    )

    static let it = PastePlainStrings(
        pasteWithFormatting: "Incolla con la formattazione originale",
        clearFormatting: "Rimuovi la formattazione ora",
        cleanInvisibleToggle: "Rimuovi i caratteri invisibili",
        cleanInvisibleCaption: "Toglie dal testo semplice gli spazi a larghezza zero, i separatori di parole, i trattini facoltativi e i watermark dell’IA.",
        trimWhitespaceToggle: "Taglia gli spazi all’inizio e alla fine",
        trimWhitespaceCaption: "Scarta gli spazi e i fine riga all’inizio e alla fine del testo copiato.",
        cleanLinksToggle: "Rimuovi i parametri di tracciamento dai link",
        cleanLinksCaption: "Applica la stessa pulizia del tracciamento a una copia formata da un solo link.",
        excludedListTitle: "App da saltare",
        excludedAddButton: "Aggiungi app…",
        excludedRemoveButton: "Rimuovi",
        excludedCaption: "Le copie di queste app conservano la formattazione. Da file, immagini, PDF e gestori di password non viene mai tolto nulla."
    )

    static let ja = PastePlainStrings(
        pasteWithFormatting: "元の書式でペースト",
        clearFormatting: "書式を今すぐ消す",
        cleanInvisibleToggle: "不可視文字を取り除く",
        cleanInvisibleCaption: "プレーンテキストから幅ゼロの空白、ワードジョイナー、ソフトハイフン、AIのウォーターマークを取り除きます。",
        trimWhitespaceToggle: "前後の空白を取り除く",
        trimWhitespaceCaption: "コピーしたテキストの先頭と末尾の空白や改行を削ります。",
        cleanLinksToggle: "リンクからトラッキングパラメータを取り除く",
        cleanLinksCaption: "1つのリンクだけのコピーには、同じトラッキングパラメータの清掃を適用します。",
        excludedListTitle: "そのまま残すApp",
        excludedAddButton: "Appを追加…",
        excludedRemoveButton: "削除",
        excludedCaption: "これらのAppでコピーしたものは書式が保たれます。ファイル・画像・PDF・パスワードマネージャの内容は一切加工しません。"
    )

    static let ko = PastePlainStrings(
        pasteWithFormatting: "원본 서식으로 붙여넣기",
        clearFormatting: "지금 서식 지우기",
        cleanInvisibleToggle: "보이지 않는 문자 제거",
        cleanInvisibleCaption: "일반 텍스트에서 폭 0 공백, 단어 연결 문자, 소프트 하이픈, AI 워터마크를 제거합니다.",
        trimWhitespaceToggle: "앞뒤 공백 잘라내기",
        trimWhitespaceCaption: "복사한 텍스트의 시작과 끝에 있는 공백과 줄바꿈을 버립니다.",
        cleanLinksToggle: "링크에서 추적 매개변수 제거",
        cleanLinksCaption: "하나의 링크로만 이루어진 복사본에 같은 추적 매개변수 정리를 적용합니다.",
        excludedListTitle: "건너뛸 앱",
        excludedAddButton: "앱 추가…",
        excludedRemoveButton: "제거",
        excludedCaption: "이 앱에서 복사한 내용은 서식이 유지됩니다. 파일, 이미지, PDF, 암호 관리자의 내용은 절대 가공하지 않습니다."
    )

    static let zhHans = PastePlainStrings(
        pasteWithFormatting: "按原格式粘贴",
        clearFormatting: "立即清除格式",
        cleanInvisibleToggle: "移除不可见字符",
        cleanInvisibleCaption: "从纯文本中移除零宽空格、词连接符、软连字符和 AI 水印字符。",
        trimWhitespaceToggle: "去除首尾空白",
        trimWhitespaceCaption: "去掉拷贝文本开头和结尾的空格与换行。",
        cleanLinksToggle: "移除链接中的跟踪参数",
        cleanLinksCaption: "对只有单个链接的拷贝应用同样的跟踪参数清理。",
        excludedListTitle: "不处理的 App",
        excludedAddButton: "添加 App…",
        excludedRemoveButton: "移除",
        excludedCaption: "这些 App 拷贝的内容会保留格式。文件、图像、PDF 和密码管理器的内容永远不会被改动。"
    )

    static let zhTW = PastePlainStrings(
        pasteWithFormatting: "以原格式貼上",
        clearFormatting: "立即清除格式",
        cleanInvisibleToggle: "移除不可見字元",
        cleanInvisibleCaption: "從純文字中移除零寬空格、文字連接符、軟連字號和 AI 浮水印字元。",
        trimWhitespaceToggle: "去除首尾空白",
        trimWhitespaceCaption: "去掉拷貝文字開頭和結尾的空格與換行。",
        cleanLinksToggle: "移除連結中的追蹤參數",
        cleanLinksCaption: "對只有單一連結的拷貝套用同樣的追蹤參數清理。",
        excludedListTitle: "不處理的 App",
        excludedAddButton: "加入 App…",
        excludedRemoveButton: "移除",
        excludedCaption: "這些 App 拷貝的內容會保留格式。檔案、影像、PDF 和密碼管理器的內容永遠不會被更動。"
    )

    static let zhHK = PastePlainStrings(
        pasteWithFormatting: "以原格式貼上",
        clearFormatting: "立即清除格式",
        cleanInvisibleToggle: "移除不可見字元",
        cleanInvisibleCaption: "從純文字中移除零寬空格、文字連接符、軟連字號和 AI 浮水印字元。",
        trimWhitespaceToggle: "去除首尾空白",
        trimWhitespaceCaption: "去掉拷貝文字開頭和結尾的空格與換行。",
        cleanLinksToggle: "移除連結中的追蹤參數",
        cleanLinksCaption: "對只有單一連結的拷貝套用同樣的追蹤參數清理。",
        excludedListTitle: "不處理的 App",
        excludedAddButton: "加入 App…",
        excludedRemoveButton: "移除",
        excludedCaption: "這些 App 拷貝的內容會保留格式。檔案、影像、PDF 和密碼管理器的內容永遠不會被更動。"
    )

    static let uk = PastePlainStrings(
        pasteWithFormatting: "Вставити з початковим форматуванням",
        clearFormatting: "Прибрати форматування зараз",
        cleanInvisibleToggle: "Видаляти невидимі символи",
        cleanInvisibleCaption: "Прибирає з простого тексту нульові пробіли, з’єднувачі слів, м’які переноси та водяні знаки ШІ.",
        trimWhitespaceToggle: "Обрізати пробіли на початку та в кінці",
        trimWhitespaceCaption: "Видаляє пробіли й розриви рядків на початку та в кінці скопійованого тексту.",
        cleanLinksToggle: "Видаляти трекінг-параметри з посилань",
        cleanLinksCaption: "Застосовує те саме очищення від трекінгу до копії, що є одним-єдиним посиланням.",
        excludedListTitle: "Програми без змін",
        excludedAddButton: "Додати програму…",
        excludedRemoveButton: "Видалити",
        excludedCaption: "Копії з цих програм зберігають форматування. Файли, зображення, PDF і менеджери паролів ніколи не змінюються."
    )
}
