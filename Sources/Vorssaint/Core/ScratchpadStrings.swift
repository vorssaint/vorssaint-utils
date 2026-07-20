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
        hubDescription: "A floating pad for short-lived notes",
        panelCaption: "Quick notes that save themselves",
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
        retentionCaption: "The pad empties itself once the text goes that long without edits."
    )

    static let ptBR = ScratchpadFeatureStrings(
        pageTitle: "Rascunho",
        hubDescription: "Um bloco flutuante para anotações passageiras",
        panelCaption: "Notas rápidas que se salvam sozinhas",
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
        retentionCaption: "O bloco se esvazia quando o texto passa esse tempo sem edições."
    )

    static let tr = ScratchpadFeatureStrings(
        pageTitle: "Karalama defteri",
        hubDescription: "Kısa ömürlü notlar için yüzen bir not alanı",
        panelCaption: "Kendini kaydeden hızlı notlar",
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
        retentionCaption: "Metin bu süre boyunca düzenlenmezse defter kendini boşaltır."
    )

    static let ru = ScratchpadFeatureStrings(
        pageTitle: "Черновик",
        hubDescription: "Плавающий блокнот для коротких заметок",
        panelCaption: "Быстрые заметки, которые сохраняются сами",
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
        retentionCaption: "Черновик очищается сам, если текст столько времени не редактировался."
    )

    static let es = ScratchpadFeatureStrings(
        pageTitle: "Borrador",
        hubDescription: "Un bloc flotante para notas pasajeras",
        panelCaption: "Notas rápidas que se guardan solas",
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
        retentionCaption: "El bloc se vacía cuando el texto pasa ese tiempo sin cambios."
    )

    static let de = ScratchpadFeatureStrings(
        pageTitle: "Schmierzettel",
        hubDescription: "Ein schwebender Zettel für kurzlebige Notizen",
        panelCaption: "Schnelle Notizen, die sich selbst sichern",
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
        retentionCaption: "Der Zettel leert sich, wenn der Text so lange nicht bearbeitet wurde."
    )

    static let fr = ScratchpadFeatureStrings(
        pageTitle: "Brouillon",
        hubDescription: "Un bloc flottant pour les notes éphémères",
        panelCaption: "Des notes rapides qui s'enregistrent toutes seules",
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
        retentionCaption: "Le bloc se vide quand le texte reste aussi longtemps sans modification."
    )

    static let it = ScratchpadFeatureStrings(
        pageTitle: "Bozza",
        hubDescription: "Un blocco fluttuante per note usa e getta",
        panelCaption: "Note rapide che si salvano da sole",
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
        retentionCaption: "Il blocco si svuota quando il testo resta così a lungo senza modifiche."
    )

    static let ja = ScratchpadFeatureStrings(
        pageTitle: "クイックメモ",
        hubDescription: "一時的なメモのためのフローティングパッド",
        panelCaption: "自動で保存されるクイックメモ",
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
        retentionCaption: "その期間編集がないと、メモは自動で空になります。"
    )

    static let ko = ScratchpadFeatureStrings(
        pageTitle: "빠른 메모",
        hubDescription: "잠깐 쓰는 메모를 위한 떠 있는 메모판",
        panelCaption: "자동으로 저장되는 빠른 메모",
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
        retentionCaption: "그 기간 동안 편집이 없으면 메모가 자동으로 비워집니다."
    )

    static let zhHans = ScratchpadFeatureStrings(
        pageTitle: "草稿板",
        hubDescription: "用于临时笔记的浮动便笺",
        panelCaption: "自动保存的快速笔记",
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
        retentionCaption: "文本超过该时间没有编辑时，草稿板会自动清空。"
    )

    static let zhTW = ScratchpadFeatureStrings(
        pageTitle: "草稿板",
        hubDescription: "存放臨時筆記的浮動便箋",
        panelCaption: "自動儲存的快速筆記",
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
        retentionCaption: "文字超過該時間沒有編輯時，草稿板會自動清空。"
    )

    static let zhHK = ScratchpadFeatureStrings(
        pageTitle: "草稿板",
        hubDescription: "存放臨時筆記的浮動便箋",
        panelCaption: "自動儲存的快速筆記",
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
        retentionCaption: "文字超過該時間沒有編輯，草稿板會自動清空。"
    )
}
