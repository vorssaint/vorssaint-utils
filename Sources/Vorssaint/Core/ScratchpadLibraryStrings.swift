// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScratchpadLibraryLabel: Int, CaseIterable {
    case inbox, all, pinned, trash, folders, newFolder, renameFolder, deleteFolder, move
    case pin, unpin, temporary, source, sidebar, search, delete, restore, emptyTrash
    case deleteForever, permanentMessage, importNotes, backup, restoreBackup, exportFolder
    case replaceMessage, folderMessage, liveEditing, failed
    case duplicate, checklistTools, uncheckAll, removeCompleted, createCheckboxOnNewLine
    case previousNote, nextNote
    case calculationMode
    case exchangeRatesToggle, exchangeRatesCaption, updateExchangeRates, updatingExchangeRates
    case exchangeRatesFailed, builtInRates, ratesUpdated
}

struct ScratchpadLibraryStrings {
    let language: AppLanguage
    subscript(_ label: ScratchpadLibraryLabel) -> String {
        if label == .createCheckboxOnNewLine { return "Create checkbox upon new line" }
        if label == .previousNote || label == .nextNote {
            let pair = Self.navigation[language]!
            return label == .previousNote ? pair.0 : pair.1
        }
        if label == .calculationMode { return Self.calculation[language] ?? "Calculation mode" }
        if let extra = Self.extras[language] {
            switch label {
            case .exchangeRatesToggle: return extra.toggle
            case .exchangeRatesCaption: return extra.caption
            case .updateExchangeRates: return extra.update
            case .updatingExchangeRates: return extra.updating
            case .exchangeRatesFailed: return extra.failed
            case .builtInRates: return extra.builtIn
            case .ratesUpdated: return extra.ratesFrom
            default: break
            }
        }
        return Self.translations[language]![label.rawValue]
    }

    private struct ExtraLabels {
        let toggle: String
        let caption: String
        let update: String
        let updating: String
        let failed: String
        let builtIn: String
        let ratesFrom: String
    }

