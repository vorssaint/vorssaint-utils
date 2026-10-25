// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderDockReplacementStrings {
    let enableLabel: String
    let caption: String
    let appLabel: String
    let chooseApp: String
    let noApp: String
    let invalidApp: String
    let clearSelection: String
}

extension FeatureStrings {
    static func finderDockReplacement(_ language: AppLanguage) -> FinderDockReplacementStrings {
        switch language {
        case .enUS: return .init(
            enableLabel: "Open another app from Finder’s Dock icon",
            caption: "Click the Finder icon in the Dock to open your chosen app. The icon stays unchanged.",
            appLabel: "App",
            chooseApp: "Choose app…",
            noApp: "None",
            invalidApp: "Choose an available app other than Finder or Vorssaint.",
            clearSelection: "Clear selection")
        case .ptBR: return .init(
            enableLabel: "Abrir outro app pelo ícone do Finder no Dock",
            caption: "Clique no ícone do Finder no Dock para abrir o app escolhido. O ícone permanece igual.",
            appLabel: "App",
            chooseApp: "Escolher app…",
            noApp: "Nenhum",
            invalidApp: "Escolha um app disponível que não seja o Finder ou o Vorssaint.",
            clearSelection: "Limpar seleção")
        case .tr: return .init(
            enableLabel: "Finder’ın Dock simgesinden başka bir uygulama aç",
            caption: "Seçtiğiniz uygulamayı açmak için Dock’taki Finder simgesine tıklayın. Simge değişmez.",
            appLabel: "Uygulama",
            chooseApp: "Uygulama seç…",
            noApp: "Yok",
            invalidApp: "Finder veya Vorssaint dışında kullanılabilir bir uygulama seçin.",
            clearSelection: "Seçimi temizle")
        case .ru: return .init(
            enableLabel: "Открывать другое приложение значком Finder в Dock",
            caption: "Нажмите значок Finder в Dock, чтобы открыть выбранное приложение. Значок не изменится.",
            appLabel: "Приложение",
            chooseApp: "Выбрать приложение…",
            noApp: "Нет",
            invalidApp: "Выберите доступное приложение, кроме Finder и Vorssaint.",
            clearSelection: "Очистить выбор")
        case .es: return .init(
            enableLabel: "Abrir otra app desde el icono del Finder en el Dock",
            caption: "Haz clic en el icono del Finder en el Dock para abrir la app elegida. El icono no cambia.",
            appLabel: "App",
            chooseApp: "Elegir app…",
            noApp: "Ninguna",
            invalidApp: "Elige una app disponible que no sea el Finder ni Vorssaint.",
            clearSelection: "Borrar selección")
        case .sk: return .init(
            enableLabel: "Otvárať inú aplikáciu ikonou Finderu v Docku",
            caption: "Kliknutím na ikonu Finderu v Docku otvoríte vybranú aplikáciu. Ikona sa nezmení.",
            appLabel: "Aplikácia",
            chooseApp: "Vybrať aplikáciu…",
            noApp: "Žiadna",
            invalidApp: "Vyberte dostupnú aplikáciu okrem Finderu a Vorssaintu.",
            clearSelection: "Zrušiť výber")
        case .de: return .init(
            enableLabel: "Andere App über das Finder-Symbol im Dock öffnen",
            caption: "Klicke auf das Finder-Symbol im Dock, um die gewählte App zu öffnen. Das Symbol bleibt unverändert.",
            appLabel: "App",
            chooseApp: "App auswählen…",
            noApp: "Keine",
            invalidApp: "Wähle eine verfügbare App außer Finder oder Vorssaint.",
            clearSelection: "Auswahl aufheben")
        case .fr: return .init(
            enableLabel: "Ouvrir une autre app depuis l’icône du Finder dans le Dock",
            caption: "Cliquez sur l’icône du Finder dans le Dock pour ouvrir l’app choisie. L’icône reste inchangée.",
            appLabel: "App",
            chooseApp: "Choisir une app…",
            noApp: "Aucune",
            invalidApp: "Choisissez une app disponible autre que le Finder ou Vorssaint.",
            clearSelection: "Effacer la sélection")
        case .it: return .init(
            enableLabel: "Apri un’altra app dall’icona del Finder nel Dock",
            caption: "Fai clic sull’icona del Finder nel Dock per aprire l’app scelta. L’icona resta invariata.",
            appLabel: "App",
            chooseApp: "Scegli app…",
            noApp: "Nessuna",
            invalidApp: "Scegli un’app disponibile diversa dal Finder o da Vorssaint.",
            clearSelection: "Cancella selezione")
        case .ja: return .init(
            enableLabel: "DockのFinderアイコンから別のアプリを開く",
            caption: "DockのFinderアイコンをクリックすると、選択したアプリが開きます。アイコンは変わりません。",
            appLabel: "アプリ",
            chooseApp: "アプリを選択…",
            noApp: "なし",
            invalidApp: "FinderとVorssaint以外の利用可能なアプリを選択してください。",
            clearSelection: "選択を解除")
        case .ko: return .init(
            enableLabel: "Dock의 Finder 아이콘으로 다른 앱 열기",
            caption: "Dock의 Finder 아이콘을 클릭하면 선택한 앱이 열립니다. 아이콘은 바뀌지 않습니다.",
            appLabel: "앱",
            chooseApp: "앱 선택…",
            noApp: "없음",
            invalidApp: "Finder 또는 Vorssaint 이외의 사용 가능한 앱을 선택하세요.",
            clearSelection: "선택 지우기")
        case .uk: return .init(
            enableLabel: "Відкривати іншу програму значком Finder у Dock",
            caption: "Натисніть значок Finder у Dock, щоб відкрити вибрану програму. Значок не зміниться.",
            appLabel: "Програма",
            chooseApp: "Вибрати програму…",
            noApp: "Немає",
            invalidApp: "Виберіть доступну програму, крім Finder і Vorssaint.",
            clearSelection: "Очистити вибір")
        case .zhHans: return .init(
            enableLabel: "通过程序坞的 Finder 图标打开其他 App",
            caption: "点按程序坞中的 Finder 图标即可打开所选 App。图标保持不变。",
            appLabel: "App",
            chooseApp: "选择 App…",
            noApp: "无",
            invalidApp: "请选择 Finder 和 Vorssaint 以外的可用 App。",
            clearSelection: "清除选择")
        case .zhTW: return .init(
            enableLabel: "透過 Dock 的 Finder 圖示開啟其他 App",
            caption: "點按 Dock 中的 Finder 圖示即可開啟所選 App。圖示保持不變。",
            appLabel: "App",
            chooseApp: "選擇 App…",
            noApp: "無",
            invalidApp: "請選擇 Finder 和 Vorssaint 以外的可用 App。",
            clearSelection: "清除選擇")
        case .zhHK: return .init(
            enableLabel: "透過 Dock 的 Finder 圖示開啟其他 App",
            caption: "按一下 Dock 中的 Finder 圖示即可開啟所選 App。圖示保持不變。",
            appLabel: "App",
            chooseApp: "選擇 App…",
            noApp: "無",
            invalidApp: "請選擇 Finder 和 Vorssaint 以外可用的 App。",
            clearSelection: "清除選擇")
        }
    }
}
