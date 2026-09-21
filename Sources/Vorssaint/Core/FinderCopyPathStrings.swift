// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderCopyPathStrings {
    let title: String
    let enableLabel: String
    let caption: String
    let shortcutLabel: String
}

extension FeatureStrings {
    static func finderCopyPath(_ language: AppLanguage) -> FinderCopyPathStrings {
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

extension FinderCopyPathStrings {
    static let enUS = FinderCopyPathStrings(
        title: "Copy path",
        enableLabel: "Copy selected paths with a shortcut",
        caption: "Copies the full POSIX path of the selected file or folder. Multiple selections are copied one path per line.",
        shortcutLabel: "Copy path"
    )

    static let ptBR = FinderCopyPathStrings(
        title: "Copiar caminho",
        enableLabel: "Copiar caminhos selecionados com um atalho",
        caption: "Copia o caminho POSIX completo do arquivo ou pasta selecionado. Várias seleções são copiadas com um caminho por linha.",
        shortcutLabel: "Copiar caminho"
    )

    static let tr = FinderCopyPathStrings(
        title: "Yolu kopyala",
        enableLabel: "Seçili yolları bir kısayolla kopyala",
        caption: "Seçili dosya veya klasörün tam POSIX yolunu kopyalar. Birden çok seçimde her satıra bir yol kopyalanır.",
        shortcutLabel: "Yolu kopyala"
    )

    static let ru = FinderCopyPathStrings(
        title: "Копировать путь",
        enableLabel: "Копировать выбранные пути сочетанием клавиш",
        caption: "Копирует полный POSIX-путь выбранного файла или папки. Для нескольких объектов каждый путь помещается на отдельную строку.",
        shortcutLabel: "Копировать путь"
    )

    static let es = FinderCopyPathStrings(
        title: "Copiar ruta",
        enableLabel: "Copiar las rutas seleccionadas con un atajo",
        caption: "Copia la ruta POSIX completa del archivo o carpeta seleccionado. Si hay varios, copia una ruta por línea.",
        shortcutLabel: "Copiar ruta"
    )

    static let de = FinderCopyPathStrings(
        title: "Pfad kopieren",
        enableLabel: "Ausgewählte Pfade mit einem Kurzbefehl kopieren",
        caption: "Kopiert den vollständigen POSIX-Pfad der ausgewählten Datei oder des Ordners. Bei mehreren Elementen steht ein Pfad pro Zeile.",
        shortcutLabel: "Pfad kopieren"
    )

    static let fr = FinderCopyPathStrings(
        title: "Copier le chemin",
        enableLabel: "Copier les chemins sélectionnés avec un raccourci",
        caption: "Copie le chemin POSIX complet du fichier ou dossier sélectionné. Pour plusieurs éléments, un chemin est copié par ligne.",
        shortcutLabel: "Copier le chemin"
    )

    static let it = FinderCopyPathStrings(
        title: "Copia percorso",
        enableLabel: "Copia i percorsi selezionati con un’abbreviazione",
        caption: "Copia il percorso POSIX completo del file o della cartella selezionata. Per più elementi viene copiato un percorso per riga.",
        shortcutLabel: "Copia percorso"
    )

    static let ja = FinderCopyPathStrings(
        title: "パスをコピー",
        enableLabel: "ショートカットで選択項目のパスをコピー",
        caption: "選択したファイルやフォルダの完全なPOSIXパスをコピーします。複数選択では1行に1つのパスをコピーします。",
        shortcutLabel: "パスをコピー"
    )

    static let ko = FinderCopyPathStrings(
        title: "경로 복사",
        enableLabel: "단축키로 선택한 경로 복사",
        caption: "선택한 파일 또는 폴더의 전체 POSIX 경로를 복사합니다. 여러 항목은 한 줄에 하나의 경로로 복사됩니다.",
        shortcutLabel: "경로 복사"
    )

    static let zhHans = FinderCopyPathStrings(
        title: "拷贝路径",
        enableLabel: "使用快捷键拷贝所选路径",
        caption: "拷贝所选文件或文件夹的完整 POSIX 路径。选择多个项目时，每行拷贝一个路径。",
        shortcutLabel: "拷贝路径"
    )

    static let zhTW = FinderCopyPathStrings(
        title: "拷貝路徑",
        enableLabel: "使用快捷鍵拷貝所選路徑",
        caption: "拷貝所選檔案或資料夾的完整 POSIX 路徑。選取多個項目時，每行拷貝一個路徑。",
        shortcutLabel: "拷貝路徑"
    )

    static let zhHK = FinderCopyPathStrings(
        title: "複製路徑",
        enableLabel: "使用快捷鍵複製所選路徑",
        caption: "複製所選檔案或資料夾的完整 POSIX 路徑。選取多個項目時，每行複製一個路徑。",
        shortcutLabel: "複製路徑"
    )
}
