// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderFolderInfoFeatureStrings {
    let enableLabel: String
    let caption: String
}

extension FeatureStrings {
    static func finderFolderInfo(_ language: AppLanguage) -> FinderFolderInfoFeatureStrings {
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

extension FinderFolderInfoFeatureStrings {
    static let enUS = FinderFolderInfoFeatureStrings(
        enableLabel: "Space on folders opens Get Info",
        caption: "In Finder, Space still opens Quick Look for files. When only folders are selected, Space opens Get Info instead. Renaming and other text fields are left alone."
    )

    static let ptBR = FinderFolderInfoFeatureStrings(
        enableLabel: "Espaço em pastas abre Obter Informações",
        caption: "No Finder, Espaço continua abrindo o Quick Look para arquivos. Quando só pastas estão selecionadas, Espaço abre Obter Informações. Renomeação e outros campos de texto ficam intactos."
    )

    static let tr = FinderFolderInfoFeatureStrings(
        enableLabel: "Klasörlerde Boşluk, Bilgi Al’ı açar",
        caption: "Finder’da Boşluk dosyalar için Hızlı Bakış’ı açmaya devam eder. Yalnızca klasörler seçiliyken Boşluk Bilgi Al’ı açar. Yeniden adlandırma ve diğer metin alanlarına dokunulmaz."
    )

    static let ru = FinderFolderInfoFeatureStrings(
        enableLabel: "Пробел на папках открывает «Свойства»",
        caption: "В Finder Пробел по-прежнему открывает Быстрый просмотр для файлов. Если выбраны только папки, Пробел открывает «Свойства». Переименование и другие поля ввода не затрагиваются."
    )

    static let es = FinderFolderInfoFeatureStrings(
        enableLabel: "Espacio en carpetas abre Obtener información",
        caption: "En el Finder, Espacio sigue abriendo Quick Look para archivos. Cuando solo hay carpetas seleccionadas, Espacio abre Obtener información. El renombrado y otros campos de texto no se tocan."
    )

    static let de = FinderFolderInfoFeatureStrings(
        enableLabel: "Leertaste bei Ordnern öffnet Informationen",
        caption: "Im Finder öffnet die Leertaste weiterhin Quick Look für Dateien. Sind nur Ordner ausgewählt, öffnet die Leertaste Informationen. Umbenennen und andere Textfelder bleiben unberührt."
    )

    static let fr = FinderFolderInfoFeatureStrings(
        enableLabel: "Espace sur les dossiers ouvre Lire les informations",
        caption: "Dans le Finder, Espace ouvre toujours Aperçu rapide pour les fichiers. Lorsque seuls des dossiers sont sélectionnés, Espace ouvre Lire les informations. Le renommage et les autres champs de texte restent intacts."
    )

    static let it = FinderFolderInfoFeatureStrings(
        enableLabel: "Spazio sulle cartelle apre Ottieni informazioni",
        caption: "Nel Finder, Spazio continua ad aprire Quick Look per i file. Quando sono selezionate solo cartelle, Spazio apre Ottieni informazioni. Ridenomina e altri campi di testo restano intatti."
    )

    static let ja = FinderFolderInfoFeatureStrings(
        enableLabel: "フォルダでスペースを押すと情報を見る",
        caption: "Finderでは、ファイルのスペースはこれまでどおりクイックルックを開きます。フォルダだけが選択されているときは、スペースで「情報を見る」を開きます。名前の変更やほかのテキスト欄には影響しません。"
    )

    static let ko = FinderFolderInfoFeatureStrings(
        enableLabel: "폴더에서 스페이스를 누르면 정보 가져오기",
        caption: "Finder에서 파일의 스페이스는 계속 Quick Look을 엽니다. 폴더만 선택된 경우 스페이스는 정보 가져오기를 엽니다. 이름 변경과 다른 텍스트 필드는 그대로 둡니다."
    )

    static let zhHans = FinderFolderInfoFeatureStrings(
        enableLabel: "在文件夹上按空格打开显示简介",
        caption: "在访达中，对文件按空格仍会打开快速查看。仅选中文件夹时，空格会打开显示简介。重命名和其他文本栏不受影响。"
    )

    static let zhTW = FinderFolderInfoFeatureStrings(
        enableLabel: "在檔案夾上按空白鍵開啟簡介視窗",
        caption: "在 Finder 中，對檔案按空白鍵仍會開啟快速看。只選取檔案夾時，空白鍵會開啟簡介視窗。重新命名和其他文字欄位不受影響。"
    )

    static let zhHK = FinderFolderInfoFeatureStrings(
        enableLabel: "在檔案夾上按空白鍵開啟簡介視窗",
        caption: "在 Finder 中，對檔案按空白鍵仍會開啟快速睇。只選取檔案夾時，空白鍵會開啟簡介視窗。重新命名和其他文字欄位不受影響。"
    )
}
