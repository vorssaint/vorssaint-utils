// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DefaultBrowserFeatureStrings {
    let title: String
    let hubDescription: String
    let current: String
    let none: String
    let makeDefault: String
    let isDefault: String
    let empty: String
    let confirmNote: String
}

extension FeatureStrings {
    static func defaultBrowser(_ language: AppLanguage) -> DefaultBrowserFeatureStrings {
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

extension DefaultBrowserFeatureStrings {
    static let enUS = DefaultBrowserFeatureStrings(title: "Default Browser", hubDescription: "Choose which installed browser opens web links", current: "Opens web links", none: "No default browser", makeDefault: "Make Default", isDefault: "Default", empty: "No browsers found", confirmNote: "macOS asks you to confirm the change.")
    static let ptBR = DefaultBrowserFeatureStrings(title: "Navegador padrão", hubDescription: "Escolha qual navegador instalado abre os links da web", current: "Abre os links da web", none: "Nenhum navegador padrão", makeDefault: "Tornar padrão", isDefault: "Padrão", empty: "Nenhum navegador encontrado", confirmNote: "O macOS pede que você confirme a alteração.")
    static let tr = DefaultBrowserFeatureStrings(title: "Varsayılan Tarayıcı", hubDescription: "Web bağlantılarını hangi yüklü tarayıcının açacağını seçin", current: "Web bağlantılarını açar", none: "Varsayılan tarayıcı yok", makeDefault: "Varsayılan Yap", isDefault: "Varsayılan", empty: "Tarayıcı bulunamadı", confirmNote: "macOS değişikliği onaylamanızı ister.")
    static let ru = DefaultBrowserFeatureStrings(title: "Браузер по умолчанию", hubDescription: "Выберите, какой из установленных браузеров открывает веб-ссылки", current: "Открывает веб-ссылки", none: "Браузер по умолчанию не выбран", makeDefault: "Сделать основным", isDefault: "По умолчанию", empty: "Браузеры не найдены", confirmNote: "macOS попросит подтвердить изменение.")
    static let es = DefaultBrowserFeatureStrings(title: "Navegador predeterminado", hubDescription: "Elige qué navegador instalado abre los enlaces web", current: "Abre los enlaces web", none: "Sin navegador predeterminado", makeDefault: "Usar como predeterminado", isDefault: "Predeterminado", empty: "No se encontraron navegadores", confirmNote: "macOS te pide confirmar el cambio.")
    static let sk = DefaultBrowserFeatureStrings(title: "Predvolený prehliadač", hubDescription: "Vyberte, ktorý nainštalovaný prehliadač otvára webové odkazy", current: "Otvára webové odkazy", none: "Žiadny predvolený prehliadač", makeDefault: "Nastaviť ako predvolený", isDefault: "Predvolený", empty: "Nenašli sa žiadne prehliadače", confirmNote: "macOS vás požiada o potvrdenie zmeny.")
    static let de = DefaultBrowserFeatureStrings(title: "Standardbrowser", hubDescription: "Wähle, welcher installierte Browser Weblinks öffnet", current: "Öffnet Weblinks", none: "Kein Standardbrowser", makeDefault: "Als Standard festlegen", isDefault: "Standard", empty: "Keine Browser gefunden", confirmNote: "macOS fragt nach einer Bestätigung.")
    static let fr = DefaultBrowserFeatureStrings(title: "Navigateur par défaut", hubDescription: "Choisissez le navigateur installé qui ouvre les liens web", current: "Ouvre les liens web", none: "Aucun navigateur par défaut", makeDefault: "Définir par défaut", isDefault: "Par défaut", empty: "Aucun navigateur trouvé", confirmNote: "macOS vous demande de confirmer le changement.")
    static let it = DefaultBrowserFeatureStrings(title: "Browser predefinito", hubDescription: "Scegli quale browser installato apre i link web", current: "Apre i link web", none: "Nessun browser predefinito", makeDefault: "Imposta come predefinito", isDefault: "Predefinito", empty: "Nessun browser trovato", confirmNote: "macOS ti chiede di confermare la modifica.")
    static let ja = DefaultBrowserFeatureStrings(title: "デフォルトのブラウザ", hubDescription: "Webリンクを開くブラウザを、インストール済みのものから選びます", current: "Webリンクを開くアプリ", none: "デフォルトのブラウザがありません", makeDefault: "デフォルトにする", isDefault: "デフォルト", empty: "ブラウザが見つかりません", confirmNote: "変更時にmacOSが確認を求めます。")
    static let ko = DefaultBrowserFeatureStrings(title: "기본 브라우저", hubDescription: "웹 링크를 열 브라우저를 설치된 브라우저 중에서 선택합니다", current: "웹 링크를 여는 앱", none: "기본 브라우저 없음", makeDefault: "기본으로 설정", isDefault: "기본", empty: "브라우저를 찾을 수 없습니다", confirmNote: "macOS에서 변경을 확인하도록 요청합니다.")
    static let uk = DefaultBrowserFeatureStrings(title: "Браузер за замовчуванням", hubDescription: "Виберіть, який зі встановлених браузерів відкриває вебпосилання", current: "Відкриває вебпосилання", none: "Браузер за замовчуванням не вибрано", makeDefault: "Зробити основним", isDefault: "За замовчуванням", empty: "Браузери не знайдено", confirmNote: "macOS попросить підтвердити зміну.")
    static let zhHans = DefaultBrowserFeatureStrings(title: "默认浏览器", hubDescription: "选择由哪个已安装的浏览器打开网页链接", current: "打开网页链接", none: "没有默认浏览器", makeDefault: "设为默认", isDefault: "默认", empty: "未找到浏览器", confirmNote: "macOS 会请你确认此更改。")
    static let zhTW = DefaultBrowserFeatureStrings(title: "預設瀏覽器", hubDescription: "選擇由哪個已安裝的瀏覽器開啟網頁連結", current: "開啟網頁連結", none: "沒有預設瀏覽器", makeDefault: "設為預設", isDefault: "預設", empty: "找不到瀏覽器", confirmNote: "macOS 會請您確認此變更。")
    static let zhHK = DefaultBrowserFeatureStrings(title: "預設瀏覽器", hubDescription: "選擇由哪個已安裝的瀏覽器開啟網頁連結", current: "開啟網頁連結", none: "沒有預設瀏覽器", makeDefault: "設為預設", isDefault: "預設", empty: "找不到瀏覽器", confirmNote: "macOS 會請您確認此變更。")
}