    private static let extras: [AppLanguage: ExtraLabels] = [
        .enUS: ExtraLabels(
            toggle: "Update exchange rates daily",
            caption: "Currency answers work offline with built-in rates. With this on, Vorssaint downloads a small daily rate table from api.frankfurter.dev. Note text is never sent.",
            update: "Update rates now",
            updating: "Updating rates…",
            failed: "Could not update rates. Using the last saved table.",
            builtIn: "Built-in rates",
            ratesFrom: "Rates from %@"),
        .ptBR: ExtraLabels(
            toggle: "Atualizar taxas de câmbio diariamente",
            caption: "As respostas em moeda funcionam offline com taxas integradas. Com esta opção ativada, o Vorssaint baixa uma pequena tabela diária de taxas de api.frankfurter.dev. O texto da nota nunca é enviado.",
            update: "Atualizar taxas agora",
            updating: "Atualizando taxas…",
            failed: "Não foi possível atualizar as taxas. Usando a última tabela salva.",
            builtIn: "Taxas integradas",
            ratesFrom: "Taxas de %@"),
        .es: ExtraLabels(
            toggle: "Actualizar los tipos de cambio a diario",
            caption: "Las respuestas de moneda funcionan sin conexión con tipos integrados. Con esta opción activada, Vorssaint descarga una pequeña tabla diaria desde api.frankfurter.dev. El texto de la nota nunca se envía.",
            update: "Actualizar tipos ahora",
            updating: "Actualizando tipos…",
            failed: "No se pudieron actualizar los tipos. Se usa la última tabla guardada.",
            builtIn: "Tipos integrados",
            ratesFrom: "Tipos de %@"),
        .fr: ExtraLabels(
            toggle: "Mettre à jour les taux de change chaque jour",
            caption: "Les réponses en devises fonctionnent hors ligne avec des taux intégrés. Lorsque cette option est activée, Vorssaint télécharge une petite table quotidienne depuis api.frankfurter.dev. Le texte des notes n’est jamais envoyé.",
            update: "Mettre à jour les taux",
            updating: "Mise à jour des taux…",
            failed: "Impossible de mettre à jour les taux. La dernière table enregistrée est utilisée.",
            builtIn: "Taux intégrés",
            ratesFrom: "Taux du %@"),
        .de: ExtraLabels(
            toggle: "Wechselkurse täglich aktualisieren",
            caption: "Währungsantworten funktionieren offline mit integrierten Kursen. Wenn dies aktiviert ist, lädt Vorssaint eine kleine tägliche Kurstabelle von api.frankfurter.dev. Notiztext wird nie gesendet.",
            update: "Kurse jetzt aktualisieren",
            updating: "Kurse werden aktualisiert…",
            failed: "Kurse konnten nicht aktualisiert werden. Die zuletzt gespeicherte Tabelle wird verwendet.",
            builtIn: "Integrierte Kurse",
            ratesFrom: "Kurse vom %@"),
        .it: ExtraLabels(
            toggle: "Aggiorna i tassi di cambio ogni giorno",
            caption: "Le risposte in valuta funzionano offline con tassi integrati. Con questa opzione attiva, Vorssaint scarica una piccola tabella giornaliera da api.frankfurter.dev. Il testo delle note non viene mai inviato.",
            update: "Aggiorna tassi ora",
            updating: "Aggiornamento tassi…",
            failed: "Impossibile aggiornare i tassi. Viene usata l’ultima tabella salvata.",
            builtIn: "Tassi integrati",
            ratesFrom: "Tassi del %@"),
        .ja: ExtraLabels(
            toggle: "為替レートを毎日更新",
            caption: "通貨の計算は内蔵レートでオフラインでも動作します。これをオンにすると、Vorssaint は api.frankfurter.dev から小さな毎日のレート表をダウンロードします。ノートの本文は送信されません。",
            update: "今すぐレートを更新",
            updating: "レートを更新中…",
            failed: "レートを更新できませんでした。最後に保存した表を使用します。",
            builtIn: "内蔵レート",
            ratesFrom: "%@ のレート"),
        .ko: ExtraLabels(
            toggle: "환율을 매일 업데이트",
            caption: "통화 계산은 내장 환율로 오프라인에서도 작동합니다. 이 옵션을 켜면 Vorssaint가 api.frankfurter.dev에서 작은 일일 환율표를 내려받습니다. 노트 텍스트는 전송되지 않습니다.",
            update: "지금 환율 업데이트",
            updating: "환율 업데이트 중…",
            failed: "환율을 업데이트하지 못했습니다. 마지막으로 저장된 표를 사용합니다.",
            builtIn: "내장 환율",
            ratesFrom: "%@ 기준 환율"),
        .ru: ExtraLabels(
            toggle: "Обновлять курсы валют ежедневно",
            caption: "Расчёты в валютах работают офлайн со встроенными курсами. Если включить этот параметр, Vorssaint загружает небольшую ежедневную таблицу курсов с api.frankfurter.dev. Текст заметок никогда не отправляется.",
            update: "Обновить курсы сейчас",
            updating: "Обновление курсов…",
            failed: "Не удалось обновить курсы. Используется последняя сохранённая таблица.",
            builtIn: "Встроенные курсы",
            ratesFrom: "Курсы от %@"),
        .uk: ExtraLabels(
            toggle: "Оновлювати курси валют щодня",
            caption: "Розрахунки у валютах працюють офлайн із вбудованими курсами. Якщо ввімкнути цей параметр, Vorssaint завантажує невелику щоденну таблицю курсів з api.frankfurter.dev. Текст нотаток ніколи не надсилається.",
            update: "Оновити курси зараз",
            updating: "Оновлення курсів…",
            failed: "Не вдалося оновити курси. Використовується остання збережена таблиця.",
            builtIn: "Вбудовані курси",
            ratesFrom: "Курси від %@"),
        .sk: ExtraLabels(
            toggle: "Denne aktualizovať výmenné kurzy",
            caption: "Prepočty mien fungujú offline s vstavanými kurzami. Po zapnutí Vorssaint stiahne malú dennú tabuľku kurzov z api.frankfurter.dev. Text poznámky sa nikdy neodosiela.",
            update: "Aktualizovať kurzy teraz",
            updating: "Aktualizácia kurzov…",
            failed: "Kurzy sa nepodarilo aktualizovať. Použije sa naposledy uložená tabuľka.",
            builtIn: "Vstavané kurzy",
            ratesFrom: "Kurzy z %@"),
        .tr: ExtraLabels(
            toggle: "Döviz kurlarını her gün güncelle",
            caption: "Döviz yanıtları yerleşik kurlarla çevrimdışı çalışır. Bu açıkken Vorssaint, api.frankfurter.dev adresinden küçük bir günlük kur tablosu indirir. Not metni hiçbir zaman gönderilmez.",
            update: "Kurları şimdi güncelle",
            updating: "Kurlar güncelleniyor…",
            failed: "Kurlar güncellenemedi. Son kaydedilen tablo kullanılıyor.",
            builtIn: "Yerleşik kurlar",
            ratesFrom: "Kurlar: %@"),
        .zhHans: ExtraLabels(
            toggle: "每天更新汇率",
            caption: "货币换算使用内置汇率，可离线工作。开启后，Vorssaint 会从 api.frankfurter.dev 下载一份小型每日汇率表。笔记正文绝不会被发送。",
            update: "立即更新汇率",
            updating: "正在更新汇率…",
            failed: "无法更新汇率。将使用上次保存的汇率表。",
            builtIn: "内置汇率",
            ratesFrom: "汇率日期：%@"),
        .zhTW: ExtraLabels(
            toggle: "每天更新匯率",
            caption: "貨幣換算使用內建匯率，可離線運作。開啟後，Vorssaint 會從 api.frankfurter.dev 下載一份小型每日匯率表。筆記內容絕不會被傳送。",
            update: "立即更新匯率",
            updating: "正在更新匯率…",
            failed: "無法更新匯率。將使用上次儲存的匯率表。",
            builtIn: "內建匯率",
            ratesFrom: "匯率日期：%@"),
        .zhHK: ExtraLabels(
            toggle: "每日更新匯率",
            caption: "貨幣換算使用內置匯率，可離線運作。開啟後，Vorssaint 會從 api.frankfurter.dev 下載一份小型每日匯率表。筆記內容絕不會被傳送。",
            update: "立即更新匯率",
            updating: "正在更新匯率…",
            failed: "無法更新匯率。將使用上次儲存的匯率表。",
            builtIn: "內置匯率",
            ratesFrom: "匯率日期：%@"),
    ]

