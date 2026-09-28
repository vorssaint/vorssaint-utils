// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowLayoutIgnoredAppsStrings {
    let sectionTitle: String
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowLayoutIgnoredApps(_ language: AppLanguage) -> WindowLayoutIgnoredAppsStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension WindowLayoutIgnoredAppsStrings {
    static let enUS = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignore apps", listTitle: "Pause in these apps", addButton: "Add an app…", removeButton: "Remove", caption: "Window Layout does not use mouse or keyboard input while one of these apps is focused.")
    static let ptBR = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignorar apps", listTitle: "Pausar nestes apps", addButton: "Adicionar app…", removeButton: "Remover", caption: "O Layout de janelas não usa entrada do mouse ou teclado enquanto um destes apps está em foco.")
    static let tr = WindowLayoutIgnoredAppsStrings(sectionTitle: "Yoksayılacak uygulamalar", listTitle: "Bu uygulamalarda duraklat", addButton: "Uygulama ekle…", removeButton: "Kaldır", caption: "Bu uygulamalardan biri odaktayken Pencere yerleşimi fare veya klavye girdisini kullanmaz.")
    static let ru = WindowLayoutIgnoredAppsStrings(sectionTitle: "Игнорируемые приложения", listTitle: "Приостанавливать в этих приложениях", addButton: "Добавить приложение…", removeButton: "Удалить", caption: "Раскладка окон не использует мышь или клавиатуру, пока одно из этих приложений в фокусе.")
    static let es = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignorar apps", listTitle: "Pausar en estas apps", addButton: "Añadir app…", removeButton: "Quitar", caption: "Diseño de ventanas no usa el ratón ni el teclado mientras una de estas apps tiene el foco.")
    static let sk = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignorované aplikácie", listTitle: "Pozastaviť v týchto aplikáciách", addButton: "Pridať aplikáciu…", removeButton: "Odstrániť", caption: "Rozloženie okien nepoužíva vstup z myši ani klávesnice, kým je jedna z týchto aplikácií v popredí.")
    static let de = WindowLayoutIgnoredAppsStrings(sectionTitle: "Apps ignorieren", listTitle: "In diesen Apps pausieren", addButton: "App hinzufügen…", removeButton: "Entfernen", caption: "Fensterlayout verwendet keine Maus- oder Tastatureingaben, solange eine dieser Apps fokussiert ist.")
    static let fr = WindowLayoutIgnoredAppsStrings(sectionTitle: "Apps à ignorer", listTitle: "Mettre en pause dans ces apps", addButton: "Ajouter une app…", removeButton: "Retirer", caption: "Disposition des fenêtres n’utilise ni la souris ni le clavier tant que l’une de ces apps est active.")
    static let it = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignora app", listTitle: "Sospendi in queste app", addButton: "Aggiungi app…", removeButton: "Rimuovi", caption: "Layout finestre non usa mouse o tastiera finché una di queste app è attiva.")
    static let ja = WindowLayoutIgnoredAppsStrings(sectionTitle: "無視するApp", listTitle: "これらのAppで一時停止", addButton: "Appを追加…", removeButton: "削除", caption: "これらのAppが前面にある間、ウインドウ配置はマウスやキーボード入力を使いません。")
    static let ko = WindowLayoutIgnoredAppsStrings(sectionTitle: "무시할 앱", listTitle: "이 앱에서 일시 정지", addButton: "앱 추가…", removeButton: "제거", caption: "이 앱 중 하나에 포커스가 있을 때 윈도우 정렬은 마우스나 키보드 입력을 사용하지 않습니다.")
    static let uk = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ігноровані програми", listTitle: "Призупиняти в цих програмах", addButton: "Додати програму…", removeButton: "Видалити", caption: "Розкладка вікон не використовує введення з миші чи клавіатури, поки одна з цих програм у фокусі.")
    static let zhHans = WindowLayoutIgnoredAppsStrings(sectionTitle: "忽略的 App", listTitle: "在这些 App 中暂停", addButton: "添加 App…", removeButton: "移除", caption: "当这些 App 之一处于焦点时，窗口布局不会使用鼠标或键盘输入。")
    static let zhTW = WindowLayoutIgnoredAppsStrings(sectionTitle: "忽略的 App", listTitle: "在這些 App 中暫停", addButton: "加入 App…", removeButton: "移除", caption: "當這些 App 之一處於焦點時，視窗排列不會使用滑鼠或鍵盤輸入。")
    static let zhHK = WindowLayoutIgnoredAppsStrings(sectionTitle: "忽略的 App", listTitle: "在這些 App 中暫停", addButton: "加入 App…", removeButton: "移除", caption: "當這些 App 之一處於焦點時，視窗排列不會使用滑鼠或鍵盤輸入。")
}
