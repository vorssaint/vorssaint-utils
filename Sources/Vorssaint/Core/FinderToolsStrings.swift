// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderToolsStrings {
    let title: String
    let description: String
    let open: String
    let chooseFiles: String
    let chooseFolder: String
    let emptySelection: String
    let run: String
    let name: String
    let destination: String
    let success: String
    let failure: String
    let cancel: String
    let selection: String

    static func localized(_ language: AppLanguage) -> FinderToolsStrings {
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

private extension FinderToolsStrings {
    static let enUS = FinderToolsStrings(
        title: "Finder Tools",
        description: "Run actions on files and folders selected in Finder.",
        open: "Open Finder Tools",
        chooseFiles: "Choose Files",
        chooseFolder: "Choose Folder",
        emptySelection: "Select at least one file or folder to continue.",
        run: "Run",
        name: "Name",
        destination: "Destination",
        success: "The action finished successfully.",
        failure: "The action couldn’t be completed. Try again.",
        cancel: "Cancel",
        selection: "Selection"
    )

    static let ptBR = FinderToolsStrings(
        title: "Ferramentas do Finder",
        description: "Execute ações nos arquivos e pastas selecionados no Finder.",
        open: "Abrir Ferramentas do Finder",
        chooseFiles: "Selecionar arquivos",
        chooseFolder: "Selecionar pasta",
        emptySelection: "Selecione ao menos um arquivo ou uma pasta para continuar.",
        run: "Executar",
        name: "Nome",
        destination: "Destino",
        success: "A ação foi concluída.",
        failure: "Não foi possível concluir a ação. Tente novamente.",
        cancel: "Cancelar",
        selection: "Seleção"
    )

    static let tr = FinderToolsStrings(
        title: "Finder Araçları",
        description: "Finder’da seçtiğiniz dosya ve klasörlerde işlemler yapın.",
        open: "Finder Araçlarını Aç",
        chooseFiles: "Dosyaları Seç",
        chooseFolder: "Klasör Seç",
        emptySelection: "Devam etmek için en az bir dosya veya klasör seçin.",
        run: "Çalıştır",
        name: "Ad",
        destination: "Hedef",
        success: "İşlem başarıyla tamamlandı.",
        failure: "İşlem tamamlanamadı. Yeniden deneyin.",
        cancel: "İptal",
        selection: "Seçim"
    )

    static let ru = FinderToolsStrings(
        title: "Инструменты Finder",
        description: "Выполняйте действия с выбранными в Finder файлами и папками.",
        open: "Открыть инструменты Finder",
        chooseFiles: "Выбрать файлы",
        chooseFolder: "Выбрать папку",
        emptySelection: "Выберите хотя бы один файл или папку, чтобы продолжить.",
        run: "Выполнить",
        name: "Имя",
        destination: "Место назначения",
        success: "Действие выполнено.",
        failure: "Не удалось выполнить действие. Попробуйте ещё раз.",
        cancel: "Отмена",
        selection: "Выбор"
    )

    static let es = FinderToolsStrings(
        title: "Herramientas del Finder",
        description: "Realiza acciones en los archivos y carpetas seleccionados en el Finder.",
        open: "Abrir Herramientas del Finder",
        chooseFiles: "Elegir archivos",
        chooseFolder: "Elegir carpeta",
        emptySelection: "Selecciona al menos un archivo o una carpeta para continuar.",
        run: "Ejecutar",
        name: "Nombre",
        destination: "Destino",
        success: "La acción se completó correctamente.",
        failure: "No se pudo completar la acción. Inténtalo de nuevo.",
        cancel: "Cancelar",
        selection: "Selección"
    )

    static let sk = FinderToolsStrings(
        title: "Nástroje Findera",
        description: "Spúšťajte akcie so súbormi a priečinkami vybranými vo Finderi.",
        open: "Otvoriť nástroje Findera",
        chooseFiles: "Vybrať súbory",
        chooseFolder: "Vybrať priečinok",
        emptySelection: "Pokračujte výberom aspoň jedného súboru alebo priečinka.",
        run: "Spustiť",
        name: "Názov",
        destination: "Cieľ",
        success: "Akcia sa úspešne dokončila.",
        failure: "Akciu sa nepodarilo dokončiť. Skúste to znova.",
        cancel: "Zrušiť",
        selection: "Výber"
    )

    static let de = FinderToolsStrings(
        title: "Finder-Werkzeuge",
        description: "Führe Aktionen für im Finder ausgewählte Dateien und Ordner aus.",
        open: "Finder-Werkzeuge öffnen",
        chooseFiles: "Dateien auswählen",
        chooseFolder: "Ordner auswählen",
        emptySelection: "Wähle mindestens eine Datei oder einen Ordner aus, um fortzufahren.",
        run: "Ausführen",
        name: "Name",
        destination: "Ziel",
        success: "Die Aktion wurde erfolgreich abgeschlossen.",
        failure: "Die Aktion konnte nicht abgeschlossen werden. Versuche es erneut.",
        cancel: "Abbrechen",
        selection: "Auswahl"
    )

    static let fr = FinderToolsStrings(
        title: "Outils du Finder",
        description: "Exécutez des actions sur les fichiers et dossiers sélectionnés dans le Finder.",
        open: "Ouvrir les outils du Finder",
        chooseFiles: "Choisir des fichiers",
        chooseFolder: "Choisir un dossier",
        emptySelection: "Sélectionnez au moins un fichier ou un dossier pour continuer.",
        run: "Exécuter",
        name: "Nom",
        destination: "Destination",
        success: "L’action a été effectuée.",
        failure: "Impossible d’effectuer l’action. Réessayez.",
        cancel: "Annuler",
        selection: "Sélection"
    )

    static let it = FinderToolsStrings(
        title: "Strumenti di Finder",
        description: "Esegui azioni sui file e sulle cartelle selezionati in Finder.",
        open: "Apri strumenti di Finder",
        chooseFiles: "Scegli file",
        chooseFolder: "Scegli cartella",
        emptySelection: "Seleziona almeno un file o una cartella per continuare.",
        run: "Esegui",
        name: "Nome",
        destination: "Destinazione",
        success: "L’azione è stata completata.",
        failure: "Impossibile completare l’azione. Riprova.",
        cancel: "Annulla",
        selection: "Selezione"
    )

    static let ja = FinderToolsStrings(
        title: "Finderツール",
        description: "Finderで選択したファイルやフォルダに対して操作を実行します。",
        open: "Finderツールを開く",
        chooseFiles: "ファイルを選択",
        chooseFolder: "フォルダを選択",
        emptySelection: "続けるにはファイルまたはフォルダを1つ以上選択してください。",
        run: "実行",
        name: "名前",
        destination: "保存先",
        success: "操作が完了しました。",
        failure: "操作を完了できませんでした。もう一度お試しください。",
        cancel: "キャンセル",
        selection: "選択項目"
    )

    static let ko = FinderToolsStrings(
        title: "Finder 도구",
        description: "Finder에서 선택한 파일과 폴더에 작업을 실행합니다.",
        open: "Finder 도구 열기",
        chooseFiles: "파일 선택",
        chooseFolder: "폴더 선택",
        emptySelection: "계속하려면 파일이나 폴더를 하나 이상 선택하세요.",
        run: "실행",
        name: "이름",
        destination: "대상 위치",
        success: "작업이 완료되었습니다.",
        failure: "작업을 완료하지 못했습니다. 다시 시도하세요.",
        cancel: "취소",
        selection: "선택 항목"
    )

    static let zhHans = FinderToolsStrings(
        title: "访达工具",
        description: "对在访达中选中的文件和文件夹执行操作。",
        open: "打开访达工具",
        chooseFiles: "选择文件",
        chooseFolder: "选择文件夹",
        emptySelection: "请选择至少一个文件或文件夹以继续。",
        run: "运行",
        name: "名称",
        destination: "目标位置",
        success: "操作已完成。",
        failure: "无法完成操作，请重试。",
        cancel: "取消",
        selection: "所选项目"
    )

    static let zhTW = FinderToolsStrings(
        title: "Finder 工具",
        description: "對在 Finder 中選取的檔案和資料夾執行操作。",
        open: "打開 Finder 工具",
        chooseFiles: "選擇檔案",
        chooseFolder: "選擇資料夾",
        emptySelection: "請至少選擇一個檔案或資料夾以繼續。",
        run: "執行",
        name: "名稱",
        destination: "目的地",
        success: "操作已完成。",
        failure: "無法完成操作，請再試一次。",
        cancel: "取消",
        selection: "所選項目"
    )

    static let zhHK = FinderToolsStrings(
        title: "Finder 工具",
        description: "對在 Finder 中選取的檔案和資料夾執行操作。",
        open: "開啟 Finder 工具",
        chooseFiles: "選擇檔案",
        chooseFolder: "選擇資料夾",
        emptySelection: "請至少選擇一個檔案或資料夾以繼續。",
        run: "執行",
        name: "名稱",
        destination: "目的地",
        success: "操作已完成。",
        failure: "無法完成操作，請再試一次。",
        cancel: "取消",
        selection: "所選項目"
    )

    static let uk = FinderToolsStrings(
        title: "Інструменти Finder",
        description: "Виконуйте дії з файлами й папками, вибраними у Finder.",
        open: "Відкрити інструменти Finder",
        chooseFiles: "Вибрати файли",
        chooseFolder: "Вибрати папку",
        emptySelection: "Виберіть принаймні один файл або папку, щоб продовжити.",
        run: "Виконати",
        name: "Назва",
        destination: "Місце призначення",
        success: "Дію виконано.",
        failure: "Не вдалося виконати дію. Спробуйте ще раз.",
        cancel: "Скасувати",
        selection: "Вибране"
    )
}

extension FinderToolsStrings {
    static func password(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Password"
        case .ptBR: return "Senha"
        case .tr: return "Parola"
        case .ru: return "Пароль"
        case .es: return "Contraseña"
        case .sk: return "Heslo"
        case .de: return "Passwort"
        case .fr: return "Mot de passe"
        case .it: return "Password"
        case .ja: return "パスワード"
        case .ko: return "암호"
        case .zhHans: return "密码"
        case .zhTW, .zhHK: return "密碼"
        case .uk: return "Пароль"
        }
    }
}