    private static let calculation: [AppLanguage: String] = [
        .enUS: "Calculation mode", .ptBR: "Modo de cálculo", .es: "Modo de cálculo",
        .fr: "Mode calcul", .de: "Berechnungsmodus", .it: "Modalità calcolo",
        .ja: "計算モード", .ko: "계산 모드", .zhHans: "计算模式", .zhTW: "計算模式",
        .zhHK: "計算模式", .tr: "Hesaplama modu", .ru: "Режим вычислений",
        .uk: "Режим обчислень", .sk: "Režim výpočtov",
    ]

    private static let navigation: [AppLanguage: (String, String)] = [
        .enUS: ("Previous note", "Next note"),
        .ptBR: ("Nota anterior", "Próxima nota"),
        .tr: ("Önceki not", "Sonraki not"),
        .ru: ("Предыдущая заметка", "Следующая заметка"),
        .es: ("Nota anterior", "Nota siguiente"),
        .sk: ("Predchádzajúca poznámka", "Nasledujúca poznámka"),
        .de: ("Vorherige Notiz", "Nächste Notiz"),
        .fr: ("Note précédente", "Note suivante"),
        .it: ("Nota precedente", "Nota successiva"),
        .ja: ("前のノート", "次のノート"),
        .ko: ("이전 노트", "다음 노트"),
        .zhHans: ("上一条笔记", "下一条笔记"),
        .zhTW: ("上一則筆記", "下一則筆記"),
        .zhHK: ("上一則筆記", "下一則筆記"),
        .uk: ("Попередня нотатка", "Наступна нотатка"),
    ]

