// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ArchiveToolsStrings {
    let title: String
    let hubDescription: String
    let createCaption: String
    let chooseSources: String
    let excludeDSStore: String
    let excludeDSStoreCaption: String
    let startCreate: String
    let noSelection: String
    let selectedItemsFormat: String
    let completedFormat: String
    let duplicateSourceFormat: String
    let sourceUnavailable: String
    let cannotPrepare: String
    let cannotPublish: String
}

extension FeatureStrings {
    static func archiveTools(_ language: AppLanguage) -> ArchiveToolsStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension ArchiveToolsStrings {
    static let enUS = ArchiveToolsStrings(
        title: "Archive tools",
        hubDescription: "Create ZIP archives without leaving Vorssaint",
        createCaption: "Combine selected files and folders into one ZIP archive.",
        chooseSources: "Drop or choose files and folders",
        excludeDSStore: "Exclude .DS_Store files",
        excludeDSStoreCaption: "Leave macOS Finder metadata out of the new archive.",
        startCreate: "Create ZIP",
        noSelection: "Nothing selected",
        selectedItemsFormat: "%d items selected",
        completedFormat: "Saved as %@",
        duplicateSourceFormat: "Two selected items are named %@. Choose items with unique top-level names.",
        sourceUnavailable: "A selected item is no longer available. Choose the sources again.",
        cannotPrepare: "A temporary workspace could not be created at the destination.",
        cannotPublish: "The completed result could not be published at the destination."
    )

    static let ptBR = ArchiveToolsStrings(
        title: "Ferramentas de arquivo",
        hubDescription: "Crie arquivos ZIP sem sair do Vorssaint",
        createCaption: "Combine os arquivos e pastas selecionados em um único ZIP.",
        chooseSources: "Soltar ou escolher arquivos e pastas",
        excludeDSStore: "Excluir arquivos .DS_Store",
        excludeDSStoreCaption: "Não incluir metadados do Finder do macOS no novo arquivo.",
        startCreate: "Criar ZIP",
        noSelection: "Nada selecionado",
        selectedItemsFormat: "%d itens selecionados",
        completedFormat: "Salvo como %@",
        duplicateSourceFormat: "Dois itens selecionados se chamam %@. Escolha nomes de nível superior exclusivos.",
        sourceUnavailable: "Um item selecionado não está mais disponível. Escolha as origens novamente.",
        cannotPrepare: "Não foi possível criar um espaço temporário no destino.",
        cannotPublish: "Não foi possível publicar o resultado concluído no destino."
    )

    static let tr = ArchiveToolsStrings(
        title: "Arşiv araçları",
        hubDescription: "Vorssaint'ten ayrılmadan ZIP arşivleri oluşturun",
        createCaption: "Seçili dosya ve klasörleri tek bir ZIP arşivinde birleştirin.",
        chooseSources: "Dosya ve klasörleri bırakın veya seçin",
        excludeDSStore: ".DS_Store dosyalarını hariç tut",
        excludeDSStoreCaption: "macOS Finder meta verilerini yeni arşive eklemeyin.",
        startCreate: "ZIP oluştur",
        noSelection: "Hiçbir şey seçilmedi",
        selectedItemsFormat: "%d öğe seçildi",
        completedFormat: "%@ olarak kaydedildi",
        duplicateSourceFormat: "Seçili iki öğenin adı %@. Benzersiz üst düzey adlara sahip öğeler seçin.",
        sourceUnavailable: "Seçili bir öğe artık kullanılamıyor. Kaynakları yeniden seçin.",
        cannotPrepare: "Hedefte geçici çalışma alanı oluşturulamadı.",
        cannotPublish: "Tamamlanan sonuç hedefte yayımlanamadı."
    )

    static let ru = ArchiveToolsStrings(
        title: "Работа с архивами",
        hubDescription: "Создавайте ZIP-архивы в Vorssaint",
        createCaption: "Объедините выбранные файлы и папки в один ZIP-архив.",
        chooseSources: "Перетащить или выбрать файлы и папки",
        excludeDSStore: "Исключать файлы .DS_Store",
        excludeDSStoreCaption: "Не добавлять метаданные Finder в новый архив.",
        startCreate: "Создать ZIP",
        noSelection: "Ничего не выбрано",
        selectedItemsFormat: "Выбрано объектов: %d",
        completedFormat: "Сохранено как %@",
        duplicateSourceFormat: "Два выбранных объекта называются %@. Выберите объекты с разными именами верхнего уровня.",
        sourceUnavailable: "Один из выбранных объектов больше недоступен. Выберите исходные объекты снова.",
        cannotPrepare: "Не удалось создать временную рабочую папку в месте назначения.",
        cannotPublish: "Не удалось опубликовать готовый результат в месте назначения."
    )

    static let es = ArchiveToolsStrings(
        title: "Herramientas de archivos",
        hubDescription: "Crea archivos ZIP sin salir de Vorssaint",
        createCaption: "Combina los archivos y carpetas seleccionados en un único ZIP.",
        chooseSources: "Soltar o elegir archivos y carpetas",
        excludeDSStore: "Excluir archivos .DS_Store",
        excludeDSStoreCaption: "No incluir metadatos del Finder de macOS en el nuevo archivo.",
        startCreate: "Crear ZIP",
        noSelection: "Nada seleccionado",
        selectedItemsFormat: "%d elementos seleccionados",
        completedFormat: "Guardado como %@",
        duplicateSourceFormat: "Dos elementos seleccionados se llaman %@. Elige nombres de nivel superior únicos.",
        sourceUnavailable: "Un elemento seleccionado ya no está disponible. Vuelve a elegir los elementos de origen.",
        cannotPrepare: "No se pudo crear un espacio de trabajo temporal en el destino.",
        cannotPublish: "No se pudo publicar el resultado completado en el destino."
    )

    static let de = ArchiveToolsStrings(
        title: "Archivwerkzeuge",
        hubDescription: "ZIP-Archive direkt in Vorssaint erstellen",
        createCaption: "Ausgewählte Dateien und Ordner in einem ZIP-Archiv zusammenfassen.",
        chooseSources: "Dateien und Ordner ablegen oder auswählen",
        excludeDSStore: ".DS_Store-Dateien ausschließen",
        excludeDSStoreCaption: "Finder-Metadaten von macOS nicht in das neue Archiv aufnehmen.",
        startCreate: "ZIP erstellen",
        noSelection: "Nichts ausgewählt",
        selectedItemsFormat: "%d Objekte ausgewählt",
        completedFormat: "Gespeichert als %@",
        duplicateSourceFormat: "Zwei ausgewählte Objekte heißen %@. Wähle eindeutige Namen auf oberster Ebene.",
        sourceUnavailable: "Ein ausgewähltes Objekt ist nicht mehr verfügbar. Wähle die Quellen erneut aus.",
        cannotPrepare: "Am Ziel konnte kein temporärer Arbeitsbereich erstellt werden.",
        cannotPublish: "Das fertige Ergebnis konnte am Ziel nicht veröffentlicht werden."
    )

    static let fr = ArchiveToolsStrings(
        title: "Outils d’archive",
        hubDescription: "Créez des archives ZIP dans Vorssaint",
        createCaption: "Regroupez les fichiers et dossiers sélectionnés dans une archive ZIP.",
        chooseSources: "Déposer ou choisir des fichiers et dossiers",
        excludeDSStore: "Exclure les fichiers .DS_Store",
        excludeDSStoreCaption: "Ne pas inclure les métadonnées Finder de macOS dans la nouvelle archive.",
        startCreate: "Créer le ZIP",
        noSelection: "Aucune sélection",
        selectedItemsFormat: "%d éléments sélectionnés",
        completedFormat: "Enregistré sous %@",
        duplicateSourceFormat: "Deux éléments sélectionnés portent le nom %@. Choisissez des noms de premier niveau uniques.",
        sourceUnavailable: "Un élément sélectionné n’est plus disponible. Choisissez à nouveau les sources.",
        cannotPrepare: "Impossible de créer un espace de travail temporaire à la destination.",
        cannotPublish: "Impossible de publier le résultat terminé à la destination."
    )

    static let it = ArchiveToolsStrings(
        title: "Strumenti archivio",
        hubDescription: "Crea archivi ZIP senza lasciare Vorssaint",
        createCaption: "Combina i file e le cartelle selezionati in un unico archivio ZIP.",
        chooseSources: "Trascina o scegli file e cartelle",
        excludeDSStore: "Escludi i file .DS_Store",
        excludeDSStoreCaption: "Non includere i metadati del Finder di macOS nel nuovo archivio.",
        startCreate: "Crea ZIP",
        noSelection: "Nessuna selezione",
        selectedItemsFormat: "%d elementi selezionati",
        completedFormat: "Salvato come %@",
        duplicateSourceFormat: "Due elementi selezionati si chiamano %@. Scegli nomi di primo livello univoci.",
        sourceUnavailable: "Un elemento selezionato non è più disponibile. Scegli di nuovo le origini.",
        cannotPrepare: "Impossibile creare uno spazio di lavoro temporaneo nella destinazione.",
        cannotPublish: "Impossibile pubblicare il risultato completato nella destinazione."
    )

    static let ja = ArchiveToolsStrings(
        title: "アーカイブツール",
        hubDescription: "Vorssaint で ZIP アーカイブを作成します",
        createCaption: "選択したファイルとフォルダを1つの ZIP アーカイブにまとめます。",
        chooseSources: "ファイルとフォルダをドロップまたは選択",
        excludeDSStore: ".DS_Store ファイルを除外",
        excludeDSStoreCaption: "macOS Finder のメタデータを新しいアーカイブに含めません。",
        startCreate: "ZIP を作成",
        noSelection: "何も選択されていません",
        selectedItemsFormat: "%d項目を選択中",
        completedFormat: "%@として保存しました",
        duplicateSourceFormat: "選択した2つの項目の名前が%@です。最上位の名前が異なる項目を選択してください。",
        sourceUnavailable: "選択した項目を利用できなくなりました。ソースを選択し直してください。",
        cannotPrepare: "保存先に一時作業領域を作成できませんでした。",
        cannotPublish: "完成した結果を保存先に公開できませんでした。"
    )

    static let ko = ArchiveToolsStrings(
        title: "아카이브 도구",
        hubDescription: "Vorssaint에서 ZIP 아카이브를 만듭니다",
        createCaption: "선택한 파일과 폴더를 하나의 ZIP 아카이브로 결합합니다.",
        chooseSources: "파일 및 폴더를 놓거나 선택",
        excludeDSStore: ".DS_Store 파일 제외",
        excludeDSStoreCaption: "macOS Finder 메타데이터를 새 아카이브에 포함하지 않습니다.",
        startCreate: "ZIP 만들기",
        noSelection: "선택한 항목 없음",
        selectedItemsFormat: "%d개 항목 선택됨",
        completedFormat: "%@ 이름으로 저장됨",
        duplicateSourceFormat: "선택한 두 항목의 이름이 %@입니다. 최상위 이름이 고유한 항목을 선택하세요.",
        sourceUnavailable: "선택한 항목을 더 이상 사용할 수 없습니다. 소스를 다시 선택하세요.",
        cannotPrepare: "대상에 임시 작업 공간을 만들 수 없습니다.",
        cannotPublish: "완료된 결과를 대상에 게시할 수 없습니다."
    )

    static let zhHans = ArchiveToolsStrings(
        title: "归档工具",
        hubDescription: "无需离开 Vorssaint 即可创建 ZIP 归档",
        createCaption: "将所选文件和文件夹合并到一个 ZIP 归档中。",
        chooseSources: "拖放或选择文件和文件夹",
        excludeDSStore: "排除 .DS_Store 文件",
        excludeDSStoreCaption: "不在新归档中包含 macOS 访达元数据。",
        startCreate: "创建 ZIP",
        noSelection: "未选择任何项目",
        selectedItemsFormat: "已选择 %d 个项目",
        completedFormat: "已存储为 %@",
        duplicateSourceFormat: "两个所选项目都名为 %@。请选择顶层名称不同的项目。",
        sourceUnavailable: "某个所选项目已不可用。请重新选择源项目。",
        cannotPrepare: "无法在目标位置创建临时工作区。",
        cannotPublish: "无法将完成的结果发布到目标位置。"
    )

    static let zhTW = ArchiveToolsStrings(
        title: "封存工具",
        hubDescription: "不必離開 Vorssaint 即可建立 ZIP 封存檔",
        createCaption: "將所選檔案和檔案夾合併到一個 ZIP 封存檔中。",
        chooseSources: "拖放或選擇檔案和檔案夾",
        excludeDSStore: "排除 .DS_Store 檔案",
        excludeDSStoreCaption: "不要在新封存檔中包含 macOS Finder 中繼資料。",
        startCreate: "建立 ZIP",
        noSelection: "尚未選擇項目",
        selectedItemsFormat: "已選擇 %d 個項目",
        completedFormat: "已儲存為 %@",
        duplicateSourceFormat: "兩個所選項目都命名為 %@。請選擇頂層名稱不同的項目。",
        sourceUnavailable: "某個所選項目已無法使用。請重新選擇來源項目。",
        cannotPrepare: "無法在目的地建立暫存工作區。",
        cannotPublish: "無法將完成的結果發佈到目的地。"
    )

    static let zhHK = ArchiveToolsStrings(
        title: "封存工具",
        hubDescription: "毋須離開 Vorssaint 即可建立 ZIP 封存檔",
        createCaption: "將所選檔案及資料夾合併到一個 ZIP 封存檔中。",
        chooseSources: "拖放或選擇檔案及資料夾",
        excludeDSStore: "排除 .DS_Store 檔案",
        excludeDSStoreCaption: "不要在新封存檔中包含 macOS Finder 元資料。",
        startCreate: "建立 ZIP",
        noSelection: "尚未選擇項目",
        selectedItemsFormat: "已選擇 %d 個項目",
        completedFormat: "已儲存為 %@",
        duplicateSourceFormat: "兩個所選項目都名為 %@。請選擇頂層名稱不同的項目。",
        sourceUnavailable: "某個所選項目已無法使用。請重新選擇來源項目。",
        cannotPrepare: "無法在目的地建立暫存工作區。",
        cannotPublish: "無法將完成的結果發佈到目的地。"
    )
}