extension FinderToolsStrings {
    static func defaultName(_ action: FinderToolsAction, language: AppLanguage) -> String {
        if action == .batchRename { return "{n}-{name}" }
        if action == .searchFolder { return "" }
        if action == .newFolder || action == .group { return FinderToolsAction.newFolder.title(languageCode: language.rawValue) }
        let base: String
        switch language {
        case .enUS: base = "Untitled"
        case .ptBR: base = "Sem título"
        case .es: base = "Sin título"
        case .fr: base = "Sans titre"
        case .de: base = "Ohne Titel"
        case .it: base = "Senza titolo"
        case .tr: base = "Başlıksız"
        case .sk: base = "Bez názvu"
        case .ru: base = "Без названия"
        case .uk: base = "Без назви"
        case .ja: base = "名称未設定"
        case .ko: base = "무제"
        case .zhHans: base = "未命名"
        case .zhTW, .zhHK: base = "未命名"
        }
        if action == .newFile || action == .pasteText { return base + ".txt" }
        if action == .pasteMarkdown { return base + ".md" }
        return base
    }
}

extension FinderToolsStrings {
    static func presentationCompression(_ language: String) -> String {
        switch language {
        case "en-US": return "Creates a smaller PPTX copy. JPEG pictures use 80% quality; their dimensions and slide content are preserved."
        case "pt-BR": return "Cria uma cópia PPTX menor. Imagens JPEG usam qualidade de 80%; as dimensões e o conteúdo dos slides são preservados."
        case "es": return "Crea una copia PPTX más pequeña. Las imágenes JPEG usan calidad del 80%; se conservan sus dimensiones y el contenido de las diapositivas."
        case "fr": return "Crée une copie PPTX plus petite. Les images JPEG utilisent une qualité de 80 % ; leurs dimensions et le contenu des diapositives sont conservés."
        case "de": return "Erstellt eine kleinere PPTX-Kopie. JPEG-Bilder verwenden 80 % Qualität; Abmessungen und Folieninhalt bleiben erhalten."
        case "it": return "Crea una copia PPTX più piccola. Le immagini JPEG usano qualità 80%; dimensioni e contenuto delle diapositive restano invariati."
        case "ja": return "小さいPPTXコピーを作成します。JPEG画質は80%で、画像の寸法とスライドの内容は保持されます。"
        case "ko": return "더 작은 PPTX 복사본을 만듭니다. JPEG 품질은 80%이며 이미지 크기와 슬라이드 내용은 유지됩니다."
        case "zh-Hans": return "创建更小的 PPTX 副本。JPEG 图像使用 80% 质量，保留图像尺寸和幻灯片内容。"
        case "zh-TW": return "製作較小的 PPTX 副本。JPEG 影像使用 80% 品質，保留影像尺寸和投影片內容。"
        case "zh-HK": return "製作較小的 PPTX 副本。JPEG 影像使用 80% 品質，保留影像尺寸和投影片內容。"
        case "ru": return "Создаёт уменьшенную копию PPTX. Качество JPEG — 80%; размеры изображений и содержимое слайдов сохраняются."
        case "uk": return "Створює зменшену копію PPTX. Якість JPEG — 80%; розміри зображень і вміст слайдів зберігаються."
        case "tr": return "Daha küçük bir PPTX kopyası oluşturur. JPEG kalitesi %80 olur; görsel boyutları ve slayt içeriği korunur."
        case "sk": return "Vytvorí menšiu kópiu PPTX. Obrázky JPEG používajú kvalitu 80 %; rozmery a obsah snímok sa zachovajú."
        default: return presentationCompression("en-US")
        }
    }
}
