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
    let nextBrowser: String
    let inRotation: String
    let rotationCaption: String
    let panelCaption: String
    let islandNotice: String
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
    static let enUS = DefaultBrowserFeatureStrings(title: "Default Browser", hubDescription: "Choose which installed browser opens web links", current: "Opens web links", none: "No default browser", makeDefault: "Make Default", isDefault: "Default", empty: "No browsers found", confirmNote: "macOS asks you to confirm the change.", nextBrowser: "Next Default Browser", inRotation: "Include in shortcut", rotationCaption: "The shortcut makes the next checked browser the default. With none checked, it goes through all of them. macOS asks to confirm each change.", panelCaption: "Choose which browser opens links", islandNotice: "Show the switch in the Dynamic Island")
    static let ptBR = DefaultBrowserFeatureStrings(title: "Navegador padrão", hubDescription: "Escolha qual navegador instalado abre os links da web", current: "Abre os links da web", none: "Nenhum navegador padrão", makeDefault: "Tornar padrão", isDefault: "Padrão", empty: "Nenhum navegador encontrado", confirmNote: "O macOS pede que você confirme a alteração.", nextBrowser: "Próximo navegador padrão", inRotation: "Incluir no atalho", rotationCaption: "O atalho torna padrão o próximo navegador marcado. Sem nenhum marcado, passa por todos. O macOS pede confirmação a cada mudança.", panelCaption: "Escolha qual navegador abre os links", islandNotice: "Mostrar a troca na Dynamic Island")
    static let tr = DefaultBrowserFeatureStrings(title: "Varsayılan Tarayıcı", hubDescription: "Web bağlantılarını hangi yüklü tarayıcının açacağını seçin", current: "Web bağlantılarını açar", none: "Varsayılan tarayıcı yok", makeDefault: "Varsayılan Yap", isDefault: "Varsayılan", empty: "Tarayıcı bulunamadı", confirmNote: "macOS değişikliği onaylamanızı ister.", nextBrowser: "Sonraki Varsayılan Tarayıcı", inRotation: "Kısayola dahil et", rotationCaption: "Kısayol, işaretli sonraki tarayıcıyı varsayılan yapar. Hiçbiri işaretli değilse hepsini sırayla dolaşır. macOS her değişikliği onaylamanızı ister.", panelCaption: "Bağlantıları hangi tarayıcının açacağını seçin", islandNotice: "Geçişi Dynamic Island’da göster")
    static let ru = DefaultBrowserFeatureStrings(title: "Браузер по умолчанию", hubDescription: "Выберите, какой из установленных браузеров открывает веб-ссылки", current: "Открывает веб-ссылки", none: "Браузер по умолчанию не выбран", makeDefault: "Сделать основным", isDefault: "По умолчанию", empty: "Браузеры не найдены", confirmNote: "macOS попросит подтвердить изменение.", nextBrowser: "Следующий браузер по умолчанию", inRotation: "Включить в сочетание клавиш", rotationCaption: "Сочетание клавиш делает основным следующий отмеченный браузер. Если ничего не отмечено, перебираются все. macOS просит подтвердить каждое изменение.", panelCaption: "Выберите, какой браузер открывает ссылки", islandNotice: "Показывать смену в Dynamic Island")
    static let es = DefaultBrowserFeatureStrings(title: "Navegador predeterminado", hubDescription: "Elige qué navegador instalado abre los enlaces web", current: "Abre los enlaces web", none: "Sin navegador predeterminado", makeDefault: "Usar como predeterminado", isDefault: "Predeterminado", empty: "No se encontraron navegadores", confirmNote: "macOS te pide confirmar el cambio.", nextBrowser: "Siguiente navegador predeterminado", inRotation: "Incluir en el atajo", rotationCaption: "El atajo hace predeterminado el siguiente navegador marcado. Si no hay ninguno marcado, recorre todos. macOS pide confirmar cada cambio.", panelCaption: "Elige qué navegador abre los enlaces", islandNotice: "Mostrar el cambio en el Dynamic Island")
    static let sk = DefaultBrowserFeatureStrings(title: "Predvolený prehliadač", hubDescription: "Vyberte, ktorý nainštalovaný prehliadač otvára webové odkazy", current: "Otvára webové odkazy", none: "Žiadny predvolený prehliadač", makeDefault: "Nastaviť ako predvolený", isDefault: "Predvolený", empty: "Nenašli sa žiadne prehliadače", confirmNote: "macOS vás požiada o potvrdenie zmeny.", nextBrowser: "Ďalší predvolený prehliadač", inRotation: "Zahrnúť do skratky", rotationCaption: "Skratka nastaví ako predvolený ďalší označený prehliadač. Ak nie je označený žiadny, prechádza všetkými. macOS žiada potvrdiť každú zmenu.", panelCaption: "Vyberte, ktorý prehliadač otvára odkazy", islandNotice: "Zobraziť zmenu v Dynamic Island")
    static let de = DefaultBrowserFeatureStrings(title: "Standardbrowser", hubDescription: "Wähle, welcher installierte Browser Weblinks öffnet", current: "Öffnet Weblinks", none: "Kein Standardbrowser", makeDefault: "Als Standard festlegen", isDefault: "Standard", empty: "Keine Browser gefunden", confirmNote: "macOS fragt nach einer Bestätigung.", nextBrowser: "Nächster Standardbrowser", inRotation: "Im Kurzbefehl verwenden", rotationCaption: "Der Kurzbefehl macht den nächsten markierten Browser zum Standard. Ist keiner markiert, wechselt er durch alle. macOS fragt bei jeder Änderung nach einer Bestätigung.", panelCaption: "Wähle, welcher Browser Links öffnet", islandNotice: "Wechsel in der Dynamic Island anzeigen")
    static let fr = DefaultBrowserFeatureStrings(title: "Navigateur par défaut", hubDescription: "Choisissez le navigateur installé qui ouvre les liens web", current: "Ouvre les liens web", none: "Aucun navigateur par défaut", makeDefault: "Définir par défaut", isDefault: "Par défaut", empty: "Aucun navigateur trouvé", confirmNote: "macOS vous demande de confirmer le changement.", nextBrowser: "Navigateur par défaut suivant", inRotation: "Inclure dans le raccourci", rotationCaption: "Le raccourci définit par défaut le navigateur coché suivant. Si aucun n’est coché, il les parcourt tous. macOS demande de confirmer chaque changement.", panelCaption: "Choisissez le navigateur qui ouvre les liens", islandNotice: "Afficher le changement dans le Dynamic Island")
    static let it = DefaultBrowserFeatureStrings(title: "Browser predefinito", hubDescription: "Scegli quale browser installato apre i link web", current: "Apre i link web", none: "Nessun browser predefinito", makeDefault: "Imposta come predefinito", isDefault: "Predefinito", empty: "Nessun browser trovato", confirmNote: "macOS ti chiede di confermare la modifica.", nextBrowser: "Browser predefinito successivo", inRotation: "Includi nella scorciatoia", rotationCaption: "La scorciatoia imposta come predefinito il browser selezionato successivo. Se non ne è selezionato nessuno, li scorre tutti. macOS chiede di confermare ogni modifica.", panelCaption: "Scegli quale browser apre i link", islandNotice: "Mostra il cambio nel Dynamic Island")
    static let ja = DefaultBrowserFeatureStrings(title: "デフォルトのブラウザ", hubDescription: "Webリンクを開くブラウザを、インストール済みのものから選びます", current: "Webリンクを開くアプリ", none: "デフォルトのブラウザがありません", makeDefault: "デフォルトにする", isDefault: "デフォルト", empty: "ブラウザが見つかりません", confirmNote: "変更時にmacOSが確認を求めます。", nextBrowser: "次のデフォルトブラウザ", inRotation: "ショートカットに含める", rotationCaption: "ショートカットで、チェックした次のブラウザをデフォルトにします。チェックがない場合はすべてを順に切り替えます。変更のたびにmacOSが確認を求めます。", panelCaption: "リンクを開くブラウザを選択", islandNotice: "切り替えをDynamic Islandに表示")
    static let ko = DefaultBrowserFeatureStrings(title: "기본 브라우저", hubDescription: "웹 링크를 열 브라우저를 설치된 브라우저 중에서 선택합니다", current: "웹 링크를 여는 앱", none: "기본 브라우저 없음", makeDefault: "기본으로 설정", isDefault: "기본", empty: "브라우저를 찾을 수 없습니다", confirmNote: "macOS에서 변경을 확인하도록 요청합니다.", nextBrowser: "다음 기본 브라우저", inRotation: "단축키에 포함", rotationCaption: "단축키를 누르면 체크한 다음 브라우저가 기본으로 설정됩니다. 체크한 브라우저가 없으면 모든 브라우저를 순서대로 전환합니다. 변경할 때마다 macOS에서 확인을 요청합니다.", panelCaption: "링크를 열 브라우저 선택", islandNotice: "Dynamic Island에 전환 표시")
    static let uk = DefaultBrowserFeatureStrings(title: "Браузер за замовчуванням", hubDescription: "Виберіть, який зі встановлених браузерів відкриває вебпосилання", current: "Відкриває вебпосилання", none: "Браузер за замовчуванням не вибрано", makeDefault: "Зробити основним", isDefault: "За замовчуванням", empty: "Браузери не знайдено", confirmNote: "macOS попросить підтвердити зміну.", nextBrowser: "Наступний браузер за замовчуванням", inRotation: "Додати до сполучення клавіш", rotationCaption: "Сполучення клавіш робить основним наступний позначений браузер. Якщо нічого не позначено, перебираються всі. macOS просить підтвердити кожну зміну.", panelCaption: "Виберіть, який браузер відкриває посилання", islandNotice: "Показувати зміну в Dynamic Island")
    static let zhHans = DefaultBrowserFeatureStrings(title: "默认浏览器", hubDescription: "选择由哪个已安装的浏览器打开网页链接", current: "打开网页链接", none: "没有默认浏览器", makeDefault: "设为默认", isDefault: "默认", empty: "未找到浏览器", confirmNote: "macOS 会请你确认此更改。", nextBrowser: "下一个默认浏览器", inRotation: "包含在快捷键中", rotationCaption: "快捷键会将下一个勾选的浏览器设为默认。未勾选任何浏览器时，会在全部浏览器之间轮换。每次更改 macOS 都会请你确认。", panelCaption: "选择打开链接的浏览器", islandNotice: "在Dynamic Island中显示切换")
    static let zhTW = DefaultBrowserFeatureStrings(title: "預設瀏覽器", hubDescription: "選擇由哪個已安裝的瀏覽器開啟網頁連結", current: "開啟網頁連結", none: "沒有預設瀏覽器", makeDefault: "設為預設", isDefault: "預設", empty: "找不到瀏覽器", confirmNote: "macOS 會請您確認此變更。", nextBrowser: "下一個預設瀏覽器", inRotation: "包含在快速鍵中", rotationCaption: "快速鍵會將下一個勾選的瀏覽器設為預設。未勾選任何瀏覽器時，會在全部瀏覽器之間輪換。每次變更 macOS 都會請您確認。", panelCaption: "選擇開啟連結的瀏覽器", islandNotice: "在Dynamic Island中顯示切換")
    static let zhHK = DefaultBrowserFeatureStrings(title: "預設瀏覽器", hubDescription: "選擇由哪個已安裝的瀏覽器開啟網頁連結", current: "開啟網頁連結", none: "沒有預設瀏覽器", makeDefault: "設為預設", isDefault: "預設", empty: "找不到瀏覽器", confirmNote: "macOS 會請您確認此變更。", nextBrowser: "下一個預設瀏覽器", inRotation: "包含在快速鍵中", rotationCaption: "快速鍵會將下一個已剔選的瀏覽器設為預設。未剔選任何瀏覽器時，會在全部瀏覽器之間輪換。每次變更 macOS 都會請您確認。", panelCaption: "選擇開啟連結的瀏覽器", islandNotice: "在Dynamic Island中顯示切換")
}
