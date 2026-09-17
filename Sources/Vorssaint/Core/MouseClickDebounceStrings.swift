// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseClickDebounceStrings {
    let title: String
    let caption: String
    let moreOptions: String
    let windowLabel: String
    let windowCaption: String
}

extension FeatureStrings {
    static func mouseClickDebounce(_ language: AppLanguage) -> MouseClickDebounceStrings {
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

extension MouseClickDebounceStrings {
    static let enUS = MouseClickDebounceStrings(
        title: "Extra click filter",
        caption: "Ignores rapid extra clicks from worn mouse buttons without slowing normal clicks.",
        moreOptions: "More options",
        windowLabel: "Filter window",
        windowCaption: "A repeated click inside this interval is treated as an accidental duplicate."
    )

    static let ptBR = MouseClickDebounceStrings(
        title: "Filtro de cliques extras",
        caption: "Ignora cliques extras rápidos de botões desgastados sem atrasar cliques normais.",
        moreOptions: "Mais opções",
        windowLabel: "Janela do filtro",
        windowCaption: "Um clique repetido dentro deste intervalo é tratado como duplicação acidental."
    )

    static let tr = MouseClickDebounceStrings(
        title: "Tıklama filtresi",
        caption: "Aşınmış fare düğmelerinin hızlı ek tıklamalarını normal tıklamaları geciktirmeden yok sayar.",
        moreOptions: "Daha fazla seçenek",
        windowLabel: "Filtre aralığı",
        windowCaption: "Bu aralıkta tekrarlanan tıklama yanlışlıkla yinelenmiş sayılır."
    )

    static let ru = MouseClickDebounceStrings(
        title: "Фильтр кликов",
        caption: "Игнорирует быстрые лишние клики изношенных кнопок мыши без задержки обычных кликов.",
        moreOptions: "Дополнительные параметры",
        windowLabel: "Интервал фильтра",
        windowCaption: "Повторный клик в этом интервале считается случайным повтором."
    )

    static let es = MouseClickDebounceStrings(
        title: "Filtro de clics",
        caption: "Ignora clics extra rápidos de botones desgastados sin retrasar los clics normales.",
        moreOptions: "Más opciones",
        windowLabel: "Intervalo del filtro",
        windowCaption: "Un clic repetido dentro de este intervalo se considera una repetición accidental."
    )

    static let de = MouseClickDebounceStrings(
        title: "Klickfilter",
        caption: "Ignoriert schnelle zusätzliche Klicks abgenutzter Maustasten, ohne normale Klicks zu verzögern.",
        moreOptions: "Weitere Optionen",
        windowLabel: "Filterzeitraum",
        windowCaption: "Ein wiederholter Klick in diesem Zeitraum gilt als versehentliche Wiederholung."
    )

    static let fr = MouseClickDebounceStrings(
        title: "Filtre de clics",
        caption: "Ignore les clics supplémentaires rapides des boutons usés sans retarder les clics normaux.",
        moreOptions: "Plus d’options",
        windowLabel: "Intervalle du filtre",
        windowCaption: "Un clic répété dans cet intervalle est considéré comme une répétition accidentelle."
    )

    static let it = MouseClickDebounceStrings(
        title: "Filtro clic",
        caption: "Ignora i clic extra rapidi dei pulsanti usurati senza ritardare i clic normali.",
        moreOptions: "Altre opzioni",
        windowLabel: "Intervallo del filtro",
        windowCaption: "Un clic ripetuto in questo intervallo viene considerato una ripetizione accidentale."
    )

    static let ja = MouseClickDebounceStrings(
        title: "クリックの誤入力防止",
        caption: "摩耗したマウスボタンの素早い余分なクリックを、通常のクリックを遅らせずに無視します。",
        moreOptions: "その他のオプション",
        windowLabel: "フィルタ時間",
        windowCaption: "この時間内の繰り返しクリックは誤った重複として扱われます。"
    )

    static let ko = MouseClickDebounceStrings(
        title: "클릭 중복 방지",
        caption: "마모된 마우스 버튼의 빠른 추가 클릭을 일반 클릭 지연 없이 무시합니다.",
        moreOptions: "추가 옵션",
        windowLabel: "필터 시간",
        windowCaption: "이 시간 안에 반복된 클릭은 실수로 중복된 클릭으로 처리됩니다."
    )

    static let zhHans = MouseClickDebounceStrings(
        title: "点击防抖",
        caption: "忽略磨损鼠标按键产生的快速多余点击，不延迟正常点击。",
        moreOptions: "更多选项",
        windowLabel: "过滤时段",
        windowCaption: "此时段内的重复点击会被视为意外重复。"
    )

    static let zhTW = MouseClickDebounceStrings(
        title: "點按防抖",
        caption: "忽略磨損滑鼠按鍵產生的快速多餘點按，不延遲正常點按。",
        moreOptions: "更多選項",
        windowLabel: "過濾時段",
        windowCaption: "此時段內的重複點按會視為意外重複。"
    )

    static let zhHK = MouseClickDebounceStrings(
        title: "點按防抖",
        caption: "忽略磨損滑鼠按鍵產生的快速多餘點按，不延遲正常點按。",
        moreOptions: "更多選項",
        windowLabel: "過濾時段",
        windowCaption: "此時段內的重複點按會視為意外重複。"
    )
}
