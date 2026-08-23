// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the scratchpad, the floating pad for short-lived text.
struct ScratchpadFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let placeholder: String
    let copyAll: String
    let copied: String
    let exportAction: String
    let clearAction: String
    let retentionTitle: String
    let retentionNever: String
    let retentionDay: String
    let retentionWeek: String
    let retentionMonth: String
    let retentionCaption: String
    let closeOnClickOutside: String
    let keepOpen: String
    let backgroundOpacity: String
    let backgroundTranslucent: String
    let backgroundOpaque: String
    let newPad: String
    let padActions: String
    let renamePad: String
    let closePad: String
    let saveName: String
    let cancel: String
    let deletePadMessageFormat: String
    let padLimitFormat: String
    let previewFormatting: String
    let editText: String
}

extension FeatureStrings {
    static func scratchpad(_ language: AppLanguage) -> ScratchpadFeatureStrings {
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

extension ScratchpadFeatureStrings {
    static let enUS = ScratchpadFeatureStrings(
        pageTitle: "Scratchpad",
        hubDescription: "Floating pads for short-lived notes",
        panelCaption: "Quick notes in separate tabs",
        openButton: "Open scratchpad",
        placeholder: "Type anything. It saves by itself.",
        copyAll: "Copy all",
        copied: "Copied",
        exportAction: "Save as file",
        clearAction: "Clear",
        retentionTitle: "Clear on its own",
        retentionNever: "Never",
        retentionDay: "After a day unused",
        retentionWeek: "After a week unused",
        retentionMonth: "After a month unused",
        retentionCaption: "The pad empties itself once the text goes that long without edits.",
        closeOnClickOutside: "Close when I click outside",
        keepOpen: "Keep open",
        backgroundOpacity: "Pad background",
        backgroundTranslucent: "Translucent",
        backgroundOpaque: "Opaque",
        newPad: "New scratchpad",
        padActions: "Scratchpad actions",
        renamePad: "Rename scratchpad",
        closePad: "Close scratchpad",
        saveName: "Save",
        cancel: "Cancel",
        deletePadMessageFormat: "Delete “%@” and everything in it?",
        padLimitFormat: "You can keep up to %d scratchpads",
        previewFormatting: "Show formatting",
        editText: "Edit text"
    )

    static let ptBR = ScratchpadFeatureStrings(
        pageTitle: "Rascunho",
        hubDescription: "Blocos flutuantes para anotações passageiras",
        panelCaption: "Notas rápidas em abas separadas",
        openButton: "Abrir rascunho",
        placeholder: "Digite qualquer coisa. Salva sozinho.",
        copyAll: "Copiar tudo",
        copied: "Copiado",
        exportAction: "Salvar como arquivo",
        clearAction: "Limpar",
        retentionTitle: "Limpar sozinho",
        retentionNever: "Nunca",
        retentionDay: "Após um dia sem uso",
        retentionWeek: "Após uma semana sem uso",
        retentionMonth: "Após um mês sem uso",
        retentionCaption: "O bloco se esvazia quando o texto passa esse tempo sem edições.",
        closeOnClickOutside: "Fechar ao clicar fora",
        keepOpen: "Manter aberto",
        backgroundOpacity: "Fundo do bloco",
        backgroundTranslucent: "Translúcido",
        backgroundOpaque: "Opaco",
        newPad: "Novo rascunho",
        padActions: "Ações do rascunho",
        renamePad: "Renomear rascunho",
        closePad: "Fechar rascunho",
        saveName: "Salvar",
        cancel: "Cancelar",
        deletePadMessageFormat: "Apagar “%@” e todo o conteúdo?",
        padLimitFormat: "Você pode manter até %d rascunhos",
        previewFormatting: "Ver formatação",
        editText: "Editar texto"
    )

    static let tr = ScratchpadFeatureStrings(
        pageTitle: "Karalama defteri",
        hubDescription: "Kısa süreli notlar için sekmeli yüzen not alanları",
        panelCaption: "Ayrı sekmelerde hızlı notlar",
        openButton: "Karalama defterini aç",
        placeholder: "Bir şeyler yazın. Kendiliğinden kaydedilir.",
        copyAll: "Tümünü kopyala",
        copied: "Kopyalandı",
        exportAction: "Dosya olarak kaydet",
        clearAction: "Temizle",
        retentionTitle: "Kendiliğinden temizle",
        retentionNever: "Hiçbir zaman",
        retentionDay: "Bir gün kullanılmayınca",
        retentionWeek: "Bir hafta kullanılmayınca",
        retentionMonth: "Bir ay kullanılmayınca",
        retentionCaption: "Metin bu süre boyunca düzenlenmezse defter kendini boşaltır.",
        closeOnClickOutside: "Dışarı tıklayınca kapat",
        keepOpen: "Açık tut",
        backgroundOpacity: "Defter arka planı",
        backgroundTranslucent: "Yarı saydam",
        backgroundOpaque: "Opak",
        newPad: "Yeni karalama defteri",
        padActions: "Karalama defteri işlemleri",
        renamePad: "Karalama defterini yeniden adlandır",
        closePad: "Karalama defterini kapat",
        saveName: "Kaydet",
        cancel: "Vazgeç",
        deletePadMessageFormat: "“%@” ve içindeki her şey silinsin mi?",
        padLimitFormat: "%d adede kadar karalama defteri tutabilirsiniz",
        previewFormatting: "Biçimlendirmeyi göster",
        editText: "Metni düzenle"
    )

    static let ru = ScratchpadFeatureStrings(
        pageTitle: "Черновик",
        hubDescription: "Плавающие блокноты с вкладками для коротких заметок",
        panelCaption: "Быстрые заметки в отдельных вкладках",
        openButton: "Открыть черновик",
        placeholder: "Напишите что угодно. Сохраняется само.",
        copyAll: "Скопировать всё",
        copied: "Скопировано",
        exportAction: "Сохранить как файл",
        clearAction: "Очистить",
        retentionTitle: "Очищать автоматически",
        retentionNever: "Никогда",
        retentionDay: "Через день без правок",
        retentionWeek: "Через неделю без правок",
        retentionMonth: "Через месяц без правок",
        retentionCaption: "Черновик очищается сам, если текст столько времени не редактировался.",
        closeOnClickOutside: "Закрывать при щелчке снаружи",
        keepOpen: "Оставить открытым",
        backgroundOpacity: "Фон черновика",
        backgroundTranslucent: "Полупрозрачный",
        backgroundOpaque: "Непрозрачный",
        newPad: "Новый черновик",
        padActions: "Действия с черновиком",
        renamePad: "Переименовать черновик",
        closePad: "Закрыть черновик",
        saveName: "Сохранить",
        cancel: "Отмена",
        deletePadMessageFormat: "Удалить «%@» вместе со всем содержимым?",
        padLimitFormat: "Можно хранить до %d черновиков",
        previewFormatting: "Показать форматирование",
        editText: "Редактировать текст"
    )

    static let es = ScratchpadFeatureStrings(
        pageTitle: "Borrador",
        hubDescription: "Blocs flotantes con pestañas para notas pasajeras",
        panelCaption: "Notas rápidas en pestañas separadas",
        openButton: "Abrir borrador",
        placeholder: "Escribe cualquier cosa. Se guarda solo.",
        copyAll: "Copiar todo",
        copied: "Copiado",
        exportAction: "Guardar como archivo",
        clearAction: "Limpiar",
        retentionTitle: "Limpiar solo",
        retentionNever: "Nunca",
        retentionDay: "Tras un día sin uso",
        retentionWeek: "Tras una semana sin uso",
        retentionMonth: "Tras un mes sin uso",
        retentionCaption: "El bloc se vacía cuando el texto pasa ese tiempo sin cambios.",
        closeOnClickOutside: "Cerrar al hacer clic fuera",
        keepOpen: "Mantener abierto",
        backgroundOpacity: "Fondo del borrador",
        backgroundTranslucent: "Translúcido",
        backgroundOpaque: "Opaco",
        newPad: "Nuevo borrador",
        padActions: "Acciones del borrador",
        renamePad: "Renombrar borrador",
        closePad: "Cerrar borrador",
        saveName: "Guardar",
        cancel: "Cancelar",
        deletePadMessageFormat: "¿Eliminar «%@» y todo su contenido?",
        padLimitFormat: "Puedes guardar hasta %d borradores",
        previewFormatting: "Ver formato",
        editText: "Editar texto"
    )

    static let de = ScratchpadFeatureStrings(
        pageTitle: "Schmierzettel",
        hubDescription: "Schwebende Zettel mit Tabs für kurzlebige Notizen",
        panelCaption: "Schnelle Notizen in eigenen Tabs",
        openButton: "Schmierzettel öffnen",
        placeholder: "Einfach lostippen. Wird von selbst gesichert.",
        copyAll: "Alles kopieren",
        copied: "Kopiert",
        exportAction: "Als Datei sichern",
        clearAction: "Leeren",
        retentionTitle: "Automatisch leeren",
        retentionNever: "Nie",
        retentionDay: "Nach einem Tag ohne Änderung",
        retentionWeek: "Nach einer Woche ohne Änderung",
        retentionMonth: "Nach einem Monat ohne Änderung",
        retentionCaption: "Der Zettel leert sich, wenn der Text so lange nicht bearbeitet wurde.",
        closeOnClickOutside: "Beim Klick außerhalb schließen",
        keepOpen: "Offen halten",
        backgroundOpacity: "Hintergrund des Zettels",
        backgroundTranslucent: "Durchscheinend",
        backgroundOpaque: "Deckend",
        newPad: "Neuer Schmierzettel",
        padActions: "Schmierzettelaktionen",
        renamePad: "Schmierzettel umbenennen",
        closePad: "Schmierzettel schließen",
        saveName: "Sichern",
        cancel: "Abbrechen",
        deletePadMessageFormat: "„%@“ und den gesamten Inhalt löschen?",
        padLimitFormat: "Du kannst bis zu %d Schmierzettel behalten",
        previewFormatting: "Formatierung zeigen",
        editText: "Text bearbeiten"
    )

    static let fr = ScratchpadFeatureStrings(
        pageTitle: "Brouillon",
        hubDescription: "Des blocs flottants à onglets pour les notes éphémères",
        panelCaption: "Des notes rapides dans des onglets séparés",
        openButton: "Ouvrir le brouillon",
        placeholder: "Écrivez ce que vous voulez. Tout s'enregistre tout seul.",
        copyAll: "Tout copier",
        copied: "Copié",
        exportAction: "Enregistrer dans un fichier",
        clearAction: "Effacer",
        retentionTitle: "Effacer automatiquement",
        retentionNever: "Jamais",
        retentionDay: "Après un jour sans modification",
        retentionWeek: "Après une semaine sans modification",
        retentionMonth: "Après un mois sans modification",
        retentionCaption: "Le bloc se vide quand le texte reste aussi longtemps sans modification.",
        closeOnClickOutside: "Fermer si je clique à l’extérieur",
        keepOpen: "Garder ouvert",
        backgroundOpacity: "Fond du brouillon",
        backgroundTranslucent: "Translucide",
        backgroundOpaque: "Opaque",
        newPad: "Nouveau brouillon",
        padActions: "Actions du brouillon",
        renamePad: "Renommer le brouillon",
        closePad: "Fermer le brouillon",
        saveName: "Enregistrer",
        cancel: "Annuler",
        deletePadMessageFormat: "Supprimer « %@ » et tout son contenu ?",
        padLimitFormat: "Vous pouvez conserver jusqu’à %d brouillons",
        previewFormatting: "Afficher la mise en forme",
        editText: "Modifier le texte"
    )

    static let it = ScratchpadFeatureStrings(
        pageTitle: "Bozza",
        hubDescription: "Blocchi fluttuanti a schede per note usa e getta",
        panelCaption: "Note rapide in schede separate",
        openButton: "Apri bozza",
        placeholder: "Scrivi qualsiasi cosa. Si salva da sola.",
        copyAll: "Copia tutto",
        copied: "Copiato",
        exportAction: "Salva come file",
        clearAction: "Svuota",
        retentionTitle: "Svuota automaticamente",
        retentionNever: "Mai",
        retentionDay: "Dopo un giorno senza modifiche",
        retentionWeek: "Dopo una settimana senza modifiche",
        retentionMonth: "Dopo un mese senza modifiche",
        retentionCaption: "Il blocco si svuota quando il testo resta così a lungo senza modifiche.",
        closeOnClickOutside: "Chiudi quando clicco fuori",
        keepOpen: "Mantieni aperto",
        backgroundOpacity: "Sfondo della bozza",
        backgroundTranslucent: "Traslucido",
        backgroundOpaque: "Opaco",
        newPad: "Nuova bozza",
        padActions: "Azioni della bozza",
        renamePad: "Rinomina bozza",
        closePad: "Chiudi bozza",
        saveName: "Salva",
        cancel: "Annulla",
        deletePadMessageFormat: "Eliminare “%@” e tutto il contenuto?",
        padLimitFormat: "Puoi conservare fino a %d bozze",
        previewFormatting: "Mostra formattazione",
        editText: "Modifica testo"
    )

    static let ja = ScratchpadFeatureStrings(
        pageTitle: "クイックメモ",
        hubDescription: "一時的なメモをタブで分けられるフローティングパッド",
        panelCaption: "タブで分けて自動保存するクイックメモ",
        openButton: "クイックメモを開く",
        placeholder: "何でも入力してください。自動で保存されます。",
        copyAll: "すべてコピー",
        copied: "コピーしました",
        exportAction: "ファイルとして保存",
        clearAction: "消去",
        retentionTitle: "自動で消去",
        retentionNever: "しない",
        retentionDay: "1日使わなかったら",
        retentionWeek: "1週間使わなかったら",
        retentionMonth: "1か月使わなかったら",
        retentionCaption: "その期間編集がないと、メモは自動で空になります。",
        closeOnClickOutside: "外側をクリックしたら閉じる",
        keepOpen: "開いたままにする",
        backgroundOpacity: "メモの背景",
        backgroundTranslucent: "半透明",
        backgroundOpaque: "不透明",
        newPad: "新しいクイックメモ",
        padActions: "クイックメモの操作",
        renamePad: "名前を変更",
        closePad: "クイックメモを閉じる",
        saveName: "保存",
        cancel: "キャンセル",
        deletePadMessageFormat: "「%@」とその内容をすべて削除しますか？",
        padLimitFormat: "クイックメモは最大%d個まで作成できます",
        previewFormatting: "書式を表示",
        editText: "テキストを編集"
    )

    static let ko = ScratchpadFeatureStrings(
        pageTitle: "빠른 메모",
        hubDescription: "짧은 메모를 탭으로 나누는 플로팅 메모판",
        panelCaption: "각 탭에 따로 저장되는 빠른 메모",
        openButton: "빠른 메모 열기",
        placeholder: "아무거나 입력하세요. 자동으로 저장됩니다.",
        copyAll: "전체 복사",
        copied: "복사됨",
        exportAction: "파일로 저장",
        clearAction: "지우기",
        retentionTitle: "자동으로 지우기",
        retentionNever: "안 함",
        retentionDay: "하루 동안 사용하지 않으면",
        retentionWeek: "일주일 동안 사용하지 않으면",
        retentionMonth: "한 달 동안 사용하지 않으면",
        retentionCaption: "그 기간 동안 편집이 없으면 메모가 자동으로 비워집니다.",
        closeOnClickOutside: "바깥을 클릭하면 닫기",
        keepOpen: "열어 두기",
        backgroundOpacity: "메모 배경",
        backgroundTranslucent: "반투명",
        backgroundOpaque: "불투명",
        newPad: "새 빠른 메모",
        padActions: "빠른 메모 동작",
        renamePad: "빠른 메모 이름 변경",
        closePad: "빠른 메모 닫기",
        saveName: "저장",
        cancel: "취소",
        deletePadMessageFormat: "“%@” 및 모든 내용을 삭제할까요?",
        padLimitFormat: "빠른 메모는 최대 %d개까지 만들 수 있습니다",
        previewFormatting: "서식 보기",
        editText: "텍스트 편집"
    )

    static let zhHans = ScratchpadFeatureStrings(
        pageTitle: "草稿板",
        hubDescription: "用标签页整理临时笔记的浮动记事板",
        panelCaption: "在独立标签页中自动保存的速记",
        openButton: "打开草稿板",
        placeholder: "随便写点什么，会自动保存。",
        copyAll: "全部拷贝",
        copied: "已拷贝",
        exportAction: "存储为文件",
        clearAction: "清空",
        retentionTitle: "自动清空",
        retentionNever: "从不",
        retentionDay: "一天未使用后",
        retentionWeek: "一周未使用后",
        retentionMonth: "一个月未使用后",
        retentionCaption: "文本超过该时间没有编辑时，草稿板会自动清空。",
        closeOnClickOutside: "点击外部时关闭",
        keepOpen: "保持打开",
        backgroundOpacity: "草稿板背景",
        backgroundTranslucent: "半透明",
        backgroundOpaque: "不透明",
        newPad: "新建草稿板",
        padActions: "草稿板操作",
        renamePad: "重命名草稿板",
        closePad: "关闭草稿板",
        saveName: "存储",
        cancel: "取消",
        deletePadMessageFormat: "删除“%@”及其中的全部内容？",
        padLimitFormat: "最多可保留 %d 个草稿板",
        previewFormatting: "显示格式",
        editText: "编辑文本"
    )

    static let zhTW = ScratchpadFeatureStrings(
        pageTitle: "草稿板",
        hubDescription: "用分頁整理臨時筆記的浮動記事板",
        panelCaption: "在不同分頁中自動儲存的快速筆記",
        openButton: "打開草稿板",
        placeholder: "隨手寫點什麼，會自動儲存。",
        copyAll: "全部拷貝",
        copied: "已拷貝",
        exportAction: "儲存為檔案",
        clearAction: "清空",
        retentionTitle: "自動清空",
        retentionNever: "永不",
        retentionDay: "一天未使用後",
        retentionWeek: "一週未使用後",
        retentionMonth: "一個月未使用後",
        retentionCaption: "文字超過該時間沒有編輯時，草稿板會自動清空。",
        closeOnClickOutside: "點一下外部時關閉",
        keepOpen: "保持開啟",
        backgroundOpacity: "草稿板背景",
        backgroundTranslucent: "半透明",
        backgroundOpaque: "不透明",
        newPad: "新增草稿板",
        padActions: "草稿板操作",
        renamePad: "重新命名草稿板",
        closePad: "關閉草稿板",
        saveName: "儲存",
        cancel: "取消",
        deletePadMessageFormat: "刪除「%@」和其中的所有內容？",
        padLimitFormat: "最多可保留 %d 個草稿板",
        previewFormatting: "顯示格式",
        editText: "編輯文字"
    )

    static let zhHK = ScratchpadFeatureStrings(
        pageTitle: "草稿板",
        hubDescription: "用分頁整理臨時筆記的浮動記事板",
        panelCaption: "在不同分頁中自動儲存的快速筆記",
        openButton: "開啟草稿板",
        placeholder: "隨手寫些什麼，會自動儲存。",
        copyAll: "全部拷貝",
        copied: "已拷貝",
        exportAction: "儲存為檔案",
        clearAction: "清空",
        retentionTitle: "自動清空",
        retentionNever: "永不",
        retentionDay: "一天未使用後",
        retentionWeek: "一星期未使用後",
        retentionMonth: "一個月未使用後",
        retentionCaption: "文字超過該時間沒有編輯，草稿板會自動清空。",
        closeOnClickOutside: "點一下外部時關閉",
        keepOpen: "保持開啟",
        backgroundOpacity: "草稿板背景",
        backgroundTranslucent: "半透明",
        backgroundOpaque: "不透明",
        newPad: "新增草稿板",
        padActions: "草稿板操作",
        renamePad: "重新命名草稿板",
        closePad: "關閉草稿板",
        saveName: "儲存",
        cancel: "取消",
        deletePadMessageFormat: "刪除「%@」及當中的所有內容？",
        padLimitFormat: "最多可保留 %d 個草稿板",
        previewFormatting: "顯示格式",
        editText: "編輯文字"
    )
}
