// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Settings copy for importing a ClearURLs rules file into Clean URL.
struct URLCleanerImportStrings {
    let sectionTitle: String
    let emptyCaption: String
    let summaryFormat: String
    let importButton: String
    let replaceButton: String
    let openRules: String
    let fileCaption: String
    let removeButton: String
    let importTitleFormat: String
    let replaceTitleFormat: String
    let addsFormat: String
    let changesFormat: String
    let skippedFormat: String
    let exceptionsFormat: String
    let keepsChoices: String
    let importConfirm: String
    let replaceConfirm: String
    let cancel: String
    let removeTitle: String
    let removeMessageFormat: String
    let removeConfirm: String
    let errorNotClearURLs: String
    let errorTooLarge: String
    let errorTooMany: String
    let errorNothingUsable: String
    let errorUnreadable: String
    let importedTag: String
    let filterPlaceholder: String
}

extension FeatureStrings {
    static func urlCleanerImport(_ language: AppLanguage) -> URLCleanerImportStrings {
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

extension URLCleanerImportStrings {
    static let enUS = URLCleanerImportStrings(
        sectionTitle: "More rules",
        emptyCaption: "No rules imported. A ClearURLs rules file adds many more sites.",
        summaryFormat: "Imported %1$@ on %2$@. Sites: %3$d. Parameters: %4$d.",
        importButton: "Import rules file…",
        replaceButton: "Replace…",
        openRules: "Get the ClearURLs rules",
        fileCaption: "Download data.min.json from ClearURLs, then import it here. The app never downloads it itself.",
        removeButton: "Remove imported rules",
        importTitleFormat: "Import %@?",
        replaceTitleFormat: "Replace the imported rules with %@?",
        addsFormat: "This file adds rules. Sites: %2$d. Parameters: %1$d.",
        changesFormat: "Parameters added: %1$d. Removed: %2$d. Unchanged: %3$d.",
        skippedFormat: "Rules left out because the app cannot use them (patterns, redirects and rules for one page): %d.",
        exceptionsFormat: "ClearURLs leaves some links alone (exceptions: %d). Here a parameter goes everywhere on its site, so switch it off after importing if a link breaks.",
        keepsChoices: "Parameters you switched off stay off.",
        importConfirm: "Import",
        replaceConfirm: "Replace",
        cancel: "Cancel",
        removeTitle: "Remove the imported rules?",
        removeMessageFormat: "The imported rules stop applying. Sites: %d.",
        removeConfirm: "Remove",
        errorNotClearURLs: "This is not a ClearURLs rules file. No rules were imported.",
        errorTooLarge: "The file is larger than 1 MB, too large for a rules file. No rules were imported.",
        errorTooMany: "The file has more than 5000 rules. No rules were imported.",
        errorNothingUsable: "The file has no rules the app can use. No rules were imported.",
        errorUnreadable: "The file could not be read. No rules were imported.",
        importedTag: "Imported",
        filterPlaceholder: "Filter sites"
    )

    static let ptBR = URLCleanerImportStrings(
        sectionTitle: "Mais regras",
        emptyCaption: "Nenhuma regra importada. Um arquivo de regras do ClearURLs cobre muitos outros sites.",
        summaryFormat: "%1$@ importado em %2$@. Sites: %3$d. Parâmetros: %4$d.",
        importButton: "Importar arquivo de regras…",
        replaceButton: "Substituir…",
        openRules: "Obter as regras do ClearURLs",
        fileCaption: "Baixe o data.min.json do ClearURLs e importe aqui. O app não baixa nada sozinho.",
        removeButton: "Remover regras importadas",
        importTitleFormat: "Importar %@?",
        replaceTitleFormat: "Substituir as regras importadas por %@?",
        addsFormat: "Este arquivo adiciona regras. Sites: %2$d. Parâmetros: %1$d.",
        changesFormat: "Parâmetros adicionados: %1$d. Removidos: %2$d. Sem mudança: %3$d.",
        skippedFormat: "Regras deixadas de fora porque o app não consegue usá-las (padrões, redirecionamentos e regras de uma só página): %d.",
        exceptionsFormat: "O ClearURLs deixa alguns links intactos (exceções: %d). Aqui um parâmetro sai do site inteiro. Desative-o depois de importar se um link parar de funcionar.",
        keepsChoices: "Parâmetros desativados continuam desativados.",
        importConfirm: "Importar",
        replaceConfirm: "Substituir",
        cancel: "Cancelar",
        removeTitle: "Remover as regras importadas?",
        removeMessageFormat: "As regras importadas deixam de valer. Sites: %d.",
        removeConfirm: "Remover",
        errorNotClearURLs: "Este não é um arquivo de regras do ClearURLs. Nenhuma regra foi importada.",
        errorTooLarge: "O arquivo passa de 1 MB, grande demais para um arquivo de regras. Nenhuma regra foi importada.",
        errorTooMany: "O arquivo tem mais de 5000 regras. Nenhuma regra foi importada.",
        errorNothingUsable: "O arquivo não tem regras que o app possa usar. Nenhuma regra foi importada.",
        errorUnreadable: "Não foi possível ler o arquivo. Nenhuma regra foi importada.",
        importedTag: "Importado",
        filterPlaceholder: "Filtrar sites"
    )

    static let tr = URLCleanerImportStrings(
        sectionTitle: "Daha fazla kural",
        emptyCaption: "İçe aktarılmış kural yok. Bir ClearURLs kural dosyası çok daha fazla siteyi kapsar.",
        summaryFormat: "%1$@, %2$@ tarihinde içe aktarıldı. Site: %3$d. Parametre: %4$d.",
        importButton: "Kural dosyası içe aktar…",
        replaceButton: "Değiştir…",
        openRules: "ClearURLs kurallarını al",
        fileCaption: "data.min.json dosyasını ClearURLs’ten indirip buradan içe aktarın. Uygulama kendisi hiçbir şey indirmez.",
        removeButton: "İçe aktarılan kuralları kaldır",
        importTitleFormat: "%@ içe aktarılsın mı?",
        replaceTitleFormat: "İçe aktarılan kurallar %@ ile değiştirilsin mi?",
        addsFormat: "Bu dosya kural ekler. Site: %2$d. Parametre: %1$d.",
        changesFormat: "Eklenen parametre: %1$d. Kaldırılan: %2$d. Değişmeyen: %3$d.",
        skippedFormat: "Uygulamanın kullanamadığı için dışarıda bırakılan kurallar (kalıplar, yönlendirmeler ve tek sayfaya özel kurallar): %d.",
        exceptionsFormat: "ClearURLs bazı bağlantılara dokunmaz (istisna: %d). Burada bir parametre sitenin her yerinden kaldırılır. Bir bağlantı bozulursa içe aktardıktan sonra o parametreyi kapatın.",
        keepsChoices: "Kapattığınız parametreler kapalı kalır.",
        importConfirm: "İçe aktar",
        replaceConfirm: "Değiştir",
        cancel: "Vazgeç",
        removeTitle: "İçe aktarılan kurallar kaldırılsın mı?",
        removeMessageFormat: "İçe aktarılan kurallar artık uygulanmaz. Site: %d.",
        removeConfirm: "Kaldır",
        errorNotClearURLs: "Bu bir ClearURLs kural dosyası değil. Hiçbir kural içe aktarılmadı.",
        errorTooLarge: "Dosya 1 MB’tan büyük, bir kural dosyası için fazla büyük. Hiçbir kural içe aktarılmadı.",
        errorTooMany: "Dosyada 5000’den fazla kural var. Hiçbir kural içe aktarılmadı.",
        errorNothingUsable: "Dosyada uygulamanın kullanabileceği kural yok. Hiçbir kural içe aktarılmadı.",
        errorUnreadable: "Dosya okunamadı. Hiçbir kural içe aktarılmadı.",
        importedTag: "İçe aktarıldı",
        filterPlaceholder: "Siteleri filtrele"
    )

    static let ru = URLCleanerImportStrings(
        sectionTitle: "Дополнительные правила",
        emptyCaption: "Правила не импортированы. Файл правил ClearURLs охватывает гораздо больше сайтов.",
        summaryFormat: "%1$@ импортирован %2$@. Сайтов: %3$d, параметров: %4$d.",
        importButton: "Импортировать файл правил…",
        replaceButton: "Заменить…",
        openRules: "Получить правила ClearURLs",
        fileCaption: "Скачайте data.min.json с ClearURLs и импортируйте его здесь. Приложение само ничего не скачивает.",
        removeButton: "Удалить импортированные правила",
        importTitleFormat: "Импортировать %@?",
        replaceTitleFormat: "Заменить импортированные правила на %@?",
        addsFormat: "Будет добавлено параметров: %1$d, сайтов: %2$d.",
        changesFormat: "Добавлено параметров: %1$d, удалено: %2$d, без изменений: %3$d.",
        skippedFormat: "Правил, которые приложение не может использовать, пропущено: %d. Это шаблоны, перенаправления и правила для отдельных страниц.",
        exceptionsFormat: "ClearURLs не трогает некоторые ссылки (исключений: %d). Здесь параметр удаляется на всём сайте. Если ссылка сломается, отключите его после импорта.",
        keepsChoices: "Отключённые параметры останутся отключёнными.",
        importConfirm: "Импортировать",
        replaceConfirm: "Заменить",
        cancel: "Отмена",
        removeTitle: "Удалить импортированные правила?",
        removeMessageFormat: "Импортированные правила перестанут действовать. Сайтов: %d.",
        removeConfirm: "Удалить",
        errorNotClearURLs: "Это не файл правил ClearURLs. Правила не импортированы.",
        errorTooLarge: "Файл больше 1 МБ, слишком большой для файла правил. Правила не импортированы.",
        errorTooMany: "В файле больше 5000 правил. Правила не импортированы.",
        errorNothingUsable: "В файле нет правил, которые может использовать приложение. Правила не импортированы.",
        errorUnreadable: "Не удалось прочитать файл. Правила не импортированы.",
        importedTag: "Импортировано",
        filterPlaceholder: "Фильтр сайтов"
    )

    static let es = URLCleanerImportStrings(
        sectionTitle: "Más reglas",
        emptyCaption: "No hay reglas importadas. Un archivo de reglas de ClearURLs cubre muchos más sitios.",
        summaryFormat: "%1$@ importado el %2$@. Sitios: %3$d. Parámetros: %4$d.",
        importButton: "Importar archivo de reglas…",
        replaceButton: "Reemplazar…",
        openRules: "Obtener las reglas de ClearURLs",
        fileCaption: "Descarga data.min.json de ClearURLs y luego impórtalo aquí. La app no descarga nada por su cuenta.",
        removeButton: "Quitar reglas importadas",
        importTitleFormat: "¿Importar %@?",
        replaceTitleFormat: "¿Reemplazar las reglas importadas por %@?",
        addsFormat: "Este archivo añade reglas. Sitios: %2$d. Parámetros: %1$d.",
        changesFormat: "Parámetros añadidos: %1$d. Quitados: %2$d. Sin cambios: %3$d.",
        skippedFormat: "Reglas omitidas porque la app no puede usarlas (patrones, redirecciones y reglas para una sola página): %d.",
        exceptionsFormat: "ClearURLs deja algunos enlaces intactos (excepciones: %d). Aquí un parámetro se quita en todo el sitio. Desactívalo tras importar si un enlace deja de funcionar.",
        keepsChoices: "Los parámetros desactivados siguen desactivados.",
        importConfirm: "Importar",
        replaceConfirm: "Reemplazar",
        cancel: "Cancelar",
        removeTitle: "¿Quitar las reglas importadas?",
        removeMessageFormat: "Las reglas importadas dejarán de aplicarse. Sitios: %d.",
        removeConfirm: "Quitar",
        errorNotClearURLs: "Este no es un archivo de reglas de ClearURLs. No se importó ninguna regla.",
        errorTooLarge: "El archivo supera 1 MB, demasiado para un archivo de reglas. No se importó ninguna regla.",
        errorTooMany: "El archivo tiene más de 5000 reglas. No se importó ninguna regla.",
        errorNothingUsable: "El archivo no tiene reglas que la app pueda usar. No se importó ninguna regla.",
        errorUnreadable: "No se pudo leer el archivo. No se importó ninguna regla.",
        importedTag: "Importado",
        filterPlaceholder: "Filtrar sitios"
    )

    static let sk = URLCleanerImportStrings(
        sectionTitle: "Ďalšie pravidlá",
        emptyCaption: "Žiadne importované pravidlá. Súbor pravidiel ClearURLs pokrýva oveľa viac stránok.",
        summaryFormat: "%1$@ importovaný %2$@. Stránok: %3$d, parametrov: %4$d.",
        importButton: "Importovať súbor pravidiel…",
        replaceButton: "Nahradiť…",
        openRules: "Získať pravidlá ClearURLs",
        fileCaption: "Stiahnite data.min.json z ClearURLs a importujte ho tu. Aplikácia sama nič nesťahuje.",
        removeButton: "Odstrániť importované pravidlá",
        importTitleFormat: "Importovať %@?",
        replaceTitleFormat: "Nahradiť importované pravidlá súborom %@?",
        addsFormat: "Pridá parametrov: %1$d, stránok: %2$d.",
        changesFormat: "Pridané parametre: %1$d, odstránené: %2$d, bez zmeny: %3$d.",
        skippedFormat: "Pravidiel, ktoré aplikácia nevie použiť, sa vynechá: %d. Ide o vzory, presmerovania a pravidlá pre jednotlivé stránky.",
        exceptionsFormat: "ClearURLs niektoré odkazy nechá tak (výnimiek: %d). Tu sa parameter odstráni na celej stránke. Ak sa odkaz pokazí, po importe ho vypnite.",
        keepsChoices: "Vypnuté parametre zostanú vypnuté.",
        importConfirm: "Importovať",
        replaceConfirm: "Nahradiť",
        cancel: "Zrušiť",
        removeTitle: "Odstrániť importované pravidlá?",
        removeMessageFormat: "Importované pravidlá prestanú platiť. Stránok: %d.",
        removeConfirm: "Odstrániť",
        errorNotClearURLs: "Toto nie je súbor pravidiel ClearURLs. Neimportovali sa žiadne pravidlá.",
        errorTooLarge: "Súbor má viac ako 1 MB, na súbor pravidiel je to priveľa. Neimportovali sa žiadne pravidlá.",
        errorTooMany: "Súbor má viac ako 5000 pravidiel. Neimportovali sa žiadne pravidlá.",
        errorNothingUsable: "Súbor neobsahuje pravidlá, ktoré aplikácia vie použiť. Neimportovali sa žiadne pravidlá.",
        errorUnreadable: "Súbor sa nepodarilo prečítať. Neimportovali sa žiadne pravidlá.",
        importedTag: "Importované",
        filterPlaceholder: "Filtrovať stránky"
    )

    static let de = URLCleanerImportStrings(
        sectionTitle: "Weitere Regeln",
        emptyCaption: "Keine Regeln importiert. Eine ClearURLs-Regeldatei deckt viele weitere Websites ab.",
        summaryFormat: "%1$@ am %2$@ importiert. Websites: %3$d. Parameter: %4$d.",
        importButton: "Regeldatei importieren…",
        replaceButton: "Ersetzen…",
        openRules: "ClearURLs-Regeln holen",
        fileCaption: "Lade data.min.json von ClearURLs herunter und importiere sie hier. Die App lädt selbst nichts herunter.",
        removeButton: "Importierte Regeln entfernen",
        importTitleFormat: "%@ importieren?",
        replaceTitleFormat: "Importierte Regeln durch %@ ersetzen?",
        addsFormat: "Diese Datei fügt Regeln hinzu. Websites: %2$d. Parameter: %1$d.",
        changesFormat: "Parameter hinzugefügt: %1$d. Entfernt: %2$d. Unverändert: %3$d.",
        skippedFormat: "Ausgelassene Regeln, weil die App sie nicht nutzen kann (Muster, Weiterleitungen und Regeln für einzelne Seiten): %d.",
        exceptionsFormat: "ClearURLs lässt manche Links unangetastet (Ausnahmen: %d). Hier wird ein Parameter auf der ganzen Website entfernt. Schalte ihn nach dem Import aus, wenn ein Link nicht mehr funktioniert.",
        keepsChoices: "Ausgeschaltete Parameter bleiben aus.",
        importConfirm: "Importieren",
        replaceConfirm: "Ersetzen",
        cancel: "Abbrechen",
        removeTitle: "Importierte Regeln entfernen?",
        removeMessageFormat: "Die importierten Regeln gelten dann nicht mehr. Websites: %d.",
        removeConfirm: "Entfernen",
        errorNotClearURLs: "Das ist keine ClearURLs-Regeldatei. Es wurden keine Regeln importiert.",
        errorTooLarge: "Die Datei ist größer als 1 MB und damit zu groß für eine Regeldatei. Es wurden keine Regeln importiert.",
        errorTooMany: "Die Datei enthält mehr als 5000 Regeln. Es wurden keine Regeln importiert.",
        errorNothingUsable: "Die Datei enthält keine Regeln, die die App nutzen kann. Es wurden keine Regeln importiert.",
        errorUnreadable: "Die Datei konnte nicht gelesen werden. Es wurden keine Regeln importiert.",
        importedTag: "Importiert",
        filterPlaceholder: "Websites filtern"
    )

    static let fr = URLCleanerImportStrings(
        sectionTitle: "Autres règles",
        emptyCaption: "Aucune règle importée. Un fichier de règles ClearURLs couvre bien plus de sites.",
        summaryFormat: "%1$@ importé le %2$@. Sites\u{00A0}: %3$d. Paramètres\u{00A0}: %4$d.",
        importButton: "Importer un fichier de règles…",
        replaceButton: "Remplacer…",
        openRules: "Obtenir les règles ClearURLs",
        fileCaption: "Téléchargez data.min.json depuis ClearURLs, puis importez-le ici. L’app ne télécharge rien elle-même.",
        removeButton: "Retirer les règles importées",
        importTitleFormat: "Importer %@\u{00A0}?",
        replaceTitleFormat: "Remplacer les règles importées par %@\u{00A0}?",
        addsFormat: "Ce fichier ajoute des règles. Sites\u{00A0}: %2$d. Paramètres\u{00A0}: %1$d.",
        changesFormat: "Paramètres ajoutés\u{00A0}: %1$d. Retirés\u{00A0}: %2$d. Inchangés\u{00A0}: %3$d.",
        skippedFormat: "Règles laissées de côté, car l’app ne peut pas les utiliser (motifs, redirections et règles propres à une page)\u{00A0}: %d.",
        exceptionsFormat: "ClearURLs laisse certains liens intacts (exceptions\u{00A0}: %d). Ici, un paramètre est retiré sur tout le site. Désactivez-le après l’import si un lien ne fonctionne plus.",
        keepsChoices: "Les paramètres désactivés le restent.",
        importConfirm: "Importer",
        replaceConfirm: "Remplacer",
        cancel: "Annuler",
        removeTitle: "Retirer les règles importées\u{00A0}?",
        removeMessageFormat: "Les règles importées ne s’appliqueront plus. Sites\u{00A0}: %d.",
        removeConfirm: "Retirer",
        errorNotClearURLs: "Ce n’est pas un fichier de règles ClearURLs. Aucune règle n’a été importée.",
        errorTooLarge: "Le fichier dépasse 1\u{00A0}Mo, trop pour un fichier de règles. Aucune règle n’a été importée.",
        errorTooMany: "Le fichier contient plus de 5000 règles. Aucune règle n’a été importée.",
        errorNothingUsable: "Le fichier ne contient aucune règle utilisable par l’app. Aucune règle n’a été importée.",
        errorUnreadable: "Impossible de lire le fichier. Aucune règle n’a été importée.",
        importedTag: "Importé",
        filterPlaceholder: "Filtrer les sites"
    )

    static let it = URLCleanerImportStrings(
        sectionTitle: "Altre regole",
        emptyCaption: "Nessuna regola importata. Un file di regole ClearURLs copre molti altri siti.",
        summaryFormat: "%1$@ importato il %2$@. Siti: %3$d. Parametri: %4$d.",
        importButton: "Importa file di regole…",
        replaceButton: "Sostituisci…",
        openRules: "Scarica le regole ClearURLs",
        fileCaption: "Scarica data.min.json da ClearURLs, poi importalo qui. L’app non scarica nulla da sola.",
        removeButton: "Rimuovi regole importate",
        importTitleFormat: "Importare %@?",
        replaceTitleFormat: "Sostituire le regole importate con %@?",
        addsFormat: "Questo file aggiunge regole. Siti: %2$d. Parametri: %1$d.",
        changesFormat: "Parametri aggiunti: %1$d. Rimossi: %2$d. Invariati: %3$d.",
        skippedFormat: "Regole escluse perché l’app non può usarle (schemi, reindirizzamenti e regole per una sola pagina): %d.",
        exceptionsFormat: "ClearURLs lascia intatti alcuni link (eccezioni: %d). Qui un parametro viene rimosso su tutto il sito. Disattivalo dopo l’importazione se un link smette di funzionare.",
        keepsChoices: "I parametri disattivati restano disattivati.",
        importConfirm: "Importa",
        replaceConfirm: "Sostituisci",
        cancel: "Annulla",
        removeTitle: "Rimuovere le regole importate?",
        removeMessageFormat: "Le regole importate non verranno più applicate. Siti: %d.",
        removeConfirm: "Rimuovi",
        errorNotClearURLs: "Questo non è un file di regole ClearURLs. Nessuna regola è stata importata.",
        errorTooLarge: "Il file supera 1 MB, troppo per un file di regole. Nessuna regola è stata importata.",
        errorTooMany: "Il file contiene più di 5000 regole. Nessuna regola è stata importata.",
        errorNothingUsable: "Il file non contiene regole utilizzabili dall’app. Nessuna regola è stata importata.",
        errorUnreadable: "Impossibile leggere il file. Nessuna regola è stata importata.",
        importedTag: "Importato",
        filterPlaceholder: "Filtra siti"
    )

    static let ja = URLCleanerImportStrings(
        sectionTitle: "その他のルール",
        emptyCaption: "ルールは読み込まれていません。ClearURLs のルールファイルを読み込むと、より多くのサイトに対応できます。",
        summaryFormat: "%1$@ を %2$@ に読み込み済み: %3$d サイト、パラメータ %4$d 個。",
        importButton: "ルールファイルを読み込む…",
        replaceButton: "置き換える…",
        openRules: "ClearURLs のルールを入手",
        fileCaption: "ClearURLs から data.min.json をダウンロードして、ここで読み込みます。App が自分でダウンロードすることはありません。",
        removeButton: "読み込んだルールを削除",
        importTitleFormat: "%@ を読み込みますか？",
        replaceTitleFormat: "読み込んだルールを %@ で置き換えますか？",
        addsFormat: "%2$d サイトのパラメータ %1$d 個を追加します。",
        changesFormat: "追加 %1$d 個、削除 %2$d 個、変更なし %3$d 個。",
        skippedFormat: "App で使えないルール %d 件（パターン、リダイレクト、特定ページ用のルール）は読み込みません。",
        exceptionsFormat: "ClearURLs は一部のリンクを対象外にしています（例外 %d 件）。ここではパラメータがサイト全体で削除されるため、リンクが壊れる場合は読み込み後にそのパラメータをオフにしてください。",
        keepsChoices: "オフにしたパラメータはそのままです。",
        importConfirm: "読み込む",
        replaceConfirm: "置き換える",
        cancel: "キャンセル",
        removeTitle: "読み込んだルールを削除しますか？",
        removeMessageFormat: "%d サイトの読み込んだルールが無効になります。",
        removeConfirm: "削除",
        errorNotClearURLs: "ClearURLs のルールファイルではありません。ルールは読み込まれませんでした。",
        errorTooLarge: "ファイルが 1 MB を超えていて、ルールファイルとしては大きすぎます。ルールは読み込まれませんでした。",
        errorTooMany: "ルールが 5000 件を超えています。ルールは読み込まれませんでした。",
        errorNothingUsable: "App で使えるルールがありません。ルールは読み込まれませんでした。",
        errorUnreadable: "ファイルを読み取れませんでした。ルールは読み込まれませんでした。",
        importedTag: "読み込み済み",
        filterPlaceholder: "サイトを絞り込む"
    )

    static let ko = URLCleanerImportStrings(
        sectionTitle: "추가 규칙",
        emptyCaption: "가져온 규칙이 없습니다. ClearURLs 규칙 파일을 가져오면 더 많은 사이트를 정리합니다.",
        summaryFormat: "%1$@ 가져옴(%2$@): 사이트 %3$d개, 매개변수 %4$d개.",
        importButton: "규칙 파일 가져오기…",
        replaceButton: "교체…",
        openRules: "ClearURLs 규칙 받기",
        fileCaption: "ClearURLs에서 data.min.json을 내려받은 뒤 여기서 가져오세요. 앱이 직접 내려받지는 않습니다.",
        removeButton: "가져온 규칙 제거",
        importTitleFormat: "%@을(를) 가져올까요?",
        replaceTitleFormat: "가져온 규칙을 %@(으)로 교체할까요?",
        addsFormat: "사이트 %2$d개에 매개변수 %1$d개를 추가합니다.",
        changesFormat: "추가 %1$d개, 제거 %2$d개, 그대로 %3$d개.",
        skippedFormat: "앱에서 쓸 수 없는 규칙 %d개(패턴, 리디렉션, 특정 페이지용 규칙)는 가져오지 않습니다.",
        exceptionsFormat: "ClearURLs는 일부 링크를 건너뜁니다(예외 %d개). 여기서는 매개변수가 사이트 전체에서 제거되므로, 링크가 깨지면 가져온 뒤 해당 매개변수를 끄세요.",
        keepsChoices: "끈 매개변수는 그대로 꺼져 있습니다.",
        importConfirm: "가져오기",
        replaceConfirm: "교체",
        cancel: "취소",
        removeTitle: "가져온 규칙을 제거할까요?",
        removeMessageFormat: "사이트 %d개의 가져온 규칙이 더 이상 적용되지 않습니다.",
        removeConfirm: "제거",
        errorNotClearURLs: "ClearURLs 규칙 파일이 아닙니다. 규칙을 가져오지 않았습니다.",
        errorTooLarge: "파일이 1MB를 넘어 규칙 파일로 보기에는 너무 큽니다. 규칙을 가져오지 않았습니다.",
        errorTooMany: "규칙이 5000개를 넘습니다. 규칙을 가져오지 않았습니다.",
        errorNothingUsable: "앱에서 쓸 수 있는 규칙이 없습니다. 규칙을 가져오지 않았습니다.",
        errorUnreadable: "파일을 읽을 수 없습니다. 규칙을 가져오지 않았습니다.",
        importedTag: "가져옴",
        filterPlaceholder: "사이트 필터"
    )

    static let zhHans = URLCleanerImportStrings(
        sectionTitle: "更多规则",
        emptyCaption: "没有导入规则。导入 ClearURLs 规则文件可以覆盖更多网站。",
        summaryFormat: "已导入 %1$@（%2$@）：%3$d 个网站，%4$d 个参数。",
        importButton: "导入规则文件…",
        replaceButton: "替换…",
        openRules: "获取 ClearURLs 规则",
        fileCaption: "先从 ClearURLs 下载 data.min.json，再在这里导入。App 自己不会下载。",
        removeButton: "移除导入的规则",
        importTitleFormat: "导入 %@？",
        replaceTitleFormat: "用 %@ 替换导入的规则？",
        addsFormat: "将加入 %2$d 个网站的 %1$d 个参数。",
        changesFormat: "新增 %1$d 个参数，移除 %2$d 个，不变 %3$d 个。",
        skippedFormat: "有 %d 条规则 App 用不了，不会导入：正则、跳转和只针对某个页面的规则。",
        exceptionsFormat: "ClearURLs 会跳过一些链接（%d 条例外）。这里参数会在整个网站上删除，如果某个链接因此出错，导入后把那个参数勾掉即可。",
        keepsChoices: "你勾掉的参数保持不变。",
        importConfirm: "导入",
        replaceConfirm: "替换",
        cancel: "取消",
        removeTitle: "移除导入的规则？",
        removeMessageFormat: "这 %d 个网站的导入规则将不再生效。",
        removeConfirm: "移除",
        errorNotClearURLs: "这不是 ClearURLs 规则文件，没有导入任何规则。",
        errorTooLarge: "文件超过 1 MB，不像是规则文件，没有导入任何规则。",
        errorTooMany: "规则超过 5000 条，没有导入任何规则。",
        errorNothingUsable: "文件里没有 App 能用的规则，没有导入任何规则。",
        errorUnreadable: "无法读取这个文件，没有导入任何规则。",
        importedTag: "导入",
        filterPlaceholder: "筛选网站"
    )

    static let zhTW = URLCleanerImportStrings(
        sectionTitle: "更多規則",
        emptyCaption: "尚未匯入規則。匯入 ClearURLs 規則檔可以涵蓋更多網站。",
        summaryFormat: "已匯入 %1$@（%2$@）：%3$d 個網站，%4$d 個參數。",
        importButton: "匯入規則檔…",
        replaceButton: "取代…",
        openRules: "取得 ClearURLs 規則",
        fileCaption: "先從 ClearURLs 下載 data.min.json，再在這裡匯入。App 本身不會下載。",
        removeButton: "移除匯入的規則",
        importTitleFormat: "匯入 %@？",
        replaceTitleFormat: "以 %@ 取代匯入的規則？",
        addsFormat: "將加入 %2$d 個網站的 %1$d 個參數。",
        changesFormat: "新增 %1$d 個參數，移除 %2$d 個，不變 %3$d 個。",
        skippedFormat: "有 %d 條規則 App 無法使用，不會匯入：正規表示式、重新導向和只針對單一頁面的規則。",
        exceptionsFormat: "ClearURLs 會略過部分連結（%d 條例外）。這裡參數會在整個網站上移除，若某個連結因此出錯，匯入後取消勾選該參數即可。",
        keepsChoices: "你取消勾選的參數維持不變。",
        importConfirm: "匯入",
        replaceConfirm: "取代",
        cancel: "取消",
        removeTitle: "移除匯入的規則？",
        removeMessageFormat: "這 %d 個網站的匯入規則將不再生效。",
        removeConfirm: "移除",
        errorNotClearURLs: "這不是 ClearURLs 規則檔，未匯入任何規則。",
        errorTooLarge: "檔案超過 1 MB，不像是規則檔，未匯入任何規則。",
        errorTooMany: "規則超過 5000 條，未匯入任何規則。",
        errorNothingUsable: "檔案中沒有 App 能用的規則，未匯入任何規則。",
        errorUnreadable: "無法讀取這個檔案，未匯入任何規則。",
        importedTag: "已匯入",
        filterPlaceholder: "篩選網站"
    )

    static let zhHK = URLCleanerImportStrings(
        sectionTitle: "更多規則",
        emptyCaption: "尚未匯入規則。匯入 ClearURLs 規則檔可以涵蓋更多網站。",
        summaryFormat: "已匯入 %1$@（%2$@）：%3$d 個網站，%4$d 個參數。",
        importButton: "匯入規則檔…",
        replaceButton: "取代…",
        openRules: "取得 ClearURLs 規則",
        fileCaption: "先從 ClearURLs 下載 data.min.json，再在這裡匯入。App 本身不會下載。",
        removeButton: "移除匯入的規則",
        importTitleFormat: "匯入 %@？",
        replaceTitleFormat: "以 %@ 取代匯入的規則？",
        addsFormat: "將加入 %2$d 個網站的 %1$d 個參數。",
        changesFormat: "新增 %1$d 個參數，移除 %2$d 個，不變 %3$d 個。",
        skippedFormat: "有 %d 條規則 App 無法使用，不會匯入：正規表示式、重新導向和只針對單一頁面的規則。",
        exceptionsFormat: "ClearURLs 會略過部分連結（%d 條例外）。這裡參數會在整個網站上移除，若某個連結因此出錯，匯入後取消勾選該參數即可。",
        keepsChoices: "你取消勾選的參數維持不變。",
        importConfirm: "匯入",
        replaceConfirm: "取代",
        cancel: "取消",
        removeTitle: "移除匯入的規則？",
        removeMessageFormat: "這 %d 個網站的匯入規則將不再生效。",
        removeConfirm: "移除",
        errorNotClearURLs: "這不是 ClearURLs 規則檔，未匯入任何規則。",
        errorTooLarge: "檔案超過 1 MB，不像是規則檔，未匯入任何規則。",
        errorTooMany: "規則超過 5000 條，未匯入任何規則。",
        errorNothingUsable: "檔案中沒有 App 能用的規則，未匯入任何規則。",
        errorUnreadable: "無法讀取這個檔案，未匯入任何規則。",
        importedTag: "已匯入",
        filterPlaceholder: "篩選網站"
    )

    static let uk = URLCleanerImportStrings(
        sectionTitle: "Додаткові правила",
        emptyCaption: "Правила не імпортовано. Файл правил ClearURLs охоплює значно більше сайтів.",
        summaryFormat: "%1$@ імпортовано %2$@. Сайтів: %3$d, параметрів: %4$d.",
        importButton: "Імпортувати файл правил…",
        replaceButton: "Замінити…",
        openRules: "Отримати правила ClearURLs",
        fileCaption: "Завантажте data.min.json із ClearURLs та імпортуйте його тут. Застосунок сам нічого не завантажує.",
        removeButton: "Вилучити імпортовані правила",
        importTitleFormat: "Імпортувати %@?",
        replaceTitleFormat: "Замінити імпортовані правила на %@?",
        addsFormat: "Буде додано параметрів: %1$d, сайтів: %2$d.",
        changesFormat: "Додано параметрів: %1$d, вилучено: %2$d, без змін: %3$d.",
        skippedFormat: "Правил, які застосунок не може використати, пропущено: %d. Це шаблони, переспрямування та правила для окремих сторінок.",
        exceptionsFormat: "ClearURLs не чіпає деякі посилання (винятків: %d). Тут параметр вилучається на всьому сайті. Якщо посилання зламається, вимкніть його після імпорту.",
        keepsChoices: "Вимкнені параметри залишаться вимкненими.",
        importConfirm: "Імпортувати",
        replaceConfirm: "Замінити",
        cancel: "Скасувати",
        removeTitle: "Вилучити імпортовані правила?",
        removeMessageFormat: "Імпортовані правила перестануть діяти. Сайтів: %d.",
        removeConfirm: "Вилучити",
        errorNotClearURLs: "Це не файл правил ClearURLs. Жодних правил не імпортовано.",
        errorTooLarge: "Файл більший за 1 МБ, завеликий для файлу правил. Жодних правил не імпортовано.",
        errorTooMany: "У файлі понад 5000 правил. Жодних правил не імпортовано.",
        errorNothingUsable: "У файлі немає правил, які може використати застосунок. Жодних правил не імпортовано.",
        errorUnreadable: "Не вдалося прочитати файл. Жодних правил не імпортовано.",
        importedTag: "Імпортовано",
        filterPlaceholder: "Фільтр сайтів"
    )
}
