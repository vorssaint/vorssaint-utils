// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderRenameFeatureStrings {
    let pageTitle: String
    let hubTitle: String
    let hubDescription: String
    let enableLabel: String
    let caption: String
    let shortcutLabel: String
}

extension FeatureStrings {
    static func finderRename(_ language: AppLanguage) -> FinderRenameFeatureStrings {
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

extension FinderRenameFeatureStrings {
    static let enUS = FinderRenameFeatureStrings(
        pageTitle: "Finder shortcuts",
        hubTitle: "Rename shortcut",
        hubDescription: "Rename the selected file or folder with a shortcut you choose.",
        enableLabel: "Use a shortcut to rename",
        caption: "The shortcut only acts in Finder and leaves text fields alone. F2 works as a regular key; on keyboards where it controls brightness, use Fn-F2 or choose another shortcut.",
        shortcutLabel: "Rename"
    )

    static let ptBR = FinderRenameFeatureStrings(
        pageTitle: "Atalhos do Finder",
        hubTitle: "Atalho para renomear",
        hubDescription: "Renomeie o arquivo ou a pasta selecionada com um atalho à sua escolha.",
        enableLabel: "Usar um atalho para renomear",
        caption: "O atalho só funciona no Finder e não interfere em campos de texto. F2 funciona como tecla comum; se ela controlar o brilho, use Fn-F2 ou escolha outro atalho.",
        shortcutLabel: "Renomear"
    )

    static let tr = FinderRenameFeatureStrings(
        pageTitle: "Finder kısayolları",
        hubTitle: "Yeniden adlandırma kısayolu",
        hubDescription: "Seçili dosya veya klasörü seçtiğiniz bir kısayolla yeniden adlandırın.",
        enableLabel: "Yeniden adlandırmak için kısayol kullan",
        caption: "Kısayol yalnızca Finder'da çalışır ve metin alanlarına dokunmaz. F2 normal tuş olarak çalışır; parlaklığı denetliyorsa Fn-F2 kullanın veya başka bir kısayol seçin.",
        shortcutLabel: "Yeniden adlandır"
    )

    static let ru = FinderRenameFeatureStrings(
        pageTitle: "Сочетания Finder",
        hubTitle: "Сочетание для переименования",
        hubDescription: "Переименовывайте выбранный файл или папку заданным сочетанием клавиш.",
        enableLabel: "Использовать сочетание для переименования",
        caption: "Сочетание работает только в Finder и не мешает полям ввода. F2 работает как обычная клавиша; если она меняет яркость, нажмите Fn-F2 или выберите другое сочетание.",
        shortcutLabel: "Переименовать"
    )

    static let es = FinderRenameFeatureStrings(
        pageTitle: "Atajos del Finder",
        hubTitle: "Atajo para renombrar",
        hubDescription: "Renombra el archivo o la carpeta seleccionada con el atajo que elijas.",
        enableLabel: "Usar un atajo para renombrar",
        caption: "El atajo solo funciona en el Finder y no interfiere con los campos de texto. F2 funciona como tecla normal; si controla el brillo, usa Fn-F2 o elige otro atajo.",
        shortcutLabel: "Renombrar"
    )

    static let de = FinderRenameFeatureStrings(
        pageTitle: "Finder-Kurzbefehle",
        hubTitle: "Kurzbefehl zum Umbenennen",
        hubDescription: "Benenne die ausgewählte Datei oder den Ordner mit einem Kurzbefehl deiner Wahl um.",
        enableLabel: "Mit einem Kurzbefehl umbenennen",
        caption: "Der Kurzbefehl wirkt nur im Finder und lässt Textfelder in Ruhe. F2 funktioniert als normale Taste; steuert sie die Helligkeit, verwende Fn-F2 oder wähle einen anderen Kurzbefehl.",
        shortcutLabel: "Umbenennen"
    )

    static let fr = FinderRenameFeatureStrings(
        pageTitle: "Raccourcis du Finder",
        hubTitle: "Raccourci pour renommer",
        hubDescription: "Renommez le fichier ou le dossier sélectionné avec le raccourci de votre choix.",
        enableLabel: "Utiliser un raccourci pour renommer",
        caption: "Le raccourci agit uniquement dans le Finder et laisse les champs de texte intacts. F2 fonctionne comme une touche normale ; si elle règle la luminosité, utilisez Fn-F2 ou choisissez un autre raccourci.",
        shortcutLabel: "Renommer"
    )

    static let it = FinderRenameFeatureStrings(
        pageTitle: "Abbreviazioni del Finder",
        hubTitle: "Abbreviazione per rinominare",
        hubDescription: "Rinomina il file o la cartella selezionata con un'abbreviazione a tua scelta.",
        enableLabel: "Usa un'abbreviazione per rinominare",
        caption: "L'abbreviazione funziona solo nel Finder e non interferisce con i campi di testo. F2 funziona come tasto normale; se regola la luminosità, usa Fn-F2 o scegli un'altra abbreviazione.",
        shortcutLabel: "Rinomina"
    )

    static let ja = FinderRenameFeatureStrings(
        pageTitle: "Finderのショートカット",
        hubTitle: "名前変更のショートカット",
        hubDescription: "選択したファイルやフォルダを、選んだショートカットで名前変更します。",
        enableLabel: "ショートカットで名前を変更",
        caption: "ショートカットはFinderでのみ動作し、テキスト欄には影響しません。F2は通常のキーとして動作します。明るさを調整する場合はFn-F2を使うか、別のショートカットを選んでください。",
        shortcutLabel: "名前を変更"
    )

    static let ko = FinderRenameFeatureStrings(
        pageTitle: "Finder 단축키",
        hubTitle: "이름 변경 단축키",
        hubDescription: "선택한 파일이나 폴더의 이름을 원하는 단축키로 변경합니다.",
        enableLabel: "단축키로 이름 변경",
        caption: "단축키는 Finder에서만 작동하며 텍스트 필드에는 영향을 주지 않습니다. F2는 일반 키로 작동합니다. 밝기를 조절한다면 Fn-F2를 누르거나 다른 단축키를 선택하세요.",
        shortcutLabel: "이름 변경"
    )

    static let zhHans = FinderRenameFeatureStrings(
        pageTitle: "访达快捷键",
        hubTitle: "重命名快捷键",
        hubDescription: "使用你选择的快捷键重命名所选文件或文件夹。",
        enableLabel: "使用快捷键重命名",
        caption: "快捷键仅在访达中生效，不会干扰文本栏。F2 会作为普通按键使用；如果它用于调节亮度，请按 Fn-F2 或选择其他快捷键。",
        shortcutLabel: "重命名"
    )

    static let zhTW = FinderRenameFeatureStrings(
        pageTitle: "Finder 快捷鍵",
        hubTitle: "重新命名快捷鍵",
        hubDescription: "使用你選擇的快捷鍵重新命名所選檔案或資料夾。",
        enableLabel: "使用快捷鍵重新命名",
        caption: "快捷鍵只會在 Finder 中生效，不會影響文字欄位。F2 會當作一般按鍵使用；如果它用來調整亮度，請按 Fn-F2 或選擇其他快捷鍵。",
        shortcutLabel: "重新命名"
    )

    static let zhHK = FinderRenameFeatureStrings(
        pageTitle: "Finder 快捷鍵",
        hubTitle: "重新命名快捷鍵",
        hubDescription: "使用你選擇的快捷鍵重新命名所選檔案或資料夾。",
        enableLabel: "使用快捷鍵重新命名",
        caption: "快捷鍵只會在 Finder 生效，不會影響文字欄位。F2 會當作一般按鍵使用；如果它用來調校亮度，請按 Fn-F2 或選擇其他快捷鍵。",
        shortcutLabel: "重新命名"
    )
}