    private static let translations: [AppLanguage: [String]] = [
        .enUS: ["Inbox", "All notes", "Pinned", "Trash", "Folders", "New folder", "Rename folder", "Delete folder", "Move to folder", "Pin note", "Unpin note", "Temporary note", "Markdown source", "Browse notes", "Search notes", "Move to Trash", "Restore", "Empty Trash", "Delete permanently", "Permanently delete these notes? This cannot be undone.", "Import notes", "Back up Scratchpad", "Restore Scratchpad backup", "Export folder as Markdown", "Replace your notes with this backup? A recovery copy of your current notes will be saved first.", "The notes in this folder will move to Inbox.", "Live Markdown", "The operation could not be completed. Your existing notes were preserved.", "Duplicate note", "Checklist", "Uncheck all", "Remove completed items"],
        .ptBR: ["Entrada", "Todas as notas", "Fixadas", "Lixeira", "Pastas", "Nova pasta", "Renomear pasta", "Excluir pasta", "Mover para pasta", "Fixar nota", "Desafixar nota", "Nota temporária", "Código Markdown", "Explorar notas", "Buscar notas", "Mover para Lixeira", "Restaurar", "Esvaziar Lixeira", "Excluir permanentemente", "Excluir estas notas permanentemente? Não é possível desfazer.", "Importar notas", "Fazer backup do Rascunho", "Restaurar backup do Rascunho", "Exportar pasta como Markdown", "Substituir as notas por este backup? Uma cópia das notas atuais será salva primeiro.", "As notas desta pasta serão movidas para Entrada.", "Markdown ao vivo", "Não foi possível concluir. As notas existentes foram preservadas.", "Duplicar nota", "Lista de tarefas", "Desmarcar tudo", "Remover itens concluídos"],
        .tr: ["Gelen kutusu", "Tüm notlar", "Sabitlenenler", "Çöp Kutusu", "Klasörler", "Yeni klasör", "Klasörü yeniden adlandır", "Klasörü sil", "Klasöre taşı", "Notu sabitle", "Sabitlemeyi kaldır", "Geçici not", "Markdown kaynağı", "Notlara göz at", "Notlarda ara", "Çöp Kutusuna taşı", "Geri yükle", "Çöp Kutusunu boşalt", "Kalıcı olarak sil", "Bu notlar kalıcı olarak silinsin mi? Geri alınamaz.", "Notları içe aktar", "Notları yedekle", "Not yedeğini geri yükle", "Klasörü Markdown olarak dışa aktar", "Notlar bu yedekle değiştirilsin mi? Önce mevcut notların kopyası kaydedilecek.", "Bu klasördeki notlar Gelen kutusuna taşınacak.", "Canlı Markdown", "İşlem tamamlanamadı. Mevcut notlar korundu.", "Notu çoğalt", "Kontrol listesi", "Tüm işaretleri kaldır", "Tamamlanan öğeleri kaldır"],
        .ru: ["Входящие", "Все заметки", "Закреплённые", "Корзина", "Папки", "Новая папка", "Переименовать папку", "Удалить папку", "Переместить в папку", "Закрепить заметку", "Открепить заметку", "Временная заметка", "Исходный Markdown", "Обзор заметок", "Поиск заметок", "В Корзину", "Восстановить", "Очистить Корзину", "Удалить навсегда", "Удалить эти заметки навсегда? Это нельзя отменить.", "Импорт заметок", "Создать резервную копию", "Восстановить резервную копию", "Экспорт папки в Markdown", "Заменить заметки этой копией? Сначала будет сохранена копия текущих заметок.", "Заметки этой папки будут перемещены во Входящие.", "Живой Markdown", "Не удалось завершить операцию. Заметки сохранены.", "Дублировать заметку", "Список задач", "Снять все отметки", "Убрать выполненные пункты"],
        .es: ["Entrada", "Todas las notas", "Fijadas", "Papelera", "Carpetas", "Nueva carpeta", "Renombrar carpeta", "Eliminar carpeta", "Mover a carpeta", "Fijar nota", "Desfijar nota", "Nota temporal", "Fuente Markdown", "Explorar notas", "Buscar notas", "Mover a Papelera", "Restaurar", "Vaciar Papelera", "Eliminar definitivamente", "¿Eliminar estas notas definitivamente? No se puede deshacer.", "Importar notas", "Crear copia de Scratchpad", "Restaurar copia de Scratchpad", "Exportar carpeta como Markdown", "¿Reemplazar las notas con esta copia? Primero se guardará una copia de las notas actuales.", "Las notas de esta carpeta se moverán a Entrada.", "Markdown en vivo", "No se pudo completar la operación. Se conservaron las notas existentes.", "Duplicar nota", "Lista de tareas", "Desmarcar todo", "Quitar elementos completados"],
        .sk: ["Doručené", "Všetky poznámky", "Pripnuté", "Kôš", "Priečinky", "Nový priečinok", "Premenovať priečinok", "Odstrániť priečinok", "Presunúť do priečinka", "Pripnúť poznámku", "Odopnúť poznámku", "Dočasná poznámka", "Zdroj Markdown", "Prehliadať poznámky", "Hľadať poznámky", "Presunúť do Koša", "Obnoviť", "Vyprázdniť Kôš", "Natrvalo odstrániť", "Natrvalo odstrániť tieto poznámky? Toto sa nedá vrátiť.", "Importovať poznámky", "Zálohovať poznámky", "Obnoviť zálohu", "Exportovať priečinok ako Markdown", "Nahradiť poznámky touto zálohou? Najprv sa uloží kópia aktuálnych poznámok.", "Poznámky z priečinka sa presunú do Doručených.", "Živý Markdown", "Operáciu sa nepodarilo dokončiť. Poznámky zostali zachované.", "Duplikovať poznámku", "Kontrolný zoznam", "Zrušiť všetky začiarknutia", "Odstrániť dokončené položky"],
        .de: ["Eingang", "Alle Notizen", "Angeheftet", "Papierkorb", "Ordner", "Neuer Ordner", "Ordner umbenennen", "Ordner löschen", "In Ordner verschieben", "Notiz anheften", "Notiz lösen", "Temporäre Notiz", "Markdown-Quelltext", "Notizen durchsuchen", "Notizen suchen", "In Papierkorb verschieben", "Wiederherstellen", "Papierkorb leeren", "Endgültig löschen", "Diese Notizen endgültig löschen? Dies kann nicht rückgängig gemacht werden.", "Notizen importieren", "Scratchpad sichern", "Scratchpad-Sicherung wiederherstellen", "Ordner als Markdown exportieren", "Notizen durch diese Sicherung ersetzen? Zuerst wird eine Kopie der aktuellen Notizen gespeichert.", "Die Notizen dieses Ordners werden in den Eingang verschoben.", "Live-Markdown", "Der Vorgang konnte nicht abgeschlossen werden. Bestehende Notizen wurden erhalten.", "Notiz duplizieren", "Checkliste", "Alle abwählen", "Erledigte Einträge entfernen"],
        .fr: ["Boîte de réception", "Toutes les notes", "Épinglées", "Corbeille", "Dossiers", "Nouveau dossier", "Renommer le dossier", "Supprimer le dossier", "Déplacer vers un dossier", "Épingler la note", "Désépingler la note", "Note temporaire", "Source Markdown", "Parcourir les notes", "Rechercher des notes", "Mettre à la Corbeille", "Restaurer", "Vider la Corbeille", "Supprimer définitivement", "Supprimer définitivement ces notes ? Cette action est irréversible.", "Importer des notes", "Sauvegarder Scratchpad", "Restaurer une sauvegarde", "Exporter le dossier en Markdown", "Remplacer les notes par cette sauvegarde ? Une copie des notes actuelles sera enregistrée d’abord.", "Les notes de ce dossier seront déplacées dans la boîte de réception.", "Markdown en direct", "L’opération a échoué. Les notes existantes ont été conservées.", "Dupliquer la note", "Liste de tâches", "Tout décocher", "Retirer les éléments terminés"],
        .it: ["Posta in arrivo", "Tutte le note", "Fissate", "Cestino", "Cartelle", "Nuova cartella", "Rinomina cartella", "Elimina cartella", "Sposta nella cartella", "Fissa nota", "Rimuovi fissaggio", "Nota temporanea", "Sorgente Markdown", "Sfoglia note", "Cerca note", "Sposta nel Cestino", "Ripristina", "Svuota Cestino", "Elimina definitivamente", "Eliminare queste note definitivamente? Non è possibile annullare.", "Importa note", "Esegui backup di Scratchpad", "Ripristina backup", "Esporta cartella come Markdown", "Sostituire le note con questo backup? Prima verrà salvata una copia delle note attuali.", "Le note di questa cartella verranno spostate nella Posta in arrivo.", "Markdown dal vivo", "Impossibile completare l’operazione. Le note esistenti sono state conservate.", "Duplica nota", "Lista di controllo", "Deseleziona tutto", "Rimuovi elementi completati"],
        .ja: ["受信箱", "すべてのノート", "ピン留め", "ゴミ箱", "フォルダ", "新規フォルダ", "フォルダ名を変更", "フォルダを削除", "フォルダに移動", "ノートをピン留め", "ピン留めを解除", "一時ノート", "Markdownソース", "ノートを参照", "ノートを検索", "ゴミ箱に移動", "復元", "ゴミ箱を空にする", "完全に削除", "これらのノートを完全に削除しますか？元に戻せません。", "ノートを読み込む", "Scratchpadをバックアップ", "バックアップを復元", "フォルダをMarkdownで書き出す", "このバックアップでノートを置き換えますか？現在のノートのコピーを先に保存します。", "このフォルダのノートは受信箱に移動します。", "ライブMarkdown", "操作を完了できませんでした。既存のノートは保持されました。", "ノートを複製", "チェックリスト", "すべてのチェックを外す", "完了した項目を除く"],
        .ko: ["받은 편지함", "모든 노트", "고정됨", "휴지통", "폴더", "새 폴더", "폴더 이름 변경", "폴더 삭제", "폴더로 이동", "노트 고정", "고정 해제", "임시 노트", "Markdown 소스", "노트 둘러보기", "노트 검색", "휴지통으로 이동", "복원", "휴지통 비우기", "영구 삭제", "이 노트를 영구 삭제하시겠습니까? 되돌릴 수 없습니다.", "노트 가져오기", "Scratchpad 백업", "백업 복원", "폴더를 Markdown으로 내보내기", "이 백업으로 노트를 교체하시겠습니까? 먼저 현재 노트 사본을 저장합니다.", "이 폴더의 노트는 받은 편지함으로 이동합니다.", "실시간 Markdown", "작업을 완료하지 못했습니다. 기존 노트는 보존되었습니다.", "노트 복제", "체크리스트", "모두 체크 해제", "완료한 항목 제거"],
        .zhHans: ["收件箱", "所有笔记", "已置顶", "废纸篓", "文件夹", "新建文件夹", "重命名文件夹", "删除文件夹", "移到文件夹", "置顶笔记", "取消置顶", "临时笔记", "Markdown 源码", "浏览笔记", "搜索笔记", "移到废纸篓", "恢复", "清空废纸篓", "永久删除", "永久删除这些笔记？此操作无法撤销。", "导入笔记", "备份 Scratchpad", "恢复备份", "将文件夹导出为 Markdown", "用此备份替换笔记？将先保存当前笔记的副本。", "此文件夹中的笔记将移到收件箱。", "实时 Markdown", "无法完成操作。现有笔记已保留。", "复制笔记", "清单", "全部取消勾选", "移除已完成项目"],
        .zhTW: ["收件匣", "所有筆記", "已釘選", "垃圾桶", "資料夾", "新增資料夾", "重新命名資料夾", "刪除資料夾", "移至資料夾", "釘選筆記", "取消釘選", "暫存筆記", "Markdown 原始碼", "瀏覽筆記", "搜尋筆記", "移至垃圾桶", "還原", "清空垃圾桶", "永久刪除", "永久刪除這些筆記？此操作無法復原。", "匯入筆記", "備份 Scratchpad", "還原備份", "將資料夾匯出為 Markdown", "以此備份取代筆記？將先儲存目前筆記的副本。", "此資料夾中的筆記將移至收件匣。", "即時 Markdown", "無法完成操作。現有筆記已保留。", "複製筆記", "檢查清單", "全部取消勾選", "移除已完成項目"],
        .zhHK: ["收件匣", "所有筆記", "已置頂", "垃圾桶", "資料夾", "新增資料夾", "重新命名資料夾", "刪除資料夾", "移至資料夾", "置頂筆記", "取消置頂", "暫存筆記", "Markdown 原始碼", "瀏覽筆記", "搜尋筆記", "移至垃圾桶", "還原", "清空垃圾桶", "永久刪除", "永久刪除這些筆記？此操作無法復原。", "匯入筆記", "備份 Scratchpad", "還原備份", "將資料夾匯出為 Markdown", "以此備份取代筆記？會先儲存目前筆記的副本。", "此資料夾中的筆記會移至收件匣。", "即時 Markdown", "無法完成操作。現有筆記已保留。", "複製筆記", "檢查清單", "全部取消勾選", "移除已完成項目"],
        .uk: ["Вхідні", "Усі нотатки", "Закріплені", "Кошик", "Папки", "Нова папка", "Перейменувати папку", "Видалити папку", "Перемістити до папки", "Закріпити нотатку", "Відкріпити нотатку", "Тимчасова нотатка", "Джерело Markdown", "Переглянути нотатки", "Пошук нотаток", "Перемістити до Кошика", "Відновити", "Очистити Кошик", "Видалити назавжди", "Видалити ці нотатки назавжди? Це неможливо скасувати.", "Імпортувати нотатки", "Створити резервну копію", "Відновити резервну копію", "Експортувати папку в Markdown", "Замінити нотатки цією копією? Спочатку буде збережено копію поточних нотаток.", "Нотатки з цієї папки буде переміщено до Вхідних.", "Живий Markdown", "Не вдалося завершити операцію. Наявні нотатки збережено.", "Дублювати нотатку", "Список завдань", "Зняти всі позначки", "Прибрати виконані пункти"]
    ]
}
